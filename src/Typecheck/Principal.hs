module Typecheck.Principal
  ( PrincipalType (..)
  , PrincipalTypeError (..)
  , TypeVar (..)
  , TypeScheme (..)
  , principalProgramType
  , principalType
  , renderPrincipalType
  , renderPrincipalTypeError
  , renderTypeScheme
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Runtime.Int (mkHIntLiteral)
import Syntax.AST
import Syntax.Pretty (prettyType, renderDoc)
import Typecheck.Types (TypeError (..), renderTypeError)

newtype TypeVar = TypeVar Int
  deriving stock (Show, Eq, Ord)

data PrincipalType
  = PInt
  | PBool
  | PFun PrincipalType PrincipalType
  | PVar TypeVar
  deriving stock (Show, Eq, Ord)

data TypeScheme = TypeScheme [TypeVar] PrincipalType
  deriving stock (Show, Eq, Ord)

data PrincipalTypeError
  = PrincipalTypeFailure TypeError
  | PrincipalOccursCheck TypeVar PrincipalType
  | PrincipalAmbiguousEquality PrincipalType
  deriving stock (Show, Eq)

data InferState = InferState
  { nextTypeVar :: Int
  }
  deriving stock (Show, Eq)

type Subst = Map.Map TypeVar PrincipalType

type PrincipalEnv = Map.Map Name TypeScheme

type InferM = ExceptT PrincipalTypeError (State InferState)

principalType :: Expr -> Either PrincipalTypeError TypeScheme
principalType expression =
  evalState (runExceptT (inferPrincipal Map.empty expression)) initialState

principalProgramType :: Program -> Either PrincipalTypeError TypeScheme
principalProgramType program =
  evalState (runExceptT (inferProgramPrincipal program)) initialState

initialState :: InferState
initialState =
  InferState {nextTypeVar = 0}

inferProgramPrincipal :: Program -> InferM TypeScheme
inferProgramPrincipal program = do
  env <- inferTopDefs Map.empty (programDefs program)
  inferPrincipal env (programMain program)

inferTopDefs :: PrincipalEnv -> [TopDef] -> InferM PrincipalEnv
inferTopDefs env = \case
  [] ->
    pure env
  def : rest -> do
    if topDefName def `Map.member` env
      then throwTypeError (DuplicateTopLevelName (topDefName def))
      else pure ()
    validateTopDefTypes (topDefName def) (map paramType (topDefParams def)) (topDefReturnType def)
    checkDuplicateParams (map paramName (topDefParams def))
    let paramEnv =
          Map.fromList
            [ (paramName param, TypeScheme [] (fromSyntaxType (paramType param)))
            | param <- topDefParams def
            ]
        returnType = fromSyntaxType (topDefReturnType def)
        bodyEnv = paramEnv <> env
    (_, bodyType) <- infer bodyEnv (topDefBody def)
    _ <- unifyOrTypeError returnType bodyType
    let functionType =
          foldr (PFun . fromSyntaxType . paramType) returnType (topDefParams def)
    inferTopDefs (Map.insert (topDefName def) (TypeScheme [] functionType) env) rest

inferPrincipal :: PrincipalEnv -> Expr -> InferM TypeScheme
inferPrincipal env expression = do
  (subst, ty) <- infer env expression
  pure (generalize (applySubstEnv subst env) (applySubst subst ty))

infer :: PrincipalEnv -> Expr -> InferM (Subst, PrincipalType)
infer env = \case
  EInt n -> do
    case mkHIntLiteral n of
      Right _ -> pure (emptySubst, PInt)
      Left _ -> throwTypeError (IntLiteralOutOfRange n)
  EBool {} ->
    pure (emptySubst, PBool)
  EVar name ->
    case Map.lookup name env of
      Just scheme -> do
        ty <- instantiate scheme
        pure (emptySubst, ty)
      Nothing ->
        throwTypeError (UnknownVariable name)
  ELet name rhs body -> do
    (substRhs, rhsType) <- infer env rhs
    let envAfterRhs = applySubstEnv substRhs env
        rhsScheme = generalize envAfterRhs rhsType
    (substBody, bodyType) <- infer (Map.insert name rhsScheme envAfterRhs) body
    pure (substBody `composeSubst` substRhs, bodyType)
  EIf cond thenBranch elseBranch -> do
    (substCond, condType) <- infer env cond
    substBool <- unifyOrTypeError PBool condType
    let envAfterCond = applySubstEnv (substBool `composeSubst` substCond) env
    (substThen, thenType) <- infer envAfterCond thenBranch
    (substElse, elseType) <- infer (applySubstEnv substThen envAfterCond) elseBranch
    substBranches <- unifyOrTypeError (applySubst substElse thenType) elseType
    pure
      ( substBranches `composeSubst` substElse `composeSubst` substThen `composeSubst` substBool `composeSubst` substCond
      , applySubst substBranches elseType
      )
  EBin op lhs rhs ->
    inferBinOp env op lhs rhs
  ELam name argType body -> do
    let argPrincipalType = fromSyntaxType argType
        envWithArg = Map.insert name (TypeScheme [] argPrincipalType) env
    (substBody, bodyType) <- infer envWithArg body
    pure (substBody, PFun (applySubst substBody argPrincipalType) bodyType)
  EApp fn arg -> do
    (substFn, fnType) <- infer env fn
    (substArg, argType) <- infer (applySubstEnv substFn env) arg
    resultType <- freshTypeVar
    substApp <- unifyOrTypeError (applySubst substArg fnType) (PFun argType resultType)
    pure
      ( substApp `composeSubst` substArg `composeSubst` substFn
      , applySubst substApp resultType
      )

inferBinOp :: PrincipalEnv -> BinOp -> Expr -> Expr -> InferM (Subst, PrincipalType)
inferBinOp env op lhs rhs = do
  (substLhs, lhsType) <- infer env lhs
  (substRhs, rhsType) <- infer (applySubstEnv substLhs env) rhs
  case op of
    Add -> intBin substLhs substRhs lhsType rhsType PInt
    Sub -> intBin substLhs substRhs lhsType rhsType PInt
    Mul -> intBin substLhs substRhs lhsType rhsType PInt
    Div -> intBin substLhs substRhs lhsType rhsType PInt
    Lt -> intBin substLhs substRhs lhsType rhsType PBool
    Eq -> equality substLhs substRhs lhsType rhsType
 where
  intBin substLhs substRhs lhsType rhsType resultType = do
    substLhsInt <- unifyOrTypeError PInt (applySubst substRhs lhsType)
    substRhsInt <- unifyOrTypeError PInt (applySubst substLhsInt rhsType)
    pure (substRhsInt `composeSubst` substLhsInt `composeSubst` substRhs `composeSubst` substLhs, resultType)

  equality substLhs substRhs lhsType rhsType = do
    substEq <- unifyOrTypeError (applySubst substRhs lhsType) rhsType
    let equalType = applySubst substEq rhsType
    case equalType of
      PInt -> pure (substEq `composeSubst` substRhs `composeSubst` substLhs, PBool)
      PBool -> pure (substEq `composeSubst` substRhs `composeSubst` substLhs, PBool)
      PFun {} ->
        throwTypeError (EqualityNotSupported (toSyntaxTypeLossy equalType))
      PVar {} ->
        throwError (PrincipalAmbiguousEquality equalType)

freshTypeVar :: InferM PrincipalType
freshTypeVar = do
  state <- get
  let ty = PVar (TypeVar (nextTypeVar state))
  modify' (\st -> st {nextTypeVar = nextTypeVar st + 1})
  pure ty

instantiate :: TypeScheme -> InferM PrincipalType
instantiate (TypeScheme vars ty) = do
  replacements <-
    traverse
      ( \var -> do
          replacement <- freshTypeVar
          pure (var, replacement)
      )
      vars
  pure (applySubst (Map.fromList replacements) ty)

generalize :: PrincipalEnv -> PrincipalType -> TypeScheme
generalize env ty =
  TypeScheme (Set.toAscList (freeTypeVars ty `Set.difference` freeTypeVarsEnv env)) ty

unifyOrTypeError :: PrincipalType -> PrincipalType -> InferM Subst
unifyOrTypeError expected actual =
  case unify expected actual of
    Left err -> throwError err
    Right subst -> pure subst

unify :: PrincipalType -> PrincipalType -> Either PrincipalTypeError Subst
unify expected actual =
  case (expected, actual) of
    (PInt, PInt) ->
      Right emptySubst
    (PBool, PBool) ->
      Right emptySubst
    (PFun expectedArg expectedResult, PFun actualArg actualResult) -> do
      substArg <- unify expectedArg actualArg
      substResult <- unify (applySubst substArg expectedResult) (applySubst substArg actualResult)
      Right (substResult `composeSubst` substArg)
    (PVar var, ty) ->
      bindVar var ty
    (ty, PVar var) ->
      bindVar var ty
    _ ->
      Left (PrincipalTypeFailure (TypeMismatch (toSyntaxTypeLossy expected) (toSyntaxTypeLossy actual)))

bindVar :: TypeVar -> PrincipalType -> Either PrincipalTypeError Subst
bindVar var ty
  | ty == PVar var = Right emptySubst
  | var `Set.member` freeTypeVars ty = Left (PrincipalOccursCheck var ty)
  | otherwise = Right (Map.singleton var ty)

applySubst :: Subst -> PrincipalType -> PrincipalType
applySubst subst = \case
  PInt ->
    PInt
  PBool ->
    PBool
  PFun arg result ->
    PFun (applySubst subst arg) (applySubst subst result)
  PVar var ->
    Map.findWithDefault (PVar var) var subst

applySubstScheme :: Subst -> TypeScheme -> TypeScheme
applySubstScheme subst (TypeScheme vars ty) =
  TypeScheme vars (applySubst (foldr Map.delete subst vars) ty)

applySubstEnv :: Subst -> PrincipalEnv -> PrincipalEnv
applySubstEnv subst =
  Map.map (applySubstScheme subst)

composeSubst :: Subst -> Subst -> Subst
composeSubst newer older =
  Map.map (applySubst newer) older <> newer

emptySubst :: Subst
emptySubst =
  Map.empty

freeTypeVars :: PrincipalType -> Set.Set TypeVar
freeTypeVars = \case
  PInt ->
    Set.empty
  PBool ->
    Set.empty
  PFun arg result ->
    freeTypeVars arg <> freeTypeVars result
  PVar var ->
    Set.singleton var

freeTypeVarsScheme :: TypeScheme -> Set.Set TypeVar
freeTypeVarsScheme (TypeScheme vars ty) =
  freeTypeVars ty `Set.difference` Set.fromList vars

freeTypeVarsEnv :: PrincipalEnv -> Set.Set TypeVar
freeTypeVarsEnv =
  foldMap freeTypeVarsScheme

fromSyntaxType :: Type -> PrincipalType
fromSyntaxType = \case
  TInt ->
    PInt
  TBool ->
    PBool
  TFun arg result ->
    PFun (fromSyntaxType arg) (fromSyntaxType result)

toSyntaxTypeLossy :: PrincipalType -> Type
toSyntaxTypeLossy = \case
  PInt ->
    TInt
  PBool ->
    TBool
  PFun arg result ->
    TFun (toSyntaxTypeLossy arg) (toSyntaxTypeLossy result)
  PVar {} ->
    TInt

validateTopDefTypes :: Name -> [Type] -> Type -> InferM ()
validateTopDefTypes name paramTypes returnType =
  mapM_ rejectFunctionType (paramTypes <> [returnType])
 where
  rejectFunctionType ty =
    case ty of
      TFun {} -> throwTypeError (TopLevelFunctionTypeUnsupported name ty)
      TInt -> pure ()
      TBool -> pure ()

checkDuplicateParams :: [Name] -> InferM ()
checkDuplicateParams =
  go Set.empty
 where
  go _ [] =
    pure ()
  go seen (name : rest)
    | name `Set.member` seen = throwTypeError (DuplicateParameter name)
    | otherwise = go (Set.insert name seen) rest

throwTypeError :: TypeError -> InferM a
throwTypeError =
  throwError . PrincipalTypeFailure

renderPrincipalTypeError :: PrincipalTypeError -> Text
renderPrincipalTypeError = \case
  PrincipalTypeFailure err ->
    renderTypeError err
  PrincipalOccursCheck var ty ->
    "recursive type variable " <> renderTypeVar var <> " occurs in " <> renderPrincipalType ty
  PrincipalAmbiguousEquality ty ->
    "ambiguous equality operand type " <> renderPrincipalType ty

renderTypeScheme :: TypeScheme -> Text
renderTypeScheme (TypeScheme vars ty)
  | null vars = renderPrincipalType ty
  | otherwise =
      "forall "
        <> Text.unwords (map renderTypeVar vars)
        <> ". "
        <> renderPrincipalType ty

renderPrincipalType :: PrincipalType -> Text
renderPrincipalType = \case
  PInt ->
    renderDoc (prettyType TInt)
  PBool ->
    renderDoc (prettyType TBool)
  PFun arg result ->
    "(" <> renderPrincipalType arg <> " -> " <> renderPrincipalType result <> ")"
  PVar var ->
    renderTypeVar var

renderTypeVar :: TypeVar -> Text
renderTypeVar (TypeVar n) =
  "'t" <> Text.pack (show n)
