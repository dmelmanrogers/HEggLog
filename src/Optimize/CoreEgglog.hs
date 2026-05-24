module Optimize.CoreEgglog
  ( CoreEgglogError (..)
  , CoreEgglogResult (..)
  , optimizeCoreModuleWithEgglog
  , renderCoreEgglogError
  , renderCoreEgglogStatus
  )
where

import Control.Monad.State.Strict (StateT, evalStateT, get, lift, modify', runStateT)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Eval (RunConfig)
import Egglog.Sort (renderFunctionName)
import Haskell2010.Core.FreeVars (freeVarsExpr)
import Haskell2010.Core.Pretty (renderCoreExpr, renderCoreType)
import Haskell2010.Core.Subst (substExpr)
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names (Namespace (TermNamespace), RName (..), nameOcc, nameUnique)
import Haskell2010.Syntax (Literal (..))
import IR.ANF
import qualified Optimize.EgglogBackend as ANFEgglog
import Syntax.AST (BinOp (..), Name (..), Type (..))

data CoreEgglogResult = CoreEgglogResult
  { coreEgglogOriginalModule :: CoreModule
  , coreEgglogOptimizedModule :: CoreModule
  , coreEgglogOriginalCost :: Int
  , coreEgglogOptimizedCost :: Int
  , coreEgglogAppliedRules :: [Text]
  , coreEgglogProvenanceTrace :: [Text]
  }
  deriving stock (Show, Eq)

data CoreEgglogError
  = CoreEgglogInvalidInput [CoreValidate.CoreValidationError]
  | CoreEgglogInvalidOutput [CoreValidate.CoreValidationError]
  | CoreEgglogBackendError ANFEgglog.EgglogBackendError
  | CoreEgglogUnsupportedType CoreType
  | CoreEgglogUnsupportedANF AExpr
  | CoreEgglogUnsupportedANFAtom Atom
  | CoreEgglogTypeMismatch CoreType CoreType
  | CoreEgglogUnknownANFName Name
  | CoreEgglogCannotConvert Text
  deriving stock (Show, Eq)

data OptimizeState = OptimizeState
  { optimizeNextUnique :: Int
  , optimizeAppliedRules :: [Text]
  , optimizeProvenance :: [Text]
  }
  deriving stock (Show, Eq)

type OptimizeM = StateT OptimizeState (Either CoreEgglogError)

data EncodedFragment = EncodedFragment
  { fragmentANF :: AExpr
  , fragmentNameTypes :: Map.Map Name CoreType
  , fragmentCoreNames :: Map.Map Name RName
  , fragmentNextUnique :: Int
  }
  deriving stock (Show, Eq)

data EncodeState = EncodeState
  { encodeNextTemp :: Int
  , encodeNameTypes :: Map.Map Name CoreType
  , encodeCoreNames :: Map.Map Name RName
  }
  deriving stock (Show, Eq)

type EncodeM = StateT EncodeState Maybe

data DecodeState = DecodeState
  { decodeNextUnique :: Int
  , decodeNameTypes :: Map.Map Name CoreType
  , decodeCoreNames :: Map.Map Name RName
  }
  deriving stock (Show, Eq)

type DecodeM = StateT DecodeState (Either CoreEgglogError)

data KnownCaseScrutinee
  = KnownCaseConstructor RName [CoreExpr]
  | KnownCaseLiteral Literal
  deriving stock (Show, Eq)

optimizeCoreModuleWithEgglog :: RunConfig -> CoreModule -> Either CoreEgglogError CoreEgglogResult
optimizeCoreModuleWithEgglog config coreModule = do
  let validationEnv = CoreValidate.moduleValidationEnv coreModule
  case CoreValidate.validateModule validationEnv coreModule of
    Left errors -> Left (CoreEgglogInvalidInput errors)
    Right () -> Right ()
  let initialState =
        OptimizeState
          { optimizeNextUnique = nextUniqueAfterModule coreModule
          , optimizeAppliedRules = []
          , optimizeProvenance = []
          }
      moduleScope = scopeFromBinds (coreModuleBinds coreModule)
  (optimizedBinds, finalState) <-
    runStateT (traverse (optimizeBind config validationEnv moduleScope) (coreModuleBinds coreModule)) initialState
  let optimizedModule = coreModule {coreModuleBinds = optimizedBinds}
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv optimizedModule) optimizedModule of
    Left errors -> Left (CoreEgglogInvalidOutput errors)
    Right () ->
      Right
        CoreEgglogResult
          { coreEgglogOriginalModule = coreModule
          , coreEgglogOptimizedModule = optimizedModule
          , coreEgglogOriginalCost = moduleCost coreModule
          , coreEgglogOptimizedCost = moduleCost optimizedModule
          , coreEgglogAppliedRules = uniqueTexts (optimizeAppliedRules finalState)
          , coreEgglogProvenanceTrace = optimizeProvenance finalState
          }

optimizeBind :: RunConfig -> CoreValidate.CoreValidationEnv -> Map.Map RName CoreType -> CoreBind -> OptimizeM CoreBind
optimizeBind config validationEnv env = \case
  CoreNonRec binder rhs -> do
    optimized <- optimizeExpr config validationEnv env rhs
    pure (CoreNonRec binder optimized)
  CoreRec pairs -> do
    let recEnv = Map.union (Map.fromList [(coreBinderName binder, coreBinderType binder) | (binder, _) <- pairs]) env
    CoreRec <$> traverse (optimizePair recEnv) pairs
 where
  optimizePair recEnv (binder, rhs) = do
    optimized <- optimizeExpr config validationEnv recEnv rhs
    pure (binder, optimized)

optimizeExpr :: RunConfig -> CoreValidate.CoreValidationEnv -> Map.Map RName CoreType -> CoreExpr -> OptimizeM CoreExpr
optimizeExpr config validationEnv env expression = do
  rebuilt <-
    case expression of
      CVar {} ->
        pure expression
      CLit {} ->
        pure expression
      CCon {} ->
        pure expression
      CLam binder body ty ->
        CLam binder <$> optimizeExpr config validationEnv (Map.insert (coreBinderName binder) (coreBinderType binder) env) body <*> pure ty
      CApp fn arg ty ->
        CApp <$> optimizeExpr config validationEnv env fn <*> optimizeExpr config validationEnv env arg <*> pure ty
      CTypeLam variables body ty ->
        CTypeLam variables <$> optimizeExpr config validationEnv env body <*> pure ty
      CTypeApp fn arguments ty ->
        CTypeApp <$> optimizeExpr config validationEnv env fn <*> pure arguments <*> pure ty
      CLet bind body ty -> do
        optimizedBind <- optimizeBind config validationEnv env bind
        let env' = Map.union (scopeFromBind optimizedBind) env
        CLet optimizedBind <$> optimizeExpr config validationEnv env' body <*> pure ty
      CCase scrutinee binder alternatives ty -> do
        optimizedScrutinee <- optimizeExpr config validationEnv env scrutinee
        let altEnvBase = Map.insert (coreBinderName binder) (coreBinderType binder) env
        optimizedAlts <- traverse (optimizeAlt altEnvBase) alternatives
        pure (CCase optimizedScrutinee binder optimizedAlts ty)
      CCoerce inner ty ->
        CCoerce <$> optimizeExpr config validationEnv env inner <*> pure ty
      CPrimOp op arguments ty ->
        CPrimOp op <$> traverse (optimizeExpr config validationEnv env) arguments <*> pure ty
      CForeignCall foreignImport arguments ty ->
        CForeignCall foreignImport <$> traverse (optimizeExpr config validationEnv env) arguments <*> pure ty
      CForeignImportValue {} ->
        pure expression
  tryEgglogRewrite config env rebuilt >>= tryKnownCaseRewrite validationEnv env
 where
  optimizeAlt altEnvBase (CoreAlt altCon binders body) = do
    let altEnv = Map.union (Map.fromList [(coreBinderName binder, coreBinderType binder) | binder <- binders]) altEnvBase
    CoreAlt altCon binders <$> optimizeExpr config validationEnv altEnv body

tryKnownCaseRewrite :: CoreValidate.CoreValidationEnv -> Map.Map RName CoreType -> CoreExpr -> OptimizeM CoreExpr
tryKnownCaseRewrite validationEnv env expression =
  case expression of
    CCase scrutinee binder alternatives ty ->
      case selectKnownCaseAlternative validationEnv scrutinee binder alternatives of
        Nothing ->
          pure expression
        Just (ruleName, selected) -> do
          let originalCost = expressionCost expression
              selectedCost = expressionCost selected
          if selectedCost < originalCost && exprType selected == ty
            then do
              validateSelected selected
              recordCoreRewrite ruleName expression selected originalCost selectedCost
              pure selected
            else pure expression
    _ ->
      pure expression
 where
  validateSelected selected =
    let localValidationEnv =
          validationEnv
            { CoreValidate.coreValueTypes =
                Map.union env (CoreValidate.coreValueTypes validationEnv)
            }
     in case CoreValidate.validateExprWith localValidationEnv selected of
          Left errors -> lift (Left (CoreEgglogInvalidOutput errors))
          Right () -> pure ()

recordCoreRewrite :: Text -> CoreExpr -> CoreExpr -> Int -> Int -> OptimizeM ()
recordCoreRewrite ruleName before after originalCost optimizedCost =
  modify' $
    \state ->
      state
        { optimizeAppliedRules = optimizeAppliedRules state <> [ruleName]
        , optimizeProvenance =
            optimizeProvenance state
              <> [ "selected Core rule "
                     <> ruleName
                     <> ": "
                     <> renderCoreExpr before
                     <> " ==> "
                     <> renderCoreExpr after
                 , "fragment cost: "
                     <> Text.pack (show originalCost)
                     <> " -> "
                     <> Text.pack (show optimizedCost)
                 ]
        }

selectKnownCaseAlternative ::
  CoreValidate.CoreValidationEnv ->
  CoreExpr ->
  CoreBinder ->
  [CoreAlt] ->
  Maybe (Text, CoreExpr)
selectKnownCaseAlternative validationEnv scrutinee binder alternatives = do
  known <- knownCaseScrutinee validationEnv scrutinee
  case known of
    KnownCaseConstructor constructorName fields ->
      selectConstructorAlternative scrutinee binder constructorName fields alternatives
    KnownCaseLiteral literal ->
      selectLiteralAlternative scrutinee binder literal alternatives

knownCaseScrutinee :: CoreValidate.CoreValidationEnv -> CoreExpr -> Maybe KnownCaseScrutinee
knownCaseScrutinee validationEnv expression =
  case expression of
    CLit literal _ ->
      Just (KnownCaseLiteral literal)
    _ ->
      uncurry KnownCaseConstructor <$> knownConstructorApplication validationEnv expression

knownConstructorApplication :: CoreValidate.CoreValidationEnv -> CoreExpr -> Maybe (RName, [CoreExpr])
knownConstructorApplication validationEnv expression = do
  (constructorName, fields) <- peelConstructorApplication expression []
  info <- Map.lookup constructorName (CoreValidate.coreConstructorTypes validationEnv)
  expectedFields <- CoreValidate.constructorFieldsForResult info (exprType expression)
  if length fields == length expectedFields && and (zipWith ((==) . exprType) fields expectedFields)
    then Just (constructorName, fields)
    else Nothing

peelConstructorApplication :: CoreExpr -> [CoreExpr] -> Maybe (RName, [CoreExpr])
peelConstructorApplication expression fields =
  case expression of
    CApp fn arg _ ->
      peelConstructorApplication fn (arg : fields)
    CTypeApp fn _ _ ->
      peelConstructorApplication fn fields
    CCon constructorName _ ->
      Just (constructorName, fields)
    _ ->
      Nothing

selectConstructorAlternative ::
  CoreExpr ->
  CoreBinder ->
  RName ->
  [CoreExpr] ->
  [CoreAlt] ->
  Maybe (Text, CoreExpr)
selectConstructorAlternative scrutinee binder constructorName fields alternatives =
  case matchingConstructorAlternatives of
    [(fieldBinders, body)]
      | length fieldBinders == length fields ->
          Just
            ( "core-case-known-constructor"
            , applyCaseSubstitutions scrutinee binder (zip fieldBinders fields) body
            )
    [] ->
      selectDefaultAlternative "core-case-known-constructor-default" scrutinee binder alternatives
    _ ->
      Nothing
 where
  matchingConstructorAlternatives =
    [ (fieldBinders, body)
    | CoreAlt (ConstructorAlt altConstructorName) fieldBinders body <- alternatives
    , altConstructorName == constructorName
    ]

selectLiteralAlternative :: CoreExpr -> CoreBinder -> Literal -> [CoreAlt] -> Maybe (Text, CoreExpr)
selectLiteralAlternative scrutinee binder literal alternatives =
  case matchingLiteralAlternatives of
    [body] ->
      Just ("core-case-known-literal", substExpr (coreBinderName binder) scrutinee body)
    [] ->
      selectDefaultAlternative "core-case-known-literal-default" scrutinee binder alternatives
    _ ->
      Nothing
 where
  matchingLiteralAlternatives =
    [ body
    | CoreAlt (LiteralAlt altLiteral) [] body <- alternatives
    , altLiteral == literal
    ]

selectDefaultAlternative :: Text -> CoreExpr -> CoreBinder -> [CoreAlt] -> Maybe (Text, CoreExpr)
selectDefaultAlternative ruleName scrutinee binder alternatives =
  case [body | CoreAlt DefaultAlt [] body <- alternatives] of
    [body] -> Just (ruleName, substExpr (coreBinderName binder) scrutinee body)
    _ -> Nothing

applyCaseSubstitutions :: CoreExpr -> CoreBinder -> [(CoreBinder, CoreExpr)] -> CoreExpr -> CoreExpr
applyCaseSubstitutions scrutinee binder fields body =
  foldl substituteField withCaseBinder fields
 where
  withCaseBinder =
    substExpr (coreBinderName binder) scrutinee body
  substituteField expression (fieldBinder, fieldExpr) =
    substExpr (coreBinderName fieldBinder) fieldExpr expression

tryEgglogRewrite :: RunConfig -> Map.Map RName CoreType -> CoreExpr -> OptimizeM CoreExpr
tryEgglogRewrite config env expression = do
  optimizerState <- get
  case encodeCoreFragment env expression of
    Nothing ->
      pure expression
    Just fragment ->
      case ANFEgglog.optimizeWithEgglog config (fragmentANF fragment) of
        Left err
          | isUnsupportedANFBackend err -> pure expression
        Left err
          | expressionCost expression <= 1 -> pure expression
          | otherwise -> lift (Left (CoreEgglogBackendError err))
        Right result -> do
          decoded <-
            lift $
              decodeANFFragment
                (fragmentNameTypes fragment)
                (fragmentCoreNames fragment)
                (max (fragmentNextUnique fragment) (optimizeNextUnique optimizerState))
                (exprType expression)
                (ANFEgglog.optimizedANF result)
          let decodedCost = expressionCost decoded
              originalCost = expressionCost expression
          if decodedCost < originalCost && decoded /= expression
            then do
              modify' $
                \state ->
                  state
                    { optimizeNextUnique = max (optimizeNextUnique state) (nextUniqueAfterExpr decoded)
                    , optimizeAppliedRules =
                        optimizeAppliedRules state
                          <> map (renderFunctionName . ANFEgglog.appliedRuleName) (ANFEgglog.appliedRules result)
                    , optimizeProvenance =
                        optimizeProvenance state
                          <> [ "optimized Core fragment: "
                                 <> renderCoreExpr expression
                                 <> " ==> "
                                 <> renderCoreExpr decoded
                             , "fragment cost: "
                                 <> Text.pack (show originalCost)
                                 <> " -> "
                                 <> Text.pack (show decodedCost)
                             ]
                          <> take 8 (ANFEgglog.provenanceTrace result)
                    }
              pure decoded
            else pure expression

isUnsupportedANFBackend :: ANFEgglog.EgglogBackendError -> Bool
isUnsupportedANFBackend = \case
  ANFEgglog.UnsupportedLambda {} -> True
  ANFEgglog.UnsupportedApplication {} -> True
  ANFEgglog.UnsupportedDirectCall {} -> True
  ANFEgglog.UnsupportedPrimitive {} -> True
  ANFEgglog.UnsupportedType {} -> True
  ANFEgglog.AmbiguousFreeVariable {} -> True
  ANFEgglog.UnboundResolvedBinder {} -> True
  ANFEgglog.FragmentTypeMismatch {} -> True
  ANFEgglog.InvalidIntLiteral {} -> True
  _ -> False

encodeCoreFragment :: Map.Map RName CoreType -> CoreExpr -> Maybe EncodedFragment
encodeCoreFragment env expression = do
  _ <- coreTypeToANFType (exprType expression)
  let initialState =
        EncodeState
          { encodeNextTemp = 0
          , encodeNameTypes = Map.empty
          , encodeCoreNames = Map.empty
          }
  (anf, finalState) <- runStateT (toANFExpr env expression) initialState
  pure
    EncodedFragment
      { fragmentANF = anf
      , fragmentNameTypes = encodeNameTypes finalState
      , fragmentCoreNames = encodeCoreNames finalState
      , fragmentNextUnique = nextUniqueAfterExpr expression
      }

toANFExpr :: Map.Map RName CoreType -> CoreExpr -> EncodeM AExpr
toANFExpr env expression =
  case expression of
    CVar name ty ->
      AAtom <$> toANFAtom env (CVar name ty)
    CLit literal ty ->
      AAtom <$> toANFAtom env (CLit literal ty)
    CCon name ty ->
      AAtom <$> toANFAtom env (CCon name ty)
    CPrimOp op [lhs, rhs] ty
      | Just anfOp <- corePrimToANF op -> do
          (lhsAtom, lhsWrap) <- atomize env lhs
          (rhsAtom, rhsWrap) <- atomize env rhs
          pure (lhsWrap (rhsWrap (APrim anfOp lhsAtom rhsAtom)))
      | otherwise -> unsupported
      where
        _ = ty
    CCoerce inner _ ->
      toANFExpr env inner
    CCase scrutinee binder alternatives ty
      | coreBinderName binder `Set.notMember` Set.unions [freeVarsExpr body | CoreAlt _ _ body <- alternatives]
      , Just (trueBody, falseBody) <- boolCaseBodies alternatives
      , coreTypeSupported ty -> do
          (condAtom, condWrap) <- atomize env scrutinee
          trueANF <- toANFExpr env trueBody
          falseANF <- toANFExpr env falseBody
          pure (condWrap (AIf condAtom trueANF falseANF))
      | otherwise -> unsupported
    _ ->
      unsupported
 where
  unsupported =
    lift Nothing

toANFAtom :: Map.Map RName CoreType -> CoreExpr -> EncodeM Atom
toANFAtom _env = \case
  CVar name ty -> do
    let anfName = coreNameToANF name
    modify' $
      \state ->
        state
          { encodeNameTypes = Map.insert anfName ty (encodeNameTypes state)
          , encodeCoreNames = Map.insert anfName name (encodeCoreNames state)
          }
    pure (AVar anfName)
  CLit (LInt value) ty
    | ty == intTy ->
        pure (AInt value)
  CCon name ty
    | ty == boolTy && name == trueDataConName ->
        pure (ABool True)
    | ty == boolTy && name == falseDataConName ->
        pure (ABool False)
  _ ->
    lift Nothing

atomize :: Map.Map RName CoreType -> CoreExpr -> EncodeM (Atom, AExpr -> AExpr)
atomize env expression =
  case expression of
    CVar {} ->
      do
        atom <- toANFAtom env expression
        pure (atom, id)
    CLit {} ->
      do
        atom <- toANFAtom env expression
        pure (atom, id)
    CCon {} ->
      do
        atom <- toANFAtom env expression
        pure (atom, id)
    CCoerce inner _ ->
      atomize env inner
    _ -> do
      expr <- toANFExpr env expression
      temp <- freshANFTemp (exprType expression)
      pure (AVar temp, ALet temp expr)

freshANFTemp :: CoreType -> EncodeM Name
freshANFTemp ty = do
  state <- get
  let index = encodeNextTemp state
      name = Name ("_core_egg_t" <> Text.pack (show index))
  modify' $
    \current ->
      current
        { encodeNextTemp = index + 1
        , encodeNameTypes = Map.insert name ty (encodeNameTypes current)
        }
  pure name

decodeANFFragment ::
  Map.Map Name CoreType ->
  Map.Map Name RName ->
  Int ->
  CoreType ->
  AExpr ->
  Either CoreEgglogError CoreExpr
decodeANFFragment nameTypes coreNames nextUnique expected expression =
  evalStateT (fromANFExpr expected expression) initialState
 where
  initialState =
    DecodeState
      { decodeNextUnique = nextUnique
      , decodeNameTypes = nameTypes
      , decodeCoreNames = coreNames
      }

fromANFExpr :: CoreType -> AExpr -> DecodeM CoreExpr
fromANFExpr expected expression =
  case expression of
    AAtom atom ->
      fromANFAtom expected atom
    APrim op lhs rhs ->
      case op of
        Eq -> do
          lhsTy <- inferANFAtomCoreType lhs
          rhsTy <- inferANFAtomCoreType rhs
          assertCoreType lhsTy rhsTy
          assertCoreType expected boolTy
          CPrimOp
            <$> pure PrimEq
            <*> traverse (fromANFAtom lhsTy) [lhs, rhs]
            <*> pure boolTy
        _ -> do
          let resultTy = anfPrimResultCoreType op
              operandTy = anfPrimOperandCoreType op
          assertCoreType expected resultTy
          CPrimOp
            <$> pure (anfPrimToCore op)
            <*> traverse (fromANFAtom operandTy) [lhs, rhs]
            <*> pure resultTy
    AIf cond thenBranch elseBranch -> do
      condExpr <- fromANFAtom boolTy cond
      thenExpr <- fromANFExpr expected thenBranch
      elseExpr <- fromANFExpr expected elseBranch
      caseBinder <- freshCoreBinder "$egg_case" boolTy
      pure
        ( CCase
            condExpr
            caseBinder
            [ CoreAlt (ConstructorAlt trueDataConName) [] thenExpr
            , CoreAlt (ConstructorAlt falseDataConName) [] elseExpr
            ]
            expected
        )
    ALet name rhs body -> do
      rhsTy <- inferANFCoreType rhs
      rhsCore <- fromANFExpr rhsTy rhs
      binder <- binderForANFName name rhsTy
      modify' $
        \state ->
          state
            { decodeNameTypes = Map.insert name rhsTy (decodeNameTypes state)
            , decodeCoreNames = Map.insert name (coreBinderName binder) (decodeCoreNames state)
            }
      bodyCore <- fromANFExpr expected body
      pure (CLet (CoreNonRec binder rhsCore) bodyCore expected)
    ALam {} ->
      lift (Left (CoreEgglogUnsupportedANF expression))
    AApp {} ->
      lift (Left (CoreEgglogUnsupportedANF expression))
    ACall {} ->
      lift (Left (CoreEgglogUnsupportedANF expression))

fromANFAtom :: CoreType -> Atom -> DecodeM CoreExpr
fromANFAtom expected atom =
  case atom of
    AInt value -> do
      assertCoreType expected intTy
      pure (CLit (LInt value) intTy)
    ABool True -> do
      assertCoreType expected boolTy
      pure (CCon trueDataConName boolTy)
    ABool False -> do
      assertCoreType expected boolTy
      pure (CCon falseDataConName boolTy)
    AVar name -> do
      state <- get
      case (Map.lookup name (decodeCoreNames state), Map.lookup name (decodeNameTypes state)) of
        (Just coreName, Just ty) -> do
          assertCoreType expected ty
          pure (CVar coreName ty)
        _ ->
          lift (Left (CoreEgglogUnknownANFName name))

binderForANFName :: Name -> CoreType -> DecodeM CoreBinder
binderForANFName name ty = do
  state <- get
  case Map.lookup name (decodeCoreNames state) of
    Just coreName ->
      pure (CoreBinder coreName ty)
    Nothing ->
      freshCoreBinder (unName name) ty

freshCoreBinder :: Text -> CoreType -> DecodeM CoreBinder
freshCoreBinder occurrence ty = do
  state <- get
  let unique = decodeNextUnique state
      name =
        RName
          { nameNamespace = TermNamespace
          , nameOcc = occurrence
          , nameUnique = unique
          , nameExternal = False
          }
  modify' (\current -> current {decodeNextUnique = unique + 1})
  pure (CoreBinder name ty)

inferANFCoreType :: AExpr -> DecodeM CoreType
inferANFCoreType = \case
  AAtom atom ->
    inferANFAtomCoreType atom
  APrim op lhs rhs -> do
    lhsTy <- inferANFAtomCoreType lhs
    rhsTy <- inferANFAtomCoreType rhs
    case op of
      Eq -> do
        assertCoreType lhsTy rhsTy
        pure boolTy
      _ -> do
        let operandTy = anfPrimOperandCoreType op
        assertCoreType operandTy lhsTy
        assertCoreType operandTy rhsTy
        pure (anfPrimResultCoreType op)
  AIf cond thenBranch elseBranch -> do
    condTy <- inferANFAtomCoreType cond
    assertCoreType boolTy condTy
    thenTy <- inferANFCoreType thenBranch
    elseTy <- inferANFCoreType elseBranch
    assertCoreType thenTy elseTy
    pure thenTy
  ALet name rhs body -> do
    rhsTy <- inferANFCoreType rhs
    modify' (\state -> state {decodeNameTypes = Map.insert name rhsTy (decodeNameTypes state)})
    inferANFCoreType body
  other ->
    lift (Left (CoreEgglogUnsupportedANF other))

inferANFAtomCoreType :: Atom -> DecodeM CoreType
inferANFAtomCoreType = \case
  AInt {} -> pure intTy
  ABool {} -> pure boolTy
  AVar name -> do
    state <- get
    case Map.lookup name (decodeNameTypes state) of
      Just ty -> pure ty
      Nothing -> lift (Left (CoreEgglogUnknownANFName name))

assertCoreType :: CoreType -> CoreType -> DecodeM ()
assertCoreType expected actual
  | expected == actual = pure ()
  | otherwise = lift (Left (CoreEgglogTypeMismatch expected actual))

boolCaseBodies :: [CoreAlt] -> Maybe (CoreExpr, CoreExpr)
boolCaseBodies alternatives = do
  let trueBody =
        [body | CoreAlt (ConstructorAlt name) [] body <- alternatives, name == trueDataConName]
      falseBody =
        [body | CoreAlt (ConstructorAlt name) [] body <- alternatives, name == falseDataConName]
      defaultBody =
        [body | CoreAlt DefaultAlt [] body <- alternatives]
  case (trueBody, falseBody, defaultBody) of
    ([t], [f], _) -> Just (t, f)
    ([t], [], [d]) -> Just (t, d)
    ([], [f], [d]) -> Just (d, f)
    _ -> Nothing

corePrimToANF :: CorePrimOp -> Maybe BinOp
corePrimToANF = \case
  PrimAdd -> Just Add
  PrimSub -> Just Sub
  PrimMul -> Just Mul
  PrimDiv -> Just Div
  PrimRem -> Nothing
  PrimEq -> Just Eq
  PrimLt -> Just Lt
  PrimNegate -> Nothing
  PrimBitAnd -> Nothing
  PrimBitOr -> Nothing
  PrimBitXor -> Nothing
  PrimBitComplement -> Nothing
  PrimShift -> Nothing
  PrimShiftL -> Nothing
  PrimShiftR -> Nothing
  PrimRotate -> Nothing
  PrimRotateL -> Nothing
  PrimRotateR -> Nothing
  PrimBit -> Nothing
  PrimTestBit -> Nothing
  PrimCharToInt -> Nothing
  PrimIntToChar -> Nothing
  PrimShowInt -> Nothing
  PrimShowBool -> Nothing
  PrimPutStrLn -> Nothing
  PrimGetLine -> Nothing
  PrimGetArgs -> Nothing
  PrimGetProgName -> Nothing
  PrimGetEnv -> Nothing
  PrimExitWith -> Nothing
  PrimStdHandle {} -> Nothing
  PrimOpenFile -> Nothing
  PrimHClose -> Nothing
  PrimReadFile -> Nothing
  PrimWriteFile -> Nothing
  PrimAppendFile -> Nothing
  PrimHFileSize -> Nothing
  PrimHSetFileSize -> Nothing
  PrimHIsEOF -> Nothing
  PrimHSetBuffering -> Nothing
  PrimHGetBuffering -> Nothing
  PrimHFlush -> Nothing
  PrimHGetPosn -> Nothing
  PrimHSetPosn -> Nothing
  PrimHSeek -> Nothing
  PrimHTell -> Nothing
  PrimHIsOpen -> Nothing
  PrimHIsClosed -> Nothing
  PrimHIsReadable -> Nothing
  PrimHIsWritable -> Nothing
  PrimHIsSeekable -> Nothing
  PrimHIsTerminalDevice -> Nothing
  PrimHSetEcho -> Nothing
  PrimHGetEcho -> Nothing
  PrimHShow -> Nothing
  PrimHWaitForInput -> Nothing
  PrimHReady -> Nothing
  PrimHGetChar -> Nothing
  PrimHGetLine -> Nothing
  PrimHLookAhead -> Nothing
  PrimHGetContents -> Nothing
  PrimHPutChar -> Nothing
  PrimHPutStr -> Nothing
  PrimHPutStrLn -> Nothing
  PrimIOThen -> Nothing
  PrimIOBind -> Nothing
  PrimIOReturn -> Nothing
  PrimIOFail -> Nothing
  PrimIOError -> Nothing
  PrimIOCatch -> Nothing
  PrimIOTry -> Nothing
  PrimIOFix -> Nothing
  PrimNullPtr -> Nothing
  PrimCastPtr -> Nothing
  PrimIsNullPtr -> Nothing
  PrimNewStablePtr -> Nothing
  PrimDeRefStablePtr -> Nothing
  PrimFreeStablePtr -> Nothing
  PrimCastStablePtrToPtr -> Nothing
  PrimCastPtrToStablePtr -> Nothing
  PrimFreeHaskellFunPtr -> Nothing
  PrimNewForeignPtr -> Nothing
  PrimNewForeignPtr_ -> Nothing
  PrimAddForeignPtrFinalizer -> Nothing
  PrimFinalizeForeignPtr -> Nothing
  PrimWithForeignPtr -> Nothing
  PrimTouchForeignPtr -> Nothing
  PrimUnsafeForeignPtrToPtr -> Nothing
  PrimCastForeignPtr -> Nothing
  PrimPtrPlus -> Nothing
  PrimPtrMinus -> Nothing
  PrimPtrAlign -> Nothing
  PrimMallocBytes -> Nothing
  PrimReallocBytes -> Nothing
  PrimFree -> Nothing
  PrimFinalizerFree -> Nothing
  PrimPeek {} -> Nothing
  PrimPoke {} -> Nothing
  PrimCopyBytes -> Nothing
  PrimMoveBytes -> Nothing
  PrimGetErrno -> Nothing
  PrimResetErrno -> Nothing
  PrimPeekCString -> Nothing
  PrimPeekCStringLen -> Nothing
  PrimNewCString -> Nothing
  PrimPeekCWString -> Nothing
  PrimPeekCWStringLen -> Nothing
  PrimNewCWString -> Nothing
  PrimFloat {} -> Nothing
  PrimFloatInt {} -> Nothing
  PrimFixedIntegral {} -> Nothing

anfPrimToCore :: BinOp -> CorePrimOp
anfPrimToCore = \case
  Add -> PrimAdd
  Sub -> PrimSub
  Mul -> PrimMul
  Div -> PrimDiv
  Eq -> PrimEq
  Lt -> PrimLt

anfPrimOperandCoreType :: BinOp -> CoreType
anfPrimOperandCoreType = \case
  Eq -> intTy
  Lt -> intTy
  _ -> intTy

anfPrimResultCoreType :: BinOp -> CoreType
anfPrimResultCoreType = \case
  Lt -> boolTy
  Eq -> boolTy
  _ -> intTy

coreTypeToANFType :: CoreType -> Maybe Type
coreTypeToANFType ty
  | ty == intTy = Just TInt
  | ty == boolTy = Just TBool
  | otherwise = Nothing

coreTypeSupported :: CoreType -> Bool
coreTypeSupported =
  maybe False (const True) . coreTypeToANFType

coreNameToANF :: RName -> Name
coreNameToANF name =
  Name
    ( "core_"
        <> sanitizeName (nameOcc name)
        <> "_u"
        <> Text.pack (show (nameUnique name))
    )

sanitizeName :: Text -> Text
sanitizeName =
  Text.concatMap encode
 where
  encode char
    | char >= 'a' && char <= 'z' = Text.singleton char
    | char >= 'A' && char <= 'Z' = Text.singleton char
    | char >= '0' && char <= '9' = Text.singleton char
    | char == '_' = "_u"
    | otherwise = "_x" <> Text.pack (show (ordCode char)) <> "_"

ordCode :: Char -> Int
ordCode =
  fromEnum

scopeFromBinds :: [CoreBind] -> Map.Map RName CoreType
scopeFromBinds binds =
  Map.fromList [(coreBinderName binder, coreBinderType binder) | bind <- binds, binder <- bindersOf bind]

scopeFromBind :: CoreBind -> Map.Map RName CoreType
scopeFromBind bind =
  Map.fromList [(coreBinderName binder, coreBinderType binder) | binder <- bindersOf bind]

moduleCost :: CoreModule -> Int
moduleCost (CoreModule _ _ binds _foreignExports) =
  sum (map bindCost binds)

bindCost :: CoreBind -> Int
bindCost = \case
  CoreNonRec _ rhs -> expressionCost rhs
  CoreRec pairs -> sum (map (expressionCost . snd) pairs)

expressionCost :: CoreExpr -> Int
expressionCost = \case
  CVar {} -> 1
  CLit {} -> 1
  CCon {} -> 1
  CLam _ body _ -> 1 + expressionCost body
  CApp fn arg _ -> 1 + expressionCost fn + expressionCost arg
  CTypeLam _ body _ -> expressionCost body
  CTypeApp fn _ _ -> expressionCost fn
  CLet bind body _ -> 1 + bindCost bind + expressionCost body
  CCase scrutinee _ alternatives _ ->
    1 + expressionCost scrutinee + sum [expressionCost body | CoreAlt _ _ body <- alternatives]
  CCoerce expression _ ->
    expressionCost expression
  CPrimOp _ arguments _ ->
    2 + sum (map expressionCost arguments)
  CForeignCall _ arguments _ ->
    3 + sum (map expressionCost arguments)
  CForeignImportValue {} ->
    2

nextUniqueAfterModule :: CoreModule -> Int
nextUniqueAfterModule (CoreModule _ _ binds foreignExports) =
  maximum (1000000 : concatMap uniquesInBind binds <> map (nameUnique . coreForeignExportName) foreignExports) + 1

nextUniqueAfterExpr :: CoreExpr -> Int
nextUniqueAfterExpr expression =
  maximum (1000000 : uniquesInExpr expression) + 1

uniquesInBind :: CoreBind -> [Int]
uniquesInBind = \case
  CoreNonRec binder rhs -> nameUnique (coreBinderName binder) : uniquesInExpr rhs
  CoreRec pairs -> concatMap (\(binder, rhs) -> nameUnique (coreBinderName binder) : uniquesInExpr rhs) pairs

uniquesInExpr :: CoreExpr -> [Int]
uniquesInExpr = \case
  CVar name _ -> [nameUnique name]
  CLit {} -> []
  CCon name _ -> [nameUnique name]
  CLam binder body _ -> nameUnique (coreBinderName binder) : uniquesInExpr body
  CApp fn arg _ -> uniquesInExpr fn <> uniquesInExpr arg
  CTypeLam variables body _ -> map nameUnique variables <> uniquesInExpr body
  CTypeApp fn _ _ -> uniquesInExpr fn
  CLet bind body _ -> uniquesInBind bind <> uniquesInExpr body
  CCase scrutinee binder alternatives _ ->
    uniquesInExpr scrutinee
      <> [nameUnique (coreBinderName binder)]
      <> concatMap uniquesInAlt alternatives
  CCoerce expression _ ->
    uniquesInExpr expression
  CPrimOp _ arguments _ -> concatMap uniquesInExpr arguments
  CForeignCall foreignImport arguments _ ->
    uniqueInForeignImport foreignImport <> concatMap uniquesInExpr arguments
  CForeignImportValue foreignImport _ ->
    uniqueInForeignImport foreignImport

uniquesInAlt :: CoreAlt -> [Int]
uniquesInAlt (CoreAlt altCon binders body) =
  altUnique altCon <> map (nameUnique . coreBinderName) binders <> uniquesInExpr body
 where
  altUnique = \case
    ConstructorAlt name -> [nameUnique name]
    _ -> []

uniqueInForeignImport :: CoreForeignImport -> [Int]
uniqueInForeignImport foreignImport =
  [nameUnique (coreForeignImportName foreignImport)]

uniqueTexts :: [Text] -> [Text]
uniqueTexts =
  reverse . snd . foldl step (Set.empty, [])
 where
  step (seen, acc) value
    | value `Set.member` seen = (seen, acc)
    | otherwise = (Set.insert value seen, value : acc)

renderCoreEgglogStatus :: CoreEgglogResult -> Text
renderCoreEgglogStatus result =
  if coreEgglogOriginalCost result == coreEgglogOptimizedCost result
    then "egglog-core: checked; no lower-cost Core selected"
    else
      "egglog-core: optimized; cost "
        <> Text.pack (show (coreEgglogOriginalCost result))
        <> " -> "
        <> Text.pack (show (coreEgglogOptimizedCost result))
        <> "; rules: "
        <> renderRules (coreEgglogAppliedRules result)

renderRules :: [Text] -> Text
renderRules = \case
  [] -> "none"
  rules -> Text.intercalate ", " rules

renderCoreEgglogError :: CoreEgglogError -> Text
renderCoreEgglogError = \case
  CoreEgglogInvalidInput errors ->
    "invalid Core before Egglog optimization: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)
  CoreEgglogInvalidOutput errors ->
    "Egglog extraction produced invalid Core: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)
  CoreEgglogBackendError err ->
    ANFEgglog.renderEgglogBackendError err
  CoreEgglogUnsupportedType ty ->
    "Core Egglog optimizer does not support type " <> renderCoreType ty
  CoreEgglogUnsupportedANF expr ->
    "Core Egglog optimizer cannot decode ANF expression " <> renderANF expr
  CoreEgglogUnsupportedANFAtom atom ->
    "Core Egglog optimizer cannot decode ANF atom " <> Text.pack (show atom)
  CoreEgglogTypeMismatch expected actual ->
    "Core Egglog type mismatch: expected " <> renderCoreType expected <> ", got " <> renderCoreType actual
  CoreEgglogUnknownANFName name ->
    "Core Egglog extraction referenced unknown name " <> unName name
  CoreEgglogCannotConvert message ->
    message
