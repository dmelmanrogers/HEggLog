module Haskell2010.Typecheck
  ( TypecheckError (..)
  , renderTypecheckError
  , typecheckModuleToCore
  )
where

import Control.Monad (foldM, unless)
import Control.Monad.State.Strict (StateT, get, lift, modify, runStateT)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names
import Haskell2010.Renamed
import Haskell2010.Syntax (Literal (..))

data TypecheckError
  = UnsupportedCore0 Text
  | DuplicateTypeSignature RName
  | SignatureWithoutBinding RName
  | UnknownCore0Variable RName
  | TypeMismatch MonoType MonoType
  | OccursCheck Int MonoType
  | AmbiguousTypeVariable Int
  | CoreValidationFailed [CoreValidate.CoreValidationError]
  deriving stock (Show, Eq)

data MonoType
  = TyMeta Int
  | TyVar RName
  | TyCon RName
  | TyApp MonoType MonoType
  | TyFun MonoType MonoType
  | TyTuple [MonoType]
  | TyList MonoType
  deriving stock (Show, Eq, Ord)

data Scheme = Scheme [RName] MonoType
  deriving stock (Show, Eq, Ord)

data TypedBinder = TypedBinder RName MonoType
  deriving stock (Show, Eq, Ord)

data TypedBinding = TypedBinding
  { typedBindingName :: RName
  , typedBindingScheme :: Scheme
  , typedBindingGeneralizedMetas :: Map.Map Int RName
  , typedBindingRhs :: TypedExpr
  }
  deriving stock (Show, Eq, Ord)

data TypedAlt = TypedAlt CoreAltCon [TypedBinder] TypedExpr
  deriving stock (Show, Eq, Ord)

data TypedExpr
  = TVar RName Scheme [MonoType] MonoType
  | TLit Literal MonoType
  | TCon RName MonoType
  | TLam TypedBinder TypedExpr MonoType
  | TApp TypedExpr TypedExpr MonoType
  | TLet [TypedBinding] TypedExpr MonoType
  | TCase TypedExpr TypedBinder [TypedAlt] MonoType
  | TPrim CorePrimOp [TypedExpr] MonoType
  deriving stock (Show, Eq, Ord)

type TypeEnv = Map.Map RName Scheme

type Subst = Map.Map Int MonoType

data InferState = InferState
  { nextMeta :: Int
  , substitution :: Subst
  , nextGeneratedUnique :: Int
  }
  deriving stock (Show, Eq)

type InferM = StateT InferState (Either TypecheckError)

typecheckModuleToCore :: RHsModule -> Either TypecheckError CoreModule
typecheckModuleToCore sourceModule = do
  ((typedBindings, _typedEnv), finalState) <-
    runInfer (inferBindingGroup Map.empty (rModuleDecls sourceModule))
  coreBinds <- traverse (bindingToCore (substitution finalState) Map.empty) typedBindings
  let coreModule =
        CoreModule
          { coreModuleName = rModuleName sourceModule
          , coreModuleBinds =
              case coreBinds of
                [] -> []
                [one] -> [one]
                many -> [CoreRec (concatMap bindPairs many)]
          }
  case CoreValidate.validateModule CoreValidate.defaultValidationEnv coreModule of
    Right () -> Right coreModule
    Left errors -> Left (CoreValidationFailed errors)

renderTypecheckError :: TypecheckError -> Text
renderTypecheckError = \case
  UnsupportedCore0 message ->
    "unsupported Core-0 Haskell 2010 form: " <> message
  DuplicateTypeSignature name ->
    "duplicate type signature for `" <> renderRName name <> "`"
  SignatureWithoutBinding name ->
    "type signature has no Core-0 binding: `" <> renderRName name <> "`"
  UnknownCore0Variable name ->
    "unknown Core-0 variable `" <> renderRName name <> "`"
  TypeMismatch expected actual ->
    "type mismatch: expected " <> renderMonoType expected <> ", got " <> renderMonoType actual
  OccursCheck meta ty ->
    "occurs check failed: ?" <> renderInt meta <> " occurs in " <> renderMonoType ty
  AmbiguousTypeVariable meta ->
    "ambiguous Core-0 type variable ?" <> renderInt meta
  CoreValidationFailed errors ->
    "generated Core failed validation: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)

runInfer :: InferM a -> Either TypecheckError (a, InferState)
runInfer action =
  let initialState =
        InferState
          { nextMeta = 0
          , substitution = Map.empty
          , nextGeneratedUnique = 100000
          }
   in swapState <$> runStateT action initialState
 where
  swapState (value, state) =
    (value, state)

inferBindingGroup :: TypeEnv -> [RDecl] -> InferM ([TypedBinding], TypeEnv)
inferBindingGroup outerEnv decls = do
  signatures <- collectSignatures decls
  sourceBindings <- collectValueBindings decls
  let bindingNames = map sourceBindingName sourceBindings
  mapM_ (ensureSignatureHasBinding bindingNames) (Map.keys signatures)
  prepared <- traverse (prepareBinding signatures) sourceBindings
  let recursiveEnv = Map.union (Map.fromList [(preparedName binding, preparedScheme binding) | binding <- prepared]) outerEnv
  inferred <- traverse (inferPreparedBinding recursiveEnv) prepared
  finalized <- traverse (finalizeBinding outerEnv signatures) inferred
  let finalizedEnv = Map.union (Map.fromList [(typedBindingName binding, typedBindingScheme binding) | binding <- finalized]) outerEnv
  pure (finalized, finalizedEnv)

data SourceBinding = SourceBinding RName [RPat] RRhs [RDecl]
  deriving stock (Show, Eq, Ord)

data PreparedBinding = PreparedBinding
  { preparedName :: RName
  , preparedPatterns :: [RPat]
  , preparedRhs :: RRhs
  , preparedWhereDecls :: [RDecl]
  , preparedExpected :: MonoType
  , preparedScheme :: Scheme
  , preparedHasSignature :: Bool
  }
  deriving stock (Show, Eq, Ord)

data InferredBinding = InferredBinding PreparedBinding TypedExpr
  deriving stock (Show, Eq, Ord)

collectSignatures :: [RDecl] -> InferM (Map.Map RName Scheme)
collectSignatures =
  foldM collect Map.empty
 where
  collect acc = \case
    RTypeSignature names sourceType -> do
      scheme <- sourceScheme sourceType
      foldM (insertSignature scheme) acc names
    _ ->
      pure acc

  insertSignature scheme acc name =
    case Map.lookup name acc of
      Just _ -> throwTypecheck (DuplicateTypeSignature name)
      Nothing -> pure (Map.insert name scheme acc)

collectValueBindings :: [RDecl] -> InferM [SourceBinding]
collectValueBindings =
  foldM collect []
 where
  collect acc = \case
    RTypeSignature {} ->
      pure acc
    RFixityDecl {} ->
      pure acc
    RFunctionBinding name patterns rhs whereDecls ->
      pure (acc <> [SourceBinding name patterns rhs whereDecls])
    RPatternBinding (RPVar name) rhs whereDecls ->
      pure (acc <> [SourceBinding name [] rhs whereDecls])
    RPatternBinding pat _ _ ->
      throwTypecheck (UnsupportedCore0 ("top-level pattern binding " <> renderPatternShape pat))
    other ->
      throwTypecheck (UnsupportedCore0 ("declaration " <> Text.pack (show other)))

sourceBindingName :: SourceBinding -> RName
sourceBindingName (SourceBinding name _ _ _) =
  name

ensureSignatureHasBinding :: [RName] -> RName -> InferM ()
ensureSignatureHasBinding bindingNames name =
  unless (name `elem` bindingNames) $
    throwTypecheck (SignatureWithoutBinding name)

prepareBinding :: Map.Map RName Scheme -> SourceBinding -> InferM PreparedBinding
prepareBinding signatures (SourceBinding name patterns rhs whereDecls) =
  case Map.lookup name signatures of
    Just scheme ->
      pure
        PreparedBinding
          { preparedName = name
          , preparedPatterns = patterns
          , preparedRhs = rhs
          , preparedWhereDecls = whereDecls
          , preparedExpected = schemeBody scheme
          , preparedScheme = scheme
          , preparedHasSignature = True
          }
    Nothing -> do
      expected <- freshMeta
      pure
        PreparedBinding
          { preparedName = name
          , preparedPatterns = patterns
          , preparedRhs = rhs
          , preparedWhereDecls = whereDecls
          , preparedExpected = expected
          , preparedScheme = Scheme [] expected
          , preparedHasSignature = False
          }

inferPreparedBinding :: TypeEnv -> PreparedBinding -> InferM InferredBinding
inferPreparedBinding env prepared = do
  expr <- inferFunctionBindingExpr env (preparedPatterns prepared) (preparedRhs prepared) (preparedWhereDecls prepared)
  unify (preparedExpected prepared) (typedExprType expr)
  pure (InferredBinding prepared expr)

finalizeBinding :: TypeEnv -> Map.Map RName Scheme -> InferredBinding -> InferM TypedBinding
finalizeBinding outerEnv signatures (InferredBinding prepared rhs) =
  if preparedHasSignature prepared
    then do
      let scheme = signatures Map.! preparedName prepared
      pure
        TypedBinding
          { typedBindingName = preparedName prepared
          , typedBindingScheme = scheme
          , typedBindingGeneralizedMetas = Map.empty
          , typedBindingRhs = rhs
          }
    else do
      generalized <- generalize outerEnv (typedExprType rhs)
      pure
        TypedBinding
          { typedBindingName = preparedName prepared
          , typedBindingScheme = generalizedScheme generalized
          , typedBindingGeneralizedMetas = generalizedMetas generalized
          , typedBindingRhs = rhs
          }

inferFunctionBindingExpr :: TypeEnv -> [RPat] -> RRhs -> [RDecl] -> InferM TypedExpr
inferFunctionBindingExpr env patterns rhs whereDecls = do
  bodyExpr <- rhsToExpr rhs whereDecls
  inferLambda env patterns bodyExpr

inferLambda :: TypeEnv -> [RPat] -> RExpr -> InferM TypedExpr
inferLambda env patterns bodyExpr = do
  binders <- traverse inferPatternBinder patterns
  let bodyEnv =
        foldr
          (\binder -> Map.insert (typedBinderName binder) (Scheme [] (typedBinderType binder)))
          env
          binders
  body <- inferExpr bodyEnv bodyExpr
  pure (foldr wrapLambda body binders)
 where
  wrapLambda binder body =
    TLam binder body (TyFun (typedBinderType binder) (typedExprType body))

rhsToExpr :: RRhs -> [RDecl] -> InferM RExpr
rhsToExpr rhs whereDecls =
  case rhs of
    RUnguarded expr ->
      pure $
        if null whereDecls
          then expr
          else RLet whereDecls expr
    RGuarded {} ->
      throwTypecheck (UnsupportedCore0 "guarded right-hand side")

inferExpr :: TypeEnv -> RExpr -> InferM TypedExpr
inferExpr env = \case
  RVar name ->
    case Map.lookup name env of
      Nothing ->
        throwTypecheck (UnknownCore0Variable name)
      Just scheme -> do
        (instantiatedTy, typeArguments) <- instantiate scheme
        pure (TVar name scheme typeArguments instantiatedTy)
  RCon name ->
    inferConstructor name
  RLit literal ->
    pure (TLit literal (literalMonoType literal))
  RApp fn arg -> do
    typedFn <- inferExpr env fn
    typedArg <- inferExpr env arg
    resultTy <- freshMeta
    unify (typedExprType typedFn) (TyFun (typedExprType typedArg) resultTy)
    pure (TApp typedFn typedArg resultTy)
  RInfixApp lhs op rhs ->
    inferPrimitive env lhs op rhs
  RLambda patterns body ->
    inferLambda env patterns body
  RLet decls body -> do
    (bindings, env') <- inferBindingGroup env decls
    typedBody <- inferExpr env' body
    pure (TLet bindings typedBody (typedExprType typedBody))
  RIf condition thenBranch elseBranch -> do
    typedCondition <- inferExpr env condition
    unify (typedExprType typedCondition) boolMonoType
    typedThen <- inferExpr env thenBranch
    typedElse <- inferExpr env elseBranch
    unify (typedExprType typedThen) (typedExprType typedElse)
    caseBinder <- freshTermBinder "$if" boolMonoType
    let resultTy = typedExprType typedThen
    pure
      ( TCase
          typedCondition
          caseBinder
          [ TypedAlt (ConstructorAlt trueDataConName) [] typedThen
          , TypedAlt (ConstructorAlt falseDataConName) [] typedElse
          ]
          resultTy
      )
  RCase scrutinee alternatives -> do
    typedScrutinee <- inferExpr env scrutinee
    unify (typedExprType typedScrutinee) boolMonoType
    resultTy <- freshMeta
    caseBinder <- caseBinderFor alternatives
    typedAlternatives <- traverse (inferBoolAlt env caseBinder resultTy) alternatives
    pure (TCase typedScrutinee caseBinder typedAlternatives resultTy)
  RParen inner ->
    inferExpr env inner
  RExprTypeSig inner sourceType -> do
    scheme <- sourceScheme sourceType
    typedInner <- inferExpr env inner
    unify (typedExprType typedInner) (schemeBody scheme)
    pure typedInner
  unsupported ->
    throwTypecheck (UnsupportedCore0 ("expression " <> Text.pack (show unsupported)))

inferConstructor :: RName -> InferM TypedExpr
inferConstructor name
  | nameOcc name == "True" =
      pure (TCon trueDataConName boolMonoType)
  | nameOcc name == "False" =
      pure (TCon falseDataConName boolMonoType)
  | otherwise =
      throwTypecheck (UnsupportedCore0 ("constructor `" <> renderRName name <> "`"))

inferPrimitive :: TypeEnv -> RExpr -> RName -> RExpr -> InferM TypedExpr
inferPrimitive env lhs op rhs =
  case nameOcc op of
    "+" -> fixedInt PrimAdd
    "-" -> fixedInt PrimSub
    "*" -> fixedInt PrimMul
    "/" -> fixedInt PrimDiv
    "<" -> fixedCompare PrimLt
    "==" -> equality
    other -> throwTypecheck (UnsupportedCore0 ("operator `" <> other <> "`"))
 where
  fixedInt prim = do
    typedLhs <- inferExpr env lhs
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedLhs) intMonoType
    unify (typedExprType typedRhs) intMonoType
    pure (TPrim prim [typedLhs, typedRhs] intMonoType)

  fixedCompare prim = do
    typedLhs <- inferExpr env lhs
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedLhs) intMonoType
    unify (typedExprType typedRhs) intMonoType
    pure (TPrim prim [typedLhs, typedRhs] boolMonoType)

  equality = do
    typedLhs <- inferExpr env lhs
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedLhs) (typedExprType typedRhs)
    equalityType <- applyCurrent (typedExprType typedLhs)
    unless (supportsCore0Equality equalityType) $
      throwTypecheck (UnsupportedCore0 ("equality for type " <> renderMonoType equalityType))
    pure (TPrim PrimEq [typedLhs, typedRhs] boolMonoType)

  supportsCore0Equality ty =
    ty == intMonoType
      || ty == boolMonoType
      || ty == charMonoType
      || ty == stringMonoType

inferBoolAlt :: TypeEnv -> TypedBinder -> MonoType -> RAlt -> InferM TypedAlt
inferBoolAlt env caseBinder resultTy (RAlt pat rhs whereDecls) = do
  (altCon, extraBinders, env') <- boolAltPattern env caseBinder pat
  bodyExpr <- rhsToExpr rhs whereDecls
  typedBody <- inferExpr env' bodyExpr
  unify resultTy (typedExprType typedBody)
  pure (TypedAlt altCon extraBinders typedBody)

boolAltPattern :: TypeEnv -> TypedBinder -> RPat -> InferM (CoreAltCon, [TypedBinder], TypeEnv)
boolAltPattern env caseBinder = \case
  RPCon name []
    | nameOcc name == "True" ->
        pure (ConstructorAlt trueDataConName, [], env)
    | nameOcc name == "False" ->
        pure (ConstructorAlt falseDataConName, [], env)
  RPWildcard ->
    pure (DefaultAlt, [], env)
  RPVar name ->
    let binder = TypedBinder name (typedBinderType caseBinder)
     in pure (DefaultAlt, [], Map.insert name (Scheme [] (typedBinderType binder)) env)
  RPParen pat ->
    boolAltPattern env caseBinder pat
  pat ->
    throwTypecheck (UnsupportedCore0 ("case pattern " <> renderPatternShape pat))

caseBinderFor :: [RAlt] -> InferM TypedBinder
caseBinderFor alternatives =
  case [name | RAlt (RPVar name) _ _ <- alternatives] of
    name : _ ->
      pure (TypedBinder name boolMonoType)
    [] ->
      freshTermBinder "$case" boolMonoType

inferPatternBinder :: RPat -> InferM TypedBinder
inferPatternBinder = \case
  RPVar name ->
    TypedBinder name <$> freshMeta
  RPWildcard ->
    freshMeta >>= freshTermBinder "$wild"
  RPParen pat ->
    inferPatternBinder pat
  pat ->
    throwTypecheck (UnsupportedCore0 ("lambda/function pattern " <> renderPatternShape pat))

sourceScheme :: RHsType -> InferM Scheme
sourceScheme sourceType = do
  mono <- sourceMonoType sourceType
  pure (Scheme (List.nub (typeVars mono)) mono)

sourceMonoType :: RHsType -> InferM MonoType
sourceMonoType = \case
  RTyVar name ->
    pure (TyVar name)
  RTyCon name ->
    typeConstructorMonoType name
  RTyApp fn arg ->
    TyApp <$> sourceMonoType fn <*> sourceMonoType arg
  RTyFun arg result ->
    TyFun <$> sourceMonoType arg <*> sourceMonoType result
  RTyContext [] body ->
    sourceMonoType body
  RTyContext _ _ ->
    throwTypecheck (UnsupportedCore0 "type-class constraints")
  RTyTuple types ->
    TyTuple <$> traverse sourceMonoType types
  RTyList elementType ->
    TyList <$> sourceMonoType elementType
  RTyParen inner ->
    sourceMonoType inner

typeConstructorMonoType :: RName -> InferM MonoType
typeConstructorMonoType name =
  case nameOcc name of
    "Int" -> pure intMonoType
    "Bool" -> pure boolMonoType
    "Char" -> pure charMonoType
    "String" -> pure stringMonoType
    other -> throwTypecheck (UnsupportedCore0 ("type constructor `" <> other <> "`"))

instantiate :: Scheme -> InferM (MonoType, [MonoType])
instantiate (Scheme variables body) = do
  replacements <- traverse (\name -> (name,) <$> freshMeta) variables
  let replacementMap = Map.fromList replacements
      instantiated = replaceTypeVars replacementMap body
  pure (instantiated, map snd replacements)

data Generalized = Generalized
  { generalizedScheme :: Scheme
  , generalizedMetas :: Map.Map Int RName
  }
  deriving stock (Show, Eq, Ord)

generalize :: TypeEnv -> MonoType -> InferM Generalized
generalize env ty = do
  zonked <- applyCurrent ty
  let envMetas = freeMetaVarsEnv env
      metas = Set.toAscList (freeMetaVars zonked `Set.difference` envMetas)
  names <- traverse freshTypeVariableName metas
  let metaMap = Map.fromList (zip metas names)
      generalizedTy = replaceMetasWithVars metaMap zonked
  pure
    Generalized
      { generalizedScheme = Scheme names generalizedTy
      , generalizedMetas = metaMap
      }

unify :: MonoType -> MonoType -> InferM ()
unify lhs rhs = do
  lhs' <- applyCurrent lhs
  rhs' <- applyCurrent rhs
  case (lhs', rhs') of
    (TyMeta lhsMeta, TyMeta rhsMeta)
      | lhsMeta == rhsMeta -> pure ()
    (TyMeta meta, ty) ->
      bindMeta meta ty
    (ty, TyMeta meta) ->
      bindMeta meta ty
    (TyVar lhsName, TyVar rhsName)
      | lhsName == rhsName -> pure ()
    (TyCon lhsName, TyCon rhsName)
      | lhsName == rhsName -> pure ()
    (TyApp lhsFn lhsArg, TyApp rhsFn rhsArg) ->
      unify lhsFn rhsFn *> unify lhsArg rhsArg
    (TyFun lhsArg lhsResult, TyFun rhsArg rhsResult) ->
      unify lhsArg rhsArg *> unify lhsResult rhsResult
    (TyTuple lhsFields, TyTuple rhsFields)
      | length lhsFields == length rhsFields ->
          zipWithM_ unify lhsFields rhsFields
    (TyList lhsElement, TyList rhsElement) ->
      unify lhsElement rhsElement
    _ ->
      throwTypecheck (TypeMismatch lhs' rhs')

bindMeta :: Int -> MonoType -> InferM ()
bindMeta meta ty
  | ty == TyMeta meta = pure ()
  | meta `Set.member` freeMetaVars ty = throwTypecheck (OccursCheck meta ty)
  | otherwise =
      modify $ \state ->
        state {substitution = Map.insert meta ty (substitution state)}

applyCurrent :: MonoType -> InferM MonoType
applyCurrent ty = do
  subst <- substitution <$> get
  pure (applySubst subst ty)

applySubst :: Subst -> MonoType -> MonoType
applySubst subst = \case
  TyMeta meta ->
    case Map.lookup meta subst of
      Nothing -> TyMeta meta
      Just ty -> applySubst subst ty
  TyVar name ->
    TyVar name
  TyCon name ->
    TyCon name
  TyApp fn arg ->
    TyApp (applySubst subst fn) (applySubst subst arg)
  TyFun arg result ->
    TyFun (applySubst subst arg) (applySubst subst result)
  TyTuple fields ->
    TyTuple (map (applySubst subst) fields)
  TyList elementType ->
    TyList (applySubst subst elementType)

freeMetaVarsEnv :: TypeEnv -> Set.Set Int
freeMetaVarsEnv =
  Set.unions . map freeMetaVarsScheme . Map.elems

freeMetaVarsScheme :: Scheme -> Set.Set Int
freeMetaVarsScheme (Scheme _ ty) =
  freeMetaVars ty

freeMetaVars :: MonoType -> Set.Set Int
freeMetaVars = \case
  TyMeta meta -> Set.singleton meta
  TyVar {} -> Set.empty
  TyCon {} -> Set.empty
  TyApp fn arg -> freeMetaVars fn <> freeMetaVars arg
  TyFun arg result -> freeMetaVars arg <> freeMetaVars result
  TyTuple fields -> Set.unions (map freeMetaVars fields)
  TyList elementType -> freeMetaVars elementType

typeVars :: MonoType -> [RName]
typeVars =
  Set.toList . collect
 where
  collect = \case
    TyMeta {} -> Set.empty
    TyVar name -> Set.singleton name
    TyCon {} -> Set.empty
    TyApp fn arg -> collect fn <> collect arg
    TyFun arg result -> collect arg <> collect result
    TyTuple fields -> Set.unions (map collect fields)
    TyList elementType -> collect elementType

replaceTypeVars :: Map.Map RName MonoType -> MonoType -> MonoType
replaceTypeVars replacements = \case
  TyMeta meta -> TyMeta meta
  TyVar name -> Map.findWithDefault (TyVar name) name replacements
  TyCon name -> TyCon name
  TyApp fn arg -> TyApp (replaceTypeVars replacements fn) (replaceTypeVars replacements arg)
  TyFun arg result -> TyFun (replaceTypeVars replacements arg) (replaceTypeVars replacements result)
  TyTuple fields -> TyTuple (map (replaceTypeVars replacements) fields)
  TyList elementType -> TyList (replaceTypeVars replacements elementType)

replaceMetasWithVars :: Map.Map Int RName -> MonoType -> MonoType
replaceMetasWithVars replacements = \case
  TyMeta meta ->
    maybe (TyMeta meta) TyVar (Map.lookup meta replacements)
  TyVar name ->
    TyVar name
  TyCon name ->
    TyCon name
  TyApp fn arg ->
    TyApp (replaceMetasWithVars replacements fn) (replaceMetasWithVars replacements arg)
  TyFun arg result ->
    TyFun (replaceMetasWithVars replacements arg) (replaceMetasWithVars replacements result)
  TyTuple fields ->
    TyTuple (map (replaceMetasWithVars replacements) fields)
  TyList elementType ->
    TyList (replaceMetasWithVars replacements elementType)

bindingToCore :: Subst -> Map.Map Int RName -> TypedBinding -> Either TypecheckError CoreBind
bindingToCore subst ambientMetas binding = do
  let scheme = typedBindingScheme binding
      allMetas = Map.union (typedBindingGeneralizedMetas binding) ambientMetas
  binderTy <- schemeToCoreType scheme
  rhs <- exprToCore subst allMetas (typedBindingRhs binding)
  let rhsWithTypeLambdas =
        case schemeVars scheme of
          [] -> rhs
          variables -> CTypeLam variables rhs binderTy
  pure (CoreNonRec (CoreBinder (typedBindingName binding) binderTy) rhsWithTypeLambdas)

bindPairs :: CoreBind -> [(CoreBinder, CoreExpr)]
bindPairs = \case
  CoreNonRec binder rhs -> [(binder, rhs)]
  CoreRec pairs -> pairs

exprToCore :: Subst -> Map.Map Int RName -> TypedExpr -> Either TypecheckError CoreExpr
exprToCore subst metas = \case
  TVar name scheme typeArguments ty -> do
    varTy <- schemeToCoreTypeWith subst metas scheme
    resultTy <- monoToCoreType subst metas ty
    coreTypeArguments <- traverse (monoToCoreType subst metas) typeArguments
    let varExpr = CVar name varTy
    pure $
      case schemeVars scheme of
        [] -> CVar name resultTy
        _ -> CTypeApp varExpr coreTypeArguments resultTy
  TLit literal ty ->
    CLit literal <$> monoToCoreType subst metas ty
  TCon name ty ->
    CCon name <$> monoToCoreType subst metas ty
  TLam binder body ty -> do
    coreBinder <- typedBinderToCore subst metas binder
    coreBody <- exprToCore subst metas body
    coreTy <- monoToCoreType subst metas ty
    pure (CLam coreBinder coreBody coreTy)
  TApp fn arg ty -> do
    coreFn <- exprToCore subst metas fn
    coreArg <- exprToCore subst metas arg
    coreTy <- monoToCoreType subst metas ty
    pure (CApp coreFn coreArg coreTy)
  TLet bindings body ty -> do
    coreBindings <- traverse (bindingToCore subst metas) bindings
    coreBody <- exprToCore subst metas body
    coreTy <- monoToCoreType subst metas ty
    pure
      ( CLet
          (case coreBindings of
            [] -> CoreRec []
            [one] -> one
            many -> CoreRec (concatMap bindPairs many)
          )
          coreBody
          coreTy
      )
  TCase scrutinee binder alternatives ty -> do
    coreScrutinee <- exprToCore subst metas scrutinee
    coreBinder <- typedBinderToCore subst metas binder
    coreAlternatives <- traverse (altToCore subst metas) alternatives
    coreTy <- monoToCoreType subst metas ty
    pure (CCase coreScrutinee coreBinder coreAlternatives coreTy)
  TPrim op arguments ty -> do
    coreArguments <- traverse (exprToCore subst metas) arguments
    coreTy <- monoToCoreType subst metas ty
    pure (CPrimOp op coreArguments coreTy)

altToCore :: Subst -> Map.Map Int RName -> TypedAlt -> Either TypecheckError CoreAlt
altToCore subst metas (TypedAlt altCon binders body) =
  CoreAlt altCon
    <$> traverse (typedBinderToCore subst metas) binders
    <*> exprToCore subst metas body

typedBinderToCore :: Subst -> Map.Map Int RName -> TypedBinder -> Either TypecheckError CoreBinder
typedBinderToCore subst metas (TypedBinder name ty) =
  CoreBinder name <$> monoToCoreType subst metas ty

schemeToCoreType :: Scheme -> Either TypecheckError CoreType
schemeToCoreType =
  schemeToCoreTypeWith Map.empty Map.empty

schemeToCoreTypeWith :: Subst -> Map.Map Int RName -> Scheme -> Either TypecheckError CoreType
schemeToCoreTypeWith subst metas (Scheme variables ty) = do
  body <- monoToCoreType subst metas ty
  pure $
    case variables of
      [] -> body
      _ -> CTyForall variables body

monoToCoreType :: Subst -> Map.Map Int RName -> MonoType -> Either TypecheckError CoreType
monoToCoreType subst metas ty =
  go (applySubst subst ty)
 where
  go = \case
    TyMeta meta ->
      maybe (Left (AmbiguousTypeVariable meta)) (Right . CTyVar) (Map.lookup meta metas)
    TyVar name ->
      Right (CTyVar name)
    TyCon name ->
      Right (CTyCon name)
    TyApp fn arg ->
      CTyApp <$> go fn <*> go arg
    TyFun arg result ->
      CTyFun <$> go arg <*> go result
    TyTuple fields ->
      CTyTuple <$> traverse go fields
    TyList elementType ->
      CTyList <$> go elementType

typedExprType :: TypedExpr -> MonoType
typedExprType = \case
  TVar _ _ _ ty -> ty
  TLit _ ty -> ty
  TCon _ ty -> ty
  TLam _ _ ty -> ty
  TApp _ _ ty -> ty
  TLet _ _ ty -> ty
  TCase _ _ _ ty -> ty
  TPrim _ _ ty -> ty

typedBinderName :: TypedBinder -> RName
typedBinderName (TypedBinder name _) =
  name

typedBinderType :: TypedBinder -> MonoType
typedBinderType (TypedBinder _ ty) =
  ty

schemeVars :: Scheme -> [RName]
schemeVars (Scheme variables _) =
  variables

schemeBody :: Scheme -> MonoType
schemeBody (Scheme _ body) =
  body

freshMeta :: InferM MonoType
freshMeta = do
  state <- get
  let meta = nextMeta state
  modify $ \current -> current {nextMeta = meta + 1}
  pure (TyMeta meta)

freshGeneratedName :: Namespace -> Text -> InferM RName
freshGeneratedName namespace occurrence = do
  state <- get
  let unique = nextGeneratedUnique state
  modify $ \current -> current {nextGeneratedUnique = unique + 1}
  pure
    RName
      { nameNamespace = namespace
      , nameOcc = occurrence
      , nameUnique = unique
      , nameExternal = False
      }

freshTypeVariableName :: Int -> InferM RName
freshTypeVariableName meta =
  freshGeneratedName TypeVariableNamespace ("t" <> Text.pack (show meta))

freshTermBinder :: Text -> MonoType -> InferM TypedBinder
freshTermBinder occurrence ty =
  (`TypedBinder` ty) <$> freshGeneratedName TermNamespace occurrence

literalMonoType :: Literal -> MonoType
literalMonoType = \case
  LInt {} -> intMonoType
  LChar {} -> charMonoType
  LString {} -> stringMonoType

intMonoType :: MonoType
intMonoType =
  coreTypeToMono intTy

boolMonoType :: MonoType
boolMonoType =
  coreTypeToMono boolTy

charMonoType :: MonoType
charMonoType =
  coreTypeToMono charTy

stringMonoType :: MonoType
stringMonoType =
  coreTypeToMono stringTy

coreTypeToMono :: CoreType -> MonoType
coreTypeToMono = \case
  CTyVar name -> TyVar name
  CTyCon name -> TyCon name
  CTyApp fn arg -> TyApp (coreTypeToMono fn) (coreTypeToMono arg)
  CTyFun arg result -> TyFun (coreTypeToMono arg) (coreTypeToMono result)
  CTyForall _ _ -> error "Core-0 monotypes cannot contain forall"
  CTyTuple fields -> TyTuple (map coreTypeToMono fields)
  CTyList elementType -> TyList (coreTypeToMono elementType)

zipWithM_ :: Monad m => (a -> b -> m c) -> [a] -> [b] -> m ()
zipWithM_ f lhs rhs =
  sequence_ (zipWith f lhs rhs)

throwTypecheck :: TypecheckError -> InferM a
throwTypecheck =
  lift . Left

renderMonoType :: MonoType -> Text
renderMonoType =
  renderMonoTypePrec 0

renderMonoTypePrec :: Int -> MonoType -> Text
renderMonoTypePrec contextPrec = \case
  TyMeta meta -> "?" <> renderInt meta
  TyVar name -> renderRName name
  TyCon name -> renderRName name
  TyApp fn arg ->
    parensIf (contextPrec > 1) $
      renderMonoTypePrec 1 fn <> " " <> renderMonoTypePrec 2 arg
  TyFun arg result ->
    parensIf (contextPrec > 0) $
      renderMonoTypePrec 1 arg <> " -> " <> renderMonoTypePrec 0 result
  TyTuple fields ->
    "(" <> Text.intercalate ", " (map renderMonoType fields) <> ")"
  TyList elementType ->
    "[" <> renderMonoType elementType <> "]"

renderPatternShape :: RPat -> Text
renderPatternShape = \case
  RPVar name -> "variable `" <> renderRName name <> "`"
  RPCon name _ -> "constructor `" <> renderRName name <> "`"
  RPLit literal -> "literal `" <> Text.pack (show literal) <> "`"
  RPWildcard -> "wildcard"
  RPTuple {} -> "tuple"
  RPList {} -> "list"
  RPAs name _ -> "as-pattern `" <> renderRName name <> "`"
  RPIrrefutable {} -> "irrefutable pattern"
  RPParen pat -> renderPatternShape pat

renderInt :: Int -> Text
renderInt =
  Text.pack . show

parensIf :: Bool -> Text -> Text
parensIf needsParens text
  | needsParens = "(" <> text <> ")"
  | otherwise = text
