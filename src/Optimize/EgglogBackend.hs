module Optimize.EgglogBackend
  ( AppliedRuleSummary (..)
  , BinderKey (..)
  , EncodedBinding (..)
  , EncodedProgram (..)
  , EncodedRun (..)
  , EgglogBackendError (..)
  , EgglogBackendResult (..)
  , EgglogOptimizationAttempt (..)
  , EgglogOptimizationResult (..)
  , ExtractionStats (..)
  , RunStats (..)
  , SupportedFragment
  , classifyEgglogFragment
  , encodeResolvedANF
  , extractOptimizedANF
  , optimizeANFWithEgglog
  , optimizeWithEgglog
  , renderEgglogBackendError
  , runEgglogCompilerRules
  , tryOptimizeWithEgglog
  )
where

import Control.Monad.State.Strict (State, evalState, get, modify', runState)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Database
import Egglog.Eval
import Egglog.Extract
import Egglog.Pattern
import Egglog.Rebuild
import Egglog.Rule
import Egglog.Sort
import Egglog.Value
import Eval.ANFInterpreter (ANFValue, evalANF)
import IR.ANF
import IR.ANF.Resolved
import IR.ANF.Validate
import Optimize.EgglogBackend.Fragment
  ( FragmentError
  , SupportedFragment
  , TypedResolvedAExpr (..)
  , TypedResolvedAtom (..)
  , classifyResolvedANF
  , typedExprType
  , typedFreeVariableTypes
  )
import qualified Optimize.EgglogBackend.Fragment as Fragment
import Optimize.EgglogBackend.Rules
import Optimize.EgglogBackend.Schema
import Syntax.AST (BinOp (..), Name (..), Type (..))
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

newtype BinderKey = BinderKey {unBinderKey :: Text}
  deriving stock (Show, Eq, Ord)

data EncodedBinding = EncodedBinding
  { encodedBinder :: Binder
  , encodedBindingType :: Type
  , encodedBindingRHS :: TypedResolvedAExpr
  , encodedBinderPattern :: Pattern
  }
  deriving stock (Show, Eq, Ord)

data EncodedProgram = EncodedProgram
  { encodedOriginal :: AExpr
  , encodedResolved :: ResolvedAExpr
  , encodedTyped :: TypedResolvedAExpr
  , encodedRootType :: Type
  , encodedInitialDatabase :: Database
  , encodedProgram :: Program
  , encodedRootFunction :: FunctionName
  , encodedRootPattern :: Pattern
  , encodedBinderTerms :: Map.Map BinderId Pattern
  , encodedFreeVariables :: Map.Map Name Pattern
  , encodedFreeVariableTypes :: Map.Map Name Type
  , encodedBindings :: Map.Map BinderId EncodedBinding
  , encodedBindingOrder :: [BinderId]
  , encodedOutputNames :: Map.Map BinderId Name
  , encodedProvenance :: [Text]
  }
  deriving stock (Show, Eq)

data EncodedRun = EncodedRun
  { encodedRunResult :: RunResult
  , encodedRunDatabase :: Database
  , encodedRunRootValue :: Value
  , encodedRunStats :: RunStats
  , encodedRunRebuildStats :: RebuildStats
  , encodedRunAppliedRules :: [AppliedRuleSummary]
  , encodedRunFunctionTableSizes :: Map.Map FunctionName Int
  , encodedRunUnionCount :: Int
  , encodedRunSaturated :: Bool
  }
  deriving stock (Show, Eq)

data RunStats = RunStats
  { runIterations :: Int
  , runSaturated :: Bool
  }
  deriving stock (Show, Eq, Ord)

data ExtractionStats = ExtractionStats
  { originalCost :: Int
  , optimizedCost :: Int
  }
  deriving stock (Show, Eq, Ord)

data AppliedRuleSummary = AppliedRuleSummary
  { appliedRuleName :: FunctionName
  }
  deriving stock (Show, Eq, Ord)

data EgglogOptimizationResult = EgglogOptimizationResult
  { originalANF :: AExpr
  , resolvedANF :: ResolvedAExpr
  , optimizedANF :: AExpr
  , originalType :: Type
  , optimizedType :: Type
  , runStats :: RunStats
  , rebuildStats :: RebuildStats
  , extractionStats :: ExtractionStats
  , appliedRules :: [AppliedRuleSummary]
  , functionEntries :: Int
  , unsupportedReason :: Maybe EgglogBackendError
  }
  deriving stock (Show, Eq)

data EgglogOptimizationAttempt
  = EgglogOptimized EgglogOptimizationResult
  | EgglogUnsupported EgglogBackendError
  | EgglogFailed EgglogBackendError
  deriving stock (Show, Eq)

data EgglogBackendResult = EgglogBackendResult
  { egglogOptimizedANF :: AExpr
  , egglogIterations :: Int
  , egglogSaturated :: Bool
  }
  deriving stock (Show, Eq, Ord)

data EgglogBackendError
  = ResolveFailed ResolveError
  | UnsupportedLambda Binder
  | UnsupportedApplication TypedResolvedAtom TypedResolvedAtom
  | UnsupportedPrimitive BinOp
  | UnsupportedType Type
  | AmbiguousFreeVariable Name
  | UnboundResolvedBinder Binder
  | FragmentTypeMismatch Type Type
  | EgglogKernelError EgglogError
  | ExtractionFailed EgglogError
  | CannotConvertExtracted ExtractedTerm
  | MissingRootValue FunctionName
  | ReconstructedANFInvalid ANFValidationError
  | ReconstructedTypeError Text
  | OptimizedTypeChanged Type Type
  | SemanticCheckFailed ANFValue ANFValue
  deriving stock (Show, Eq)

optimizeANFWithEgglog :: AExpr -> Either EgglogBackendError EgglogBackendResult
optimizeANFWithEgglog expression = do
  result <- optimizeWithEgglog defaultRunConfig expression
  pure
    EgglogBackendResult
      { egglogOptimizedANF = optimizedANF result
      , egglogIterations = runIterations (runStats result)
      , egglogSaturated = runSaturated (runStats result)
        }

classifyEgglogFragment :: ResolvedAExpr -> Either EgglogBackendError SupportedFragment
classifyEgglogFragment =
  mapLeft fragmentToBackendError . classifyResolvedANF

optimizeWithEgglog :: RunConfig -> AExpr -> Either EgglogBackendError EgglogOptimizationResult
optimizeWithEgglog config expression = do
  resolved <- mapLeft ResolveFailed (resolveANF expression)
  typed <- classifyEgglogFragment resolved
  encodedWithoutSource <- encodeResolvedANF typed
  let encoded =
        encodedWithoutSource
          { encodedOriginal = expression
          , encodedResolved = resolved
          }
  encodedRun <- runEgglogCompilerRules config encoded
  let runResult = encodedRunResult encodedRun
  optimized <- extractOptimizedANF encoded encodedRun
  optimizedTy <- mapLeft ReconstructedTypeError (inferANFTypeText (encodedFreeVariableTypes encoded) optimized)
  checkSemantics expression optimized
  pure
    EgglogOptimizationResult
      { originalANF = expression
      , resolvedANF = resolved
      , optimizedANF = optimized
      , originalType = encodedRootType encoded
      , optimizedType = optimizedTy
      , runStats =
          RunStats
            { runIterations = resultIterations runResult
            , runSaturated = resultSaturated runResult
            }
      , rebuildStats = resultRebuildStats runResult
      , extractionStats =
          ExtractionStats
            { originalCost = anfCost expression
            , optimizedCost = anfCost optimized
            }
      , appliedRules = map AppliedRuleSummary (resultAppliedRules runResult)
      , functionEntries = sum (Map.elems (encodedRunFunctionTableSizes encodedRun))
      , unsupportedReason = Nothing
      }

tryOptimizeWithEgglog :: RunConfig -> AExpr -> EgglogOptimizationAttempt
tryOptimizeWithEgglog config expression =
  case optimizeWithEgglog config expression of
    Right result ->
      EgglogOptimized result
    Left err
      | isUnsupported err -> EgglogUnsupported err
      | otherwise -> EgglogFailed err

encodeResolvedANF :: SupportedFragment -> Either EgglogBackendError EncodedProgram
encodeResolvedANF typed = do
  freeTypes <- mapLeft fragmentToBackendError (typedFreeVariableTypes typed)
  let (rootPattern, state) = runEncode (encodeExpr typed)
      rootFn = rootFunction (typedExprType typed)
      initialActions = reverse (encodeActions state) <> [ASet rootFn [] rootPattern]
      program =
        Program
          { programDecls = backendDecls
          , programInitialActions = initialActions
          , programRules = compilerRules
          }
      bindingIds = reverse (encodeBindingOrder state)
      names = Map.fromList [(ident, stableOutputName binder) | ident <- bindingIds, Just binding <- [Map.lookup ident (encodeBindings state)], let binder = encodedBinder binding]
      bindings = encodeBindings state
  pure
    EncodedProgram
      { encodedOriginal = typedToANF typed
      , encodedResolved = typedToResolved typed
      , encodedTyped = typed
      , encodedRootType = typedExprType typed
      , encodedInitialDatabase = databaseFromDecls backendDecls
      , encodedProgram = program
      , encodedRootFunction = rootFn
      , encodedRootPattern = rootPattern
      , encodedBinderTerms = Map.map encodedBinderPattern bindings
      , encodedFreeVariables = freeVariableTerms typed
      , encodedFreeVariableTypes = freeTypes
      , encodedBindings = encodeBindings state
      , encodedBindingOrder = bindingIds
      , encodedOutputNames = names
      , encodedProvenance = map actionProvenance initialActions
      }

runEgglogCompilerRules :: RunConfig -> EncodedProgram -> Either EgglogBackendError EncodedRun
runEgglogCompilerRules config encoded = do
  runResult <- mapLeft EgglogKernelError (runProgram config (encodedProgram encoded))
  rootValue <-
    mapLeft EgglogKernelError $
      lookupFunction (encodedRootFunction encoded) [] (resultDatabase runResult)
  case rootValue of
    Just value ->
      Right
        EncodedRun
          { encodedRunResult = runResult
          , encodedRunDatabase = resultDatabase runResult
          , encodedRunRootValue = value
          , encodedRunStats =
              RunStats
                { runIterations = resultIterations runResult
                , runSaturated = resultSaturated runResult
                }
          , encodedRunRebuildStats = resultRebuildStats runResult
          , encodedRunAppliedRules = map AppliedRuleSummary (resultAppliedRules runResult)
          , encodedRunFunctionTableSizes = Map.map Map.size (tables (resultDatabase runResult))
          , encodedRunUnionCount = unionsCreated (resultRebuildStats runResult)
          , encodedRunSaturated = resultSaturated runResult
          }
    Nothing ->
      Left (MissingRootValue (encodedRootFunction encoded))

data EncodeState = EncodeState
  { encodeActions :: [Action]
  , encodeBindings :: Map.Map BinderId EncodedBinding
  , encodeBindingOrder :: [BinderId]
  }
  deriving stock (Show, Eq)

runEncode :: State EncodeState a -> (a, EncodeState)
runEncode action =
  let state =
        EncodeState
          { encodeActions = []
          , encodeBindings = Map.empty
          , encodeBindingOrder = []
          }
   in runState action state

encodeExpr :: TypedResolvedAExpr -> State EncodeState Pattern
encodeExpr = \case
  TRAtom atom ->
    pure (encodeAtom atom)
  TRPrim _ op lhs rhs ->
    case op of
      Add -> call (iAddFn symbols) [encodeAtom lhs, encodeAtom rhs]
      Mul -> call (iMulFn symbols) [encodeAtom lhs, encodeAtom rhs]
      _ -> call (iAddFn symbols) [encodeAtom lhs, encodeAtom rhs]
  TRIf ty cond thenBranch elseBranch -> do
    thenPattern <- encodeExpr thenBranch
    elsePattern <- encodeExpr elseBranch
    case ty of
      TInt -> call (iIfFn symbols) [encodeAtom cond, thenPattern, elsePattern]
      TBool -> call (bIfFn symbols) [encodeAtom cond, thenPattern, elsePattern]
      TFun {} -> call (iIfFn symbols) [encodeAtom cond, thenPattern, elsePattern]
  TRLet _ binder rhs body -> do
    rhsPattern <- encodeExpr rhs
    let binderPattern = binderTerm (typedExprType rhs) binder
        binding =
          EncodedBinding
            { encodedBinder = binder
            , encodedBindingType = typedExprType rhs
            , encodedBindingRHS = rhs
            , encodedBinderPattern = binderPattern
            }
    modify' $
      \state ->
        state
          { encodeActions = AUnion binderPattern rhsPattern : encodeActions state
          , encodeBindings = Map.insert (binderId binder) binding (encodeBindings state)
          , encodeBindingOrder = binderId binder : encodeBindingOrder state
          }
    encodeExpr body
 where
  call name args =
    pure (PCall name args)

encodeAtom :: TypedResolvedAtom -> Pattern
encodeAtom atom =
  case typedAtomNode atom of
    RInt n ->
      PCall (iNumFn symbols) [PValue (VInt n)]
    RBool b ->
      PCall (bBoolFn symbols) [PValue (VBool b)]
    RVar (BoundVar binder) ->
      binderTerm (typedAtomType atom) binder
    RVar (FreeVar name) ->
      namedVarTerm (typedAtomType atom) (freeBinderKey name)

binderTerm :: Type -> Binder -> Pattern
binderTerm ty binder =
  namedVarTerm ty (localBinderKey binder)

namedVarTerm :: Type -> BinderKey -> Pattern
namedVarTerm ty key =
  case ty of
    TInt -> PCall (iVarFn symbols) [PValue (VString (unBinderKey key))]
    TBool -> PCall (bVarFn symbols) [PValue (VString (unBinderKey key))]
    TFun {} -> PCall (iVarFn symbols) [PValue (VString (unBinderKey key))]

extractOptimizedANF :: EncodedProgram -> EncodedRun -> Either EgglogBackendError AExpr
extractOptimizedANF encoded encodedRun = do
  rootValue <- mapLeft EgglogKernelError (lookupFunction (rootFunction (encodedRootType encoded)) [] db)
  rootTerm <-
    case rootValue of
      Just (VId sortName ident) ->
        mapLeft ExtractionFailed (extractCheapest db sortName ident)
      _ ->
        Left (MissingRootValue (rootFunction (encodedRootType encoded)))
  rootBuilt <- buildTop encoded rootTerm
  (bindings, needed) <- collectNeededBindings encoded db (builtRefs rootBuilt)
  let retainedIds = filter (`Set.member` needed) (encodedBindingOrder encoded)
      body = builtExpr rootBuilt
      optimized = foldr addBinding body retainedIds
      addBinding ident acc =
        case Map.lookup ident bindings of
          Just built ->
            ALet (outputName encoded ident) (builtExpr built) acc
          Nothing ->
            acc
  mapLeft ReconstructedANFInvalid (validateANFWithFreeVars (Map.keysSet (encodedFreeVariableTypes encoded)) optimized)
  optimizedTy <- inferANFType (encodedFreeVariableTypes encoded) optimized
  if optimizedTy == encodedRootType encoded
    then pure optimized
    else Left (OptimizedTypeChanged (encodedRootType encoded) optimizedTy)
 where
  db = encodedRunDatabase encodedRun

collectNeededBindings :: EncodedProgram -> Database -> Set.Set BinderId -> Either EgglogBackendError (Map.Map BinderId BuiltExpr, Set.Set BinderId)
collectNeededBindings encoded db =
  loop Map.empty
 where
  loop built seen =
    case filter (`Map.notMember` built) (Set.toList seen) of
      [] -> Right (built, seen)
      ident : _ -> do
        binding <-
          case Map.lookup ident (encodedBindings encoded) of
            Just value -> Right value
            Nothing -> Left (ReconstructedTypeError ("missing encoded binding " <> Text.pack (show ident)))
        builtBinding <- extractBinding encoded db binding
        loop (Map.insert ident builtBinding built) (seen <> builtRefs builtBinding)

extractBinding :: EncodedProgram -> Database -> EncodedBinding -> Either EgglogBackendError BuiltExpr
extractBinding encoded db binding = do
  let binder = encodedBinder binding
      name = variableFunction (encodedBindingType binding)
      key = unBinderKey (localBinderKey binder)
  found <- mapLeft EgglogKernelError (lookupFunction name [VString key] db)
  case found of
    Just (VId sortName ident) -> do
      extracted <- mapLeft ExtractionFailed (extractCheapest db sortName ident)
      built <- buildTop encoded extracted
      if isSelfReference encoded (binderId binder) built
        then originalBuilt encoded (encodedBindingRHS binding)
        else Right built
    _ ->
      originalBuilt encoded (encodedBindingRHS binding)

data BuiltExpr = BuiltExpr
  { builtExpr :: AExpr
  , builtRefs :: Set.Set BinderId
  }
  deriving stock (Show, Eq, Ord)

buildTop :: EncodedProgram -> ExtractedTerm -> Either EgglogBackendError BuiltExpr
buildTop encoded term =
  case termToAtom encoded term of
    Just (atom, refs) ->
      Right BuiltExpr {builtExpr = AAtom atom, builtRefs = refs}
    Nothing ->
      evalState (buildExpr encoded term) 0

buildExpr :: EncodedProgram -> ExtractedTerm -> State Int (Either EgglogBackendError BuiltExpr)
buildExpr encoded term =
  case termToAtom encoded term of
    Just (atom, refs) ->
      pure (Right BuiltExpr {builtExpr = AAtom atom, builtRefs = refs})
    Nothing ->
      case term of
        ExtractCall name [lhs, rhs]
          | name == iAddFn symbols -> buildBinary encoded Add lhs rhs
          | name == iMulFn symbols -> buildBinary encoded Mul lhs rhs
        ExtractCall name [cond, thenTerm, elseTerm]
          | name == iIfFn symbols || name == bIfFn symbols -> buildIf encoded cond thenTerm elseTerm
        _ ->
          pure (Left (CannotConvertExtracted term))

buildBinary :: EncodedProgram -> BinOp -> ExtractedTerm -> ExtractedTerm -> State Int (Either EgglogBackendError BuiltExpr)
buildBinary encoded op lhs rhs = do
  lhsResult <- buildAtom encoded lhs
  rhsResult <- buildAtom encoded rhs
  case (lhsResult, rhsResult) of
    (Right (lhsAtom, lhsWrap, lhsRefs), Right (rhsAtom, rhsWrap, rhsRefs)) ->
      pure
        ( Right
            BuiltExpr
              { builtExpr = lhsWrap (rhsWrap (APrim op lhsAtom rhsAtom))
              , builtRefs = lhsRefs <> rhsRefs
              }
        )
    (Left err, _) -> pure (Left err)
    (_, Left err) -> pure (Left err)

buildIf :: EncodedProgram -> ExtractedTerm -> ExtractedTerm -> ExtractedTerm -> State Int (Either EgglogBackendError BuiltExpr)
buildIf encoded cond thenTerm elseTerm = do
  condResult <- buildAtom encoded cond
  thenResult <- buildExpr encoded thenTerm
  elseResult <- buildExpr encoded elseTerm
  case (condResult, thenResult, elseResult) of
    (Right (condAtom, condWrap, condRefs), Right thenBuilt, Right elseBuilt) ->
      pure
        ( Right
            BuiltExpr
              { builtExpr = condWrap (AIf condAtom (builtExpr thenBuilt) (builtExpr elseBuilt))
              , builtRefs = condRefs <> builtRefs thenBuilt <> builtRefs elseBuilt
              }
        )
    (Left err, _, _) -> pure (Left err)
    (_, Left err, _) -> pure (Left err)
    (_, _, Left err) -> pure (Left err)

buildAtom :: EncodedProgram -> ExtractedTerm -> State Int (Either EgglogBackendError (Atom, AExpr -> AExpr, Set.Set BinderId))
buildAtom encoded term =
  case termToAtom encoded term of
    Just (atom, refs) ->
      pure (Right (atom, id, refs))
    Nothing -> do
      exprResult <- buildExpr encoded term
      case exprResult of
        Left err -> pure (Left err)
        Right built -> do
          temp <- freshTemp
          pure (Right (AVar temp, ALet temp (builtExpr built), builtRefs built))

termToAtom :: EncodedProgram -> ExtractedTerm -> Maybe (Atom, Set.Set BinderId)
termToAtom encoded = \case
  ExtractCall name [ExtractValue (VInt n)]
    | name == iNumFn symbols -> Just (AInt n, Set.empty)
  ExtractCall name [ExtractValue (VBool b)]
    | name == bBoolFn symbols -> Just (ABool b, Set.empty)
  ExtractCall name [ExtractValue (VString key)]
    | name == iVarFn symbols || name == bVarFn symbols -> decodeKey encoded key
  _ ->
    Nothing

decodeKey :: EncodedProgram -> Text -> Maybe (Atom, Set.Set BinderId)
decodeKey encoded key =
  case Text.stripPrefix "local:" key of
    Just rest ->
      let identText = Text.takeWhile (/= ':') rest
       in case reads (Text.unpack identText) of
            [(n, "")] ->
              let ident = BinderId n
               in Just (AVar (outputName encoded ident), Set.singleton ident)
            _ -> Nothing
    Nothing ->
      case Text.stripPrefix "free:" key of
        Just name -> Just (AVar (Name name), Set.empty)
        Nothing -> Nothing

originalBuilt :: EncodedProgram -> TypedResolvedAExpr -> Either EgglogBackendError BuiltExpr
originalBuilt encoded =
  go
 where
  go = \case
    TRAtom atom ->
      atomOriginal atom
    TRPrim _ op lhs rhs -> do
      lhsBuilt <- atomOriginal lhs
      rhsBuilt <- atomOriginal rhs
      lhsAtom <- builtToAtom lhsBuilt
      rhsAtom <- builtToAtom rhsBuilt
      Right BuiltExpr {builtExpr = APrim op lhsAtom rhsAtom, builtRefs = builtRefs lhsBuilt <> builtRefs rhsBuilt}
    TRIf _ cond thenBranch elseBranch -> do
      condBuilt <- atomOriginal cond
      condAtom <- builtToAtom condBuilt
      thenBuilt <- go thenBranch
      elseBuilt <- go elseBranch
      Right
        BuiltExpr
          { builtExpr = AIf condAtom (builtExpr thenBuilt) (builtExpr elseBuilt)
          , builtRefs = builtRefs condBuilt <> builtRefs thenBuilt <> builtRefs elseBuilt
          }
    TRLet _ binder rhs body -> do
      rhsBuilt <- go rhs
      bodyBuilt <- go body
      let name = outputName encoded (binderId binder)
      Right
        BuiltExpr
          { builtExpr = ALet name (builtExpr rhsBuilt) (builtExpr bodyBuilt)
          , builtRefs = Set.delete (binderId binder) (builtRefs rhsBuilt <> builtRefs bodyBuilt)
          }

  atomOriginal atom =
    case typedAtomNode atom of
      RInt n -> Right BuiltExpr {builtExpr = AAtom (AInt n), builtRefs = Set.empty}
      RBool b -> Right BuiltExpr {builtExpr = AAtom (ABool b), builtRefs = Set.empty}
      RVar (BoundVar binder) ->
        Right BuiltExpr {builtExpr = AAtom (AVar (outputName encoded (binderId binder))), builtRefs = Set.singleton (binderId binder)}
      RVar (FreeVar name) ->
        Right BuiltExpr {builtExpr = AAtom (AVar name), builtRefs = Set.empty}

  builtToAtom built =
    case builtExpr built of
      AAtom atom -> Right atom
      expr -> Left (ReconstructedTypeError ("expected atom while reconstructing original expression, got " <> renderANF expr))

isSelfReference :: EncodedProgram -> BinderId -> BuiltExpr -> Bool
isSelfReference encoded ident built =
  builtExpr built == AAtom (AVar (outputName encoded ident))

freeVariableTerms :: TypedResolvedAExpr -> Map.Map Name Pattern
freeVariableTerms = \case
  TRAtom atom ->
    freeVariableAtom atom
  TRPrim _ _ lhs rhs ->
    freeVariableAtom lhs <> freeVariableAtom rhs
  TRIf _ cond thenBranch elseBranch ->
    freeVariableAtom cond <> freeVariableTerms thenBranch <> freeVariableTerms elseBranch
  TRLet _ _ rhs body ->
    freeVariableTerms rhs <> freeVariableTerms body

freeVariableAtom :: TypedResolvedAtom -> Map.Map Name Pattern
freeVariableAtom atom =
  case typedAtomNode atom of
    RVar (FreeVar name) ->
      Map.singleton name (encodeAtom atom)
    _ ->
      Map.empty

actionProvenance :: Action -> Text
actionProvenance =
  Text.pack . show

inferANFType :: Map.Map Name Type -> AExpr -> Either EgglogBackendError Type
inferANFType =
  infer
 where
  infer env = \case
    AAtom atom ->
      inferAtom env atom
    APrim op lhs rhs ->
      case op of
        Add -> intPrim lhs rhs
        Mul -> intPrim lhs rhs
        Sub -> Left (UnsupportedPrimitive Sub)
        Div -> Left (UnsupportedPrimitive Div)
        Eq -> Left (UnsupportedPrimitive Eq)
        Lt -> Left (UnsupportedPrimitive Lt)
     where
      intPrim leftAtom rightAtom = do
        assertAtomType env TInt leftAtom
        assertAtomType env TInt rightAtom
        Right TInt
    AIf cond thenBranch elseBranch -> do
      assertAtomType env TBool cond
      thenType <- infer env thenBranch
      elseType <- infer env elseBranch
      if thenType == elseType
        then Right thenType
        else Left (FragmentTypeMismatch thenType elseType)
    ALam _ ty _ ->
      Left (UnsupportedType (TFun ty ty))
    AApp {} ->
      Left (ReconstructedTypeError "applications are outside the Egglog backend fragment")
    ALet name rhs body -> do
      rhsType <- infer env rhs
      infer (Map.insert name rhsType env) body

  inferAtom env = \case
    AInt _ -> Right TInt
    ABool _ -> Right TBool
    AVar name ->
      case Map.lookup name env of
        Just ty -> Right ty
        Nothing -> Left (ReconstructedTypeError ("unbound reconstructed variable " <> renderDoc (prettyName name)))

  assertAtomType env expected atom = do
    actual <- inferAtom env atom
    if actual == expected
      then Right ()
      else Left (FragmentTypeMismatch expected actual)

inferANFTypeText :: Map.Map Name Type -> AExpr -> Either Text Type
inferANFTypeText freeTypes expression =
  mapLeft renderEgglogBackendError (inferANFType freeTypes expression)

checkSemantics :: AExpr -> AExpr -> Either EgglogBackendError ()
checkSemantics original optimized =
  case (evalANF original, evalANF optimized) of
    (Right originalValue, Right optimizedValue)
      | originalValue == optimizedValue -> Right ()
      | otherwise -> Left (SemanticCheckFailed originalValue optimizedValue)
    _ ->
      Right ()

anfCost :: AExpr -> Int
anfCost = \case
  AAtom {} -> 1
  APrim {} -> 3
  AIf _ thenBranch elseBranch -> 1 + anfCost thenBranch + anfCost elseBranch
  ALam _ _ body -> 1 + anfCost body
  AApp {} -> 3
  ALet _ rhs body -> 1 + anfCost rhs + anfCost body

rootFunction :: Type -> FunctionName
rootFunction = \case
  TInt -> iRootFn symbols
  TBool -> bRootFn symbols
  TFun {} -> iRootFn symbols

variableFunction :: Type -> FunctionName
variableFunction = \case
  TInt -> iVarFn symbols
  TBool -> bVarFn symbols
  TFun {} -> iVarFn symbols

localBinderKey :: Binder -> BinderKey
localBinderKey binder =
  BinderKey ("local:" <> Text.pack (show (unBinderId (binderId binder))) <> ":" <> renderBinderKey binder)

freeBinderKey :: Name -> BinderKey
freeBinderKey (Name name) =
  BinderKey ("free:" <> name)

stableOutputName :: Binder -> Name
stableOutputName binder =
  Name ("_egg_b" <> Text.pack (show (unBinderId (binderId binder))))

outputName :: EncodedProgram -> BinderId -> Name
outputName encoded ident =
  Map.findWithDefault (Name ("_egg_missing" <> Text.pack (show (unBinderId ident)))) ident (encodedOutputNames encoded)

freshTemp :: State Int Name
freshTemp = do
  next <- get
  modify' (+ 1)
  pure (Name ("_egg_t" <> Text.pack (show next)))

fragmentToBackendError :: FragmentError -> EgglogBackendError
fragmentToBackendError = \case
  Fragment.UnsupportedLambda binder ->
    UnsupportedLambda binder
  Fragment.UnsupportedApplication fn arg ->
    UnsupportedApplication fn arg
  Fragment.UnsupportedPrimitive op ->
    UnsupportedPrimitive op
  Fragment.UnsupportedType ty ->
    UnsupportedType ty
  Fragment.AmbiguousFreeVariable name ->
    AmbiguousFreeVariable name
  Fragment.UnboundResolvedBinder binder ->
    UnboundResolvedBinder binder
  Fragment.TypeMismatch expected actual ->
    FragmentTypeMismatch expected actual

isUnsupported :: EgglogBackendError -> Bool
isUnsupported = \case
  UnsupportedLambda {} -> True
  UnsupportedApplication {} -> True
  UnsupportedPrimitive {} -> True
  UnsupportedType {} -> True
  AmbiguousFreeVariable {} -> True
  UnboundResolvedBinder {} -> True
  FragmentTypeMismatch {} -> True
  _ -> False

resolvedToANF :: ResolvedAExpr -> AExpr
resolvedToANF = \case
  RAtom atom ->
    AAtom (resolvedAtomToAtom atom)
  RPrim op lhs rhs ->
    APrim op (resolvedAtomToAtom lhs) (resolvedAtomToAtom rhs)
  RIf cond thenBranch elseBranch ->
    AIf (resolvedAtomToAtom cond) (resolvedToANF thenBranch) (resolvedToANF elseBranch)
  RLam binder ty body ->
    ALam (binderName binder) ty (resolvedToANF body)
  RApp fn arg ->
    AApp (resolvedAtomToAtom fn) (resolvedAtomToAtom arg)
  RLet binder rhs body ->
    ALet (binderName binder) (resolvedToANF rhs) (resolvedToANF body)

resolvedAtomToAtom :: ResolvedAtom -> Atom
resolvedAtomToAtom = \case
  RInt n -> AInt n
  RBool b -> ABool b
  RVar (FreeVar name) -> AVar name
  RVar (BoundVar binder) -> AVar (binderName binder)

typedToANF :: TypedResolvedAExpr -> AExpr
typedToANF =
  resolvedToANF . typedToResolved

typedToResolved :: TypedResolvedAExpr -> ResolvedAExpr
typedToResolved = \case
  TRAtom atom ->
    RAtom (typedAtomNode atom)
  TRPrim _ op lhs rhs ->
    RPrim op (typedAtomNode lhs) (typedAtomNode rhs)
  TRIf _ cond thenBranch elseBranch ->
    RIf (typedAtomNode cond) (typedToResolved thenBranch) (typedToResolved elseBranch)
  TRLet _ binder rhs body ->
    RLet binder (typedToResolved rhs) (typedToResolved body)

renderEgglogBackendError :: EgglogBackendError -> Text
renderEgglogBackendError = \case
  ResolveFailed err ->
    "ANF resolution failed: " <> Text.pack (show err)
  UnsupportedLambda binder ->
    "unsupported lambda binder: " <> renderBinderKey binder
  UnsupportedApplication fn arg ->
    "unsupported application: " <> Text.pack (show fn) <> " " <> Text.pack (show arg)
  UnsupportedPrimitive op ->
    "unsupported primitive: " <> renderDoc (prettyBinOp op)
  UnsupportedType ty ->
    "unsupported type: " <> renderDoc (prettyType ty)
  AmbiguousFreeVariable name ->
    "ambiguous free variable: " <> renderDoc (prettyName name)
  UnboundResolvedBinder binder ->
    "unbound resolved binder: " <> renderBinderKey binder
  FragmentTypeMismatch expected actual ->
    "fragment type mismatch: expected " <> renderDoc (prettyType expected) <> ", got " <> renderDoc (prettyType actual)
  EgglogKernelError err ->
    Text.pack (show err)
  ExtractionFailed err ->
    "extraction failed: " <> Text.pack (show err)
  CannotConvertExtracted term ->
    "cannot convert extracted Egglog term to ANF: " <> renderExtractedTerm term
  MissingRootValue name ->
    "missing Egglog root value for " <> renderFunctionName name
  ReconstructedANFInvalid err ->
    renderANFValidationError err
  ReconstructedTypeError message ->
    "reconstructed ANF type error: " <> message
  OptimizedTypeChanged expected actual ->
    "optimized type changed: expected " <> renderDoc (prettyType expected) <> ", got " <> renderDoc (prettyType actual)
  SemanticCheckFailed expected actual ->
    "semantic check failed: expected " <> Text.pack (show expected) <> ", got " <> Text.pack (show actual)

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left err -> Left (f err)
  Right value -> Right value
