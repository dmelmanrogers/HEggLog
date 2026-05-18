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

data STGLowerError
  = STGLowerInvalidCore [CoreValidate.CoreValidationError]
  | STGLowerInvalidSTG [STGValidate.STGValidationError]
  | STGLowerUnsupported Text
  deriving stock (Show, Eq)

data LowerState = LowerState
  { lowerNextUnique :: Int
  }
  deriving stock (Show, Eq)

type LowerM = StateT LowerState (Either STGLowerError)

data ValueApp = ValueApp CoreExpr CoreType
  deriving stock (Show, Eq, Ord)

lowerCoreModule :: CoreModule -> Either STGLowerError STGProgram
lowerCoreModule coreModule =
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv coreModule) coreModule of
    Left errors -> Left (STGLowerInvalidCore errors)
    Right () -> do
      program <-
        runLowerWith
          (namesInModule coreModule)
          ( STGProgram (coreModuleConstructors coreModule)
              <$> traverse lowerBind (coreModuleBinds coreModule)
          )
      case STGValidate.validateProgram program of
        Left errors -> Left (STGLowerInvalidSTG errors)
        Right () -> Right program

lowerCoreBind :: CoreBind -> Either STGLowerError STGBind
lowerCoreBind coreBind =
  runLowerWith (namesInBind coreBind) (lowerBind coreBind)

lowerCoreExpr :: CoreExpr -> Either STGLowerError STGExpr
lowerCoreExpr expression =
  case CoreValidate.validateExpr expression of
    Left errors -> Left (STGLowerInvalidCore errors)
    Right () -> do
      stgExpr <- runLowerWith (namesInExpr expression) (lowerExpr expression)
      case STGValidate.validateExpr stgExpr of
        Left errors -> Left (STGLowerInvalidSTG errors)
        Right () -> Right stgExpr

runLowerWith :: [RName] -> LowerM a -> Either STGLowerError a
runLowerWith names action =
  fst <$> runStateT action initialState
 where
  initialState =
    LowerState
      { lowerNextUnique = maximum (1000000 : map nameUnique names) + 1
      }

lowerBind :: CoreBind -> LowerM STGBind
lowerBind = \case
  CoreNonRec binder rhs ->
    STGNonRec (lowerBinder binder) <$> lowerRhs rhs
  CoreRec pairs ->
    STGRec <$> traverse lowerPair pairs
 where
  lowerPair (binder, rhs) = do
    loweredRhs <- lowerRhs rhs
    pure (lowerBinder binder, loweredRhs)

lowerRhs :: CoreExpr -> LowerM STGRhs
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
      STGFunction [lowerBinder binder] <$> lowerExpr body
    CCon name ty ->
      pure (STGConstructor name [] ty)
    other ->
      STGThunk Updatable <$> lowerExpr other

lowerConstructorRhs :: RName -> [CoreExpr] -> CoreType -> LowerM STGRhs
lowerConstructorRhs name fields resultTy = do
  (binds, atoms) <- atomizeMany fields
  if null binds
    then pure (STGConstructor name atoms resultTy)
    else STGThunk Updatable <$> constructorValueExpr binds name atoms resultTy

lowerExpr :: CoreExpr -> LowerM STGExpr
lowerExpr expression =
  case collectConstructorApplication expression of
    Just (name, fields, resultTy) -> do
      (binds, atoms) <- atomizeMany fields
      constructorValueExpr binds name atoms resultTy
    Nothing ->
      case expression of
        CVar name ty ->
          pure (STGAtom (STGVar name ty))
        CLit literal ty ->
          pure (STGAtom (STGLit literal ty))
        CCon name ty ->
          pure (STGAtom (STGCon name ty))
        CLam {} ->
          lowerLambdaValue expression
        CApp {} ->
          lowerApplication expression
        CTypeLam _ body _ ->
          lowerExpr body
        CTypeApp fn _ ty ->
          retagExpr ty <$> lowerExpr fn
        CLet bind body ty ->
          STGLet <$> lowerBind bind <*> lowerExpr body <*> pure ty
        CCase scrutinee binder alternatives ty ->
          STGCase
            <$> lowerExpr scrutinee
            <*> pure (lowerBinder binder)
            <*> traverse lowerAlt alternatives
            <*> pure ty
        CPrimOp op arguments ty -> do
          (binds, atoms) <- atomizeMany arguments
          pure (wrapLets binds (STGPrim op atoms ty))

lowerApplication :: CoreExpr -> LowerM STGExpr
lowerApplication expression = do
  let (calleeExpr, valueApps) = collectValueApps expression
  (calleeBinds, calleeName) <- atomizeCallee calleeExpr
  lowerApplicationChain calleeBinds calleeName valueApps

lowerApplicationChain :: [STGBind] -> RName -> [ValueApp] -> LowerM STGExpr
lowerApplicationChain prefixBinds calleeName = \case
  [] ->
    throwLower (STGLowerUnsupported ("empty Core application spine in " <> renderCoreExpr (CVar calleeName unitTy)))
  [ValueApp argument resultTy] -> do
    (argumentBinds, argumentAtom) <- atomizeExpr argument
    pure (wrapLets (prefixBinds <> argumentBinds) (STGApp calleeName [argumentAtom] resultTy))
  ValueApp argument resultTy : rest -> do
    (argumentBinds, argumentAtom) <- atomizeExpr argument
    tmpBinder <- freshBinder resultTy
    let partialBind =
          STGNonRec
            tmpBinder
            (STGThunk SingleEntry (STGApp calleeName [argumentAtom] resultTy))
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
atomizeExpr expression =
  case atomFromExpr expression of
    Just atom ->
      pure ([], atom)
    Nothing -> do
      let ty = runtimeExprType expression
      binder <- freshBinder ty
      rhs <- lowerRhs expression
      pure ([STGNonRec binder rhs], STGVar (stgBinderName binder) ty)

atomFromExpr :: CoreExpr -> Maybe STGAtom
atomFromExpr = \case
  CVar name ty ->
    Just (STGVar name ty)
  CLit literal ty ->
    Just (STGLit literal ty)
  CCon name ty ->
    Just (STGCon name ty)
  CTypeApp fn _ ty ->
    retagAtom ty <$> atomFromExpr fn
  _ ->
    Nothing

constructorValueExpr :: [STGBind] -> RName -> [STGAtom] -> CoreType -> LowerM STGExpr
constructorValueExpr prefixBinds name atoms resultTy = do
  binder <- freshBinder resultTy
  let constructorBind = STGNonRec binder (STGConstructor name atoms resultTy)
  pure (wrapLets (prefixBinds <> [constructorBind]) (STGAtom (STGVar (stgBinderName binder) resultTy)))

lowerLambdaValue :: CoreExpr -> LowerM STGExpr
lowerLambdaValue expression = do
  let ty = runtimeExprType expression
  binder <- freshBinder ty
  rhs <- lowerRhs expression
  pure (STGLet (STGNonRec binder rhs) (STGAtom (STGVar (stgBinderName binder) ty)) ty)

lowerAlt :: CoreAlt -> LowerM STGAlt
lowerAlt (CoreAlt altCon binders body) =
  STGAlt altCon (map lowerBinder binders) <$> lowerExpr body

lowerBinder :: CoreBinder -> STGBinder
lowerBinder (CoreBinder name ty) =
  STGBinder name ty

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

collectValueApps :: CoreExpr -> (CoreExpr, [ValueApp])
collectValueApps =
  go []
 where
  go apps = \case
    CApp fn argument resultTy ->
      go (ValueApp argument resultTy : apps) fn
    CTypeApp fn _ _ ->
      go apps fn
    other ->
      (other, apps)

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
  CTypeLam _ body _ -> stripTypeLambdas body
  other -> other

stripTypeApplications :: CoreExpr -> CoreExpr
stripTypeApplications = \case
  CTypeApp fn _ _ -> stripTypeApplications fn
  other -> other

runtimeExprType :: CoreExpr -> CoreType
runtimeExprType = \case
  CTypeLam _ body _ ->
    runtimeExprType body
  CTypeApp _ _ ty ->
    ty
  other ->
    exprType other

retagExpr :: CoreType -> STGExpr -> STGExpr
retagExpr ty = \case
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
namesInModule (CoreModule _ constructors binds) =
  concatMap namesInConstructorInfo (Map.elems constructors) <> concatMap namesInBind binds

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
  CPrimOp _ arguments ty ->
    concatMap namesInExpr arguments <> namesInType ty

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
