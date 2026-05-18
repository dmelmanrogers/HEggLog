module Analysis.InferFacts
  ( inferFacts
  )
where

import Analysis.Facts
import qualified Data.Map.Strict as Map
import IR.ANF
import Syntax.AST
import Typecheck.Types (TypeEnv)

-- egglog-style optimization combines equality reasoning with relational facts.
-- This pass is intentionally conservative: it emits facts for names only when
-- the fact follows from the ANF term and the binder name is unambiguous.
inferFacts :: AExpr -> [Fact]
inferFacts expression =
  snd (inferExpr binderCounts Map.empty expression)
 where
  binderCounts = countBinders expression

inferExpr :: BinderCounts -> TypeEnv -> AExpr -> (Maybe Type, [Fact])
inferExpr binderCounts env = \case
  AAtom atom ->
    (typeOfAtom env atom, [])
  APrim op lhs rhs ->
    (typeOfPrim env op lhs rhs, [])
  AIf cond thenBranch elseBranch ->
    let condType = typeOfAtom env cond
        (thenType, thenFacts) = inferExpr binderCounts env thenBranch
        (elseType, elseFacts) = inferExpr binderCounts env elseBranch
        resultType =
          case (condType, thenType, elseType) of
            (Just TBool, Just lhsType, Just rhsType)
              | lhsType == rhsType -> Just lhsType
            _ -> Nothing
     in (resultType, thenFacts <> elseFacts)
  ALam name argType body ->
    let paramFacts = factsForParameter binderCounts name argType
        (bodyType, bodyFacts) = inferExpr binderCounts (Map.insert name argType env) body
     in (TFun argType <$> bodyType, paramFacts <> bodyFacts)
  AApp fn arg ->
    let resultType =
          case (typeOfAtom env fn, typeOfAtom env arg) of
            (Just (TFun expectedArg result), Just actualArg)
              | expectedArg == actualArg -> Just result
            _ -> Nothing
     in (resultType, [])
  ACall {} ->
    (Nothing, [])
  ALet name rhs body ->
    let (rhsType, rhsFacts) = inferExpr binderCounts env rhs
        boundFacts = factsForBinding binderCounts name rhs rhsType
        bodyEnv =
          case rhsType of
            Just ty -> Map.insert name ty env
            Nothing -> env
        (bodyType, bodyFacts) = inferExpr binderCounts bodyEnv body
     in (bodyType, rhsFacts <> boundFacts <> bodyFacts)

typeOfAtom :: TypeEnv -> Atom -> Maybe Type
typeOfAtom env = \case
  AVar name -> Map.lookup name env
  AInt _ -> Just TInt
  ABool _ -> Just TBool

typeOfPrim :: TypeEnv -> BinOp -> Atom -> Atom -> Maybe Type
typeOfPrim env op lhs rhs =
  case op of
    Add -> intOperands *> Just TInt
    Sub -> intOperands *> Just TInt
    Mul -> intOperands *> Just TInt
    Div -> intOperands *> Just TInt
    Lt -> intOperands *> Just TBool
    Eq ->
      case (typeOfAtom env lhs, typeOfAtom env rhs) of
        (Just TInt, Just TInt) -> Just TBool
        (Just TBool, Just TBool) -> Just TBool
        _ -> Nothing
 where
  intOperands =
    case (typeOfAtom env lhs, typeOfAtom env rhs) of
      (Just TInt, Just TInt) -> Just ()
      _ -> Nothing

factsForParameter :: BinderCounts -> Name -> Type -> [Fact]
factsForParameter binderCounts name ty
  | isUniqueBinder binderCounts name = [HasType name ty]
  | otherwise = []

factsForBinding :: BinderCounts -> Name -> AExpr -> Maybe Type -> [Fact]
factsForBinding binderCounts name rhs rhsType
  | not (isUniqueBinder binderCounts name) = []
  | otherwise =
      typeFacts <> purityFacts <> constFacts <> nonZeroFacts
 where
  typeFacts =
    case rhsType of
      Just ty -> [HasType name ty]
      Nothing -> []
  purityFacts =
    [IsPure name | isPureExpr rhs]
  constFacts =
    case constOfExpr rhs of
      Just value -> [IsConst name value]
      Nothing -> []
  nonZeroFacts =
    case constOfExpr rhs of
      Just (ConstInt n)
        | n /= 0 -> [NonZero name]
      _ -> []

constOfExpr :: AExpr -> Maybe ConstValue
constOfExpr = \case
  AAtom (AInt n) -> Just (ConstInt n)
  AAtom (ABool b) -> Just (ConstBool b)
  AAtom (AVar _) -> Nothing
  APrim {} -> Nothing
  AIf {} -> Nothing
  ALam {} -> Nothing
  AApp {} -> Nothing
  ACall {} -> Nothing
  ALet {} -> Nothing

-- The current language is pure. This fact means "no side effects"; it does not
-- promise totality or rule out runtime errors such as division by zero.
isPureExpr :: AExpr -> Bool
isPureExpr = \case
  AAtom {} -> True
  APrim {} -> True
  AIf _ thenBranch elseBranch ->
    isPureExpr thenBranch && isPureExpr elseBranch
  ALam _ _ body ->
    isPureExpr body
  AApp {} -> True
  ACall {} -> True
  ALet _ rhs body ->
    isPureExpr rhs && isPureExpr body

type BinderCounts = Map.Map Name Int

countBinders :: AExpr -> BinderCounts
countBinders = \case
  AAtom {} ->
    Map.empty
  APrim {} ->
    Map.empty
  AIf _ thenBranch elseBranch ->
    countBinders thenBranch <> countBinders elseBranch
  ALam name _ body ->
    Map.insertWith (+) name 1 (countBinders body)
  AApp {} ->
    Map.empty
  ACall {} ->
    Map.empty
  ALet name rhs body ->
    Map.insertWith (+) name 1 (countBinders rhs <> countBinders body)

isUniqueBinder :: BinderCounts -> Name -> Bool
isUniqueBinder binderCounts name =
  Map.lookup name binderCounts == Just 1
