module Eval.Interpreter
  ( RuntimeError (..)
  , Value (..)
  , eval
  , evalProgram
  , renderRuntimeError
  , renderValue
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (Reader, asks, local, runReader)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Prettyprinter ((<+>))
import Runtime.Int
  ( HInt
  , IntError
  , addHInt
  , divHInt
  , eqHInt
  , hintToInteger
  , ltHInt
  , mkHIntLiteral
  , mulHInt
  , renderHInt
  , renderIntError
  , subHInt
  )
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, renderDoc)

data Value
  = VInt HInt
  | VBool Bool
  | VClosure Env Name Expr
  deriving stock (Show, Eq)

type Env = Map.Map Name Value

data RuntimeError
  = RuntimeUnknownVariable Name
  | RuntimeTypeError Text
  | DivisionByZero
  | RuntimeIntError IntError
  deriving stock (Show, Eq)

eval :: Expr -> Either RuntimeError Value
eval expression =
  runReader (runExceptT (evalExpr expression)) Map.empty

evalProgram :: Program -> Either RuntimeError Value
evalProgram program =
  runReader (runExceptT (evalProgramM program)) Map.empty

type EvalM = ExceptT RuntimeError (Reader Env)

evalProgramM :: Program -> EvalM Value
evalProgramM program = do
  env <- buildTopEnv Map.empty (programDefs program)
  local (const env) (evalExpr (programMain program))

buildTopEnv :: Env -> [TopDef] -> EvalM Env
buildTopEnv env = \case
  [] ->
    pure env
  def : rest -> do
    value <- local (const env) (evalExpr (topDefAsExpr def))
    buildTopEnv (Map.insert (topDefName def) value env) rest

topDefAsExpr :: TopDef -> Expr
topDefAsExpr def =
  foldr (\(Param name ty) body -> ELam name ty body) (topDefBody def) (topDefParams def)

evalExpr :: Expr -> EvalM Value
evalExpr = \case
  EInt n ->
    case mkHIntLiteral n of
      Right value -> pure (VInt value)
      Left err -> throwError (RuntimeIntError err)
  EBool b ->
    pure (VBool b)
  EVar name ->
    asks (Map.lookup name) >>= \case
      Just value -> pure value
      Nothing -> throwError (RuntimeUnknownVariable name)
  ELet name rhs body -> do
    value <- evalExpr rhs
    local (Map.insert name value) (evalExpr body)
  EIf cond thenBranch elseBranch -> do
    evalExpr cond >>= \case
      VBool True -> evalExpr thenBranch
      VBool False -> evalExpr elseBranch
      other -> throwError (RuntimeTypeError ("if condition must be Bool, got " <> renderValue other))
  EBin op lhs rhs ->
    evalBinOp op lhs rhs
  ELam name _ body -> do
    env <- asks id
    pure (VClosure env name body)
  EApp fn arg -> do
    fnValue <- evalExpr fn
    argValue <- evalExpr arg
    case fnValue of
      VClosure closureEnv name body ->
        local (const (Map.insert name argValue closureEnv)) (evalExpr body)
      other ->
        throwError (RuntimeTypeError ("expected a function, got " <> renderValue other))

evalBinOp :: BinOp -> Expr -> Expr -> EvalM Value
evalBinOp op lhs rhs = do
  lhsValue <- evalExpr lhs
  rhsValue <- evalExpr rhs
  case (op, lhsValue, rhsValue) of
    (Add, VInt a, VInt b) -> checkedIntValue (addHInt a b)
    (Sub, VInt a, VInt b) -> checkedIntValue (subHInt a b)
    (Mul, VInt a, VInt b) -> checkedIntValue (mulHInt a b)
    (Div, VInt _, VInt b)
      | hintToInteger b == 0 -> throwError DivisionByZero
    (Div, VInt a, VInt b) -> checkedIntValue (divHInt a b)
    (Lt, VInt a, VInt b) -> pure (VBool (ltHInt a b))
    (Eq, VInt a, VInt b) -> pure (VBool (eqHInt a b))
    (Eq, VBool a, VBool b) -> pure (VBool (a == b))
    _ ->
      throwError $
        RuntimeTypeError
          ("invalid operands for " <> renderDoc (prettyBinOp op))
 where
  checkedIntValue =
    \case
      Right value -> pure (VInt value)
      Left err -> throwError (RuntimeIntError err)

renderValue :: Value -> Text
renderValue = \case
  VInt n -> renderHInt n
  VBool True -> "true"
  VBool False -> "false"
  VClosure {} -> "<function>"

renderRuntimeError :: RuntimeError -> Text
renderRuntimeError = \case
  RuntimeUnknownVariable name ->
    renderDoc ("unknown variable:" <+> prettyName name)
  RuntimeTypeError message ->
    message
  DivisionByZero ->
    "division by zero"
  RuntimeIntError err ->
    renderIntError err
