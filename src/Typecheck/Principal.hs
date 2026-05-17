module Typecheck.Principal
  ( PrincipalType (..)
  , PrincipalTypeError (..)
  , TypeVar (..)
  , TypeScheme (..)
  , elaborateLocated
  , elaborateLocatedProgram
  , elaborateLocatedWithEnv
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
import Syntax.Located
import Syntax.Pretty (prettyType, renderDoc)
import Syntax.Span (SourceSpan)
import Typecheck.Types (LocatedTypeError (..), TypeEnv, TypeError (..), renderTypeError)

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
  , equalityConstraints :: [EqualityConstraint]
  }
  deriving stock (Show, Eq)

data EqualityConstraint = EqualityConstraint SourceSpan PrincipalType
  deriving stock (Show, Eq)

type Subst = Map.Map TypeVar PrincipalType

type PrincipalEnv = Map.Map Name TypeScheme

type InferM = ExceptT PrincipalTypeError (State InferState)

type LocatedInferM = ExceptT LocatedTypeError (State InferState)

principalType :: Expr -> Either PrincipalTypeError TypeScheme
principalType expression =
  evalState (runExceptT (inferPrincipal Map.empty expression)) initialState

principalProgramType :: Program -> Either PrincipalTypeError TypeScheme
principalProgramType program =
  evalState (runExceptT (inferProgramPrincipal program)) initialState

initialState :: InferState
initialState =
  InferState {nextTypeVar = 0, equalityConstraints = []}

data PrincipalLocatedExpr = PrincipalLocatedExpr SourceSpan PrincipalLocatedExprNode
  deriving stock (Show, Eq)

data PrincipalLocatedExprNode
  = PLInt Integer
  | PLBool Bool
  | PLVar Name
  | PLLet Name PrincipalLocatedExpr PrincipalLocatedExpr
  | PLIf PrincipalLocatedExpr PrincipalLocatedExpr PrincipalLocatedExpr
  | PLBin BinOp PrincipalLocatedExpr PrincipalLocatedExpr
  | PLLam Name PrincipalType PrincipalLocatedExpr
  | PLApp PrincipalLocatedExpr PrincipalLocatedExpr
  deriving stock (Show, Eq)

elaborateLocated :: LocatedExpr -> Either LocatedTypeError (Type, LocatedExpr)
elaborateLocated =
  elaborateLocatedWithEnv Map.empty

elaborateLocatedWithEnv :: TypeEnv -> LocatedExpr -> Either LocatedTypeError (Type, LocatedExpr)
elaborateLocatedWithEnv env expression =
  evalState (runExceptT (elaborateLocatedExprM (principalEnvFromTypeEnv env) expression)) initialState

elaborateLocatedProgram :: LocatedProgram -> Either LocatedTypeError (Type, LocatedProgram)
elaborateLocatedProgram program =
  evalState (runExceptT (elaborateLocatedProgramM program)) initialState

principalEnvFromTypeEnv :: TypeEnv -> PrincipalEnv
principalEnvFromTypeEnv =
  Map.map (TypeScheme [] . fromSyntaxType)

elaborateLocatedProgramM :: LocatedProgram -> LocatedInferM (Type, LocatedProgram)
elaborateLocatedProgramM program = do
  (env, defs) <- elaborateLocatedTopDefs Map.empty (locatedProgramDefs program)
  (mainType, mainExpr) <- elaborateLocatedExprM env (locatedProgramMain program)
  pure
    ( mainType
    , LocatedProgram
        { locatedProgramDefs = defs
        , locatedProgramMain = mainExpr
        }
    )

elaborateLocatedTopDefs :: PrincipalEnv -> [LocatedTopDef] -> LocatedInferM (PrincipalEnv, [LocatedTopDef])
elaborateLocatedTopDefs env = \case
  [] ->
    pure (env, [])
  def : rest -> do
    if locatedTopDefName def `Map.member` env
      then throwLocated (locatedTopDefSpan def) (DuplicateTopLevelName (locatedTopDefName def))
      else pure ()
    validateLocatedTopDefTypes def
    checkDuplicateLocatedParams (locatedTopDefParams def)
    resetEqualityConstraints
    let params = [param | LocatedParam _ param <- locatedTopDefParams def]
        paramEnv =
          Map.fromList
            [ (paramName param, TypeScheme [] (fromSyntaxType (paramType param)))
            | param <- params
            ]
        returnType = fromSyntaxType (locatedTopDefReturnType def)
    (substBody, bodyType, bodyPrincipal) <- inferLocatedPrincipal (paramEnv <> env) (locatedTopDefBody def)
    substReturn <- unifyOrLocated (locatedTopDefSpan def) returnType bodyType
    let subst = substReturn `composeSubst` substBody
    constraints <- currentEqualityConstraints
    validateEqualityConstraints subst constraints
    body <- finalizeLocatedExpr (applySubstLocatedExpr subst bodyPrincipal)
    let transformedDef = def {locatedTopDefBody = body}
        env' = Map.insert (locatedTopDefName def) (TypeScheme [] (fromSyntaxType (locatedTopDefType transformedDef))) env
    (finalEnv, restDefs) <- elaborateLocatedTopDefs env' rest
    pure (finalEnv, transformedDef : restDefs)

elaborateLocatedExprM :: PrincipalEnv -> LocatedExpr -> LocatedInferM (Type, LocatedExpr)
elaborateLocatedExprM env expression = do
  resetEqualityConstraints
  (subst, principalTy, principalExpr) <- inferLocatedPrincipal env expression
  constraints <- currentEqualityConstraints
  validateEqualityConstraints subst constraints
  finalExpr <- finalizeLocatedExpr (applySubstLocatedExpr subst principalExpr)
  finalType <- concreteTypeOrLocated (locatedExprSpan expression) (applySubst subst principalTy)
  pure (finalType, finalExpr)

inferLocatedPrincipal :: PrincipalEnv -> LocatedExpr -> LocatedInferM (Subst, PrincipalType, PrincipalLocatedExpr)
inferLocatedPrincipal env (LocatedExpr sourceRange node) =
  case node of
    LInt n -> do
      case mkHIntLiteral n of
        Right _ -> pure (emptySubst, PInt, PrincipalLocatedExpr sourceRange (PLInt n))
        Left _ -> throwLocated sourceRange (IntLiteralOutOfRange n)
    LBool value ->
      pure (emptySubst, PBool, PrincipalLocatedExpr sourceRange (PLBool value))
    LVar name ->
      case Map.lookup name env of
        Just scheme -> do
          ty <- instantiateLocated sourceRange scheme
          pure (emptySubst, ty, PrincipalLocatedExpr sourceRange (PLVar name))
        Nothing ->
          throwLocated sourceRange (UnknownVariable name)
    LLet name rhs body -> do
      (substRhs, rhsType, principalRhs) <- inferLocatedPrincipal env rhs
      let envAfterRhs = applySubstEnv substRhs env
          rhsScheme = TypeScheme [] (applySubst substRhs rhsType)
      (substBody, bodyType, principalBody) <- inferLocatedPrincipal (Map.insert name rhsScheme envAfterRhs) body
      pure
        ( substBody `composeSubst` substRhs
        , bodyType
        , PrincipalLocatedExpr sourceRange (PLLet name principalRhs principalBody)
        )
    LIf cond thenBranch elseBranch -> do
      (substCond, condType, principalCond) <- inferLocatedPrincipal env cond
      substBool <- requireBoolCondition (locatedExprSpan cond) (applySubst substCond condType)
      let envAfterCond = applySubstEnv (substBool `composeSubst` substCond) env
      (substThen, thenType, principalThen) <- inferLocatedPrincipal envAfterCond thenBranch
      (substElse, elseType, principalElse) <- inferLocatedPrincipal (applySubstEnv substThen envAfterCond) elseBranch
      substBranches <- unifyOrLocated sourceRange (applySubst substElse thenType) elseType
      pure
        ( substBranches `composeSubst` substElse `composeSubst` substThen `composeSubst` substBool `composeSubst` substCond
        , applySubst substBranches elseType
        , PrincipalLocatedExpr sourceRange (PLIf principalCond principalThen principalElse)
        )
    LBin op lhs rhs ->
      inferLocatedBinOp env sourceRange op lhs rhs
    LLam name maybeArgType body -> do
      argType <-
        case maybeArgType of
          Just explicitType -> pure (fromSyntaxType explicitType)
          Nothing -> freshTypeVarLocated sourceRange
      (substBody, bodyType, principalBody) <-
        inferLocatedPrincipal (Map.insert name (TypeScheme [] argType) env) body
      pure
        ( substBody
        , PFun (applySubst substBody argType) bodyType
        , PrincipalLocatedExpr sourceRange (PLLam name argType principalBody)
        )
    LApp fn arg -> do
      (substFn, fnType, principalFn) <- inferLocatedPrincipal env fn
      (substArg, argType, principalArg) <- inferLocatedPrincipal (applySubstEnv substFn env) arg
      resultType <- freshTypeVarLocated sourceRange
      let appliedFnType = applySubst substArg fnType
      case appliedFnType of
        PInt ->
          throwLocated (locatedExprSpan fn) (ExpectedFunction TInt)
        PBool ->
          throwLocated (locatedExprSpan fn) (ExpectedFunction TBool)
        PFun {} ->
          pure ()
        PVar {} ->
          pure ()
      substApp <- unifyOrLocated (locatedExprSpan arg) appliedFnType (PFun argType resultType)
      pure
        ( substApp `composeSubst` substArg `composeSubst` substFn
        , applySubst substApp resultType
        , PrincipalLocatedExpr sourceRange (PLApp principalFn principalArg)
        )

inferLocatedBinOp :: PrincipalEnv -> SourceSpan -> BinOp -> LocatedExpr -> LocatedExpr -> LocatedInferM (Subst, PrincipalType, PrincipalLocatedExpr)
inferLocatedBinOp env sourceRange op lhs rhs = do
  (substLhs, lhsType, principalLhs) <- inferLocatedPrincipal env lhs
  (substRhs, rhsType, principalRhs) <- inferLocatedPrincipal (applySubstEnv substLhs env) rhs
  let principalExpr = PrincipalLocatedExpr sourceRange (PLBin op principalLhs principalRhs)
  case op of
    Add -> intBin principalExpr substLhs substRhs lhsType rhsType PInt
    Sub -> intBin principalExpr substLhs substRhs lhsType rhsType PInt
    Mul -> intBin principalExpr substLhs substRhs lhsType rhsType PInt
    Div -> intBin principalExpr substLhs substRhs lhsType rhsType PInt
    Lt -> intBin principalExpr substLhs substRhs lhsType rhsType PBool
    Eq -> equality principalExpr substLhs substRhs lhsType rhsType
 where
  requireIntOperand operandSpan actual =
    case actual of
      PInt ->
        pure emptySubst
      PBool ->
        throwLocated operandSpan (ExpectedIntOperand op TBool)
      PFun {} ->
        throwLocated operandSpan (ExpectedIntOperand op (toSyntaxTypeLossy actual))
      PVar {} ->
        unifyOrLocated operandSpan PInt actual

  intBin principalExpr substLhs substRhs lhsType rhsType resultType = do
    substLhsInt <- requireIntOperand (locatedExprSpan lhs) (applySubst substRhs lhsType)
    substRhsInt <- requireIntOperand (locatedExprSpan rhs) (applySubst substLhsInt rhsType)
    pure (substRhsInt `composeSubst` substLhsInt `composeSubst` substRhs `composeSubst` substLhs, resultType, principalExpr)

  equality principalExpr substLhs substRhs lhsType rhsType = do
    substEq <- unifyOrLocated sourceRange (applySubst substRhs lhsType) rhsType
    recordEqualityConstraint sourceRange (applySubst substEq rhsType)
    pure (substEq `composeSubst` substRhs `composeSubst` substLhs, PBool, principalExpr)

requireBoolCondition :: SourceSpan -> PrincipalType -> LocatedInferM Subst
requireBoolCondition sourceRange actual =
  case actual of
    PBool ->
      pure emptySubst
    PInt ->
      throwLocated sourceRange (ExpectedBoolCondition TInt)
    PFun {} ->
      throwLocated sourceRange (ExpectedBoolCondition (toSyntaxTypeLossy actual))
    PVar {} ->
      unifyOrLocated sourceRange PBool actual

finalizeLocatedExpr :: PrincipalLocatedExpr -> LocatedInferM LocatedExpr
finalizeLocatedExpr (PrincipalLocatedExpr sourceRange node) =
  case node of
    PLInt n ->
      pure (LocatedExpr sourceRange (LInt n))
    PLBool value ->
      pure (LocatedExpr sourceRange (LBool value))
    PLVar name ->
      pure (LocatedExpr sourceRange (LVar name))
    PLLet name rhs body ->
      LocatedExpr sourceRange <$> (LLet name <$> finalizeLocatedExpr rhs <*> finalizeLocatedExpr body)
    PLIf cond thenBranch elseBranch ->
      LocatedExpr sourceRange <$> (LIf <$> finalizeLocatedExpr cond <*> finalizeLocatedExpr thenBranch <*> finalizeLocatedExpr elseBranch)
    PLBin op lhs rhs ->
      LocatedExpr sourceRange <$> (LBin op <$> finalizeLocatedExpr lhs <*> finalizeLocatedExpr rhs)
    PLLam name argType body -> do
      syntaxArgType <-
        case concreteType argType of
          Just ty -> pure ty
          Nothing -> throwLocated sourceRange (AmbiguousLambdaParameter name)
      LocatedExpr sourceRange . LLam name (Just syntaxArgType) <$> finalizeLocatedExpr body
    PLApp fn arg ->
      LocatedExpr sourceRange <$> (LApp <$> finalizeLocatedExpr fn <*> finalizeLocatedExpr arg)

applySubstLocatedExpr :: Subst -> PrincipalLocatedExpr -> PrincipalLocatedExpr
applySubstLocatedExpr subst (PrincipalLocatedExpr sourceRange node) =
  PrincipalLocatedExpr sourceRange $
    case node of
      PLInt n ->
        PLInt n
      PLBool value ->
        PLBool value
      PLVar name ->
        PLVar name
      PLLet name rhs body ->
        PLLet name (applySubstLocatedExpr subst rhs) (applySubstLocatedExpr subst body)
      PLIf cond thenBranch elseBranch ->
        PLIf (applySubstLocatedExpr subst cond) (applySubstLocatedExpr subst thenBranch) (applySubstLocatedExpr subst elseBranch)
      PLBin op lhs rhs ->
        PLBin op (applySubstLocatedExpr subst lhs) (applySubstLocatedExpr subst rhs)
      PLLam name argType body ->
        PLLam name (applySubst subst argType) (applySubstLocatedExpr subst body)
      PLApp fn arg ->
        PLApp (applySubstLocatedExpr subst fn) (applySubstLocatedExpr subst arg)

concreteTypeOrLocated :: SourceSpan -> PrincipalType -> LocatedInferM Type
concreteTypeOrLocated sourceRange ty =
  case concreteType ty of
    Just syntaxType -> pure syntaxType
    Nothing -> throwLocated sourceRange AmbiguousExpressionType

concreteType :: PrincipalType -> Maybe Type
concreteType = \case
  PInt ->
    Just TInt
  PBool ->
    Just TBool
  PFun arg result ->
    TFun <$> concreteType arg <*> concreteType result
  PVar {} ->
    Nothing

validateEqualityConstraints :: Subst -> [EqualityConstraint] -> LocatedInferM ()
validateEqualityConstraints subst =
  mapM_ validate
 where
  validate (EqualityConstraint sourceRange ty) =
    let resolvedType = applySubst subst ty
     in case resolvedType of
      PInt ->
        pure ()
      PBool ->
        pure ()
      PFun {} ->
        throwLocated sourceRange (EqualityNotSupported (toSyntaxTypeLossy resolvedType))
      PVar {} ->
        throwLocated sourceRange AmbiguousEqualityOperand

resetEqualityConstraints :: LocatedInferM ()
resetEqualityConstraints =
  modify' (\state -> state {equalityConstraints = []})

recordEqualityConstraint :: SourceSpan -> PrincipalType -> LocatedInferM ()
recordEqualityConstraint sourceRange ty =
  modify' (\state -> state {equalityConstraints = EqualityConstraint sourceRange ty : equalityConstraints state})

currentEqualityConstraints :: LocatedInferM [EqualityConstraint]
currentEqualityConstraints =
  reverse . equalityConstraints <$> get

freshTypeVarLocated :: SourceSpan -> LocatedInferM PrincipalType
freshTypeVarLocated _sourceRange = do
  state <- get
  let ty = PVar (TypeVar (nextTypeVar state))
  modify' (\st -> st {nextTypeVar = nextTypeVar st + 1})
  pure ty

instantiateLocated :: SourceSpan -> TypeScheme -> LocatedInferM PrincipalType
instantiateLocated _sourceRange (TypeScheme vars ty) = do
  replacements <-
    traverse
      ( \var -> do
          replacement <- freshTypeVarLocated _sourceRange
          pure (var, replacement)
      )
      vars
  pure (applySubst (Map.fromList replacements) ty)

unifyOrLocated :: SourceSpan -> PrincipalType -> PrincipalType -> LocatedInferM Subst
unifyOrLocated sourceRange expected actual =
  case unify expected actual of
    Left err -> throwLocated sourceRange (principalTypeErrorToTypeError err)
    Right subst -> pure subst

principalTypeErrorToTypeError :: PrincipalTypeError -> TypeError
principalTypeErrorToTypeError = \case
  PrincipalTypeFailure err ->
    err
  PrincipalOccursCheck {} ->
    RecursiveType
  PrincipalAmbiguousEquality {} ->
    AmbiguousEqualityOperand

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

throwLocated :: SourceSpan -> TypeError -> LocatedInferM a
throwLocated sourceRange =
  throwError . LocatedTypeError sourceRange

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
