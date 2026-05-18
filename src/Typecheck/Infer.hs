module Typecheck.Infer
  ( elaborateLocated
  , elaborateLocatedProgram
  , elaborateLocatedWithEnv
  , infer
  , inferLocated
  , inferLocatedProgram
  , inferLocatedWithEnv
  , inferProgram
  , inferWithEnv
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (Reader, asks, local, runReader)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Runtime.Int (mkHIntLiteral)
import Syntax.AST
import Syntax.Located
import qualified Typecheck.Principal as Principal
import Typecheck.Types

infer :: Expr -> Either TypeError Type
infer expression =
  runReader (runExceptT (inferExpr expression)) emptyTypeEnv

inferWithEnv :: TypeEnv -> Expr -> Either TypeError Type
inferWithEnv env expression =
  runReader (runExceptT (inferExpr expression)) env

inferLocated :: LocatedExpr -> Either LocatedTypeError Type
inferLocated expression =
  fst <$> Principal.elaborateLocated expression

inferLocatedWithEnv :: TypeEnv -> LocatedExpr -> Either LocatedTypeError Type
inferLocatedWithEnv env expression =
  fst <$> Principal.elaborateLocatedWithEnv env expression

inferProgram :: Program -> Either TypeError Type
inferProgram program =
  runReader (runExceptT (inferProgramM program)) emptyTypeEnv

inferLocatedProgram :: LocatedProgram -> Either LocatedTypeError Type
inferLocatedProgram program =
  fst <$> Principal.elaborateLocatedProgram program

elaborateLocated :: LocatedExpr -> Either LocatedTypeError (Type, LocatedExpr)
elaborateLocated =
  Principal.elaborateLocated

elaborateLocatedWithEnv :: TypeEnv -> LocatedExpr -> Either LocatedTypeError (Type, LocatedExpr)
elaborateLocatedWithEnv =
  Principal.elaborateLocatedWithEnv

elaborateLocatedProgram :: LocatedProgram -> Either LocatedTypeError (Type, LocatedProgram)
elaborateLocatedProgram =
  Principal.elaborateLocatedProgram

type InferM = ExceptT TypeError (Reader TypeEnv)

inferExpr :: Expr -> InferM Type
inferExpr = \case
  EInt n -> do
    case mkHIntLiteral n of
      Right _ -> pure TInt
      Left _ -> throwError (IntLiteralOutOfRange n)
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

inferProgramM :: Program -> InferM Type
inferProgramM program = do
  env <- inferTopDefs emptyTypeEnv (programDefs program)
  local (const env) (inferExpr (programMain program))

inferTopDefs :: TypeEnv -> [TopDef] -> InferM TypeEnv
inferTopDefs env = \case
  [] ->
    pure env
  def : rest -> do
    if topDefName def `Map.member` env
      then throwError (DuplicateTopLevelName (topDefName def))
      else pure ()
    validateTopDefTypes (topDefName def) (map paramType (topDefParams def)) (topDefReturnType def)
    checkDuplicateParams (map paramName (topDefParams def))
    let paramEnv = Map.fromList [(paramName param, paramType param) | param <- topDefParams def]
    bodyType <- local (const (paramEnv <> env)) (inferExpr (topDefBody def))
    expect (topDefReturnType def) bodyType
      `orThrow` TypeMismatch (topDefReturnType def) bodyType
    inferTopDefs (Map.insert (topDefName def) (topDefType def) env) rest

validateTopDefTypes :: Name -> [Type] -> Type -> InferM ()
validateTopDefTypes name paramTypes returnType =
  mapM_ rejectFunctionType (paramTypes <> [returnType])
 where
  rejectFunctionType ty =
    case ty of
      TFun {} -> throwError (TopLevelFunctionTypeUnsupported name ty)
      TInt -> pure ()
      TBool -> pure ()

checkDuplicateParams :: [Name] -> InferM ()
checkDuplicateParams =
  go Set.empty
 where
  go _ [] =
    pure ()
  go seen (name : rest)
    | name `Set.member` seen = throwError (DuplicateParameter name)
    | otherwise = go (Set.insert name seen) rest

topDefType :: TopDef -> Type
topDefType def =
  foldr TFun (topDefReturnType def) (map paramType (topDefParams def))
