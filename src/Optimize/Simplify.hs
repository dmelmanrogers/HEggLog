module Optimize.Simplify
  ( AppliedRewrite (..)
  , SimplifyError (..)
  , SimplifyResult (..)
  , defaultRewriteRules
  , renderAppliedRewrites
  , renderSimplifyError
  , simplifyFixpoint
  , simplifyOnePass
  )
where

import Analysis.Facts (Fact)
import Analysis.InferFacts (inferFacts)
import Data.Text (Text)
import qualified Data.Text as Text
import IR.ANF
import IR.ANF.Validate
import Optimize.Rewrite
import Runtime.Int (addHInt, hintToInteger, mkHIntLiteral, mulHInt, subHInt)
import Syntax.AST

data AppliedRewrite = AppliedRewrite
  { appliedRuleName :: Text
  , appliedExplanation :: Text
  }
  deriving stock (Show, Eq, Ord)

data SimplifyResult = SimplifyResult
  { simplifiedANF :: AExpr
  , appliedRewrites :: [AppliedRewrite]
  }
  deriving stock (Show, Eq, Ord)

data SimplifyError
  = SimplifyInputInvalid ANFValidationError
  | SimplifyOutputInvalid ANFValidationError
  | SimplifyRewriteFailed RewriteDiagnostic
  | SimplifyFixpointDidNotConverge Int
  deriving stock (Show, Eq, Ord)

-- This optimizer is deliberately replaceable: it runs fact-aware local rewrites
-- over ANF today, while preserving the same condition-checking contract a
-- future e-graph or egglog backend should use.
simplifyOnePass :: AExpr -> Either SimplifyError SimplifyResult
simplifyOnePass expression = do
  mapValidationError SimplifyInputInvalid (validateANF expression)
  let facts = inferFacts expression
  (optimized, rewrites) <- simplifyExpr facts expression
  mapValidationError SimplifyOutputInvalid (validateANF optimized)
  pure SimplifyResult {simplifiedANF = optimized, appliedRewrites = rewrites}

simplifyFixpoint :: AExpr -> Either SimplifyError SimplifyResult
simplifyFixpoint =
  loop 0 []
 where
  loop iteration trace expression
    | iteration > maxIterations =
        Left (SimplifyFixpointDidNotConverge maxIterations)
    | otherwise = do
        SimplifyResult next stepTrace <- simplifyOnePass expression
        let totalTrace = trace <> stepTrace
        if next == expression
          then pure SimplifyResult {simplifiedANF = next, appliedRewrites = totalTrace}
          else loop (iteration + 1) totalTrace next

  maxIterations = 64

simplifyExpr :: [Fact] -> AExpr -> Either SimplifyError (AExpr, [AppliedRewrite])
simplifyExpr facts expression =
  case rewriteCurrent facts expression of
    Just rewritten ->
      rewritten
    Nothing ->
      simplifyChildren facts expression

simplifyChildren :: [Fact] -> AExpr -> Either SimplifyError (AExpr, [AppliedRewrite])
simplifyChildren facts = \case
  AAtom atom ->
    pure (AAtom atom, [])
  APrim op lhs rhs ->
    pure (APrim op lhs rhs, [])
  AIf cond thenExpr elseExpr -> do
    (thenOptimized, thenTrace) <- simplifyExpr facts thenExpr
    (elseOptimized, elseTrace) <- simplifyExpr facts elseExpr
    pure (AIf cond thenOptimized elseOptimized, thenTrace <> elseTrace)
  ALam name argType body -> do
    (bodyOptimized, trace) <- simplifyExpr facts body
    pure (ALam name argType bodyOptimized, trace)
  AApp fn arg ->
    pure (AApp fn arg, [])
  ALet name rhs body -> do
    (rhsOptimized, rhsTrace) <- simplifyExpr facts rhs
    (bodyOptimized, bodyTrace) <- simplifyExpr facts body
    pure (ALet name rhsOptimized bodyOptimized, rhsTrace <> bodyTrace)

rewriteCurrent :: [Fact] -> AExpr -> Maybe (Either SimplifyError (AExpr, [AppliedRewrite]))
rewriteCurrent facts expression =
  firstSuccessful (map tryPatternRule defaultRewriteRules <> [tryConstantFold])
 where
  tryPatternRule rule =
    case matchRewriteRule rule expression of
      Nothing ->
        Nothing
      Just binding ->
        Just $ do
          mapRewriteError (authorizeRewrite facts binding rule)
          maybeReplacement <- mapRewriteError (instantiateRewriteRhs rule binding)
          case maybeReplacement of
            Just replacement ->
              pure (replacement, [applied rule])
            Nothing ->
              Left (SimplifyRewriteFailed (PatternVariableUnbound (RewriteVar (rewriteName rule))))

  tryConstantFold =
    case expression of
      APrim op (AInt lhs) (AInt rhs) ->
        case foldIntegerPrim op lhs rhs of
          Just replacement ->
            let rule = constantFoldRule op
             in Just $ do
                  mapRewriteError (authorizeRewrite facts emptyPatternBinding rule)
                  pure (replacement, [applied rule])
          Nothing ->
            Nothing
      _ ->
        Nothing

firstSuccessful :: [Maybe a] -> Maybe a
firstSuccessful = \case
  [] -> Nothing
  Nothing : rest -> firstSuccessful rest
  Just value : _ -> Just value

defaultRewriteRules :: [RewriteRule]
defaultRewriteRules =
  [ addRightZero
  , addLeftZero
  , mulRightOne
  , mulLeftOne
  , mulRightZero
  , mulLeftZero
  , ifTrueRule
  , ifFalseRule
  ]

addRightZero :: RewriteRule
addRightZero =
  binaryIdentityRule "add-right-zero" "x + 0 simplifies to x" Add (PBind x) (PInt 0) (PBind x)

addLeftZero :: RewriteRule
addLeftZero =
  binaryIdentityRule "add-left-zero" "0 + x simplifies to x" Add (PInt 0) (PBind x) (PBind x)

mulRightOne :: RewriteRule
mulRightOne =
  binaryIdentityRule "mul-right-one" "x * 1 simplifies to x" Mul (PBind x) (PInt 1) (PBind x)

mulLeftOne :: RewriteRule
mulLeftOne =
  binaryIdentityRule "mul-left-one" "1 * x simplifies to x" Mul (PInt 1) (PBind x) (PBind x)

mulRightZero :: RewriteRule
mulRightZero =
  binaryIdentityRule "mul-right-zero" "x * 0 simplifies to 0" Mul (PBind x) (PInt 0) (PInt 0)

mulLeftZero :: RewriteRule
mulLeftZero =
  binaryIdentityRule "mul-left-zero" "0 * x simplifies to 0" Mul (PInt 0) (PBind x) (PInt 0)

ifTrueRule :: RewriteRule
ifTrueRule =
  RewriteRule
    { rewriteName = "if-true"
    , rewriteLhs = MatchIf (PBool True) (MatchBind thenVar) (MatchBind elseVar)
    , rewriteRhs = ReplaceWith (MatchBind thenVar)
    , rewriteConditions = []
    , rewriteTypeCheck = TypePreservingByConstruction
    , rewriteExplanation = "if true selects the then branch"
    }

ifFalseRule :: RewriteRule
ifFalseRule =
  RewriteRule
    { rewriteName = "if-false"
    , rewriteLhs = MatchIf (PBool False) (MatchBind thenVar) (MatchBind elseVar)
    , rewriteRhs = ReplaceWith (MatchBind elseVar)
    , rewriteConditions = []
    , rewriteTypeCheck = TypePreservingByConstruction
    , rewriteExplanation = "if false selects the else branch"
    }

binaryIdentityRule :: Text -> Text -> BinOp -> PatternAtom -> PatternAtom -> PatternAtom -> RewriteRule
binaryIdentityRule ruleName explanation op lhs rhs replacement =
  RewriteRule
    { rewriteName = ruleName
    , rewriteLhs = MatchPrim op lhs rhs
    , rewriteRhs = ReplaceWith (MatchAtom replacement)
    , rewriteConditions = []
    , rewriteTypeCheck = TypePreservingByConstruction
    , rewriteExplanation = explanation
    }

constantFoldRule :: BinOp -> RewriteRule
constantFoldRule op =
  RewriteRule
    { rewriteName = "constant-fold-" <> renderOpName op
    , rewriteLhs = MatchPrim op (PBind x) (PBind y)
    , rewriteRhs = ComputedReplacement "integer arithmetic is evaluated at compile time"
    , rewriteConditions = []
    , rewriteTypeCheck = TypePreservingByConstruction
    , rewriteExplanation = "constant integer arithmetic is evaluated at compile time"
    }

foldIntegerPrim :: BinOp -> Integer -> Integer -> Maybe AExpr
foldIntegerPrim op lhs rhs = do
  lhsInt <- either (const Nothing) Just (mkHIntLiteral lhs)
  rhsInt <- either (const Nothing) Just (mkHIntLiteral rhs)
  case op of
    Add -> foldChecked (addHInt lhsInt rhsInt)
    Sub -> foldChecked (subHInt lhsInt rhsInt)
    Mul -> foldChecked (mulHInt lhsInt rhsInt)
    Div -> Nothing
    Eq -> Nothing
    Lt -> Nothing
 where
  foldChecked result =
    AAtom . AInt . hintToInteger <$> either (const Nothing) Just result

renderAppliedRewrites :: [AppliedRewrite] -> Text
renderAppliedRewrites [] =
  "<none>"
renderAppliedRewrites rewrites =
  Text.unlines (map renderAppliedRewrite rewrites)

renderAppliedRewrite :: AppliedRewrite -> Text
renderAppliedRewrite rewrite =
  appliedRuleName rewrite <> ": " <> appliedExplanation rewrite

renderSimplifyError :: SimplifyError -> Text
renderSimplifyError = \case
  SimplifyInputInvalid err ->
    "invalid ANF input: " <> renderANFValidationError err
  SimplifyOutputInvalid err ->
    "optimizer produced invalid ANF: " <> renderANFValidationError err
  SimplifyRewriteFailed diagnostic ->
    "rewrite failed: " <> renderRewriteDiagnostic diagnostic
  SimplifyFixpointDidNotConverge iterationLimit ->
    "simplification did not converge within " <> Text.pack (show iterationLimit) <> " iterations"

renderRewriteDiagnostic :: RewriteDiagnostic -> Text
renderRewriteDiagnostic = \case
  PatternVariableUnbound var ->
    "pattern variable was unbound: " <> unRewriteVar var
  PatternVariableConflict var ->
    "pattern variable matched conflicting values: " <> unRewriteVar var
  ConditionNotSatisfied condition ->
    "rewrite condition was not satisfied: " <> Text.pack (show condition)

mapValidationError :: (ANFValidationError -> SimplifyError) -> Either ANFValidationError a -> Either SimplifyError a
mapValidationError f = \case
  Left err -> Left (f err)
  Right value -> Right value

mapRewriteError :: Either RewriteDiagnostic a -> Either SimplifyError a
mapRewriteError = \case
  Left err -> Left (SimplifyRewriteFailed err)
  Right value -> Right value

applied :: RewriteRule -> AppliedRewrite
applied rule =
  AppliedRewrite
    { appliedRuleName = rewriteName rule
    , appliedExplanation = rewriteExplanation rule
    }

renderOpName :: BinOp -> Text
renderOpName = \case
  Add -> "add"
  Sub -> "sub"
  Mul -> "mul"
  Div -> "div"
  Eq -> "eq"
  Lt -> "lt"

x :: RewriteVar
x =
  RewriteVar "x"

y :: RewriteVar
y =
  RewriteVar "y"

thenVar :: RewriteVar
thenVar =
  RewriteVar "then"

elseVar :: RewriteVar
elseVar =
  RewriteVar "else"
