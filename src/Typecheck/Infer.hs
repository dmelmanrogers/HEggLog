module Typecheck.Infer
  ( infer
  , inferLocated
  , inferLocatedProgram
  , inferProgram
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.Reader (Reader, asks, local, runReader)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Runtime.Int (mkHIntLiteral)
import Syntax.AST
import Syntax.Located
import Syntax.Span (SourceSpan)
import Typecheck.Types

infer :: Expr -> Either TypeError Type
infer expression =
  runReader (runExceptT (inferExpr expression)) emptyTypeEnv

inferLocated :: LocatedExpr -> Either LocatedTypeError Type
inferLocated expression =
  runReader (runExceptT (inferLocatedExpr expression)) emptyTypeEnv

inferProgram :: Program -> Either TypeError Type
inferProgram program =
  runReader (runExceptT (inferProgramM program)) emptyTypeEnv

inferLocatedProgram :: LocatedProgram -> Either LocatedTypeError Type
inferLocatedProgram program =
  runReader (runExceptT (inferLocatedProgramM program)) emptyTypeEnv

type InferM = ExceptT TypeError (Reader TypeEnv)

type LocatedInferM = ExceptT LocatedTypeError (Reader TypeEnv)

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

inferLocatedExpr :: LocatedExpr -> LocatedInferM Type
inferLocatedExpr (LocatedExpr sourceRange node) =
  case node of
    LInt n -> do
      case mkHIntLiteral n of
        Right _ -> pure TInt
        Left _ -> throwLocated sourceRange (IntLiteralOutOfRange n)
    LBool _ ->
      pure TBool
    LVar name ->
      asks (Map.lookup name) >>= \case
        Just ty -> pure ty
        Nothing -> throwLocated sourceRange (UnknownVariable name)
    LLet name rhs body -> do
      rhsType <- inferLocatedExpr rhs
      local (Map.insert name rhsType) (inferLocatedExpr body)
    LIf cond thenBranch elseBranch -> do
      condType <- inferLocatedExpr cond
      expect TBool condType
        `orThrowLocated` (locatedExprSpan cond, ExpectedBoolCondition condType)
      thenType <- inferLocatedExpr thenBranch
      elseType <- inferLocatedExpr elseBranch
      expect thenType elseType
        `orThrowLocated` (sourceRange, TypeMismatch thenType elseType)
      pure thenType
    LBin op lhs rhs ->
      inferLocatedBinOp sourceRange op lhs rhs
    LLam name argType body -> do
      bodyType <- local (Map.insert name argType) (inferLocatedExpr body)
      pure (TFun argType bodyType)
    LApp fn arg -> do
      fnType <- inferLocatedExpr fn
      argType <- inferLocatedExpr arg
      case fnType of
        TFun expectedArg resultType -> do
          expect expectedArg argType
            `orThrowLocated` (locatedExprSpan arg, TypeMismatch expectedArg argType)
          pure resultType
        _ ->
          throwLocated (locatedExprSpan fn) (ExpectedFunction fnType)

inferLocatedBinOp :: SourceSpan -> BinOp -> LocatedExpr -> LocatedExpr -> LocatedInferM Type
inferLocatedBinOp sourceRange op lhs rhs = do
  lhsType <- inferLocatedExpr lhs
  rhsType <- inferLocatedExpr rhs
  case op of
    Add -> intBin lhsType rhsType
    Sub -> intBin lhsType rhsType
    Mul -> intBin lhsType rhsType
    Div -> intBin lhsType rhsType
    Lt -> intComparison lhsType rhsType
    Eq -> locatedEquality sourceRange lhsType rhsType
 where
  intBin lhsType rhsType = do
    requireInt (locatedExprSpan lhs) lhsType
    requireInt (locatedExprSpan rhs) rhsType
    pure TInt
  intComparison lhsType rhsType = do
    requireInt (locatedExprSpan lhs) lhsType
    requireInt (locatedExprSpan rhs) rhsType
    pure TBool
  requireInt operandSpan actual =
    expect TInt actual
      `orThrowLocated` (operandSpan, ExpectedIntOperand op actual)

locatedEquality :: SourceSpan -> Type -> Type -> LocatedInferM Type
locatedEquality sourceRange lhsType rhsType = do
  expect lhsType rhsType
    `orThrowLocated` (sourceRange, TypeMismatch lhsType rhsType)
  case lhsType of
    TInt -> pure TBool
    TBool -> pure TBool
    TFun _ _ -> throwLocated sourceRange (EqualityNotSupported lhsType)

orThrowLocated :: Bool -> (SourceSpan, TypeError) -> LocatedInferM ()
orThrowLocated condition (sourceRange, err) =
  if condition
    then pure ()
    else throwLocated sourceRange err

throwLocated :: SourceSpan -> TypeError -> LocatedInferM a
throwLocated sourceRange err =
  throwError (LocatedTypeError sourceRange err)

inferLocatedProgramM :: LocatedProgram -> LocatedInferM Type
inferLocatedProgramM program = do
  env <- inferLocatedTopDefs emptyTypeEnv (locatedProgramDefs program)
  local (const env) (inferLocatedExpr (locatedProgramMain program))

inferLocatedTopDefs :: TypeEnv -> [LocatedTopDef] -> LocatedInferM TypeEnv
inferLocatedTopDefs env = \case
  [] ->
    pure env
  def : rest -> do
    if locatedTopDefName def `Map.member` env
      then throwLocated (locatedTopDefSpan def) (DuplicateTopLevelName (locatedTopDefName def))
      else pure ()
    validateLocatedTopDefTypes def
    checkDuplicateLocatedParams (locatedTopDefParams def)
    let params = [param | LocatedParam _ param <- locatedTopDefParams def]
        paramEnv = Map.fromList [(paramName param, paramType param) | param <- params]
    bodyType <- local (const (paramEnv <> env)) (inferLocatedExpr (locatedTopDefBody def))
    expect (locatedTopDefReturnType def) bodyType
      `orThrowLocated` (locatedTopDefSpan def, TypeMismatch (locatedTopDefReturnType def) bodyType)
    inferLocatedTopDefs (Map.insert (locatedTopDefName def) (locatedTopDefType def) env) rest

validateLocatedTopDefTypes :: LocatedTopDef -> LocatedInferM ()
validateLocatedTopDefTypes def = do
  mapM_ rejectParam (locatedTopDefParams def)
  rejectReturn (locatedTopDefReturnType def)
 where
  rejectParam (LocatedParam sourceRange param) =
    case paramType param of
      TFun {} -> throwLocated sourceRange (TopLevelFunctionTypeUnsupported (locatedTopDefName def) (paramType param))
      TInt -> pure ()
      TBool -> pure ()
  rejectReturn ty =
    case ty of
      TFun {} -> throwLocated (locatedTopDefSpan def) (TopLevelFunctionTypeUnsupported (locatedTopDefName def) ty)
      TInt -> pure ()
      TBool -> pure ()

checkDuplicateLocatedParams :: [LocatedParam] -> LocatedInferM ()
checkDuplicateLocatedParams =
  go Set.empty
 where
  go _ [] =
    pure ()
  go seen (LocatedParam sourceRange param : rest)
    | paramName param `Set.member` seen = throwLocated sourceRange (DuplicateParameter (paramName param))
    | otherwise = go (Set.insert (paramName param) seen) rest

locatedTopDefType :: LocatedTopDef -> Type
locatedTopDefType def =
  foldr TFun (locatedTopDefReturnType def) [paramType param | LocatedParam _ param <- locatedTopDefParams def]
