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
import Eval.Interpreter (RuntimeError (..))
import IR.ANF
import Runtime.Int
  ( HInt
  , addHInt
  , divHInt
  , eqHInt
  , hintToInteger
  , ltHInt
  , mkHIntLiteral
  , mulHInt
  , renderHInt
  , subHInt
  )
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, renderDoc)

data ANFValue
  = ANFVInt HInt
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
  ACall callee _ ->
    throwError (RuntimeTypeError ("ANF direct call requires top-level program evaluator for " <> renderDoc (prettyName callee)))
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
    case mkHIntLiteral n of
      Right value -> pure (ANFVInt value)
      Left err -> throwError (RuntimeIntError err)
  ABool b ->
    pure (ANFVBool b)

evalPrim :: BinOp -> ANFValue -> ANFValue -> EvalM ANFValue
evalPrim op lhs rhs =
  case (op, lhs, rhs) of
    (Add, ANFVInt a, ANFVInt b) -> checkedIntValue (addHInt a b)
    (Sub, ANFVInt a, ANFVInt b) -> checkedIntValue (subHInt a b)
    (Mul, ANFVInt a, ANFVInt b) -> checkedIntValue (mulHInt a b)
    (Div, ANFVInt _, ANFVInt b)
      | hintToInteger b == 0 -> throwError DivisionByZero
    (Div, ANFVInt a, ANFVInt b) -> checkedIntValue (divHInt a b)
    (Lt, ANFVInt a, ANFVInt b) -> pure (ANFVBool (ltHInt a b))
    (Eq, ANFVInt a, ANFVInt b) -> pure (ANFVBool (eqHInt a b))
    (Eq, ANFVBool a, ANFVBool b) -> pure (ANFVBool (a == b))
    _ ->
      throwError $
        RuntimeTypeError
          ("invalid operands for " <> renderDoc (prettyBinOp op))
 where
  checkedIntValue =
    \case
      Right value -> pure (ANFVInt value)
      Left err -> throwError (RuntimeIntError err)

renderANFValue :: ANFValue -> Text
renderANFValue = \case
  ANFVInt n -> renderHInt n
  ANFVBool True -> "true"
  ANFVBool False -> "false"
  ANFVClosure {} -> "<function>"
