module Haskell2010.STG.Lower
  ( STGLowerError (..)
  , lowerCoreBind
  , lowerCoreExpr
  , lowerCoreModule
  , renderSTGLowerError
  )
where

import Control.Monad.State.Strict (StateT, get, lift, modify, runStateT)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Pretty (renderCoreExpr)
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names (Namespace (..), RName (..))
import Haskell2010.STG.Syntax
import qualified Haskell2010.STG.Validate as STGValidate
import Syntax.Span (SourceSpan)

data STGLowerError
  = STGLowerInvalidCore [CoreValidate.CoreValidationError]
  | STGLowerInvalidSTG [STGValidate.STGValidationError]
  | STGLowerUnsupported Text
  deriving stock (Show, Eq)

data LowerState = LowerState
  { lowerNextUnique :: Int
  , lowerValidationEnv :: CoreValidate.CoreValidationEnv
  , lowerCurrentSource :: Maybe SourceSpan
  }
  deriving stock (Show, Eq)

type LowerM = StateT LowerState (Either STGLowerError)

data ValueApp = ValueApp CoreExpr CoreType
  deriving stock (Show, Eq, Ord)

lowerCoreModule :: CoreModule -> Either STGLowerError STGProgram
lowerCoreModule coreModule =
  case CoreValidate.validateModule validationEnv coreModule of
    Left errors -> Left (STGLowerInvalidCore errors)
    Right () -> do
      program <-
        runLowerWith
          validationEnv
          (namesInModule coreModule)
          ( STGProgram (coreModuleConstructors coreModule)
              <$> traverse lowerBind (coreModuleBinds coreModule)
              <*> traverse runtimeForeignExport (coreModuleForeignExports coreModule)
              <*> pure (coreModuleRuntimeSpans coreModule)
          )
      case STGValidate.validateProgram program of
        Left errors -> Left (STGLowerInvalidSTG errors)
        Right () -> Right program
 where
  validationEnv =
    CoreValidate.moduleValidationEnv coreModule

lowerCoreBind :: CoreBind -> Either STGLowerError STGBind
lowerCoreBind coreBind =
  runLowerWith CoreValidate.defaultValidationEnv (namesInBind coreBind) (lowerBind coreBind)

runtimeForeignExport :: CoreForeignExport -> LowerM CoreForeignExport
runtimeForeignExport foreignExport = do
  runtimeTy <- runtimeType (coreForeignExportType foreignExport)
  pure foreignExport {coreForeignExportType = runtimeTy}

lowerCoreExpr :: CoreExpr -> Either STGLowerError STGExpr
lowerCoreExpr expression =
  case CoreValidate.validateExpr expression of
    Left errors -> Left (STGLowerInvalidCore errors)
    Right () -> do
      stgExpr <- runLowerWith CoreValidate.defaultValidationEnv (namesInExpr expression) (lowerExpr expression)
      case STGValidate.validateExpr stgExpr of
        Left errors -> Left (STGLowerInvalidSTG errors)
        Right () -> Right stgExpr

runLowerWith :: CoreValidate.CoreValidationEnv -> [RName] -> LowerM a -> Either STGLowerError a
runLowerWith validationEnv names action =
  fst <$> runStateT action initialState
 where
  initialState =
    LowerState
      { lowerNextUnique = maximum (1000000 : map nameUnique names) + 1
      , lowerValidationEnv = validationEnv
      , lowerCurrentSource = Nothing
      }

lowerBind :: CoreBind -> LowerM STGBind
lowerBind = \case
  CoreNonRec binder rhs -> do
    stgBinder <- lowerBinder binder
    STGNonRec stgBinder <$> lowerRhs rhs
  CoreRec pairs ->
    STGRec <$> traverse lowerPair pairs
 where
  lowerPair (binder, rhs) = do
    stgBinder <- lowerBinder binder
    loweredRhs <- lowerRhs rhs
    pure (stgBinder, loweredRhs)

lowerRhs :: CoreExpr -> LowerM STGRhs
lowerRhs (CSpanned sourceRange expression) =
  withLowerSource sourceRange (addRhsSourceSpan sourceRange <$> lowerRhs expression)
lowerRhs expression =
  case collectConstructorApplication expression of
    Just (name, fields, resultTy) ->
      lowerConstructorRhs name fields resultTy
    Nothing ->
      lowerNonConstructorRhs expression

lowerNonConstructorRhs :: CoreExpr -> LowerM STGRhs
lowerNonConstructorRhs expression =
  case stripTypeLambdas expression of
    CLam binder body _ ->
      STGFunction <$> ((: []) <$> lowerBinder binder) <*> lowerExpr body
    CCon name ty ->
      STGConstructor name [] <$> runtimeType ty
    other ->
      STGThunk (updateFlagForThunkType (exprType other)) <$> lowerExpr other

addRhsSourceSpan :: SourceSpan -> STGRhs -> STGRhs
addRhsSourceSpan sourceRange = \case
  STGFunction binders body ->
    STGFunction binders (STGSpanned sourceRange body)
  STGThunk updateFlag body ->
    STGThunk updateFlag (STGSpanned sourceRange body)
  constructor@STGConstructor {} ->
    constructor

lowerConstructorRhs :: RName -> [CoreExpr] -> CoreType -> LowerM STGRhs
lowerConstructorRhs name fields resultTy = do
  (binds, atoms) <- atomizeMany fields
  resultRuntimeTy <- runtimeType resultTy
  if null binds
    then pure (STGConstructor name atoms resultRuntimeTy)
    else STGThunk Updatable <$> constructorValueExpr binds name atoms resultRuntimeTy

lowerExpr :: CoreExpr -> LowerM STGExpr
lowerExpr expression =
  case collectConstructorApplication expression of
    Just (name, fields, resultTy) -> do
      (binds, atoms) <- atomizeMany fields
      constructorValueExpr binds name atoms resultTy
    Nothing ->
      case expression of
        CVar name ty ->
          STGAtom . STGVar name <$> runtimeType ty
        CLit literal ty ->
          STGAtom . STGLit literal <$> runtimeType ty
        CCon name ty ->
          STGAtom . STGCon name <$> runtimeType ty
        CSpanned sourceRange inner ->
          withLowerSource sourceRange (STGSpanned sourceRange <$> lowerExpr inner)
        CLam {} ->
          lowerLambdaValue expression
        CApp {} ->
          lowerApplication expression
        CTypeLam _ body _ ->
          lowerExpr body
        CTypeApp fn _ ty ->
          retagExpr <$> runtimeType ty <*> lowerExpr fn
        CLet bind body ty ->
          STGLet <$> lowerBind bind <*> lowerExpr body <*> runtimeType ty
        CCase scrutinee binder alternatives ty ->
          STGCase
            <$> lowerExpr scrutinee
            <*> lowerBinder binder
            <*> traverse lowerAlt alternatives
            <*> runtimeType ty
        CCoerce inner ty ->
          retagExpr <$> runtimeType ty <*> lowerExpr inner
        CPrimOp op arguments ty -> do
          (binds, atoms) <- atomizeMany arguments
          ty' <- runtimeType ty
          pure (wrapLets binds (STGPrim op atoms ty'))
        CForeignCall foreignImport arguments ty -> do
          (binds, atoms) <- atomizeMany arguments
          ty' <- runtimeType ty
          foreignImport' <- runtimeForeignImport foreignImport
          pure (wrapLets binds (STGForeignCall foreignImport' atoms ty'))
        CForeignImportValue foreignImport ty -> do
          foreignImport' <- runtimeForeignImport foreignImport
          STGForeignImportValue foreignImport' <$> runtimeType ty

lowerApplication :: CoreExpr -> LowerM STGExpr
lowerApplication expression = do
  let (calleeExpr, valueApps) = collectValueApps expression
  (calleeBinds, calleeName) <- atomizeCallee calleeExpr
  case applicationCalleeSource expression of
    Nothing ->
      lowerApplicationChain calleeBinds calleeName valueApps
    Just sourceRange ->
      withLowerSource sourceRange (STGSpanned sourceRange <$> lowerApplicationChain calleeBinds calleeName valueApps)

lowerApplicationChain :: [STGBind] -> RName -> [ValueApp] -> LowerM STGExpr
lowerApplicationChain prefixBinds calleeName = \case
  [] ->
    throwLower (STGLowerUnsupported ("empty Core application spine in " <> renderCoreExpr (CVar calleeName unitTy)))
  [ValueApp argument resultTy] -> do
    (argumentBinds, argumentAtom) <- atomizeExpr argument
    resultRuntimeTy <- runtimeType resultTy
    pure (wrapLets (prefixBinds <> argumentBinds) (STGApp calleeName [argumentAtom] resultRuntimeTy))
  ValueApp argument resultTy : rest -> do
    (argumentBinds, argumentAtom) <- atomizeExpr argument
    resultRuntimeTy <- runtimeType resultTy
    tmpBinder <- freshBinder resultRuntimeTy
    partialBody <- withCurrentSource (STGApp calleeName [argumentAtom] resultRuntimeTy)
    let partialBind =
          STGNonRec
            tmpBinder
            (STGThunk SingleEntry partialBody)
    lowerApplicationChain
      (prefixBinds <> argumentBinds <> [partialBind])
      (stgBinderName tmpBinder)
      rest

atomizeCallee :: CoreExpr -> LowerM ([STGBind], RName)
atomizeCallee expression =
  case stripTypeApplications expression of
    CVar name _ ->
      pure ([], name)
    other -> do
      (binds, atom) <- atomizeExpr other
      case atom of
        STGVar name _ ->
          pure (binds, name)
        _ ->
          throwLower (STGLowerUnsupported ("non-function Core callee " <> renderCoreExpr expression))

atomizeMany :: [CoreExpr] -> LowerM ([STGBind], [STGAtom])
atomizeMany =
  go [] []
 where
  go binds atoms [] =
    pure (binds, atoms)
  go binds atoms (expression : rest) = do
    (newBinds, atom) <- atomizeExpr expression
    go (binds <> newBinds) (atoms <> [atom]) rest

atomizeExpr :: CoreExpr -> LowerM ([STGBind], STGAtom)
atomizeExpr expression = do
  maybeAtom <- atomFromExpr expression
  case maybeAtom of
    Just atom ->
      pure ([], atom)
    Nothing -> do
      ty <- runtimeExprType expression
      binder <- freshBinder ty
      rhs <- lowerRhs expression
      pure ([STGNonRec binder rhs], STGVar (stgBinderName binder) ty)

atomFromExpr :: CoreExpr -> LowerM (Maybe STGAtom)
atomFromExpr expression =
  case expression of
    CVar name ty ->
      Just . STGVar name <$> runtimeType ty
    CLit literal ty ->
      Just . STGLit literal <$> runtimeType ty
    CCon name ty ->
      Just . STGCon name <$> runtimeType ty
    CSpanned _ inner ->
      atomFromExpr inner
    CTypeApp fn _ ty -> do
      ty' <- runtimeType ty
      fmap (retagAtom ty') <$> atomFromExpr fn
    CCoerce inner ty -> do
      ty' <- runtimeType ty
      fmap (retagAtom ty') <$> atomFromExpr inner
    _ ->
      pure Nothing

constructorValueExpr :: [STGBind] -> RName -> [STGAtom] -> CoreType -> LowerM STGExpr
constructorValueExpr prefixBinds name atoms resultTy = do
  resultRuntimeTy <- runtimeType resultTy
  binder <- freshBinder resultRuntimeTy
  let constructorBind = STGNonRec binder (STGConstructor name atoms resultRuntimeTy)
  pure (wrapLets (prefixBinds <> [constructorBind]) (STGAtom (STGVar (stgBinderName binder) resultRuntimeTy)))

lowerLambdaValue :: CoreExpr -> LowerM STGExpr
lowerLambdaValue expression = do
  ty <- runtimeExprType expression
  binder <- freshBinder ty
  rhs <- lowerRhs expression
  pure (STGLet (STGNonRec binder rhs) (STGAtom (STGVar (stgBinderName binder) ty)) ty)

lowerAlt :: CoreAlt -> LowerM STGAlt
lowerAlt (CoreAlt altCon binders body) =
  STGAlt altCon <$> traverse lowerBinder binders <*> lowerExpr body

lowerBinder :: CoreBinder -> LowerM STGBinder
lowerBinder (CoreBinder name ty) =
  STGBinder name <$> runtimeType ty

freshBinder :: CoreType -> LowerM STGBinder
freshBinder ty = do
  state <- get
  let unique = lowerNextUnique state
  modify $ \current -> current {lowerNextUnique = unique + 1}
  pure
    STGBinder
      { stgBinderName =
          RName
            { nameNamespace = TermNamespace
            , nameOcc = "$stg"
            , nameUnique = unique
            , nameExternal = False
            }
      , stgBinderType = ty
      }

withLowerSource :: SourceSpan -> LowerM a -> LowerM a
withLowerSource sourceRange action = do
  previous <- lowerCurrentSource <$> get
  modify $ \state -> state {lowerCurrentSource = Just sourceRange}
  result <- action
  modify $ \state -> state {lowerCurrentSource = previous}
  pure result

withCurrentSource :: STGExpr -> LowerM STGExpr
withCurrentSource expression = do
  maybeSource <- lowerCurrentSource <$> get
  pure $
    case maybeSource of
      Nothing -> expression
      Just sourceRange -> STGSpanned sourceRange expression

collectValueApps :: CoreExpr -> (CoreExpr, [ValueApp])
collectValueApps =
  go []
 where
  go apps = \case
    CApp fn argument resultTy ->
      go (ValueApp argument resultTy : apps) fn
    CSpanned _ inner ->
      go apps inner
    CTypeApp fn _ _ ->
      go apps fn
    other ->
      (other, apps)

applicationCalleeSource :: CoreExpr -> Maybe SourceSpan
applicationCalleeSource = \case
  CSpanned sourceRange _ ->
    Just sourceRange
  CApp fn _ _ ->
    applicationCalleeSource fn
  CTypeApp fn _ _ ->
    applicationCalleeSource fn
  CCoerce expression _ ->
    applicationCalleeSource expression
  _ ->
    Nothing

collectConstructorApplication :: CoreExpr -> Maybe (RName, [CoreExpr], CoreType)
collectConstructorApplication expression =
  case collectValueApps expression of
    (_, []) ->
      Nothing
    (constructorExpr, valueApps) ->
      case stripTypeApplications constructorExpr of
        CCon name _ ->
          Just (name, [argument | ValueApp argument _ <- valueApps], exprType expression)
        _ ->
          Nothing

stripTypeLambdas :: CoreExpr -> CoreExpr
stripTypeLambdas = \case
  CSpanned _ expression -> stripTypeLambdas expression
  CTypeLam _ body _ -> stripTypeLambdas body
  other -> other

stripTypeApplications :: CoreExpr -> CoreExpr
stripTypeApplications = \case
  CSpanned _ expression -> stripTypeApplications expression
  CTypeApp fn _ _ -> stripTypeApplications fn
  other -> other

runtimeExprType :: CoreExpr -> LowerM CoreType
runtimeExprType = \case
  CSpanned _ expression ->
    runtimeExprType expression
  CTypeLam _ body _ ->
    runtimeExprType body
  CTypeApp _ _ ty ->
    runtimeType ty
  other ->
    runtimeType (exprType other)

runtimeType :: CoreType -> LowerM CoreType
runtimeType ty = do
  env <- lowerValidationEnv <$> get
  pure (CoreValidate.eraseNewtypeType env ty)

retagExpr :: CoreType -> STGExpr -> STGExpr
retagExpr ty = \case
  STGSpanned sourceRange expression ->
    STGSpanned sourceRange (retagExpr ty expression)
  STGAtom atom ->
    STGAtom (retagAtom ty atom)
  STGApp callee arguments _ ->
    STGApp callee arguments ty
  STGLet bind body _ ->
    STGLet bind (retagExpr ty body) ty
  STGCase scrutinee binder alternatives _ ->
    STGCase scrutinee binder alternatives ty
  STGPrim op arguments _ ->
    STGPrim op arguments ty
  STGForeignCall foreignImport arguments _ ->
    STGForeignCall foreignImport arguments ty
  STGForeignImportValue foreignImport _ ->
    STGForeignImportValue foreignImport ty

retagAtom :: CoreType -> STGAtom -> STGAtom
retagAtom ty = \case
  STGVar name _ ->
    STGVar name ty
  STGLit literal _ ->
    STGLit literal ty
  STGCon name _ ->
    STGCon name ty

wrapLets :: [STGBind] -> STGExpr -> STGExpr
wrapLets binds body =
  foldr (\bind expr -> STGLet bind expr (stgExprType expr)) body binds

namesInModule :: CoreModule -> [RName]
namesInModule (CoreModule _ constructors binds exports _) =
  concatMap namesInConstructorInfo (Map.elems constructors)
    <> concatMap namesInBind binds
    <> map coreForeignExportName exports

namesInBind :: CoreBind -> [RName]
namesInBind = \case
  CoreNonRec binder rhs ->
    namesInBinder binder <> namesInExpr rhs
  CoreRec pairs ->
    concatMap (\(binder, rhs) -> namesInBinder binder <> namesInExpr rhs) pairs

namesInExpr :: CoreExpr -> [RName]
namesInExpr = \case
  CVar name ty ->
    name : namesInType ty
  CLit _ ty ->
    namesInType ty
  CCon name ty ->
    name : namesInType ty
  CSpanned _ expression ->
    namesInExpr expression
  CLam binder body ty ->
    namesInBinder binder <> namesInExpr body <> namesInType ty
  CApp fn argument ty ->
    namesInExpr fn <> namesInExpr argument <> namesInType ty
  CTypeLam variables body ty ->
    variables <> namesInExpr body <> namesInType ty
  CTypeApp fn arguments ty ->
    namesInExpr fn <> concatMap namesInType arguments <> namesInType ty
  CLet bind body ty ->
    namesInBind bind <> namesInExpr body <> namesInType ty
  CCase scrutinee binder alternatives ty ->
    namesInExpr scrutinee <> namesInBinder binder <> concatMap namesInAlt alternatives <> namesInType ty
  CCoerce expression ty ->
    namesInExpr expression <> namesInType ty
  CPrimOp _ arguments ty ->
    concatMap namesInExpr arguments <> namesInType ty
  CForeignCall foreignImport arguments ty ->
    namesInForeignImport foreignImport <> concatMap namesInExpr arguments <> namesInType ty
  CForeignImportValue foreignImport ty ->
    namesInForeignImport foreignImport <> namesInType ty

runtimeForeignImport :: CoreForeignImport -> LowerM CoreForeignImport
runtimeForeignImport foreignImport = do
  ty <- runtimeType (coreForeignImportType foreignImport)
  pure foreignImport {coreForeignImportType = ty}

namesInForeignImport :: CoreForeignImport -> [RName]
namesInForeignImport foreignImport =
  coreForeignImportName foreignImport : namesInType (coreForeignImportType foreignImport)

namesInAlt :: CoreAlt -> [RName]
namesInAlt (CoreAlt altCon binders body) =
  namesInAltCon altCon <> concatMap namesInBinder binders <> namesInExpr body

namesInAltCon :: CoreAltCon -> [RName]
namesInAltCon = \case
  ConstructorAlt name -> [name]
  _ -> []

namesInBinder :: CoreBinder -> [RName]
namesInBinder (CoreBinder name ty) =
  name : namesInType ty

namesInType :: CoreType -> [RName]
namesInType = \case
  CTyVar name -> [name]
  CTyCon name -> [name]
  CTyApp fn argument -> namesInType fn <> namesInType argument
  CTyFun argument result -> namesInType argument <> namesInType result
  CTyForall variables body -> variables <> namesInType body
  CTyTuple fields -> concatMap namesInType fields
  CTyList elementTy -> namesInType elementTy

namesInConstructorInfo :: CoreConstructorInfo -> [RName]
namesInConstructorInfo info =
  constructorTyVars info
    <> concatMap namesInType (constructorFields info)
    <> namesInType (constructorResult info)

throwLower :: STGLowerError -> LowerM a
throwLower =
  lift . Left

updateFlagForThunkType :: CoreType -> STGUpdateFlag
updateFlagForThunkType = \case
  CTyApp (CTyCon name) _
    | name == ioTyConName -> SingleEntry
  _ -> Updatable

renderSTGLowerError :: STGLowerError -> Text
renderSTGLowerError = \case
  STGLowerInvalidCore errors ->
    "invalid Core before STG lowering: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)
  STGLowerInvalidSTG errors ->
    "lowered STG failed validation: "
      <> Text.intercalate "; " (map STGValidate.renderSTGValidationError errors)
  STGLowerUnsupported message ->
    "unsupported Core-to-STG lowering form: " <> message
