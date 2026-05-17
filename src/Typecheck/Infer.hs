module Typecheck.Infer
  ( infer
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (Reader, asks, local, runReader)
import qualified Data.Map.Strict as Map
import Syntax.AST
import Typecheck.Types

infer :: Expr -> Either TypeError Type
infer expression =
  runReader (runExceptT (inferExpr expression)) emptyTypeEnv

type InferM = ExceptT TypeError (Reader TypeEnv)

inferExpr :: Expr -> InferM Type
inferExpr = \case
  EInt _ ->
    pure TInt
  EBool _ ->
    pure TBool
  EVar name ->
    asks (Map.lookup name) >>= \case
      Just ty -> pure ty
      Nothing -> throwError (UnknownVariable name)
  ELet name rhs body -> do
    rhsType <- inferExpr rhs
    local (Map.insert name rhsType) (inferExpr body)
  EIf cond thenBranch elseBranch -> do
    condType <- inferExpr cond
    expect TBool condType
      `orThrow` ExpectedBoolCondition condType
    thenType <- inferExpr thenBranch
    elseType <- inferExpr elseBranch
    expect thenType elseType
      `orThrow` TypeMismatch thenType elseType
    pure thenType
  EBin op lhs rhs ->
    inferBinOp op lhs rhs
  ELam name argType body -> do
    bodyType <- local (Map.insert name argType) (inferExpr body)
    pure (TFun argType bodyType)
  EApp fn arg -> do
    fnType <- inferExpr fn
    argType <- inferExpr arg
    case fnType of
      TFun expectedArg resultType -> do
        expect expectedArg argType
          `orThrow` TypeMismatch expectedArg argType
        pure resultType
      _ ->
        throwError (ExpectedFunction fnType)

inferBinOp :: BinOp -> Expr -> Expr -> InferM Type
inferBinOp op lhs rhs = do
  lhsType <- inferExpr lhs
  rhsType <- inferExpr rhs
  case op of
    Add -> intBin lhsType rhsType
    Sub -> intBin lhsType rhsType
    Mul -> intBin lhsType rhsType
    Div -> intBin lhsType rhsType
    Lt -> intComparison lhsType rhsType
    Eq -> equality lhsType rhsType
 where
  intBin lhsType rhsType = do
    requireInt lhsType
    requireInt rhsType
    pure TInt
  intComparison lhsType rhsType = do
    requireInt lhsType
    requireInt rhsType
    pure TBool
  requireInt actual =
    expect TInt actual `orThrow` ExpectedIntOperand op actual

equality :: Type -> Type -> InferM Type
equality lhsType rhsType = do
  expect lhsType rhsType
    `orThrow` TypeMismatch lhsType rhsType
  case lhsType of
    TInt -> pure TBool
    TBool -> pure TBool
    TFun _ _ -> throwError (EqualityNotSupported lhsType)

expect :: Type -> Type -> Bool
expect =
  (==)

orThrow :: Bool -> TypeError -> InferM ()
orThrow condition err =
  if condition
    then pure ()
    else throwError err
