module Optimize.Rewrite
  ( PatternAtom (..)
  , PatternBinding (..)
  , RewriteCondition (..)
  , RewriteDiagnostic (..)
  , RewritePattern (..)
  , RewriteRhs (..)
  , RewriteRule (..)
  , RewriteTypeCheckHook (..)
  , RewriteVar (..)
  , authorizeRewrite
  , checkRewriteConditions
  , divideSelfNonZero
  , emptyPatternBinding
  , instantiateRewriteRhs
  , matchRewriteRule
  )
where

import Analysis.Facts
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import IR.ANF
import Syntax.AST

newtype RewriteVar = RewriteVar {unRewriteVar :: Text}
  deriving stock (Show, Eq, Ord)

data PatternAtom
  = PBind RewriteVar
  | PName Name
  | PInt Integer
  | PBool Bool
  deriving stock (Show, Eq, Ord)

data RewritePattern
  = MatchBind RewriteVar
  | MatchAtom PatternAtom
  | MatchPrim BinOp PatternAtom PatternAtom
  | MatchIf PatternAtom RewritePattern RewritePattern
  | MatchApp PatternAtom PatternAtom
  deriving stock (Show, Eq, Ord)

data RewriteRhs
  = ReplaceWith RewritePattern
  | ComputedReplacement Text
  deriving stock (Show, Eq, Ord)

data RewriteCondition
  = RequiresType PatternAtom Type
  | RequiresPure PatternAtom
  | RequiresConst PatternAtom ConstValue
  | RequiresNonZero PatternAtom
  deriving stock (Show, Eq, Ord)

data RewriteTypeCheckHook
  = TypePreservingByConstruction
  deriving stock (Show, Eq, Ord)

data RewriteRule = RewriteRule
  { rewriteName :: Text
  , rewriteLhs :: RewritePattern
  , rewriteRhs :: RewriteRhs
  , rewriteConditions :: [RewriteCondition]
  , rewriteTypeCheck :: RewriteTypeCheckHook
  , rewriteExplanation :: Text
  }
  deriving stock (Show, Eq, Ord)

data PatternBinding = PatternBinding
  { atomBindings :: Map.Map RewriteVar Atom
  , exprBindings :: Map.Map RewriteVar AExpr
  }
  deriving stock (Show, Eq, Ord)

data RewriteDiagnostic
  = PatternVariableUnbound RewriteVar
  | PatternVariableConflict RewriteVar
  | ConditionNotSatisfied RewriteCondition
  deriving stock (Show, Eq, Ord)

emptyPatternBinding :: PatternBinding
emptyPatternBinding =
  PatternBinding
    { atomBindings = Map.empty
    , exprBindings = Map.empty
    }

matchRewriteRule :: RewriteRule -> AExpr -> Maybe PatternBinding
matchRewriteRule rule expression =
  matchPattern (rewriteLhs rule) expression emptyPatternBinding

instantiateRewriteRhs :: RewriteRule -> PatternBinding -> Either RewriteDiagnostic (Maybe AExpr)
instantiateRewriteRhs rule binding =
  case rewriteRhs rule of
    ReplaceWith patternRhs ->
      Just <$> instantiatePattern binding patternRhs
    ComputedReplacement _ ->
      Right Nothing

authorizeRewrite :: [Fact] -> PatternBinding -> RewriteRule -> Either RewriteDiagnostic ()
authorizeRewrite facts binding rule = do
  checkRewriteConditions facts binding rule
  checkRewriteTypePreservation rule

checkRewriteConditions :: [Fact] -> PatternBinding -> RewriteRule -> Either RewriteDiagnostic ()
checkRewriteConditions facts binding rule =
  mapM_ checkCondition (rewriteConditions rule)
 where
  checkCondition condition
    | conditionSatisfied facts binding condition = Right ()
    | otherwise = Left (ConditionNotSatisfied condition)

checkRewriteTypePreservation :: RewriteRule -> Either RewriteDiagnostic ()
checkRewriteTypePreservation rule =
  case rewriteTypeCheck rule of
    TypePreservingByConstruction -> Right ()

matchPattern :: RewritePattern -> AExpr -> PatternBinding -> Maybe PatternBinding
matchPattern patternExpr expression binding =
  case (patternExpr, expression) of
    (MatchBind var, _) ->
      bindExpr var expression binding
    (MatchAtom patternAtom, AAtom atom) ->
      matchAtom patternAtom atom binding
    (MatchPrim patternOp lhsPattern rhsPattern, APrim actualOp lhs rhs)
      | patternOp == actualOp ->
          matchAtom lhsPattern lhs binding >>= matchAtom rhsPattern rhs
    (MatchIf condPattern thenPattern elsePattern, AIf cond thenBranch elseBranch) ->
      matchAtom condPattern cond binding
        >>= matchPattern thenPattern thenBranch
        >>= matchPattern elsePattern elseBranch
    (MatchApp fnPattern argPattern, AApp fn arg) ->
      matchAtom fnPattern fn binding >>= matchAtom argPattern arg
    _ ->
      Nothing

matchAtom :: PatternAtom -> Atom -> PatternBinding -> Maybe PatternBinding
matchAtom patternAtom atom binding =
  case patternAtom of
    PBind var ->
      bindAtom var atom binding
    PName name ->
      if atom == AVar name then Just binding else Nothing
    PInt n ->
      if atom == AInt n then Just binding else Nothing
    PBool b ->
      if atom == ABool b then Just binding else Nothing

bindAtom :: RewriteVar -> Atom -> PatternBinding -> Maybe PatternBinding
bindAtom var atom binding =
  case Map.lookup var (atomBindings binding) of
    Just existing
      | existing == atom -> Just binding
      | otherwise -> Nothing
    Nothing ->
      Just binding {atomBindings = Map.insert var atom (atomBindings binding)}

bindExpr :: RewriteVar -> AExpr -> PatternBinding -> Maybe PatternBinding
bindExpr var expression binding =
  case Map.lookup var (exprBindings binding) of
    Just existing
      | existing == expression -> Just binding
      | otherwise -> Nothing
    Nothing ->
      Just binding {exprBindings = Map.insert var expression (exprBindings binding)}

instantiatePattern :: PatternBinding -> RewritePattern -> Either RewriteDiagnostic AExpr
instantiatePattern binding = \case
  MatchBind var ->
    case Map.lookup var (exprBindings binding) of
      Just expression -> Right expression
      Nothing -> Left (PatternVariableUnbound var)
  MatchAtom patternAtom ->
    AAtom <$> instantiateAtom binding patternAtom
  MatchPrim op lhs rhs ->
    APrim op <$> instantiateAtom binding lhs <*> instantiateAtom binding rhs
  MatchIf cond thenBranch elseBranch ->
    AIf
      <$> instantiateAtom binding cond
      <*> instantiatePattern binding thenBranch
      <*> instantiatePattern binding elseBranch
  MatchApp fn arg ->
    AApp <$> instantiateAtom binding fn <*> instantiateAtom binding arg

instantiateAtom :: PatternBinding -> PatternAtom -> Either RewriteDiagnostic Atom
instantiateAtom binding = \case
  PBind var ->
    case Map.lookup var (atomBindings binding) of
      Just atom -> Right atom
      Nothing -> Left (PatternVariableUnbound var)
  PName name ->
    Right (AVar name)
  PInt n ->
    Right (AInt n)
  PBool b ->
    Right (ABool b)

conditionSatisfied :: [Fact] -> PatternBinding -> RewriteCondition -> Bool
conditionSatisfied facts binding = \case
  RequiresType patternAtom expectedType ->
    maybe False (atomHasType facts expectedType) (resolvePatternAtom binding patternAtom)
  RequiresPure patternAtom ->
    maybe False (atomIsPure facts) (resolvePatternAtom binding patternAtom)
  RequiresConst patternAtom expectedValue ->
    maybe False (atomIsConst facts expectedValue) (resolvePatternAtom binding patternAtom)
  RequiresNonZero patternAtom ->
    maybe False (atomIsNonZero facts) (resolvePatternAtom binding patternAtom)

resolvePatternAtom :: PatternBinding -> PatternAtom -> Maybe Atom
resolvePatternAtom binding = \case
  PBind var -> Map.lookup var (atomBindings binding)
  PName name -> Just (AVar name)
  PInt n -> Just (AInt n)
  PBool b -> Just (ABool b)

atomHasType :: [Fact] -> Type -> Atom -> Bool
atomHasType facts expectedType = \case
  AInt _ ->
    expectedType == TInt
  ABool _ ->
    expectedType == TBool
  AVar name ->
    HasType name expectedType `elem` facts

atomIsPure :: [Fact] -> Atom -> Bool
atomIsPure facts = \case
  AInt _ -> True
  ABool _ -> True
  AVar name -> IsPure name `elem` facts

atomIsConst :: [Fact] -> ConstValue -> Atom -> Bool
atomIsConst facts expectedValue atom =
  case (atom, expectedValue) of
    (AInt actual, ConstInt expected) ->
      actual == expected
    (ABool actual, ConstBool expected) ->
      actual == expected
    (AVar name, _) ->
      IsConst name expectedValue `elem` facts
    _ ->
      False

atomIsNonZero :: [Fact] -> Atom -> Bool
atomIsNonZero facts = \case
  AInt n ->
    n /= 0
  ABool _ ->
    False
  AVar name ->
    NonZero name `elem` facts

-- This deliberately remains a described conditional rule, not an enabled
-- simplification. It documents the future EqSat contract: division by self is
-- sound only when a relational fact proves the divisor is nonzero.
divideSelfNonZero :: RewriteRule
divideSelfNonZero =
  let x = PBind (RewriteVar "x")
   in RewriteRule
        { rewriteName = "divide-self-nonzero"
        , rewriteLhs = MatchPrim Div x x
        , rewriteRhs = ReplaceWith (MatchAtom (PInt 1))
        , rewriteConditions = [RequiresNonZero x]
        , rewriteTypeCheck = TypePreservingByConstruction
        , rewriteExplanation = "x / x is 1 only when facts prove x is nonzero"
        }
