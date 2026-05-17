module Eval.ANFInterpreter
  ( ANFValue (..)
  , evalANF
  , renderANFValue
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (Reader, asks, local, runReader)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Eval.Interpreter (RuntimeError (..))
import IR.ANF
import Syntax.AST
import Syntax.Pretty (prettyBinOp, renderDoc)

data ANFValue
  = ANFVInt Integer
  | ANFVBool Bool
  | ANFVClosure Env Name AExpr
  deriving stock (Show, Eq)

type Env = Map.Map Name ANFValue

evalANF :: AExpr -> Either RuntimeError ANFValue
evalANF expression =
  runReader (runExceptT (evalExpr expression)) Map.empty

type EvalM = ExceptT RuntimeError (Reader Env)

evalExpr :: AExpr -> EvalM ANFValue
evalExpr = \case
  AAtom atom ->
    evalAtom atom
  APrim op lhs rhs -> do
    lhsValue <- evalAtom lhs
    rhsValue <- evalAtom rhs
    evalPrim op lhsValue rhsValue
  AIf cond thenBranch elseBranch ->
    evalAtom cond >>= \case
      ANFVBool True -> evalExpr thenBranch
      ANFVBool False -> evalExpr elseBranch
      other ->
        throwError $
          RuntimeTypeError ("if condition must be Bool, got " <> renderANFValue other)
  ALam name _ body -> do
    env <- asks id
    pure (ANFVClosure env name body)
  AApp fn arg -> do
    fnValue <- evalAtom fn
    argValue <- evalAtom arg
    case fnValue of
      ANFVClosure closureEnv name body ->
        local (const (Map.insert name argValue closureEnv)) (evalExpr body)
      other ->
        throwError (RuntimeTypeError ("expected a function, got " <> renderANFValue other))
  ALet name rhs body -> do
    value <- evalExpr rhs
    local (Map.insert name value) (evalExpr body)

evalAtom :: Atom -> EvalM ANFValue
evalAtom = \case
  AVar name ->
    asks (Map.lookup name) >>= \case
      Just value -> pure value
      Nothing -> throwError (RuntimeUnknownVariable name)
  AInt n ->
    pure (ANFVInt n)
  ABool b ->
    pure (ANFVBool b)

evalPrim :: BinOp -> ANFValue -> ANFValue -> EvalM ANFValue
evalPrim op lhs rhs =
  case (op, lhs, rhs) of
    (Add, ANFVInt a, ANFVInt b) -> pure (ANFVInt (a + b))
    (Sub, ANFVInt a, ANFVInt b) -> pure (ANFVInt (a - b))
    (Mul, ANFVInt a, ANFVInt b) -> pure (ANFVInt (a * b))
    (Div, ANFVInt _, ANFVInt 0) -> throwError DivisionByZero
    (Div, ANFVInt a, ANFVInt b) -> pure (ANFVInt (a `div` b))
    (Lt, ANFVInt a, ANFVInt b) -> pure (ANFVBool (a < b))
    (Eq, ANFVInt a, ANFVInt b) -> pure (ANFVBool (a == b))
    (Eq, ANFVBool a, ANFVBool b) -> pure (ANFVBool (a == b))
    _ ->
      throwError $
        RuntimeTypeError
          ("invalid operands for " <> renderDoc (prettyBinOp op))

renderANFValue :: ANFValue -> Text
renderANFValue = \case
  ANFVInt n -> Text.pack (show n)
  ANFVBool True -> "true"
  ANFVBool False -> "false"
  ANFVClosure {} -> "<function>"
