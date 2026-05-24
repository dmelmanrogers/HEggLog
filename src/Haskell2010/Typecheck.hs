module Haskell2010.Typecheck
  ( Kind (..)
  , PatternExhaustivenessContext (..)
  , TypeConstructorInfo (..)
  , TypecheckError (..)
  , TypecheckResult (..)
  , TypecheckWarning (..)
  , kindArity
  , kindFromArity
  , renderKind
  , typeConstructorArity
  , typeConstructorInfo
  , renderTypecheckError
  , renderTypecheckWarning
  , typecheckModuleToCore
  , typecheckModuleToCoreWithWarnings
  )
where

import Control.Applicative ((<|>))
import Control.Monad ((>=>), foldM, unless, when)
import Control.Monad.State.Strict (State, StateT, get, lift, modify, runState, runStateT)
import Data.Foldable (traverse_)
import qualified Data.Graph as Graph
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import qualified Data.Ratio as Ratio
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.FixedWidth
import Haskell2010.Names
import Haskell2010.Renamed
import Haskell2010.StandardLibrary (standardLibraryExternalName)
import Haskell2010.Syntax (Literal (..))
import qualified Haskell2010.Syntax as S
import Syntax.Span (SourceSpan (..), renderSourceDiagnostic)

data Kind
  = StarKind
  | KindArrow Kind Kind
  | KindMeta Int
  deriving stock (Show, Eq, Ord)

newtype TypeConstructorInfo = TypeConstructorInfo
  { typeConstructorKind :: Kind
  }
  deriving stock (Show, Eq, Ord)

data TypeSynonymInfo = TypeSynonymInfo
  { typeSynonymParams :: [RName]
  , typeSynonymBody :: RHsType
  }
  deriving stock (Show, Eq, Ord)

typeConstructorInfo :: Int -> TypeConstructorInfo
typeConstructorInfo arity =
  TypeConstructorInfo (kindFromArity arity)

typeConstructorArity :: TypeConstructorInfo -> Int
typeConstructorArity =
  kindArity . typeConstructorKind

kindFromArity :: Int -> Kind
kindFromArity arity
  | arity <= 0 = StarKind
  | otherwise = KindArrow StarKind (kindFromArity (arity - 1))

kindArity :: Kind -> Int
kindArity = \case
  StarKind -> 0
  KindArrow _ result -> 1 + kindArity result
  KindMeta {} -> 0

renderKind :: Kind -> Text
renderKind =
  renderRight
 where
  renderRight = \case
    StarKind -> "*"
    KindArrow argument result -> renderArgument argument <> " -> " <> renderRight result
    KindMeta meta -> "?k" <> renderInt meta

  renderArgument = \case
    StarKind -> "*"
    arrow@KindArrow {} -> "(" <> renderRight arrow <> ")"
    KindMeta meta -> "?k" <> renderInt meta

data TypecheckError
  = TypecheckErrorAt SourceSpan TypecheckError
  | UnsupportedCore0 Text
  | DuplicateTypeSignature RName
  | SignatureWithoutBinding RName
  | UnknownCore0Variable RName
  | TypeMismatch MonoType MonoType
  | OccursCheck Int MonoType
  | KindMismatch Kind Kind
  | KindOccursCheck Int Kind
  | RecursiveTypeSynonym [RName]
  | TypeSynonymArityMismatch RName Int Int
  | InvalidNewtypeConstructorArity RName Int
  | InvalidClassConstraintArity RName Int
  | UnsupportedClassConstraintContext ClassConstraintContext [ClassConstraint]
  | UnsolvedClassConstraint ClassConstraint
  | AmbiguousTypeVariable Int
  | CoreValidationFailed [CoreValidate.CoreValidationError]
  deriving stock (Show, Eq)

data TypecheckWarning
  = TypecheckWarningAt SourceSpan TypecheckWarning
  | NonExhaustivePatternMatch PatternExhaustivenessContext [Text]
  | RedundantPatternMatch PatternExhaustivenessContext
  deriving stock (Show, Eq)

data PatternExhaustivenessContext
  = CasePatternExhaustiveness
  | FunctionPatternExhaustiveness RName
  | LambdaPatternExhaustiveness
  | GeneratedPatternExhaustiveness
  deriving stock (Show, Eq, Ord)

data TypecheckResult = TypecheckResult
  { typecheckResultCore :: CoreModule
  , typecheckResultWarnings :: [TypecheckWarning]
  }
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

data ClassConstraint = ClassConstraint
  { classConstraintClass :: RName
  , classConstraintArguments :: [MonoType]
  , classConstraintSpan :: Maybe SourceSpan
  }
  deriving stock (Show)

instance Eq ClassConstraint where
  lhs == rhs =
    classConstraintClass lhs == classConstraintClass rhs
      && classConstraintArguments lhs == classConstraintArguments rhs

instance Ord ClassConstraint where
  compare lhs rhs =
    compare
      (classConstraintClass lhs, classConstraintArguments lhs)
      (classConstraintClass rhs, classConstraintArguments rhs)

data ClassConstraintContext
  = SuperclassConstraintContext RName
  | MethodConstraintContext RName
  | InstanceConstraintContext RHsType
  | ExpressionSignatureConstraintContext
  deriving stock (Show, Eq, Ord)

singleClassConstraint :: RName -> MonoType -> ClassConstraint
singleClassConstraint className ty =
  singleClassConstraintAt Nothing className ty

singleClassConstraintAt :: Maybe SourceSpan -> RName -> MonoType -> ClassConstraint
singleClassConstraintAt sourceRange className ty =
  ClassConstraint
    { classConstraintClass = className
    , classConstraintArguments = [ty]
    , classConstraintSpan = sourceRange
    }

mapClassConstraintArguments :: (MonoType -> MonoType) -> ClassConstraint -> ClassConstraint
mapClassConstraintArguments f constraint =
  constraint {classConstraintArguments = map f (classConstraintArguments constraint)}

withClassConstraintSpan :: Maybe SourceSpan -> ClassConstraint -> ClassConstraint
withClassConstraintSpan Nothing constraint =
  constraint
withClassConstraintSpan sourceRange constraint =
  constraint {classConstraintSpan = sourceRange}

withSchemeConstraintSpan :: Maybe SourceSpan -> Scheme -> Scheme
withSchemeConstraintSpan sourceRange (Scheme variables constraints body) =
  Scheme variables (map (withClassConstraintSpan sourceRange) constraints) body

classConstraintSingleArgument :: ClassConstraint -> Either TypecheckError MonoType
classConstraintSingleArgument constraint =
  case classConstraintArguments constraint of
    [ty] -> Right ty
    arguments -> Left (InvalidClassConstraintArity (classConstraintClass constraint) (length arguments))

data Scheme = Scheme [RName] [ClassConstraint] MonoType
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

data DataConstructorInfo = DataConstructorInfo
  { dataConstructorTyVars :: [RName]
  , dataConstructorFields :: [MonoType]
  , dataConstructorCoreFields :: Maybe [CoreType]
  , dataConstructorFieldLabels :: [Maybe RName]
  , dataConstructorResult :: MonoType
  , dataConstructorScheme :: Scheme
  , dataConstructorRepresentation :: CoreConstructorRepresentation
  }
  deriving stock (Show, Eq, Ord)

data RecordSelectorInfo = RecordSelectorInfo
  { recordSelectorName :: RName
  , recordSelectorTyVars :: [RName]
  , recordSelectorResultType :: MonoType
  , recordSelectorFieldType :: MonoType
  , recordSelectorScheme :: Scheme
  , recordSelectorAlternatives :: [RecordSelectorAlternative]
  }
  deriving stock (Show, Eq, Ord)

data RecordSelectorAlternative = RecordSelectorAlternative
  { recordSelectorConstructor :: RName
  , recordSelectorFieldIndex :: Int
  , recordSelectorConstructorFields :: [MonoType]
  , recordSelectorConstructorRepresentation :: CoreConstructorRepresentation
  }
  deriving stock (Show, Eq, Ord)

positionalDataConstructorInfo ::
  [RName] ->
  [MonoType] ->
  MonoType ->
  Scheme ->
  CoreConstructorRepresentation ->
  DataConstructorInfo
positionalDataConstructorInfo tyVars fields resultTy scheme representation =
  DataConstructorInfo
    { dataConstructorTyVars = tyVars
    , dataConstructorFields = fields
    , dataConstructorCoreFields = Nothing
    , dataConstructorFieldLabels = replicate (length fields) Nothing
    , dataConstructorResult = resultTy
    , dataConstructorScheme = scheme
    , dataConstructorRepresentation = representation
    }

data ClassInfo = ClassInfo
  { classInfoName :: RName
  , classInfoVariable :: RName
  , classInfoVariableKind :: Kind
  , classInfoDictTypeName :: RName
  , classInfoDictConstructorName :: RName
  , classInfoSuperclasses :: [ClassConstraint]
  , classInfoMethods :: [ClassMethodInfo]
  }
  deriving stock (Show, Eq, Ord)

data ClassMethodInfo = ClassMethodInfo
  { classMethodName :: RName
  , classMethodScheme :: Scheme
  , classMethodFieldType :: MonoType
  , classMethodFieldScheme :: Scheme
  , classMethodFieldIndex :: Int
  , classMethodDefault :: Maybe SourceBinding
  }
  deriving stock (Show, Eq, Ord)

data TypedInstanceDictionary = TypedInstanceDictionary
  { typedInstanceClass :: RName
  , typedInstanceType :: MonoType
  , typedInstanceVariables :: [RName]
  , typedInstanceContext :: [ClassConstraint]
  , typedInstanceDictName :: RName
  , typedInstanceSuperclasses :: [ClassConstraint]
  , typedInstanceMethods :: [TypedExpr]
  }
  deriving stock (Show, Eq, Ord)

data PatternPlan = PatternPlan
  { patternAltCon :: CoreAltCon
  , patternAltBinders :: [TypedBinder]
  , patternEnv :: TypeEnv
  , patternWrapBody :: TypedExpr -> TypedExpr
  , patternNeedsRuntimeCase :: Bool
  }

data TypedExpr
  = TVar RName Scheme [MonoType] MonoType
  | TLit Literal MonoType
  | TCon RName Scheme [MonoType] MonoType
  | TNewtypeCon RName Scheme [MonoType] MonoType TypedBinder
  | TTuple [TypedExpr] MonoType
  | TList [TypedExpr] MonoType
  | TLam TypedBinder TypedExpr MonoType
  | TApp TypedExpr TypedExpr MonoType
  | TLet [TypedBinding] TypedExpr MonoType
  | TCase TypedExpr TypedBinder [TypedAlt] MonoType
  | TCoerce TypedExpr MonoType
  | TPrim CorePrimOp [TypedExpr] MonoType
  deriving stock (Show, Eq, Ord)

type TypeEnv = Map.Map RName Scheme

type Subst = Map.Map Int MonoType

data InferState = InferState
  { nextMeta :: Int
  , substitution :: Subst
  , nextKindMeta :: Int
  , kindSubstitution :: Map.Map Int Kind
  , typeVariableKinds :: Map.Map RName Kind
  , nextGeneratedUnique :: Int
  , typeConstructors :: Map.Map RName TypeConstructorInfo
  , typeSynonyms :: Map.Map RName TypeSynonymInfo
  , dataConstructors :: Map.Map RName DataConstructorInfo
  , recordSelectors :: Map.Map RName RecordSelectorInfo
  , classInfos :: Map.Map RName ClassInfo
  , defaultTypes :: [MonoType]
  , typecheckSpanStack :: [SourceSpan]
  , typecheckWarnings :: [TypecheckWarning]
  }
  deriving stock (Show, Eq)

type InferM = StateT InferState (Either TypecheckError)

typecheckModuleToCore :: RHsModule -> Either TypecheckError CoreModule
typecheckModuleToCore =
  fmap typecheckResultCore . typecheckModuleToCoreWithWarnings

typecheckModuleToCoreWithWarnings :: RHsModule -> Either TypecheckError TypecheckResult
typecheckModuleToCoreWithWarnings sourceModule = do
  let sourceDecls = rModuleDecls sourceModule
      tupleArities = collectTupleArities sourceDecls
      preludeValues = collectPreludeValueNames sourceDecls
  ((typedBindings, _typedEnv, typedInstances, foreignCoreBinds, foreignCoreExports), finalState) <-
    runInfer Map.empty $ do
      typeConstructors <- collectTypeConstructors sourceDecls
      modify (\state -> state {typeConstructors = typeConstructors})
      sourceClasses <- collectClassInfos sourceDecls
      let classes = Map.union sourceClasses builtinClassInfos
      modify (\state -> state {classInfos = classes})
      defaults <- collectDefaultTypes sourceDecls
      modify (\state -> state {defaultTypes = defaults})
      constructors <- collectDataConstructors sourceDecls
      dictionaryConstructors <- classDictionaryConstructors classes
      let allConstructors =
            Map.unions
              [ constructors
              , dictionaryConstructors
              , builtinDataConstructors
              ]
      selectors <- collectRecordSelectors allConstructors
      modify
        ( \state ->
            state
              { dataConstructors = allConstructors
              , recordSelectors = selectors
              }
        )
      validateForeignDecls sourceDecls
      foreignEnv <- foreignImportTypeEnv sourceDecls
      let classEnv =
            Map.unions
              [ classMethodTypeEnv classes
              , recordSelectorTypeEnv selectors
              , foreignEnv
              ]
      (bindings, env) <- inferBindingGroup classEnv sourceDecls
      explicitInstances <- inferInstanceDictionaries env sourceDecls
      derivedInstances <- inferDerivedInstanceDictionaries env sourceDecls explicitInstances
      validateForeignExportsAgainstEnv env sourceDecls
      foreignCoreBinds <- foreignImportCoreBinds sourceDecls
      foreignCoreExports <- foreignExportCoreExports sourceDecls
      let instances = explicitInstances <> derivedInstances
      pure (bindings, env, instances, foreignCoreBinds, foreignCoreExports)
  let classes = classInfos finalState
      classesForCore = usedClassInfos classes (substitution finalState) typedBindings typedInstances
      needsPreludePairSelectors =
        any ((`elem` ["fst", "snd"]) . nameOcc) preludeValues
      coreTupleArities =
        if builtinRealClassName `Map.member` classesForCore || builtinIntegralClassName `Map.member` classesForCore || needsPreludePairSelectors
          then Set.insert 2 tupleArities
          else tupleArities
      builtinInstances = builtinInstanceDictionaries classesForCore
      instances =
        builtinInstanceDictionaryRefs builtinInstances
          <> instanceDictionaryRefs (substitution finalState) classesForCore typedInstances
      elaborationEnv =
        CoreElabEnv
          (substitution finalState)
          Map.empty
          classesForCore
          instances
          []
  coreBinds <- traverse (bindingToCore elaborationEnv) typedBindings
  classCoreBinds <- classSelectorCoreBinds (substitution finalState) classesForCore
  recordCoreBinds <- recordSelectorCoreBinds (substitution finalState) (recordSelectors finalState)
  builtinEqSupportBinds <- builtinEqSupportCoreBinds classesForCore
  builtinOrdSupportBinds <- builtinOrdSupportCoreBinds classesForCore
  builtinShowSupportBinds <- builtinShowSupportCoreBinds classesForCore
  builtinReadSupportBinds <- builtinReadSupportCoreBinds classesForCore
  builtinFunctorSupportBinds <- builtinFunctorSupportCoreBinds classesForCore
  builtinMonadSupportBinds <- builtinMonadSupportCoreBinds classesForCore
  builtinInstanceCoreBinds <- traverse (builtinInstanceDictionaryToCore classesForCore) builtinInstances
  instanceCoreBinds <- traverse (instanceDictionaryToCore (substitution finalState) classesForCore instances) typedInstances
  preludeCoreBinds <- preludeCoreBindings (preludeValues <> classPreludeSupportNames classesForCore)
  let sourceCoreBinds = maybe [] (: []) (bindingGroupCoreBind typedBindings coreBinds)
  coreConstructors <-
    Map.union (tupleConstructorInfos coreTupleArities)
      <$> constructorInfosToCore
        (substitution finalState)
        (filterClassDictionaryConstructors classes classesForCore (dataConstructors finalState))
  let coreModule =
        uniquifyCoreModuleBinders
          CoreModule
          { coreModuleName = rModuleName sourceModule
          , coreModuleConstructors = coreConstructors
          , coreModuleBinds =
              case preludeCoreBinds <> classCoreBinds <> recordCoreBinds <> builtinEqSupportBinds <> builtinOrdSupportBinds <> builtinShowSupportBinds <> builtinReadSupportBinds <> builtinFunctorSupportBinds <> builtinMonadSupportBinds <> builtinInstanceCoreBinds <> instanceCoreBinds <> foreignCoreBinds <> sourceCoreBinds of
                [] -> []
                [one] -> [one]
                many -> [CoreRec (concatMap bindPairs many)]
          , coreModuleForeignExports = foreignCoreExports
          }
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv coreModule) coreModule of
    Right () ->
      Right
        TypecheckResult
          { typecheckResultCore = coreModule
          , typecheckResultWarnings = typecheckWarnings finalState
          }
    Left errors -> Left (CoreValidationFailed errors)

renderTypecheckError :: TypecheckError -> Text
renderTypecheckError = \case
  TypecheckErrorAt sourceRange err ->
    renderSourceDiagnostic sourceRange "type error" (renderTypecheckErrorDetail err)
  err ->
    renderTypecheckErrorDetail err

renderTypecheckErrorDetail :: TypecheckError -> Text
renderTypecheckErrorDetail = \case
  TypecheckErrorAt _ err ->
    renderTypecheckErrorDetail err
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
  KindMismatch expected actual ->
    "kind mismatch: expected " <> renderKind expected <> ", got " <> renderKind actual
  KindOccursCheck meta kind ->
    "kind occurs check failed: ?k" <> renderInt meta <> " occurs in " <> renderKind kind
  RecursiveTypeSynonym names ->
    "recursive type synonym cycle: " <> Text.intercalate " -> " (map renderRName names)
  TypeSynonymArityMismatch name expected actual ->
    "type synonym `"
      <> renderRName name
      <> "` expects "
      <> renderInt expected
      <> " argument(s), got "
      <> renderInt actual
  InvalidNewtypeConstructorArity name actual ->
    "newtype constructor `"
      <> renderRName name
      <> "` must have exactly one field, got "
      <> renderInt actual
  InvalidClassConstraintArity name actual ->
    "class constraint `"
      <> renderRName name
      <> "` must have exactly one argument, got "
      <> renderInt actual
  UnsupportedClassConstraintContext context constraints ->
    "unsupported class-constraint context: "
      <> renderClassConstraintContext context
      <> case constraints of
        [] -> ""
        _ -> " with " <> Text.intercalate ", " (map renderClassConstraint constraints)
  UnsolvedClassConstraint constraint ->
    "unsolved type-class constraint " <> renderClassConstraint constraint
  AmbiguousTypeVariable meta ->
    "ambiguous Core-0 type variable ?" <> renderInt meta
  CoreValidationFailed errors ->
    "generated Core failed validation: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)

renderTypecheckWarning :: TypecheckWarning -> Text
renderTypecheckWarning = \case
  TypecheckWarningAt sourceRange warning ->
    renderSourceDiagnostic sourceRange "warning" (renderTypecheckWarningDetail warning)
  warning ->
    renderTypecheckWarningDetail warning

renderTypecheckWarningDetail :: TypecheckWarning -> Text
renderTypecheckWarningDetail = \case
  TypecheckWarningAt _ warning ->
    renderTypecheckWarningDetail warning
  NonExhaustivePatternMatch context missing ->
    "non-exhaustive pattern match: "
      <> renderPatternExhaustivenessContext context
      <> renderPatternCoverageMiss context
      <> renderMissingPatternWitnesses missing
  RedundantPatternMatch context ->
    "redundant pattern match: "
      <> renderPatternExhaustivenessContext context
      <> renderPatternRedundancy context

renderMissingPatternWitnesses :: [Text] -> Text
renderMissingPatternWitnesses = \case
  [] -> "all supported patterns"
  witnesses -> Text.intercalate ", " witnesses

renderPatternCoverageMiss :: PatternExhaustivenessContext -> Text
renderPatternCoverageMiss = \case
  CasePatternExhaustiveness ->
    " do not cover "
  FunctionPatternExhaustiveness {} ->
    " does not cover "
  LambdaPatternExhaustiveness ->
    " does not cover "
  GeneratedPatternExhaustiveness ->
    " does not cover "

renderPatternRedundancy :: PatternExhaustivenessContext -> Text
renderPatternRedundancy = \case
  CasePatternExhaustiveness ->
    " contain an unreachable alternative"
  FunctionPatternExhaustiveness {} ->
    " contains an unreachable alternative"
  LambdaPatternExhaustiveness ->
    " contains an unreachable alternative"
  GeneratedPatternExhaustiveness ->
    " contains an unreachable alternative"

renderPatternExhaustivenessContext :: PatternExhaustivenessContext -> Text
renderPatternExhaustivenessContext = \case
  CasePatternExhaustiveness ->
    "case alternatives"
  FunctionPatternExhaustiveness name ->
    "function `" <> renderRName name <> "`"
  LambdaPatternExhaustiveness ->
    "lambda pattern"
  GeneratedPatternExhaustiveness ->
    "generated pattern"

runInfer :: Map.Map RName TypeConstructorInfo -> InferM a -> Either TypecheckError (a, InferState)
runInfer initialTypeConstructors action =
  let initialState =
        InferState
          { nextMeta = 0
          , substitution = Map.empty
          , nextKindMeta = 0
          , kindSubstitution = Map.empty
          , typeVariableKinds = Map.empty
          , nextGeneratedUnique = 100000
          , typeConstructors = initialTypeConstructors
          , typeSynonyms = Map.empty
          , dataConstructors = Map.empty
          , recordSelectors = Map.empty
          , classInfos = Map.empty
          , defaultTypes = [intMonoType, doubleMonoType]
          , typecheckSpanStack = []
          , typecheckWarnings = []
          }
   in swapState <$> runStateT action initialState
 where
  swapState (value, state) =
    (value, state)

collectTypeConstructors :: [RDecl] -> InferM (Map.Map RName TypeConstructorInfo)
collectTypeConstructors decls = do
  seeded <- foldM seed Map.empty decls
  let synonyms = collectTypeSynonyms decls
  validateTypeSynonymCycles synonyms
  modify (\state -> state {typeConstructors = seeded, typeSynonyms = synonyms})
  traverse_ validateNewtypeDecl decls
  traverse_ inferDeclKinds decls
  finalized <- finalizeTypeConstructors seeded
  modify (\state -> state {typeConstructors = finalized})
  pure finalized
 where
  seed acc = \case
    RDataDecl name params _ _ ->
      insertTypeConstructor name params acc
    RNewtypeDecl name params _ _ ->
      insertTypeConstructor name params acc
    RTypeSynonym name params _ ->
      insertTypeConstructor name params acc
    _ ->
      pure acc

insertTypeConstructor :: RName -> [RName] -> Map.Map RName TypeConstructorInfo -> InferM (Map.Map RName TypeConstructorInfo)
insertTypeConstructor name params acc = do
  paramKinds <- traverse (const freshKindMeta) params
  pure (Map.insert name (TypeConstructorInfo (foldr KindArrow StarKind paramKinds)) acc)

validateNewtypeDecl :: RDecl -> InferM ()
validateNewtypeDecl = \case
  RNewtypeDecl _ _ constructor _ ->
    validateNewtypeConstructor constructor
  _ ->
    pure ()

validateNewtypeConstructor :: RConDecl -> InferM ()
validateNewtypeConstructor conDecl =
  withTypecheckSpan (rConDeclSpan conDecl) $
    unless (length fields == 1) $
      throwTypecheck (InvalidNewtypeConstructorArity constructorName (length fields))
 where
  constructorName = conDeclName conDecl
  fields = conDeclFieldTypes conDecl

collectTypeSynonyms :: [RDecl] -> Map.Map RName TypeSynonymInfo
collectTypeSynonyms =
  foldr collect Map.empty
 where
  collect decl acc =
    case decl of
      RTypeSynonym name params body ->
        Map.insert name TypeSynonymInfo {typeSynonymParams = params, typeSynonymBody = body} acc
      _ ->
        acc

validateTypeSynonymCycles :: Map.Map RName TypeSynonymInfo -> InferM ()
validateTypeSynonymCycles synonyms =
  traverse_ validateComponent (Graph.stronglyConnComp graphNodes)
 where
  synonymNames = Map.keysSet synonyms
  graphNodes =
    [ (name, name, Set.toList (typeSynonymDependencies info))
    | (name, info) <- Map.toList synonyms
    ]

  typeSynonymDependencies info =
    sourceTypeConstructors (typeSynonymBody info) `Set.intersection` synonymNames

  dependenciesFor name =
    maybe Set.empty typeSynonymDependencies (Map.lookup name synonyms)

  validateComponent = \case
    Graph.AcyclicSCC name ->
      when (name `Set.member` dependenciesFor name) $
        throwTypecheck (RecursiveTypeSynonym [name, name])
    Graph.CyclicSCC names ->
      throwTypecheck (RecursiveTypeSynonym names)

inferDeclKinds :: RDecl -> InferM ()
inferDeclKinds = \case
  RDataDecl typeName params constructors _ ->
    withTypeParameterKinds typeName params $
      traverse_ checkConstructor constructors
  RNewtypeDecl typeName params constructor _ ->
    withTypeParameterKinds typeName params (checkConstructor constructor)
  RTypeSynonym typeName params body ->
    withTypeParameterKinds typeName params (checkSourceTypeKind body)
  _ ->
    pure ()
 where
  checkConstructor constructor =
    traverse_ checkSourceTypeKind (conDeclFieldTypes constructor)

sourceTypeConstructors :: RHsType -> Set.Set RName
sourceTypeConstructors = \case
  RTyVar {} ->
    Set.empty
  RTyCon name ->
    Set.singleton name
  RTyApp fn arg ->
    sourceTypeConstructors fn <> sourceTypeConstructors arg
  RTyFun arg result ->
    sourceTypeConstructors arg <> sourceTypeConstructors result
  RTyContext constraints body ->
    Set.unions (map sourceTypeConstructors constraints) <> sourceTypeConstructors body
  RTyTuple types ->
    Set.unions (map sourceTypeConstructors types)
  RTyList elementType ->
    sourceTypeConstructors elementType
  RTyParen inner ->
    sourceTypeConstructors inner

withTypeParameterKinds :: RName -> [RName] -> InferM a -> InferM a
withTypeParameterKinds typeName params action = do
  oldKinds <- typeVariableKinds <$> get
  constructors <- typeConstructors <$> get
  let parameterKinds =
        case Map.lookup typeName constructors of
          Nothing -> replicate (length params) StarKind
          Just info -> take (length params) (kindArgumentKinds (typeConstructorKind info))
  modify
    ( \state ->
        state
          { typeVariableKinds =
              Map.union
                (Map.fromList (zip params parameterKinds))
                (typeVariableKinds state)
          }
    )
  result <- action
  modify (\state -> state {typeVariableKinds = oldKinds})
  pure result

kindArgumentKinds :: Kind -> [Kind]
kindArgumentKinds = \case
  KindArrow argument result -> argument : kindArgumentKinds result
  _ -> []

finalizeTypeConstructors :: Map.Map RName TypeConstructorInfo -> InferM (Map.Map RName TypeConstructorInfo)
finalizeTypeConstructors constructors =
  traverse finalize constructors
 where
  finalize info = do
    kind <- applyKindCurrent (typeConstructorKind info)
    pure (TypeConstructorInfo (defaultKindMetas kind))

defaultKindMetas :: Kind -> Kind
defaultKindMetas = \case
  StarKind -> StarKind
  KindArrow argument result -> KindArrow (defaultKindMetas argument) (defaultKindMetas result)
  KindMeta {} -> StarKind

collectDataConstructors :: [RDecl] -> InferM (Map.Map RName DataConstructorInfo)
collectDataConstructors =
  foldM collect Map.empty
 where
  collect acc = \case
    RDataDecl typeName params constructors _ ->
      foldM (insertConstructor CoreDataConstructor typeName params) acc constructors
    RNewtypeDecl typeName params constructor _ ->
      insertConstructor CoreNewtypeConstructor typeName params acc constructor
    _ ->
      pure acc

  insertConstructor representation typeName params acc constructor = do
    let constructorName = conDeclName constructor
        sourceFields = conDeclFieldTypes constructor
        fieldLabels = conDeclFieldLabels constructor
    fieldTypes <- constructorFieldMonoTypes params sourceFields
    let resultTy = foldl TyApp (TyCon typeName) (map TyVar params)
        scheme = Scheme params [] (foldr TyFun resultTy fieldTypes)
        info =
          DataConstructorInfo
            { dataConstructorTyVars = params
            , dataConstructorFields = fieldTypes
            , dataConstructorCoreFields = Nothing
            , dataConstructorFieldLabels = fieldLabels
            , dataConstructorResult = resultTy
            , dataConstructorScheme = scheme
            , dataConstructorRepresentation = representation
            }
    pure (Map.insert constructorName info acc)

conDeclName :: RConDecl -> RName
conDeclName = \case
  RConDecl name _ -> name
  RRecordConDecl name _ -> name

conDeclFieldTypes :: RConDecl -> [RHsType]
conDeclFieldTypes = \case
  RConDecl _ fields ->
    fields
  RRecordConDecl _ fields ->
    concatMap (\(RConField labels sourceType) -> replicate (length labels) sourceType) fields

conDeclFieldLabels :: RConDecl -> [Maybe RName]
conDeclFieldLabels = \case
  RConDecl _ fields ->
    replicate (length fields) Nothing
  RRecordConDecl _ fields ->
    concatMap (\(RConField labels _) -> map Just labels) fields

constructorFieldMonoTypes :: [RName] -> [RHsType] -> InferM [MonoType]
constructorFieldMonoTypes params fields =
  traverse (sourceMonoType >=> canonicalizeDataFieldTypeVars params) fields

canonicalizeDataFieldTypeVars :: [RName] -> MonoType -> InferM MonoType
canonicalizeDataFieldTypeVars params =
  go
 where
  paramsByOccurrence = Map.fromList [(nameOcc param, param) | param <- params]

  go = \case
    TyMeta meta ->
      pure (TyMeta meta)
    TyVar name ->
      case Map.lookup (nameOcc name) paramsByOccurrence of
        Just param ->
          pure (TyVar param)
        Nothing ->
          throwTypecheck
            ( UnsupportedCore0
                ( "constructor field type variable `"
                    <> nameOcc name
                    <> "` is not bound by the data type parameters"
                )
            )
    TyCon name ->
      pure (TyCon name)
    TyApp fn arg ->
      TyApp <$> go fn <*> go arg
    TyFun arg result ->
      TyFun <$> go arg <*> go result
    TyTuple fields ->
      TyTuple <$> traverse go fields
    TyList element ->
      TyList <$> go element

collectRecordSelectors :: Map.Map RName DataConstructorInfo -> InferM (Map.Map RName RecordSelectorInfo)
collectRecordSelectors constructors =
  foldM collectSelector Map.empty recordFields
 where
  recordFields =
    [ (selectorName, constructorName, fieldIndex, info, fieldTy)
    | (constructorName, info) <- Map.toList constructors
    , (fieldIndex, (Just selectorName, fieldTy)) <- zip [0 ..] (zip (dataConstructorFieldLabels info) (dataConstructorFields info))
    ]

  collectSelector acc (selectorName, constructorName, fieldIndex, info, fieldTy)
    | duplicatedConstructorField selectorName constructorName acc =
        throwTypecheck
          ( UnsupportedCore0
              ( "duplicate record field `"
                  <> renderRName selectorName
                  <> "` in constructor `"
                  <> renderRName constructorName
                  <> "`"
              )
          )
    | otherwise =
        case Map.lookup selectorName acc of
          Nothing ->
            pure (Map.insert selectorName (newSelector selectorName constructorName fieldIndex info fieldTy) acc)
          Just existing ->
            if recordSelectorResultType existing == dataConstructorResult info
              && recordSelectorFieldType existing == fieldTy
              then pure (Map.insert selectorName (appendSelectorAlternative existing constructorName fieldIndex info) acc)
              else
                throwTypecheck
                  ( UnsupportedCore0
                      ( "record field `"
                          <> renderRName selectorName
                          <> "` has inconsistent constructor result or field types"
                      )
                  )

  duplicatedConstructorField selectorName constructorName acc =
    case Map.lookup selectorName acc of
      Nothing -> False
      Just existing ->
        any ((== constructorName) . recordSelectorConstructor) (recordSelectorAlternatives existing)

  newSelector selectorName constructorName fieldIndex info fieldTy =
    let scheme = Scheme (dataConstructorTyVars info) [] (TyFun (dataConstructorResult info) fieldTy)
     in RecordSelectorInfo
          { recordSelectorName = selectorName
          , recordSelectorTyVars = dataConstructorTyVars info
          , recordSelectorResultType = dataConstructorResult info
          , recordSelectorFieldType = fieldTy
          , recordSelectorScheme = scheme
          , recordSelectorAlternatives = [selectorAlternative constructorName fieldIndex info]
          }

  appendSelectorAlternative selector constructorName fieldIndex info =
    selector
      { recordSelectorAlternatives =
          recordSelectorAlternatives selector <> [selectorAlternative constructorName fieldIndex info]
      }

  selectorAlternative constructorName fieldIndex info =
    RecordSelectorAlternative
      { recordSelectorConstructor = constructorName
      , recordSelectorFieldIndex = fieldIndex
      , recordSelectorConstructorFields = dataConstructorFields info
      , recordSelectorConstructorRepresentation = dataConstructorRepresentation info
      }

recordSelectorTypeEnv :: Map.Map RName RecordSelectorInfo -> TypeEnv
recordSelectorTypeEnv =
  Map.map recordSelectorScheme

collectClassInfos :: [RDecl] -> InferM (Map.Map RName ClassInfo)
collectClassInfos decls = do
  infos <- foldM collect Map.empty decls
  validateSuperclassGraph infos
  pure infos
 where
  collect acc = \case
    RClassDecl constraints className classVariable classDecls -> do
      superclasses <- traverse sourceClassConstraint constraints
      let normalizedSuperclasses = map (replaceConstraintClassVariable classVariable) superclasses
      validateSuperclasses className classVariable normalizedSuperclasses
      methods <- collectClassMethods className classVariable (length normalizedSuperclasses) classDecls
      variableKind <- defaultKindMetas <$> (typeVariableKind classVariable >>= applyKindCurrent)
      let info =
            ClassInfo
              { classInfoName = className
              , classInfoVariable = classVariable
              , classInfoVariableKind = variableKind
              , classInfoDictTypeName = classDictionaryTypeName className
              , classInfoDictConstructorName = classDictionaryConstructorName className
              , classInfoSuperclasses = normalizedSuperclasses
              , classInfoMethods = methods
              }
      pure (Map.insert className info acc)
    _ ->
      pure acc

  validateSuperclasses className classVariable constraints = do
    when (any ((== className) . classConstraintClass) constraints) $
      throwTypecheck (UnsupportedCore0 ("recursive superclass for `" <> renderRName className <> "`"))
    unless (all superclassUsesClassVariable constraints) $
      throwUnsupportedClassConstraintContext (SuperclassConstraintContext className) constraints
   where
    superclassUsesClassVariable constraint =
      case classConstraintArguments constraint of
        [TyVar variable] -> variable == classVariable
        _ -> False

validateSuperclassGraph :: Map.Map RName ClassInfo -> InferM ()
validateSuperclassGraph sourceInfos =
  traverse_ validateClass (Map.keys sourceInfos)
 where
  allInfos = Map.union sourceInfos builtinClassInfos

  validateClass className =
    visit [] className

  visit path className
    | className `elem` path =
        throwTypecheck (UnsupportedCore0 ("recursive superclass cycle involving `" <> renderRName className <> "`"))
    | otherwise =
        case Map.lookup className allInfos of
          Nothing ->
            throwTypecheck (UnsupportedCore0 ("superclass for unknown class `" <> renderRName className <> "`"))
          Just info ->
            traverse_ (visit (className : path) . classConstraintClass) (classInfoSuperclasses info)

collectClassMethods :: RName -> RName -> Int -> [RDecl] -> InferM [ClassMethodInfo]
collectClassMethods className classVariable superclassCount decls = do
  signatures <- concat <$> traverse methodSignatures decls
  defaults <- collectDefaults decls
  signatureMap <- foldM insertSignature Map.empty signatures
  case filter (`Map.notMember` signatureMap) (Map.keys defaults) of
    [] -> pure ()
    defaultName : _ ->
      throwTypecheck (UnsupportedCore0 ("default method without signature `" <> renderRName defaultName <> "`"))
  traverse (methodInfo defaults) (zip [0 ..] signatures)
 where
  methodSignatures = \case
    RTypeSignature names sourceType ->
      pure [(name, sourceType) | name <- names]
    RFunctionBinding {} ->
      pure []
    RFixityDecl {} ->
      pure []
    other ->
      throwTypecheck (UnsupportedCore0 ("class declaration item " <> Text.pack (show other)))

  collectDefaults =
    foldM collectDefault Map.empty

  collectDefault acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RFunctionBinding name patterns rhs whereDecls ->
          case Map.lookup name acc of
            Just _ ->
              throwTypecheck (UnsupportedCore0 ("duplicate default method `" <> renderRName name <> "`"))
            Nothing ->
              pure
                ( Map.insert
                    name
                    SourceBinding
                      { sourceBindingSpan = rDeclSpan decl
                      , sourceBindingName = name
                      , sourceBindingPatterns = patterns
                      , sourceBindingPatternBinding = Nothing
                      , sourceBindingRhs = rhs
                      , sourceBindingWhereDecls = whereDecls
                      }
                    acc
                )
        RTypeSignature {} ->
          pure acc
        RFixityDecl {} ->
          pure acc
        other ->
          throwTypecheck (UnsupportedCore0 ("class declaration item " <> Text.pack (show other)))

  insertSignature acc (methodName, sourceType) =
    case Map.lookup methodName acc of
      Just _ -> throwTypecheck (DuplicateTypeSignature methodName)
      Nothing -> pure (Map.insert methodName sourceType acc)

  methodInfo defaults (index, (methodName, sourceType)) = do
    Scheme _ constraints body <- sourceScheme sourceType
    let normalizedConstraints = map (replaceConstraintClassVariable classVariable) constraints
        normalizedBody = replaceMonoTypeClassVariable classVariable body
        variables = List.nub (concatMap constraintTypeVars normalizedConstraints <> typeVars normalizedBody)
    unless (null constraints) $
      throwUnsupportedClassConstraintContext (MethodConstraintContext methodName) normalizedConstraints
    let classTy = TyVar classVariable
        allVariables = List.nub (classVariable : variables)
        fieldVariables = filter (/= classVariable) variables
        scheme = Scheme allVariables [singleClassConstraint className classTy] normalizedBody
        fieldScheme = Scheme fieldVariables [] normalizedBody
    pure
      ClassMethodInfo
        { classMethodName = methodName
        , classMethodScheme = scheme
        , classMethodFieldType = normalizedBody
        , classMethodFieldScheme = fieldScheme
        , classMethodFieldIndex = superclassCount + index
        , classMethodDefault = Map.lookup methodName defaults
        }

replaceConstraintClassVariable :: RName -> ClassConstraint -> ClassConstraint
replaceConstraintClassVariable classVariable =
  mapClassConstraintArguments (replaceMonoTypeClassVariable classVariable)

replaceMonoTypeClassVariable :: RName -> MonoType -> MonoType
replaceMonoTypeClassVariable classVariable = \case
  TyVar name
    | nameOcc name == nameOcc classVariable -> TyVar classVariable
    | otherwise -> TyVar name
  TyMeta meta -> TyMeta meta
  TyCon name -> TyCon name
  TyApp fn arg -> TyApp (replaceMonoTypeClassVariable classVariable fn) (replaceMonoTypeClassVariable classVariable arg)
  TyFun arg result -> TyFun (replaceMonoTypeClassVariable classVariable arg) (replaceMonoTypeClassVariable classVariable result)
  TyTuple fields -> TyTuple (map (replaceMonoTypeClassVariable classVariable) fields)
  TyList element -> TyList (replaceMonoTypeClassVariable classVariable element)

classMethodTypeEnv :: Map.Map RName ClassInfo -> TypeEnv
classMethodTypeEnv infos =
  Map.fromList
    [ (classMethodName method, classMethodScheme method)
    | info <- Map.elems infos
    , method <- classInfoMethods info
    ]

classDictionaryConstructors :: Map.Map RName ClassInfo -> InferM (Map.Map RName DataConstructorInfo)
classDictionaryConstructors =
  fmap Map.fromList . traverse constructorInfo . Map.elems
 where
  constructorInfo info = do
    coreFields <- lift (classDictionaryCoreFieldTypes Map.empty Map.empty info)
    let classVar = classInfoVariable info
        classTy = TyVar classVar
        fields = classDictionaryFieldTypes info
        resultTy = classDictionaryType info classTy
        scheme = Scheme [classVar] [] (foldr TyFun resultTy fields)
        constructorInfo' =
          (positionalDataConstructorInfo [classVar] fields resultTy scheme CoreDataConstructor)
            {dataConstructorCoreFields = Just coreFields}
    pure (classInfoDictConstructorName info, constructorInfo')

classDictionaryFieldTypes :: ClassInfo -> [MonoType]
classDictionaryFieldTypes info =
  map superclassDictionaryFieldType (classInfoSuperclasses info) <> map classMethodFieldType (classInfoMethods info)

classDictionaryCoreFieldTypes :: Subst -> Map.Map Int RName -> ClassInfo -> Either TypecheckError [CoreType]
classDictionaryCoreFieldTypes subst metas info =
  (<>) <$> traverse (monoToCoreType subst metas . superclassDictionaryFieldType) (classInfoSuperclasses info)
    <*> traverse (classMethodFieldCoreType subst metas) (classInfoMethods info)

classMethodFieldCoreType :: Subst -> Map.Map Int RName -> ClassMethodInfo -> Either TypecheckError CoreType
classMethodFieldCoreType subst metas method =
  schemeToCoreTypeWith subst metas (classMethodFieldScheme method)

superclassDictionaryFieldType :: ClassConstraint -> MonoType
superclassDictionaryFieldType constraint =
  case classConstraintArguments constraint of
    [argument] -> TyApp (TyCon (classDictionaryTypeName (classConstraintClass constraint))) argument
    _ -> error "superclassDictionaryFieldType called with non-unary constraint"

classDictionaryType :: ClassInfo -> MonoType -> MonoType
classDictionaryType info arg =
  TyApp (TyCon (classInfoDictTypeName info)) arg

classDictionaryTypeName :: RName -> RName
classDictionaryTypeName className =
  RName TypeNamespace ("$" <> nameOcc className <> "Dict") (5000000 + nameUnique className) False

classDictionaryConstructorName :: RName -> RName
classDictionaryConstructorName className =
  RName ConstructorNamespace ("$Mk" <> nameOcc className <> "Dict") (5100000 + nameUnique className) False

builtinClassInfos :: Map.Map RName ClassInfo
builtinClassInfos =
  Map.fromList
    [ (builtinEqClassName, eqInfo)
    , (builtinOrdClassName, ordInfo)
    , (builtinNumClassName, numInfo)
    , (builtinRealClassName, realInfo)
    , (builtinIntegralClassName, integralInfo)
    , (builtinFractionalClassName, fractionalInfo)
    , (builtinFloatingClassName, floatingInfo)
    , (builtinRealFracClassName, realFracInfo)
    , (builtinRealFloatClassName, realFloatInfo)
    , (builtinBitsClassName, bitsInfo)
    , (builtinShowClassName, showInfo)
    , (builtinReadClassName, readInfo)
    , (builtinEnumClassName, enumInfo)
    , (builtinBoundedClassName, boundedInfo)
    , (builtinIxClassName, ixInfo)
    , (builtinFunctorClassName, functorInfo)
    , (builtinMonadClassName, monadInfo)
    , (builtinMonadPlusClassName, builtinMonadPlusInfo)
    , (builtinStorableClassName, builtinStorableInfo)
    ]
 where
  eqA = preludeTypeVariable "a" (-1301)
  eqATy = TyVar eqA
  eqInfo =
    builtinClassInfo
      builtinEqClassName
      eqA
      []
      [ ("==", -1401, TyFun eqATy (TyFun eqATy boolMonoType))
      , ("/=", -1402, TyFun eqATy (TyFun eqATy boolMonoType))
      ]

  ordA = preludeTypeVariable "a" (-1311)
  ordATy = TyVar ordA
  ordInfo =
    builtinClassInfo
      builtinOrdClassName
      ordA
      [singleClassConstraint builtinEqClassName ordATy]
      [ ("compare", -1410, TyFun ordATy (TyFun ordATy orderingMonoType))
      , ("<", -1411, TyFun ordATy (TyFun ordATy boolMonoType))
      , ("<=", -1412, TyFun ordATy (TyFun ordATy boolMonoType))
      , (">", -1413, TyFun ordATy (TyFun ordATy boolMonoType))
      , (">=", -1414, TyFun ordATy (TyFun ordATy boolMonoType))
      , ("max", -1415, TyFun ordATy (TyFun ordATy ordATy))
      , ("min", -1416, TyFun ordATy (TyFun ordATy ordATy))
      ]

  numA = preludeTypeVariable "a" (-1321)
  numATy = TyVar numA
  numInfo =
    builtinClassInfo
      builtinNumClassName
      numA
      [ singleClassConstraint builtinEqClassName numATy
      , singleClassConstraint builtinShowClassName numATy
      ]
      [ ("+", -1421, TyFun numATy (TyFun numATy numATy))
      , ("-", -1422, TyFun numATy (TyFun numATy numATy))
      , ("*", -1423, TyFun numATy (TyFun numATy numATy))
      , ("negate", -1424, TyFun numATy numATy)
      , ("abs", -1425, TyFun numATy numATy)
      , ("signum", -1426, TyFun numATy numATy)
      , ("fromInteger", -1427, TyFun intMonoType numATy)
      ]

  realA = preludeTypeVariable "a" (-1371)
  realATy = TyVar realA
  realInfo =
    builtinClassInfo
      builtinRealClassName
      realA
      [ singleClassConstraint builtinNumClassName realATy
      , singleClassConstraint builtinOrdClassName realATy
      ]
      [("toRational", -1471, TyFun realATy rationalMonoType)]

  integralA = preludeTypeVariable "a" (-1381)
  integralATy = TyVar integralA
  integralPairTy = TyTuple [integralATy, integralATy]
  integralInfo =
    builtinClassInfo
      builtinIntegralClassName
      integralA
      [ singleClassConstraint builtinRealClassName integralATy
      , singleClassConstraint builtinEnumClassName integralATy
      ]
      [ ("quot", -1481, TyFun integralATy (TyFun integralATy integralATy))
      , ("rem", -1482, TyFun integralATy (TyFun integralATy integralATy))
      , ("div", -1483, TyFun integralATy (TyFun integralATy integralATy))
      , ("mod", -1484, TyFun integralATy (TyFun integralATy integralATy))
      , ("quotRem", -1485, TyFun integralATy (TyFun integralATy integralPairTy))
      , ("divMod", -1486, TyFun integralATy (TyFun integralATy integralPairTy))
      , ("toInteger", -1487, TyFun integralATy intMonoType)
      ]

  fractionalA = preludeTypeVariable "a" (-1388)
  fractionalATy = TyVar fractionalA
  fractionalInfo =
    builtinClassInfo
      builtinFractionalClassName
      fractionalA
      [singleClassConstraint builtinNumClassName fractionalATy]
      [ ("/", -3401, TyFun fractionalATy (TyFun fractionalATy fractionalATy))
      , ("recip", -3402, TyFun fractionalATy fractionalATy)
      , ("fromRational", -3403, TyFun rationalMonoType fractionalATy)
      ]

  floatingA = preludeTypeVariable "a" (-1497)
  floatingATy = TyVar floatingA
  floatingInfo =
    builtinClassInfo
      builtinFloatingClassName
      floatingA
      [singleClassConstraint builtinFractionalClassName floatingATy]
      [ ("pi", -3411, floatingATy)
      , ("exp", -3412, TyFun floatingATy floatingATy)
      , ("log", -3413, TyFun floatingATy floatingATy)
      , ("sqrt", -3414, TyFun floatingATy floatingATy)
      , ("**", -3415, TyFun floatingATy (TyFun floatingATy floatingATy))
      , ("logBase", -3416, TyFun floatingATy (TyFun floatingATy floatingATy))
      , ("sin", -3417, TyFun floatingATy floatingATy)
      , ("cos", -3418, TyFun floatingATy floatingATy)
      , ("tan", -3419, TyFun floatingATy floatingATy)
      , ("asin", -3420, TyFun floatingATy floatingATy)
      , ("acos", -3421, TyFun floatingATy floatingATy)
      , ("atan", -3422, TyFun floatingATy floatingATy)
      , ("sinh", -3423, TyFun floatingATy floatingATy)
      , ("cosh", -3424, TyFun floatingATy floatingATy)
      , ("tanh", -3425, TyFun floatingATy floatingATy)
      , ("asinh", -3426, TyFun floatingATy floatingATy)
      , ("acosh", -3427, TyFun floatingATy floatingATy)
      , ("atanh", -3428, TyFun floatingATy floatingATy)
      ]

  realFracA = preludeTypeVariable "a" (-1515)
  realFracATy = TyVar realFracA
  realFracPairTy = TyTuple [intMonoType, realFracATy]
  realFracInfo =
    builtinClassInfo
      builtinRealFracClassName
      realFracA
      [ singleClassConstraint builtinRealClassName realFracATy
      , singleClassConstraint builtinFractionalClassName realFracATy
      ]
      [ ("properFraction", -3431, TyFun realFracATy realFracPairTy)
      , ("truncate", -3432, TyFun realFracATy intMonoType)
      , ("round", -3433, TyFun realFracATy intMonoType)
      , ("ceiling", -3434, TyFun realFracATy intMonoType)
      , ("floor", -3435, TyFun realFracATy intMonoType)
      ]

  realFloatA = preludeTypeVariable "a" (-1520)
  realFloatATy = TyVar realFloatA
  intPairTy = TyTuple [intMonoType, intMonoType]
  realFloatInfo =
    builtinClassInfo
      builtinRealFloatClassName
      realFloatA
      [ singleClassConstraint builtinRealFracClassName realFloatATy
      , singleClassConstraint builtinFloatingClassName realFloatATy
      ]
      [ ("floatRadix", -3441, TyFun realFloatATy intMonoType)
      , ("floatDigits", -3442, TyFun realFloatATy intMonoType)
      , ("floatRange", -3443, TyFun realFloatATy intPairTy)
      , ("decodeFloat", -3444, TyFun realFloatATy intPairTy)
      , ("encodeFloat", -3445, TyFun intMonoType (TyFun intMonoType realFloatATy))
      , ("exponent", -3446, TyFun realFloatATy intMonoType)
      , ("significand", -3447, TyFun realFloatATy realFloatATy)
      , ("scaleFloat", -3448, TyFun intMonoType (TyFun realFloatATy realFloatATy))
      , ("isNaN", -3449, TyFun realFloatATy boolMonoType)
      , ("isInfinite", -3450, TyFun realFloatATy boolMonoType)
      , ("isDenormalized", -3451, TyFun realFloatATy boolMonoType)
      , ("isNegativeZero", -3452, TyFun realFloatATy boolMonoType)
      , ("isIEEE", -3453, TyFun realFloatATy boolMonoType)
      , ("atan2", -3454, TyFun realFloatATy (TyFun realFloatATy realFloatATy))
      ]

  bitsA = preludeTypeVariable "a" (-1393)
  bitsATy = TyVar bitsA
  bitsInfo =
    builtinClassInfo
      builtinBitsClassName
      bitsA
      [singleClassConstraint builtinNumClassName bitsATy]
      [ (".&.", -3901, TyFun bitsATy (TyFun bitsATy bitsATy))
      , (".|.", -3902, TyFun bitsATy (TyFun bitsATy bitsATy))
      , ("xor", -3903, TyFun bitsATy (TyFun bitsATy bitsATy))
      , ("complement", -3904, TyFun bitsATy bitsATy)
      , ("shift", -3905, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("rotate", -3906, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("bit", -3907, TyFun intMonoType bitsATy)
      , ("setBit", -3908, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("clearBit", -3909, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("complementBit", -3910, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("testBit", -3911, TyFun bitsATy (TyFun intMonoType boolMonoType))
      , ("bitSize", -3912, TyFun bitsATy intMonoType)
      , ("isSigned", -3913, TyFun bitsATy boolMonoType)
      , ("shiftL", -3914, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("shiftR", -3915, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("rotateL", -3916, TyFun bitsATy (TyFun intMonoType bitsATy))
      , ("rotateR", -3917, TyFun bitsATy (TyFun intMonoType bitsATy))
      ]

  showA = preludeTypeVariable "a" (-1331)
  showATy = TyVar showA
  showS = TyFun stringMonoType stringMonoType
  showInfo =
    builtinClassInfo
      builtinShowClassName
      showA
      []
      [ ("showsPrec", -1430, TyFun intMonoType (TyFun showATy showS))
      , ("show", -1431, TyFun showATy stringMonoType)
      , ("showList", -1432, TyFun (TyList showATy) showS)
      ]

  readA = preludeTypeVariable "a" (-1561)
  readATy = TyVar readA
  readS = TyFun stringMonoType (TyList (TyTuple [readATy, stringMonoType]))
  readListS = TyFun stringMonoType (TyList (TyTuple [TyList readATy, stringMonoType]))
  readInfo =
    builtinClassInfo
      builtinReadClassName
      readA
      []
      [ ("readsPrec", -1433, TyFun intMonoType readS)
      , ("readList", -1434, readListS)
      ]

  enumA = preludeTypeVariable "a" (-1341)
  enumATy = TyVar enumA
  enumListATy = TyList enumATy
  enumInfo =
    builtinClassInfo
      builtinEnumClassName
      enumA
      []
      [ ("succ", -1441, TyFun enumATy enumATy)
      , ("pred", -1442, TyFun enumATy enumATy)
      , ("toEnum", -1443, TyFun intMonoType enumATy)
      , ("fromEnum", -1444, TyFun enumATy intMonoType)
      , ("enumFrom", -1445, TyFun enumATy enumListATy)
      , ("enumFromThen", -1446, TyFun enumATy (TyFun enumATy enumListATy))
      , ("enumFromTo", -1447, TyFun enumATy (TyFun enumATy enumListATy))
      , ("enumFromThenTo", -1448, TyFun enumATy (TyFun enumATy (TyFun enumATy enumListATy)))
      ]

  boundedA = preludeTypeVariable "a" (-1351)
  boundedATy = TyVar boundedA
  boundedInfo =
    builtinClassInfo
      builtinBoundedClassName
      boundedA
      []
      [ ("minBound", -1451, boundedATy)
      , ("maxBound", -1452, boundedATy)
      ]

  ixA = preludeTypeVariable "a" (-1398)
  ixATy = TyVar ixA
  ixBoundsTy = TyTuple [ixATy, ixATy]
  ixInfo =
    builtinClassInfo
      builtinIxClassName
      ixA
      [singleClassConstraint builtinOrdClassName ixATy]
      [ ("range", -3601, TyFun ixBoundsTy (TyList ixATy))
      , ("index", -3602, TyFun ixBoundsTy (TyFun ixATy intMonoType))
      , ("inRange", -3603, TyFun ixBoundsTy (TyFun ixATy boolMonoType))
      , ("rangeSize", -3604, TyFun ixBoundsTy intMonoType)
      ]

  functorF = preludeTypeVariable "f" (-1391)
  functorA = preludeTypeVariable "a" (-1201)
  functorB = preludeTypeVariable "b" (-1202)
  functorFTy = TyVar functorF
  functorATy = TyVar functorA
  functorBTy = TyVar functorB
  functorInfo =
    builtinClassInfoWithKind
      builtinFunctorClassName
      functorF
      (KindArrow StarKind StarKind)
      []
      [ BuiltinMethodSpec
          "fmap"
          (-1491)
          [functorA, functorB]
          (TyFun (TyFun functorATy functorBTy) (TyFun (TyApp functorFTy functorATy) (TyApp functorFTy functorBTy)))
      ]

  monadM = preludeTypeVariable "m" (-1361)
  monadA = preludeTypeVariable "a" (-1362)
  monadB = preludeTypeVariable "b" (-1363)
  monadMTy = TyVar monadM
  monadATy = TyVar monadA
  monadBTy = TyVar monadB
  monadMA = TyApp monadMTy monadATy
  monadMB = TyApp monadMTy monadBTy
  monadInfo =
    builtinClassInfoWithKind
      builtinMonadClassName
      monadM
      (KindArrow StarKind StarKind)
      []
      [ BuiltinMethodSpec ">>=" (-1461) [monadA, monadB] (TyFun monadMA (TyFun (TyFun monadATy monadMB) monadMB))
      , BuiltinMethodSpec ">>" (-1462) [monadA, monadB] (TyFun monadMA (TyFun monadMB monadMB))
      , BuiltinMethodSpec "return" (-1463) [monadA] (TyFun monadATy monadMA)
      , BuiltinMethodSpec "fail" (-1464) [monadA] (TyFun stringMonoType monadMA)
      ]

builtinMonadPlusInfo :: ClassInfo
builtinMonadPlusInfo =
  builtinClassInfoWithKind
    builtinMonadPlusClassName
    monadPlusM
    (KindArrow StarKind StarKind)
    [singleClassConstraint builtinMonadClassName monadPlusMTy]
    [ BuiltinMethodSpec "mzero" (-1495) [monadPlusA] monadPlusMA
    , BuiltinMethodSpec "mplus" (-1496) [monadPlusA] (TyFun monadPlusMA (TyFun monadPlusMA monadPlusMA))
    ]
 where
  monadPlusM = preludeTypeVariable "m" (-1396)
  monadPlusA = preludeTypeVariable "a" (-1397)
  monadPlusMTy = TyVar monadPlusM
  monadPlusMA = TyApp monadPlusMTy (TyVar monadPlusA)

builtinStorableInfo :: ClassInfo
builtinStorableInfo =
  builtinClassInfoWithKind
    builtinStorableClassName
    storableA
    StarKind
    []
    [ BuiltinMethodSpec "sizeOf" (-1497) [] (TyFun storableATy intMonoType)
    , BuiltinMethodSpec "alignment" (-1498) [] (TyFun storableATy intMonoType)
    , BuiltinMethodSpec "peekElemOff" (-1499) [] (TyFun storablePtrA (TyFun intMonoType (ioMonoType storableATy)))
    , BuiltinMethodSpec "pokeElemOff" (-1500) [] (TyFun storablePtrA (TyFun intMonoType (TyFun storableATy (ioMonoType unitMonoType))))
    , BuiltinMethodSpec "peekByteOff" (-1501) [storableB] (TyFun storablePtrB (TyFun intMonoType (ioMonoType storableATy)))
    , BuiltinMethodSpec "pokeByteOff" (-1502) [storableB] (TyFun storablePtrB (TyFun intMonoType (TyFun storableATy (ioMonoType unitMonoType))))
    , BuiltinMethodSpec "peek" (-1503) [] (TyFun storablePtrA (ioMonoType storableATy))
    , BuiltinMethodSpec "poke" (-1504) [] (TyFun storablePtrA (TyFun storableATy (ioMonoType unitMonoType)))
    ]
 where
  storableA = preludeTypeVariable "a" (-1572)
  storableB = preludeTypeVariable "b" (-1573)
  storableATy = TyVar storableA
  storableBTy = TyVar storableB
  storablePtrA = TyApp (TyCon ptrTyConName) storableATy
  storablePtrB = TyApp (TyCon ptrTyConName) storableBTy

builtinClassInfo :: RName -> RName -> [ClassConstraint] -> [(Text, Int, MonoType)] -> ClassInfo
builtinClassInfo className classVariable superclasses methodSpecs =
  builtinClassInfoWithKind
    className
    classVariable
    StarKind
    superclasses
    [BuiltinMethodSpec occurrence unique [] fieldType | (occurrence, unique, fieldType) <- methodSpecs]

data BuiltinMethodSpec = BuiltinMethodSpec Text Int [RName] MonoType

builtinClassInfoWithKind :: RName -> RName -> Kind -> [ClassConstraint] -> [BuiltinMethodSpec] -> ClassInfo
builtinClassInfoWithKind className classVariable classVariableKind superclasses methodSpecs =
  ClassInfo
    { classInfoName = className
    , classInfoVariable = classVariable
    , classInfoVariableKind = classVariableKind
    , classInfoDictTypeName = classDictionaryTypeName className
    , classInfoDictConstructorName = classDictionaryConstructorName className
    , classInfoSuperclasses = superclasses
    , classInfoMethods =
        [ ClassMethodInfo
            { classMethodName = preludeTermName occurrence unique
            , classMethodScheme = Scheme (classVariable : methodVariables) [singleClassConstraint className (TyVar classVariable)] fieldType
            , classMethodFieldType = fieldType
            , classMethodFieldScheme = Scheme methodVariables [] fieldType
            , classMethodFieldIndex = length superclasses + index
            , classMethodDefault = Nothing
            }
        | (index, BuiltinMethodSpec occurrence unique methodVariables fieldType) <- zip [0 ..] methodSpecs
        ]
    }

builtinEqClassName :: RName
builtinEqClassName =
  preludeClassName "Eq" (-1300)

builtinOrdClassName :: RName
builtinOrdClassName =
  preludeClassName "Ord" (-1310)

builtinNumClassName :: RName
builtinNumClassName =
  preludeClassName "Num" (-1320)

builtinRealClassName :: RName
builtinRealClassName =
  preludeClassName "Real" (-1370)

builtinIntegralClassName :: RName
builtinIntegralClassName =
  preludeClassName "Integral" (-1380)

builtinFractionalClassName :: RName
builtinFractionalClassName =
  preludeClassName "Fractional" (-1388)

builtinFloatingClassName :: RName
builtinFloatingClassName =
  preludeClassName "Floating" (-1497)

builtinRealFracClassName :: RName
builtinRealFracClassName =
  preludeClassName "RealFrac" (-1515)

builtinRealFloatClassName :: RName
builtinRealFloatClassName =
  preludeClassName "RealFloat" (-1520)

builtinBitsClassName :: RName
builtinBitsClassName =
  preludeClassName "Bits" (-1394)

builtinShowClassName :: RName
builtinShowClassName =
  preludeClassName "Show" (-1330)

builtinReadClassName :: RName
builtinReadClassName =
  preludeClassName "Read" (-1560)

builtinEnumClassName :: RName
builtinEnumClassName =
  preludeClassName "Enum" (-1340)

builtinBoundedClassName :: RName
builtinBoundedClassName =
  preludeClassName "Bounded" (-1350)

builtinIxClassName :: RName
builtinIxClassName =
  preludeClassName "Ix" (-1398)

builtinFunctorClassName :: RName
builtinFunctorClassName =
  preludeClassName "Functor" (-1390)

builtinMonadClassName :: RName
builtinMonadClassName =
  preludeClassName "Monad" (-1360)

builtinMonadPlusClassName :: RName
builtinMonadPlusClassName =
  preludeClassName "MonadPlus" (-1395)

builtinStorableClassName :: RName
builtinStorableClassName =
  preludeClassName "Storable" (-1399)

preludeClassName :: Text -> Int -> RName
preludeClassName occurrence unique =
  RName ClassNamespace occurrence unique True

canonicalClassName :: RName -> RName
canonicalClassName name
  | nameExternal name =
      case nameOcc name of
        "Eq" -> builtinEqClassName
        "Ord" -> builtinOrdClassName
        "Num" -> builtinNumClassName
        "Real" -> builtinRealClassName
        "Integral" -> builtinIntegralClassName
        "Fractional" -> builtinFractionalClassName
        "Floating" -> builtinFloatingClassName
        "RealFrac" -> builtinRealFracClassName
        "RealFloat" -> builtinRealFloatClassName
        "Bits" -> builtinBitsClassName
        "Show" -> builtinShowClassName
        "Read" -> builtinReadClassName
        "Enum" -> builtinEnumClassName
        "Bounded" -> builtinBoundedClassName
        "Ix" -> builtinIxClassName
        "Functor" -> builtinFunctorClassName
        "Monad" -> builtinMonadClassName
        "MonadPlus" -> builtinMonadPlusClassName
        "Storable" -> builtinStorableClassName
        _ -> name
  | otherwise = name

builtinMethodInfoByOccurrence :: Text -> Maybe ClassMethodInfo
builtinMethodInfoByOccurrence occurrence =
  List.find ((== occurrence) . nameOcc . classMethodName) $
    concatMap classInfoMethods (Map.elems builtinClassInfos)

builtinClassInfoByOccurrence :: Text -> InferM ClassInfo
builtinClassInfoByOccurrence occurrence = do
  classes <- classInfos <$> get
  let className =
        case occurrence of
          "Eq" -> builtinEqClassName
          "Ord" -> builtinOrdClassName
          "Num" -> builtinNumClassName
          "Real" -> builtinRealClassName
          "Integral" -> builtinIntegralClassName
          "Fractional" -> builtinFractionalClassName
          "Floating" -> builtinFloatingClassName
          "RealFrac" -> builtinRealFracClassName
          "RealFloat" -> builtinRealFloatClassName
          "Bits" -> builtinBitsClassName
          "Show" -> builtinShowClassName
          "Read" -> builtinReadClassName
          "Enum" -> builtinEnumClassName
          "Bounded" -> builtinBoundedClassName
          "Ix" -> builtinIxClassName
          "Functor" -> builtinFunctorClassName
          "Monad" -> builtinMonadClassName
          "MonadPlus" -> builtinMonadPlusClassName
          "Storable" -> builtinStorableClassName
          _ -> RName ClassNamespace occurrence 0 True
  case Map.lookup className classes of
    Just info -> pure info
    Nothing -> throwTypecheck (UnsupportedCore0 ("missing built-in class `" <> occurrence <> "`"))

builtinDataConstructors :: Map.Map RName DataConstructorInfo
builtinDataConstructors =
  Map.fromList
    [ (listNilDataConName, positionalDataConstructorInfo [a] [] listA (Scheme [a] [] listA) CoreDataConstructor)
    ,
      ( listConsDataConName
      , positionalDataConstructorInfo
          [a]
          [aTy, listA]
          listA
          (Scheme [a] [] (TyFun aTy (TyFun listA listA)))
          CoreDataConstructor
      )
    , (unitDataConName, positionalDataConstructorInfo [] [] unitMonoType (Scheme [] [] unitMonoType) CoreDataConstructor)
    , (maybeNothingDataConName, positionalDataConstructorInfo [a] [] maybeA (Scheme [a] [] maybeA) CoreDataConstructor)
    ,
      ( maybeJustDataConName
      , positionalDataConstructorInfo
          [a]
          [aTy]
          maybeA
          (Scheme [a] [] (TyFun aTy maybeA))
          CoreDataConstructor
      )
    ,
      ( eitherLeftDataConName
      , positionalDataConstructorInfo
          [a, b]
          [aTy]
          eitherAB
          (Scheme [a, b] [] (TyFun aTy eitherAB))
          CoreDataConstructor
      )
    ,
      ( eitherRightDataConName
      , positionalDataConstructorInfo
          [a, b]
          [bTy]
          eitherAB
          (Scheme [a, b] [] (TyFun bTy eitherAB))
          CoreDataConstructor
      )
    , (orderingLTDataConName, positionalDataConstructorInfo [] [] orderingMonoType (Scheme [] [] orderingMonoType) CoreDataConstructor)
    , (orderingEQDataConName, positionalDataConstructorInfo [] [] orderingMonoType (Scheme [] [] orderingMonoType) CoreDataConstructor)
    , (orderingGTDataConName, positionalDataConstructorInfo [] [] orderingMonoType (Scheme [] [] orderingMonoType) CoreDataConstructor)
    ,
      ( ioErrorDataConName
      , positionalDataConstructorInfo
          []
          [ioErrorTypeMonoType, stringMonoType, maybeHandleMonoType, maybeFilePathMonoType]
          ioErrorMonoType
          ( Scheme
              []
              []
              (TyFun ioErrorTypeMonoType (TyFun stringMonoType (TyFun maybeHandleMonoType (TyFun maybeFilePathMonoType ioErrorMonoType))))
          )
          CoreDataConstructor
      )
    , (ioErrorAlreadyExistsTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorDoesNotExistTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorAlreadyInUseTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorFullTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorEOFTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorIllegalOperationTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorPermissionTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioErrorUserTypeDataConName, ioErrorTypeDataConstructorInfo)
    , (ioModeReadDataConName, ioModeDataConstructorInfo)
    , (ioModeWriteDataConName, ioModeDataConstructorInfo)
    , (ioModeAppendDataConName, ioModeDataConstructorInfo)
    , (ioModeReadWriteDataConName, ioModeDataConstructorInfo)
    , (bufferModeNoDataConName, bufferModeNullaryDataConstructorInfo)
    , (bufferModeLineDataConName, bufferModeNullaryDataConstructorInfo)
    ,
      ( bufferModeBlockDataConName
      , positionalDataConstructorInfo
          []
          [TyApp (TyCon maybeTyConName) intMonoType]
          bufferModeMonoType
          (Scheme [] [] (TyFun (TyApp (TyCon maybeTyConName) intMonoType) bufferModeMonoType))
          CoreDataConstructor
      )
    , (exitSuccessDataConName, positionalDataConstructorInfo [] [] exitCodeMonoType (Scheme [] [] exitCodeMonoType) CoreDataConstructor)
    ,
      ( exitFailureDataConName
      , positionalDataConstructorInfo
          []
          [intMonoType]
          exitCodeMonoType
          (Scheme [] [] (TyFun intMonoType exitCodeMonoType))
          CoreDataConstructor
      )
    , (seekModeAbsoluteDataConName, seekModeDataConstructorInfo)
    , (seekModeRelativeDataConName, seekModeDataConstructorInfo)
    , (seekModeFromEndDataConName, seekModeDataConstructorInfo)
    ,
      ( ratioDataConName
      , positionalDataConstructorInfo
          [a]
          [aTy, aTy]
          ratioA
          (Scheme [a] [] (TyFun aTy (TyFun aTy ratioA)))
          CoreDataConstructor
      )
    ,
      ( errnoDataConName
      , positionalDataConstructorInfo
          []
          [fixedIntegralMonoType FixedInt32]
          (fixedIntegralMonoType FixedInt32)
          (Scheme [] [] (TyFun (fixedIntegralMonoType FixedInt32) (fixedIntegralMonoType FixedInt32)))
          CoreNewtypeConstructor
      )
    ]
 where
  a = preludeTypeVariable "a" (-1001)
  b = preludeTypeVariable "b" (-1002)
  aTy = TyVar a
  bTy = TyVar b
  listA = TyList aTy
  maybeA = TyApp (TyCon maybeTyConName) aTy
  eitherAB = TyApp (TyApp (TyCon eitherTyConName) aTy) bTy
  ratioA = TyApp (TyCon ratioTyConName) aTy
  maybeHandleMonoType = TyApp (TyCon maybeTyConName) handleMonoType
  maybeFilePathMonoType = TyApp (TyCon maybeTyConName) filePathMonoType
  ioErrorTypeDataConstructorInfo =
    positionalDataConstructorInfo [] [] ioErrorTypeMonoType (Scheme [] [] ioErrorTypeMonoType) CoreDataConstructor
  ioModeDataConstructorInfo =
    positionalDataConstructorInfo [] [] ioModeMonoType (Scheme [] [] ioModeMonoType) CoreDataConstructor
  bufferModeNullaryDataConstructorInfo =
    positionalDataConstructorInfo [] [] bufferModeMonoType (Scheme [] [] bufferModeMonoType) CoreDataConstructor
  seekModeDataConstructorInfo =
    positionalDataConstructorInfo [] [] seekModeMonoType (Scheme [] [] seekModeMonoType) CoreDataConstructor

preludeTypeVariable :: Text -> Int -> RName
preludeTypeVariable occurrence unique =
  RName TypeVariableNamespace occurrence unique True

errnoDataConName :: RName
errnoDataConName =
  preludeTermName "Errno" (-120050)

usedClassInfos ::
  Map.Map RName ClassInfo ->
  Subst ->
  [TypedBinding] ->
  [TypedInstanceDictionary] ->
  Map.Map RName ClassInfo
usedClassInfos classes subst bindings instances =
  Map.filterWithKey (\name _ -> name `Set.member` usedNames) classes
 where
  bindingConstraints =
    concatMap typedBindingClassConstraints bindings
  instanceConstraints =
    [singleClassConstraint (typedInstanceClass dictionary) (typedInstanceType dictionary) | dictionary <- instances]
      <> concatMap typedInstanceContext instances
      <> concatMap typedInstanceSuperclasses instances
      <> concatMap (concatMap typedExprClassConstraints . typedInstanceMethods) instances
  initialUsedNames =
    Set.fromList
      [ className
      | constraint <- map (applyConstraintSubst subst) (bindingConstraints <> instanceConstraints)
      , let className = classConstraintClass constraint
      ]
  usedNames = closeSuperclassNames initialUsedNames

  closeSuperclassNames names =
    let extra =
          Set.fromList
            [ classConstraintClass superclass
            | name <- Set.toList names
            , Just info <- [Map.lookup name classes]
            , superclass <- classInfoSuperclasses info
            ]
        names' = names <> extra
     in if names' == names then names else closeSuperclassNames names'

typedBindingClassConstraints :: TypedBinding -> [ClassConstraint]
typedBindingClassConstraints binding =
  schemeConstraints (typedBindingScheme binding) <> typedExprClassConstraints (typedBindingRhs binding)

typedExprClassConstraints :: TypedExpr -> [ClassConstraint]
typedExprClassConstraints = \case
  TVar _ scheme typeArguments _ ->
    instantiateSchemeConstraints scheme typeArguments
  TLit {} ->
    []
  TCon _ scheme typeArguments _ ->
    instantiateSchemeConstraints scheme typeArguments
  TNewtypeCon _ scheme typeArguments _ _ ->
    instantiateSchemeConstraints scheme typeArguments
  TTuple fields _ ->
    concatMap typedExprClassConstraints fields
  TList elements _ ->
    concatMap typedExprClassConstraints elements
  TLam _ body _ ->
    typedExprClassConstraints body
  TApp fn arg _ ->
    typedExprClassConstraints fn <> typedExprClassConstraints arg
  TLet bindings body _ ->
    concatMap typedBindingClassConstraints bindings <> typedExprClassConstraints body
  TCase scrutinee _ alternatives _ ->
    typedExprClassConstraints scrutinee <> concatMap typedAltClassConstraints alternatives
  TCoerce expression _ ->
    typedExprClassConstraints expression
  TPrim _ arguments _ ->
    concatMap typedExprClassConstraints arguments

typedAltClassConstraints :: TypedAlt -> [ClassConstraint]
typedAltClassConstraints (TypedAlt _ _ body) =
  typedExprClassConstraints body

applyConstraintSubst :: Subst -> ClassConstraint -> ClassConstraint
applyConstraintSubst subst =
  mapClassConstraintArguments (applySubst subst)

filterClassDictionaryConstructors ::
  Map.Map RName ClassInfo ->
  Map.Map RName ClassInfo ->
  Map.Map RName DataConstructorInfo ->
  Map.Map RName DataConstructorInfo
filterClassDictionaryConstructors allClasses usedClasses =
  Map.filterWithKey keepConstructor
 where
  allDictionaryConstructors =
    Set.fromList (map classInfoDictConstructorName (Map.elems allClasses))
  usedDictionaryConstructors =
    Set.fromList (map classInfoDictConstructorName (Map.elems usedClasses))
  keepConstructor name _ =
    name `Set.notMember` allDictionaryConstructors || name `Set.member` usedDictionaryConstructors

constructorInfosToCore ::
  Subst ->
  Map.Map RName DataConstructorInfo ->
  Either TypecheckError (Map.Map RName CoreConstructorInfo)
constructorInfosToCore subst =
  traverse toCore
 where
  toCore info =
    CoreConstructorInfo (dataConstructorTyVars info)
      <$> maybe (traverse (monoToCoreType subst Map.empty) (dataConstructorFields info)) pure (dataConstructorCoreFields info)
      <*> monoToCoreType subst Map.empty (dataConstructorResult info)
      <*> pure (dataConstructorRepresentation info)

tupleConstructorInfos :: Set.Set Int -> Map.Map RName CoreConstructorInfo
tupleConstructorInfos =
  Map.fromList . map (\arity -> (tupleDataConName arity, tupleConstructorInfo arity)) . Set.toList

tupleConstructorInfo :: Int -> CoreConstructorInfo
tupleConstructorInfo arity =
  CoreConstructorInfo variables fields (CTyTuple fields) CoreDataConstructor
 where
  variables = [preludeTypeVariable ("t" <> renderInt index) (-1100 - index) | index <- [0 .. arity - 1]]
  fields = map CTyVar variables

collectTupleArities :: [RDecl] -> Set.Set Int
collectTupleArities =
  Set.unions . map declTupleArities

declTupleArities :: RDecl -> Set.Set Int
declTupleArities = \case
  RTypeSignature _ ty -> typeTupleArities ty
  RFunctionBinding _ patterns rhs whereDecls ->
    Set.unions (map patternTupleArities patterns)
      <> rhsTupleArities rhs
      <> collectTupleArities whereDecls
  RPatternBinding pat rhs whereDecls ->
    patternTupleArities pat <> rhsTupleArities rhs <> collectTupleArities whereDecls
  RDataDecl _ _ constructors _ ->
    Set.unions [Set.unions (map typeTupleArities (conDeclFieldTypes constructor)) | constructor <- constructors]
  RNewtypeDecl _ _ constructor _ ->
    Set.unions (map typeTupleArities (conDeclFieldTypes constructor))
  RTypeSynonym _ _ ty ->
    typeTupleArities ty
  RClassDecl constraints _ _ decls ->
    Set.unions (map typeTupleArities constraints) <> collectTupleArities decls
  RInstanceDecl constraints ty decls ->
    Set.unions (map typeTupleArities (ty : constraints)) <> collectTupleArities decls
  RDefaultDecl types ->
    Set.unions (map typeTupleArities types)
  RFixityDecl {} -> Set.empty
  RForeignDecl {} -> Set.empty

rhsTupleArities :: RRhs -> Set.Set Int
rhsTupleArities = \case
  RUnguarded expr -> exprTupleArities expr
  RGuarded branches -> Set.unions [exprTupleArities guard <> exprTupleArities body | (guard, body) <- branches]

exprTupleArities :: RExpr -> Set.Set Int
exprTupleArities = \case
  RVar {} -> Set.empty
  RCon {} -> Set.empty
  RLit {} -> Set.empty
  RApp fn arg -> exprTupleArities fn <> exprTupleArities arg
  RInfixApp lhs _ rhs -> exprTupleArities lhs <> exprTupleArities rhs
  RLambda patterns body -> Set.unions (map patternTupleArities patterns) <> exprTupleArities body
  RLet decls body -> collectTupleArities decls <> exprTupleArities body
  RIf condition thenBranch elseBranch ->
    exprTupleArities condition <> exprTupleArities thenBranch <> exprTupleArities elseBranch
  RCase scrutinee alternatives ->
    exprTupleArities scrutinee <> Set.unions (map altTupleArities alternatives)
  RDo statements -> Set.unions (map stmtTupleArities statements)
  RList expressions -> Set.unions (map exprTupleArities expressions)
  RTuple expressions -> Set.insert (length expressions) (Set.unions (map exprTupleArities expressions))
  RUnit -> Set.singleton 0
  RParen inner -> exprTupleArities inner
  RLeftSection expr _ -> exprTupleArities expr
  RRightSection _ expr -> exprTupleArities expr
  RArithmeticSeq start step end ->
    exprTupleArities start <> foldMap exprTupleArities step <> foldMap exprTupleArities end
  RListComp body statements -> exprTupleArities body <> Set.unions (map stmtTupleArities statements)
  RExprTypeSig expr ty -> exprTupleArities expr <> typeTupleArities ty
  RRecordCon _ fields -> Set.unions (map (exprTupleArities . snd) fields)
  RRecordUpdate scrutinee fields -> exprTupleArities scrutinee <> Set.unions (map (exprTupleArities . snd) fields)

stmtTupleArities :: RStmt -> Set.Set Int
stmtTupleArities = \case
  RBindStmt pat expr -> patternTupleArities pat <> exprTupleArities expr
  RLetStmt decls -> collectTupleArities decls
  RExprStmt expr -> exprTupleArities expr

altTupleArities :: RAlt -> Set.Set Int
altTupleArities (RAlt pat rhs whereDecls) =
  patternTupleArities pat <> rhsTupleArities rhs <> collectTupleArities whereDecls

patternTupleArities :: RPat -> Set.Set Int
patternTupleArities = \case
  RPVar {} -> Set.empty
  RPCon _ patterns -> Set.unions (map patternTupleArities patterns)
  RPRecordCon _ fields -> Set.unions (map (patternTupleArities . snd) fields)
  RPLit {} -> Set.empty
  RPWildcard -> Set.empty
  RPTuple patterns -> Set.insert (length patterns) (Set.unions (map patternTupleArities patterns))
  RPList patterns -> Set.unions (map patternTupleArities patterns)
  RPAs _ pat -> patternTupleArities pat
  RPIrrefutable pat -> patternTupleArities pat
  RPParen pat -> patternTupleArities pat

patternBindingNames :: RPat -> [RName]
patternBindingNames =
  List.nub . go
 where
  go = \case
    RPVar name -> [name]
    RPCon _ patterns -> concatMap go patterns
    RPRecordCon _ fields -> concatMap (go . snd) fields
    RPLit {} -> []
    RPWildcard -> []
    RPTuple patterns -> concatMap go patterns
    RPList patterns -> concatMap go patterns
    RPAs name pat -> name : go pat
    RPIrrefutable pat -> go pat
    RPParen pat -> go pat

typeTupleArities :: RHsType -> Set.Set Int
typeTupleArities = \case
  RTyVar {} -> Set.empty
  RTyCon {} -> Set.empty
  RTyApp fn arg -> typeTupleArities fn <> typeTupleArities arg
  RTyFun arg result -> typeTupleArities arg <> typeTupleArities result
  RTyContext constraints body -> Set.unions (map typeTupleArities constraints) <> typeTupleArities body
  RTyTuple fields -> Set.insert (length fields) (Set.unions (map typeTupleArities fields))
  RTyList elementType -> typeTupleArities elementType
  RTyParen inner -> typeTupleArities inner

collectPreludeValueNames :: [RDecl] -> [RName]
collectPreludeValueNames =
  List.nub . concatMap declPreludeValueNames

declPreludeValueNames :: RDecl -> [RName]
declPreludeValueNames = \case
  RTypeSignature {} -> []
  RFunctionBinding _ patterns rhs whereDecls ->
    concatMap patternPreludeValueNames patterns <> rhsPreludeValueNames rhs <> collectPreludeValueNames whereDecls
  RPatternBinding pat rhs whereDecls ->
    patternPreludeValueNames pat <> rhsPreludeValueNames rhs <> collectPreludeValueNames whereDecls
  RDataDecl {} -> []
  RNewtypeDecl {} -> []
  RTypeSynonym {} -> []
  RClassDecl _ _ _ decls -> collectPreludeValueNames decls
  RInstanceDecl _ _ decls -> collectPreludeValueNames decls
  RDefaultDecl {} -> []
  RFixityDecl {} -> []
  RForeignDecl {} -> []

rhsPreludeValueNames :: RRhs -> [RName]
rhsPreludeValueNames = \case
  RUnguarded expr -> exprPreludeValueNames expr
  RGuarded branches -> concat [exprPreludeValueNames guard <> exprPreludeValueNames body | (guard, body) <- branches]

exprPreludeValueNames :: RExpr -> [RName]
exprPreludeValueNames = \case
  RVar name -> [name | isSupportedPreludeValue name]
  RCon {} -> []
  RLit {} -> []
  RApp fn arg -> exprPreludeValueNames fn <> exprPreludeValueNames arg
  RInfixApp lhs op rhs -> [op | isSupportedPreludeValue op] <> exprPreludeValueNames lhs <> exprPreludeValueNames rhs
  RLambda patterns body -> concatMap patternPreludeValueNames patterns <> exprPreludeValueNames body
  RLet decls body -> collectPreludeValueNames decls <> exprPreludeValueNames body
  RIf condition thenBranch elseBranch ->
    exprPreludeValueNames condition <> exprPreludeValueNames thenBranch <> exprPreludeValueNames elseBranch
  RCase scrutinee alternatives ->
    exprPreludeValueNames scrutinee <> concatMap altPreludeValueNames alternatives
  RDo statements -> concatMap stmtPreludeValueNames statements
  RList expressions -> concatMap exprPreludeValueNames expressions
  RTuple expressions -> concatMap exprPreludeValueNames expressions
  RUnit -> []
  RParen inner -> exprPreludeValueNames inner
  RLeftSection expr op -> [op | isSupportedPreludeValue op] <> exprPreludeValueNames expr
  RRightSection op expr -> [op | isSupportedPreludeValue op] <> exprPreludeValueNames expr
  RArithmeticSeq start step end ->
    arithmeticSequencePreludeNames <> exprPreludeValueNames start <> foldMap exprPreludeValueNames step <> foldMap exprPreludeValueNames end
  RListComp body statements -> exprPreludeValueNames body <> concatMap stmtPreludeValueNames statements
  RExprTypeSig expr _ -> exprPreludeValueNames expr
  RRecordCon _ fields -> concatMap (exprPreludeValueNames . snd) fields
  RRecordUpdate scrutinee fields -> exprPreludeValueNames scrutinee <> concatMap (exprPreludeValueNames . snd) fields

stmtPreludeValueNames :: RStmt -> [RName]
stmtPreludeValueNames = \case
  RBindStmt pat expr -> patternPreludeValueNames pat <> exprPreludeValueNames expr
  RLetStmt decls -> collectPreludeValueNames decls
  RExprStmt expr -> exprPreludeValueNames expr

altPreludeValueNames :: RAlt -> [RName]
altPreludeValueNames (RAlt pat rhs whereDecls) =
  patternPreludeValueNames pat <> rhsPreludeValueNames rhs <> collectPreludeValueNames whereDecls

patternPreludeValueNames :: RPat -> [RName]
patternPreludeValueNames = \case
  RPVar {} -> []
  RPCon _ patterns -> concatMap patternPreludeValueNames patterns
  RPRecordCon _ fields -> concatMap (patternPreludeValueNames . snd) fields
  RPLit {} -> []
  RPWildcard -> []
  RPTuple patterns -> concatMap patternPreludeValueNames patterns
  RPList patterns -> concatMap patternPreludeValueNames patterns
  RPAs _ pat -> patternPreludeValueNames pat
  RPIrrefutable pat -> patternPreludeValueNames pat
  RPParen pat -> patternPreludeValueNames pat

isSupportedPreludeValue :: RName -> Bool
isSupportedPreludeValue name =
  nameExternal name && nameOcc name `elem` supportedPreludeValueOccurrences

supportedPreludeValueOccurrences :: [Text]
supportedPreludeValueOccurrences =
  [ "id"
  , "const"
  , "not"
  , "otherwise"
  , "$"
  , "."
  , "flip"
  , "fmap"
  , "map"
  , "foldr"
  , "foldl"
  , "head"
  , "tail"
  , "null"
  , "fst"
  , "snd"
  , "length"
  , "filter"
  , "reverse"
  , "++"
  , "mapM"
  , "mapM_"
  , "forM"
  , "forM_"
  , "sequence"
  , "sequence_"
  , "=<<"
  , ">=>"
  , "<=<"
  , "forever"
  , "join"
  , "msum"
  , "filterM"
  , "mapAndUnzipM"
  , "zipWithM"
  , "zipWithM_"
  , "foldM"
  , "foldM_"
  , "replicateM"
  , "replicateM_"
  , "guard"
  , "when"
  , "unless"
  , "liftM"
  , "liftM2"
  , "liftM3"
  , "liftM4"
  , "liftM5"
  , "ap"
  , "showsPrec"
  , "show"
  , "showList"
  , "shows"
  , "readsPrec"
  , "readList"
  , "reads"
  , "read"
  , "lex"
  , "readParen"
  , "putStrLn"
  , "getLine"
  , "print"
  , "userError"
  , "mkIOError"
  , "annotateIOError"
  , "isAlreadyExistsError"
  , "isDoesNotExistError"
  , "isAlreadyInUseError"
  , "isFullError"
  , "isEOFError"
  , "isIllegalOperation"
  , "isPermissionError"
  , "isUserError"
  , "ioeGetErrorString"
  , "ioeGetHandle"
  , "ioeGetFileName"
  , "alreadyExistsErrorType"
  , "doesNotExistErrorType"
  , "alreadyInUseErrorType"
  , "fullErrorType"
  , "eofErrorType"
  , "illegalOperationErrorType"
  , "permissionErrorType"
  , "userErrorType"
  , "ioError"
  , "catch"
  , "try"
  , "fixIO"
  , "stdin"
  , "stdout"
  , "stderr"
  , "withFile"
  , "openFile"
  , "hClose"
  , "readFile"
  , "writeFile"
  , "appendFile"
  , "hFileSize"
  , "hSetFileSize"
  , "hIsEOF"
  , "isEOF"
  , "hSetBuffering"
  , "hGetBuffering"
  , "hFlush"
  , "hGetPosn"
  , "hSetPosn"
  , "hSeek"
  , "hTell"
  , "hIsOpen"
  , "hIsClosed"
  , "hIsReadable"
  , "hIsWritable"
  , "hIsSeekable"
  , "hIsTerminalDevice"
  , "hSetEcho"
  , "hGetEcho"
  , "hShow"
  , "hWaitForInput"
  , "hReady"
  , "hGetChar"
  , "hGetLine"
  , "hLookAhead"
  , "hGetContents"
  , "hPutChar"
  , "hPutStr"
  , "hPutStrLn"
  , "hPrint"
  , "interact"
  , "putChar"
  , "putStr"
  , "getChar"
  , "getContents"
  , "getArgs"
  , "getProgName"
  , "getEnv"
  , "exitWith"
  , "exitFailure"
  , "exitSuccess"
  , "readIO"
  , "readLn"
  , "nullPtr"
  , "castPtr"
  , "nullFunPtr"
  , "castFunPtr"
  , "castFunPtrToPtr"
  , "castPtrToFunPtr"
  , "freeHaskellFunPtr"
  , "newStablePtr"
  , "deRefStablePtr"
  , "freeStablePtr"
  , "castStablePtrToPtr"
  , "castPtrToStablePtr"
  , "newForeignPtr"
  , "newForeignPtr_"
  , "addForeignPtrFinalizer"
  , "finalizeForeignPtr"
  , "unsafeForeignPtrToPtr"
  , "withForeignPtr"
  , "touchForeignPtr"
  , "castForeignPtr"
  , "throwIf"
  , "throwIf_"
  , "throwIfNull"
  , "void"
  , "maybeNew"
  , "maybeWith"
  , "maybePeek"
  , "plusPtr"
  , "minusPtr"
  , "alignPtr"
  , "malloc"
  , "mallocBytes"
  , "alloca"
  , "allocaBytes"
  , "realloc"
  , "reallocBytes"
  , "free"
  , "finalizerFree"
  , "advancePtr"
  , "mallocArray"
  , "mallocArray0"
  , "allocaArray"
  , "allocaArray0"
  , "reallocArray"
  , "reallocArray0"
  , "peekArray"
  , "peekArray0"
  , "pokeArray"
  , "pokeArray0"
  , "newArray"
  , "newArray0"
  , "withArray"
  , "withArray0"
  , "withArrayLen"
  , "withArrayLen0"
  , "copyArray"
  , "moveArray"
  , "lengthArray0"
  , "copyBytes"
  , "moveBytes"
  , "peekCString"
  , "peekCStringLen"
  , "newCString"
  , "newCStringLen"
  , "withCString"
  , "withCStringLen"
  , "peekCAString"
  , "peekCAStringLen"
  , "newCAString"
  , "newCAStringLen"
  , "withCAString"
  , "withCAStringLen"
  , "peekCWString"
  , "peekCWStringLen"
  , "newCWString"
  , "newCWStringLen"
  , "withCWString"
  , "withCWStringLen"
  , "charIsRepresentable"
  , "castCharToCChar"
  , "castCCharToChar"
  , "castCharToCUChar"
  , "castCUCharToChar"
  , "castCharToCSChar"
  , "castCSCharToChar"
  , "eOK"
  , "e2BIG"
  , "eACCES"
  , "eADDRINUSE"
  , "eADDRNOTAVAIL"
  , "eADV"
  , "eAFNOSUPPORT"
  , "eAGAIN"
  , "eALREADY"
  , "eBADF"
  , "eBADMSG"
  , "eBADRPC"
  , "eBUSY"
  , "eCHILD"
  , "eCOMM"
  , "eCONNABORTED"
  , "eCONNREFUSED"
  , "eCONNRESET"
  , "eDEADLK"
  , "eDESTADDRREQ"
  , "eDIRTY"
  , "eDOM"
  , "eDQUOT"
  , "eEXIST"
  , "eFAULT"
  , "eFBIG"
  , "eFTYPE"
  , "eHOSTDOWN"
  , "eHOSTUNREACH"
  , "eIDRM"
  , "eILSEQ"
  , "eINPROGRESS"
  , "eINTR"
  , "eINVAL"
  , "eIO"
  , "eISCONN"
  , "eISDIR"
  , "eLOOP"
  , "eMFILE"
  , "eMLINK"
  , "eMSGSIZE"
  , "eMULTIHOP"
  , "eNAMETOOLONG"
  , "eNETDOWN"
  , "eNETRESET"
  , "eNETUNREACH"
  , "eNFILE"
  , "eNOBUFS"
  , "eNODATA"
  , "eNODEV"
  , "eNOENT"
  , "eNOEXEC"
  , "eNOLCK"
  , "eNOLINK"
  , "eNOMEM"
  , "eNOMSG"
  , "eNONET"
  , "eNOPROTOOPT"
  , "eNOSPC"
  , "eNOSR"
  , "eNOSTR"
  , "eNOSYS"
  , "eNOTBLK"
  , "eNOTCONN"
  , "eNOTDIR"
  , "eNOTEMPTY"
  , "eNOTSOCK"
  , "eNOTTY"
  , "eNXIO"
  , "eOPNOTSUPP"
  , "ePERM"
  , "ePFNOSUPPORT"
  , "ePIPE"
  , "ePROCLIM"
  , "ePROCUNAVAIL"
  , "ePROGMISMATCH"
  , "ePROGUNAVAIL"
  , "ePROTO"
  , "ePROTONOSUPPORT"
  , "ePROTOTYPE"
  , "eRANGE"
  , "eREMCHG"
  , "eREMOTE"
  , "eROFS"
  , "eRPCMISMATCH"
  , "eRREMOTE"
  , "eSHUTDOWN"
  , "eSOCKTNOSUPPORT"
  , "eSPIPE"
  , "eSRCH"
  , "eSRMNT"
  , "eSTALE"
  , "eTIME"
  , "eTIMEDOUT"
  , "eTOOMANYREFS"
  , "eTXTBSY"
  , "eUSERS"
  , "eWOULDBLOCK"
  , "eXDEV"
  , "isValidErrno"
  , "getErrno"
  , "resetErrno"
  , "errnoToIOError"
  , "throwErrno"
  , "throwErrnoIf"
  , "throwErrnoIf_"
  , "throwErrnoIfRetry"
  , "throwErrnoIfRetry_"
  , "throwErrnoIfMinus1"
  , "throwErrnoIfMinus1_"
  , "throwErrnoIfMinus1Retry"
  , "throwErrnoIfMinus1Retry_"
  , "throwErrnoIfNull"
  , "throwErrnoIfNullRetry"
  , "throwErrnoIfRetryMayBlock"
  , "throwErrnoIfRetryMayBlock_"
  , "throwErrnoIfMinus1RetryMayBlock"
  , "throwErrnoIfMinus1RetryMayBlock_"
  , "throwErrnoIfNullRetryMayBlock"
  , "throwErrnoPath"
  , "throwErrnoPathIf"
  , "throwErrnoPathIf_"
  , "throwErrnoPathIfNull"
  , "throwErrnoPathIfMinus1"
  , "throwErrnoPathIfMinus1_"
  , "return"
  , "fail"
  , ">>="
  , ">>"
  , "=="
  , "/="
  , "<"
  , "<="
  , ">"
  , ">="
  , "compare"
  , "max"
  , "min"
  , "succ"
  , "pred"
  , "toEnum"
  , "fromEnum"
  , "enumFrom"
  , "enumFromThen"
  , "enumFromTo"
  , "enumFromThenTo"
  , "minBound"
  , "maxBound"
  , "+"
  , "-"
  , "*"
  , "negate"
  , "abs"
  , "signum"
  , "fromInteger"
  , "toRational"
  , "%"
  , "numerator"
  , "denominator"
  , "approxRational"
  , "quot"
  , "rem"
  , "div"
  , "mod"
  , "quotRem"
  , "divMod"
  , "toInteger"
  ]

errnoConstantValues :: [(Text, Integer)]
errnoConstantValues =
  [ ("eOK", 0)
  , ("e2BIG", 7)
  , ("eACCES", 13)
  , ("eADDRINUSE", 48)
  , ("eADDRNOTAVAIL", 49)
  , ("eADV", -1)
  , ("eAFNOSUPPORT", 47)
  , ("eAGAIN", 35)
  , ("eALREADY", 37)
  , ("eBADF", 9)
  , ("eBADMSG", 94)
  , ("eBADRPC", 72)
  , ("eBUSY", 16)
  , ("eCHILD", 10)
  , ("eCOMM", -1)
  , ("eCONNABORTED", 53)
  , ("eCONNREFUSED", 61)
  , ("eCONNRESET", 54)
  , ("eDEADLK", 11)
  , ("eDESTADDRREQ", 39)
  , ("eDIRTY", -1)
  , ("eDOM", 33)
  , ("eDQUOT", 69)
  , ("eEXIST", 17)
  , ("eFAULT", 14)
  , ("eFBIG", 27)
  , ("eFTYPE", 79)
  , ("eHOSTDOWN", 64)
  , ("eHOSTUNREACH", 65)
  , ("eIDRM", 90)
  , ("eILSEQ", 92)
  , ("eINPROGRESS", 36)
  , ("eINTR", 4)
  , ("eINVAL", 22)
  , ("eIO", 5)
  , ("eISCONN", 56)
  , ("eISDIR", 21)
  , ("eLOOP", 62)
  , ("eMFILE", 24)
  , ("eMLINK", 31)
  , ("eMSGSIZE", 40)
  , ("eMULTIHOP", 95)
  , ("eNAMETOOLONG", 63)
  , ("eNETDOWN", 50)
  , ("eNETRESET", 52)
  , ("eNETUNREACH", 51)
  , ("eNFILE", 23)
  , ("eNOBUFS", 55)
  , ("eNODATA", 96)
  , ("eNODEV", 19)
  , ("eNOENT", 2)
  , ("eNOEXEC", 8)
  , ("eNOLCK", 77)
  , ("eNOLINK", 97)
  , ("eNOMEM", 12)
  , ("eNOMSG", 91)
  , ("eNONET", -1)
  , ("eNOPROTOOPT", 42)
  , ("eNOSPC", 28)
  , ("eNOSR", 98)
  , ("eNOSTR", 99)
  , ("eNOSYS", 78)
  , ("eNOTBLK", 15)
  , ("eNOTCONN", 57)
  , ("eNOTDIR", 20)
  , ("eNOTEMPTY", 66)
  , ("eNOTSOCK", 38)
  , ("eNOTTY", 25)
  , ("eNXIO", 6)
  , ("eOPNOTSUPP", 102)
  , ("ePERM", 1)
  , ("ePFNOSUPPORT", 46)
  , ("ePIPE", 32)
  , ("ePROCLIM", 67)
  , ("ePROCUNAVAIL", 76)
  , ("ePROGMISMATCH", 75)
  , ("ePROGUNAVAIL", 74)
  , ("ePROTO", 100)
  , ("ePROTONOSUPPORT", 43)
  , ("ePROTOTYPE", 41)
  , ("eRANGE", 34)
  , ("eREMCHG", -1)
  , ("eREMOTE", 71)
  , ("eROFS", 30)
  , ("eRPCMISMATCH", 73)
  , ("eRREMOTE", -1)
  , ("eSHUTDOWN", 58)
  , ("eSOCKTNOSUPPORT", 44)
  , ("eSPIPE", 29)
  , ("eSRCH", 3)
  , ("eSRMNT", -1)
  , ("eSTALE", 70)
  , ("eTIME", 101)
  , ("eTIMEDOUT", 60)
  , ("eTOOMANYREFS", 59)
  , ("eTXTBSY", 26)
  , ("eUSERS", 68)
  , ("eWOULDBLOCK", 35)
  , ("eXDEV", 18)
  ]

errnoConstantValue :: Text -> Maybe Integer
errnoConstantValue occurrence =
  lookup occurrence errnoConstantValues

isErrnoConstantOccurrence :: Text -> Bool
isErrnoConstantOccurrence occurrence =
  maybe False (const True) (errnoConstantValue occurrence)

validErrnoValues :: [Integer]
validErrnoValues =
  List.nub [value | (_, value) <- errnoConstantValues, value >= 0]

inferBindingGroup :: TypeEnv -> [RDecl] -> InferM ([TypedBinding], TypeEnv)
inferBindingGroup outerEnv decls = do
  signatures <- collectSignatures decls
  sourceBindings <- collectValueBindings decls
  let bindingNames = map sourceBindingName sourceBindings
  mapM_ (ensureSignatureHasBinding bindingNames) (Map.keys signatures)
  prepared <- traverse (prepareBinding signatures) sourceBindings
  inferPreparedComponents outerEnv signatures prepared

inferPreparedComponents :: TypeEnv -> Map.Map RName Scheme -> [PreparedBinding] -> InferM ([TypedBinding], TypeEnv)
inferPreparedComponents outerEnv signatures prepared =
  foldM inferComponent ([], outerEnv) (preparedBindingComponents prepared)
 where
  inferComponent (bindingsAcc, env) component = do
    let recursiveEnv =
          Map.union
            (Map.fromList [(preparedName binding, preparedScheme binding) | binding <- component])
            env
    inferred <- traverse (inferPreparedBinding recursiveEnv) component
    defaultBindingGroupConstraints inferred
    finalized <- traverse (finalizeBinding env signatures) inferred
    subst <- substitution <$> get
    let groupSchemes = Map.fromList [(typedBindingName binding, typedBindingScheme binding) | binding <- finalized]
        finalizedWithRecursiveSchemes = map (refreshBindingReferences subst groupSchemes) finalized
        env' = Map.union groupSchemes env
    pure (bindingsAcc <> finalizedWithRecursiveSchemes, env')

preparedBindingComponents :: [PreparedBinding] -> [[PreparedBinding]]
preparedBindingComponents prepared =
  map flattenSCC (Graph.stronglyConnComp graphNodes)
 where
  bindingNames = Set.fromList (map preparedName prepared)
  graphNodes =
    [ ( binding
      , preparedName binding
      , Set.toList (preparedBindingDependencies binding `Set.intersection` bindingNames)
      )
    | binding <- prepared
    ]
  flattenSCC = \case
    Graph.AcyclicSCC binding -> [binding]
    Graph.CyclicSCC bindings -> bindings

preparedBindingDependencies :: PreparedBinding -> Set.Set RName
preparedBindingDependencies binding =
  Set.unions
    [ rhsFreeTermNames (preparedRhs binding)
    , Set.unions (map declFreeTermNames (preparedWhereDecls binding))
    ]

declFreeTermNames :: RDecl -> Set.Set RName
declFreeTermNames = \case
  RFunctionBinding _ _ rhs whereDecls ->
    rhsFreeTermNames rhs <> Set.unions (map declFreeTermNames whereDecls)
  RPatternBinding _ rhs whereDecls ->
    rhsFreeTermNames rhs <> Set.unions (map declFreeTermNames whereDecls)
  RClassDecl _ _ _ decls ->
    Set.unions (map declFreeTermNames decls)
  RInstanceDecl _ _ decls ->
    Set.unions (map declFreeTermNames decls)
  _ ->
    Set.empty

rhsFreeTermNames :: RRhs -> Set.Set RName
rhsFreeTermNames = \case
  RUnguarded expr ->
    exprFreeTermNames expr
  RGuarded branches ->
    Set.unions [exprFreeTermNames guard <> exprFreeTermNames body | (guard, body) <- branches]

exprFreeTermNames :: RExpr -> Set.Set RName
exprFreeTermNames = \case
  RVar name -> Set.singleton name
  RCon {} -> Set.empty
  RLit {} -> Set.empty
  RApp fn arg -> exprFreeTermNames fn <> exprFreeTermNames arg
  RInfixApp lhs op rhs -> Set.insert op (exprFreeTermNames lhs <> exprFreeTermNames rhs)
  RLambda _ body -> exprFreeTermNames body
  RLet decls body -> Set.unions (map declFreeTermNames decls) <> exprFreeTermNames body
  RIf condition thenBranch elseBranch ->
    exprFreeTermNames condition <> exprFreeTermNames thenBranch <> exprFreeTermNames elseBranch
  RCase scrutinee alternatives ->
    exprFreeTermNames scrutinee <> Set.unions (map altFreeTermNames alternatives)
  RDo statements ->
    Set.unions (map stmtFreeTermNames statements)
  RList expressions ->
    Set.unions (map exprFreeTermNames expressions)
  RTuple expressions ->
    Set.unions (map exprFreeTermNames expressions)
  RUnit ->
    Set.empty
  RParen inner ->
    exprFreeTermNames inner
  RLeftSection expr op ->
    Set.insert op (exprFreeTermNames expr)
  RRightSection op expr ->
    Set.insert op (exprFreeTermNames expr)
  RArithmeticSeq start step end ->
    exprFreeTermNames start <> foldMap exprFreeTermNames step <> foldMap exprFreeTermNames end
  RListComp body statements ->
    exprFreeTermNames body <> Set.unions (map stmtFreeTermNames statements)
  RExprTypeSig expr _ ->
    exprFreeTermNames expr
  RRecordCon _ fields ->
    Set.unions (map (exprFreeTermNames . snd) fields)
  RRecordUpdate scrutinee fields ->
    exprFreeTermNames scrutinee <> Set.unions (map (exprFreeTermNames . snd) fields)

stmtFreeTermNames :: RStmt -> Set.Set RName
stmtFreeTermNames = \case
  RBindStmt _ expr ->
    exprFreeTermNames expr
  RLetStmt decls ->
    Set.unions (map declFreeTermNames decls)
  RExprStmt expr ->
    exprFreeTermNames expr

altFreeTermNames :: RAlt -> Set.Set RName
altFreeTermNames (RAlt _ rhs whereDecls) =
  rhsFreeTermNames rhs <> Set.unions (map declFreeTermNames whereDecls)

defaultBindingGroupConstraints :: [InferredBinding] -> InferM ()
defaultBindingGroupConstraints inferred = do
  defaults <- defaultTypes <$> get
  unless (null defaults) $ do
    subst <- substitution <$> get
    let constraints =
          List.nub
            ( map
                (applyConstraintSubst subst)
                (concatMap inferredBindingClassConstraints inferred)
            )
        protectedMetas =
          Set.unions
            [ freeMetaVars (applySubst subst (typedExprType rhs))
            | InferredBinding prepared rhs <- inferred
            , not (canDefaultBindingResult prepared)
            ]
        candidates = defaultableConstraintMetas protectedMetas constraints
    traverse_
      ( \(meta, metaConstraints) ->
          case selectDefaultType meta metaConstraints defaults of
            Just defaultTy -> unify (TyMeta meta) defaultTy
            Nothing -> pure ()
      )
      candidates

inferredBindingClassConstraints :: InferredBinding -> [ClassConstraint]
inferredBindingClassConstraints (InferredBinding _ rhs) =
  typedExprDefaultingConstraints rhs

typedExprDefaultingConstraints :: TypedExpr -> [ClassConstraint]
typedExprDefaultingConstraints = \case
  TVar _ scheme typeArguments _ ->
    instantiateSchemeConstraints scheme typeArguments
  TLit {} ->
    []
  TCon _ scheme typeArguments _ ->
    instantiateSchemeConstraints scheme typeArguments
  TNewtypeCon _ scheme typeArguments _ _ ->
    instantiateSchemeConstraints scheme typeArguments
  TTuple fields _ ->
    concatMap typedExprDefaultingConstraints fields
  TList elements _ ->
    concatMap typedExprDefaultingConstraints elements
  TLam _ body _ ->
    typedExprDefaultingConstraints body
  TApp fn arg _ ->
    typedExprDefaultingConstraints fn <> typedExprDefaultingConstraints arg
  TLet _ body _ ->
    typedExprDefaultingConstraints body
  TCase scrutinee _ alternatives _ ->
    typedExprDefaultingConstraints scrutinee <> concatMap typedAltDefaultingConstraints alternatives
  TCoerce expression _ ->
    typedExprDefaultingConstraints expression
  TPrim _ arguments _ ->
    concatMap typedExprDefaultingConstraints arguments

typedAltDefaultingConstraints :: TypedAlt -> [ClassConstraint]
typedAltDefaultingConstraints (TypedAlt _ _ body) =
  typedExprDefaultingConstraints body

-- TYPE-019 policy: the executable subset treats unsigned nullary bindings as
-- eligible for standard-class defaulting before generalization. Signed bindings
-- and functions with value parameters keep their result metas protected.
canDefaultBindingResult :: PreparedBinding -> Bool
canDefaultBindingResult prepared =
  not (preparedHasSignature prepared) && null (preparedPatterns prepared)

defaultableConstraintMetas :: Set.Set Int -> [ClassConstraint] -> [(Int, [ClassConstraint])]
defaultableConstraintMetas protectedMetas constraints =
  [ (meta, metaConstraints)
  | (meta, metaConstraints) <- Map.toAscList constraintsByMeta
  , meta `Set.notMember` protectedMetas
  , all (isDefaultingCompatibleConstraint meta) metaConstraints
  , any (isDefaultingTriggerClass . constraintClassName) metaConstraints
  ]
 where
  constraintsByMeta =
    Map.fromListWith
      (<>)
      [ (meta, [constraint])
      | constraint <- constraints
      , meta <- Set.toList (freeMetaVarsConstraint constraint)
      ]

isDefaultingCompatibleConstraint :: Int -> ClassConstraint -> Bool
isDefaultingCompatibleConstraint expectedMeta constraint =
  isStandardDefaultingClass (constraintClassName constraint)
    && case classConstraintArguments constraint of
      [TyMeta meta] ->
        meta == expectedMeta
      [argument]
        | constraintClassName constraint == builtinShowClassName ->
            isStructuralShowMetaArgument expectedMeta argument
      _ ->
        False

isStructuralShowMetaArgument :: Int -> MonoType -> Bool
isStructuralShowMetaArgument expectedMeta = \case
  TyList element ->
    isStructuralShowMetaArgument expectedMeta element
  TyMeta meta ->
    meta == expectedMeta
  _ ->
    False

constraintClassName :: ClassConstraint -> RName
constraintClassName =
  classConstraintClass

isStandardDefaultingClass :: RName -> Bool
isStandardDefaultingClass className =
  className `Set.member` standardDefaultingClasses

isDefaultingTriggerClass :: RName -> Bool
isDefaultingTriggerClass className =
  className `Set.member` numericDefaultingClasses

selectDefaultType :: Int -> [ClassConstraint] -> [MonoType] -> Maybe MonoType
selectDefaultType meta constraints =
  List.find (satisfiesAll . replaceMeta)
 where
  replaceMeta defaultTy =
    map (mapClassConstraintArguments (replaceDefaultableMeta defaultTy)) constraints
  satisfiesAll =
    all isBuiltinInstanceConstraint
  replaceDefaultableMeta defaultTy = \case
    TyMeta candidate
      | candidate == meta -> defaultTy
    TyApp fn arg ->
      TyApp (replaceDefaultableMeta defaultTy fn) (replaceDefaultableMeta defaultTy arg)
    TyFun arg result ->
      TyFun (replaceDefaultableMeta defaultTy arg) (replaceDefaultableMeta defaultTy result)
    TyTuple fields ->
      TyTuple (map (replaceDefaultableMeta defaultTy) fields)
    TyList element ->
      TyList (replaceDefaultableMeta defaultTy element)
    other ->
      other

standardDefaultingClasses :: Set.Set RName
standardDefaultingClasses =
  Set.fromList
    [ builtinEqClassName
    , builtinOrdClassName
    , builtinEnumClassName
    , builtinBoundedClassName
    , builtinNumClassName
    , builtinRealClassName
    , builtinIntegralClassName
    , builtinFractionalClassName
    , builtinFloatingClassName
    , builtinRealFracClassName
    , builtinRealFloatClassName
    , builtinShowClassName
    ]

numericDefaultingClasses :: Set.Set RName
numericDefaultingClasses =
  Set.fromList
    [ builtinNumClassName
    , builtinRealClassName
    , builtinIntegralClassName
    , builtinFractionalClassName
    , builtinFloatingClassName
    , builtinRealFracClassName
    , builtinRealFloatClassName
    ]

refreshBindingReferences :: Subst -> Map.Map RName Scheme -> TypedBinding -> TypedBinding
refreshBindingReferences subst schemes binding =
  binding {typedBindingRhs = refreshExprReferences subst schemes (typedBindingRhs binding)}

refreshExprReferences :: Subst -> Map.Map RName Scheme -> TypedExpr -> TypedExpr
refreshExprReferences subst schemes = \case
  TVar name oldScheme oldTypeArguments ty ->
    case Map.lookup name schemes of
      Nothing ->
        TVar name oldScheme oldTypeArguments ty
      Just scheme ->
        TVar name scheme (schemeTypeArgumentsFor subst scheme ty) ty
  TLit literal ty ->
    TLit literal ty
  TCon name scheme typeArguments ty ->
    TCon name scheme typeArguments ty
  TNewtypeCon name scheme typeArguments ty binder ->
    TNewtypeCon name scheme typeArguments ty binder
  TTuple fields ty ->
    TTuple (map (refreshExprReferences subst schemes) fields) ty
  TList elements ty ->
    TList (map (refreshExprReferences subst schemes) elements) ty
  TLam binder body ty ->
    TLam binder (refreshExprReferences subst schemes body) ty
  TApp fn arg ty ->
    TApp (refreshExprReferences subst schemes fn) (refreshExprReferences subst schemes arg) ty
  TLet bindings body ty ->
    TLet (map (refreshBindingReferences subst schemes) bindings) (refreshExprReferences subst schemes body) ty
  TCase scrutinee binder alternatives ty ->
    TCase (refreshExprReferences subst schemes scrutinee) binder (map (refreshAltReferences subst schemes) alternatives) ty
  TCoerce expression ty ->
    TCoerce (refreshExprReferences subst schemes expression) ty
  TPrim op arguments ty ->
    TPrim op (map (refreshExprReferences subst schemes) arguments) ty

refreshAltReferences :: Subst -> Map.Map RName Scheme -> TypedAlt -> TypedAlt
refreshAltReferences subst schemes (TypedAlt altCon binders body) =
  TypedAlt altCon binders (refreshExprReferences subst schemes body)

schemeTypeArgumentsFor :: Subst -> Scheme -> MonoType -> [MonoType]
schemeTypeArgumentsFor subst scheme ty =
  case matchSchemeBody subst scheme ty of
    Just replacements ->
      [ Map.findWithDefault (TyVar variable) variable replacements
      | variable <- schemeVars scheme
      ]
    Nothing ->
      []

matchSchemeBody :: Subst -> Scheme -> MonoType -> Maybe (Map.Map RName MonoType)
matchSchemeBody subst scheme ty =
  matchMonoTypes (Set.fromList (schemeVars scheme)) (applySubst subst (schemeBody scheme)) (applySubst subst ty) Map.empty

matchMonoTypes :: Set.Set RName -> MonoType -> MonoType -> Map.Map RName MonoType -> Maybe (Map.Map RName MonoType)
matchMonoTypes variables patternTy actualTy replacements =
  case patternTy of
    TyVar name
      | name `Set.member` variables ->
          case Map.lookup name replacements of
            Nothing -> Just (Map.insert name actualTy replacements)
            Just existing
              | existing == actualTy -> Just replacements
              | otherwise -> Nothing
      | patternTy == actualTy -> Just replacements
      | otherwise -> Nothing
    TyMeta _
      | patternTy == actualTy -> Just replacements
      | otherwise -> Nothing
    TyCon name ->
      case actualTy of
        TyCon actualName
          | name == actualName -> Just replacements
        _ -> Nothing
    TyApp patternFn patternArg ->
      case actualTy of
        TyApp actualFn actualArg ->
          matchMonoTypes variables patternFn actualFn replacements
            >>= matchMonoTypes variables patternArg actualArg
        TyList actualElement
          | TyCon name <- patternFn
          , name == listTyConName ->
              matchMonoTypes variables patternArg actualElement replacements
        _ -> Nothing
    TyFun patternArg patternResult ->
      case actualTy of
        TyFun actualArg actualResult ->
          matchMonoTypes variables patternArg actualArg replacements
            >>= matchMonoTypes variables patternResult actualResult
        _ -> Nothing
    TyTuple patternFields ->
      case actualTy of
        TyTuple actualFields
          | length patternFields == length actualFields ->
              foldM
                (\acc (patternField, actualField) -> matchMonoTypes variables patternField actualField acc)
                replacements
                (zip patternFields actualFields)
        _ -> Nothing
    TyList patternElement ->
      case actualTy of
        TyList actualElement ->
          matchMonoTypes variables patternElement actualElement replacements
        TyApp actualFn actualArg
          | TyCon name <- actualFn
          , name == listTyConName ->
              matchMonoTypes variables patternElement actualArg replacements
        _ -> Nothing

data SourceBinding = SourceBinding
  { sourceBindingSpan :: Maybe SourceSpan
  , sourceBindingName :: RName
  , sourceBindingPatterns :: [RPat]
  , sourceBindingPatternBinding :: Maybe RPat
  , sourceBindingRhs :: RRhs
  , sourceBindingWhereDecls :: [RDecl]
  }
  deriving stock (Show, Eq, Ord)

data PreparedBinding = PreparedBinding
  { preparedSpan :: Maybe SourceSpan
  , preparedName :: RName
  , preparedPatterns :: [RPat]
  , preparedPatternBinding :: Maybe RPat
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
  collect acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RTypeSignature names sourceType -> do
          scheme <- sourceScheme sourceType
          validateSchemeConstraints scheme
          foldM (insertSignature scheme) acc names
        _ ->
          pure acc

  insertSignature scheme acc name =
    case Map.lookup name acc of
      Just _ -> throwTypecheck (DuplicateTypeSignature name)
      Nothing -> pure (Map.insert name scheme acc)

validateSchemeConstraints :: Scheme -> InferM ()
validateSchemeConstraints scheme = do
  classes <- classInfos <$> get
  traverse_ (validateConstraint classes) (schemeConstraints scheme)
 where
  validateConstraint classes constraint = do
    let actualArity = length (classConstraintArguments constraint)
    unless (actualArity == 1) $
      throwTypecheck (InvalidClassConstraintArity (classConstraintClass constraint) actualArity)
    unless (Map.member (classConstraintClass constraint) classes) $
      throwTypecheck (UnsupportedCore0 ("unknown type-class constraint `" <> renderClassConstraint constraint <> "`"))

collectDefaultTypes :: [RDecl] -> InferM [MonoType]
collectDefaultTypes decls =
  case [types | RDefaultDecl types <- decls] of
    [] ->
      pure [intMonoType, doubleMonoType]
    [types] ->
      traverse defaultTypeMonoType types
    _ ->
      throwTypecheck (UnsupportedCore0 "multiple default declarations")

defaultTypeMonoType :: RHsType -> InferM MonoType
defaultTypeMonoType sourceType = do
  expanded <- expandSourceTypeSynonyms sourceType
  case sourceTypeWithoutParens expanded of
    RTyCon name
      | nameOcc name == "Int" -> pure intMonoType
      | nameOcc name == "Integer" -> pure intMonoType
      | nameOcc name == "Float" -> pure floatMonoType
      | nameOcc name == "Double" -> pure doubleMonoType
    other ->
      throwTypecheck (UnsupportedCore0 ("default type " <> Text.pack (show other)))

validateForeignDecls :: [RDecl] -> InferM ()
validateForeignDecls =
  traverse_ validateForeignDecl

foreignImportTypeEnv :: [RDecl] -> InferM TypeEnv
foreignImportTypeEnv =
  foldM collect Map.empty
 where
  collect acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RForeignDecl (RForeignImportDecl foreignImport) -> do
          scheme <- foreignImportScheme foreignImport
          pure (Map.insert (rForeignImportName foreignImport) scheme acc)
        _ ->
          pure acc

validateForeignDecl :: RDecl -> InferM ()
validateForeignDecl decl =
  withTypecheckSpan (rDeclSpan decl) $
    case decl of
      RForeignDecl (RForeignImportDecl foreignImport) ->
        validateForeignImport foreignImport
      RForeignDecl (RForeignExportDecl foreignExport) ->
        validateForeignExport foreignExport
      _ ->
        pure ()

validateForeignExportsAgainstEnv :: TypeEnv -> [RDecl] -> InferM ()
validateForeignExportsAgainstEnv env =
  traverse_ validateExport
 where
  validateExport decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RForeignDecl (RForeignExportDecl foreignExport) -> do
          declaredTy <- foreignDeclarationMonoType "foreign export" (rForeignExportType foreignExport)
          case Map.lookup (rForeignExportName foreignExport) env of
            Nothing ->
              throwTypecheck (UnknownCore0Variable (rForeignExportName foreignExport))
            Just scheme@(Scheme _ constraints _) -> do
              unless (null constraints) $
                throwTypecheck (UnsupportedCore0 ("foreign export target `" <> renderRName (rForeignExportName foreignExport) <> "` has constrained type"))
              (actualTy, _) <- instantiate scheme
              unify actualTy declaredTy
        _ ->
          pure ()

validateForeignImport :: RForeignImport -> InferM ()
validateForeignImport foreignImport = do
  validateForeignCallConv "foreign import" (rForeignImportCallConv foreignImport)
  ty <- foreignDeclarationMonoType "foreign import" (rForeignImportType foreignImport)
  case S.foreignImportEntityKind (rForeignImportEntity foreignImport) of
    S.ForeignImportDefault ->
      validateForeignFunctionType "foreign import" ty
    S.ForeignImportStatic {} ->
      validateForeignFunctionType "foreign import static" ty
    S.ForeignImportAddress {} ->
      validateForeignAddressType ty
    S.ForeignImportDynamic ->
      validateForeignDynamicType ty
    S.ForeignImportWrapper ->
      validateForeignWrapperType ty
    S.ForeignImportUnknown raw ->
      throwTypecheck (UnsupportedCore0 ("unknown foreign import entity `" <> raw <> "`"))

validateForeignExport :: RForeignExport -> InferM ()
validateForeignExport foreignExport = do
  validateForeignCallConv "foreign export" (rForeignExportCallConv foreignExport)
  ty <- foreignDeclarationMonoType "foreign export" (rForeignExportType foreignExport)
  validateForeignFunctionType "foreign export" ty

validateForeignCallConv :: Text -> S.ForeignCallConv -> InferM ()
validateForeignCallConv context = \case
  S.ForeignCCall ->
    pure ()
  S.ForeignStdCall ->
    pure ()
  other ->
    throwTypecheck (UnsupportedCore0 (context <> " calling convention `" <> renderForeignCallConv other <> "`"))

renderForeignCallConv :: S.ForeignCallConv -> Text
renderForeignCallConv = \case
  S.ForeignCCall -> "ccall"
  S.ForeignStdCall -> "stdcall"
  S.ForeignCPlusPlus -> "cplusplus"
  S.ForeignJvm -> "jvm"
  S.ForeignDotNet -> "dotnet"
  S.ForeignOtherCallConv occurrence -> occurrence

foreignDeclarationMonoType :: Text -> RHsType -> InferM MonoType
foreignDeclarationMonoType context sourceType = do
  (constraints, ty) <- sourceQualifiedMonoType sourceType
  unless (null constraints) $
    throwTypecheck (UnsupportedCore0 (context <> " type cannot have type-class constraints"))
  pure ty

foreignImportScheme :: RForeignImport -> InferM Scheme
foreignImportScheme foreignImport = do
  ty <- foreignDeclarationMonoType "foreign import" (rForeignImportType foreignImport)
  pure (Scheme (List.nub (typeVars ty)) [] ty)

foreignImportCoreBinds :: [RDecl] -> InferM [CoreBind]
foreignImportCoreBinds =
  fmap concat . traverse foreignImportCoreBindsFromDecl
 where
  foreignImportCoreBindsFromDecl decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RForeignDecl (RForeignImportDecl foreignImport) ->
          (: []) <$> foreignImportCoreBind foreignImport
        _ ->
          pure []

foreignImportCoreBind :: RForeignImport -> InferM CoreBind
foreignImportCoreBind foreignImport = do
  scheme@(Scheme variables _ monoTy) <- foreignImportScheme foreignImport
  bodyTy <- lift (monoToCoreType Map.empty Map.empty monoTy)
  binderTy <- lift (schemeToCoreTypeWith Map.empty Map.empty scheme)
  let info =
        CoreForeignImport
          { coreForeignImportCallConv = rForeignImportCallConv foreignImport
          , coreForeignImportSafety = rForeignImportSafety foreignImport
          , coreForeignImportEntity = rForeignImportEntity foreignImport
          , coreForeignImportName = rForeignImportName foreignImport
          , coreForeignImportType = bodyTy
          }
  body <- foreignImportCoreBody foreignImport info bodyTy
  let rhs =
        case variables of
          [] -> body
          _ -> CTypeLam variables body binderTy
  pure (CoreNonRec (CoreBinder (rForeignImportName foreignImport) binderTy) rhs)

foreignImportCoreBody :: RForeignImport -> CoreForeignImport -> CoreType -> InferM CoreExpr
foreignImportCoreBody foreignImport info bodyTy =
  case S.foreignImportEntityKind (rForeignImportEntity foreignImport) of
    S.ForeignImportDefault ->
      etaExpandForeignCall info bodyTy
    S.ForeignImportStatic {} ->
      etaExpandForeignCall info bodyTy
    S.ForeignImportDynamic ->
      etaExpandForeignCall info bodyTy
    S.ForeignImportWrapper ->
      etaExpandForeignCall info bodyTy
    _ ->
      pure (CForeignImportValue info bodyTy)

foreignExportCoreExports :: [RDecl] -> InferM [CoreForeignExport]
foreignExportCoreExports =
  foldM collect []
 where
  collect acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RForeignDecl (RForeignExportDecl foreignExport) -> do
          monoTy <- foreignDeclarationMonoType "foreign export" (rForeignExportType foreignExport)
          coreTy <- lift (monoToCoreType Map.empty Map.empty monoTy)
          pure
            ( acc
                <> [ CoreForeignExport
                      { coreForeignExportCallConv = rForeignExportCallConv foreignExport
                      , coreForeignExportEntity = rForeignExportEntity foreignExport
                      , coreForeignExportName = rForeignExportName foreignExport
                      , coreForeignExportType = coreTy
                      }
                   ]
            )
        _ ->
          pure acc

etaExpandForeignCall :: CoreForeignImport -> CoreType -> InferM CoreExpr
etaExpandForeignCall info bodyTy = do
  binders <-
    traverse
      ( \(index, argumentTy) -> do
          name <- freshGeneratedName TermNamespace ("$foreign_arg" <> Text.pack (show index))
          pure (CoreBinder name argumentTy)
      )
      (zip [(0 :: Int) ..] argumentTypes)
  let call =
        CForeignCall
          info
          [CVar (coreBinderName binder) (coreBinderType binder) | binder <- binders]
          resultTy
  pure (foldr lambda call binders)
 where
  (argumentTypes, resultTy) =
    splitCoreFunctionType bodyTy

  lambda binder body =
    CLam binder body (CTyFun (coreBinderType binder) (exprType body))

splitCoreFunctionType :: CoreType -> ([CoreType], CoreType)
splitCoreFunctionType =
  go []
 where
  go acc = \case
    CTyFun argument result ->
      go (acc <> [argument]) result
    result ->
      (acc, result)

validateForeignFunctionType :: Text -> MonoType -> InferM ()
validateForeignFunctionType context ty = do
  let (arguments, result) = splitFunctionType ty
  traverse_ (validateForeignArgumentType context) arguments
  validateForeignResultType context result

validateForeignDynamicType :: MonoType -> InferM ()
validateForeignDynamicType ty =
  case ty of
    TyFun pointerTy targetTy
      | Just ptrTargetTy <- foreignFunPtrArgument pointerTy
      , ptrTargetTy == targetTy ->
          validateForeignFunctionType "foreign import dynamic target" targetTy
    _ ->
      throwTypecheck (UnsupportedCore0 ("foreign import dynamic must have type FunPtr ft -> ft, got `" <> renderMonoType ty <> "`"))

validateForeignWrapperType :: MonoType -> InferM ()
validateForeignWrapperType ty =
  case ty of
    TyFun targetTy resultTy
      | Just resultInnerTy <- foreignIOResult resultTy
      , Just ptrTargetTy <- foreignFunPtrArgument resultInnerTy
      , ptrTargetTy == targetTy -> do
          validateForeignFunctionType "foreign import wrapper target" targetTy
    _ ->
      throwTypecheck (UnsupportedCore0 ("foreign import wrapper must have type ft -> IO (FunPtr ft), got `" <> renderMonoType ty <> "`"))

validateForeignAddressType :: MonoType -> InferM ()
validateForeignAddressType ty
  | isForeignPtrType ty || isForeignFunPtrType ty =
      pure ()
  | otherwise =
      throwTypecheck (UnsupportedCore0 ("foreign import address must have type Ptr a or FunPtr a, got `" <> renderMonoType ty <> "`"))

validateForeignArgumentType :: Text -> MonoType -> InferM ()
validateForeignArgumentType context ty =
  case ty of
    TyFun {} ->
      throwTypecheck (UnsupportedCore0 ("non-marshallable foreign argument type `" <> renderMonoType ty <> "` in " <> context))
    _ ->
      validateMarshallableForeignType Set.empty ("foreign argument in " <> context) ty

validateForeignResultType :: Text -> MonoType -> InferM ()
validateForeignResultType context ty =
  case foreignIOResult ty of
    Just resultTy ->
      validateForeignResultPayload ("foreign result in " <> context) resultTy
    Nothing ->
      validateForeignResultPayload ("foreign result in " <> context) ty

validateForeignResultPayload :: Text -> MonoType -> InferM ()
validateForeignResultPayload _ ty
  | isUnitType ty =
      pure ()
validateForeignResultPayload context ty =
  validateMarshallableForeignType Set.empty context ty

validateMarshallableForeignType :: Set.Set RName -> Text -> MonoType -> InferM ()
validateMarshallableForeignType seen context ty
  | isScalarForeignType ty || isForeignPtrType ty || isForeignFunPtrType ty || isForeignStablePtrType ty =
      pure ()
  | otherwise = do
      representation <- newtypeRepresentationField ty
      case (monoTypeHeadConstructor ty, representation) of
        (Just typeName, Just fieldTy)
          | typeName `Set.notMember` seen ->
              validateMarshallableForeignType (Set.insert typeName seen) context fieldTy
        _ ->
          throwTypecheck (UnsupportedCore0 ("non-marshallable " <> context <> " type `" <> renderMonoType ty <> "`"))

newtypeRepresentationField :: MonoType -> InferM (Maybe MonoType)
newtypeRepresentationField ty = do
  constructors <- dataConstructors <$> get
  pure (listToMaybe (mapMaybe representationField (Map.elems constructors)))
 where
  representationField info = do
    let (resultHead, resultArgs) = monoTypeApplicationSpine (dataConstructorResult info)
        (tyHead, tyArgs) = monoTypeApplicationSpine ty
    resultTypeName <- tyConName resultHead
    tyTypeName <- tyConName tyHead
    fieldTy <- listToMaybe (dataConstructorFields info)
    if dataConstructorRepresentation info == CoreNewtypeConstructor
      && resultTypeName == tyTypeName
      && length resultArgs == length tyArgs
      then Just (replaceTypeVars (Map.fromList (zip (dataConstructorTyVars info) tyArgs)) fieldTy)
      else Nothing

  tyConName = \case
    TyCon name -> Just name
    _ -> Nothing

splitFunctionType :: MonoType -> ([MonoType], MonoType)
splitFunctionType =
  go []
 where
  go acc = \case
    TyFun arg result ->
      go (acc <> [arg]) result
    result ->
      (acc, result)

foreignIOResult :: MonoType -> Maybe MonoType
foreignIOResult = \case
  TyApp (TyCon name) resultTy
    | isTypeConstructorOccurrence "IO" name -> Just resultTy
  _ -> Nothing

foreignFunPtrArgument :: MonoType -> Maybe MonoType
foreignFunPtrArgument = \case
  TyApp (TyCon name) targetTy
    | isTypeConstructorOccurrence "FunPtr" name -> Just targetTy
  _ -> Nothing

isForeignPtrType :: MonoType -> Bool
isForeignPtrType = \case
  TyApp (TyCon name) _ ->
    isTypeConstructorOccurrence "Ptr" name
  _ ->
    False

isForeignFunPtrType :: MonoType -> Bool
isForeignFunPtrType = \case
  TyApp (TyCon name) _ ->
    isTypeConstructorOccurrence "FunPtr" name
  _ ->
    False

isForeignStablePtrType :: MonoType -> Bool
isForeignStablePtrType = \case
  TyApp (TyCon name) _ ->
    isTypeConstructorOccurrence "StablePtr" name
  _ ->
    False

isScalarForeignType :: MonoType -> Bool
isScalarForeignType = \case
  TyCon name ->
    nameExternal name && nameOcc name `Set.member` scalarForeignTypeOccurrences
  _ ->
    False

isUnitType :: MonoType -> Bool
isUnitType = \case
  TyTuple [] ->
    True
  TyCon name ->
    isTypeConstructorOccurrence "()" name
  _ ->
    False

isTypeConstructorOccurrence :: Text -> RName -> Bool
isTypeConstructorOccurrence occurrence name =
  nameExternal name && nameNamespace name == TypeNamespace && nameOcc name == occurrence

monoTypeHeadConstructor :: MonoType -> Maybe RName
monoTypeHeadConstructor ty =
  case fst (monoTypeApplicationSpine ty) of
    TyCon name -> Just name
    _ -> Nothing

monoTypeApplicationSpine :: MonoType -> (MonoType, [MonoType])
monoTypeApplicationSpine =
  go []
 where
  go args = \case
    TyApp fn arg ->
      go (arg : args) fn
    headTy ->
      (headTy, args)

collectValueBindings :: [RDecl] -> InferM [SourceBinding]
collectValueBindings =
  foldM collect []
 where
  collect acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RTypeSignature {} ->
          pure acc
        RFixityDecl {} ->
          pure acc
        RDataDecl {} ->
          pure acc
        RNewtypeDecl {} ->
          pure acc
        RTypeSynonym {} ->
          pure acc
        RClassDecl {} ->
          pure acc
        RInstanceDecl {} ->
          pure acc
        RDefaultDecl {} ->
          pure acc
        RForeignDecl {} ->
          pure acc
        RFunctionBinding name patterns rhs whereDecls ->
          pure
            ( acc
                <> [ SourceBinding
                      { sourceBindingSpan = rDeclSpan decl
                      , sourceBindingName = name
                      , sourceBindingPatterns = patterns
                      , sourceBindingPatternBinding = Nothing
                      , sourceBindingRhs = rhs
                      , sourceBindingWhereDecls = whereDecls
                      }
                   ]
            )
        RPatternBinding (RPVar name) rhs whereDecls ->
          pure
            ( acc
                <> [ SourceBinding
                      { sourceBindingSpan = rDeclSpan decl
                      , sourceBindingName = name
                      , sourceBindingPatterns = []
                      , sourceBindingPatternBinding = Nothing
                      , sourceBindingRhs = rhs
                      , sourceBindingWhereDecls = whereDecls
                      }
                   ]
            )
        RPatternBinding pat rhs whereDecls ->
          pure
            ( acc
                <> [ SourceBinding
                      { sourceBindingSpan = rDeclSpan decl
                      , sourceBindingName = name
                      , sourceBindingPatterns = []
                      , sourceBindingPatternBinding = Just pat
                      , sourceBindingRhs = rhs
                      , sourceBindingWhereDecls = whereDecls
                      }
                   | name <- patternBindingNames pat
                   ]
            )

ensureSignatureHasBinding :: [RName] -> RName -> InferM ()
ensureSignatureHasBinding bindingNames name =
  unless (name `elem` bindingNames) $
    throwTypecheck (SignatureWithoutBinding name)

prepareBinding :: Map.Map RName Scheme -> SourceBinding -> InferM PreparedBinding
prepareBinding signatures binding =
  case Map.lookup (sourceBindingName binding) signatures of
    Just scheme ->
      pure
        PreparedBinding
          { preparedSpan = sourceBindingSpan binding
          , preparedName = sourceBindingName binding
          , preparedPatterns = sourceBindingPatterns binding
          , preparedPatternBinding = sourceBindingPatternBinding binding
          , preparedRhs = sourceBindingRhs binding
          , preparedWhereDecls = sourceBindingWhereDecls binding
          , preparedExpected = schemeBody scheme
          , preparedScheme = scheme
          , preparedHasSignature = True
          }
    Nothing -> do
      expected <- freshMeta
      pure
        PreparedBinding
          { preparedSpan = sourceBindingSpan binding
          , preparedName = sourceBindingName binding
          , preparedPatterns = sourceBindingPatterns binding
          , preparedPatternBinding = sourceBindingPatternBinding binding
          , preparedRhs = sourceBindingRhs binding
          , preparedWhereDecls = sourceBindingWhereDecls binding
          , preparedExpected = expected
          , preparedScheme = Scheme [] [] expected
          , preparedHasSignature = False
          }

inferPreparedBinding :: TypeEnv -> PreparedBinding -> InferM InferredBinding
inferPreparedBinding env prepared =
  withTypecheckSpan (preparedSpan prepared) $ do
    expr <-
      case preparedPatternBinding prepared of
        Nothing ->
          inferFunctionBindingExpr
            env
            (FunctionPatternExhaustiveness (preparedName prepared))
            (preparedPatterns prepared)
            (preparedRhs prepared)
            (preparedWhereDecls prepared)
        Just pat ->
          inferPatternBindingSelectorExpr
            env
            (preparedName prepared)
            pat
            (preparedRhs prepared)
            (preparedWhereDecls prepared)
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
      generalized <- generalize outerEnv (typedExprDefaultingConstraints rhs) (typedExprType rhs)
      pure
        TypedBinding
          { typedBindingName = preparedName prepared
          , typedBindingScheme = generalizedScheme generalized
          , typedBindingGeneralizedMetas = generalizedMetas generalized
          , typedBindingRhs = rhs
          }

inferInstanceDictionaries :: TypeEnv -> [RDecl] -> InferM [TypedInstanceDictionary]
inferInstanceDictionaries env =
  foldM collect []
 where
  collect acc = \case
    RInstanceDecl constraints instanceHead decls -> do
      dictionary <- inferInstanceDictionary env constraints instanceHead decls
      validateInstanceDictionary acc dictionary
      pure (acc <> [dictionary])
    _ ->
      pure acc

inferDerivedInstanceDictionaries :: TypeEnv -> [RDecl] -> [TypedInstanceDictionary] -> InferM [TypedInstanceDictionary]
inferDerivedInstanceDictionaries env decls existing =
  snd <$> foldM collect (existing, []) decls
 where
  collect (known, derived) decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RDataDecl typeName params constructors derivingNames ->
          collectDerived known derived typeName params constructors derivingNames
        RNewtypeDecl typeName params constructor derivingNames ->
          collectDerived known derived typeName params [constructor] derivingNames
        _ ->
          pure (known, derived)

  collectDerived known derived typeName params constructors derivingNames = do
    classNames <- validateDerivedClasses derivingNames
    foldM (addDerived typeName params constructors) (known, derived) classNames

  addDerived typeName params constructors (known, derived) className
    | className == builtinEqClassName = do
        dictionary <- inferDerivedEqInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinOrdClassName = do
        dictionary <- inferDerivedOrdInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinShowClassName = do
        dictionary <- inferDerivedShowInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinReadClassName = do
        dictionary <- inferDerivedReadInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinEnumClassName = do
        dictionary <- inferDerivedEnumInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinBoundedClassName = do
        dictionary <- inferDerivedBoundedInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | className == builtinIxClassName = do
        dictionary <- inferDerivedIxInstanceDictionary env typeName params constructors
        validateInstanceDictionary known dictionary
        pure (known <> [dictionary], derived <> [dictionary])
    | otherwise =
        throwTypecheck (UnsupportedCore0 ("derived class `" <> renderRName className <> "`"))

validateDerivedClasses :: [RName] -> InferM [RName]
validateDerivedClasses derivingNames = do
  let classNames = map canonicalClassName derivingNames
  case classNames List.\\ List.nub classNames of
    duplicate : _ ->
      throwTypecheck (UnsupportedCore0 ("duplicate derived class `" <> renderRName duplicate <> "`"))
    [] ->
      pure ()
  traverse_
    ( \className ->
        unless (className `elem` supportedDerivedClasses) $
          throwTypecheck (UnsupportedCore0 ("derived class `" <> renderRName className <> "`"))
    )
    classNames
  pure classNames
 where
  supportedDerivedClasses =
    [ builtinEqClassName
    , builtinOrdClassName
    , builtinShowClassName
    , builtinReadClassName
    , builtinEnumClassName
    , builtinBoundedClassName
    , builtinIxClassName
    ]

validateInstanceDictionary :: [TypedInstanceDictionary] -> TypedInstanceDictionary -> InferM ()
validateInstanceDictionary existing dictionary = do
  let instanceKey = instanceKeyFor dictionary
  when (isBuiltinInstanceConstraint instanceKey) $
    throwTypecheck (UnsupportedCore0 ("duplicate built-in instance for `" <> renderClassConstraint instanceKey <> "`"))
  when (overlapsBuiltinInstanceConstraint instanceKey) $
    throwTypecheck (UnsupportedCore0 ("overlapping built-in instance for `" <> renderClassConstraint instanceKey <> "`"))
  when (any (constraintMatches instanceKey . instanceKeyFor) existing) $
    throwTypecheck (UnsupportedCore0 ("duplicate instance for `" <> renderClassConstraint instanceKey <> "`"))
  when (any (constraintsOverlap instanceKey . instanceKeyFor) existing) $
    throwTypecheck (UnsupportedCore0 ("overlapping instance for `" <> renderClassConstraint instanceKey <> "`"))

instanceKeyFor :: TypedInstanceDictionary -> ClassConstraint
instanceKeyFor dictionary =
  singleClassConstraint (typedInstanceClass dictionary) (typedInstanceType dictionary)

inferDerivedEqInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedEqInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinEqClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Eq class")
      Just classInfo -> pure classInfo
  fieldTypes <- concat <$> traverse (constructorFieldMonoTypes params . conDeclFieldTypes) constructors
  context <- List.nub . concat <$> traverse (derivedFieldConstraints "Eq" builtinEqClassName typeName) fieldTypes
  methodMap <- derivedEqMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinEqClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinEqClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

inferDerivedOrdInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedOrdInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinOrdClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Ord class")
      Just classInfo -> pure classInfo
  fieldTypes <- concat <$> traverse (constructorFieldMonoTypes params . conDeclFieldTypes) constructors
  context <- List.nub . concat <$> traverse (derivedFieldConstraints "Ord" builtinOrdClassName typeName) fieldTypes
  methodMap <- derivedOrdMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinOrdClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinOrdClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

inferDerivedShowInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedShowInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinShowClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Show class")
      Just classInfo -> pure classInfo
  fieldTypes <- concat <$> traverse (constructorFieldMonoTypes params . conDeclFieldTypes) constructors
  context <- List.nub . concat <$> traverse (derivedFieldConstraints "Show" builtinShowClassName typeName) fieldTypes
  methodMap <- derivedShowMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinShowClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinShowClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

inferDerivedReadInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedReadInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinReadClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Read class")
      Just classInfo -> pure classInfo
  fieldTypes <- concat <$> traverse (constructorFieldMonoTypes params . conDeclFieldTypes) constructors
  context <- List.nub . concat <$> traverse (derivedFieldConstraints "Read" builtinReadClassName typeName) fieldTypes
  methodMap <- derivedReadMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinReadClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinReadClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

inferDerivedEnumInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedEnumInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinEnumClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Enum class")
      Just classInfo -> pure classInfo
  validateDerivedEnumConstructors typeName constructors
  methodMap <- derivedEnumMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinEnumClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinEnumClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = []
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

inferDerivedBoundedInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedBoundedInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinBoundedClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Bounded class")
      Just classInfo -> pure classInfo
  validateDerivedBoundedConstructors typeName constructors
  fieldTypes <- concat <$> traverse (constructorFieldMonoTypes params . conDeclFieldTypes) constructors
  context <- List.nub . concat <$> traverse (derivedFieldConstraints "Bounded" builtinBoundedClassName typeName) fieldTypes
  methodMap <- derivedBoundedMethodBindings constructors info
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
      replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinBoundedClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinBoundedClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = params
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

validateDerivedEnumConstructors :: RName -> [RConDecl] -> InferM ()
validateDerivedEnumConstructors typeName constructors =
  case constructors of
    [] ->
      throwTypecheck (UnsupportedCore0 ("derived Enum for `" <> renderRName typeName <> "` requires at least one constructor"))
    _ ->
      traverse_ validateConstructor constructors
 where
  validateConstructor constructor =
    unless (null (conDeclFieldTypes constructor)) $
      throwTypecheck
        ( UnsupportedCore0
            ( "derived Enum for `"
                <> renderRName typeName
                <> "` requires only nullary constructors; constructor `"
                <> renderRName (conDeclName constructor)
                <> "` has fields"
            )
        )

validateDerivedBoundedConstructors :: RName -> [RConDecl] -> InferM ()
validateDerivedBoundedConstructors typeName constructors =
  case constructors of
    [] ->
      throwTypecheck (UnsupportedCore0 ("derived Bounded for `" <> renderRName typeName <> "` requires at least one constructor"))
    [_] -> pure ()
    _
      | all (null . conDeclFieldTypes) constructors -> pure ()
      | otherwise ->
          throwTypecheck
            ( UnsupportedCore0
                ( "derived Bounded for `"
                    <> renderRName typeName
                    <> "` requires an enumeration or a single constructor"
                )
            )

derivedFieldConstraints :: Text -> RName -> RName -> MonoType -> InferM [ClassConstraint]
derivedFieldConstraints classOccurrence className selfTypeName fieldType =
  go fieldType
 where
  go ty = do
    normalized <- applyCurrent ty
    case normalized of
      TyVar {} ->
        pure [singleClassConstraint className normalized]
      TyCon {} ->
        pure []
      TyApp {} ->
        case monoTypeHead normalized of
          Just headName
            | headName == selfTypeName -> pure []
          _ | monoTypeHeadIsVariable normalized ->
              pure [singleClassConstraint className normalized]
          _ ->
              pure []
      TyList element ->
        go element
      TyTuple {} ->
        throwTypecheck (UnsupportedCore0 ("derived " <> classOccurrence <> " for tuple fields"))
      TyFun {} ->
        throwTypecheck (UnsupportedCore0 ("derived " <> classOccurrence <> " for function fields"))
      TyMeta {} ->
        pure [singleClassConstraint className normalized]

monoTypeHeadIsVariable :: MonoType -> Bool
monoTypeHeadIsVariable = \case
  TyVar {} -> True
  TyApp fn _ -> monoTypeHeadIsVariable fn
  _ -> False

derivedEqMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedEqMethodBindings constructors info = do
  eqMethod <- requireEqMethod "=="
  notEqMethod <- requireEqMethod "/="
  eqBinding <- derivedEqEqualityBinding (classMethodName eqMethod) constructors
  notEqBinding <- derivedEqInequalityBinding (classMethodName notEqMethod) (classMethodName eqMethod)
  pure (Map.fromList [(classMethodName eqMethod, eqBinding), (classMethodName notEqMethod, notEqBinding)])
 where
  requireEqMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Eq method `" <> occurrence <> "`"))

derivedEqEqualityBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEqEqualityBinding methodName constructors = do
  lhsName <- freshGeneratedName TermNamespace "$derived_eq_lhs"
  rhsName <- freshGeneratedName TermNamespace "$derived_eq_rhs"
  alternatives <- traverse (outerAlt rhsName) constructors
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar lhsName, RPVar rhsName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar lhsName) alternatives)
      , sourceBindingWhereDecls = []
      }
 where
  outerAlt rhsName constructor = do
    let constructorName = conDeclName constructor
    lhsFields <- freshConstructorFields "$derived_eq_lhs_field" constructor
    rhsFields <- freshConstructorFields "$derived_eq_rhs_field" constructor
    let sameConstructorAlt =
          RAlt
            (RPCon constructorName (map RPVar rhsFields))
            (RUnguarded (derivedEqFields (zip lhsFields rhsFields)))
            []
        defaultAlt =
          RAlt RPWildcard (RUnguarded derivedFalse) []
    pure
      ( RAlt
          (RPCon constructorName (map RPVar lhsFields))
          (RUnguarded (RCase (RVar rhsName) [sameConstructorAlt, defaultAlt]))
          []
      )

derivedEqInequalityBinding :: RName -> RName -> InferM SourceBinding
derivedEqInequalityBinding methodName eqName = do
  lhsName <- freshGeneratedName TermNamespace "$derived_neq_lhs"
  rhsName <- freshGeneratedName TermNamespace "$derived_neq_rhs"
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar lhsName, RPVar rhsName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RCase
                (RInfixApp (RVar lhsName) eqName (RVar rhsName))
                [ RAlt (RPCon trueDataConName []) (RUnguarded derivedFalse) []
                , RAlt (RPCon falseDataConName []) (RUnguarded derivedTrue) []
                ]
            )
      , sourceBindingWhereDecls = []
      }

freshConstructorFields :: Text -> RConDecl -> InferM [RName]
freshConstructorFields prefix constructor =
  traverse
    (\index -> freshGeneratedName TermNamespace (prefix <> renderInt index))
    [0 .. length (conDeclFieldTypes constructor) - 1]

derivedEqFields :: [(RName, RName)] -> RExpr
derivedEqFields =
  foldr
    (\(lhs, rhs) rest -> RInfixApp (RInfixApp (RVar lhs) derivedEqOperatorName (RVar rhs)) derivedAndOperatorName rest)
    derivedTrue

derivedEqOperatorName :: RName
derivedEqOperatorName =
  preludeTermName "==" (-1401)

derivedAndOperatorName :: RName
derivedAndOperatorName =
  preludeTermName "&&" (-3201)

derivedTrue :: RExpr
derivedTrue =
  RCon trueDataConName

derivedFalse :: RExpr
derivedFalse =
  RCon falseDataConName

derivedOrdMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedOrdMethodBindings constructors info = do
  compareMethod <- requireOrdMethod "compare"
  ltMethod <- requireOrdMethod "<"
  leMethod <- requireOrdMethod "<="
  gtMethod <- requireOrdMethod ">"
  geMethod <- requireOrdMethod ">="
  maxMethod <- requireOrdMethod "max"
  minMethod <- requireOrdMethod "min"
  compareBinding <- derivedOrdCompareBinding (classMethodName compareMethod) constructors
  ltBinding <-
    derivedOrdPredicateBinding
      (classMethodName ltMethod)
      (classMethodName compareMethod)
      derivedTrue
      derivedFalse
      derivedFalse
  leBinding <-
    derivedOrdPredicateBinding
      (classMethodName leMethod)
      (classMethodName compareMethod)
      derivedTrue
      derivedTrue
      derivedFalse
  gtBinding <-
    derivedOrdPredicateBinding
      (classMethodName gtMethod)
      (classMethodName compareMethod)
      derivedFalse
      derivedFalse
      derivedTrue
  geBinding <-
    derivedOrdPredicateBinding
      (classMethodName geMethod)
      (classMethodName compareMethod)
      derivedFalse
      derivedTrue
      derivedTrue
  maxBinding <-
    derivedOrdChoiceBinding
      (classMethodName maxMethod)
      (classMethodName compareMethod)
      (\lhs rhs -> (rhs, rhs, lhs))
  minBinding <-
    derivedOrdChoiceBinding
      (classMethodName minMethod)
      (classMethodName compareMethod)
      (\lhs rhs -> (lhs, lhs, rhs))
  pure
    ( Map.fromList
        [ (classMethodName compareMethod, compareBinding)
        , (classMethodName ltMethod, ltBinding)
        , (classMethodName leMethod, leBinding)
        , (classMethodName gtMethod, gtBinding)
        , (classMethodName geMethod, geBinding)
        , (classMethodName maxMethod, maxBinding)
        , (classMethodName minMethod, minBinding)
        ]
    )
 where
  requireOrdMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Ord method `" <> occurrence <> "`"))

derivedOrdCompareBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedOrdCompareBinding methodName constructors = do
  lhsName <- freshGeneratedName TermNamespace "$derived_compare_lhs"
  rhsName <- freshGeneratedName TermNamespace "$derived_compare_rhs"
  alternatives <- traverse (outerAlt rhsName) (zip [0 :: Int ..] constructors)
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar lhsName, RPVar rhsName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar lhsName) alternatives)
      , sourceBindingWhereDecls = []
      }
 where
  indexedConstructors = zip [0 :: Int ..] constructors

  outerAlt rhsName (lhsIndex, constructor) = do
    lhsFields <- freshConstructorFields "$derived_ord_lhs_field" constructor
    rhsAlternatives <- traverse (rhsAlt lhsIndex lhsFields) indexedConstructors
    pure
      ( RAlt
          (RPCon (conDeclName constructor) (map RPVar lhsFields))
          (RUnguarded (RCase (RVar rhsName) rhsAlternatives))
          []
      )

  rhsAlt lhsIndex lhsFields (rhsIndex, constructor)
    | lhsIndex == rhsIndex = do
        rhsFields <- freshConstructorFields "$derived_ord_rhs_field" constructor
        pure
          ( RAlt
              (RPCon (conDeclName constructor) (map RPVar rhsFields))
              (RUnguarded (derivedOrdCompareFields (zip lhsFields rhsFields)))
              []
          )
    | lhsIndex < rhsIndex =
        pure
          ( RAlt
              (RPCon (conDeclName constructor) (replicate (length (conDeclFieldTypes constructor)) RPWildcard))
              (RUnguarded derivedLT)
              []
          )
    | otherwise =
        pure
          ( RAlt
              (RPCon (conDeclName constructor) (replicate (length (conDeclFieldTypes constructor)) RPWildcard))
              (RUnguarded derivedGT)
              []
          )

derivedOrdCompareFields :: [(RName, RName)] -> RExpr
derivedOrdCompareFields =
  foldr compareField derivedEQ
 where
  compareField (lhs, rhs) rest =
    RCase
      (RApp (RApp (RVar derivedCompareName) (RVar lhs)) (RVar rhs))
      [ RAlt (RPCon orderingLTDataConName []) (RUnguarded derivedLT) []
      , RAlt (RPCon orderingEQDataConName []) (RUnguarded rest) []
      , RAlt (RPCon orderingGTDataConName []) (RUnguarded derivedGT) []
      ]

derivedOrdPredicateBinding :: RName -> RName -> RExpr -> RExpr -> RExpr -> InferM SourceBinding
derivedOrdPredicateBinding methodName compareName ltBody eqBody gtBody = do
  lhsName <- freshGeneratedName TermNamespace ("$derived_" <> nameOcc methodName <> "_lhs")
  rhsName <- freshGeneratedName TermNamespace ("$derived_" <> nameOcc methodName <> "_rhs")
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar lhsName, RPVar rhsName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RCase
                (RApp (RApp (RVar compareName) (RVar lhsName)) (RVar rhsName))
                [ RAlt (RPCon orderingLTDataConName []) (RUnguarded ltBody) []
                , RAlt (RPCon orderingEQDataConName []) (RUnguarded eqBody) []
                , RAlt (RPCon orderingGTDataConName []) (RUnguarded gtBody) []
                ]
            )
      , sourceBindingWhereDecls = []
      }

derivedOrdChoiceBinding :: RName -> RName -> (RExpr -> RExpr -> (RExpr, RExpr, RExpr)) -> InferM SourceBinding
derivedOrdChoiceBinding methodName compareName choices = do
  lhsName <- freshGeneratedName TermNamespace ("$derived_" <> nameOcc methodName <> "_lhs")
  rhsName <- freshGeneratedName TermNamespace ("$derived_" <> nameOcc methodName <> "_rhs")
  let lhsExpr = RVar lhsName
      rhsExpr = RVar rhsName
      (ltBody, eqBody, gtBody) = choices lhsExpr rhsExpr
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar lhsName, RPVar rhsName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RCase
                (RApp (RApp (RVar compareName) lhsExpr) rhsExpr)
                [ RAlt (RPCon orderingLTDataConName []) (RUnguarded ltBody) []
                , RAlt (RPCon orderingEQDataConName []) (RUnguarded eqBody) []
                , RAlt (RPCon orderingGTDataConName []) (RUnguarded gtBody) []
                ]
            )
      , sourceBindingWhereDecls = []
      }

derivedCompareName :: RName
derivedCompareName =
  preludeTermName "compare" (-1410)

derivedLT :: RExpr
derivedLT =
  RCon orderingLTDataConName

derivedEQ :: RExpr
derivedEQ =
  RCon orderingEQDataConName

derivedGT :: RExpr
derivedGT =
  RCon orderingGTDataConName

derivedShowMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedShowMethodBindings constructors info = do
  showsPrecMethod <- requireShowMethod "showsPrec"
  showMethod <- requireShowMethod "show"
  showListMethod <- requireShowMethod "showList"
  showsPrecBinding <- derivedShowsPrecBinding (classMethodName showsPrecMethod) constructors
  showBinding <- derivedShowBinding (classMethodName showMethod) constructors
  showListBinding <- derivedShowListBinding (classMethodName showListMethod) constructors
  pure
    ( Map.fromList
        [ (classMethodName showsPrecMethod, showsPrecBinding)
        , (classMethodName showMethod, showBinding)
        , (classMethodName showListMethod, showListBinding)
        ]
    )
 where
  requireShowMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Show method `" <> occurrence <> "`"))

derivedShowsPrecBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedShowsPrecBinding methodName constructors = do
  precName <- freshGeneratedName TermNamespace "$derived_shows_prec"
  valueName <- freshGeneratedName TermNamespace "$derived_show_value"
  restName <- freshGeneratedName TermNamespace "$derived_show_rest"
  appendName <- freshGeneratedName TermNamespace "$derived_show_append"
  body <- derivedShowCase appendName (RVar precName) (RVar valueName) (RVar restName) constructors
  appendDecl <- derivedShowAppendDecl appendName
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar precName, RPVar valueName, RPVar restName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded body
      , sourceBindingWhereDecls = [appendDecl]
      }

derivedShowBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedShowBinding methodName constructors = do
  valueName <- freshGeneratedName TermNamespace "$derived_show_value"
  appendName <- freshGeneratedName TermNamespace "$derived_show_append"
  body <- derivedShowCase appendName (derivedShowInt 0) (RVar valueName) (derivedShowString "") constructors
  appendDecl <- derivedShowAppendDecl appendName
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar valueName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded body
      , sourceBindingWhereDecls = [appendDecl]
      }

derivedShowListBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedShowListBinding methodName constructors = do
  xsName <- freshGeneratedName TermNamespace "$derived_show_list_xs"
  restName <- freshGeneratedName TermNamespace "$derived_show_list_rest"
  yName <- freshGeneratedName TermNamespace "$derived_show_list_y"
  ysName <- freshGeneratedName TermNamespace "$derived_show_list_ys"
  appendName <- freshGeneratedName TermNamespace "$derived_show_append"
  tailName <- freshGeneratedName TermNamespace "$derived_show_list_tail"
  consBody <- derivedShowCase appendName (derivedShowInt 0) (RVar yName) (RApp (RApp (RVar tailName) (RVar ysName)) (RVar restName)) constructors
  tailDecl <- derivedShowListTailDecl appendName tailName constructors
  appendDecl <- derivedShowAppendDecl appendName
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar xsName, RPVar restName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RCase
                (RVar xsName)
                [ RAlt (RPList []) (RUnguarded (derivedShowStringToRest appendName "[]" (RVar restName))) []
                , RAlt
                    (RPCon listConsDataConName [RPVar yName, RPVar ysName])
                    (RUnguarded (derivedShowStringToRest appendName "[" consBody))
                    []
                ]
            )
      , sourceBindingWhereDecls = [appendDecl, tailDecl]
      }

derivedShowListTailDecl :: RName -> RName -> [RConDecl] -> InferM RDecl
derivedShowListTailDecl appendName tailName constructors = do
  xsName <- freshGeneratedName TermNamespace "$derived_show_list_tail_xs"
  restName <- freshGeneratedName TermNamespace "$derived_show_list_tail_rest"
  yName <- freshGeneratedName TermNamespace "$derived_show_list_tail_y"
  ysName <- freshGeneratedName TermNamespace "$derived_show_list_tail_ys"
  consBody <- derivedShowCase appendName (derivedShowInt 0) (RVar yName) (RApp (RApp (RVar tailName) (RVar ysName)) (RVar restName)) constructors
  pure
    ( RFunctionBinding
        tailName
        [RPVar xsName, RPVar restName]
        ( RUnguarded
            ( RCase
                (RVar xsName)
                [ RAlt (RPList []) (RUnguarded (derivedShowStringToRest appendName "]" (RVar restName))) []
                , RAlt
                    (RPCon listConsDataConName [RPVar yName, RPVar ysName])
                    (RUnguarded (derivedShowStringToRest appendName "," consBody))
                    []
                ]
            )
        )
        []
    )

derivedShowCase :: RName -> RExpr -> RExpr -> RExpr -> [RConDecl] -> InferM RExpr
derivedShowCase appendName precExpr valueExpr restExpr constructors = do
  alternatives <- traverse (derivedShowAlt appendName precExpr restExpr) constructors
  pure (RCase valueExpr alternatives)

derivedShowAlt :: RName -> RExpr -> RExpr -> RConDecl -> InferM RAlt
derivedShowAlt appendName precExpr restExpr constructor = do
  fieldNames <- freshConstructorFields "$derived_show_field" constructor
  pure
    ( RAlt
        (RPCon (conDeclName constructor) (map RPVar fieldNames))
        (RUnguarded (derivedShowConstructor appendName precExpr restExpr constructor fieldNames))
        []
    )

derivedShowConstructor :: RName -> RExpr -> RExpr -> RConDecl -> [RName] -> RExpr
derivedShowConstructor appendName precExpr restExpr constructor fieldNames
  | null fieldNames =
      derivedShowStringToRest appendName (nameOcc (conDeclName constructor)) restExpr
  | any (/= Nothing) labels =
      derivedShowRecordConstructor appendName restExpr constructor fieldNames labels
  | otherwise =
      derivedShowPrefixConstructor appendName precExpr restExpr constructor fieldNames
 where
  labels = conDeclFieldLabels constructor

derivedShowPrefixConstructor :: RName -> RExpr -> RExpr -> RConDecl -> [RName] -> RExpr
derivedShowPrefixConstructor appendName precExpr restExpr constructor fieldNames =
  case precExpr of
    RLit (LInt precedence)
      | precedence > 10 -> parenthesized
      | otherwise -> inner restExpr
    _ ->
      RIf
        (RInfixApp precExpr derivedShowGreaterThanName (derivedShowInt 10))
        parenthesized
        (inner restExpr)
 where
  parenthesized =
    derivedShowStringToRest appendName "(" (inner (derivedShowStringToRest appendName ")" restExpr))
  inner finalRest =
    derivedShowStringToRest appendName (nameOcc (conDeclName constructor)) (foldr fieldToRest finalRest fieldNames)
  fieldToRest fieldName rest =
    derivedShowStringToRest appendName " " (derivedShowFieldToRest 11 fieldName rest)

derivedShowRecordConstructor :: RName -> RExpr -> RConDecl -> [RName] -> [Maybe RName] -> RExpr
derivedShowRecordConstructor appendName restExpr constructor fieldNames labels =
  derivedShowStringToRest appendName (nameOcc (conDeclName constructor) <> " {") (fieldsToRest labelFields)
 where
  labelFields = [(label, fieldName) | (Just label, fieldName) <- zip labels fieldNames]
  fieldsToRest [] =
    derivedShowStringToRest appendName "}" restExpr
  fieldsToRest [(label, fieldName)] =
    derivedShowStringToRest appendName (nameOcc label <> " = ") (derivedShowFieldToRest 0 fieldName (derivedShowStringToRest appendName "}" restExpr))
  fieldsToRest ((label, fieldName) : rest) =
    derivedShowStringToRest appendName (nameOcc label <> " = ") (derivedShowFieldToRest 0 fieldName (derivedShowStringToRest appendName ", " (fieldsToRest rest)))

derivedShowFieldToRest :: Int -> RName -> RExpr -> RExpr
derivedShowFieldToRest precedence fieldName restExpr =
  RApp (RApp (RApp (RVar derivedShowsPrecName) (derivedShowInt (toInteger precedence))) (RVar fieldName)) restExpr

derivedShowAppendDecl :: RName -> InferM RDecl
derivedShowAppendDecl appendName = do
  xsName <- freshGeneratedName TermNamespace "$derived_show_append_xs"
  ysName <- freshGeneratedName TermNamespace "$derived_show_append_ys"
  cName <- freshGeneratedName TermNamespace "$derived_show_append_c"
  csName <- freshGeneratedName TermNamespace "$derived_show_append_cs"
  pure
    ( RFunctionBinding
        appendName
        [RPVar xsName, RPVar ysName]
        ( RUnguarded
            ( RCase
                (RVar xsName)
                [ RAlt (RPList []) (RUnguarded (RVar ysName)) []
                , RAlt
                    (RPCon listConsDataConName [RPVar cName, RPVar csName])
                    (RUnguarded (RApp (RApp (RCon listConsDataConName) (RVar cName)) (RApp (RApp (RVar appendName) (RVar csName)) (RVar ysName))))
                    []
                ]
            )
        )
        []
    )

derivedShowStringToRest :: RName -> Text -> RExpr -> RExpr
derivedShowStringToRest appendName text restExpr =
  RApp (RApp (RVar appendName) (derivedShowString text)) restExpr

derivedShowString :: Text -> RExpr
derivedShowString =
  RLit . LString

derivedShowInt :: Integer -> RExpr
derivedShowInt =
  RLit . LInt

derivedShowsPrecName :: RName
derivedShowsPrecName =
  preludeTermName "showsPrec" (-1430)

derivedShowGreaterThanName :: RName
derivedShowGreaterThanName =
  preludeTermName ">" (-1413)

derivedReadMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedReadMethodBindings constructors info = do
  readsPrecMethod <- requireReadMethod "readsPrec"
  readListMethod <- requireReadMethod "readList"
  readsPrecBinding <- derivedReadsPrecBinding (classMethodName readsPrecMethod) constructors
  readListBinding <- derivedReadListBinding (classMethodName readListMethod)
  pure
    ( Map.fromList
        [ (classMethodName readsPrecMethod, readsPrecBinding)
        , (classMethodName readListMethod, readListBinding)
        ]
    )
 where
  requireReadMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Read method `" <> occurrence <> "`"))

derivedReadsPrecBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedReadsPrecBinding methodName constructors = do
  precName <- freshGeneratedName TermNamespace "$derived_reads_prec"
  inputName <- freshGeneratedName TermNamespace "$derived_read_input"
  alternatives <- traverse (derivedReadConstructorCall (RVar precName) (RVar inputName)) constructors
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar precName, RPVar inputName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (foldr derivedReadAppend (RList []) alternatives)
      , sourceBindingWhereDecls = []
      }

derivedReadListBinding :: RName -> InferM SourceBinding
derivedReadListBinding methodName = do
  inputName <- freshGeneratedName TermNamespace "$derived_read_list_input"
  let parser = RApp (RVar derivedReadsPrecName) (derivedShowInt 0)
      body = RApp (RApp (RVar derivedReadDefaultListName) parser) (RVar inputName)
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar inputName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded body
      , sourceBindingWhereDecls = []
      }

derivedReadConstructorCall :: RExpr -> RExpr -> RConDecl -> InferM RExpr
derivedReadConstructorCall precExpr inputExpr constructor = do
  parserInputName <- freshGeneratedName TermNamespace "$derived_read_parser_input"
  parserBody <- derivedReadConstructorParserBody parserInputName constructor
  let parser = RLambda [RPVar parserInputName] parserBody
      mandatory = derivedReadParenMandatory precExpr constructor
  pure (RApp (RApp (RApp (RVar derivedReadParenName) mandatory) parser) inputExpr)

derivedReadConstructorParserBody :: RName -> RConDecl -> InferM RExpr
derivedReadConstructorParserBody parserInputName constructor = do
  recordLabels <- derivedRecordLabels constructor
  case recordLabels of
    Just labels -> derivedReadRecordParserBody parserInputName constructor labels
    Nothing -> derivedReadPrefixParserBody parserInputName constructor

derivedReadPrefixParserBody :: RName -> RConDecl -> InferM RExpr
derivedReadPrefixParserBody parserInputName constructor = do
  afterConstructorName <- freshGeneratedName TermNamespace "$derived_read_after_constructor"
  fieldNames <- freshConstructorFields "$derived_read_field" constructor
  (fieldStatements, restName) <- derivedReadFieldStatements 11 afterConstructorName fieldNames
  let statements =
        derivedReadTokenStmt (nameOcc (conDeclName constructor)) (RVar parserInputName) afterConstructorName
          : fieldStatements
      value = foldl RApp (RCon (conDeclName constructor)) (map RVar fieldNames)
  pure (RListComp (RTuple [value, RVar restName]) statements)

derivedReadRecordParserBody :: RName -> RConDecl -> [RName] -> InferM RExpr
derivedReadRecordParserBody parserInputName constructor labels = do
  afterConstructorName <- freshGeneratedName TermNamespace "$derived_read_after_constructor"
  afterOpenName <- freshGeneratedName TermNamespace "$derived_read_after_record_open"
  fieldNames <- freshConstructorFields "$derived_read_record_field" constructor
  (fieldStatements, restName) <- derivedReadRecordFieldStatements afterOpenName (zip labels fieldNames)
  let statements =
        [ derivedReadTokenStmt (nameOcc (conDeclName constructor)) (RVar parserInputName) afterConstructorName
        , derivedReadTokenStmt "{" (RVar afterConstructorName) afterOpenName
        ]
          <> fieldStatements
      value = RRecordCon (conDeclName constructor) [(label, RVar fieldName) | (label, fieldName) <- zip labels fieldNames]
  pure (RListComp (RTuple [value, RVar restName]) statements)

derivedRecordLabels :: RConDecl -> InferM (Maybe [RName])
derivedRecordLabels constructor =
  case conDeclFieldLabels constructor of
    labels
      | any (/= Nothing) labels ->
          case sequence labels of
            Just labelNames -> pure (Just labelNames)
            Nothing ->
              throwTypecheck
                ( UnsupportedCore0
                    ( "derived Read for mixed labelled and unlabelled constructor `"
                        <> renderRName (conDeclName constructor)
                        <> "`"
                    )
                )
      | otherwise -> pure Nothing

derivedReadFieldStatements :: Int -> RName -> [RName] -> InferM ([RStmt], RName)
derivedReadFieldStatements precedence initialInputName =
  go initialInputName
 where
  go currentInputName [] =
    pure ([], currentInputName)
  go currentInputName (fieldName : fields) = do
    afterFieldName <- freshGeneratedName TermNamespace "$derived_read_after_field"
    (restStatements, finalInputName) <- go afterFieldName fields
    let statement = derivedReadFieldStmt precedence fieldName (RVar currentInputName) afterFieldName
    pure (statement : restStatements, finalInputName)

derivedReadRecordFieldStatements :: RName -> [(RName, RName)] -> InferM ([RStmt], RName)
derivedReadRecordFieldStatements initialInputName fields =
  go True initialInputName fields
 where
  go _ currentInputName [] = do
    afterCloseName <- freshGeneratedName TermNamespace "$derived_read_after_record_close"
    pure ([derivedReadTokenStmt "}" (RVar currentInputName) afterCloseName], afterCloseName)
  go firstField currentInputName ((labelName, fieldName) : rest) = do
    (separatorStatements, afterSeparatorName) <-
      if firstField
        then pure ([], currentInputName)
        else do
          afterCommaName <- freshGeneratedName TermNamespace "$derived_read_after_record_comma"
          pure ([derivedReadTokenStmt "," (RVar currentInputName) afterCommaName], afterCommaName)
    afterLabelName <- freshGeneratedName TermNamespace "$derived_read_after_record_label"
    afterEqualsName <- freshGeneratedName TermNamespace "$derived_read_after_record_equals"
    afterFieldName <- freshGeneratedName TermNamespace "$derived_read_after_record_field"
    (restStatements, finalInputName) <- go False afterFieldName rest
    let statements =
          separatorStatements
            <> [ derivedReadTokenStmt (nameOcc labelName) (RVar afterSeparatorName) afterLabelName
               , derivedReadTokenStmt "=" (RVar afterLabelName) afterEqualsName
               , derivedReadFieldStmt 0 fieldName (RVar afterEqualsName) afterFieldName
               ]
            <> restStatements
    pure (statements, finalInputName)

derivedReadTokenStmt :: Text -> RExpr -> RName -> RStmt
derivedReadTokenStmt token inputExpr outputName =
  RBindStmt (RPTuple [RPLit (LString token), RPVar outputName]) (RApp (RVar derivedReadLexName) inputExpr)

derivedReadFieldStmt :: Int -> RName -> RExpr -> RName -> RStmt
derivedReadFieldStmt precedence fieldName inputExpr outputName =
  RBindStmt
    (RPTuple [RPVar fieldName, RPVar outputName])
    (RApp (RApp (RVar derivedReadsPrecName) (derivedShowInt (toInteger precedence))) inputExpr)

derivedReadParenMandatory :: RExpr -> RConDecl -> RExpr
derivedReadParenMandatory precExpr constructor
  | null (conDeclFieldTypes constructor) = derivedFalse
  | constructorUsesRecordSyntax constructor = derivedFalse
  | otherwise = RInfixApp precExpr derivedShowGreaterThanName (derivedShowInt 10)

constructorUsesRecordSyntax :: RConDecl -> Bool
constructorUsesRecordSyntax =
  any (/= Nothing) . conDeclFieldLabels

derivedReadAppend :: RExpr -> RExpr -> RExpr
derivedReadAppend lhs rhs =
  RInfixApp lhs derivedReadAppendName rhs

derivedReadAppendName :: RName
derivedReadAppendName =
  readAppendName

derivedReadDefaultListName :: RName
derivedReadDefaultListName =
  readDefaultListName

derivedReadLexName :: RName
derivedReadLexName =
  readLexName

derivedReadParenName :: RName
derivedReadParenName =
  readParenName

derivedReadsPrecName :: RName
derivedReadsPrecName =
  preludeTermName "readsPrec" (-1433)

derivedEnumMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedEnumMethodBindings constructors info = do
  succMethod <- requireEnumMethod "succ"
  predMethod <- requireEnumMethod "pred"
  toEnumMethod <- requireEnumMethod "toEnum"
  fromEnumMethod <- requireEnumMethod "fromEnum"
  enumFromMethod <- requireEnumMethod "enumFrom"
  enumFromThenMethod <- requireEnumMethod "enumFromThen"
  enumFromToMethod <- requireEnumMethod "enumFromTo"
  enumFromThenToMethod <- requireEnumMethod "enumFromThenTo"
  succBinding <- derivedEnumSuccBinding (classMethodName succMethod) constructors
  predBinding <- derivedEnumPredBinding (classMethodName predMethod) constructors
  toEnumBinding <- derivedEnumToEnumBinding (classMethodName toEnumMethod) constructors
  fromEnumBinding <- derivedEnumFromEnumBinding (classMethodName fromEnumMethod) constructors
  enumFromBinding <- derivedEnumFromBinding (classMethodName enumFromMethod) constructors
  enumFromThenBinding <- derivedEnumFromThenBinding (classMethodName enumFromThenMethod) constructors
  enumFromToBinding <- derivedEnumFromToBinding (classMethodName enumFromToMethod)
  enumFromThenToBinding <- derivedEnumFromThenToBinding (classMethodName enumFromThenToMethod)
  pure
    ( Map.fromList
        [ (classMethodName succMethod, succBinding)
        , (classMethodName predMethod, predBinding)
        , (classMethodName toEnumMethod, toEnumBinding)
        , (classMethodName fromEnumMethod, fromEnumBinding)
        , (classMethodName enumFromMethod, enumFromBinding)
        , (classMethodName enumFromThenMethod, enumFromThenBinding)
        , (classMethodName enumFromToMethod, enumFromToBinding)
        , (classMethodName enumFromThenToMethod, enumFromThenToBinding)
        ]
    )
 where
  requireEnumMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Enum method `" <> occurrence <> "`"))

derivedEnumSuccBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumSuccBinding methodName constructors = do
  valueName <- freshGeneratedName TermNamespace "$derived_enum_succ_value"
  firstConstructor <- derivedEnumFirstConstructorName constructors
  let pairs = zip constructors (drop 1 constructors)
      alternatives =
        [ RAlt (RPCon (conDeclName current) []) (RUnguarded (RCon (conDeclName next))) []
        | (current, next) <- pairs
        ]
          <> [derivedEnumFailureAlt (RCon firstConstructor)]
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar valueName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar valueName) alternatives)
      , sourceBindingWhereDecls = []
      }

derivedEnumPredBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumPredBinding methodName constructors = do
  valueName <- freshGeneratedName TermNamespace "$derived_enum_pred_value"
  firstConstructor <- derivedEnumFirstConstructorName constructors
  let pairs = zip (drop 1 constructors) constructors
      alternatives =
        [ RAlt (RPCon (conDeclName current) []) (RUnguarded (RCon (conDeclName previous))) []
        | (current, previous) <- pairs
        ]
          <> [derivedEnumFailureAlt (RCon firstConstructor)]
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar valueName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar valueName) alternatives)
      , sourceBindingWhereDecls = []
      }

derivedEnumToEnumBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumToEnumBinding methodName constructors = do
  indexName <- freshGeneratedName TermNamespace "$derived_enum_to_enum_index"
  firstConstructor <- derivedEnumFirstConstructorName constructors
  let alternatives =
        [ RAlt (RPLit (LInt (toInteger index))) (RUnguarded (RCon (conDeclName constructor))) []
        | (index, constructor) <- zip [0 :: Int ..] constructors
        ]
          <> [derivedEnumFailureAlt (RCon firstConstructor)]
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar indexName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar indexName) alternatives)
      , sourceBindingWhereDecls = []
      }

derivedEnumFromEnumBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumFromEnumBinding methodName constructors = do
  valueName <- freshGeneratedName TermNamespace "$derived_enum_from_enum_value"
  let alternatives =
        [ RAlt (RPCon (conDeclName constructor) []) (RUnguarded (RLit (LInt (toInteger index)))) []
        | (index, constructor) <- zip [0 :: Int ..] constructors
        ]
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar valueName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded (RCase (RVar valueName) alternatives)
      , sourceBindingWhereDecls = []
      }

derivedEnumFromBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumFromBinding methodName constructors = do
  startName <- freshGeneratedName TermNamespace "$derived_enum_from_start"
  lastConstructor <- derivedEnumLastConstructorName constructors
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar startName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RApp
                (RApp (RVar derivedEnumFromToName) (RVar startName))
                (RCon lastConstructor)
            )
      , sourceBindingWhereDecls = []
      }

derivedEnumFromThenBinding :: RName -> [RConDecl] -> InferM SourceBinding
derivedEnumFromThenBinding methodName constructors = do
  startName <- freshGeneratedName TermNamespace "$derived_enum_from_then_start"
  nextName <- freshGeneratedName TermNamespace "$derived_enum_from_then_next"
  firstConstructor <- derivedEnumFirstConstructorName constructors
  lastConstructor <- derivedEnumLastConstructorName constructors
  let startExpr = RVar startName
      nextExpr = RVar nextName
      ascending =
        RInfixApp
          (RApp (RVar derivedFromEnumName) nextExpr)
          derivedGreaterEqualName
          (RApp (RVar derivedFromEnumName) startExpr)
      bound =
        RCase
          ascending
          [ RAlt (RPCon trueDataConName []) (RUnguarded (RCon lastConstructor)) []
          , RAlt (RPCon falseDataConName []) (RUnguarded (RCon firstConstructor)) []
          ]
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar startName, RPVar nextName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            ( RApp
                (RApp (RApp (RVar derivedEnumFromThenToName) startExpr) nextExpr)
                bound
            )
      , sourceBindingWhereDecls = []
      }

derivedEnumFromToBinding :: RName -> InferM SourceBinding
derivedEnumFromToBinding methodName = do
  startName <- freshGeneratedName TermNamespace "$derived_enum_from_to_start"
  endName <- freshGeneratedName TermNamespace "$derived_enum_from_to_end"
  let startExpr = RVar startName
      endExpr = RVar endName
      indexRange =
        RApp
          (RApp (RVar derivedEnumFromToName) (RApp (RVar derivedFromEnumName) startExpr))
          (RApp (RVar derivedFromEnumName) endExpr)
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar startName, RPVar endName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            (RApp (RApp (RVar derivedMapName) (RVar derivedToEnumName)) indexRange)
      , sourceBindingWhereDecls = []
      }

derivedEnumFromThenToBinding :: RName -> InferM SourceBinding
derivedEnumFromThenToBinding methodName = do
  startName <- freshGeneratedName TermNamespace "$derived_enum_from_then_to_start"
  nextName <- freshGeneratedName TermNamespace "$derived_enum_from_then_to_next"
  endName <- freshGeneratedName TermNamespace "$derived_enum_from_then_to_end"
  let startExpr = RVar startName
      nextExpr = RVar nextName
      endExpr = RVar endName
      indexRange =
        RApp
          ( RApp
              ( RApp
                  (RVar derivedEnumFromThenToName)
                  (RApp (RVar derivedFromEnumName) startExpr)
              )
              (RApp (RVar derivedFromEnumName) nextExpr)
          )
          (RApp (RVar derivedFromEnumName) endExpr)
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = [RPVar startName, RPVar nextName, RPVar endName]
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs =
          RUnguarded
            (RApp (RApp (RVar derivedMapName) (RVar derivedToEnumName)) indexRange)
      , sourceBindingWhereDecls = []
      }

derivedEnumFailureAlt :: RExpr -> RAlt
derivedEnumFailureAlt dummy =
  RAlt RPWildcard (RUnguarded (derivedEnumFailureExpr dummy)) []

derivedEnumFailureExpr :: RExpr -> RExpr
derivedEnumFailureExpr dummy =
  RCase
    derivedFalse
    [RAlt (RPCon trueDataConName []) (RUnguarded dummy) []]

derivedEnumFirstConstructorName :: [RConDecl] -> InferM RName
derivedEnumFirstConstructorName = \case
  first : _ -> pure (conDeclName first)
  [] -> throwTypecheck (UnsupportedCore0 "derived Enum requires at least one constructor")

derivedEnumLastConstructorName :: [RConDecl] -> InferM RName
derivedEnumLastConstructorName = \case
  first : rest -> pure (go first rest)
  [] -> throwTypecheck (UnsupportedCore0 "derived Enum requires at least one constructor")
 where
  go current [] = conDeclName current
  go _ (next : rest) = go next rest

derivedMapName :: RName
derivedMapName =
  preludeTermName "map" (-99962)

derivedToEnumName :: RName
derivedToEnumName =
  preludeTermName "toEnum" (-1443)

derivedFromEnumName :: RName
derivedFromEnumName =
  preludeTermName "fromEnum" (-1444)

derivedEnumFromToName :: RName
derivedEnumFromToName =
  preludeTermName "enumFromTo" (-1447)

derivedEnumFromThenToName :: RName
derivedEnumFromThenToName =
  preludeTermName "enumFromThenTo" (-1448)

derivedGreaterEqualName :: RName
derivedGreaterEqualName =
  preludeTermName ">=" (-1414)

data DerivedBoundedEndpoint = DerivedMinBound | DerivedMaxBound
  deriving stock (Show, Eq, Ord)

derivedBoundedMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedBoundedMethodBindings constructors info = do
  minMethod <- requireBoundedMethod "minBound"
  maxMethod <- requireBoundedMethod "maxBound"
  minBinding <- derivedBoundedBinding (classMethodName minMethod) DerivedMinBound constructors
  maxBinding <- derivedBoundedBinding (classMethodName maxMethod) DerivedMaxBound constructors
  pure (Map.fromList [(classMethodName minMethod, minBinding), (classMethodName maxMethod, maxBinding)])
 where
  requireBoundedMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Bounded method `" <> occurrence <> "`"))

derivedBoundedBinding :: RName -> DerivedBoundedEndpoint -> [RConDecl] -> InferM SourceBinding
derivedBoundedBinding methodName endpoint constructors = do
  boundExpr <- derivedBoundedExpr endpoint constructors
  pure
    SourceBinding
      { sourceBindingSpan = Nothing
      , sourceBindingName = methodName
      , sourceBindingPatterns = []
      , sourceBindingPatternBinding = Nothing
      , sourceBindingRhs = RUnguarded boundExpr
      , sourceBindingWhereDecls = []
      }

derivedBoundedExpr :: DerivedBoundedEndpoint -> [RConDecl] -> InferM RExpr
derivedBoundedExpr endpoint constructors
  | all (null . conDeclFieldTypes) constructors =
      RCon <$> boundaryConstructorName endpoint constructors
  | otherwise =
      case constructors of
        [constructor] -> pure (derivedBoundedProductExpr endpoint constructor)
        [] -> throwTypecheck (UnsupportedCore0 "derived Bounded requires at least one constructor")
        _ -> throwTypecheck (UnsupportedCore0 "derived Bounded requires an enumeration or a single constructor")

boundaryConstructorName :: DerivedBoundedEndpoint -> [RConDecl] -> InferM RName
boundaryConstructorName endpoint constructors =
  case endpoint of
    DerivedMinBound -> derivedEnumFirstConstructorName constructors
    DerivedMaxBound -> derivedEnumLastConstructorName constructors

derivedBoundedProductExpr :: DerivedBoundedEndpoint -> RConDecl -> RExpr
derivedBoundedProductExpr endpoint constructor =
  foldl RApp (RCon (conDeclName constructor)) fieldBounds
 where
  fieldBounds =
    replicate (length (conDeclFieldTypes constructor)) (RVar (boundedEndpointName endpoint))

boundedEndpointName :: DerivedBoundedEndpoint -> RName
boundedEndpointName = \case
  DerivedMinBound -> derivedMinBoundName
  DerivedMaxBound -> derivedMaxBoundName

derivedMinBoundName :: RName
derivedMinBoundName =
  preludeTermName "minBound" (-1451)

derivedMaxBoundName :: RName
derivedMaxBoundName =
  preludeTermName "maxBound" (-1452)

inferDerivedIxInstanceDictionary :: TypeEnv -> RName -> [RName] -> [RConDecl] -> InferM TypedInstanceDictionary
inferDerivedIxInstanceDictionary env typeName params constructors = do
  classes <- classInfos <$> get
  info <-
    case Map.lookup builtinIxClassName classes of
      Nothing -> throwTypecheck (UnsupportedCore0 "missing built-in Ix class")
      Just classInfo -> pure classInfo
  methodMap <- derivedIxMethodBindings constructors info
  context <-
    case constructors of
      []
        -> throwTypecheck (UnsupportedCore0 "derived Ix requires at least one constructor")
      _
        | all null (map conDeclFieldTypes constructors) ->
            pure [singleClassConstraint builtinEnumClassName (foldl TyApp (TyCon typeName) (map TyVar params))]
      [constructor] ->
        do
          fieldTypes <- constructorFieldMonoTypes params (conDeclFieldTypes constructor)
          List.nub . concat <$> traverse (derivedFieldConstraints "Ix" builtinIxClassName typeName) fieldTypes
      _ ->
        throwTypecheck (UnsupportedCore0 "derived Ix requires an enumeration or a single constructor")
  let instanceType = foldl TyApp (TyCon typeName) (map TyVar params)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName builtinIxClassName instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = builtinIxClassName
      , typedInstanceType = instanceType
      , typedInstanceVariables = typeVars instanceType
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = [singleClassConstraint builtinOrdClassName instanceType]
      , typedInstanceMethods = typedMethods
      }

derivedIxMethodBindings :: [RConDecl] -> ClassInfo -> InferM (Map.Map RName SourceBinding)
derivedIxMethodBindings constructors info = do
  rangeMethod <- requireIxMethod "range"
  indexMethod <- requireIxMethod "index"
  inRangeMethod <- requireIxMethod "inRange"
  rangeSizeMethod <- requireIxMethod "rangeSize"
  bindings <-
    if all null (map conDeclFieldTypes constructors)
      then derivedIxEnumBindings constructors rangeMethod indexMethod inRangeMethod rangeSizeMethod
      else case constructors of
        [constructor] -> derivedIxProductBindings constructor rangeMethod indexMethod inRangeMethod rangeSizeMethod
        [] -> throwTypecheck (UnsupportedCore0 "derived Ix requires at least one constructor")
        _ -> throwTypecheck (UnsupportedCore0 "derived Ix requires an enumeration or a single constructor")
  pure (Map.fromList bindings)
 where
  requireIxMethod occurrence =
    case List.find ((== occurrence) . nameOcc . classMethodName) (classInfoMethods info) of
      Just method -> pure method
      Nothing -> throwTypecheck (UnsupportedCore0 ("missing Ix method `" <> occurrence <> "`"))

derivedIxEnumBindings ::
  [RConDecl] ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  InferM [(RName, SourceBinding)]
derivedIxEnumBindings _constructors rangeMethod indexMethod inRangeMethod rangeSizeMethod = do
  boundsName <- freshGeneratedName TermNamespace "$derived_ix_bounds"
  lowerName <- freshGeneratedName TermNamespace "$derived_ix_lower"
  upperName <- freshGeneratedName TermNamespace "$derived_ix_upper"
  valueName <- freshGeneratedName TermNamespace "$derived_ix_value"
  let lowerExpr = RVar lowerName
      upperExpr = RVar upperName
      valueExpr = RVar valueName
      intBounds = RTuple [RApp (RVar derivedFromEnumName) lowerExpr, RApp (RVar derivedFromEnumName) upperExpr]
      rangeExpr =
        RCase
          (RVar boundsName)
          [ RAlt
              (RPTuple [RPVar lowerName, RPVar upperName])
              (RUnguarded (RApp (RApp (RVar derivedMapName) (RVar derivedToEnumName)) (RApp (RVar (classMethodName rangeMethod)) intBounds)))
              []
          ]
      indexExpr =
        RCase
          (RVar boundsName)
          [ RAlt
              (RPTuple [RPVar lowerName, RPVar upperName])
              (RUnguarded (RApp (RApp (RVar (classMethodName indexMethod)) intBounds) (RApp (RVar derivedFromEnumName) valueExpr)))
              []
          ]
      inRangeExpr =
        RCase
          (RVar boundsName)
          [ RAlt
              (RPTuple [RPVar lowerName, RPVar upperName])
              (RUnguarded (RApp (RApp (RVar (classMethodName inRangeMethod)) intBounds) (RApp (RVar derivedFromEnumName) valueExpr)))
              []
          ]
      rangeSizeExpr =
        RCase
          (RVar boundsName)
          [ RAlt
              (RPTuple [RPVar lowerName, RPVar upperName])
              (RUnguarded (RApp (RVar (classMethodName rangeSizeMethod)) intBounds))
              []
          ]
  pure
    [ (classMethodName rangeMethod, derivedMethodBinding (classMethodName rangeMethod) [RPVar boundsName] rangeExpr)
    , (classMethodName indexMethod, derivedMethodBinding (classMethodName indexMethod) [RPVar boundsName, RPVar valueName] indexExpr)
    , (classMethodName inRangeMethod, derivedMethodBinding (classMethodName inRangeMethod) [RPVar boundsName, RPVar valueName] inRangeExpr)
    , (classMethodName rangeSizeMethod, derivedMethodBinding (classMethodName rangeSizeMethod) [RPVar boundsName] rangeSizeExpr)
    ]

derivedIxProductBindings ::
  RConDecl ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  ClassMethodInfo ->
  InferM [(RName, SourceBinding)]
derivedIxProductBindings constructor rangeMethod indexMethod inRangeMethod rangeSizeMethod = do
  boundsName <- freshGeneratedName TermNamespace "$derived_ix_product_bounds"
  valueName <- freshGeneratedName TermNamespace "$derived_ix_product_value"
  lowerNames <- traverse (\index -> freshGeneratedName TermNamespace ("$derived_ix_product_lower_" <> renderInt index)) [0 .. fieldCount - 1]
  upperNames <- traverse (\index -> freshGeneratedName TermNamespace ("$derived_ix_product_upper_" <> renderInt index)) [0 .. fieldCount - 1]
  valueNames <- traverse (\index -> freshGeneratedName TermNamespace ("$derived_ix_product_value_" <> renderInt index)) [0 .. fieldCount - 1]
  rangeNames <- traverse (\index -> freshGeneratedName TermNamespace ("$derived_ix_product_range_" <> renderInt index)) [0 .. fieldCount - 1]
  let lowerPat = RPCon (conDeclName constructor) (map RPVar lowerNames)
      upperPat = RPCon (conDeclName constructor) (map RPVar upperNames)
      valuePat = RPCon (conDeclName constructor) (map RPVar valueNames)
      rangePat = derivedIxRepresentationPat rangeNames
      lowerRep = derivedIxRepresentationExpr (map RVar lowerNames)
      upperRep = derivedIxRepresentationExpr (map RVar upperNames)
      valueRep = derivedIxRepresentationExpr (map RVar valueNames)
      repBounds = RTuple [lowerRep, upperRep]
      construct fields = foldl RApp (RCon (conDeclName constructor)) fields
      boundsAlt rhs =
        RAlt
          (RPTuple [lowerPat, upperPat])
          (RUnguarded rhs)
          []
      rangeExpr =
        RCase
          (RVar boundsName)
          [ boundsAlt
              (RApp (RApp (RVar derivedMapName) (RLambda [rangePat] (construct (map RVar rangeNames)))) (RApp (RVar (classMethodName rangeMethod)) repBounds))
          ]
      indexExpr =
        RCase
          (RVar boundsName)
          [ boundsAlt
              (RCase (RVar valueName) [RAlt valuePat (RUnguarded (RApp (RApp (RVar (classMethodName indexMethod)) repBounds) valueRep)) []])
          ]
      inRangeExpr =
        RCase
          (RVar boundsName)
          [ boundsAlt
              (RCase (RVar valueName) [RAlt valuePat (RUnguarded (RApp (RApp (RVar (classMethodName inRangeMethod)) repBounds) valueRep)) []])
          ]
      rangeSizeExpr =
        RCase
          (RVar boundsName)
          [boundsAlt (RApp (RVar (classMethodName rangeSizeMethod)) repBounds)]
  pure
    [ (classMethodName rangeMethod, derivedMethodBinding (classMethodName rangeMethod) [RPVar boundsName] rangeExpr)
    , (classMethodName indexMethod, derivedMethodBinding (classMethodName indexMethod) [RPVar boundsName, RPVar valueName] indexExpr)
    , (classMethodName inRangeMethod, derivedMethodBinding (classMethodName inRangeMethod) [RPVar boundsName, RPVar valueName] inRangeExpr)
    , (classMethodName rangeSizeMethod, derivedMethodBinding (classMethodName rangeSizeMethod) [RPVar boundsName] rangeSizeExpr)
    ]
 where
  fieldCount = length (conDeclFieldTypes constructor)

derivedMethodBinding :: RName -> [RPat] -> RExpr -> SourceBinding
derivedMethodBinding methodName patterns expr =
  SourceBinding
    { sourceBindingSpan = Nothing
    , sourceBindingName = methodName
    , sourceBindingPatterns = patterns
    , sourceBindingPatternBinding = Nothing
    , sourceBindingRhs = RUnguarded expr
    , sourceBindingWhereDecls = []
    }

derivedIxRepresentationExpr :: [RExpr] -> RExpr
derivedIxRepresentationExpr = \case
  [expr] -> expr
  exprs -> RTuple exprs

derivedIxRepresentationPat :: [RName] -> RPat
derivedIxRepresentationPat = \case
  [name] -> RPVar name
  names -> RPTuple (map RPVar names)

constraintsOverlap :: ClassConstraint -> ClassConstraint -> Bool
constraintsOverlap lhs rhs =
  classConstraintClass lhs == classConstraintClass rhs
    && case (classConstraintArguments lhs, classConstraintArguments rhs) of
      ([lhsArg], [rhsArg]) -> typesMayUnify lhsArg rhsArg
      _ -> False

typesMayUnify :: MonoType -> MonoType -> Bool
typesMayUnify lhs rhs =
  case (lhs, rhs) of
    (TyVar {}, _) -> True
    (_, TyVar {}) -> True
    (TyMeta {}, _) -> True
    (_, TyMeta {}) -> True
    (TyCon lhsName, TyCon rhsName) -> lhsName == rhsName
    (TyApp (TyCon lhsName) lhsArg, TyList rhsElement)
      | lhsName == listTyConName -> typesMayUnify lhsArg rhsElement
    (TyList lhsElement, TyApp (TyCon rhsName) rhsArg)
      | rhsName == listTyConName -> typesMayUnify lhsElement rhsArg
    (TyApp lhsFn lhsArg, TyApp rhsFn rhsArg) ->
      typesMayUnify lhsFn rhsFn && typesMayUnify lhsArg rhsArg
    (TyFun lhsArg lhsResult, TyFun rhsArg rhsResult) ->
      typesMayUnify lhsArg rhsArg && typesMayUnify lhsResult rhsResult
    (TyTuple lhsFields, TyTuple rhsFields) ->
      length lhsFields == length rhsFields && and (zipWith typesMayUnify lhsFields rhsFields)
    (TyList lhsElement, TyList rhsElement) ->
      typesMayUnify lhsElement rhsElement
    _ -> False

inferInstanceDictionary :: TypeEnv -> [RHsType] -> RHsType -> [RDecl] -> InferM TypedInstanceDictionary
inferInstanceDictionary env sourceContext instanceHead decls = do
  (className, instanceType) <- splitInstanceHead instanceHead
  rawContext <- traverse sourceClassConstraint sourceContext
  context <- traverse (canonicalizeInstanceContextConstraint instanceType) rawContext
  classes <- classInfos <$> get
  info <-
    case Map.lookup className classes of
      Nothing -> throwTypecheck (UnsupportedCore0 ("instance for unknown class `" <> renderRName className <> "`"))
      Just classInfo -> pure classInfo
  methodMap <- collectInstanceMethods decls
  let classMethodNames = map classMethodName (classInfoMethods info)
      extraMethods = filter (`notElem` classMethodNames) (Map.keys methodMap)
  case extraMethods of
    [] -> pure ()
    extra : _ ->
      throwTypecheck (UnsupportedCore0 ("unknown instance method `" <> renderRName extra <> "`"))
  let replacements = Map.singleton (classInfoVariable info) instanceType
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
  typedMethods <- traverse (inferInstanceMethod env info instanceType methodMap) (classInfoMethods info)
  dictName <- instanceDictionaryName className instanceType
  pure
    TypedInstanceDictionary
      { typedInstanceClass = className
      , typedInstanceType = instanceType
      , typedInstanceVariables = typeVars instanceType
      , typedInstanceContext = context
      , typedInstanceDictName = dictName
      , typedInstanceSuperclasses = superclassConstraints
      , typedInstanceMethods = typedMethods
      }

splitInstanceHead :: RHsType -> InferM (RName, MonoType)
splitInstanceHead = \case
  RTyApp (RTyCon className) argument -> do
    let canonicalName = canonicalClassName className
    expectedKind <- classConstraintArgumentKind canonicalName
    (canonicalName,) <$> sourceMonoTypeAtKind expectedKind argument
  other ->
    throwTypecheck (UnsupportedCore0 ("instance head " <> Text.pack (show other)))

canonicalizeInstanceContextConstraint :: MonoType -> ClassConstraint -> InferM ClassConstraint
canonicalizeInstanceContextConstraint instanceType constraint = do
  arguments <- traverse canonicalize (classConstraintArguments constraint)
  pure constraint {classConstraintArguments = arguments}
 where
  variablesByOccurrence = Map.fromList [(nameOcc variable, variable) | variable <- typeVars instanceType]

  canonicalize = \case
    TyMeta meta ->
      pure (TyMeta meta)
    TyVar name ->
      case Map.lookup (nameOcc name) variablesByOccurrence of
        Just variable ->
          pure (TyVar variable)
        Nothing ->
          throwTypecheck
            ( UnsupportedCore0
                ( "instance context type variable `"
                    <> nameOcc name
                    <> "` is not bound by the instance head"
                )
            )
    TyCon name ->
      pure (TyCon name)
    TyApp fn arg ->
      TyApp <$> canonicalize fn <*> canonicalize arg
    TyFun arg result ->
      TyFun <$> canonicalize arg <*> canonicalize result
    TyTuple fields ->
      TyTuple <$> traverse canonicalize fields
    TyList element ->
      TyList <$> canonicalize element

collectInstanceMethods :: [RDecl] -> InferM (Map.Map RName SourceBinding)
collectInstanceMethods =
  foldM collect Map.empty
 where
  collect acc decl =
    withTypecheckSpan (rDeclSpan decl) $
      case decl of
        RFunctionBinding name patterns rhs whereDecls ->
          let canonicalName = canonicalInstanceMethodName name
           in case Map.lookup canonicalName acc of
            Just _ ->
              throwTypecheck (UnsupportedCore0 ("duplicate instance method `" <> renderRName canonicalName <> "`"))
            Nothing ->
              pure
                ( Map.insert
                    canonicalName
                    SourceBinding
                      { sourceBindingSpan = rDeclSpan decl
                      , sourceBindingName = canonicalName
                      , sourceBindingPatterns = patterns
                      , sourceBindingPatternBinding = Nothing
                      , sourceBindingRhs = rhs
                      , sourceBindingWhereDecls = whereDecls
                      }
                    acc
                )
        RTypeSignature {} ->
          pure acc
        RFixityDecl {} ->
          pure acc
        other ->
          throwTypecheck (UnsupportedCore0 ("instance declaration item " <> Text.pack (show other)))

canonicalInstanceMethodName :: RName -> RName
canonicalInstanceMethodName name
  | nameExternal name =
      maybe name classMethodName (builtinMethodInfoByOccurrence (nameOcc name))
  | otherwise =
      name

inferInstanceMethod ::
  TypeEnv ->
  ClassInfo ->
  MonoType ->
  Map.Map RName SourceBinding ->
  ClassMethodInfo ->
  InferM TypedExpr
inferInstanceMethod env info instanceType methodMap method =
  case Map.lookup (classMethodName method) methodMap <|> classMethodDefault method of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("missing instance method `" <> renderRName (classMethodName method) <> "`"))
    Just binding ->
      inferInstanceMethodBinding env info instanceType method binding

inferInstanceMethodBinding ::
  TypeEnv ->
  ClassInfo ->
  MonoType ->
  ClassMethodInfo ->
  SourceBinding ->
  InferM TypedExpr
inferInstanceMethodBinding env info instanceType method binding =
  withTypecheckSpan (sourceBindingSpan binding) $ do
    let replacements = Map.singleton (classInfoVariable info) instanceType
        expected = replaceTypeVars replacements (classMethodFieldType method)
        exhaustivenessContext =
          case sourceBindingSpan binding of
            Nothing -> GeneratedPatternExhaustiveness
            Just _ -> FunctionPatternExhaustiveness (sourceBindingName binding)
    expr <-
      inferFunctionBindingExpr
        env
        exhaustivenessContext
        (sourceBindingPatterns binding)
        (sourceBindingRhs binding)
        (sourceBindingWhereDecls binding)
    unify expected (typedExprType expr)
    pure expr

aliasPatternBinder :: RName -> MonoType -> TypedExpr -> TypedExpr -> TypedExpr
aliasPatternBinder name ty scrutinee body =
  case scrutinee of
    TVar scrutineeName _ _ _
      | scrutineeName == name -> body
    _ ->
      TLet
        [ TypedBinding
            { typedBindingName = name
            , typedBindingScheme = Scheme [] [] ty
            , typedBindingGeneralizedMetas = Map.empty
            , typedBindingRhs = scrutinee
            }
        ]
        body
        (typedExprType body)

instanceDictionaryName :: RName -> MonoType -> InferM RName
instanceDictionaryName className instanceType =
  freshGeneratedName
    TermNamespace
    ("$f" <> nameOcc className <> monoTypeOccurrence instanceType)

monoTypeOccurrence :: MonoType -> Text
monoTypeOccurrence = \case
  TyMeta meta -> "$m" <> renderInt meta
  TyVar name -> nameOcc name
  TyCon name -> nameOcc name
  TyApp fn arg -> monoTypeOccurrence fn <> "_" <> monoTypeOccurrence arg
  TyFun arg result -> "Fun_" <> monoTypeOccurrence arg <> "_" <> monoTypeOccurrence result
  TyTuple fields -> "Tuple" <> renderInt (length fields)
  TyList element -> "List_" <> monoTypeOccurrence element

inferFunctionBindingExpr :: TypeEnv -> PatternExhaustivenessContext -> [RPat] -> RRhs -> [RDecl] -> InferM TypedExpr
inferFunctionBindingExpr env context patterns rhs whereDecls = do
  inferLambdaRhs env context patterns rhs whereDecls

inferPatternBindingSelectorExpr :: TypeEnv -> RName -> RPat -> RRhs -> [RDecl] -> InferM TypedExpr
inferPatternBindingSelectorExpr env name pat rhs whereDecls = do
  scrutinee <- inferRhs env rhs whereDecls
  (bindings, _patternEnv) <- inferIrrefutablePatternBindings (typedExprType scrutinee) scrutinee pat
  case List.find ((== name) . typedBindingName) bindings of
    Just binding ->
      pure (typedBindingRhs binding)
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("pattern binding does not bind `" <> renderRName name <> "`"))

inferLambda :: TypeEnv -> [RPat] -> RExpr -> InferM TypedExpr
inferLambda env patterns bodyExpr =
  inferLambdaBody env LambdaPatternExhaustiveness patterns (inferExpr) bodyExpr

inferLambdaRhs :: TypeEnv -> PatternExhaustivenessContext -> [RPat] -> RRhs -> [RDecl] -> InferM TypedExpr
inferLambdaRhs env context patterns rhs whereDecls =
  inferLambdaBody env context patterns (\bodyEnv _ -> inferRhs bodyEnv rhs whereDecls) (RUnit)

inferLambdaBody :: TypeEnv -> PatternExhaustivenessContext -> [RPat] -> (TypeEnv -> RExpr -> InferM TypedExpr) -> RExpr -> InferM TypedExpr
inferLambdaBody env context patterns inferBody bodyExpr = do
  (binders, bodyEnv, wrapPatterns) <- inferLambdaPatterns context env patterns
  body <- wrapPatterns <$> inferBody bodyEnv bodyExpr
  pure (foldr wrapLambda body binders)
 where
  wrapLambda binder body =
    TLam binder body (TyFun (typedBinderType binder) (typedExprType body))

inferLambdaPatterns :: PatternExhaustivenessContext -> TypeEnv -> [RPat] -> InferM ([TypedBinder], TypeEnv, TypedExpr -> TypedExpr)
inferLambdaPatterns context initialEnv =
  go [] initialEnv id
 where
  go binders env wrap = \case
    [] ->
      pure (binders, env, wrap)
    pat : rest ->
      case pat of
        RPVar name -> do
          binder <- TypedBinder name <$> freshMeta
          go
            (binders <> [binder])
            (Map.insert name (Scheme [] [] (typedBinderType binder)) env)
            wrap
            rest
        RPWildcard -> do
          binder <- freshMeta >>= freshTermBinder "$wild"
          go (binders <> [binder]) env wrap rest
        RPParen inner ->
          go binders env wrap (inner : rest)
        _ -> do
          patTy <- freshMeta
          binder <- freshTermBinder "$arg" patTy
          caseBinder <- freshTermBinder "$case" patTy
          let scrutinee = TVar (typedBinderName binder) (Scheme [] [] patTy) [] patTy
          plan <- inferPatternPlan env patTy scrutinee pat
          warnForPatternCoverage context patTy [PatternCoverageRow (rPatSpan pat) pat (RUnguarded RUnit)]
          let wrapOne = caseForPatternPlan scrutinee caseBinder plan
          go (binders <> [binder]) (patternEnv plan) (wrap . wrapOne) rest

inferRhs :: TypeEnv -> RRhs -> [RDecl] -> InferM TypedExpr
inferRhs env rhs whereDecls =
  withTypecheckSpan (rRhsSpan rhs) $ do
    (whereBindings, rhsEnv) <-
      if null whereDecls
        then pure ([], env)
        else inferBindingGroup env whereDecls
    body <-
      case rhs of
        RUnguarded expr ->
          inferExpr rhsEnv expr
        RGuarded branches ->
          inferGuardedBranches rhsEnv branches
    pure $
      case whereBindings of
        [] -> body
        bindings -> TLet bindings body (typedExprType body)

inferGuardedBranches :: TypeEnv -> [(RExpr, RExpr)] -> InferM TypedExpr
inferGuardedBranches env branches = do
  resultTy <- freshMeta
  go resultTy branches
 where
  go resultTy =
    \case
      [] ->
        patternMatchFailureExpr resultTy
      (guardExpr, bodyExpr) : rest -> do
        typedGuard <- inferExpr env guardExpr
        unify (typedExprType typedGuard) boolMonoType
        typedBody <- inferExpr env bodyExpr
        unify resultTy (typedExprType typedBody)
        falseBranch <- go resultTy rest
        branchResultTy <- applyCurrent resultTy
        caseBinder <- freshTermBinder "$guard" boolMonoType
        pure
          ( TCase
              typedGuard
              caseBinder
              [ TypedAlt (ConstructorAlt trueDataConName) [] typedBody
              , TypedAlt (ConstructorAlt falseDataConName) [] falseBranch
              ]
              branchResultTy
          )

patternMatchFailureExpr :: MonoType -> InferM TypedExpr
patternMatchFailureExpr resultTy = do
  resultTy' <- applyCurrent resultTy
  caseBinder <- freshTermBinder "$match_fail" boolMonoType
  pure
    ( TCase
        (TCon falseDataConName (Scheme [] [] boolMonoType) [] boolMonoType)
        caseBinder
        []
        resultTy'
    )

inferExpr :: TypeEnv -> RExpr -> InferM TypedExpr
inferExpr env expr =
  withTypecheckSpan (rExprSpan expr) $
    case expr of
      RVar name ->
        case Map.lookup name env of
          Nothing ->
            inferPreludeValue name
          Just scheme -> do
            (instantiatedTy, typeArguments) <- instantiate scheme
            pure (TVar name scheme typeArguments instantiatedTy)
      RCon name ->
        inferConstructor name
      RRecordCon name fields ->
        inferRecordConstruction env name fields
      RRecordUpdate scrutinee fields ->
        inferRecordUpdate env scrutinee fields
      RLit (LString value) ->
        pure (stringLiteralTypedExpr value)
      RLit (LInt value) ->
        inferIntegerLiteral value
      RLit (LFloat value) ->
        inferFractionalLiteral (toRational value)
      RLit (LDouble value) ->
        inferFractionalLiteral (toRational value)
      RLit literal ->
        pure (TLit literal (literalMonoType literal))
      RApp fn arg -> do
        typedFn <- inferExpr env fn
        typedArg <- inferExpr env arg
        resultTy <- freshMeta
        unify (typedExprType typedFn) (TyFun (typedExprType typedArg) resultTy)
        pure (TApp typedFn typedArg resultTy)
      RInfixApp lhs op rhs ->
        inferInfixApp env lhs op rhs
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
        scrutineeTy <- applyCurrent (typedExprType typedScrutinee)
        resultTy <- freshMeta
        let coverageContext =
              case rExprSpan expr of
                Nothing -> GeneratedPatternExhaustiveness
                Just _ -> CasePatternExhaustiveness
        warnForPatternCoverage coverageContext scrutineeTy [PatternCoverageRow (rAltSpan alt) pat rhs | alt@(RAlt pat rhs _) <- alternatives]
        case alternatives of
          firstAlt : _ -> do
            firstIrrefutable <- caseAltCanElideRuntimeCase firstAlt
            if firstIrrefutable
              then snd <$> inferCaseAlt env scrutineeTy typedScrutinee resultTy firstAlt
              else inferRuntimeCase env typedScrutinee scrutineeTy resultTy alternatives
          [] ->
            throwTypecheck (UnsupportedCore0 "empty case expression")
      RDo statements ->
        inferDo env statements
      RList expressions -> do
        elementTy <- freshMeta
        typedElements <- traverse (inferExpr env) expressions
        mapM_ (unify elementTy . typedExprType) typedElements
        elementTy' <- applyCurrent elementTy
        pure (TList typedElements (TyList elementTy'))
      RTuple expressions -> do
        typedFields <- traverse (inferExpr env) expressions
        pure (TTuple typedFields (TyTuple (map typedExprType typedFields)))
      RUnit ->
        pure (TTuple [] unitMonoType)
      RParen inner ->
        inferExpr env inner
      RLeftSection sectionExpr op ->
        inferSection env "$section_rhs" (\hole -> RInfixApp sectionExpr op hole)
      RRightSection op sectionExpr ->
        inferSection env "$section_lhs" (\hole -> RInfixApp hole op sectionExpr)
      RArithmeticSeq start step end ->
        inferArithmeticSeq env start step end
      RListComp body statements ->
        inferListComp env body statements
      RExprTypeSig inner sourceType -> do
        scheme <- sourceScheme sourceType
        unless (null (schemeConstraints scheme)) $
          throwUnsupportedClassConstraintContext ExpressionSignatureConstraintContext (schemeConstraints scheme)
        typedInner <- inferExpr env inner
        unify (typedExprType typedInner) (schemeBody scheme)
        pure typedInner

inferSection :: TypeEnv -> Text -> (RExpr -> RExpr) -> InferM TypedExpr
inferSection env argumentOccurrence buildBody = do
  argumentTy <- freshMeta
  binder <- freshTermBinder argumentOccurrence argumentTy
  let binderName = typedBinderName binder
      bodyEnv = Map.insert binderName (Scheme [] [] argumentTy) env
  body <- inferExpr bodyEnv (buildBody (RVar binderName))
  argumentTy' <- applyCurrent argumentTy
  resultTy <- applyCurrent (typedExprType body)
  let binder' = TypedBinder binderName argumentTy'
  pure (TLam binder' body (TyFun argumentTy' resultTy))

inferArithmeticSeq :: TypeEnv -> RExpr -> Maybe RExpr -> Maybe RExpr -> InferM TypedExpr
inferArithmeticSeq env start maybeStep maybeEnd = do
  typedStart <- inferExpr env start
  typedStep <- traverse (inferExpr env) maybeStep
  typedEnd <- traverse (inferExpr env) maybeEnd
  traverse_ (unify (typedExprType typedStart) . typedExprType) typedStep
  traverse_ (unify (typedExprType typedStart) . typedExprType) typedEnd
  inferredElementTy <- applyCurrent (typedExprType typedStart)
  elementTy <-
    case inferredElementTy of
      TyMeta {} -> do
        unify inferredElementTy intMonoType
        pure intMonoType
      _ ->
        pure inferredElementTy
  unify (typedExprType typedStart) elementTy
  traverse_ (unify elementTy . typedExprType) typedStep
  traverse_ (unify elementTy . typedExprType) typedEnd
  elementTy' <- applyCurrent elementTy
  method <- builtinClassMethod "Enum" (arithmeticSequenceMethodOccurrence typedStep typedEnd)
  classVariable <- classMethodSingleVariable (nameOcc (classMethodName method)) method
  sourceRange <- currentTypecheckSpan
  let methodScheme = withSchemeConstraintSpan sourceRange (classMethodScheme method)
      methodTy = replaceTypeVars (Map.singleton classVariable elementTy') (schemeBody methodScheme)
      methodExpr = TVar (classMethodName method) methodScheme [elementTy'] methodTy
      arguments = typedStart : maybe [] (: []) typedStep <> maybe [] (: []) typedEnd
  pure (applyArithmeticSequenceMethod methodExpr arguments)

arithmeticSequenceMethodOccurrence :: Maybe TypedExpr -> Maybe TypedExpr -> Text
arithmeticSequenceMethodOccurrence typedStep typedEnd =
  case (typedStep, typedEnd) of
    (Nothing, Nothing) -> "enumFrom"
    (Just _, Nothing) -> "enumFromThen"
    (Nothing, Just _) -> "enumFromTo"
    (Just _, Just _) -> "enumFromThenTo"

applyArithmeticSequenceMethod :: TypedExpr -> [TypedExpr] -> TypedExpr
applyArithmeticSequenceMethod =
  List.foldl' apply
 where
  apply fn arg =
    case typedExprType fn of
      TyFun _ resultTy -> TApp fn arg resultTy
      _ -> error "arithmetic sequence method applied past its arity"

inferListComp :: TypeEnv -> RExpr -> [RStmt] -> InferM TypedExpr
inferListComp env body statements = do
  elementTy <- freshMeta
  inferListCompWithTail env elementTy body statements (typedListNil elementTy)

inferListCompWithTail :: TypeEnv -> MonoType -> RExpr -> [RStmt] -> TypedExpr -> InferM TypedExpr
inferListCompWithTail env elementTy body [] tailExpr = do
  typedBody <- inferExpr env body
  unify elementTy (typedExprType typedBody)
  elementTy' <- applyCurrent elementTy
  unify (typedExprType tailExpr) (TyList elementTy')
  pure (typedListCons elementTy' typedBody tailExpr)
inferListCompWithTail env elementTy body (statement : rest) tailExpr =
  withTypecheckSpan (rStmtSpan statement) $
    case statement of
      RExprStmt guardExpr -> do
        typedGuard <- inferExpr env guardExpr
        unify (typedExprType typedGuard) boolMonoType
        success <- inferListCompWithTail env elementTy body rest tailExpr
        unify (typedExprType success) (typedExprType tailExpr)
        caseBinder <- freshTermBinder "$list_comp_guard" boolMonoType
        pure
          ( TCase
              typedGuard
              caseBinder
              [ TypedAlt (ConstructorAlt trueDataConName) [] success
              , TypedAlt (ConstructorAlt falseDataConName) [] tailExpr
              ]
              (typedExprType tailExpr)
          )
      RLetStmt decls -> do
        (bindings, env') <- inferBindingGroup env decls
        restExpr <- inferListCompWithTail env' elementTy body rest tailExpr
        pure (TLet bindings restExpr (typedExprType restExpr))
      RBindStmt pat sourceExpr -> do
        typedSource <- inferExpr env sourceExpr
        sourceElementTy <- freshMeta
        unify (typedExprType typedSource) (TyList sourceElementTy)
        sourceElementTy' <- applyCurrent sourceElementTy
        elementTy' <- applyCurrent elementTy
        let sourceListTy = TyList sourceElementTy'
            resultListTy = TyList elementTy'
            goTy = TyFun sourceListTy (TyFun resultListTy resultListTy)
        goBinder <- freshTermBinder "$list_comp_go" goTy
        xsBinder <- freshTermBinder "$list_comp_xs" sourceListTy
        accBinder <- freshTermBinder "$list_comp_acc" resultListTy
        caseBinder <- freshTermBinder "$list_comp_list" sourceListTy
        headBinder <- freshTermBinder "$list_comp_head" sourceElementTy'
        tailBinder <- freshTermBinder "$list_comp_tail" sourceListTy
        let goExpr = typedLocalVar goBinder
            xsExpr = typedLocalVar xsBinder
            accExpr = typedLocalVar accBinder
            headExpr = typedLocalVar headBinder
            tailListExpr = typedLocalVar tailBinder
            recursiveTail =
              TApp
                (TApp goExpr tailListExpr (TyFun resultListTy resultListTy))
                accExpr
                resultListTy
        consBody <-
          inferListCompPattern
            env
            sourceElementTy'
            headExpr
            pat
            (\env' -> inferListCompWithTail env' elementTy body rest recursiveTail)
            recursiveTail
        unify (typedExprType consBody) resultListTy
        let goBody =
              TCase
                xsExpr
                caseBinder
                [ TypedAlt (ConstructorAlt listNilDataConName) [] accExpr
                , TypedAlt (ConstructorAlt listConsDataConName) [headBinder, tailBinder] consBody
                ]
                resultListTy
            goRhs =
              TLam xsBinder (TLam accBinder goBody (TyFun resultListTy resultListTy)) goTy
            goBinding =
              TypedBinding
                { typedBindingName = typedBinderName goBinder
                , typedBindingScheme = Scheme [] [] goTy
                , typedBindingGeneralizedMetas = Map.empty
                , typedBindingRhs = goRhs
                }
            appliedGo =
              TApp
                (TApp goExpr typedSource (TyFun resultListTy resultListTy))
                tailExpr
                resultListTy
        pure (TLet [goBinding] appliedGo resultListTy)

inferListCompPattern ::
  TypeEnv ->
  MonoType ->
  TypedExpr ->
  RPat ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompPattern env expectedTy scrutinee pat success failure =
  withTypecheckSpan (rPatSpan pat) $
    case pat of
      RPVar name -> do
        body <- success (Map.insert name (Scheme [] [] expectedTy) env)
        pure (aliasPatternBinder name expectedTy scrutinee body)
      RPWildcard ->
        success env
      RPLit (LString value) ->
        inferListCompPattern env expectedTy scrutinee (RPList (stringLiteralPattern value)) success failure
      RPLit literal -> do
        unify expectedTy (literalMonoType literal)
        matched <- success env
        listCompMatchCase scrutinee [(LiteralAlt literal, [], matched)] failure
      RPCon name args ->
        inferListCompConstructorPattern env expectedTy scrutinee name args success failure
      RPRecordCon name fields ->
        inferListCompRecordPattern env expectedTy scrutinee name fields success failure
      RPTuple patterns ->
        inferListCompTuplePattern env expectedTy scrutinee patterns success failure
      RPList patterns ->
        inferListCompListPattern env expectedTy scrutinee patterns success failure
      RPParen inner ->
        inferListCompPattern env expectedTy scrutinee inner success failure
      RPAs name inner ->
        inferListCompPattern
          env
          expectedTy
          scrutinee
          inner
          ( \innerEnv -> do
              body <- success (Map.insert name (Scheme [] [] expectedTy) innerEnv)
              pure (aliasPatternBinder name expectedTy scrutinee body)
          )
          failure
      RPIrrefutable inner -> do
        plan <- inferIrrefutablePatternPlan env expectedTy scrutinee inner
        body <- success (patternEnv plan)
        pure (patternWrapBody plan body)

inferListCompConstructorPattern ::
  TypeEnv ->
  MonoType ->
  TypedExpr ->
  RName ->
  [RPat] ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompConstructorPattern env expectedTy scrutinee name args success failure = do
  (coreName, info) <- lookupListCompConstructor name
  (fieldTypes, resultTy) <- instantiateConstructorPattern info
  unless (length fieldTypes == length args) $
    throwTypecheck
      ( UnsupportedCore0
          ( "constructor pattern `"
              <> renderRName name
              <> "` expects "
              <> Text.pack (show (length fieldTypes))
              <> " fields, got "
              <> Text.pack (show (length args))
          )
      )
  unify expectedTy resultTy
  case dataConstructorRepresentation info of
    CoreNewtypeConstructor ->
      case (fieldTypes, args) of
        ([fieldTy], [fieldPat]) -> do
          fieldTy' <- applyCurrent fieldTy
          inferListCompPattern env fieldTy' (TCoerce scrutinee fieldTy') fieldPat success failure
        _ ->
          throwTypecheck (InvalidNewtypeConstructorArity name (length fieldTypes))
    CoreDataConstructor -> do
      fieldTypes' <- traverse applyCurrent fieldTypes
      fieldBinders <- traverse (uncurry listCompFieldBinder) (zip [0 ..] fieldTypes')
      matched <- inferListCompFieldPatterns env fieldBinders args success failure
      listCompMatchCase
        scrutinee
        [(ConstructorAlt coreName, fieldBinders, matched)]
        failure

inferListCompRecordPattern ::
  TypeEnv ->
  MonoType ->
  TypedExpr ->
  RName ->
  [(RName, RPat)] ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompRecordPattern env expectedTy scrutinee name fields success failure = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("record constructor pattern `" <> renderRName name <> "`"))
    Just info -> do
      orderedFields <- orderRecordPatternFields name info fields
      inferListCompConstructorPattern env expectedTy scrutinee name orderedFields success failure

inferListCompTuplePattern ::
  TypeEnv ->
  MonoType ->
  TypedExpr ->
  [RPat] ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompTuplePattern env expectedTy scrutinee patterns success failure = do
  fieldTypes <- traverse (const freshMeta) patterns
  unify expectedTy (TyTuple fieldTypes)
  fieldTypes' <- traverse applyCurrent fieldTypes
  fieldBinders <- traverse (uncurry listCompFieldBinder) (zip [0 ..] fieldTypes')
  matched <- inferListCompFieldPatterns env fieldBinders patterns success failure
  listCompMatchCase
    scrutinee
    [(ConstructorAlt (tupleDataConName (length patterns)), fieldBinders, matched)]
    failure

inferListCompListPattern ::
  TypeEnv ->
  MonoType ->
  TypedExpr ->
  [RPat] ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompListPattern env expectedTy scrutinee patterns success failure = do
  elementTy <- freshMeta
  unify expectedTy (TyList elementTy)
  case patterns of
    [] -> do
      matched <- success env
      listCompMatchCase scrutinee [(ConstructorAlt listNilDataConName, [], matched)] failure
    headPat : tailPats ->
      inferListCompConstructorPattern env expectedTy scrutinee listConsDataConName [headPat, RPList tailPats] success failure

inferListCompFieldPatterns ::
  TypeEnv ->
  [TypedBinder] ->
  [RPat] ->
  (TypeEnv -> InferM TypedExpr) ->
  TypedExpr ->
  InferM TypedExpr
inferListCompFieldPatterns env fieldBinders patterns success failure =
  go env (zip fieldBinders patterns)
 where
  go currentEnv [] =
    success currentEnv
  go currentEnv ((binder, pat) : rest) =
    inferListCompPattern
      currentEnv
      (typedBinderType binder)
      (typedLocalVar binder)
      pat
      (\env' -> go env' rest)
      failure

listCompMatchCase :: TypedExpr -> [(CoreAltCon, [TypedBinder], TypedExpr)] -> TypedExpr -> InferM TypedExpr
listCompMatchCase scrutinee matchedAlternatives failure = do
  mapM_ (\(_, _, body) -> unify (typedExprType body) (typedExprType failure)) matchedAlternatives
  caseBinder <- freshTermBinder "$list_comp_match" (typedExprType scrutinee)
  pure
    ( TCase
        scrutinee
        caseBinder
        ( [TypedAlt altCon binders body | (altCon, binders, body) <- matchedAlternatives]
            <> [TypedAlt DefaultAlt [] failure]
        )
        (typedExprType failure)
    )

lookupListCompConstructor :: RName -> InferM (RName, DataConstructorInfo)
lookupListCompConstructor name = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Just info ->
      pure (name, info)
    Nothing ->
      case preludeConstructorInfo name of
        Just (coreName, info) ->
          pure (coreName, info)
        Nothing ->
          throwTypecheck (UnsupportedCore0 ("constructor pattern `" <> renderRName name <> "`"))

listCompFieldBinder :: Int -> MonoType -> InferM TypedBinder
listCompFieldBinder index =
  freshTermBinder ("$list_comp_field" <> renderInt index)

typedLocalVar :: TypedBinder -> TypedExpr
typedLocalVar binder =
  TVar (typedBinderName binder) (Scheme [] [] (typedBinderType binder)) [] (typedBinderType binder)

typedListNil :: MonoType -> TypedExpr
typedListNil elementTy =
  TList [] (TyList elementTy)

typedListCons :: MonoType -> TypedExpr -> TypedExpr -> TypedExpr
typedListCons elementTy headExpr tailExpr =
  TApp (TApp consExpr headExpr (TyFun listTy listTy)) tailExpr listTy
 where
  listTy = TyList elementTy
  consScheme = dataConstructorScheme (builtinDataConstructors Map.! listConsDataConName)
  consExpr = TCon listConsDataConName consScheme [elementTy] (TyFun elementTy (TyFun listTy listTy))

inferDo :: TypeEnv -> [RStmt] -> InferM TypedExpr
inferDo _ [] =
  throwTypecheck (UnsupportedCore0 "empty do expression")
inferDo env [statement@(RExprStmt expr)] =
  withTypecheckSpan (rStmtSpan statement) $
    inferExpr env expr
inferDo env (statement@(RExprStmt expr) : rest) =
  withTypecheckSpan (rStmtSpan statement) $ do
    first <- inferExpr env expr
    restExpr <- inferDo env rest
    thenExpr <- inferPreludeMonadMethod env ">>"
    thenFirst <- applyTypedExpr thenExpr first
    applyTypedExpr thenFirst restExpr
inferDo env (statement@(RLetStmt decls) : rest) =
  withTypecheckSpan (rStmtSpan statement) $ do
    (bindings, env') <- inferBindingGroup env decls
    body <- inferDo env' rest
    pure (TLet bindings body (typedExprType body))
inferDo env (statement@(RBindStmt pat expr) : rest) =
  withTypecheckSpan (rStmtSpan statement) $ do
    first <- inferExpr env expr
    bindExpr <- inferPreludeMonadMethod env ">>="
    bindFirst <- applyTypedExpr bindExpr first
    bindFirstTy <- applyCurrent (typedExprType bindFirst)
    (valueTy, expectedBodyTy) <-
      case bindFirstTy of
        TyFun (TyFun argumentTy resultTy) _ ->
          pure (argumentTy, resultTy)
        other ->
          throwTypecheck
            ( UnsupportedCore0
                ( "built-in method `>>=` has unexpected partially applied type "
                    <> renderMonoType other
                )
            )
    valueTy' <- applyCurrent valueTy
    argumentBinder <- freshTermBinder "$do_bind" valueTy'
    caseBinder <- freshTermBinder "$do_bind_case" valueTy'
    let argument =
          TVar
            (typedBinderName argumentBinder)
            (Scheme [] [] valueTy')
            []
            valueTy'
    plan <- inferPatternPlan env valueTy' argument pat
    body <- inferDo (patternEnv plan) rest
    unify (typedExprType body) expectedBodyTy
    bodyTy <- applyCurrent (typedExprType body)
    failedBody <- doPatternFailBody env statement bodyTy
    let wrappedBody =
          doCaseForPatternPlan
            (patternSyntacticallyIrrefutable pat)
            argument
            caseBinder
            plan
            body
            failedBody
        continuationTy = TyFun valueTy' (typedExprType wrappedBody)
        continuation = TLam argumentBinder wrappedBody continuationTy
    applyTypedExpr bindFirst continuation

inferPreludeMonadMethod :: TypeEnv -> Text -> InferM TypedExpr
inferPreludeMonadMethod env occurrence = do
  unique <- monadMethodUnique occurrence
  inferExpr env (RVar (preludeTermName occurrence unique))
 where
  monadMethodUnique = \case
    ">>=" -> pure (-1461)
    ">>" -> pure (-1462)
    "return" -> pure (-1463)
    "fail" -> pure (-1464)
    other -> throwTypecheck (UnsupportedCore0 ("unknown Monad method `" <> other <> "`"))

applyTypedExpr :: TypedExpr -> TypedExpr -> InferM TypedExpr
applyTypedExpr fn arg = do
  resultTy <- freshMeta
  unify (typedExprType fn) (TyFun (typedExprType arg) resultTy)
  resultTy' <- applyCurrent resultTy
  pure (TApp fn arg resultTy')

doPatternFailBody :: TypeEnv -> RStmt -> MonoType -> InferM TypedExpr
doPatternFailBody env statement expectedTy = do
  failExpr <- inferPreludeMonadMethod env "fail"
  let message =
        "pattern match failure in do expression"
          <> maybe "" ((": " <>) . renderSourceDiagnosticLine) (rStmtSpan statement)
      messageExpr = stringLiteralTypedExpr message
  failed <- applyTypedExpr failExpr messageExpr
  unify (typedExprType failed) expectedTy
  pure failed

renderSourceDiagnosticLine :: SourceSpan -> Text
renderSourceDiagnosticLine sourceRange =
  case Text.lines (renderSourceDiagnostic sourceRange "" "") of
    firstLine : _ -> firstLine
    [] -> ""

doCaseForPatternPlan :: Bool -> TypedExpr -> TypedBinder -> PatternPlan -> TypedExpr -> TypedExpr -> TypedExpr
doCaseForPatternPlan isIrrefutable scrutinee caseBinder plan success failure
  | patternNeedsRuntimeCase plan && not isIrrefutable =
      TCase
        scrutinee
        caseBinder
        [ TypedAlt
            (patternAltCon plan)
            (patternAltBinders plan)
            (patternWrapBody plan success)
        , TypedAlt DefaultAlt [] failure
        ]
        (typedExprType success)
  | otherwise =
      caseForPatternPlan scrutinee caseBinder plan success

inferRecordConstruction :: TypeEnv -> RName -> [(RName, RExpr)] -> InferM TypedExpr
inferRecordConstruction env name fields = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("record constructor `" <> renderRName name <> "`"))
    Just info -> do
      orderedFields <- orderRecordFields "record construction" name info fields
      (fieldTypes, resultTy, typeArguments) <- instantiateConstructorFields info
      typedFields <- traverse (inferExpr env) orderedFields
      mapM_ (uncurry unify) (zip fieldTypes (map typedExprType typedFields))
      constructorTy <- applyCurrent (foldr TyFun resultTy fieldTypes)
      typedConstructor <- typedConstructorExpr name info typeArguments constructorTy
      foldM applyConstructorArgument typedConstructor typedFields
 where
  applyConstructorArgument function argument = do
    freshResultTy <- freshMeta
    unify (typedExprType function) (TyFun (typedExprType argument) freshResultTy)
    resultTy' <- applyCurrent freshResultTy
    pure (TApp function argument resultTy')

inferRecordUpdate :: TypeEnv -> RExpr -> [(RName, RExpr)] -> InferM TypedExpr
inferRecordUpdate env scrutinee fields = do
  when (null fields) $
    throwTypecheck (UnsupportedCore0 "record update requires at least one field")
  ensureNoDuplicateRecordUpdateLabels (map fst fields)
  selectors <- recordSelectors <$> get
  selectorInfos <- traverse (lookupRecordUpdateSelector selectors) (map fst fields)
  targetHead <- recordUpdateTargetHead selectorInfos
  typedScrutinee <- inferExpr env scrutinee
  rejectMismatchedConcreteRecordUpdate targetHead typedScrutinee
  typedFields <- traverse (\(name, expr) -> (name,) <$> inferExpr env expr) fields
  unifyRecordUpdateFields typedScrutinee typedFields selectorInfos
  scrutineeTy <- applyCurrent (typedExprType typedScrutinee)
  constructors <- dataConstructors <$> get
  let recordConstructors = recordConstructorsForHead targetHead constructors
      updateLabels = Set.fromList (map fst fields)
      updatableConstructors =
        [ (name, info)
        | (name, info) <- recordConstructors
        , recordConstructorHasLabels updateLabels info
        ]
  when (null updatableConstructors) $
    throwTypecheck
      ( UnsupportedCore0
          ( "record update fields "
              <> Text.intercalate ", " (map (renderRName . fst) fields)
              <> " are not all provided by any constructor of `"
              <> renderRName targetHead
              <> "`"
          )
      )
  case updatableConstructors of
    [(name, info)]
      | dataConstructorRepresentation info == CoreNewtypeConstructor ->
          recordUpdateConstructorBody scrutineeTy (Map.fromList typedFields) name info
    _ -> do
      alternatives <- traverse (uncurry (recordUpdateAlternative scrutineeTy (Map.fromList typedFields))) updatableConstructors
      resultTy <- applyCurrent scrutineeTy
      caseBinder <- freshTermBinder "$record_update" resultTy
      pure (TCase typedScrutinee caseBinder alternatives resultTy)

lookupRecordUpdateSelector :: Map.Map RName RecordSelectorInfo -> RName -> InferM RecordSelectorInfo
lookupRecordUpdateSelector selectors label =
  case Map.lookup label selectors of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("record update uses unknown field `" <> renderRName label <> "`"))
    Just info ->
      pure info

recordUpdateTargetHead :: [RecordSelectorInfo] -> InferM RName
recordUpdateTargetHead selectorInfos =
  case List.nub (mapMaybe (recordTypeHead . recordSelectorResultType) selectorInfos) of
    [targetHead] ->
      pure targetHead
    [] ->
      throwTypecheck (UnsupportedCore0 "record update could not determine a record datatype")
    heads ->
      throwTypecheck
        ( UnsupportedCore0
            ( "record update fields are ambiguous across datatypes "
                <> Text.intercalate ", " (map renderRName heads)
            )
        )

rejectMismatchedConcreteRecordUpdate :: RName -> TypedExpr -> InferM ()
rejectMismatchedConcreteRecordUpdate targetHead typedScrutinee = do
  scrutineeTy <- applyCurrent (typedExprType typedScrutinee)
  case recordTypeHead scrutineeTy of
    Just scrutineeHead
      | scrutineeHead /= targetHead ->
          throwTypecheck
            ( UnsupportedCore0
                ( "record update uses fields from `"
                    <> renderRName targetHead
                    <> "` on scrutinee of type "
                    <> renderMonoType scrutineeTy
                )
            )
    _ ->
      pure ()

unifyRecordUpdateFields :: TypedExpr -> [(RName, TypedExpr)] -> [RecordSelectorInfo] -> InferM ()
unifyRecordUpdateFields typedScrutinee typedFields selectorInfos =
  traverse_ unifyOne (zip typedFields selectorInfos)
 where
  unifyOne ((_, typedField), selectorInfo) = do
    (selectorTy, _) <- instantiate (recordSelectorScheme selectorInfo)
    case selectorTy of
      TyFun recordTy fieldTy -> do
        unify (typedExprType typedScrutinee) recordTy
        unify (typedExprType typedField) fieldTy
      other ->
        throwTypecheck (UnsupportedCore0 ("record selector `" <> renderRName (recordSelectorName selectorInfo) <> "` has non-function type " <> renderMonoType other))

recordConstructorsForHead :: RName -> Map.Map RName DataConstructorInfo -> [(RName, DataConstructorInfo)]
recordConstructorsForHead targetHead constructors =
  [ (name, info)
  | (name, info) <- Map.toList constructors
  , recordTypeHead (dataConstructorResult info) == Just targetHead
  ]

recordConstructorHasLabels :: Set.Set RName -> DataConstructorInfo -> Bool
recordConstructorHasLabels labels info =
  labels `Set.isSubsetOf` Map.keysSet (recordLabelIndexMapPure info)

recordUpdateAlternative :: MonoType -> Map.Map RName TypedExpr -> RName -> DataConstructorInfo -> InferM TypedAlt
recordUpdateAlternative scrutineeTy typedFields name info = do
  (fieldTypes, resultTy, typeArguments) <- instantiateConstructorFields info
  unify resultTy scrutineeTy
  fieldTypes' <- traverse applyCurrent fieldTypes
  resultTy' <- applyCurrent resultTy
  typeArguments' <- traverse applyCurrent typeArguments
  binders <- traverse (uncurry recordUpdateFieldBinder) (zip [0 :: Int ..] fieldTypes')
  body <- recordUpdateConstructorBodyFromFields typedFields name info fieldTypes' resultTy' typeArguments' (Just binders)
  pure (TypedAlt (ConstructorAlt name) binders body)

recordUpdateConstructorBody :: MonoType -> Map.Map RName TypedExpr -> RName -> DataConstructorInfo -> InferM TypedExpr
recordUpdateConstructorBody scrutineeTy typedFields name info = do
  (fieldTypes, resultTy, typeArguments) <- instantiateConstructorFields info
  unify resultTy scrutineeTy
  fieldTypes' <- traverse applyCurrent fieldTypes
  resultTy' <- applyCurrent resultTy
  typeArguments' <- traverse applyCurrent typeArguments
  recordUpdateConstructorBodyFromFields typedFields name info fieldTypes' resultTy' typeArguments' Nothing

recordUpdateConstructorBodyFromFields ::
  Map.Map RName TypedExpr ->
  RName ->
  DataConstructorInfo ->
  [MonoType] ->
  MonoType ->
  [MonoType] ->
  Maybe [TypedBinder] ->
  InferM TypedExpr
recordUpdateConstructorBodyFromFields typedFields name info fieldTypes resultTy typeArguments maybeBinders = do
  fieldArgs <- traverse recordUpdateFieldArg (zip3 [0 :: Int ..] fieldTypes (dataConstructorFieldLabels info))
  constructorTy <- applyCurrent (foldr TyFun resultTy fieldTypes)
  typedConstructor <- typedConstructorExpr name info typeArguments constructorTy
  foldM applyConstructorArgument typedConstructor fieldArgs
 where
  recordUpdateFieldArg (index, fieldTy, maybeLabel) =
    case maybeLabel >>= (`Map.lookup` typedFields) of
      Just typedField -> do
        unify fieldTy (typedExprType typedField)
        pure typedField
      Nothing ->
        case maybeBinders >>= listAt index of
          Just binder ->
            pure (typedLocalVar binder)
          Nothing ->
            typedLocalVar <$> recordUpdateFieldBinder index fieldTy

  applyConstructorArgument function argument = do
    freshResultTy <- freshMeta
    unify (typedExprType function) (TyFun (typedExprType argument) freshResultTy)
    resultTy' <- applyCurrent freshResultTy
    pure (TApp function argument resultTy')

listAt :: Int -> [a] -> Maybe a
listAt index values
  | index < 0 = Nothing
  | otherwise =
      case drop index values of
        value : _ -> Just value
        [] -> Nothing

recordUpdateFieldBinder :: Int -> MonoType -> InferM TypedBinder
recordUpdateFieldBinder index =
  freshTermBinder ("$record_update_field" <> renderInt index)

recordTypeHead :: MonoType -> Maybe RName
recordTypeHead = \case
  TyCon name -> Just name
  TyApp fn _ -> recordTypeHead fn
  _ -> Nothing

ensureNoDuplicateRecordUpdateLabels :: [RName] -> InferM ()
ensureNoDuplicateRecordUpdateLabels =
  go Set.empty
 where
  go _ [] =
    pure ()
  go seen (label : rest)
    | label `Set.member` seen =
        throwTypecheck (UnsupportedCore0 ("record update repeats field `" <> renderRName label <> "`"))
    | otherwise =
        go (Set.insert label seen) rest

inferConstructor :: RName -> InferM TypedExpr
inferConstructor name
  | nameOcc name == "True" =
      pure (TCon trueDataConName (Scheme [] [] boolMonoType) [] boolMonoType)
  | nameOcc name == "False" =
      pure (TCon falseDataConName (Scheme [] [] boolMonoType) [] boolMonoType)
  | otherwise = do
      constructors <- dataConstructors <$> get
      case Map.lookup name constructors of
        Nothing ->
          case preludeConstructorInfo name of
            Nothing ->
              throwTypecheck (UnsupportedCore0 ("constructor `" <> renderRName name <> "`"))
            Just (coreName, info) -> do
              (instantiatedTy, typeArguments) <- instantiate (dataConstructorScheme info)
              typedConstructorExpr coreName info typeArguments instantiatedTy
        Just info -> do
          (instantiatedTy, typeArguments) <- instantiate (dataConstructorScheme info)
          typedConstructorExpr name info typeArguments instantiatedTy

typedConstructorExpr :: RName -> DataConstructorInfo -> [MonoType] -> MonoType -> InferM TypedExpr
typedConstructorExpr name info typeArguments instantiatedTy =
  case dataConstructorRepresentation info of
    CoreDataConstructor ->
      pure (TCon name (dataConstructorScheme info) typeArguments instantiatedTy)
    CoreNewtypeConstructor ->
      case instantiatedTy of
        TyFun fieldTy _ -> do
          binder <- freshTermBinder ("$newtype_" <> nameOcc name) fieldTy
          pure (TNewtypeCon name (dataConstructorScheme info) typeArguments instantiatedTy binder)
        _ ->
          throwTypecheck (UnsupportedCore0 ("newtype constructor `" <> renderRName name <> "` has non-function type"))

inferPreludeValue :: RName -> InferM TypedExpr
inferPreludeValue name =
  case preludeValueScheme name of
    Nothing ->
      throwTypecheck (UnknownCore0Variable name)
    Just scheme -> do
      sourceRange <- currentTypecheckSpan
      let spannedScheme = withSchemeConstraintSpan sourceRange scheme
      (instantiatedTy, typeArguments) <- instantiate spannedScheme
      pure (TVar (preludeValueCoreName name) spannedScheme typeArguments instantiatedTy)

inferIntegerLiteral :: Integer -> InferM TypedExpr
inferIntegerLiteral value = do
  resultTy <- freshMeta
  method <- builtinClassMethod "Num" "fromInteger"
  classVariable <- classMethodSingleVariable "fromInteger" method
  sourceRange <- currentTypecheckSpan
  let methodScheme = withSchemeConstraintSpan sourceRange (classMethodScheme method)
  let methodTy =
        replaceTypeVars
          (Map.singleton classVariable resultTy)
          (schemeBody methodScheme)
      methodExpr = TVar (classMethodName method) methodScheme [resultTy] methodTy
      literalExpr = TLit (LInt value) intMonoType
  case methodTy of
    TyFun _ result ->
      pure (TApp methodExpr literalExpr result)
    other ->
      throwTypecheck
        ( UnsupportedCore0
            ( "built-in method `fromInteger` has unexpected type "
                <> renderMonoType other
            )
        )

inferFractionalLiteral :: Rational -> InferM TypedExpr
inferFractionalLiteral value = do
  resultTy <- freshMeta
  method <- builtinClassMethod "Fractional" "fromRational"
  classVariable <- classMethodSingleVariable "fromRational" method
  sourceRange <- currentTypecheckSpan
  let methodScheme = withSchemeConstraintSpan sourceRange (classMethodScheme method)
      methodTy =
        replaceTypeVars
          (Map.singleton classVariable resultTy)
          (schemeBody methodScheme)
      methodExpr = TVar (classMethodName method) methodScheme [resultTy] methodTy
      literalExpr = rationalLiteralTypedExpr (Ratio.numerator value) (Ratio.denominator value)
  case methodTy of
    TyFun _ result ->
      pure (TApp methodExpr literalExpr result)
    other ->
      throwTypecheck
        ( UnsupportedCore0
            ( "built-in method `fromRational` has unexpected type "
                <> renderMonoType other
            )
        )

rationalLiteralTypedExpr :: Integer -> Integer -> TypedExpr
rationalLiteralTypedExpr numeratorValue denominatorValue =
  TApp (TApp conExpr numeratorExpr (TyFun intMonoType rationalMonoType)) denominatorExpr rationalMonoType
 where
  conScheme = dataConstructorScheme (builtinDataConstructors Map.! ratioDataConName)
  conExpr =
    TCon
      ratioDataConName
      conScheme
      [intMonoType]
      (TyFun intMonoType (TyFun intMonoType rationalMonoType))
  numeratorExpr = TLit (LInt numeratorValue) intMonoType
  denominatorExpr = TLit (LInt denominatorValue) intMonoType

preludeValueCoreName :: RName -> RName
preludeValueCoreName name =
  case builtinMethodInfoByOccurrence (nameOcc name) of
    Just method -> classMethodName method
    Nothing -> name

preludeConstructorInfo :: RName -> Maybe (RName, DataConstructorInfo)
preludeConstructorInfo name
  | not (nameExternal name) && name `Map.notMember` builtinDataConstructors = Nothing
  | otherwise =
      case nameOcc name of
        "[]" -> lookupBuiltin listNilDataConName
        ":" -> lookupBuiltin listConsDataConName
        "()" -> lookupBuiltin unitDataConName
        "Nothing" -> lookupBuiltin maybeNothingDataConName
        "Just" -> lookupBuiltin maybeJustDataConName
        "Left" -> lookupBuiltin eitherLeftDataConName
        "Right" -> lookupBuiltin eitherRightDataConName
        "LT" -> lookupBuiltin orderingLTDataConName
        "EQ" -> lookupBuiltin orderingEQDataConName
        "GT" -> lookupBuiltin orderingGTDataConName
        "ReadMode" -> lookupBuiltin ioModeReadDataConName
        "WriteMode" -> lookupBuiltin ioModeWriteDataConName
        "AppendMode" -> lookupBuiltin ioModeAppendDataConName
        "ReadWriteMode" -> lookupBuiltin ioModeReadWriteDataConName
        "NoBuffering" -> lookupBuiltin bufferModeNoDataConName
        "LineBuffering" -> lookupBuiltin bufferModeLineDataConName
        "BlockBuffering" -> lookupBuiltin bufferModeBlockDataConName
        "ExitSuccess" -> lookupBuiltin exitSuccessDataConName
        "ExitFailure" -> lookupBuiltin exitFailureDataConName
        "AbsoluteSeek" -> lookupBuiltin seekModeAbsoluteDataConName
        "RelativeSeek" -> lookupBuiltin seekModeRelativeDataConName
        "SeekFromEnd" -> lookupBuiltin seekModeFromEndDataConName
        "Errno" -> lookupBuiltin errnoDataConName
        _ -> Nothing
 where
  lookupBuiltin coreName = (coreName,) <$> Map.lookup coreName builtinDataConstructors

preludeValueScheme :: RName -> Maybe Scheme
preludeValueScheme name
  | not (nameExternal name) = Nothing
  | otherwise =
      case builtinMethodInfoByOccurrence (nameOcc name) of
        Just method -> Just (classMethodScheme method)
        Nothing ->
          case nameOcc name of
            "id" -> Just (Scheme [a] [] (TyFun aTy aTy))
            "const" -> Just (Scheme [a, b] [] (TyFun aTy (TyFun bTy aTy)))
            "not" -> Just (Scheme [] [] (TyFun boolMonoType boolMonoType))
            "otherwise" -> Just (Scheme [] [] boolMonoType)
            "$" -> Just (Scheme [a, b] [] (TyFun (TyFun aTy bTy) (TyFun aTy bTy)))
            "." -> Just (Scheme [a, b, c] [] (TyFun (TyFun bTy cTy) (TyFun (TyFun aTy bTy) (TyFun aTy cTy))))
            "flip" -> Just (Scheme [a, b, c] [] (TyFun (TyFun aTy (TyFun bTy cTy)) (TyFun bTy (TyFun aTy cTy))))
            "map" -> Just (Scheme [a, b] [] (TyFun (TyFun aTy bTy) (TyFun listA listB)))
            "foldr" ->
              Just
                ( Scheme
                    [a, b]
                    []
                    (TyFun (TyFun aTy (TyFun bTy bTy)) (TyFun bTy (TyFun listA bTy)))
                )
            "foldl" ->
              Just
                ( Scheme
                    [a, b]
                    []
                    (TyFun (TyFun bTy (TyFun aTy bTy)) (TyFun bTy (TyFun listA bTy)))
                )
            "head" -> Just (Scheme [a] [] (TyFun listA aTy))
            "tail" -> Just (Scheme [a] [] (TyFun listA listA))
            "null" -> Just (Scheme [a] [] (TyFun listA boolMonoType))
            "fst" -> Just (Scheme [a, b] [] (TyFun tupleAB aTy))
            "snd" -> Just (Scheme [a, b] [] (TyFun tupleAB bTy))
            "length" -> Just (Scheme [a] [] (TyFun listA intMonoType))
            "filter" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun listA listA)))
            "reverse" -> Just (Scheme [a] [] (TyFun listA listA))
            "++" -> Just (Scheme [a] [] (TyFun listA (TyFun listA listA)))
            "shows" -> Just (Scheme [a] [singleClassConstraint builtinShowClassName aTy] (TyFun aTy (TyFun stringMonoType stringMonoType)))
            "reads" -> Just (Scheme [a] [singleClassConstraint builtinReadClassName aTy] readSA)
            "read" -> Just (Scheme [a] [singleClassConstraint builtinReadClassName aTy] (TyFun stringMonoType aTy))
            "lex" -> Just (Scheme [] [] (TyFun stringMonoType (TyList (TyTuple [stringMonoType, stringMonoType]))))
            "readParen" -> Just (Scheme [a] [] (TyFun boolMonoType (TyFun readSA readSA)))
            "%" -> Just (Scheme [] [] (TyFun intMonoType (TyFun intMonoType rationalMonoType)))
            "numerator" -> Just (Scheme [] [] (TyFun rationalMonoType intMonoType))
            "denominator" -> Just (Scheme [] [] (TyFun rationalMonoType intMonoType))
            "approxRational" -> Just (Scheme [] [] (TyFun rationalMonoType (TyFun rationalMonoType rationalMonoType)))
            "$read_append" -> Just (Scheme [a] [] (TyFun listA (TyFun listA listA)))
            "$read_exact" -> Just (Scheme [] [] (TyFun stringMonoType (TyFun stringMonoType (TyList (TyTuple [unitMonoType, stringMonoType])))))
            "$read_default_list" -> Just (Scheme [a] [] (TyFun readSA readListSA))
            "$read_paren" -> Just (Scheme [a] [] (TyFun boolMonoType (TyFun readSA readSA)))
            "$read_lex" -> Just (Scheme [] [] (TyFun stringMonoType (TyList (TyTuple [stringMonoType, stringMonoType]))))
            "$read_int" -> Just (Scheme [] [] intReadS)
            "$read_bool" -> Just (Scheme [] [] boolReadS)
            "$read_char" -> Just (Scheme [] [] charReadS)
            "$read_string" -> Just (Scheme [] [] stringReadS)
            "mapM" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (TyFun aTy mB) (TyFun listA (mList bTy))))
            "mapM_" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (TyFun aTy mB) (TyFun listA mUnit)))
            "forM" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun listA (TyFun (TyFun aTy mB) (mList bTy))))
            "forM_" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun listA (TyFun (TyFun aTy mB) mUnit)))
            "sequence" -> Just (Scheme [m, a] [monadConstraint] (TyFun (TyList mA) (mList aTy)))
            "sequence_" -> Just (Scheme [m, a] [monadConstraint] (TyFun (TyList mA) mUnit))
            "=<<" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (TyFun aTy mB) (TyFun mA mB)))
            ">=>" -> Just (Scheme [m, a, b, c] [monadConstraint] (TyFun (TyFun aTy mB) (TyFun (TyFun bTy mC) (TyFun aTy mC))))
            "<=<" -> Just (Scheme [m, a, b, c] [monadConstraint] (TyFun (TyFun bTy mC) (TyFun (TyFun aTy mB) (TyFun aTy mC))))
            "forever" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun mA mB))
            "void" -> Just (Scheme [f, a] [singleClassConstraint builtinFunctorClassName fTy] (TyFun fA fUnit))
            "join" -> Just (Scheme [m, a] [monadConstraint] (TyFun (mOf mA) mA))
            "msum" -> Just (Scheme [m, a] [monadPlusConstraint] (TyFun (TyList mA) mA))
            "filterM" -> Just (Scheme [m, a] [monadConstraint] (TyFun (TyFun aTy mBool) (TyFun listA (mList aTy))))
            "mapAndUnzipM" -> Just (Scheme [m, a, b, c] [monadConstraint] (TyFun (TyFun aTy (mOf tupleBC)) (TyFun listA (mOf (TyTuple [listB, listC])))))
            "zipWithM" -> Just (Scheme [m, a, b, c] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy mC)) (TyFun listA (TyFun listB (mList cTy)))))
            "zipWithM_" -> Just (Scheme [m, a, b, c] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy mC)) (TyFun listA (TyFun listB mUnit))))
            "foldM" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy mA)) (TyFun aTy (TyFun listB mA))))
            "foldM_" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy mA)) (TyFun aTy (TyFun listB mUnit))))
            "replicateM" -> Just (Scheme [m, a] [monadConstraint] (TyFun intMonoType (TyFun mA (mList aTy))))
            "replicateM_" -> Just (Scheme [m, a] [monadConstraint] (TyFun intMonoType (TyFun mA mUnit)))
            "guard" -> Just (Scheme [m] [monadPlusConstraint] (TyFun boolMonoType mUnit))
            "when" -> Just (Scheme [m] [monadConstraint] (TyFun boolMonoType (TyFun mUnit mUnit)))
            "unless" -> Just (Scheme [m] [monadConstraint] (TyFun boolMonoType (TyFun mUnit mUnit)))
            "liftM" -> Just (Scheme [m, a, r] [monadConstraint] (TyFun (TyFun aTy rTy) (TyFun mA mR)))
            "liftM2" -> Just (Scheme [m, a, b, r] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy rTy)) (TyFun mA (TyFun mB mR))))
            "liftM3" -> Just (Scheme [m, a, b, c, r] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy (TyFun cTy rTy))) (TyFun mA (TyFun mB (TyFun mC mR)))))
            "liftM4" -> Just (Scheme [m, a, b, c, d, r] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy (TyFun cTy (TyFun dTy rTy)))) (TyFun mA (TyFun mB (TyFun mC (TyFun mD mR))))))
            "liftM5" -> Just (Scheme [m, a, b, c, d, e, r] [monadConstraint] (TyFun (TyFun aTy (TyFun bTy (TyFun cTy (TyFun dTy (TyFun eTy rTy))))) (TyFun mA (TyFun mB (TyFun mC (TyFun mD (TyFun mE mR)))))))
            "ap" -> Just (Scheme [m, a, b] [monadConstraint] (TyFun (mOf (TyFun aTy bTy)) (TyFun mA mB)))
            "fixIO" -> Just (Scheme [a] [] (TyFun (TyFun aTy (ioMonoType aTy)) (ioMonoType aTy)))
            "stdin" -> Just (Scheme [] [] handleMonoType)
            "stdout" -> Just (Scheme [] [] handleMonoType)
            "stderr" -> Just (Scheme [] [] handleMonoType)
            "withFile" -> Just (Scheme [r] [] (TyFun filePathMonoType (TyFun ioModeMonoType (TyFun (TyFun handleMonoType (ioMonoType rTy)) (ioMonoType rTy)))))
            "openFile" -> Just (Scheme [] [] (TyFun filePathMonoType (TyFun ioModeMonoType (ioMonoType handleMonoType))))
            "hClose" -> Just (Scheme [] [] (TyFun handleMonoType ioUnit))
            "readFile" -> Just (Scheme [] [] (TyFun filePathMonoType (ioMonoType stringMonoType)))
            "writeFile" -> Just (Scheme [] [] (TyFun filePathMonoType (TyFun stringMonoType ioUnit)))
            "appendFile" -> Just (Scheme [] [] (TyFun filePathMonoType (TyFun stringMonoType ioUnit)))
            "hFileSize" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType intMonoType)))
            "hSetFileSize" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun intMonoType ioUnit)))
            "hIsEOF" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "isEOF" -> Just (Scheme [] [] (ioMonoType boolMonoType))
            "hSetBuffering" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun bufferModeMonoType ioUnit)))
            "hGetBuffering" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType bufferModeMonoType)))
            "hFlush" -> Just (Scheme [] [] (TyFun handleMonoType ioUnit))
            "hGetPosn" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType handlePosnMonoType)))
            "hSetPosn" -> Just (Scheme [] [] (TyFun handlePosnMonoType ioUnit))
            "hSeek" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun seekModeMonoType (TyFun intMonoType ioUnit))))
            "hTell" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType intMonoType)))
            "hIsOpen" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hIsClosed" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hIsReadable" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hIsWritable" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hIsSeekable" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hIsTerminalDevice" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hSetEcho" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun boolMonoType ioUnit)))
            "hGetEcho" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hShow" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType stringMonoType)))
            "hWaitForInput" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun intMonoType (ioMonoType boolMonoType))))
            "hReady" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType boolMonoType)))
            "hGetChar" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType charMonoType)))
            "hGetLine" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType stringMonoType)))
            "hLookAhead" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType charMonoType)))
            "hGetContents" -> Just (Scheme [] [] (TyFun handleMonoType (ioMonoType stringMonoType)))
            "hPutChar" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun charMonoType ioUnit)))
            "hPutStr" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun stringMonoType ioUnit)))
            "hPutStrLn" -> Just (Scheme [] [] (TyFun handleMonoType (TyFun stringMonoType ioUnit)))
            "hPrint" -> Just (Scheme [a] [singleClassConstraint builtinShowClassName aTy] (TyFun handleMonoType (TyFun aTy ioUnit)))
            "interact" -> Just (Scheme [] [] (TyFun (TyFun stringMonoType stringMonoType) ioUnit))
            "putChar" -> Just (Scheme [] [] (TyFun charMonoType ioUnit))
            "putStr" -> Just (Scheme [] [] (TyFun stringMonoType ioUnit))
            "putStrLn" -> Just (Scheme [] [] (TyFun stringMonoType ioUnit))
            "getChar" -> Just (Scheme [] [] (ioMonoType charMonoType))
            "getLine" -> Just (Scheme [] [] (ioMonoType stringMonoType))
            "getContents" -> Just (Scheme [] [] (ioMonoType stringMonoType))
            "getArgs" -> Just (Scheme [] [] (ioMonoType (TyList stringMonoType)))
            "getProgName" -> Just (Scheme [] [] (ioMonoType stringMonoType))
            "getEnv" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType stringMonoType)))
            "exitWith" -> Just (Scheme [a] [] (TyFun exitCodeMonoType (ioMonoType aTy)))
            "exitFailure" -> Just (Scheme [a] [] (ioMonoType aTy))
            "exitSuccess" -> Just (Scheme [a] [] (ioMonoType aTy))
            "print" -> Just (Scheme [a] [singleClassConstraint builtinShowClassName aTy] (TyFun aTy ioUnit))
            "readIO" -> Just (Scheme [a] [singleClassConstraint builtinReadClassName aTy] (TyFun stringMonoType (ioMonoType aTy)))
            "readLn" -> Just (Scheme [a] [singleClassConstraint builtinReadClassName aTy] (ioMonoType aTy))
            "userError" -> Just (Scheme [] [] (TyFun stringMonoType ioErrorMonoType))
            "mkIOError" -> Just (Scheme [] [] (TyFun ioErrorTypeMonoType (TyFun stringMonoType (TyFun maybeHandle (TyFun maybeFilePath ioErrorMonoType)))))
            "annotateIOError" -> Just (Scheme [] [] (TyFun ioErrorMonoType (TyFun stringMonoType (TyFun maybeHandle (TyFun maybeFilePath ioErrorMonoType)))))
            "isAlreadyExistsError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isDoesNotExistError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isAlreadyInUseError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isFullError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isEOFError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isIllegalOperation" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isPermissionError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "isUserError" -> Just (Scheme [] [] ioErrorPredicateTy)
            "ioeGetErrorString" -> Just (Scheme [] [] (TyFun ioErrorMonoType stringMonoType))
            "ioeGetHandle" -> Just (Scheme [] [] (TyFun ioErrorMonoType maybeHandle))
            "ioeGetFileName" -> Just (Scheme [] [] (TyFun ioErrorMonoType maybeFilePath))
            "alreadyExistsErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "doesNotExistErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "alreadyInUseErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "fullErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "eofErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "illegalOperationErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "permissionErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "userErrorType" -> Just (Scheme [] [] ioErrorTypeMonoType)
            "ioError" -> Just (Scheme [a] [] (TyFun ioErrorMonoType (ioMonoType aTy)))
            "catch" -> Just (Scheme [a] [] (TyFun (ioMonoType aTy) (TyFun (TyFun ioErrorMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "try" -> Just (Scheme [a] [] (TyFun (ioMonoType aTy) (ioMonoType (TyApp (TyApp (TyCon eitherTyConName) ioErrorMonoType) aTy))))
            "nullPtr" -> Just (Scheme [a] [] ptrA)
            "castPtr" -> Just (Scheme [a, b] [] (TyFun ptrA ptrB))
            "nullFunPtr" -> Just (Scheme [a] [] funPtrA)
            "castFunPtr" -> Just (Scheme [a, b] [] (TyFun funPtrA funPtrB))
            "castFunPtrToPtr" -> Just (Scheme [a, b] [] (TyFun funPtrA ptrB))
            "castPtrToFunPtr" -> Just (Scheme [a, b] [] (TyFun ptrA funPtrB))
            "freeHaskellFunPtr" -> Just (Scheme [a] [] (TyFun funPtrA ioUnit))
            "newStablePtr" -> Just (Scheme [a] [] (TyFun aTy (ioMonoType stablePtrA)))
            "deRefStablePtr" -> Just (Scheme [a] [] (TyFun stablePtrA (ioMonoType aTy)))
            "freeStablePtr" -> Just (Scheme [a] [] (TyFun stablePtrA ioUnit))
            "castStablePtrToPtr" -> Just (Scheme [a] [] (TyFun stablePtrA ptrUnit))
            "castPtrToStablePtr" -> Just (Scheme [a] [] (TyFun ptrUnit stablePtrA))
            "newForeignPtr" -> Just (Scheme [a] [] (TyFun finalizerPtrA (TyFun ptrA (ioMonoType foreignPtrA))))
            "newForeignPtr_" -> Just (Scheme [a] [] (TyFun ptrA (ioMonoType foreignPtrA)))
            "addForeignPtrFinalizer" -> Just (Scheme [a] [] (TyFun finalizerPtrA (TyFun foreignPtrA ioUnit)))
            "finalizeForeignPtr" -> Just (Scheme [a] [] (TyFun foreignPtrA ioUnit))
            "unsafeForeignPtrToPtr" -> Just (Scheme [a] [] (TyFun foreignPtrA ptrA))
            "withForeignPtr" -> Just (Scheme [a, b] [] (TyFun foreignPtrA (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy))))
            "touchForeignPtr" -> Just (Scheme [a] [] (TyFun foreignPtrA ioUnit))
            "castForeignPtr" -> Just (Scheme [a, b] [] (TyFun foreignPtrA foreignPtrB))
            "throwIf" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun (TyFun aTy stringMonoType) (TyFun (ioMonoType aTy) (ioMonoType aTy)))))
            "throwIf_" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun (TyFun aTy stringMonoType) (TyFun (ioMonoType aTy) ioUnit))))
            "throwIfNull" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (ioMonoType ptrA) (ioMonoType ptrA))))
            "maybeNew" -> Just (Scheme [a] [] (TyFun (TyFun aTy (ioMonoType ptrA)) (TyFun maybeA (ioMonoType ptrA))))
            "maybeWith" -> Just (Scheme [a, b, c] [] (TyFun (TyFun aTy (TyFun (TyFun ptrB (ioMonoType cTy)) (ioMonoType cTy))) (TyFun maybeA (TyFun (TyFun ptrB (ioMonoType cTy)) (ioMonoType cTy)))))
            "maybePeek" -> Just (Scheme [a, b] [] (TyFun (TyFun ptrA (ioMonoType bTy)) (TyFun ptrA (ioMonoType maybeB))))
            "plusPtr" -> Just (Scheme [a, b] [] (TyFun ptrA (TyFun intMonoType ptrB)))
            "minusPtr" -> Just (Scheme [a, b] [] (TyFun ptrA (TyFun ptrB intMonoType)))
            "alignPtr" -> Just (Scheme [a] [] (TyFun ptrA (TyFun intMonoType ptrA)))
            "malloc" -> Just (Scheme [a] [storableA] (ioMonoType ptrA))
            "mallocBytes" -> Just (Scheme [a] [] (TyFun intMonoType (ioMonoType ptrA)))
            "alloca" -> Just (Scheme [a, b] [storableA] (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy)))
            "allocaBytes" -> Just (Scheme [a, b] [] (TyFun intMonoType (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy))))
            "realloc" -> Just (Scheme [a, b] [storableB] (TyFun ptrA (ioMonoType ptrB)))
            "reallocBytes" -> Just (Scheme [a] [] (TyFun ptrA (TyFun intMonoType (ioMonoType ptrA))))
            "free" -> Just (Scheme [a] [] (TyFun ptrA ioUnit))
            "finalizerFree" -> Just (Scheme [a] [] finalizerPtrA)
            "advancePtr" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun intMonoType ptrA)))
            "mallocArray" -> Just (Scheme [a] [storableA] (TyFun intMonoType (ioMonoType ptrA)))
            "mallocArray0" -> Just (Scheme [a] [storableA] (TyFun intMonoType (ioMonoType ptrA)))
            "allocaArray" -> Just (Scheme [a, b] [storableA] (TyFun intMonoType (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy))))
            "allocaArray0" -> Just (Scheme [a, b] [storableA] (TyFun intMonoType (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy))))
            "reallocArray" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun intMonoType (ioMonoType ptrA))))
            "reallocArray0" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun intMonoType (ioMonoType ptrA))))
            "peekArray" -> Just (Scheme [a] [storableA] (TyFun intMonoType (TyFun ptrA (ioMonoType listA))))
            "peekArray0" -> Just (Scheme [a] [storableA, eqA] (TyFun aTy (TyFun ptrA (ioMonoType listA))))
            "pokeArray" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun listA ioUnit)))
            "pokeArray0" -> Just (Scheme [a] [storableA] (TyFun aTy (TyFun ptrA (TyFun listA ioUnit))))
            "newArray" -> Just (Scheme [a] [storableA] (TyFun listA (ioMonoType ptrA)))
            "newArray0" -> Just (Scheme [a] [storableA] (TyFun aTy (TyFun listA (ioMonoType ptrA))))
            "withArray" -> Just (Scheme [a, b] [storableA] (TyFun listA (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy))))
            "withArray0" -> Just (Scheme [a, b] [storableA] (TyFun aTy (TyFun listA (TyFun (TyFun ptrA (ioMonoType bTy)) (ioMonoType bTy)))))
            "withArrayLen" -> Just (Scheme [a, b] [storableA] (TyFun listA (TyFun (TyFun intMonoType (TyFun ptrA (ioMonoType bTy))) (ioMonoType bTy))))
            "withArrayLen0" -> Just (Scheme [a, b] [storableA] (TyFun aTy (TyFun listA (TyFun (TyFun intMonoType (TyFun ptrA (ioMonoType bTy))) (ioMonoType bTy)))))
            "copyArray" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun ptrA (TyFun intMonoType ioUnit))))
            "moveArray" -> Just (Scheme [a] [storableA] (TyFun ptrA (TyFun ptrA (TyFun intMonoType ioUnit))))
            "lengthArray0" -> Just (Scheme [a] [storableA, eqA] (TyFun aTy (TyFun ptrA (ioMonoType intMonoType))))
            "copyBytes" -> Just (Scheme [a, b] [] (TyFun ptrA (TyFun ptrB (TyFun intMonoType ioUnit))))
            "moveBytes" -> Just (Scheme [a, b] [] (TyFun ptrA (TyFun ptrB (TyFun intMonoType ioUnit))))
            "peekCString" -> Just (Scheme [] [] (TyFun cStringMonoType (ioMonoType stringMonoType)))
            "peekCStringLen" -> Just (Scheme [] [] (TyFun cStringLenMonoType (ioMonoType stringMonoType)))
            "newCString" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cStringMonoType)))
            "newCStringLen" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cStringLenMonoType)))
            "withCString" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cStringMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "withCStringLen" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cStringLenMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "peekCAString" -> Just (Scheme [] [] (TyFun cStringMonoType (ioMonoType stringMonoType)))
            "peekCAStringLen" -> Just (Scheme [] [] (TyFun cStringLenMonoType (ioMonoType stringMonoType)))
            "newCAString" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cStringMonoType)))
            "newCAStringLen" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cStringLenMonoType)))
            "withCAString" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cStringMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "withCAStringLen" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cStringLenMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "peekCWString" -> Just (Scheme [] [] (TyFun cWStringMonoType (ioMonoType stringMonoType)))
            "peekCWStringLen" -> Just (Scheme [] [] (TyFun cWStringLenMonoType (ioMonoType stringMonoType)))
            "newCWString" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cWStringMonoType)))
            "newCWStringLen" -> Just (Scheme [] [] (TyFun stringMonoType (ioMonoType cWStringLenMonoType)))
            "withCWString" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cWStringMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "withCWStringLen" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (TyFun cWStringLenMonoType (ioMonoType aTy)) (ioMonoType aTy))))
            "charIsRepresentable" -> Just (Scheme [] [] (TyFun charMonoType (ioMonoType boolMonoType)))
            "castCharToCChar" -> Just (Scheme [] [] (TyFun charMonoType cCharMonoType))
            "castCCharToChar" -> Just (Scheme [] [] (TyFun cCharMonoType charMonoType))
            "castCharToCUChar" -> Just (Scheme [] [] (TyFun charMonoType cUCharMonoType))
            "castCUCharToChar" -> Just (Scheme [] [] (TyFun cUCharMonoType charMonoType))
            "castCharToCSChar" -> Just (Scheme [] [] (TyFun charMonoType cCharMonoType))
            "castCSCharToChar" -> Just (Scheme [] [] (TyFun cCharMonoType charMonoType))
            "isValidErrno" -> Just (Scheme [] [] (TyFun errnoMonoType boolMonoType))
            "getErrno" -> Just (Scheme [] [] (ioMonoType errnoMonoType))
            "resetErrno" -> Just (Scheme [] [] ioUnit)
            "errnoToIOError" -> Just (Scheme [] [] (TyFun stringMonoType (TyFun errnoMonoType (TyFun maybeHandle (TyFun maybeFilePath ioErrorMonoType)))))
            "throwErrno" -> Just (Scheme [a] [] (TyFun stringMonoType (ioMonoType aTy)))
            "throwErrnoIf" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy)))))
            "throwErrnoIf_" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit))))
            "throwErrnoIfRetry" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy)))))
            "throwErrnoIfRetry_" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit))))
            "throwErrnoIfMinus1" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy))))
            "throwErrnoIfMinus1_" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit)))
            "throwErrnoIfMinus1Retry" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy))))
            "throwErrnoIfMinus1Retry_" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit)))
            "throwErrnoIfNull" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (ioMonoType ptrA) (ioMonoType ptrA))))
            "throwErrnoIfNullRetry" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun (ioMonoType ptrA) (ioMonoType ptrA))))
            "throwErrnoIfRetryMayBlock" -> Just (Scheme [a, b] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) (TyFun (ioMonoType bTy) (ioMonoType aTy))))))
            "throwErrnoIfRetryMayBlock_" -> Just (Scheme [a, b] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun (ioMonoType aTy) (TyFun (ioMonoType bTy) ioUnit)))))
            "throwErrnoIfMinus1RetryMayBlock" -> Just (Scheme [a, b] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) (TyFun (ioMonoType bTy) (ioMonoType aTy)))))
            "throwErrnoIfMinus1RetryMayBlock_" -> Just (Scheme [a, b] [numA, eqA] (TyFun stringMonoType (TyFun (ioMonoType aTy) (TyFun (ioMonoType bTy) ioUnit))))
            "throwErrnoIfNullRetryMayBlock" -> Just (Scheme [a, b] [] (TyFun stringMonoType (TyFun (ioMonoType ptrA) (TyFun (ioMonoType bTy) (ioMonoType ptrA)))))
            "throwErrnoPath" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun stringMonoType (ioMonoType aTy))))
            "throwErrnoPathIf" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy))))))
            "throwErrnoPathIf_" -> Just (Scheme [a] [] (TyFun (TyFun aTy boolMonoType) (TyFun stringMonoType (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit)))))
            "throwErrnoPathIfNull" -> Just (Scheme [a] [] (TyFun stringMonoType (TyFun stringMonoType (TyFun (ioMonoType ptrA) (ioMonoType ptrA)))))
            "throwErrnoPathIfMinus1" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun stringMonoType (TyFun (ioMonoType aTy) (ioMonoType aTy)))))
            "throwErrnoPathIfMinus1_" -> Just (Scheme [a] [numA, eqA] (TyFun stringMonoType (TyFun stringMonoType (TyFun (ioMonoType aTy) ioUnit))))
            occurrence
              | isErrnoConstantOccurrence occurrence -> Just (Scheme [] [] errnoMonoType)
            _ -> Nothing
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  c = preludeTypeVariable "c" (-1203)
  d = preludeTypeVariable "d" (-1204)
  e = preludeTypeVariable "e" (-1205)
  r = preludeTypeVariable "r" (-1206)
  f = preludeTypeVariable "f" (-1207)
  m = preludeTypeVariable "m" (-1208)
  aTy = TyVar a
  bTy = TyVar b
  cTy = TyVar c
  dTy = TyVar d
  eTy = TyVar e
  rTy = TyVar r
  fTy = TyVar f
  mTy = TyVar m
  listA = TyList aTy
  listB = TyList bTy
  listC = TyList cTy
  tupleAB = TyTuple [aTy, bTy]
  tupleBC = TyTuple [bTy, cTy]
  maybeA = TyApp (TyCon maybeTyConName) aTy
  maybeB = TyApp (TyCon maybeTyConName) bTy
  mOf ty = TyApp mTy ty
  mA = mOf aTy
  mB = mOf bTy
  mC = mOf cTy
  mD = mOf dTy
  mE = mOf eTy
  mR = mOf rTy
  mUnit = mOf unitMonoType
  mBool = mOf boolMonoType
  mList ty = mOf (TyList ty)
  fA = TyApp fTy aTy
  fUnit = TyApp fTy unitMonoType
  monadConstraint = singleClassConstraint builtinMonadClassName mTy
  monadPlusConstraint = singleClassConstraint builtinMonadPlusClassName mTy
  storableA = singleClassConstraint builtinStorableClassName aTy
  storableB = singleClassConstraint builtinStorableClassName bTy
  eqA = singleClassConstraint builtinEqClassName aTy
  numA = singleClassConstraint builtinNumClassName aTy
  cCharMonoType = builtinForeignTypeMonoType "CChar"
  cUCharMonoType = builtinForeignTypeMonoType "CUChar"
  cWCharMonoType = builtinForeignTypeMonoType "CWchar"
  cStringMonoType = TyApp (TyCon ptrTyConName) cCharMonoType
  cWStringMonoType = TyApp (TyCon ptrTyConName) cWCharMonoType
  cStringLenMonoType = TyTuple [cStringMonoType, intMonoType]
  cWStringLenMonoType = TyTuple [cWStringMonoType, intMonoType]
  errnoMonoType = builtinForeignTypeMonoType "CInt"
  readSA = TyFun stringMonoType (TyList (TyTuple [aTy, stringMonoType]))
  readListSA = TyFun stringMonoType (TyList (TyTuple [listA, stringMonoType]))
  intReadS = TyFun stringMonoType (TyList (TyTuple [intMonoType, stringMonoType]))
  boolReadS = TyFun stringMonoType (TyList (TyTuple [boolMonoType, stringMonoType]))
  charReadS = TyFun stringMonoType (TyList (TyTuple [charMonoType, stringMonoType]))
  stringReadS = TyFun stringMonoType (TyList (TyTuple [stringMonoType, stringMonoType]))
  ioUnit = ioMonoType unitMonoType
  maybeHandle = TyApp (TyCon maybeTyConName) handleMonoType
  maybeFilePath = TyApp (TyCon maybeTyConName) filePathMonoType
  ioErrorPredicateTy = TyFun ioErrorMonoType boolMonoType
  ptrA = TyApp (TyCon ptrTyConName) aTy
  ptrB = TyApp (TyCon ptrTyConName) bTy
  ptrUnit = TyApp (TyCon ptrTyConName) unitMonoType
  funPtrA = TyApp (TyCon funPtrTyConName) aTy
  funPtrB = TyApp (TyCon funPtrTyConName) bTy
  stablePtrA = TyApp (TyCon stablePtrTyConName) aTy
  foreignPtrA = TyApp (TyCon foreignPtrTyConName) aTy
  foreignPtrB = TyApp (TyCon foreignPtrTyConName) bTy
  finalizerPtrA = TyApp (TyCon funPtrTyConName) (TyFun ptrA ioUnit)

inferInfixApp :: TypeEnv -> RExpr -> RName -> RExpr -> InferM TypedExpr
inferInfixApp env lhs op rhs
  | isBuiltinPrimitiveOperator op =
      inferPrimitive env lhs op rhs
  | otherwise =
      inferExpr env (RApp (RApp (infixOperatorExpr op) lhs) rhs)

isBuiltinPrimitiveOperator :: RName -> Bool
isBuiltinPrimitiveOperator op =
  nameExternal op && nameNamespace op == TermNamespace && nameOcc op `Set.member` builtinPrimitiveOperatorOccurrences

builtinPrimitiveOperatorOccurrences :: Set.Set Text
builtinPrimitiveOperatorOccurrences =
  Set.fromList ["+", "-", "*", "/", "++", "<", "<=", ">", ">=", "==", "/=", ">>=", ">>", "&&", "||"]

infixOperatorExpr :: RName -> RExpr
infixOperatorExpr op
  | nameNamespace op == ConstructorNamespace = RCon op
  | otherwise = RVar op

inferPrimitive :: TypeEnv -> RExpr -> RName -> RExpr -> InferM TypedExpr
inferPrimitive env lhs op rhs =
  case nameOcc op of
    ":" -> inferExpr env (RApp (RApp (RCon op) lhs) rhs)
    "+" -> overloadedBinary "Num" "+"
    "-" -> overloadedBinary "Num" "-"
    "*" -> overloadedBinary "Num" "*"
    "/" -> overloadedBinary "Fractional" "/"
    "++" -> inferExpr env (RApp (RApp (RVar op) lhs) rhs)
    "<" -> overloadedBinary "Ord" "<"
    "<=" -> overloadedBinary "Ord" "<="
    ">" -> overloadedBinary "Ord" ">"
    ">=" -> overloadedBinary "Ord" ">="
    "==" -> overloadedBinary "Eq" "=="
    "/=" -> overloadedBinary "Eq" "/="
    ">>=" -> inferExpr env (RApp (RApp (RVar op) lhs) rhs)
    ">>" -> inferExpr env (RApp (RApp (RVar op) lhs) rhs)
    "&&" -> shortCircuit falseTyped trueDataConName
    "||" -> shortCircuit trueTyped falseDataConName
    _ -> inferExpr env (RApp (RApp (infixOperatorExpr op) lhs) rhs)
 where
  trueTyped = TCon trueDataConName (Scheme [] [] boolMonoType) [] boolMonoType
  falseTyped = TCon falseDataConName (Scheme [] [] boolMonoType) [] boolMonoType

  shortCircuit shortcutValue continueName = do
    typedLhs <- inferExpr env lhs
    unify (typedExprType typedLhs) boolMonoType
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedRhs) boolMonoType
    caseBinder <- freshTermBinder "$boolop" boolMonoType
    let trueAlt
          | continueName == trueDataConName = TypedAlt (ConstructorAlt trueDataConName) [] typedRhs
          | otherwise = TypedAlt (ConstructorAlt trueDataConName) [] shortcutValue
        falseAlt
          | continueName == falseDataConName = TypedAlt (ConstructorAlt falseDataConName) [] typedRhs
          | otherwise = TypedAlt (ConstructorAlt falseDataConName) [] shortcutValue
    pure (TCase typedLhs caseBinder [trueAlt, falseAlt] boolMonoType)

  overloadedBinary classOccurrence methodOccurrence = do
    typedLhs <- inferExpr env lhs
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedLhs) (typedExprType typedRhs)
    argumentTy <- applyCurrent (typedExprType typedLhs)
    method <- builtinClassMethod classOccurrence methodOccurrence
    classVariable <- classMethodSingleVariable methodOccurrence method
    sourceRange <- currentTypecheckSpan
    let methodScheme = withSchemeConstraintSpan sourceRange (classMethodScheme method)
        methodBodyTy = replaceTypeVars (Map.singleton classVariable argumentTy) (schemeBody methodScheme)
        resultTy =
          case methodBodyTy of
            TyFun _ (TyFun _ result) -> result
            other -> other
        methodExpr = TVar (classMethodName method) methodScheme [argumentTy] methodBodyTy
    pure (TApp (TApp methodExpr typedLhs (TyFun argumentTy resultTy)) typedRhs resultTy)

builtinClassMethod :: Text -> Text -> InferM ClassMethodInfo
builtinClassMethod classOccurrence methodOccurrence = do
  info <- builtinClassInfoByOccurrence classOccurrence
  case List.find ((== methodOccurrence) . nameOcc . classMethodName) (classInfoMethods info) of
    Just method -> pure method
    Nothing ->
      throwTypecheck
        ( UnsupportedCore0
            ( "missing built-in method `"
                <> methodOccurrence
                <> "` for class `"
                <> classOccurrence
                <> "`"
            )
        )

classMethodSingleVariable :: Text -> ClassMethodInfo -> InferM RName
classMethodSingleVariable methodOccurrence method =
  case schemeVars (classMethodScheme method) of
    [variable] -> pure variable
    variables ->
      throwTypecheck
        ( UnsupportedCore0
            ( "built-in method `"
                <> methodOccurrence
                <> "` has unexpected type variables "
                <> Text.pack (show variables)
            )
        )

inferCaseAlt :: TypeEnv -> MonoType -> TypedExpr -> MonoType -> RAlt -> InferM (PatternPlan, TypedExpr)
inferCaseAlt env scrutineeTy scrutinee resultTy alt@(RAlt pat rhs whereDecls) =
  withTypecheckSpan (rAltSpan alt) $ do
    plan <- inferPatternPlan env scrutineeTy scrutinee pat
    typedBody <- patternWrapBody plan <$> inferRhs (patternEnv plan) rhs whereDecls
    unify resultTy (typedExprType typedBody)
    pure (plan, typedBody)

inferRuntimeCase :: TypeEnv -> TypedExpr -> MonoType -> MonoType -> [RAlt] -> InferM TypedExpr
inferRuntimeCase env typedScrutinee scrutineeTy resultTy alternatives = do
  caseBinder <- caseBinderFor scrutineeTy alternatives
  let caseScrutinee = TVar (typedBinderName caseBinder) (Scheme [] [] scrutineeTy) [] scrutineeTy
  typedAlternatives <- traverse (inferCaseAlt env scrutineeTy caseScrutinee resultTy) alternatives
  pure
    ( TCase
        typedScrutinee
        caseBinder
        [TypedAlt (patternAltCon plan) (patternAltBinders plan) body | (plan, body) <- typedAlternatives]
        resultTy
    )

caseAltCanElideRuntimeCase :: RAlt -> InferM Bool
caseAltCanElideRuntimeCase (RAlt pat _ _) =
  patternCanElideRuntimeCase pat

patternCanElideRuntimeCase :: RPat -> InferM Bool
patternCanElideRuntimeCase = \case
  RPIrrefutable {} ->
    pure True
  RPParen inner ->
    patternCanElideRuntimeCase inner
  RPAs _ inner ->
    patternCanElideRuntimeCase inner
  RPCon name _ ->
    constructorCanElideRuntimeCase name
  RPRecordCon name _ ->
    constructorCanElideRuntimeCase name
  _ ->
    pure False

constructorCanElideRuntimeCase :: RName -> InferM Bool
constructorCanElideRuntimeCase name = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Just info ->
      pure (dataConstructorRepresentation info == CoreNewtypeConstructor)
    Nothing ->
      case preludeConstructorInfo name of
        Just (_, info) ->
          pure (dataConstructorRepresentation info == CoreNewtypeConstructor)
        Nothing ->
          pure False

data PatternCoverageRow = PatternCoverageRow
  { patternCoverageRowSpan :: Maybe SourceSpan
  , patternCoverageRowPattern :: RPat
  , patternCoverageRowRhs :: RRhs
  }
  deriving stock (Show, Eq, Ord)

data PatternCoverageState = PatternCoverageState
  { patternCoverageCoversAll :: Bool
  , patternCoverageConstructors :: Set.Set RName
  , patternCoverageLiterals :: Set.Set Literal
  }
  deriving stock (Show, Eq, Ord)

emptyPatternCoverageState :: PatternCoverageState
emptyPatternCoverageState =
  PatternCoverageState
    { patternCoverageCoversAll = False
    , patternCoverageConstructors = Set.empty
    , patternCoverageLiterals = Set.empty
    }

warnForPatternCoverage :: PatternExhaustivenessContext -> MonoType -> [PatternCoverageRow] -> InferM ()
warnForPatternCoverage GeneratedPatternExhaustiveness _ _ =
  pure ()
warnForPatternCoverage context scrutineeTy rows = do
  scrutineeTy' <- applyCurrent scrutineeTy
  warnForRedundantPatterns context scrutineeTy' rows
  missing <- missingPatternWitnesses scrutineeTy' rows
  unless (null missing) $
    emitTypecheckWarning (NonExhaustivePatternMatch context missing)

warnForRedundantPatterns :: PatternExhaustivenessContext -> MonoType -> [PatternCoverageRow] -> InferM ()
warnForRedundantPatterns context scrutineeTy =
  go emptyPatternCoverageState
 where
  go _ [] =
    pure ()
  go coverage (row : rest) = do
    redundant <- patternRedundantUnderCoverage scrutineeTy coverage (patternCoverageRowPattern row)
    when redundant $
      withTypecheckSpan (patternCoverageRowSpan row) $
        emitTypecheckWarning (RedundantPatternMatch context)
    rowCoverage <-
      if rhsProvesTotal (patternCoverageRowRhs row)
        then patternTotalCoverage scrutineeTy (patternCoverageRowPattern row)
        else pure emptyPatternCoverageState
    go (mergePatternCoverage coverage rowCoverage) rest

missingPatternWitnesses :: MonoType -> [PatternCoverageRow] -> InferM [Text]
missingPatternWitnesses scrutineeTy rows = do
  coverage <-
    foldM
      ( \acc row ->
          if rhsProvesTotal (patternCoverageRowRhs row)
            then mergePatternCoverage acc <$> patternTotalCoverage scrutineeTy (patternCoverageRowPattern row)
            else pure acc
      )
      emptyPatternCoverageState
      rows
  if patternCoverageCoversAll coverage
    then pure []
    else do
      family <- constructorFamilyForType scrutineeTy
      case family of
        Nothing ->
          pure ["<unknown>"]
        Just required ->
          pure (map renderRName (Set.toList (required `Set.difference` patternCoverageConstructors coverage)))

mergePatternCoverage :: PatternCoverageState -> PatternCoverageState -> PatternCoverageState
mergePatternCoverage lhs rhs =
  PatternCoverageState
    { patternCoverageCoversAll = patternCoverageCoversAll lhs || patternCoverageCoversAll rhs
    , patternCoverageConstructors = patternCoverageConstructors lhs <> patternCoverageConstructors rhs
    , patternCoverageLiterals = patternCoverageLiterals lhs <> patternCoverageLiterals rhs
    }

patternTotalCoverage :: MonoType -> RPat -> InferM PatternCoverageState
patternTotalCoverage scrutineeTy pat =
  case pat of
    RPVar {} ->
      pure emptyPatternCoverageState {patternCoverageCoversAll = True}
    RPWildcard ->
      pure emptyPatternCoverageState {patternCoverageCoversAll = True}
    RPIrrefutable {} ->
      pure emptyPatternCoverageState {patternCoverageCoversAll = True}
    RPParen inner ->
      patternTotalCoverage scrutineeTy inner
    RPAs _ inner ->
      patternTotalCoverage scrutineeTy inner
    RPLit literal ->
      pure emptyPatternCoverageState {patternCoverageLiterals = Set.singleton literal}
    RPList [] ->
      pure emptyPatternCoverageState {patternCoverageConstructors = Set.singleton listNilDataConName}
    RPTuple fields ->
      case scrutineeTy of
        TyTuple fieldTypes
          | length fieldTypes == length fields -> do
              fieldsExhaustive <- andM (zipWith patternProvesExhaustive fieldTypes fields)
              pure
                emptyPatternCoverageState
                  { patternCoverageConstructors =
                      if fieldsExhaustive
                        then Set.singleton (tupleDataConName (length fields))
                        else Set.empty
                  }
        _ ->
          pure emptyPatternCoverageState
    RPCon name fields ->
      constructorPatternTotalCoverage name fields
    RPRecordCon name fields ->
      recordPatternTotalCoverage name fields
    _ ->
      pure emptyPatternCoverageState

constructorPatternTotalCoverage :: RName -> [RPat] -> InferM PatternCoverageState
constructorPatternTotalCoverage name fields = do
  canonical <- canonicalConstructorName name
  fieldsCovered <-
    if canonical == trueDataConName || canonical == falseDataConName
      then pure (null fields)
      else constructorFieldsProveExhaustive canonical fields
  pure
    emptyPatternCoverageState
      { patternCoverageConstructors =
          if fieldsCovered
            then Set.singleton canonical
            else Set.empty
      }

recordPatternTotalCoverage :: RName -> [(RName, RPat)] -> InferM PatternCoverageState
recordPatternTotalCoverage name fields = do
  canonical <- canonicalConstructorName name
  maybeInfo <- lookupDataConstructorInfo canonical
  case maybeInfo of
    Nothing ->
      pure emptyPatternCoverageState
    Just info -> do
      orderedFields <- orderRecordPatternFields canonical info fields
      constructorPatternTotalCoverage canonical orderedFields

patternRedundantUnderCoverage :: MonoType -> PatternCoverageState -> RPat -> InferM Bool
patternRedundantUnderCoverage scrutineeTy coverage pat
  | patternCoverageCoversAll coverage =
      pure True
  | otherwise = do
      family <- constructorFamilyForType scrutineeTy
      case family of
        Just required
          | required `Set.isSubsetOf` patternCoverageConstructors coverage
          , patternSyntacticallyIrrefutable pat ->
              pure True
        _ ->
          patternHeadAlreadyCovered coverage pat

patternHeadAlreadyCovered :: PatternCoverageState -> RPat -> InferM Bool
patternHeadAlreadyCovered coverage = \case
  RPParen inner ->
    patternHeadAlreadyCovered coverage inner
  RPAs _ inner ->
    patternHeadAlreadyCovered coverage inner
  RPIrrefutable inner ->
    patternHeadAlreadyCovered coverage inner
  RPLit literal ->
    pure (literal `Set.member` patternCoverageLiterals coverage)
  RPList [] ->
    pure (listNilDataConName `Set.member` patternCoverageConstructors coverage)
  RPTuple fields ->
    pure (tupleDataConName (length fields) `Set.member` patternCoverageConstructors coverage)
  RPCon name _ -> do
    canonical <- canonicalConstructorName name
    pure (canonical `Set.member` patternCoverageConstructors coverage)
  RPRecordCon name _ -> do
    canonical <- canonicalConstructorName name
    pure (canonical `Set.member` patternCoverageConstructors coverage)
  _ ->
    pure False

rhsProvesTotal :: RRhs -> Bool
rhsProvesTotal = \case
  RUnguarded {} ->
    True
  RGuarded branches ->
    any (guardProvesTrue . fst) branches

guardProvesTrue :: RExpr -> Bool
guardProvesTrue = \case
  RCon name ->
    name == trueDataConName || nameOcc name == "True"
  RVar name ->
    nameOcc name == "otherwise"
  RParen inner ->
    guardProvesTrue inner
  _ ->
    False

patternProvesExhaustive :: MonoType -> RPat -> InferM Bool
patternProvesExhaustive scrutineeTy pat =
  case pat of
    RPVar {} ->
      pure True
    RPWildcard ->
      pure True
    RPIrrefutable {} ->
      pure True
    RPParen inner ->
      patternProvesExhaustive scrutineeTy inner
    RPAs _ inner ->
      patternProvesExhaustive scrutineeTy inner
    RPTuple fields ->
      case scrutineeTy of
        TyTuple fieldTypes
          | length fieldTypes == length fields ->
              andM (zipWith patternProvesExhaustive fieldTypes fields)
        _ ->
          pure False
    RPCon name fields ->
      constructorPatternProvesExhaustive scrutineeTy name fields
    RPRecordCon name fields ->
      recordPatternProvesExhaustive scrutineeTy name fields
    _ ->
      pure False

constructorPatternProvesExhaustive :: MonoType -> RName -> [RPat] -> InferM Bool
constructorPatternProvesExhaustive scrutineeTy name fields = do
  canonical <- canonicalConstructorName name
  familyCovered <- constructorFamilyCovered scrutineeTy [RPCon canonical fields]
  fieldsCovered <-
    if canonical == trueDataConName || canonical == falseDataConName
      then pure (null fields)
      else constructorFieldsProveExhaustive canonical fields
  pure (familyCovered && fieldsCovered)

recordPatternProvesExhaustive :: MonoType -> RName -> [(RName, RPat)] -> InferM Bool
recordPatternProvesExhaustive scrutineeTy name fields = do
  canonical <- canonicalConstructorName name
  maybeInfo <- lookupDataConstructorInfo canonical
  case maybeInfo of
    Nothing ->
      pure False
    Just info -> do
      orderedFields <- orderRecordPatternFields canonical info fields
      familyCovered <- constructorFamilyCovered scrutineeTy [RPRecordCon canonical fields]
      fieldsCovered <- constructorFieldsProveExhaustive canonical orderedFields
      pure (familyCovered && fieldsCovered)

constructorFieldsProveExhaustive :: RName -> [RPat] -> InferM Bool
constructorFieldsProveExhaustive name fields = do
  maybeInfo <- lookupDataConstructorInfo name
  case maybeInfo of
    Nothing ->
      pure False
    Just info -> do
      (fieldTypes, _) <- instantiateConstructorPattern info
      if length fieldTypes == length fields
        then andM (zipWith patternProvesExhaustive fieldTypes fields)
        else pure False

constructorFamilyCovered :: MonoType -> [RPat] -> InferM Bool
constructorFamilyCovered scrutineeTy patterns = do
  family <- constructorFamilyForType scrutineeTy
  case family of
    Nothing ->
      pure False
    Just required -> do
      covered <- Set.fromList . mapMaybe id <$> traverse coveredConstructor patterns
      pure (required `Set.isSubsetOf` covered)

coveredConstructor :: RPat -> InferM (Maybe RName)
coveredConstructor = \case
  RPParen inner ->
    coveredConstructor inner
  RPAs _ inner ->
    coveredConstructor inner
  RPCon name fields -> do
    canonical <- canonicalConstructorName name
    if canonical == trueDataConName || canonical == falseDataConName
      then pure (if null fields then Just canonical else Nothing)
      else do
        fieldsCovered <- constructorFieldsProveExhaustive canonical fields
        pure (if fieldsCovered then Just canonical else Nothing)
  RPRecordCon name fields -> do
    canonical <- canonicalConstructorName name
    maybeInfo <- lookupDataConstructorInfo canonical
    case maybeInfo of
      Nothing ->
        pure Nothing
      Just info -> do
        orderedFields <- orderRecordPatternFields canonical info fields
        fieldsCovered <- constructorFieldsProveExhaustive canonical orderedFields
        pure (if fieldsCovered then Just canonical else Nothing)
  RPList [] ->
    pure (Just listNilDataConName)
  RPTuple fields ->
    if all patternSyntacticallyIrrefutable fields
      then pure (Just (tupleDataConName (length fields)))
      else pure Nothing
  pat
    | patternSyntacticallyIrrefutable pat ->
        pure Nothing
  _ ->
    pure Nothing

patternSyntacticallyIrrefutable :: RPat -> Bool
patternSyntacticallyIrrefutable = \case
  RPVar {} -> True
  RPWildcard -> True
  RPIrrefutable {} -> True
  RPParen inner -> patternSyntacticallyIrrefutable inner
  RPAs _ inner -> patternSyntacticallyIrrefutable inner
  RPTuple fields -> all patternSyntacticallyIrrefutable fields
  _ -> False

constructorFamilyForType :: MonoType -> InferM (Maybe (Set.Set RName))
constructorFamilyForType scrutineeTy
  | scrutineeTy == boolMonoType =
      pure (Just (Set.fromList [trueDataConName, falseDataConName]))
constructorFamilyForType scrutineeTy =
  case scrutineeTy of
    TyList {} ->
      pure (Just (Set.fromList [listNilDataConName, listConsDataConName]))
    TyTuple fields ->
      pure (Just (Set.singleton (tupleDataConName (length fields))))
    ty -> do
      constructors <- dataConstructors <$> get
      case monoTypeHead ty of
        Nothing ->
          pure Nothing
        Just headName ->
          let matching =
                Set.fromList
                  [ name
                  | (name, info) <- Map.toList constructors
                  , monoTypeHead (dataConstructorResult info) == Just headName
                  , not (isClassDictionaryConstructorName name)
                  ]
           in pure (if Set.null matching then Nothing else Just matching)

isClassDictionaryConstructorName :: RName -> Bool
isClassDictionaryConstructorName name =
  "$Mk" `Text.isPrefixOf` nameOcc name && "Dict" `Text.isSuffixOf` nameOcc name

monoTypeHead :: MonoType -> Maybe RName
monoTypeHead = \case
  TyCon name -> Just name
  TyApp fn _ -> monoTypeHead fn
  _ -> Nothing

canonicalConstructorName :: RName -> InferM RName
canonicalConstructorName name
  | name == trueDataConName || nameOcc name == "True" =
      pure trueDataConName
  | name == falseDataConName || nameOcc name == "False" =
      pure falseDataConName
  | otherwise =
      case preludeConstructorInfo name of
        Just (coreName, _) -> pure coreName
        Nothing -> pure name

lookupDataConstructorInfo :: RName -> InferM (Maybe DataConstructorInfo)
lookupDataConstructorInfo name = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Just info -> pure (Just info)
    Nothing -> pure (snd <$> preludeConstructorInfo name)

caseForPatternPlan :: TypedExpr -> TypedBinder -> PatternPlan -> TypedExpr -> TypedExpr
caseForPatternPlan scrutinee caseBinder plan body
  | patternNeedsRuntimeCase plan =
      TCase
        scrutinee
        caseBinder
        [ TypedAlt
            (patternAltCon plan)
            (patternAltBinders plan)
            (patternWrapBody plan body)
        ]
        (typedExprType body)
  | otherwise =
      patternWrapBody plan body

inferPatternPlan :: TypeEnv -> MonoType -> TypedExpr -> RPat -> InferM PatternPlan
inferPatternPlan env expectedTy scrutinee pat =
  withTypecheckSpan (rPatSpan pat) $
    case pat of
      RPVar name ->
        pure
          PatternPlan
            { patternAltCon = DefaultAlt
            , patternAltBinders = []
            , patternEnv = Map.insert name (Scheme [] [] expectedTy) env
            , patternWrapBody = aliasPatternBinder name expectedTy scrutinee
            , patternNeedsRuntimeCase = True
            }
      RPWildcard ->
        pure
          PatternPlan
            { patternAltCon = DefaultAlt
            , patternAltBinders = []
            , patternEnv = env
            , patternWrapBody = id
            , patternNeedsRuntimeCase = True
            }
      RPLit (LString value) ->
        inferListPattern env expectedTy scrutinee (stringLiteralPattern value)
      RPLit literal -> do
        unify expectedTy (literalMonoType literal)
        pure
          PatternPlan
            { patternAltCon = LiteralAlt literal
            , patternAltBinders = []
            , patternEnv = env
            , patternWrapBody = id
            , patternNeedsRuntimeCase = True
            }
      RPCon name args ->
        inferConstructorPattern env expectedTy scrutinee name args
      RPRecordCon name fields ->
        inferRecordConstructorPattern env expectedTy scrutinee name fields
      RPTuple patterns ->
        inferTuplePattern env expectedTy patterns
      RPList patterns ->
        inferListPattern env expectedTy scrutinee patterns
      RPParen inner ->
        inferPatternPlan env expectedTy scrutinee inner
      RPAs name inner -> do
        plan <- inferPatternPlan env expectedTy scrutinee inner
        pure
          plan
            { patternEnv = Map.insert name (Scheme [] [] expectedTy) (patternEnv plan)
            , patternWrapBody = aliasPatternBinder name expectedTy scrutinee . patternWrapBody plan
            }
      RPIrrefutable inner ->
        inferIrrefutablePatternPlan env expectedTy scrutinee inner

inferIrrefutablePatternPlan :: TypeEnv -> MonoType -> TypedExpr -> RPat -> InferM PatternPlan
inferIrrefutablePatternPlan env expectedTy scrutinee pat = do
  (bindings, patternBindings) <- inferIrrefutablePatternBindings expectedTy scrutinee pat
  pure
    PatternPlan
      { patternAltCon = DefaultAlt
      , patternAltBinders = []
      , patternEnv = Map.union patternBindings env
      , patternWrapBody = \body -> lazyLet bindings body
      , patternNeedsRuntimeCase = False
      }

lazyLet :: [TypedBinding] -> TypedExpr -> TypedExpr
lazyLet [] body =
  body
lazyLet bindings body =
  TLet bindings body (typedExprType body)

inferIrrefutablePatternBindings :: MonoType -> TypedExpr -> RPat -> InferM ([TypedBinding], TypeEnv)
inferIrrefutablePatternBindings expectedTy scrutinee pat =
  withTypecheckSpan (rPatSpan pat) $
    case pat of
      RPVar name ->
        pure (singleLazyBinding name expectedTy scrutinee)
      RPWildcard ->
        pure ([], Map.empty)
      RPLit (LString value) ->
        inferIrrefutableListBindings expectedTy scrutinee (stringLiteralPattern value)
      RPLit literal -> do
        unify expectedTy (literalMonoType literal)
        pure ([], Map.empty)
      RPCon name args ->
        inferIrrefutableConstructorBindings expectedTy scrutinee name args
      RPRecordCon name fields ->
        inferIrrefutableRecordBindings expectedTy scrutinee name fields
      RPTuple patterns ->
        inferIrrefutableTupleBindings expectedTy scrutinee patterns
      RPList patterns ->
        inferIrrefutableListBindings expectedTy scrutinee patterns
      RPParen inner ->
        inferIrrefutablePatternBindings expectedTy scrutinee inner
      RPAs name inner -> do
        (bindings, patternBindings) <- inferIrrefutablePatternBindings expectedTy scrutinee inner
        let (aliasBinding, aliasEnv) = singleLazyBinding name expectedTy scrutinee
        pure (aliasBinding <> bindings, Map.union aliasEnv patternBindings)
      RPIrrefutable inner ->
        inferIrrefutablePatternBindings expectedTy scrutinee inner

singleLazyBinding :: RName -> MonoType -> TypedExpr -> ([TypedBinding], TypeEnv)
singleLazyBinding name ty scrutinee =
  ( [ TypedBinding
        { typedBindingName = name
        , typedBindingScheme = Scheme [] [] ty
        , typedBindingGeneralizedMetas = Map.empty
        , typedBindingRhs = scrutinee
        }
    ]
  , Map.singleton name (Scheme [] [] ty)
  )

inferIrrefutableConstructorBindings :: MonoType -> TypedExpr -> RName -> [RPat] -> InferM ([TypedBinding], TypeEnv)
inferIrrefutableConstructorBindings expectedTy scrutinee name args
  | nameOcc name == "True" && null args = do
      unify expectedTy boolMonoType
      pure ([], Map.empty)
  | nameOcc name == "False" && null args = do
      unify expectedTy boolMonoType
      pure ([], Map.empty)
  | otherwise = do
      constructors <- dataConstructors <$> get
      case Map.lookup name constructors of
        Nothing ->
          case preludeConstructorInfo name of
            Nothing ->
              throwTypecheck (UnsupportedCore0 ("constructor pattern `" <> renderRName name <> "`"))
            Just (coreName, info) ->
              inferIrrefutableKnownConstructorBindings expectedTy scrutinee coreName args info
        Just info ->
          inferIrrefutableKnownConstructorBindings expectedTy scrutinee name args info

inferIrrefutableRecordBindings :: MonoType -> TypedExpr -> RName -> [(RName, RPat)] -> InferM ([TypedBinding], TypeEnv)
inferIrrefutableRecordBindings expectedTy scrutinee name fields = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("record constructor pattern `" <> renderRName name <> "`"))
    Just info -> do
      orderedFields <- orderRecordPatternFields name info fields
      inferIrrefutableKnownConstructorBindings expectedTy scrutinee name orderedFields info

inferIrrefutableTupleBindings :: MonoType -> TypedExpr -> [RPat] -> InferM ([TypedBinding], TypeEnv)
inferIrrefutableTupleBindings expectedTy scrutinee patterns = do
  fieldTypes <- traverse (const freshMeta) patterns
  unify expectedTy (TyTuple fieldTypes)
  inferIrrefutableFieldBindings
    (ConstructorAlt (tupleDataConName (length patterns)))
    CoreDataConstructor
    fieldTypes
    scrutinee
    patterns

inferIrrefutableListBindings :: MonoType -> TypedExpr -> [RPat] -> InferM ([TypedBinding], TypeEnv)
inferIrrefutableListBindings expectedTy scrutinee patterns = do
  elementTy <- freshMeta
  unify expectedTy (TyList elementTy)
  case patterns of
    [] ->
      pure ([], Map.empty)
    headPat : tailPats ->
      inferIrrefutableKnownConstructorBindings expectedTy scrutinee listConsDataConName [headPat, RPList tailPats] (builtinDataConstructors Map.! listConsDataConName)

inferIrrefutableKnownConstructorBindings ::
  MonoType ->
  TypedExpr ->
  RName ->
  [RPat] ->
  DataConstructorInfo ->
  InferM ([TypedBinding], TypeEnv)
inferIrrefutableKnownConstructorBindings expectedTy scrutinee name args info = do
  (fieldTypes, resultTy) <- instantiateConstructorPattern info
  unless (length fieldTypes == length args) $
    throwTypecheck
      ( UnsupportedCore0
          ( "constructor pattern `"
              <> renderRName name
              <> "` expects "
              <> Text.pack (show (length fieldTypes))
              <> " fields, got "
              <> Text.pack (show (length args))
          )
      )
  unify expectedTy resultTy
  inferIrrefutableFieldBindings (ConstructorAlt name) (dataConstructorRepresentation info) fieldTypes scrutinee args

inferIrrefutableFieldBindings ::
  CoreAltCon ->
  CoreConstructorRepresentation ->
  [MonoType] ->
  TypedExpr ->
  [RPat] ->
  InferM ([TypedBinding], TypeEnv)
inferIrrefutableFieldBindings altCon representation fieldTypes scrutinee patterns =
  case (representation, fieldTypes, patterns) of
    (CoreNewtypeConstructor, [fieldTy], [fieldPat]) -> do
      fieldTy' <- applyCurrent fieldTy
      inferIrrefutablePatternBindings fieldTy' (TCoerce scrutinee fieldTy') fieldPat
    _ -> do
      fieldScrutinees <- traverse fieldProjection (zip [0 ..] fieldTypes)
      results <-
        traverse
          (\(fieldTy, fieldScrutinee, fieldPat) -> inferIrrefutablePatternBindings fieldTy fieldScrutinee fieldPat)
          (zip3 fieldTypes fieldScrutinees patterns)
      let bindings = concatMap fst results
          env = Map.unions (map snd results)
      pure (bindings, env)
 where
  fieldProjection (index, fieldTy) = do
    fieldBinders <- traverse (uncurry fieldBinder) (zip [0 ..] fieldTypes)
    caseBinder <- freshTermBinder "$lazy_case" (typedExprType scrutinee)
    let selectedBinder = fieldBinders !! index
        selected =
          TVar
            (typedBinderName selectedBinder)
            (Scheme [] [] (typedBinderType selectedBinder))
            []
            (typedBinderType selectedBinder)
    pure
      ( TCase
          scrutinee
          caseBinder
          [TypedAlt altCon fieldBinders selected]
          fieldTy
      )

  fieldBinder index fieldTy =
    freshTermBinder ("$lazy_field" <> renderInt index) fieldTy

inferConstructorPattern :: TypeEnv -> MonoType -> TypedExpr -> RName -> [RPat] -> InferM PatternPlan
inferConstructorPattern env expectedTy scrutinee name args
  | nameOcc name == "True" && null args = do
      unify expectedTy boolMonoType
      pure (nullaryConstructorPlan env trueDataConName)
  | nameOcc name == "False" && null args = do
      unify expectedTy boolMonoType
      pure (nullaryConstructorPlan env falseDataConName)
  | otherwise = do
      constructors <- dataConstructors <$> get
      case Map.lookup name constructors of
        Nothing ->
          case preludeConstructorInfo name of
            Nothing ->
              throwTypecheck (UnsupportedCore0 ("constructor pattern `" <> renderRName name <> "`"))
            Just (coreName, info) ->
              inferKnownConstructorPattern env expectedTy scrutinee coreName args info
        Just info -> do
          inferKnownConstructorPattern env expectedTy scrutinee name args info

inferRecordConstructorPattern :: TypeEnv -> MonoType -> TypedExpr -> RName -> [(RName, RPat)] -> InferM PatternPlan
inferRecordConstructorPattern env expectedTy scrutinee name fields = do
  constructors <- dataConstructors <$> get
  case Map.lookup name constructors of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("record constructor pattern `" <> renderRName name <> "`"))
    Just info -> do
      orderedFields <- orderRecordPatternFields name info fields
      inferKnownConstructorPattern env expectedTy scrutinee name orderedFields info

inferKnownConstructorPattern :: TypeEnv -> MonoType -> TypedExpr -> RName -> [RPat] -> DataConstructorInfo -> InferM PatternPlan
inferKnownConstructorPattern env expectedTy scrutinee name args info = do
  (fieldTypes, resultTy) <- instantiateConstructorPattern info
  unless (length fieldTypes == length args) $
    throwTypecheck
      ( UnsupportedCore0
          ( "constructor pattern `"
              <> renderRName name
              <> "` expects "
              <> Text.pack (show (length fieldTypes))
              <> " fields, got "
              <> Text.pack (show (length args))
          )
      )
  unify expectedTy resultTy
  case dataConstructorRepresentation info of
    CoreNewtypeConstructor ->
      case (fieldTypes, args) of
        ([fieldTy], [fieldPat]) -> do
          fieldTy' <- applyCurrent fieldTy
          let fieldScrutinee = TCoerce scrutinee fieldTy'
          nestedPlan <- inferPatternPlan Map.empty fieldTy' fieldScrutinee fieldPat
          nestedCaseBinder <- freshTermBinder "$newtype" fieldTy'
          pure
            PatternPlan
              { patternAltCon = DefaultAlt
              , patternAltBinders = []
              , patternEnv = Map.union (patternEnv nestedPlan) env
              , patternWrapBody = caseForPatternPlan fieldScrutinee nestedCaseBinder nestedPlan
              , patternNeedsRuntimeCase = False
              }
        _ ->
          throwTypecheck (InvalidNewtypeConstructorArity name (length fieldTypes))
    CoreDataConstructor -> do
      fieldPlans <- traverse inferFieldPattern (zip fieldTypes args)
      let fieldBinders = map fieldPatternBinder fieldPlans
          env' = foldl (\acc plan -> Map.union (fieldPatternEnv plan) acc) env fieldPlans
          wrap = foldr (.) id (map fieldPatternWrap fieldPlans)
      pure
        PatternPlan
          { patternAltCon = ConstructorAlt name
          , patternAltBinders = fieldBinders
          , patternEnv = env'
          , patternWrapBody = wrap
          , patternNeedsRuntimeCase = True
          }

inferTuplePattern :: TypeEnv -> MonoType -> [RPat] -> InferM PatternPlan
inferTuplePattern env expectedTy patterns = do
  fieldTypes <- traverse (const freshMeta) patterns
  unify expectedTy (TyTuple fieldTypes)
  fieldPlans <- traverse inferFieldPattern (zip fieldTypes patterns)
  let fieldBinders = map fieldPatternBinder fieldPlans
      env' = foldl (\acc plan -> Map.union (fieldPatternEnv plan) acc) env fieldPlans
      wrap = foldr (.) id (map fieldPatternWrap fieldPlans)
  pure
    PatternPlan
      { patternAltCon = ConstructorAlt (tupleDataConName (length patterns))
      , patternAltBinders = fieldBinders
      , patternEnv = env'
      , patternWrapBody = wrap
      , patternNeedsRuntimeCase = True
      }

inferListPattern :: TypeEnv -> MonoType -> TypedExpr -> [RPat] -> InferM PatternPlan
inferListPattern env expectedTy scrutinee patterns = do
  elementTy <- freshMeta
  unify expectedTy (TyList elementTy)
  case patterns of
    [] ->
      pure (nullaryConstructorPlan env listNilDataConName)
    headPat : tailPats ->
      inferConstructorPattern env expectedTy scrutinee listConsDataConName [headPat, RPList tailPats]

nullaryConstructorPlan :: TypeEnv -> RName -> PatternPlan
nullaryConstructorPlan env name =
  PatternPlan
    { patternAltCon = ConstructorAlt name
    , patternAltBinders = []
    , patternEnv = env
    , patternWrapBody = id
    , patternNeedsRuntimeCase = True
    }

data FieldPatternPlan = FieldPatternPlan
  { fieldPatternBinder :: TypedBinder
  , fieldPatternEnv :: TypeEnv
  , fieldPatternWrap :: TypedExpr -> TypedExpr
  }

inferFieldPattern :: (MonoType, RPat) -> InferM FieldPatternPlan
inferFieldPattern (fieldTy, pat) =
  case pat of
    RPVar name ->
      let binder = TypedBinder name fieldTy
       in pure
            FieldPatternPlan
              { fieldPatternBinder = binder
              , fieldPatternEnv = Map.singleton name (Scheme [] [] fieldTy)
              , fieldPatternWrap = id
              }
    RPWildcard -> do
      binder <- freshTermBinder "$field" fieldTy
      pure
        FieldPatternPlan
          { fieldPatternBinder = binder
          , fieldPatternEnv = Map.empty
          , fieldPatternWrap = id
          }
    RPParen inner ->
      inferFieldPattern (fieldTy, inner)
    _ -> do
      fieldBinder <- freshTermBinder "$field" fieldTy
      nestedCaseBinder <- freshTermBinder "$case" fieldTy
      let scrutinee = TVar (typedBinderName fieldBinder) (Scheme [] [] fieldTy) [] fieldTy
      nestedPlan <- inferPatternPlan Map.empty fieldTy scrutinee pat
      let wrap = caseForPatternPlan scrutinee nestedCaseBinder nestedPlan
      pure
        FieldPatternPlan
          { fieldPatternBinder = fieldBinder
          , fieldPatternEnv = patternEnv nestedPlan
          , fieldPatternWrap = wrap
          }

instantiateConstructorPattern :: DataConstructorInfo -> InferM ([MonoType], MonoType)
instantiateConstructorPattern info = do
  replacements <- traverse (\name -> (name,) <$> freshMeta) (dataConstructorTyVars info)
  let replacementMap = Map.fromList replacements
  pure
    ( map (replaceTypeVars replacementMap) (dataConstructorFields info)
    , replaceTypeVars replacementMap (dataConstructorResult info)
    )

instantiateConstructorFields :: DataConstructorInfo -> InferM ([MonoType], MonoType, [MonoType])
instantiateConstructorFields info = do
  replacements <- traverse (\name -> (name,) <$> freshMeta) (dataConstructorTyVars info)
  let replacementMap = Map.fromList replacements
      typeArguments = map snd replacements
  pure
    ( map (replaceTypeVars replacementMap) (dataConstructorFields info)
    , replaceTypeVars replacementMap (dataConstructorResult info)
    , typeArguments
    )

orderRecordFields :: Text -> RName -> DataConstructorInfo -> [(RName, a)] -> InferM [a]
orderRecordFields context constructorName info fields = do
  labelMap <- recordLabelIndexMap context constructorName info
  seen <- ensureRecordFieldInputs context constructorName labelMap (map fst fields)
  let missing = [label | label <- Map.keys labelMap, label `Set.notMember` seen]
  unless (null missing) $
    throwTypecheck
      ( UnsupportedCore0
          ( context
              <> " for `"
              <> renderRName constructorName
              <> "` is missing fields "
              <> Text.intercalate ", " (map renderRName missing)
          )
      )
  pure
    [ value
    | (_, index) <- List.sortOn snd (Map.toList labelMap)
    , let value = fieldValues Map.! index
    ]
 where
  fieldValues =
    Map.fromList
      [ (index, value)
      | (label, value) <- fields
      , Just index <- [Map.lookup label (recordLabelIndexMapPure info)]
      ]

orderRecordPatternFields :: RName -> DataConstructorInfo -> [(RName, RPat)] -> InferM [RPat]
orderRecordPatternFields constructorName info fields = do
  labelMap <- recordLabelIndexMap "record pattern" constructorName info
  _ <- ensureRecordFieldInputs "record pattern" constructorName labelMap (map fst fields)
  let provided = Map.fromList [(label, pat) | (label, pat) <- fields]
  pure
    [ maybe RPWildcard id (Map.lookup label provided)
    | (label, _) <- List.sortOn snd (Map.toList labelMap)
    ]

recordLabelIndexMap :: Text -> RName -> DataConstructorInfo -> InferM (Map.Map RName Int)
recordLabelIndexMap context constructorName info =
  case dataConstructorFieldLabels info of
    [] ->
      throwTypecheck (UnsupportedCore0 (context <> " for non-record constructor `" <> renderRName constructorName <> "`"))
    labels
      | all (== Nothing) labels ->
          throwTypecheck (UnsupportedCore0 (context <> " for non-record constructor `" <> renderRName constructorName <> "`"))
      | otherwise ->
          case sequence labels of
            Nothing ->
              throwTypecheck (UnsupportedCore0 (context <> " for partially labelled constructor `" <> renderRName constructorName <> "`"))
            Just names -> do
              ensureNoDuplicateRecordLabels constructorName names
              pure (Map.fromList (zip names [0 ..]))

recordLabelIndexMapPure :: DataConstructorInfo -> Map.Map RName Int
recordLabelIndexMapPure info =
  Map.fromList
    [ (label, index)
    | (index, Just label) <- zip [0 ..] (dataConstructorFieldLabels info)
    ]

ensureRecordFieldInputs :: Text -> RName -> Map.Map RName Int -> [RName] -> InferM (Set.Set RName)
ensureRecordFieldInputs context constructorName labelMap labels =
  go Set.empty labels
 where
  go seen [] =
    pure seen
  go seen (label : rest)
    | label `Set.member` seen =
        throwTypecheck
          ( UnsupportedCore0
              ( context
                  <> " for `"
                  <> renderRName constructorName
                  <> "` repeats field `"
                  <> renderRName label
                  <> "`"
              )
          )
    | label `Map.notMember` labelMap =
        throwTypecheck
          ( UnsupportedCore0
              ( context
                  <> " for `"
                  <> renderRName constructorName
                  <> "` uses unknown field `"
                  <> renderRName label
                  <> "`"
              )
          )
    | otherwise =
        go (Set.insert label seen) rest

ensureNoDuplicateRecordLabels :: RName -> [RName] -> InferM ()
ensureNoDuplicateRecordLabels constructorName labels =
  go Set.empty labels
 where
  go _ [] =
    pure ()
  go seen (label : rest)
    | label `Set.member` seen =
        throwTypecheck
          ( UnsupportedCore0
              ( "duplicate record field `"
                  <> renderRName label
                  <> "` in constructor `"
                  <> renderRName constructorName
                  <> "`"
              )
          )
    | otherwise =
        go (Set.insert label seen) rest

caseBinderFor :: MonoType -> [RAlt] -> InferM TypedBinder
caseBinderFor scrutineeTy alternatives =
  case [name | RAlt (RPVar name) _ _ <- alternatives] of
    name : _ ->
      pure (TypedBinder name scrutineeTy)
    [] ->
      freshTermBinder "$case" scrutineeTy

sourceScheme :: RHsType -> InferM Scheme
sourceScheme sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $ do
    (constraints, mono) <- sourceQualifiedMonoType sourceType
    pure (Scheme (List.nub (concatMap constraintTypeVars constraints <> typeVars mono)) constraints mono)

sourceQualifiedMonoType :: RHsType -> InferM ([ClassConstraint], MonoType)
sourceQualifiedMonoType sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $
    case sourceType of
      RTyContext constraints body -> do
        typedConstraints <- traverse sourceClassConstraint constraints
        mono <- sourceMonoType body
        pure (typedConstraints, mono)
      ty ->
        ([],) <$> sourceMonoType ty

sourceClassConstraint :: RHsType -> InferM ClassConstraint
sourceClassConstraint sourceConstraint =
  withTypecheckSpan (rTypeSpan sourceConstraint) $
    case typeApplicationSpine sourceConstraint of
      Just (className, arguments) -> do
        argument <- requireSingleConstraintArgument className arguments
        let canonicalName = canonicalClassName className
        expectedKind <- classConstraintArgumentKind canonicalName
        argumentTy <- sourceMonoTypeAtKind expectedKind argument
        sourceRange <- currentTypecheckSpan
        pure (singleClassConstraintAt sourceRange canonicalName argumentTy)
      Nothing ->
        throwTypecheck (UnsupportedCore0 ("type-class constraint " <> Text.pack (show sourceConstraint)))

classConstraintArgumentKind :: RName -> InferM Kind
classConstraintArgumentKind className = do
  classes <- classInfos <$> get
  pure $
    case Map.lookup className classes <|> Map.lookup className builtinClassInfos of
      Just info -> classInfoVariableKind info
      Nothing -> StarKind

requireSingleConstraintArgument :: RName -> [a] -> InferM a
requireSingleConstraintArgument className = \case
  [argument] ->
    pure argument
  arguments ->
    throwTypecheck (InvalidClassConstraintArity className (length arguments))

throwUnsupportedClassConstraintContext :: ClassConstraintContext -> [ClassConstraint] -> InferM a
throwUnsupportedClassConstraintContext context constraints =
  throwTypecheck (UnsupportedClassConstraintContext context constraints)

sourceMonoType :: RHsType -> InferM MonoType
sourceMonoType sourceType =
  sourceMonoTypeAtKind StarKind sourceType

sourceMonoTypeAtKind :: Kind -> RHsType -> InferM MonoType
sourceMonoTypeAtKind expectedKind sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $ do
    checkSourceTypeKindAt expectedKind sourceType
    expanded <- expandSourceTypeSynonyms sourceType
    sourceMonoTypeUnchecked expanded

sourceMonoTypeUnchecked :: RHsType -> InferM MonoType
sourceMonoTypeUnchecked sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $
    case sourceType of
      RTyVar name ->
        pure (TyVar name)
      RTyCon name ->
        typeConstructorMonoType name
      RTyApp fn arg ->
        TyApp <$> sourceMonoTypeUnchecked fn <*> sourceMonoTypeUnchecked arg
      RTyFun arg result ->
        TyFun <$> sourceMonoTypeUnchecked arg <*> sourceMonoTypeUnchecked result
      RTyContext [] body ->
        sourceMonoTypeUnchecked body
      RTyContext _ _ ->
        throwTypecheck (UnsupportedCore0 "nested type-class constraints")
      RTyTuple types ->
        TyTuple <$> traverse sourceMonoTypeUnchecked types
      RTyList elementType ->
        TyList <$> sourceMonoTypeUnchecked elementType
      RTyParen inner ->
        sourceMonoTypeUnchecked inner

expandSourceTypeSynonyms :: RHsType -> InferM RHsType
expandSourceTypeSynonyms =
  expandTypeSynonyms []

expandTypeSynonyms :: [RName] -> RHsType -> InferM RHsType
expandTypeSynonyms stack sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $
    case typeApplicationSpine sourceType of
      Just (name, args) -> do
        synonyms <- typeSynonyms <$> get
        case Map.lookup name synonyms <|> builtinTypeSynonymInfo name of
          Just info ->
            expandSynonymApplication stack name info args
          Nothing ->
            expandStructurally
      Nothing ->
        expandStructurally
 where
  expandStructurally =
    case sourceType of
      RTyVar {} ->
        pure sourceType
      RTyCon {} ->
        pure sourceType
      RTyApp fn arg ->
        RTyApp <$> expandTypeSynonyms stack fn <*> expandTypeSynonyms stack arg
      RTyFun arg result ->
        RTyFun <$> expandTypeSynonyms stack arg <*> expandTypeSynonyms stack result
      RTyContext constraints body ->
        RTyContext <$> traverse (expandTypeSynonyms stack) constraints <*> expandTypeSynonyms stack body
      RTyTuple types ->
        RTyTuple <$> traverse (expandTypeSynonyms stack) types
      RTyList elementType ->
        RTyList <$> expandTypeSynonyms stack elementType
      RTyParen inner ->
        RTyParen <$> expandTypeSynonyms stack inner

expandSynonymApplication :: [RName] -> RName -> TypeSynonymInfo -> [RHsType] -> InferM RHsType
expandSynonymApplication stack name info args
  | name `elem` stack = throwTypecheck (RecursiveTypeSynonym (name : stack))
  | actualArity /= expectedArity = throwTypecheck (TypeSynonymArityMismatch name expectedArity actualArity)
  | otherwise = do
      expandedArgs <- traverse (expandTypeSynonyms stack) args
      let replacements = Map.fromList (zip (typeSynonymParams info) expandedArgs)
          expandedBody = replaceSourceTypeVars replacements (typeSynonymBody info)
      expandTypeSynonyms (name : stack) expandedBody
 where
  expectedArity = length (typeSynonymParams info)
  actualArity = length args

typeApplicationSpine :: RHsType -> Maybe (RName, [RHsType])
typeApplicationSpine =
  go []
 where
  go args = \case
    RTyApp fn arg ->
      go (arg : args) fn
    RTyParen inner ->
      go args inner
    RTyCon name ->
      Just (name, args)
    _ ->
      Nothing

replaceSourceTypeVars :: Map.Map RName RHsType -> RHsType -> RHsType
replaceSourceTypeVars replacements = \case
  RTyVar name ->
    Map.findWithDefault (RTyVar name) name replacements
  RTyCon name ->
    RTyCon name
  RTyApp fn arg ->
    RTyApp (replaceSourceTypeVars replacements fn) (replaceSourceTypeVars replacements arg)
  RTyFun arg result ->
    RTyFun (replaceSourceTypeVars replacements arg) (replaceSourceTypeVars replacements result)
  RTyContext constraints body ->
    RTyContext (map (replaceSourceTypeVars replacements) constraints) (replaceSourceTypeVars replacements body)
  RTyTuple types ->
    RTyTuple (map (replaceSourceTypeVars replacements) types)
  RTyList elementType ->
    RTyList (replaceSourceTypeVars replacements elementType)
  RTyParen inner ->
    RTyParen (replaceSourceTypeVars replacements inner)

sourceTypeWithoutParens :: RHsType -> RHsType
sourceTypeWithoutParens = \case
  RTyParen inner -> sourceTypeWithoutParens inner
  other -> other

checkSourceTypeKind :: RHsType -> InferM ()
checkSourceTypeKind sourceType =
  checkSourceTypeKindAt StarKind sourceType

checkSourceTypeKindAt :: Kind -> RHsType -> InferM ()
checkSourceTypeKindAt expected sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $ do
    actual <- inferSourceTypeKind sourceType
    unifyKind expected actual

inferSourceTypeKind :: RHsType -> InferM Kind
inferSourceTypeKind sourceType =
  withTypecheckSpan (rTypeSpan sourceType) $
    case sourceType of
      RTyVar name ->
        typeVariableKind name
      RTyCon name ->
        typeConstructorKindOf name
      RTyApp fn arg -> do
        fnKind <- inferSourceTypeKind fn
        argKind <- inferSourceTypeKind arg
        resultKind <- freshKindMeta
        unifyKind (KindArrow argKind resultKind) fnKind
        applyKindCurrent resultKind
      RTyFun arg result -> do
        checkSourceTypeKind arg
        checkSourceTypeKind result
        pure StarKind
      RTyContext constraints body -> do
        traverse_ checkConstraintKind constraints
        checkSourceTypeKind body
        pure StarKind
      RTyTuple types -> do
        traverse_ checkSourceTypeKind types
        pure StarKind
      RTyList elementType -> do
        checkSourceTypeKind elementType
        pure StarKind
      RTyParen inner ->
        inferSourceTypeKind inner

checkConstraintKind :: RHsType -> InferM ()
checkConstraintKind sourceConstraint =
  withTypecheckSpan (rTypeSpan sourceConstraint) $
    case typeApplicationSpine sourceConstraint of
      Just (className, arguments) -> do
        argument <- requireSingleConstraintArgument className arguments
        expectedKind <- classConstraintArgumentKind (canonicalClassName className)
        checkSourceTypeKindAt expectedKind argument
      Nothing ->
        throwTypecheck (UnsupportedCore0 ("type-class constraint " <> Text.pack (show sourceConstraint)))

typeVariableKind :: RName -> InferM Kind
typeVariableKind name = do
  kinds <- typeVariableKinds <$> get
  case Map.lookup name kinds of
    Just kind ->
      applyKindCurrent kind
    Nothing -> do
      kind <- freshKindMeta
      modify (\state -> state {typeVariableKinds = Map.insert name kind (typeVariableKinds state)})
      pure kind

typeConstructorKindOf :: RName -> InferM Kind
typeConstructorKindOf name = do
  knownTypes <- typeConstructors <$> get
  case Map.lookup name knownTypes of
    Just info ->
      applyKindCurrent (typeConstructorKind info)
    Nothing ->
      case builtinTypeConstructorInfo name of
        Just info -> pure (typeConstructorKind info)
        Nothing -> throwTypecheck (UnsupportedCore0 ("type constructor `" <> nameOcc name <> "`"))

freshKindMeta :: InferM Kind
freshKindMeta = do
  state <- get
  let meta = nextKindMeta state
  modify (\current -> current {nextKindMeta = meta + 1})
  pure (KindMeta meta)

unifyKind :: Kind -> Kind -> InferM ()
unifyKind expected actual = do
  expected' <- applyKindCurrent expected
  actual' <- applyKindCurrent actual
  case (expected', actual') of
    (StarKind, StarKind) ->
      pure ()
    (KindArrow expectedArg expectedResult, KindArrow actualArg actualResult) ->
      unifyKind expectedArg actualArg *> unifyKind expectedResult actualResult
    (KindMeta expectedMeta, kind) ->
      bindKindMeta expectedMeta kind
    (kind, KindMeta actualMeta) ->
      bindKindMeta actualMeta kind
    _ ->
      throwTypecheck (KindMismatch expected' actual')

bindKindMeta :: Int -> Kind -> InferM ()
bindKindMeta meta kind
  | kind == KindMeta meta = pure ()
  | meta `Set.member` kindMetaVars kind = throwTypecheck (KindOccursCheck meta kind)
  | otherwise =
      modify $ \state ->
        state {kindSubstitution = Map.insert meta kind (kindSubstitution state)}

applyKindCurrent :: Kind -> InferM Kind
applyKindCurrent kind = do
  subst <- kindSubstitution <$> get
  pure (applyKindSubst subst kind)

applyKindSubst :: Map.Map Int Kind -> Kind -> Kind
applyKindSubst subst = \case
  StarKind -> StarKind
  KindArrow argument result -> KindArrow (applyKindSubst subst argument) (applyKindSubst subst result)
  KindMeta meta ->
    case Map.lookup meta subst of
      Nothing -> KindMeta meta
      Just kind -> applyKindSubst subst kind

kindMetaVars :: Kind -> Set.Set Int
kindMetaVars = \case
  StarKind -> Set.empty
  KindArrow argument result -> kindMetaVars argument <> kindMetaVars result
  KindMeta meta -> Set.singleton meta

typeConstructorMonoType :: RName -> InferM MonoType
typeConstructorMonoType name = do
  knownTypes <- typeConstructors <$> get
  case Map.lookup name knownTypes of
    Just _ ->
      pure (TyCon name)
    Nothing ->
      builtinTypeConstructorMonoType name

builtinTypeConstructorMonoType :: RName -> InferM MonoType
builtinTypeConstructorMonoType name =
  case builtinTypeConstructorInfo name of
    Nothing ->
      throwTypecheck (UnsupportedCore0 ("type constructor `" <> nameOcc name <> "`"))
    Just _ ->
      case nameOcc name of
        "Int" -> pure intMonoType
        "Integer" -> pure intMonoType
        "Float" -> pure floatMonoType
        "Double" -> pure doubleMonoType
        "Bool" -> pure boolMonoType
        "Char" -> pure charMonoType
        other
          | Just fixed <- fixedIntegralTypeByOccurrence other -> pure (fixedIntegralMonoType fixed)
        "Ratio" -> pure (TyCon ratioTyConName)
        "Rational" -> pure rationalMonoType
        "String" -> pure stringMonoType
        "ShowS" -> pure (TyFun stringMonoType stringMonoType)
        "FilePath" -> pure filePathMonoType
        "[]" -> pure (TyCon listTyConName)
        "IO" -> pure (TyCon ioTyConName)
        "IOError" -> pure ioErrorMonoType
        "IOErrorType" -> pure ioErrorTypeMonoType
        "Handle" -> pure handleMonoType
        "HandlePosn" -> pure handlePosnMonoType
        "IOMode" -> pure ioModeMonoType
        "BufferMode" -> pure bufferModeMonoType
        "SeekMode" -> pure seekModeMonoType
        "ExitCode" -> pure exitCodeMonoType
        "Maybe" -> pure (TyCon maybeTyConName)
        "Either" -> pure (TyCon eitherTyConName)
        "Ordering" -> pure orderingMonoType
        "()" -> pure unitMonoType
        "Ptr" -> pure (TyCon ptrTyConName)
        "FunPtr" -> pure (TyCon funPtrTyConName)
        "StablePtr" -> pure (TyCon stablePtrTyConName)
        "ForeignPtr" -> pure (TyCon foreignPtrTyConName)
        "FinalizerPtr" -> pure (TyCon name)
        "FinalizerEnvPtr" -> pure (TyCon name)
        "Errno" -> pure (builtinForeignTypeMonoType "CInt")
        "CString" -> pure (TyApp (TyCon ptrTyConName) (builtinForeignTypeMonoType "CChar"))
        "CWString" -> pure (TyApp (TyCon ptrTyConName) (builtinForeignTypeMonoType "CWchar"))
        "CStringLen" -> pure (TyCon name)
        "CWStringLen" -> pure (TyCon name)
        other
          | isBuiltinForeignTypeOccurrence other -> pure (builtinForeignTypeMonoType other)
          | otherwise -> throwTypecheck (UnsupportedCore0 ("type constructor `" <> other <> "`"))

builtinTypeConstructorInfo :: RName -> Maybe TypeConstructorInfo
builtinTypeConstructorInfo name
  | not (nameExternal name) = Nothing
  | otherwise =
      typeConstructorInfo
        <$> case nameOcc name of
          "Int" -> Just 0
          "Integer" -> Just 0
          "Float" -> Just 0
          "Double" -> Just 0
          "Bool" -> Just 0
          "Char" -> Just 0
          other
            | Just _ <- fixedIntegralTypeByOccurrence other -> Just 0
          "Ratio" -> Just 1
          "Rational" -> Just 0
          "String" -> Just 0
          "ShowS" -> Just 0
          "ReadS" -> Just 1
          "FilePath" -> Just 0
          "[]" -> Just 1
          "IO" -> Just 1
          "IOError" -> Just 0
          "IOErrorType" -> Just 0
          "Handle" -> Just 0
          "HandlePosn" -> Just 0
          "IOMode" -> Just 0
          "BufferMode" -> Just 0
          "SeekMode" -> Just 0
          "ExitCode" -> Just 0
          "Maybe" -> Just 1
          "Either" -> Just 2
          "Ordering" -> Just 0
          "()" -> Just 0
          "FinalizerPtr" -> Just 1
          "FinalizerEnvPtr" -> Just 2
          "Errno" -> Just 0
          "CString" -> Just 0
          "CWString" -> Just 0
          "CStringLen" -> Just 0
          "CWStringLen" -> Just 0
          other -> builtinForeignTypeArity other

builtinForeignTypeArity :: Text -> Maybe Int
builtinForeignTypeArity occurrence
  | occurrence `Set.member` scalarForeignTypeOccurrences = Just 0
  | occurrence `Set.member` pointerForeignTypeOccurrences = Just 1
  | otherwise = Nothing

isBuiltinForeignTypeOccurrence :: Text -> Bool
isBuiltinForeignTypeOccurrence occurrence =
  occurrence `Set.member` scalarForeignTypeOccurrences
    || occurrence `Set.member` pointerForeignTypeOccurrences

builtinTypeSynonymInfo :: RName -> Maybe TypeSynonymInfo
builtinTypeSynonymInfo name
  | not (nameExternal name) = Nothing
  | otherwise =
      case nameOcc name of
        "ShowS" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyFun stringSourceType stringSourceType
              }
        "ReadS" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = [readSynonymA]
              , typeSynonymBody = RTyFun stringSourceType (RTyList (RTyTuple [RTyVar readSynonymA, stringSourceType]))
              }
        "Rational" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyApp (RTyCon (preludeTypeName "Ratio" (-120070))) (RTyCon (preludeTypeName "Integer" (-120002)))
              }
        "FilePath" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = stringSourceType
              }
        "FinalizerPtr" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = [finalizerA]
              , typeSynonymBody =
                  RTyApp
                    (RTyCon (preludeTypeName "FunPtr" (-120031)))
                    ( RTyFun
                        (RTyApp (RTyCon (preludeTypeName "Ptr" (-120030))) (RTyVar finalizerA))
                        (RTyApp (RTyCon (preludeTypeName "IO" (-120007))) (RTyTuple []))
                    )
              }
        "FinalizerEnvPtr" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = [finalizerEnv, finalizerA]
              , typeSynonymBody =
                  RTyApp
                    (RTyCon (preludeTypeName "FunPtr" (-120031)))
                    ( RTyFun
                        (RTyApp (RTyCon (preludeTypeName "Ptr" (-120030))) (RTyVar finalizerEnv))
                        ( RTyFun
                            (RTyApp (RTyCon (preludeTypeName "Ptr" (-120030))) (RTyVar finalizerA))
                            (RTyApp (RTyCon (preludeTypeName "IO" (-120007))) (RTyTuple []))
                        )
                    )
              }
        "CStringLen" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyTuple [RTyCon (preludeTypeName "CString" (-120011)), RTyCon (preludeTypeName "Int" (-120001))]
              }
        "CWStringLen" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyTuple [RTyCon (preludeTypeName "CWString" (-120012)), RTyCon (preludeTypeName "Int" (-120001))]
              }
        "Errno" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyCon (preludeTypeName "CInt" (-120041))
              }
        "CString" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyApp (RTyCon (preludeTypeName "Ptr" (-120030))) (RTyCon (preludeTypeName "CChar" (-120041)))
              }
        "CWString" ->
          Just
            TypeSynonymInfo
              { typeSynonymParams = []
              , typeSynonymBody = RTyApp (RTyCon (preludeTypeName "Ptr" (-120030))) (RTyCon (preludeTypeName "CWchar" (-120042)))
              }
        _ -> Nothing
 where
  readSynonymA = preludeTypeVariable "a" (-1569)
  finalizerA = preludeTypeVariable "a" (-1570)
  finalizerEnv = preludeTypeVariable "env" (-1571)
  stringSourceType = RTyCon (preludeTypeName "String" (-120010))

preludeTypeName :: Text -> Int -> RName
preludeTypeName occurrence unique =
  RName TypeNamespace occurrence unique True

scalarForeignTypeOccurrences :: Set.Set Text
scalarForeignTypeOccurrences =
  Set.fromList scalarForeignTypeOccurrenceList

scalarForeignTypeOccurrenceList :: [Text]
scalarForeignTypeOccurrenceList =
    [ "Int"
    , "Bool"
    , "Char"
    , "Float"
    , "Double"
    , "Int8"
    , "Int16"
    , "Int32"
    , "Int64"
    , "Word8"
    , "Word16"
    , "Word32"
    , "Word64"
    , "CChar"
    , "CSChar"
    , "CUChar"
    , "CShort"
    , "CUShort"
    , "CInt"
    , "CUInt"
    , "CLong"
    , "CULong"
    , "CLLong"
    , "CULLong"
    , "CFloat"
    , "CDouble"
    , "CPtrdiff"
    , "CSize"
    , "CWchar"
    , "CSigAtomic"
    , "CIntPtr"
    , "CUIntPtr"
    , "CIntMax"
    , "CUIntMax"
    , "CClock"
    , "CTime"
    , "CFile"
    , "CFpos"
    , "CJmpBuf"
    ]

pointerForeignTypeOccurrences :: Set.Set Text
pointerForeignTypeOccurrences =
  Set.fromList ["Ptr", "FunPtr", "StablePtr", "ForeignPtr"]

builtinForeignTypeMonoType :: Text -> MonoType
builtinForeignTypeMonoType occurrence =
  case foreignCTypeAlias occurrence of
    Just ty -> ty
    Nothing -> TyCon (builtinForeignTypeName occurrence)

foreignCTypeAlias :: Text -> Maybe MonoType
foreignCTypeAlias = \case
  "CChar" -> Just (fixedIntegralMonoType FixedInt8)
  "CSChar" -> Just (fixedIntegralMonoType FixedInt8)
  "CUChar" -> Just (fixedIntegralMonoType FixedWord8)
  "CShort" -> Just (fixedIntegralMonoType FixedInt16)
  "CUShort" -> Just (fixedIntegralMonoType FixedWord16)
  "CInt" -> Just (fixedIntegralMonoType FixedInt32)
  "CUInt" -> Just (fixedIntegralMonoType FixedWord32)
  "CLong" -> Just (fixedIntegralMonoType FixedInt64)
  "CULong" -> Just (fixedIntegralMonoType FixedWord64)
  "CLLong" -> Just (fixedIntegralMonoType FixedInt64)
  "CULLong" -> Just (fixedIntegralMonoType FixedWord64)
  "CFloat" -> Just floatMonoType
  "CDouble" -> Just doubleMonoType
  "CPtrdiff" -> Just (fixedIntegralMonoType FixedInt64)
  "CSize" -> Just (fixedIntegralMonoType FixedWord64)
  "CWchar" -> Just (fixedIntegralMonoType FixedInt32)
  "CSigAtomic" -> Just (fixedIntegralMonoType FixedInt32)
  "CIntPtr" -> Just (fixedIntegralMonoType FixedInt64)
  "CUIntPtr" -> Just (fixedIntegralMonoType FixedWord64)
  "CIntMax" -> Just (fixedIntegralMonoType FixedInt64)
  "CUIntMax" -> Just (fixedIntegralMonoType FixedWord64)
  "CClock" -> Just (fixedIntegralMonoType FixedInt64)
  "CTime" -> Just (fixedIntegralMonoType FixedInt64)
  _ -> Nothing

builtinForeignTypeName :: Text -> RName
builtinForeignTypeName occurrence =
  maybe (RName TypeNamespace occurrence (builtinForeignTypeUnique occurrence) True) fixedIntegralTypeName (fixedIntegralTypeByOccurrence occurrence)

builtinForeignTypeUnique :: Text -> Int
builtinForeignTypeUnique occurrence =
  case List.elemIndex occurrence scalarForeignTypeOccurrenceList of
    Just index -> -121000 - index
    Nothing -> -121999

fixedIntegralMonoType :: FixedIntegral -> MonoType
fixedIntegralMonoType =
  coreTypeToMono . fixedIntegralTy

instantiate :: Scheme -> InferM (MonoType, [MonoType])
instantiate (Scheme variables _ body) = do
  replacements <- traverse (\name -> (name,) <$> freshMeta) variables
  let replacementMap = Map.fromList replacements
      instantiated = replaceTypeVars replacementMap body
  pure (instantiated, map snd replacements)

data Generalized = Generalized
  { generalizedScheme :: Scheme
  , generalizedMetas :: Map.Map Int RName
  }
  deriving stock (Show, Eq, Ord)

generalize :: TypeEnv -> [ClassConstraint] -> MonoType -> InferM Generalized
generalize env constraints ty = do
  subst <- substitution <$> get
  let zonked = applySubst subst ty
      zonkedConstraints = List.nub (map (applyConstraintSubst subst) constraints)
      envMetas = freeMetaVarsEnv env
      metasSet = freeMetaVars zonked `Set.difference` envMetas
      metas = Set.toAscList metasSet
      retainedConstraints =
        [ constraint
        | constraint <- zonkedConstraints
        , let constraintMetas = freeMetaVarsConstraint constraint
        , not (Set.null constraintMetas)
        , constraintMetas `Set.isSubsetOf` metasSet
        ]
  names <- traverse freshTypeVariableName metas
  let metaMap = Map.fromList (zip metas names)
      generalizedTy = replaceMetasWithVars metaMap zonked
      generalizedConstraints = map (replaceConstraintMetasWithVars metaMap) retainedConstraints
  pure
    Generalized
      { generalizedScheme = Scheme names generalizedConstraints generalizedTy
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
    (TyApp (TyCon lhsName) lhsArg, TyList rhsElement)
      | lhsName == listTyConName -> unify lhsArg rhsElement
    (TyList lhsElement, TyApp (TyCon rhsName) rhsArg)
      | rhsName == listTyConName -> unify lhsElement rhsArg
    (TyApp (TyMeta meta) lhsArg, TyList rhsElement) -> do
      bindMeta meta (TyCon listTyConName)
      unify lhsArg rhsElement
    (TyList lhsElement, TyApp (TyMeta meta) rhsArg) -> do
      bindMeta meta (TyCon listTyConName)
      unify lhsElement rhsArg
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
    normalizeListTypeApplication (TyApp (applySubst subst fn) (applySubst subst arg))
  TyFun arg result ->
    TyFun (applySubst subst arg) (applySubst subst result)
  TyTuple fields ->
    TyTuple (map (applySubst subst) fields)
  TyList elementType ->
    TyList (applySubst subst elementType)

normalizeListTypeApplication :: MonoType -> MonoType
normalizeListTypeApplication = \case
  TyApp (TyCon name) elementTy
    | name == listTyConName -> TyList elementTy
  ty -> ty

freeMetaVarsEnv :: TypeEnv -> Set.Set Int
freeMetaVarsEnv =
  Set.unions . map freeMetaVarsScheme . Map.elems

freeMetaVarsScheme :: Scheme -> Set.Set Int
freeMetaVarsScheme (Scheme _ constraints ty) =
  Set.unions (map freeMetaVarsConstraint constraints) <> freeMetaVars ty

freeMetaVarsConstraint :: ClassConstraint -> Set.Set Int
freeMetaVarsConstraint =
  Set.unions . map freeMetaVars . classConstraintArguments

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

constraintTypeVars :: ClassConstraint -> [RName]
constraintTypeVars =
  List.nub . concatMap typeVars . classConstraintArguments

replaceTypeVars :: Map.Map RName MonoType -> MonoType -> MonoType
replaceTypeVars replacements = \case
  TyMeta meta -> TyMeta meta
  TyVar name -> Map.findWithDefault (TyVar name) name replacements
  TyCon name -> TyCon name
  TyApp fn arg -> normalizeListTypeApplication (TyApp (replaceTypeVars replacements fn) (replaceTypeVars replacements arg))
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
    normalizeListTypeApplication (TyApp (replaceMetasWithVars replacements fn) (replaceMetasWithVars replacements arg))
  TyFun arg result ->
    TyFun (replaceMetasWithVars replacements arg) (replaceMetasWithVars replacements result)
  TyTuple fields ->
    TyTuple (map (replaceMetasWithVars replacements) fields)
  TyList elementType ->
    TyList (replaceMetasWithVars replacements elementType)

replaceConstraintMetasWithVars :: Map.Map Int RName -> ClassConstraint -> ClassConstraint
replaceConstraintMetasWithVars replacements =
  mapClassConstraintArguments (replaceMetasWithVars replacements)

preludeCoreBindings :: [RName] -> Either TypecheckError [CoreBind]
preludeCoreBindings names =
  pure $
    case pairs of
      [] -> []
      _ -> [CoreRec pairs]
 where
  expandedNames = preludeCoreDependencyClosure names
  pairs =
    [ pair
    | name <- expandedNames
    , pair <- maybe [] (: []) (preludeCorePair name)
    ]
      <> [reverseGoCorePair | any ((== "reverse") . nameOcc) expandedNames]

preludeCoreDependencies :: RName -> [RName]
preludeCoreDependencies name =
  case nameOcc name of
    "lex" -> readSupportPreludeNames
    "read" -> readSupportPreludeNames
    "readIO" -> readSupportPreludeNames
    "readLn" -> preludeTermName "readIO" (-3185) : readSupportPreludeNames
    "readParen" -> readSupportPreludeNames
    "%" -> ratioSupportPreludeNames
    "approxRational" -> ratioSupportPreludeNames
    "newArray" -> [standardLibraryTermName "pokeArray"]
    "pokeArray0" -> [standardLibraryTermName "pokeArray"]
    "newArray0" -> [standardLibraryTermName "pokeArray0"]
    "withArray" -> [standardLibraryTermName "newArray"]
    "withArray0" -> [standardLibraryTermName "newArray0"]
    "withArrayLen" -> [standardLibraryTermName "withArray"]
    "withArrayLen0" -> [standardLibraryTermName "withArray0"]
    "throwErrnoIfRetry_" -> [standardLibraryTermName "throwErrnoIfRetry"]
    "throwErrnoIfMinus1Retry_" -> [standardLibraryTermName "throwErrnoIfMinus1Retry"]
    "throwErrnoIfRetryMayBlock_" -> [standardLibraryTermName "throwErrnoIfRetryMayBlock"]
    "throwErrnoIfMinus1RetryMayBlock_" -> [standardLibraryTermName "throwErrnoIfMinus1RetryMayBlock"]
    occurrence
      | "$read_" `Text.isPrefixOf` occurrence -> []
      | "$ratio_" `Text.isPrefixOf` occurrence -> []
    _ -> []

preludeCoreDependencyClosure :: [RName] -> [RName]
preludeCoreDependencyClosure =
  go []
 where
  go seen [] =
    List.nub (reverse seen)
  go seen (name : rest)
    | name `elem` seen = go seen rest
    | otherwise = go (name : seen) (preludeCoreDependencies name <> rest)

classPreludeSupportNames :: Map.Map RName ClassInfo -> [RName]
classPreludeSupportNames classes =
  enumSupport <> ixSupport <> readSupport <> ratioSupport
 where
  enumSupport
    | builtinEnumClassName `Map.member` classes = derivedMapName : arithmeticSequencePreludeNames
    | otherwise = []
  ixSupport
    | builtinIxClassName `Map.member` classes = derivedMapName : arithmeticSequencePreludeNames
    | otherwise = []
  readSupport
    | builtinReadClassName `Map.member` classes = readSupportPreludeNames
    | otherwise = []
  ratioSupport
    | any (`Map.member` classes) [builtinEqClassName, builtinOrdClassName, builtinNumClassName, builtinRealClassName, builtinShowClassName, builtinReadClassName] = ratioSupportPreludeNames
    | otherwise = []

preludeCorePair :: RName -> Maybe (CoreBinder, CoreExpr)
preludeCorePair name =
  case nameOcc name of
    "id" -> Just (binderFor name idTy, CTypeLam [a] (lam idX aTy (var idX aTy)) idTy)
    "const" ->
      Just
        ( binderFor name constTy
        , CTypeLam [a, b] (lam constX aTy (lam constY bTy (var constX aTy))) constTy
        )
    "not" ->
      Just
        ( binderFor name notTy
        , lam notX boolTy $
            boolCase
              (var notX boolTy)
              notCase
              boolTy
              (con falseDataConName boolTy)
              (con trueDataConName boolTy)
        )
    "otherwise" ->
      Just (binderFor name boolTy, con trueDataConName boolTy)
    "$" ->
      Just (binderFor name dollarTy, dollarRhs)
    "." ->
      Just (binderFor name composeTy, composeRhs)
    "flip" ->
      Just (binderFor name flipTy, flipRhs)
    "map" ->
      Just (binderFor name mapTy, mapRhs name)
    "foldr" ->
      Just (binderFor name foldrTy, foldrRhs name)
    "foldl" ->
      Just (binderFor name foldlTy, foldlRhs name)
    "head" ->
      Just (binderFor name headTy, headRhs)
    "tail" ->
      Just (binderFor name tailTy, tailRhs)
    "null" ->
      Just (binderFor name nullTy, nullRhs)
    "fst" ->
      Just (binderFor name fstTy, fstRhs)
    "snd" ->
      Just (binderFor name sndTy, sndRhs)
    "length" ->
      Just (binderFor name lengthTy, lengthRhs name)
    "filter" ->
      Just (binderFor name filterTy, filterRhs name)
    "reverse" ->
      Just (binderFor name reverseTy, reverseRhs)
    "++" ->
      Just (binderFor name appendTy, appendRhs name)
    "shows" ->
      Just (binderFor name showsTy, showsRhs)
    "reads" ->
      Just (binderFor name readsTy, readsRhs)
    "read" ->
      Just (binderFor name readTy, readRhs)
    "lex" ->
      Just (binderFor name lexTy, CVar readLexName lexTy)
    "readParen" ->
      Just (binderFor name readParenTy, CVar readParenName readParenTy)
    "%" ->
      Just (binderFor name ratioPercentCoreType, CVar ratioReduceName ratioPercentCoreType)
    "numerator" ->
      Just (binderFor name ratioAccessorCoreType, ratioNumeratorRhs)
    "denominator" ->
      Just (binderFor name ratioAccessorCoreType, ratioDenominatorRhs)
    "approxRational" ->
      Just (binderFor name ratioApproxRationalCoreType, ratioApproxRationalRhs)
    "fixIO" ->
      Just (binderFor name fixIOTy, fixIORhs)
    "stdin" ->
      Just (binderFor name handleTy, CPrimOp (PrimStdHandle StdInHandle) [] handleTy)
    "stdout" ->
      Just (binderFor name handleTy, CPrimOp (PrimStdHandle StdOutHandle) [] handleTy)
    "stderr" ->
      Just (binderFor name handleTy, CPrimOp (PrimStdHandle StdErrHandle) [] handleTy)
    "withFile" ->
      Just (binderFor name withFileTy, withFileRhs)
    "openFile" ->
      Just (binderFor name openFileTy, lam ioFilePath stringTy (lam ioMode ioModeTy (CPrimOp PrimOpenFile [var ioFilePath stringTy, var ioMode ioModeTy] (ioTy handleTy))))
    "hClose" ->
      Just (binderFor name hCloseTy, lam ioHandle handleTy (CPrimOp PrimHClose [var ioHandle handleTy] ioUnitTy))
    "readFile" ->
      Just (binderFor name readFileTy, lam ioFilePath stringTy (CPrimOp PrimReadFile [var ioFilePath stringTy] (ioTy stringTy)))
    "writeFile" ->
      Just (binderFor name writeFileTy, lam ioFilePath stringTy (lam ioString stringTy (CPrimOp PrimWriteFile [var ioFilePath stringTy, var ioString stringTy] ioUnitTy)))
    "appendFile" ->
      Just (binderFor name appendFileTy, lam ioFilePath stringTy (lam ioString stringTy (CPrimOp PrimAppendFile [var ioFilePath stringTy, var ioString stringTy] ioUnitTy)))
    "hFileSize" ->
      Just (binderFor name hFileSizeTy, lam ioHandle handleTy (CPrimOp PrimHFileSize [var ioHandle handleTy] (ioTy intTy)))
    "hSetFileSize" ->
      Just (binderFor name hSetFileSizeTy, lam ioHandle handleTy (lam ioInt intTy (CPrimOp PrimHSetFileSize [var ioHandle handleTy, var ioInt intTy] ioUnitTy)))
    "hIsEOF" ->
      Just (binderFor name hIsEOFTy, lam ioHandle handleTy (CPrimOp PrimHIsEOF [var ioHandle handleTy] (ioTy boolTy)))
    "isEOF" ->
      Just (binderFor name isEOFTy, CPrimOp PrimHIsEOF [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] (ioTy boolTy))
    "hSetBuffering" ->
      Just (binderFor name hSetBufferingTy, lam ioHandle handleTy (lam ioBufferMode bufferModeTy (CPrimOp PrimHSetBuffering [var ioHandle handleTy, var ioBufferMode bufferModeTy] ioUnitTy)))
    "hGetBuffering" ->
      Just (binderFor name hGetBufferingTy, lam ioHandle handleTy (CPrimOp PrimHGetBuffering [var ioHandle handleTy] (ioTy bufferModeTy)))
    "hFlush" ->
      Just (binderFor name hCloseTy, lam ioHandle handleTy (CPrimOp PrimHFlush [var ioHandle handleTy] ioUnitTy))
    "hGetPosn" ->
      Just (binderFor name hGetPosnTy, lam ioHandle handleTy (CPrimOp PrimHGetPosn [var ioHandle handleTy] (ioTy handlePosnTy)))
    "hSetPosn" ->
      Just (binderFor name hSetPosnTy, lam ioPosn handlePosnTy (CPrimOp PrimHSetPosn [var ioPosn handlePosnTy] ioUnitTy))
    "hSeek" ->
      Just (binderFor name hSeekTy, lam ioHandle handleTy (lam ioSeekMode seekModeTy (lam ioInt intTy (CPrimOp PrimHSeek [var ioHandle handleTy, var ioSeekMode seekModeTy, var ioInt intTy] ioUnitTy))))
    "hTell" ->
      Just (binderFor name hTellTy, lam ioHandle handleTy (CPrimOp PrimHTell [var ioHandle handleTy] (ioTy intTy)))
    "hIsOpen" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsOpen [var ioHandle handleTy] (ioTy boolTy)))
    "hIsClosed" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsClosed [var ioHandle handleTy] (ioTy boolTy)))
    "hIsReadable" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsReadable [var ioHandle handleTy] (ioTy boolTy)))
    "hIsWritable" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsWritable [var ioHandle handleTy] (ioTy boolTy)))
    "hIsSeekable" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsSeekable [var ioHandle handleTy] (ioTy boolTy)))
    "hIsTerminalDevice" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHIsTerminalDevice [var ioHandle handleTy] (ioTy boolTy)))
    "hSetEcho" ->
      Just (binderFor name hSetEchoTy, lam ioHandle handleTy (lam ioBool boolTy (CPrimOp PrimHSetEcho [var ioHandle handleTy, var ioBool boolTy] ioUnitTy)))
    "hGetEcho" ->
      Just (binderFor name hHandleBoolTy, lam ioHandle handleTy (CPrimOp PrimHGetEcho [var ioHandle handleTy] (ioTy boolTy)))
    "hShow" ->
      Just (binderFor name hShowTy, lam ioHandle handleTy (CPrimOp PrimHShow [var ioHandle handleTy] (ioTy stringTy)))
    "hWaitForInput" ->
      Just (binderFor name hWaitForInputTy, lam ioHandle handleTy (lam ioInt intTy (CPrimOp PrimHWaitForInput [var ioHandle handleTy, var ioInt intTy] (ioTy boolTy))))
    "hReady" ->
      Just (binderFor name hReadyTy, lam ioHandle handleTy (CPrimOp PrimHReady [var ioHandle handleTy] (ioTy boolTy)))
    "hGetChar" ->
      Just (binderFor name hGetCharTy, lam ioHandle handleTy (CPrimOp PrimHGetChar [var ioHandle handleTy] (ioTy charTy)))
    "hGetLine" ->
      Just (binderFor name hGetLineTy, lam ioHandle handleTy (CPrimOp PrimHGetLine [var ioHandle handleTy] (ioTy stringTy)))
    "hLookAhead" ->
      Just (binderFor name hGetCharTy, lam ioHandle handleTy (CPrimOp PrimHLookAhead [var ioHandle handleTy] (ioTy charTy)))
    "hGetContents" ->
      Just (binderFor name hGetLineTy, lam ioHandle handleTy (CPrimOp PrimHGetContents [var ioHandle handleTy] (ioTy stringTy)))
    "hPutChar" ->
      Just (binderFor name hPutCharTy, lam ioHandle handleTy (lam ioChar charTy (CPrimOp PrimHPutChar [var ioHandle handleTy, var ioChar charTy] ioUnitTy)))
    "hPutStr" ->
      Just (binderFor name hPutStrTy, lam ioHandle handleTy (lam ioString stringTy (CPrimOp PrimHPutStr [var ioHandle handleTy, var ioString stringTy] ioUnitTy)))
    "hPutStrLn" ->
      Just (binderFor name hPutStrTy, lam ioHandle handleTy (lam ioString stringTy (CPrimOp PrimHPutStrLn [var ioHandle handleTy, var ioString stringTy] ioUnitTy)))
    "hPrint" ->
      Just (binderFor name hPrintTy, hPrintRhs)
    "interact" ->
      Just (binderFor name interactTy, interactRhs)
    "putChar" ->
      Just (binderFor name putCharTy, lam ioChar charTy (CPrimOp PrimHPutChar [CPrimOp (PrimStdHandle StdOutHandle) [] handleTy, var ioChar charTy] ioUnitTy))
    "putStr" ->
      Just (binderFor name putStrTy, lam ioString stringTy (CPrimOp PrimHPutStr [CPrimOp (PrimStdHandle StdOutHandle) [] handleTy, var ioString stringTy] ioUnitTy))
    "putStrLn" ->
      Just
        ( binderFor name putStrLnTy
        , lam putStrLnS stringTy (CPrimOp PrimHPutStrLn [CPrimOp (PrimStdHandle StdOutHandle) [] handleTy, var putStrLnS stringTy] ioUnitTy)
        )
    "getChar" ->
      Just (binderFor name getCharTy, CPrimOp PrimHGetChar [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] getCharTy)
    "getLine" ->
      Just (binderFor name getLineTy, CPrimOp PrimHGetLine [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] getLineTy)
    "getContents" ->
      Just (binderFor name getLineTy, CPrimOp PrimHGetContents [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] getLineTy)
    "getArgs" ->
      Just (binderFor name getArgsTy, CPrimOp PrimGetArgs [] getArgsTy)
    "getProgName" ->
      Just (binderFor name getProgNameTy, CPrimOp PrimGetProgName [] getProgNameTy)
    "getEnv" ->
      Just (binderFor name getEnvTy, lam getEnvNameValue stringTy (CPrimOp PrimGetEnv [var getEnvNameValue stringTy] getProgNameTy))
    "exitWith" ->
      Just (binderFor name exitWithTy, CTypeLam [a] (lam exitWithCode exitCodeTy (CPrimOp PrimExitWith [var exitWithCode exitCodeTy] ioA)) exitWithTy)
    "exitFailure" ->
      Just (binderFor name exitFailureTy, CTypeLam [a] (CPrimOp PrimExitWith [exitFailureOne] ioA) exitFailureTy)
    "exitSuccess" ->
      Just (binderFor name exitSuccessTy, CTypeLam [a] (CPrimOp PrimExitWith [CCon exitSuccessDataConName exitCodeTy] ioA) exitSuccessTy)
    "print" ->
      Just (binderFor name printTy, printRhs)
    "readIO" ->
      Just (binderFor name readIOTy, readIORhs)
    "readLn" ->
      Just (binderFor name readLnTy, readLnRhs)
    "userError" ->
      Just (binderFor name userErrorTy, userErrorRhs)
    "mkIOError" ->
      Just (binderFor name mkIOErrorTy, mkIOErrorRhs)
    "annotateIOError" ->
      Just (binderFor name annotateIOErrorTy, annotateIOErrorRhs)
    "isAlreadyExistsError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorAlreadyExistsTypeDataConName "$is_already_exists_error" (-3300))
    "isDoesNotExistError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorDoesNotExistTypeDataConName "$is_does_not_exist_error" (-3310))
    "isAlreadyInUseError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorAlreadyInUseTypeDataConName "$is_already_in_use_error" (-3320))
    "isFullError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorFullTypeDataConName "$is_full_error" (-3330))
    "isEOFError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorEOFTypeDataConName "$is_eof_error" (-3340))
    "isIllegalOperation" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorIllegalOperationTypeDataConName "$is_illegal_operation" (-3350))
    "isPermissionError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorPermissionTypeDataConName "$is_permission_error" (-3360))
    "isUserError" ->
      Just (binderFor name ioErrorPredicateTy, ioErrorPredicateRhs ioErrorUserTypeDataConName "$is_user_error" (-3370))
    "ioeGetErrorString" ->
      Just (binderFor name ioeGetErrorStringTy, ioErrorAccessorRhs stringTy ioErrorStringField "$ioe_get_error_string" (-3380))
    "ioeGetHandle" ->
      Just (binderFor name ioeGetHandleTy, ioErrorAccessorRhs maybeHandleTy ioErrorHandleField "$ioe_get_handle" (-3390))
    "ioeGetFileName" ->
      Just (binderFor name ioeGetFileNameTy, ioErrorAccessorRhs maybeFilePathTy ioErrorFilePathField "$ioe_get_file_name" (-3400))
    "alreadyExistsErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorAlreadyExistsTypeDataConName ioErrorTypeTy)
    "doesNotExistErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorDoesNotExistTypeDataConName ioErrorTypeTy)
    "alreadyInUseErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorAlreadyInUseTypeDataConName ioErrorTypeTy)
    "fullErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorFullTypeDataConName ioErrorTypeTy)
    "eofErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorEOFTypeDataConName ioErrorTypeTy)
    "illegalOperationErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorIllegalOperationTypeDataConName ioErrorTypeTy)
    "permissionErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorPermissionTypeDataConName ioErrorTypeTy)
    "userErrorType" ->
      Just (binderFor name ioErrorTypeTy, CCon ioErrorUserTypeDataConName ioErrorTypeTy)
    "ioError" ->
      Just (binderFor name ioErrorTy_, ioErrorRhs)
    "catch" ->
      Just (binderFor name catchTy, catchRhs)
    "try" ->
      Just (binderFor name tryTy, tryRhs)
    "nullPtr" ->
      Just (binderFor name nullPtrTy, CTypeLam [a] (CPrimOp PrimNullPtr [] ptrA) nullPtrTy)
    "castPtr" ->
      Just (binderFor name castPtrTy, CTypeLam [a, b] (lam ptrCastValue ptrA (CPrimOp PrimCastPtr [var ptrCastValue ptrA] ptrB)) castPtrTy)
    "nullFunPtr" ->
      Just (binderFor name nullFunPtrTy, CTypeLam [a] (CPrimOp PrimNullPtr [] funPtrA) nullFunPtrTy)
    "castFunPtr" ->
      Just (binderFor name castFunPtrTy, CTypeLam [a, b] (lam funPtrCastValue funPtrA (CPrimOp PrimCastPtr [var funPtrCastValue funPtrA] funPtrB)) castFunPtrTy)
    "castFunPtrToPtr" ->
      Just (binderFor name castFunPtrToPtrTy, CTypeLam [a, b] (lam funPtrToPtrValue funPtrA (CPrimOp PrimCastPtr [var funPtrToPtrValue funPtrA] ptrB)) castFunPtrToPtrTy)
    "castPtrToFunPtr" ->
      Just (binderFor name castPtrToFunPtrTy, CTypeLam [a, b] (lam ptrToFunPtrValue ptrA (CPrimOp PrimCastPtr [var ptrToFunPtrValue ptrA] funPtrB)) castPtrToFunPtrTy)
    "freeHaskellFunPtr" ->
      Just
        ( binderFor name freeHaskellFunPtrTy
        , CTypeLam [a] (lam freeHaskellFunPtrValue funPtrA (CPrimOp PrimFreeHaskellFunPtr [var freeHaskellFunPtrValue funPtrA] ioUnitTy)) freeHaskellFunPtrTy
        )
    "newStablePtr" ->
      Just
        ( binderFor name newStablePtrTy
        , CTypeLam [a] (lam stablePtrNewValue aTy (CPrimOp PrimNewStablePtr [var stablePtrNewValue aTy] (ioTy stablePtrA))) newStablePtrTy
        )
    "deRefStablePtr" ->
      Just
        ( binderFor name deRefStablePtrTy
        , CTypeLam [a] (lam stablePtrDeRefValue stablePtrA (CPrimOp PrimDeRefStablePtr [var stablePtrDeRefValue stablePtrA] (ioTy aTy))) deRefStablePtrTy
        )
    "freeStablePtr" ->
      Just
        ( binderFor name freeStablePtrTy
        , CTypeLam [a] (lam stablePtrFreeValue stablePtrA (CPrimOp PrimFreeStablePtr [var stablePtrFreeValue stablePtrA] ioUnitTy)) freeStablePtrTy
        )
    "castStablePtrToPtr" ->
      Just
        ( binderFor name castStablePtrToPtrTy
        , CTypeLam [a] (lam stablePtrCastValue stablePtrA (CPrimOp PrimCastStablePtrToPtr [var stablePtrCastValue stablePtrA] ptrUnitTy)) castStablePtrToPtrTy
        )
    "castPtrToStablePtr" ->
      Just
        ( binderFor name castPtrToStablePtrTy
        , CTypeLam [a] (lam stablePtrCastRawValue ptrUnitTy (CPrimOp PrimCastPtrToStablePtr [var stablePtrCastRawValue ptrUnitTy] stablePtrA)) castPtrToStablePtrTy
        )
    "newForeignPtr" ->
      Just
        ( binderFor name newForeignPtrTy
        , CTypeLam [a] (lam foreignPtrNewFinalizerValue finalizerPtrA (lam foreignPtrNewRawValue ptrA (CPrimOp PrimNewForeignPtr [var foreignPtrNewFinalizerValue finalizerPtrA, var foreignPtrNewRawValue ptrA] (ioTy foreignPtrA)))) newForeignPtrTy
        )
    "newForeignPtr_" ->
      Just
        ( binderFor name newForeignPtrTy_
        , CTypeLam [a] (lam foreignPtrNewRawValue_ ptrA (CPrimOp PrimNewForeignPtr_ [var foreignPtrNewRawValue_ ptrA] (ioTy foreignPtrA))) newForeignPtrTy_
        )
    "addForeignPtrFinalizer" ->
      Just
        ( binderFor name addForeignPtrFinalizerTy
        , CTypeLam [a] (lam foreignPtrAddFinalizerValue finalizerPtrA (lam foreignPtrAddValue foreignPtrA (CPrimOp PrimAddForeignPtrFinalizer [var foreignPtrAddFinalizerValue finalizerPtrA, var foreignPtrAddValue foreignPtrA] ioUnitTy))) addForeignPtrFinalizerTy
        )
    "finalizeForeignPtr" ->
      Just
        ( binderFor name finalizeForeignPtrTy
        , CTypeLam [a] (lam foreignPtrFinalizeValue foreignPtrA (CPrimOp PrimFinalizeForeignPtr [var foreignPtrFinalizeValue foreignPtrA] ioUnitTy)) finalizeForeignPtrTy
        )
    "unsafeForeignPtrToPtr" ->
      Just
        ( binderFor name unsafeForeignPtrToPtrTy
        , CTypeLam [a] (lam foreignPtrUnsafeValue foreignPtrA (CPrimOp PrimUnsafeForeignPtrToPtr [var foreignPtrUnsafeValue foreignPtrA] ptrA)) unsafeForeignPtrToPtrTy
        )
    "withForeignPtr" ->
      Just
        ( binderFor name withForeignPtrTy
        , CTypeLam [a, b] (lam foreignPtrWithValue foreignPtrA (lam withForeignPtrK (CTyFun ptrA (ioTy bTy)) (CPrimOp PrimWithForeignPtr [var foreignPtrWithValue foreignPtrA, var withForeignPtrK (CTyFun ptrA (ioTy bTy))] (ioTy bTy)))) withForeignPtrTy
        )
    "touchForeignPtr" ->
      Just
        ( binderFor name touchForeignPtrTy
        , CTypeLam [a] (lam foreignPtrTouchValue foreignPtrA (CPrimOp PrimTouchForeignPtr [var foreignPtrTouchValue foreignPtrA] ioUnitTy)) touchForeignPtrTy
        )
    "castForeignPtr" ->
      Just
        ( binderFor name castForeignPtrTy
        , CTypeLam [a, b] (lam foreignPtrCastValue foreignPtrA (CPrimOp PrimCastForeignPtr [var foreignPtrCastValue foreignPtrA] foreignPtrB)) castForeignPtrTy
        )
    "throwIf" ->
      Just (binderFor name throwIfTy, throwIfRhs)
    "throwIf_" ->
      Just (binderFor name throwIfUnitTy, throwIfUnitRhs)
    "throwIfNull" ->
      Just (binderFor name throwIfNullTy, throwIfNullRhs)
    "void" ->
      controlMonadCorePair name
    "maybeNew" ->
      Just (binderFor name maybeNewTy, maybeNewRhs)
    "maybeWith" ->
      Just (binderFor name maybeWithTy, maybeWithRhs)
    "maybePeek" ->
      Just (binderFor name maybePeekTy, maybePeekRhs)
    "plusPtr" ->
      Just (binderFor name plusPtrTy, CTypeLam [a, b] (lam ptrPlusValue ptrA (lam ptrPlusOffset intTy (CPrimOp PrimPtrPlus [var ptrPlusValue ptrA, var ptrPlusOffset intTy] ptrB))) plusPtrTy)
    "minusPtr" ->
      Just (binderFor name minusPtrTy, CTypeLam [a, b] (lam ptrMinusLeft ptrA (lam ptrMinusRight ptrB (CPrimOp PrimPtrMinus [var ptrMinusLeft ptrA, var ptrMinusRight ptrB] intTy))) minusPtrTy)
    "alignPtr" ->
      Just (binderFor name alignPtrTy, CTypeLam [a] (lam ptrAlignValue ptrA (lam ptrAlignOffset intTy (CPrimOp PrimPtrAlign [var ptrAlignValue ptrA, var ptrAlignOffset intTy] ptrA))) alignPtrTy)
    "malloc" ->
      Just (binderFor name mallocTy, mallocRhs)
    "mallocBytes" ->
      Just (binderFor name mallocBytesTy, CTypeLam [a] (lam mallocBytesSize intTy (CPrimOp PrimMallocBytes [var mallocBytesSize intTy] (ioTy ptrA))) mallocBytesTy)
    "alloca" ->
      Just (binderFor name allocaTy, allocaRhs)
    "allocaBytes" ->
      Just (binderFor name allocaBytesTy, allocaBytesRhs)
    "realloc" ->
      Just (binderFor name reallocTy, reallocRhs)
    "reallocBytes" ->
      Just (binderFor name reallocBytesTy, CTypeLam [a] (lam reallocBytesPointer ptrA (lam reallocBytesSize intTy (CPrimOp PrimReallocBytes [var reallocBytesPointer ptrA, var reallocBytesSize intTy] (ioTy ptrA)))) reallocBytesTy)
    "free" ->
      Just (binderFor name freeTy, CTypeLam [a] (lam freePointer ptrA (CPrimOp PrimFree [var freePointer ptrA] ioUnitTy)) freeTy)
    "finalizerFree" ->
      Just (binderFor name finalizerFreeTy, CTypeLam [a] (CPrimOp PrimFinalizerFree [] finalizerPtrA) finalizerFreeTy)
    "advancePtr" ->
      Just (binderFor name advancePtrTy, advancePtrRhs)
    "mallocArray" ->
      Just (binderFor name mallocArrayTy, mallocArrayRhs 0)
    "mallocArray0" ->
      Just (binderFor name mallocArrayTy, mallocArrayRhs 1)
    "allocaArray" ->
      Just (binderFor name allocaArrayTy, allocaArrayRhs 0)
    "allocaArray0" ->
      Just (binderFor name allocaArrayTy, allocaArrayRhs 1)
    "reallocArray" ->
      Just (binderFor name reallocArrayTy, reallocArrayRhs 0)
    "reallocArray0" ->
      Just (binderFor name reallocArrayTy, reallocArrayRhs 1)
    "peekArray" ->
      Just (binderFor name peekArrayTy, peekArrayRhs name)
    "peekArray0" ->
      Just (binderFor name peekArray0Ty, peekArray0Rhs name)
    "pokeArray" ->
      Just (binderFor name pokeArrayTy, pokeArrayRhs name)
    "pokeArray0" ->
      Just (binderFor name pokeArray0Ty, pokeArray0Rhs)
    "newArray" ->
      Just (binderFor name newArrayTy, newArrayRhs)
    "newArray0" ->
      Just (binderFor name newArray0Ty, newArray0Rhs)
    "withArray" ->
      Just (binderFor name withArrayTy, withArrayRhs)
    "withArray0" ->
      Just (binderFor name withArray0Ty, withArray0Rhs)
    "withArrayLen" ->
      Just (binderFor name withArrayLenTy, withArrayLenRhs)
    "withArrayLen0" ->
      Just (binderFor name withArrayLen0Ty, withArrayLen0Rhs)
    "copyArray" ->
      Just (binderFor name copyArrayTy, copyArrayRhs PrimCopyBytes)
    "moveArray" ->
      Just (binderFor name copyArrayTy, copyArrayRhs PrimMoveBytes)
    "lengthArray0" ->
      Just (binderFor name lengthArray0Ty, lengthArray0Rhs name)
    "copyBytes" ->
      Just (binderFor name copyBytesTy, CTypeLam [a, b] (lam copyDest ptrA (lam copySource ptrB (lam copyCount intTy (CPrimOp PrimCopyBytes [var copyDest ptrA, var copySource ptrB, var copyCount intTy] ioUnitTy)))) copyBytesTy)
    "moveBytes" ->
      Just (binderFor name copyBytesTy, CTypeLam [a, b] (lam copyDest ptrA (lam copySource ptrB (lam copyCount intTy (CPrimOp PrimMoveBytes [var copyDest ptrA, var copySource ptrB, var copyCount intTy] ioUnitTy)))) copyBytesTy)
    "peekCString" ->
      Just (binderFor name peekCStringTy, lam cStringPointer cStringTy (CPrimOp PrimPeekCString [var cStringPointer cStringTy] (ioTy stringTy)))
    "peekCStringLen" ->
      Just (binderFor name peekCStringLenTy, peekCStringLenRhs PrimPeekCStringLen cStringTy)
    "newCString" ->
      Just (binderFor name newCStringTy, lam cStringSource stringTy (CPrimOp PrimNewCString [var cStringSource stringTy] (ioTy cStringTy)))
    "newCStringLen" ->
      Just (binderFor name newCStringLenTy, newCStringLenRhs PrimNewCString cStringTy cStringLenTy)
    "withCString" ->
      Just (binderFor name withCStringTy, withCStringRhs cStringTy)
    "withCStringLen" ->
      Just (binderFor name withCStringLenTy, withCStringLenRhs cStringLenTy cStringTy)
    "peekCAString" ->
      Just (binderFor name peekCStringTy, lam cStringPointer cStringTy (CPrimOp PrimPeekCString [var cStringPointer cStringTy] (ioTy stringTy)))
    "peekCAStringLen" ->
      Just (binderFor name peekCStringLenTy, peekCStringLenRhs PrimPeekCStringLen cStringTy)
    "newCAString" ->
      Just (binderFor name newCStringTy, lam cStringSource stringTy (CPrimOp PrimNewCString [var cStringSource stringTy] (ioTy cStringTy)))
    "newCAStringLen" ->
      Just (binderFor name newCStringLenTy, newCStringLenRhs PrimNewCString cStringTy cStringLenTy)
    "withCAString" ->
      Just (binderFor name withCStringTy, withCStringRhs cStringTy)
    "withCAStringLen" ->
      Just (binderFor name withCStringLenTy, withCStringLenRhs cStringLenTy cStringTy)
    "peekCWString" ->
      Just (binderFor name peekCWStringTy, lam cWStringPointer cWStringTy (CPrimOp PrimPeekCWString [var cWStringPointer cWStringTy] (ioTy stringTy)))
    "peekCWStringLen" ->
      Just (binderFor name peekCWStringLenTy, peekCStringLenRhs PrimPeekCWStringLen cWStringTy)
    "newCWString" ->
      Just (binderFor name newCWStringTy, lam cStringSource stringTy (CPrimOp PrimNewCWString [var cStringSource stringTy] (ioTy cWStringTy)))
    "newCWStringLen" ->
      Just (binderFor name newCWStringLenTy, newCStringLenRhs PrimNewCWString cWStringTy cWStringLenTy)
    "withCWString" ->
      Just (binderFor name withCWStringTy, withCStringRhs cWStringTy)
    "withCWStringLen" ->
      Just (binderFor name withCWStringLenTy, withCStringLenRhs cWStringLenTy cWStringTy)
    "charIsRepresentable" ->
      Just (binderFor name charIsRepresentableTy, lam cStringChar charTy (ioReturn boolTy (CCon trueDataConName boolTy)))
    "castCharToCChar" ->
      Just (binderFor name castCharToCCharTy, lam cStringChar charTy (CPrimOp (PrimFixedIntegral FixedInt8 FixedFromInteger) [CPrimOp PrimCharToInt [var cStringChar charTy] intTy] cCharTy))
    "castCCharToChar" ->
      Just (binderFor name castCCharToCharTy, lam cStringCChar cCharTy (CPrimOp PrimIntToChar [CPrimOp (PrimFixedIntegral FixedInt8 FixedToInteger) [var cStringCChar cCharTy] intTy] charTy))
    "castCharToCUChar" ->
      Just (binderFor name castCharToCUCharTy, lam cStringChar charTy (CPrimOp (PrimFixedIntegral FixedWord8 FixedFromInteger) [CPrimOp PrimCharToInt [var cStringChar charTy] intTy] cUCharTy))
    "castCUCharToChar" ->
      Just (binderFor name castCUCharToCharTy, lam cStringCUChar cUCharTy (CPrimOp PrimIntToChar [CPrimOp (PrimFixedIntegral FixedWord8 FixedToInteger) [var cStringCUChar cUCharTy] intTy] charTy))
    "castCharToCSChar" ->
      Just (binderFor name castCharToCCharTy, lam cStringChar charTy (CPrimOp (PrimFixedIntegral FixedInt8 FixedFromInteger) [CPrimOp PrimCharToInt [var cStringChar charTy] intTy] cCharTy))
    "castCSCharToChar" ->
      Just (binderFor name castCCharToCharTy, lam cStringCChar cCharTy (CPrimOp PrimIntToChar [CPrimOp (PrimFixedIntegral FixedInt8 FixedToInteger) [var cStringCChar cCharTy] intTy] charTy))
    "getErrno" ->
      Just (binderFor name getErrnoTy, CPrimOp PrimGetErrno [] getErrnoTy)
    "resetErrno" ->
      Just (binderFor name resetErrnoTy, CPrimOp PrimResetErrno [] resetErrnoTy)
    "isValidErrno" ->
      Just (binderFor name isValidErrnoTy, isValidErrnoRhs)
    "errnoToIOError" ->
      Just (binderFor name errnoToIOErrorTy, errnoToIOErrorRhs)
    "throwErrno" ->
      Just (binderFor name throwErrnoTy, throwErrnoRhs)
    "throwErrnoIf" ->
      Just (binderFor name throwErrnoIfTy, throwErrnoIfRhs)
    "throwErrnoIf_" ->
      Just (binderFor name throwErrnoIfUnitTy, throwErrnoIfUnitRhs)
    "throwErrnoIfRetry" ->
      Just (binderFor name throwErrnoIfRetryTy, throwErrnoIfRetryRhs name)
    "throwErrnoIfRetry_" ->
      Just (binderFor name throwErrnoIfRetryUnitTy, throwErrnoIfRetryUnitRhs name)
    "throwErrnoIfMinus1" ->
      Just (binderFor name throwErrnoIfMinus1Ty, throwErrnoIfMinus1Rhs)
    "throwErrnoIfMinus1_" ->
      Just (binderFor name throwErrnoIfMinus1UnitTy, throwErrnoIfMinus1UnitRhs)
    "throwErrnoIfMinus1Retry" ->
      Just (binderFor name throwErrnoIfMinus1RetryTy, throwErrnoIfMinus1RetryRhs name)
    "throwErrnoIfMinus1Retry_" ->
      Just (binderFor name throwErrnoIfMinus1RetryUnitTy, throwErrnoIfMinus1RetryUnitRhs name)
    "throwErrnoIfNull" ->
      Just (binderFor name throwErrnoIfNullTy, throwErrnoIfNullRhs)
    "throwErrnoIfNullRetry" ->
      Just (binderFor name throwErrnoIfNullRetryTy, throwErrnoIfNullRetryRhs name)
    "throwErrnoIfRetryMayBlock" ->
      Just (binderFor name throwErrnoIfRetryMayBlockTy, throwErrnoIfRetryMayBlockRhs name)
    "throwErrnoIfRetryMayBlock_" ->
      Just (binderFor name throwErrnoIfRetryMayBlockUnitTy, throwErrnoIfRetryMayBlockUnitRhs name)
    "throwErrnoIfMinus1RetryMayBlock" ->
      Just (binderFor name throwErrnoIfMinus1RetryMayBlockTy, throwErrnoIfMinus1RetryMayBlockRhs name)
    "throwErrnoIfMinus1RetryMayBlock_" ->
      Just (binderFor name throwErrnoIfMinus1RetryMayBlockUnitTy, throwErrnoIfMinus1RetryMayBlockUnitRhs name)
    "throwErrnoIfNullRetryMayBlock" ->
      Just (binderFor name throwErrnoIfNullRetryMayBlockTy, throwErrnoIfNullRetryMayBlockRhs name)
    "throwErrnoPath" ->
      Just (binderFor name throwErrnoPathTy, throwErrnoPathRhs)
    "throwErrnoPathIf" ->
      Just (binderFor name throwErrnoPathIfTy, throwErrnoPathIfRhs)
    "throwErrnoPathIf_" ->
      Just (binderFor name throwErrnoPathIfUnitTy, throwErrnoPathIfUnitRhs)
    "throwErrnoPathIfNull" ->
      Just (binderFor name throwErrnoPathIfNullTy, throwErrnoPathIfNullRhs)
    "throwErrnoPathIfMinus1" ->
      Just (binderFor name throwErrnoPathIfMinus1Ty, throwErrnoPathIfMinus1Rhs)
    "throwErrnoPathIfMinus1_" ->
      Just (binderFor name throwErrnoPathIfMinus1UnitTy, throwErrnoPathIfMinus1UnitRhs)
    occurrence
      | Just value <- errnoConstantValue occurrence ->
          Just (binderFor name errnoTy, errnoLiteral value)
    _ -> controlMonadCorePair name <|> readPreludeCorePair name <|> ratioPreludeCorePair name <|> arithmeticSequenceCorePair name
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  c = preludeTypeVariable "c" (-1203)
  r = preludeTypeVariable "r" (-1206)
  aTy = CTyVar a
  bTy = CTyVar b
  cTy = CTyVar c
  rTy = CTyVar r
  showMethodA = preludeTypeVariable "a" (-1331)
  showMethodATy = CTyVar showMethodA
  listA = CTyList aTy
  listB = CTyList bTy
  tupleAB = CTyTuple [aTy, bTy]
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  maybeB = CTyApp (CTyCon maybeTyConName) bTy
  ioUnitTy = ioTy unitTy
  ioA = ioTy aTy
  ptrA = ptrTy aTy
  ptrB = ptrTy bTy
  ptrUnitTy = ptrTy unitTy
  funPtrA = funPtrTy aTy
  funPtrB = funPtrTy bTy
  stablePtrA = stablePtrTy aTy
  foreignPtrA = foreignPtrTy aTy
  foreignPtrB = foreignPtrTy bTy
  finalizerPtrA = funPtrTy (CTyFun ptrA ioUnitTy)
  showDictA = CTyApp (CTyCon (classDictionaryTypeName builtinShowClassName)) aTy
  showMethodDictA = CTyApp (CTyCon (classDictionaryTypeName builtinShowClassName)) showMethodATy
  readMethodA = preludeTypeVariable "a" (-1561)
  readMethodATy = CTyVar readMethodA
  readDictA = CTyApp (CTyCon (classDictionaryTypeName builtinReadClassName)) aTy
  readMethodDictA = CTyApp (CTyCon (classDictionaryTypeName builtinReadClassName)) readMethodATy

  idTy = CTyForall [a] (CTyFun aTy aTy)
  constTy = CTyForall [a, b] (CTyFun aTy (CTyFun bTy aTy))
  notTy = CTyFun boolTy boolTy
  dollarTy = CTyForall [a, b] (CTyFun (CTyFun aTy bTy) (CTyFun aTy bTy))
  composeTy = CTyForall [a, b, c] (CTyFun (CTyFun bTy cTy) (CTyFun (CTyFun aTy bTy) (CTyFun aTy cTy)))
  flipTy = CTyForall [a, b, c] (CTyFun (CTyFun aTy (CTyFun bTy cTy)) (CTyFun bTy (CTyFun aTy cTy)))
  mapTy = CTyForall [a, b] (CTyFun (CTyFun aTy bTy) (CTyFun listA listB))
  foldrTy = CTyForall [a, b] (CTyFun (CTyFun aTy (CTyFun bTy bTy)) (CTyFun bTy (CTyFun listA bTy)))
  foldlTy = CTyForall [a, b] (CTyFun (CTyFun bTy (CTyFun aTy bTy)) (CTyFun bTy (CTyFun listA bTy)))
  headTy = CTyForall [a] (CTyFun listA aTy)
  tailTy = CTyForall [a] (CTyFun listA listA)
  nullTy = CTyForall [a] (CTyFun listA boolTy)
  fstTy = CTyForall [a, b] (CTyFun tupleAB aTy)
  sndTy = CTyForall [a, b] (CTyFun tupleAB bTy)
  lengthTy = CTyForall [a] (CTyFun listA intTy)
  filterTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun listA listA))
  reverseTy = CTyForall [a] (CTyFun listA listA)
  appendTy = CTyForall [a] (CTyFun listA (CTyFun listA listA))
  fixIOTy = CTyForall [a] (CTyFun (CTyFun aTy (ioTy aTy)) (ioTy aTy))
  withFileTy = CTyForall [r] (CTyFun stringTy (CTyFun ioModeTy (CTyFun (CTyFun handleTy (ioTy rTy)) (ioTy rTy))))
  openFileTy = CTyFun stringTy (CTyFun ioModeTy (ioTy handleTy))
  hCloseTy = CTyFun handleTy ioUnitTy
  readFileTy = CTyFun stringTy (ioTy stringTy)
  writeFileTy = CTyFun stringTy (CTyFun stringTy ioUnitTy)
  appendFileTy = writeFileTy
  hFileSizeTy = CTyFun handleTy (ioTy intTy)
  hSetFileSizeTy = CTyFun handleTy (CTyFun intTy ioUnitTy)
  hIsEOFTy = CTyFun handleTy (ioTy boolTy)
  isEOFTy = ioTy boolTy
  hSetBufferingTy = CTyFun handleTy (CTyFun bufferModeTy ioUnitTy)
  hGetBufferingTy = CTyFun handleTy (ioTy bufferModeTy)
  hGetPosnTy = CTyFun handleTy (ioTy handlePosnTy)
  hSetPosnTy = CTyFun handlePosnTy ioUnitTy
  hSeekTy = CTyFun handleTy (CTyFun seekModeTy (CTyFun intTy ioUnitTy))
  hTellTy = CTyFun handleTy (ioTy intTy)
  hHandleBoolTy = CTyFun handleTy (ioTy boolTy)
  hSetEchoTy = CTyFun handleTy (CTyFun boolTy ioUnitTy)
  hShowTy = CTyFun handleTy (ioTy stringTy)
  hWaitForInputTy = CTyFun handleTy (CTyFun intTy (ioTy boolTy))
  hReadyTy = CTyFun handleTy (ioTy boolTy)
  hGetCharTy = CTyFun handleTy (ioTy charTy)
  hGetLineTy = CTyFun handleTy (ioTy stringTy)
  hPutCharTy = CTyFun handleTy (CTyFun charTy ioUnitTy)
  hPutStrTy = CTyFun handleTy (CTyFun stringTy ioUnitTy)
  hPrintTy = CTyForall [a] (CTyFun showDictA (CTyFun handleTy (CTyFun aTy ioUnitTy)))
  interactTy = CTyFun (CTyFun stringTy stringTy) ioUnitTy
  putCharTy = CTyFun charTy ioUnitTy
  putStrTy = CTyFun stringTy ioUnitTy
  putStrLnTy = CTyFun stringTy ioUnitTy
  getLineTy = ioTy stringTy
  getCharTy = ioTy charTy
  getArgsTy = ioTy (CTyList stringTy)
  getProgNameTy = ioTy stringTy
  getEnvTy = CTyFun stringTy getProgNameTy
  exitWithTy = CTyForall [a] (CTyFun exitCodeTy ioA)
  exitFailureTy = CTyForall [a] ioA
  exitSuccessTy = CTyForall [a] ioA
  showSTy = CTyFun stringTy stringTy
  showsPrecTy = CTyForall [showMethodA] (CTyFun showMethodDictA (CTyFun intTy (CTyFun showMethodATy showSTy)))
  showTy = CTyForall [showMethodA] (CTyFun showMethodDictA (CTyFun showMethodATy stringTy))
  showsTy = CTyForall [a] (CTyFun showDictA (CTyFun aTy showSTy))
  readSTy = CTyFun stringTy (CTyList (CTyTuple [aTy, stringTy]))
  readMethodSTy = CTyFun stringTy (CTyList (CTyTuple [readMethodATy, stringTy]))
  readsPrecTy = CTyForall [readMethodA] (CTyFun readMethodDictA (CTyFun intTy readMethodSTy))
  readsTy = CTyForall [a] (CTyFun readDictA readSTy)
  readTy = CTyForall [a] (CTyFun readDictA (CTyFun stringTy aTy))
  lexTy = CTyFun stringTy (CTyList (CTyTuple [stringTy, stringTy]))
  readParenTy = CTyForall [a] (CTyFun boolTy (CTyFun readSTy readSTy))
  printTy = CTyForall [a] (CTyFun showDictA (CTyFun aTy ioUnitTy))
  readIOTy = CTyForall [a] (CTyFun readDictA (CTyFun stringTy (ioTy aTy)))
  readLnTy = CTyForall [a] (CTyFun readDictA (ioTy aTy))
  getEnvNameValue = preludeTermName "$get_env_name" (-1680)
  exitWithCode = preludeTermName "$exit_with_code" (-1681)
  exitFailureOne = constructorApp exitFailureDataConName [] [CLit (LInt 1) intTy] exitCodeTy
  maybeHandleTy = CTyApp (CTyCon maybeTyConName) handleTy
  maybeFilePathTy = CTyApp (CTyCon maybeTyConName) stringTy
  userErrorTy = CTyFun stringTy ioErrorTy
  mkIOErrorTy = CTyFun ioErrorTypeTy (CTyFun stringTy (CTyFun maybeHandleTy (CTyFun maybeFilePathTy ioErrorTy)))
  annotateIOErrorTy = CTyFun ioErrorTy (CTyFun stringTy (CTyFun maybeHandleTy (CTyFun maybeFilePathTy ioErrorTy)))
  ioErrorPredicateTy = CTyFun ioErrorTy boolTy
  ioeGetErrorStringTy = CTyFun ioErrorTy stringTy
  ioeGetHandleTy = CTyFun ioErrorTy maybeHandleTy
  ioeGetFileNameTy = CTyFun ioErrorTy maybeFilePathTy
  ioErrorTy_ = CTyForall [a] (CTyFun ioErrorTy (ioTy aTy))
  catchTy = CTyForall [a] (CTyFun (ioTy aTy) (CTyFun (CTyFun ioErrorTy (ioTy aTy)) (ioTy aTy)))
  tryTy = CTyForall [a] (CTyFun (ioTy aTy) (ioTy (CTyApp (CTyApp (CTyCon eitherTyConName) ioErrorTy) aTy)))
  nullPtrTy = CTyForall [a] ptrA
  castPtrTy = CTyForall [a, b] (CTyFun ptrA ptrB)
  nullFunPtrTy = CTyForall [a] funPtrA
  castFunPtrTy = CTyForall [a, b] (CTyFun funPtrA funPtrB)
  castFunPtrToPtrTy = CTyForall [a, b] (CTyFun funPtrA ptrB)
  castPtrToFunPtrTy = CTyForall [a, b] (CTyFun ptrA funPtrB)
  freeHaskellFunPtrTy = CTyForall [a] (CTyFun funPtrA ioUnitTy)
  newStablePtrTy = CTyForall [a] (CTyFun aTy (ioTy stablePtrA))
  deRefStablePtrTy = CTyForall [a] (CTyFun stablePtrA (ioTy aTy))
  freeStablePtrTy = CTyForall [a] (CTyFun stablePtrA ioUnitTy)
  castStablePtrToPtrTy = CTyForall [a] (CTyFun stablePtrA ptrUnitTy)
  castPtrToStablePtrTy = CTyForall [a] (CTyFun ptrUnitTy stablePtrA)
  newForeignPtrTy = CTyForall [a] (CTyFun finalizerPtrA (CTyFun ptrA (ioTy foreignPtrA)))
  newForeignPtrTy_ = CTyForall [a] (CTyFun ptrA (ioTy foreignPtrA))
  addForeignPtrFinalizerTy = CTyForall [a] (CTyFun finalizerPtrA (CTyFun foreignPtrA ioUnitTy))
  finalizeForeignPtrTy = CTyForall [a] (CTyFun foreignPtrA ioUnitTy)
  unsafeForeignPtrToPtrTy = CTyForall [a] (CTyFun foreignPtrA ptrA)
  withForeignPtrTy = CTyForall [a, b] (CTyFun foreignPtrA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))
  touchForeignPtrTy = CTyForall [a] (CTyFun foreignPtrA ioUnitTy)
  castForeignPtrTy = CTyForall [a, b] (CTyFun foreignPtrA foreignPtrB)
  throwIfTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun (CTyFun aTy stringTy) (CTyFun ioA ioA)))
  throwIfUnitTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun (CTyFun aTy stringTy) (CTyFun ioA ioUnitTy)))
  throwIfNullTy = CTyForall [a] (CTyFun stringTy (CTyFun (ioTy ptrA) (ioTy ptrA)))
  maybeNewTy = CTyForall [a] (CTyFun (CTyFun aTy (ioTy ptrA)) (CTyFun maybeA (ioTy ptrA)))
  maybeWithTy = CTyForall [a, b, c] (CTyFun (CTyFun aTy (CTyFun (CTyFun ptrB (ioTy cTy)) (ioTy cTy))) (CTyFun maybeA (CTyFun (CTyFun ptrB (ioTy cTy)) (ioTy cTy))))
  maybePeekTy = CTyForall [a, b] (CTyFun (CTyFun ptrA (ioTy bTy)) (CTyFun ptrA (ioTy maybeB)))
  storableDictA = CTyApp (CTyCon (classDictionaryTypeName builtinStorableClassName)) aTy
  storableDictB = CTyApp (CTyCon (classDictionaryTypeName builtinStorableClassName)) bTy
  eqDictA = CTyApp (CTyCon (classDictionaryTypeName builtinEqClassName)) aTy
  numDictA = CTyApp (CTyCon (classDictionaryTypeName builtinNumClassName)) aTy
  cCharTy = fixedIntegralTy FixedInt8
  cUCharTy = fixedIntegralTy FixedWord8
  cWCharTy = fixedIntegralTy FixedInt32
  cStringTy = ptrTy cCharTy
  cWStringTy = ptrTy cWCharTy
  cStringLenTy = CTyTuple [cStringTy, intTy]
  cWStringLenTy = CTyTuple [cWStringTy, intTy]
  errnoTy = fixedIntegralTy FixedInt32
  plusPtrTy = CTyForall [a, b] (CTyFun ptrA (CTyFun intTy ptrB))
  minusPtrTy = CTyForall [a, b] (CTyFun ptrA (CTyFun ptrB intTy))
  alignPtrTy = CTyForall [a] (CTyFun ptrA (CTyFun intTy ptrA))
  mallocTy = CTyForall [a] (CTyFun storableDictA (ioTy ptrA))
  mallocBytesTy = CTyForall [a] (CTyFun intTy (ioTy ptrA))
  allocaTy = CTyForall [a, b] (CTyFun storableDictA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))
  allocaBytesTy = CTyForall [a, b] (CTyFun intTy (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))
  reallocTy = CTyForall [a, b] (CTyFun storableDictB (CTyFun ptrA (ioTy ptrB)))
  reallocBytesTy = CTyForall [a] (CTyFun ptrA (CTyFun intTy (ioTy ptrA)))
  freeTy = CTyForall [a] (CTyFun ptrA ioUnitTy)
  finalizerFreeTy = CTyForall [a] finalizerPtrA
  advancePtrTy = CTyForall [a] (CTyFun storableDictA (CTyFun ptrA (CTyFun intTy ptrA)))
  mallocArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun intTy (ioTy ptrA)))
  allocaArrayTy = CTyForall [a, b] (CTyFun storableDictA (CTyFun intTy (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))))
  reallocArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun ptrA (CTyFun intTy (ioTy ptrA))))
  peekArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun intTy (CTyFun ptrA (ioTy listA))))
  peekArray0Ty = CTyForall [a] (CTyFun storableDictA (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy listA)))))
  pokeArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun ptrA (CTyFun listA ioUnitTy)))
  pokeArray0Ty = CTyForall [a] (CTyFun storableDictA (CTyFun aTy (CTyFun ptrA (CTyFun listA ioUnitTy))))
  newArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun listA (ioTy ptrA)))
  newArray0Ty = CTyForall [a] (CTyFun storableDictA (CTyFun aTy (CTyFun listA (ioTy ptrA))))
  withArrayTy = CTyForall [a, b] (CTyFun storableDictA (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))))
  withArray0Ty = CTyForall [a, b] (CTyFun storableDictA (CTyFun aTy (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))))
  withArrayLenTy = CTyForall [a, b] (CTyFun storableDictA (CTyFun listA (CTyFun (CTyFun intTy (CTyFun ptrA (ioTy bTy))) (ioTy bTy))))
  withArrayLen0Ty = CTyForall [a, b] (CTyFun storableDictA (CTyFun aTy (CTyFun listA (CTyFun (CTyFun intTy (CTyFun ptrA (ioTy bTy))) (ioTy bTy)))))
  copyArrayTy = CTyForall [a] (CTyFun storableDictA (CTyFun ptrA (CTyFun ptrA (CTyFun intTy ioUnitTy))))
  lengthArray0Ty = CTyForall [a] (CTyFun storableDictA (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy intTy)))))
  copyBytesTy = CTyForall [a, b] (CTyFun ptrA (CTyFun ptrB (CTyFun intTy ioUnitTy)))
  peekCStringTy = CTyFun cStringTy (ioTy stringTy)
  peekCStringLenTy = CTyFun cStringLenTy (ioTy stringTy)
  newCStringTy = CTyFun stringTy (ioTy cStringTy)
  newCStringLenTy = CTyFun stringTy (ioTy cStringLenTy)
  withCStringTy = CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun cStringTy (ioTy aTy)) (ioTy aTy)))
  withCStringLenTy = CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun cStringLenTy (ioTy aTy)) (ioTy aTy)))
  peekCWStringTy = CTyFun cWStringTy (ioTy stringTy)
  peekCWStringLenTy = CTyFun cWStringLenTy (ioTy stringTy)
  newCWStringTy = CTyFun stringTy (ioTy cWStringTy)
  newCWStringLenTy = CTyFun stringTy (ioTy cWStringLenTy)
  withCWStringTy = CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun cWStringTy (ioTy aTy)) (ioTy aTy)))
  withCWStringLenTy = CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun cWStringLenTy (ioTy aTy)) (ioTy aTy)))
  charIsRepresentableTy = CTyFun charTy (ioTy boolTy)
  castCharToCCharTy = CTyFun charTy cCharTy
  castCCharToCharTy = CTyFun cCharTy charTy
  castCharToCUCharTy = CTyFun charTy cUCharTy
  castCUCharToCharTy = CTyFun cUCharTy charTy
  getErrnoTy = ioTy errnoTy
  resetErrnoTy = ioUnitTy
  isValidErrnoTy = CTyFun errnoTy boolTy
  errnoToIOErrorTy = CTyFun stringTy (CTyFun errnoTy (CTyFun maybeHandleTy (CTyFun maybeFilePathTy ioErrorTy)))
  throwErrnoTy = CTyForall [a] (CTyFun stringTy (ioTy aTy))
  throwErrnoIfTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun (ioTy aTy) (ioTy aTy))))
  throwErrnoIfUnitTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun (ioTy aTy) ioUnitTy)))
  throwErrnoIfRetryTy = throwErrnoIfTy
  throwErrnoIfRetryUnitTy = throwErrnoIfUnitTy
  throwErrnoIfMinus1Ty = CTyForall [a] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun (ioTy aTy) (ioTy aTy)))))
  throwErrnoIfMinus1UnitTy = CTyForall [a] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun (ioTy aTy) ioUnitTy))))
  throwErrnoIfMinus1RetryTy = throwErrnoIfMinus1Ty
  throwErrnoIfMinus1RetryUnitTy = throwErrnoIfMinus1UnitTy
  throwErrnoIfNullTy = CTyForall [a] (CTyFun stringTy (CTyFun (ioTy ptrA) (ioTy ptrA)))
  throwErrnoIfNullRetryTy = throwErrnoIfNullTy
  throwErrnoIfRetryMayBlockTy = CTyForall [a, b] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun (ioTy aTy) (CTyFun (ioTy bTy) (ioTy aTy)))))
  throwErrnoIfRetryMayBlockUnitTy = CTyForall [a, b] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun (ioTy aTy) (CTyFun (ioTy bTy) ioUnitTy))))
  throwErrnoIfMinus1RetryMayBlockTy = CTyForall [a, b] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun (ioTy aTy) (CTyFun (ioTy bTy) (ioTy aTy))))))
  throwErrnoIfMinus1RetryMayBlockUnitTy = CTyForall [a, b] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun (ioTy aTy) (CTyFun (ioTy bTy) ioUnitTy)))))
  throwErrnoIfNullRetryMayBlockTy = CTyForall [a, b] (CTyFun stringTy (CTyFun (ioTy ptrA) (CTyFun (ioTy bTy) (ioTy ptrA))))
  throwErrnoPathTy = CTyForall [a] (CTyFun stringTy (CTyFun stringTy (ioTy aTy)))
  throwErrnoPathIfTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun stringTy (CTyFun (ioTy aTy) (ioTy aTy)))))
  throwErrnoPathIfUnitTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun stringTy (CTyFun stringTy (CTyFun (ioTy aTy) ioUnitTy))))
  throwErrnoPathIfNullTy = CTyForall [a] (CTyFun stringTy (CTyFun stringTy (CTyFun (ioTy ptrA) (ioTy ptrA))))
  throwErrnoPathIfMinus1Ty = CTyForall [a] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun stringTy (CTyFun (ioTy aTy) (ioTy aTy))))))
  throwErrnoPathIfMinus1UnitTy = CTyForall [a] (CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun stringTy (CTyFun (ioTy aTy) ioUnitTy)))))

  idX = preludeTermName "$id_x" (-3001)
  constX = preludeTermName "$const_x" (-3002)
  constY = preludeTermName "$const_y" (-3003)
  notX = preludeTermName "$not_x" (-3004)
  notCase = preludeTermName "$not_case" (-3005)
  dollarF = preludeTermName "$dollar_f" (-3100)
  dollarX = preludeTermName "$dollar_x" (-3101)
  composeF = preludeTermName "$compose_f" (-3102)
  composeG = preludeTermName "$compose_g" (-3103)
  composeX = preludeTermName "$compose_x" (-3104)
  flipF = preludeTermName "$flip_f" (-3105)
  flipX = preludeTermName "$flip_x" (-3106)
  flipY = preludeTermName "$flip_y" (-3107)
  headXs = preludeTermName "$head_xs" (-3110)
  headY = preludeTermName "$head_y" (-3111)
  headYs = preludeTermName "$head_ys" (-3112)
  headCase = preludeTermName "$head_case" (-3113)
  tailXs = preludeTermName "$tail_xs" (-3114)
  tailY = preludeTermName "$tail_y" (-3115)
  tailYs = preludeTermName "$tail_ys" (-3116)
  tailCase = preludeTermName "$tail_case" (-3117)
  nullXs = preludeTermName "$null_xs" (-3118)
  nullY = preludeTermName "$null_y" (-3119)
  nullYs = preludeTermName "$null_ys" (-3120)
  nullCase = preludeTermName "$null_case" (-3121)
  fstPair = preludeTermName "$fst_pair" (-3122)
  fstX = preludeTermName "$fst_x" (-3123)
  fstY = preludeTermName "$fst_y" (-3124)
  fstCase = preludeTermName "$fst_case" (-3125)
  sndPair = preludeTermName "$snd_pair" (-3126)
  sndX = preludeTermName "$snd_x" (-3127)
  sndY = preludeTermName "$snd_y" (-3128)
  sndCase = preludeTermName "$snd_case" (-3129)

  foldrF = preludeTermName "$foldr_f" (-3020)
  foldrZ = preludeTermName "$foldr_z" (-3021)
  foldrXs = preludeTermName "$foldr_xs" (-3022)
  foldrY = preludeTermName "$foldr_y" (-3023)
  foldrYs = preludeTermName "$foldr_ys" (-3024)
  foldrCase = preludeTermName "$foldr_case" (-3025)

  foldlF = preludeTermName "$foldl_f" (-3090)
  foldlZ = preludeTermName "$foldl_z" (-3091)
  foldlXs = preludeTermName "$foldl_xs" (-3092)
  foldlY = preludeTermName "$foldl_y" (-3093)
  foldlYs = preludeTermName "$foldl_ys" (-3094)
  foldlCase = preludeTermName "$foldl_case" (-3095)

  lengthXs = preludeTermName "$length_xs" (-3030)
  lengthY = preludeTermName "$length_y" (-3031)
  lengthYs = preludeTermName "$length_ys" (-3032)
  lengthCase = preludeTermName "$length_case" (-3033)

  filterP = preludeTermName "$filter_p" (-3040)
  filterXs = preludeTermName "$filter_xs" (-3041)
  filterY = preludeTermName "$filter_y" (-3042)
  filterYs = preludeTermName "$filter_ys" (-3043)
  filterListCase = preludeTermName "$filter_list_case" (-3044)
  filterBoolCase = preludeTermName "$filter_bool_case" (-3045)

  reverseXs = preludeTermName "$reverse_xs" (-3050)
  appendXs = preludeTermName "$append_xs" (-3070)
  appendYs = preludeTermName "$append_ys" (-3071)
  appendX = preludeTermName "$append_x" (-3072)
  appendRest = preludeTermName "$append_rest" (-3073)
  appendCase = preludeTermName "$append_case" (-3074)
  putStrLnS = preludeTermName "$putStrLn_s" (-3060)
  showsDict = preludeTermName "$shows_dict" (-3080)
  showsX = preludeTermName "$shows_x" (-3081)
  showsRest = preludeTermName "$shows_rest" (-3082)
  readsDict = preludeTermName "$reads_dict" (-3083)
  readsInput = preludeTermName "$reads_input" (-3084)
  readDict = preludeTermName "$read_dict" (-3085)
  readInput = preludeTermName "$read_input" (-3086)
  ioFilePath = preludeTermName "$io_file_path" (-3160)
  ioMode = preludeTermName "$io_mode" (-3161)
  ioHandle = preludeTermName "$io_handle" (-3162)
  ioString = preludeTermName "$io_string" (-3163)
  ioInt = preludeTermName "$io_int" (-3164)
  ioBool = preludeTermName "$io_bool" (-3165)
  ioChar = preludeTermName "$io_char" (-3166)
  ioBufferMode = preludeTermName "$io_buffer_mode" (-3167)
  ioSeekMode = preludeTermName "$io_seek_mode" (-3168)
  ioPosn = preludeTermName "$io_posn" (-3169)
  withFilePath = preludeTermName "$with_file_path" (-3170)
  withFileMode = preludeTermName "$with_file_mode" (-3171)
  withFileAction = preludeTermName "$with_file_action" (-3172)
  withFileHandle = preludeTermName "$with_file_handle" (-3173)
  withFileValue = preludeTermName "$with_file_value" (-3174)
  withFileError = preludeTermName "$with_file_error" (-3179)
  hPrintDict = preludeTermName "$hprint_dict" (-3175)
  hPrintHandle = preludeTermName "$hprint_handle" (-3176)
  hPrintX = preludeTermName "$hprint_x" (-3177)
  interactFunction = preludeTermName "$interact_function" (-3178)
  interactInput = preludeTermName "$interact_input" (-3183)
  readIOValue = preludeTermName "$read_io_value" (-3180)
  readLnLine = preludeTermName "$read_ln_line" (-3181)
  fixIOFunction = preludeTermName "$fix_io_function" (-3182)
  printDict = preludeTermName "$print_dict" (-3061)
  printX = preludeTermName "$print_x" (-3062)
  userErrorMessage = preludeTermName "$user_error_message" (-3200)
  mkIOErrorType = preludeTermName "$mk_io_error_type" (-3201)
  mkIOErrorString = preludeTermName "$mk_io_error_string" (-3202)
  mkIOErrorHandle = preludeTermName "$mk_io_error_handle" (-3203)
  mkIOErrorFile = preludeTermName "$mk_io_error_file" (-3204)
  annotateError = preludeTermName "$annotate_io_error" (-3205)
  annotateString = preludeTermName "$annotate_io_error_string" (-3206)
  annotateHandle = preludeTermName "$annotate_io_error_handle" (-3207)
  annotateFile = preludeTermName "$annotate_io_error_file" (-3208)
  ioErrorRaise = preludeTermName "$io_error_raise" (-3209)
  catchAction = preludeTermName "$catch_action" (-3210)
  catchHandler = preludeTermName "$catch_handler" (-3211)
  tryAction = preludeTermName "$try_action" (-3212)
  ptrCastValue = preludeTermName "$ptr_cast_value" (-3500)
  funPtrCastValue = preludeTermName "$fun_ptr_cast_value" (-3501)
  funPtrToPtrValue = preludeTermName "$fun_ptr_to_ptr_value" (-3502)
  ptrToFunPtrValue = preludeTermName "$ptr_to_fun_ptr_value" (-3503)
  freeHaskellFunPtrValue = preludeTermName "$free_haskell_fun_ptr_value" (-3543)
  stablePtrNewValue = preludeTermName "$stable_ptr_new_value" (-3063)
  stablePtrDeRefValue = preludeTermName "$stable_ptr_deref_value" (-3064)
  stablePtrFreeValue = preludeTermName "$stable_ptr_free_value" (-3065)
  stablePtrCastValue = preludeTermName "$stable_ptr_cast_value" (-3066)
  stablePtrCastRawValue = preludeTermName "$stable_ptr_cast_raw" (-3067)
  foreignPtrNewFinalizerValue = preludeTermName "$foreign_ptr_new_finalizer" (-3068)
  foreignPtrNewRawValue = preludeTermName "$foreign_ptr_new_raw" (-3069)
  foreignPtrNewRawValue_ = preludeTermName "$foreign_ptr_new_raw_no_finalizer" (-3075)
  foreignPtrAddFinalizerValue = preludeTermName "$foreign_ptr_add_finalizer" (-3076)
  foreignPtrAddValue = preludeTermName "$foreign_ptr_add_value" (-3077)
  foreignPtrFinalizeValue = preludeTermName "$foreign_ptr_finalize_value" (-3078)
  foreignPtrUnsafeValue = preludeTermName "$foreign_ptr_unsafe_value" (-3504)
  foreignPtrWithValue = preludeTermName "$foreign_ptr_with_value" (-3079)
  withForeignPtrK = preludeTermName "$with_foreign_ptr_k" (-3080)
  foreignPtrTouchValue = preludeTermName "$foreign_ptr_touch_value" (-3081)
  foreignPtrCastValue = preludeTermName "$foreign_ptr_cast_value" (-3505)
  throwIfPredicate = preludeTermName "$throw_if_predicate" (-3510)
  throwIfMessage = preludeTermName "$throw_if_message" (-3511)
  throwIfAction = preludeTermName "$throw_if_action" (-3512)
  throwIfValue = preludeTermName "$throw_if_value" (-3513)
  throwIfCase = preludeTermName "$throw_if_case" (-3514)
  throwIfUnitPredicate = preludeTermName "$throw_if_unit_predicate" (-3515)
  throwIfUnitMessage = preludeTermName "$throw_if_unit_message" (-3516)
  throwIfUnitAction = preludeTermName "$throw_if_unit_action" (-3517)
  throwIfUnitValue = preludeTermName "$throw_if_unit_value" (-3518)
  throwIfUnitCase = preludeTermName "$throw_if_unit_case" (-3519)
  throwIfNullLocation = preludeTermName "$throw_if_null_location" (-3520)
  throwIfNullAction = preludeTermName "$throw_if_null_action" (-3521)
  throwIfNullPointer = preludeTermName "$throw_if_null_pointer" (-3522)
  throwIfNullCase = preludeTermName "$throw_if_null_case" (-3523)
  maybeNewFunction = preludeTermName "$maybe_new_function" (-3530)
  maybeNewValue = preludeTermName "$maybe_new_value" (-3531)
  maybeNewCase = preludeTermName "$maybe_new_case" (-3532)
  maybeNewJust = preludeTermName "$maybe_new_just" (-3533)
  maybeWithFunction = preludeTermName "$maybe_with_function" (-3534)
  maybeWithValue = preludeTermName "$maybe_with_value" (-3535)
  maybeWithContinuation = preludeTermName "$maybe_with_continuation" (-3536)
  maybeWithCase = preludeTermName "$maybe_with_case" (-3537)
  maybeWithJust = preludeTermName "$maybe_with_just" (-3538)
  maybePeekFunction = preludeTermName "$maybe_peek_function" (-3539)
  maybePeekPointer = preludeTermName "$maybe_peek_pointer" (-3540)
  maybePeekCase = preludeTermName "$maybe_peek_case" (-3541)
  maybePeekValue = preludeTermName "$maybe_peek_value" (-3542)
  ptrPlusValue = preludeTermName "$ptr_plus_value" (-3550)
  ptrPlusOffset = preludeTermName "$ptr_plus_offset" (-3551)
  ptrMinusLeft = preludeTermName "$ptr_minus_left" (-3552)
  ptrMinusRight = preludeTermName "$ptr_minus_right" (-3553)
  ptrAlignValue = preludeTermName "$ptr_align_value" (-3554)
  ptrAlignOffset = preludeTermName "$ptr_align_offset" (-3555)
  mallocDict = preludeTermName "$malloc_dict" (-3560)
  mallocBytesSize = preludeTermName "$malloc_bytes_size" (-3561)
  allocaDict = preludeTermName "$alloca_dict" (-3562)
  allocaContinuation = preludeTermName "$alloca_continuation" (-3563)
  allocaBytesSize = preludeTermName "$alloca_bytes_size" (-3564)
  allocaBytesContinuation = preludeTermName "$alloca_bytes_continuation" (-3565)
  allocaBytesPointer = preludeTermName "$alloca_bytes_pointer" (-3566)
  allocaBytesResult = preludeTermName "$alloca_bytes_result" (-3567)
  allocaBytesError = preludeTermName "$alloca_bytes_error" (-3568)
  reallocDict = preludeTermName "$realloc_dict" (-3569)
  reallocPointer = preludeTermName "$realloc_pointer" (-3570)
  reallocBytesPointer = preludeTermName "$realloc_bytes_pointer" (-3571)
  reallocBytesSize = preludeTermName "$realloc_bytes_size" (-3572)
  freePointer = preludeTermName "$free_pointer" (-3573)
  arrayDict = preludeTermName "$array_dict" (-3580)
  arrayCount = preludeTermName "$array_count" (-3581)
  arrayPointer = preludeTermName "$array_pointer" (-3582)
  arrayValues = preludeTermName "$array_values" (-3584)
  arrayValue = preludeTermName "$array_value" (-3585)
  arrayRest = preludeTermName "$array_rest" (-3586)
  arrayCase = preludeTermName "$array_case" (-3587)
  arrayTail = preludeTermName "$array_tail" (-3588)
  arrayContinuation = preludeTermName "$array_continuation" (-3589)
  arrayEqDict = preludeTermName "$array_eq_dict" (-3621)
  arrayMarker = preludeTermName "$array_marker" (-3622)
  arrayLength = preludeTermName "$array_length" (-3623)
  copyDest = preludeTermName "$copy_dest" (-3591)
  copySource = preludeTermName "$copy_source" (-3592)
  copyCount = preludeTermName "$copy_count" (-3593)
  cStringPointer = preludeTermName "$cstring_pointer" (-3594)
  cWStringPointer = preludeTermName "$cwstring_pointer" (-3595)
  cStringLength = preludeTermName "$cstring_length" (-3596)
  cStringSource = preludeTermName "$cstring_source" (-3597)
  cStringPair = preludeTermName "$cstring_pair" (-3598)
  cStringContinuation = preludeTermName "$cstring_continuation" (-3599)
  cStringChar = preludeTermName "$cstring_char" (-3601)
  cStringCChar = preludeTermName "$cstring_cchar" (-3602)
  cStringCUChar = preludeTermName "$cstring_cuchar" (-3603)
  errnoValue = preludeTermName "$errno_value" (-3610)
  errnoLocation = preludeTermName "$errno_location" (-3611)
  errnoHandle = preludeTermName "$errno_handle" (-3612)
  errnoFile = preludeTermName "$errno_file" (-3613)
  throwErrnoLocation = preludeTermName "$throw_errno_location" (-3614)
  throwErrnoPredicate = preludeTermName "$throw_errno_predicate" (-3615)
  throwErrnoAction = preludeTermName "$throw_errno_action" (-3616)
  throwErrnoResult = preludeTermName "$throw_errno_result" (-3617)
  throwErrnoCase = preludeTermName "$throw_errno_case" (-3618)
  throwErrnoDictNum = preludeTermName "$throw_errno_num_dict" (-3619)
  throwErrnoDictEq = preludeTermName "$throw_errno_eq_dict" (-3620)
  throwErrnoPathName = preludeTermName "$throw_errno_path" (-3624)
  throwErrnoBlockAction = preludeTermName "$throw_errno_block_action" (-3625)
  throwErrnoRetryCase = preludeTermName "$throw_errno_retry_case" (-3627)
  throwErrnoWouldBlockCase = preludeTermName "$throw_errno_would_block_case" (-3628)

  binderFor binderName ty = CoreBinder binderName ty
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var variable ty = CVar variable ty
  con constructorName ty = CCon constructorName ty
  boolCase scrutinee binderName resultTy trueBody falseBody =
    CCase
      scrutinee
      (CoreBinder binderName boolTy)
      [ CoreAlt (ConstructorAlt trueDataConName) [] trueBody
      , CoreAlt (ConstructorAlt falseDataConName) [] falseBody
      ]
      resultTy
  listCase scrutinee binderName elementTy resultTy nilBody headName tailName consBody =
    CCase
      scrutinee
      (CoreBinder binderName (CTyList elementTy))
      [ CoreAlt (ConstructorAlt listNilDataConName) [] nilBody
      , CoreAlt
          (ConstructorAlt listConsDataConName)
          [CoreBinder headName elementTy, CoreBinder tailName (CTyList elementTy)]
          consBody
      ]
      resultTy
  specialize functionName functionTy typeArguments resultTy =
    CTypeApp (CVar functionName functionTy) typeArguments resultTy
  apply fn arg resultTy =
    CApp fn arg resultTy
  intLiteral value =
    CLit (LInt value) intTy
  nil elementTy =
    constructorApp listNilDataConName [elementTy] [] (CTyList elementTy)
  cons elementTy headExpr tailExpr =
    constructorApp listConsDataConName [elementTy] [headExpr, tailExpr] (CTyList elementTy)

  dollarRhs =
    CTypeLam
      [a, b]
      (lam dollarF (CTyFun aTy bTy) (lam dollarX aTy (apply (var dollarF (CTyFun aTy bTy)) (var dollarX aTy) bTy)))
      dollarTy

  composeRhs =
    CTypeLam
      [a, b, c]
      (lam composeF (CTyFun bTy cTy) (lam composeG (CTyFun aTy bTy) (lam composeX aTy body)))
      composeTy
   where
    composedArg =
      apply (var composeG (CTyFun aTy bTy)) (var composeX aTy) bTy
    body =
      apply (var composeF (CTyFun bTy cTy)) composedArg cTy

  flipRhs =
    CTypeLam
      [a, b, c]
      (lam flipF (CTyFun aTy (CTyFun bTy cTy)) (lam flipY bTy (lam flipX aTy body)))
      flipTy
   where
    body =
      apply
        (apply (var flipF (CTyFun aTy (CTyFun bTy cTy))) (var flipX aTy) (CTyFun bTy cTy))
        (var flipY bTy)
        cTy

  headRhs =
    CTypeLam [a] (lam headXs listA headBody) headTy
   where
    headBody =
      CCase
        (var headXs listA)
        (CoreBinder headCase listA)
        [ CoreAlt
            (ConstructorAlt listConsDataConName)
            [CoreBinder headY aTy, CoreBinder headYs listA]
            (var headY aTy)
        ]
        aTy

  tailRhs =
    CTypeLam [a] (lam tailXs listA tailBody) tailTy
   where
    tailBody =
      CCase
        (var tailXs listA)
        (CoreBinder tailCase listA)
        [ CoreAlt
            (ConstructorAlt listConsDataConName)
            [CoreBinder tailY aTy, CoreBinder tailYs listA]
            (var tailYs listA)
        ]
        listA

  nullRhs =
    CTypeLam [a] (lam nullXs listA nullBody) nullTy
   where
    nullBody =
      listCase
        (var nullXs listA)
        nullCase
        aTy
        boolTy
        (con trueDataConName boolTy)
        nullY
        nullYs
        (con falseDataConName boolTy)

  fstRhs =
    CTypeLam [a, b] (lam fstPair tupleAB fstBody) fstTy
   where
    fstBody =
      CCase
        (var fstPair tupleAB)
        (CoreBinder fstCase tupleAB)
        [ CoreAlt
            (ConstructorAlt (tupleDataConName 2))
            [CoreBinder fstX aTy, CoreBinder fstY bTy]
            (var fstX aTy)
        ]
        aTy

  sndRhs =
    CTypeLam [a, b] (lam sndPair tupleAB sndBody) sndTy
   where
    sndBody =
      CCase
        (var sndPair tupleAB)
        (CoreBinder sndCase tupleAB)
        [ CoreAlt
            (ConstructorAlt (tupleDataConName 2))
            [CoreBinder sndX aTy, CoreBinder sndY bTy]
            (var sndY bTy)
        ]
        bTy

  mapRhs functionName =
    CTypeLam [a, b] (lam mapF (CTyFun aTy bTy) (lam mapXs listA mapBody)) mapTy
   where
    mapF = scopedName "$map_f" 10
    mapXs = scopedName "$map_xs" 11
    mapY = scopedName "$map_y" 12
    mapYs = scopedName "$map_ys" 13
    mapCase = scopedName "$map_case" 14
    scopedName occurrence offset =
      builtinLocalTermName occurrence (nameUnique functionName * 100 + offset)
    recursive =
      apply
        (apply (specialize functionName mapTy [aTy, bTy] (CTyFun (CTyFun aTy bTy) (CTyFun listA listB))) (var mapF (CTyFun aTy bTy)) (CTyFun listA listB))
        (var mapYs listA)
        listB
    mappedHead =
      apply (var mapF (CTyFun aTy bTy)) (var mapY aTy) bTy
    mapBody =
      listCase
        (var mapXs listA)
        mapCase
        aTy
        listB
        (nil bTy)
        mapY
        mapYs
        (cons bTy mappedHead recursive)

  foldrRhs functionName =
    CTypeLam [a, b] (lam foldrF (CTyFun aTy (CTyFun bTy bTy)) (lam foldrZ bTy (lam foldrXs listA foldrBody))) foldrTy
   where
    recursive =
      apply
        ( apply
            ( apply
                (specialize functionName foldrTy [aTy, bTy] (CTyFun (CTyFun aTy (CTyFun bTy bTy)) (CTyFun bTy (CTyFun listA bTy))))
                (var foldrF (CTyFun aTy (CTyFun bTy bTy)))
                (CTyFun bTy (CTyFun listA bTy))
            )
            (var foldrZ bTy)
            (CTyFun listA bTy)
        )
        (var foldrYs listA)
        bTy
    foldedHead =
      apply
        (apply (var foldrF (CTyFun aTy (CTyFun bTy bTy))) (var foldrY aTy) (CTyFun bTy bTy))
        recursive
        bTy
    foldrBody =
      listCase
        (var foldrXs listA)
        foldrCase
        aTy
        bTy
        (var foldrZ bTy)
        foldrY
        foldrYs
        foldedHead

  foldlRhs functionName =
    CTypeLam [a, b] (lam foldlF (CTyFun bTy (CTyFun aTy bTy)) (lam foldlZ bTy (lam foldlXs listA foldlBody))) foldlTy
   where
    nextAcc =
      apply
        (apply (var foldlF (CTyFun bTy (CTyFun aTy bTy))) (var foldlZ bTy) (CTyFun aTy bTy))
        (var foldlY aTy)
        bTy
    recursive =
      apply
        ( apply
            ( apply
                (specialize functionName foldlTy [aTy, bTy] (CTyFun (CTyFun bTy (CTyFun aTy bTy)) (CTyFun bTy (CTyFun listA bTy))))
                (var foldlF (CTyFun bTy (CTyFun aTy bTy)))
                (CTyFun bTy (CTyFun listA bTy))
            )
            nextAcc
            (CTyFun listA bTy)
        )
        (var foldlYs listA)
        bTy
    foldlBody =
      listCase
        (var foldlXs listA)
        foldlCase
        aTy
        bTy
        (var foldlZ bTy)
        foldlY
        foldlYs
        recursive

  lengthRhs functionName =
    CTypeLam [a] (lam lengthXs listA lengthBody) lengthTy
   where
    recursive =
      apply
        (specialize functionName lengthTy [aTy] (CTyFun listA intTy))
        (var lengthYs listA)
        intTy
    lengthBody =
      listCase
        (var lengthXs listA)
        lengthCase
        aTy
        intTy
        (intLiteral 0)
        lengthY
        lengthYs
        (CPrimOp PrimAdd [intLiteral 1, recursive] intTy)

  filterRhs functionName =
    CTypeLam [a] (lam filterP (CTyFun aTy boolTy) (lam filterXs listA filterBody)) filterTy
   where
    recursive =
      apply
        (apply (specialize functionName filterTy [aTy] (CTyFun (CTyFun aTy boolTy) (CTyFun listA listA))) (var filterP (CTyFun aTy boolTy)) (CTyFun listA listA))
        (var filterYs listA)
        listA
    predicate =
      apply (var filterP (CTyFun aTy boolTy)) (var filterY aTy) boolTy
    filterBody =
      listCase
        (var filterXs listA)
        filterListCase
        aTy
        listA
        (nil aTy)
        filterY
        filterYs
        ( boolCase
            predicate
            filterBoolCase
            listA
            (cons aTy (var filterY aTy) recursive)
            recursive
        )

  reverseRhs =
    CTypeLam [a] (lam reverseXs listA reverseBody) reverseTy
   where
    reverseBody =
      apply
        ( apply
            (specialize reverseGoName reverseGoTy [aTy] (CTyFun listA (CTyFun listA listA)))
            (nil aTy)
            (CTyFun listA listA)
        )
        (var reverseXs listA)
        listA

  appendRhs functionName =
    CTypeLam [a] (lam appendXs listA (lam appendYs listA appendBody)) appendTy
   where
    recursive =
      apply
        ( apply
            (specialize functionName appendTy [aTy] (CTyFun listA (CTyFun listA listA)))
            (var appendRest listA)
            (CTyFun listA listA)
        )
        (var appendYs listA)
        listA
    appendBody =
      listCase
        (var appendXs listA)
        appendCase
        aTy
        listA
        (var appendYs listA)
        appendX
        appendRest
        (cons aTy (var appendX aTy) recursive)

  showsRhs =
    CTypeLam [a] (lam showsDict showDictA (lam showsX aTy (lam showsRest stringTy showsBody))) showsTy
   where
    showsPrecFunction =
      apply
        (CTypeApp (CVar (preludeTermName "showsPrec" (-1430)) showsPrecTy) [aTy] (CTyFun showDictA (CTyFun intTy (CTyFun aTy showSTy))))
        (var showsDict showDictA)
        (CTyFun intTy (CTyFun aTy showSTy))
    showsBody =
      apply
        ( apply
            (apply showsPrecFunction zeroInt (CTyFun aTy showSTy))
            (var showsX aTy)
            showSTy
        )
        (var showsRest stringTy)
        stringTy

  readsRhs =
    CTypeLam [a] (lam readsDict readDictA (lam readsInput stringTy readsBody)) readsTy
   where
    readsPrecFunction =
      apply
        (CTypeApp (CVar (preludeTermName "readsPrec" (-1433)) readsPrecTy) [aTy] (CTyFun readDictA (CTyFun intTy readSTy)))
        (var readsDict readDictA)
        (CTyFun intTy readSTy)
    readsBody =
      apply
        (apply readsPrecFunction zeroInt readSTy)
        (var readsInput stringTy)
        (CTyList (CTyTuple [aTy, stringTy]))

  readRhs =
    CTypeLam [a] (lam readDict readDictA (lam readInput stringTy readBody)) readTy
   where
    readsPrecFunction =
      apply
        (CTypeApp (CVar (preludeTermName "readsPrec" (-1433)) readsPrecTy) [aTy] (CTyFun readDictA (CTyFun intTy readSTy)))
        (var readDict readDictA)
        (CTyFun intTy readSTy)
    parsed =
      apply
        (apply readsPrecFunction zeroInt readSTy)
        (var readInput stringTy)
        (CTyList (CTyTuple [aTy, stringTy]))
    completeFunction =
      CTypeApp
        (CVar readCompleteName readCompleteCoreType)
        [aTy]
        (CTyFun (CTyList (CTyTuple [aTy, stringTy])) aTy)
    readBody =
      apply completeFunction parsed aTy

  printRhs =
    CTypeLam [a] (lam printDict showDictA (lam printX aTy printBody)) printTy
   where
    showFunction =
      apply
        (CTypeApp (CVar (preludeTermName "show" (-1431)) showTy) [aTy] (CTyFun showDictA (CTyFun aTy stringTy)))
        (var printDict showDictA)
        (CTyFun aTy stringTy)
    shownValue =
      apply showFunction (var printX aTy) stringTy
    printBody =
      CPrimOp PrimHPutStrLn [CPrimOp (PrimStdHandle StdOutHandle) [] handleTy, shownValue] ioUnitTy

  hPrintRhs =
    CTypeLam [a] (lam hPrintDict showDictA (lam hPrintHandle handleTy (lam hPrintX aTy hPrintBody))) hPrintTy
   where
    showFunction =
      apply
        (CTypeApp (CVar (preludeTermName "show" (-1431)) showTy) [aTy] (CTyFun showDictA (CTyFun aTy stringTy)))
        (var hPrintDict showDictA)
        (CTyFun aTy stringTy)
    shownValue =
      apply showFunction (var hPrintX aTy) stringTy
    hPrintBody =
      CPrimOp PrimHPutStrLn [var hPrintHandle handleTy, shownValue] ioUnitTy

  fixIORhs =
    CTypeLam [a] (lam fixIOFunction (CTyFun aTy (ioTy aTy)) (CPrimOp PrimIOFix [var fixIOFunction (CTyFun aTy (ioTy aTy))] (ioTy aTy))) fixIOTy

  withFileRhs =
    CTypeLam [r] (lam withFilePath stringTy (lam withFileMode ioModeTy (lam withFileAction (CTyFun handleTy (ioTy rTy)) withOpen))) withFileTy
   where
    openAction =
      CPrimOp PrimOpenFile [var withFilePath stringTy, var withFileMode ioModeTy] (ioTy handleTy)
    withOpen =
      CPrimOp PrimIOBind [openAction, CLam (CoreBinder withFileHandle handleTy) withBody (CTyFun handleTy (ioTy rTy))] (ioTy rTy)
    userAction =
      apply (var withFileAction (CTyFun handleTy (ioTy rTy))) (var withFileHandle handleTy) (ioTy rTy)
    withBody =
      CPrimOp
        PrimIOCatch
        [ successPath
        , CLam
            (CoreBinder withFileError ioErrorTy)
            (CPrimOp PrimIOThen [CPrimOp PrimHClose [var withFileHandle handleTy] ioUnitTy, CPrimOp PrimIOError [var withFileError ioErrorTy] (ioTy rTy)] (ioTy rTy))
            (CTyFun ioErrorTy (ioTy rTy))
        ]
        (ioTy rTy)
    successPath =
      CPrimOp
        PrimIOBind
        [ userAction
        , CLam
            (CoreBinder withFileValue rTy)
            (CPrimOp PrimIOThen [CPrimOp PrimHClose [var withFileHandle handleTy] ioUnitTy, CPrimOp PrimIOReturn [var withFileValue rTy] (ioTy rTy)] (ioTy rTy))
            (CTyFun rTy (ioTy rTy))
        ]
        (ioTy rTy)

  interactRhs =
    lam interactFunction (CTyFun stringTy stringTy) $
      CPrimOp
        PrimIOBind
        [ CPrimOp PrimHGetContents [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] (ioTy stringTy)
        , CLam
            (CoreBinder interactInput stringTy)
            ( CPrimOp
                PrimHPutStr
                [ CPrimOp (PrimStdHandle StdOutHandle) [] handleTy
                , apply (var interactFunction (CTyFun stringTy stringTy)) (var interactInput stringTy) stringTy
                ]
                ioUnitTy
            )
            (CTyFun stringTy ioUnitTy)
        ]
        ioUnitTy

  readIORhs =
    CTypeLam [a] (lam readDict readDictA (lam readIOValue stringTy (CPrimOp PrimIOReturn [readValue] (ioTy aTy)))) readIOTy
   where
    readFunction =
      apply
        (CTypeApp (CVar (preludeTermName "read" (-1432)) readTy) [aTy] (CTyFun readDictA (CTyFun stringTy aTy)))
        (var readDict readDictA)
        (CTyFun stringTy aTy)
    readValue =
      apply readFunction (var readIOValue stringTy) aTy

  readLnRhs =
    CTypeLam [a] (lam readDict readDictA readLnBody) readLnTy
   where
    readIOFunction =
      apply
        (CTypeApp (CVar (preludeTermName "readIO" (-3185)) readIOTy) [aTy] (CTyFun readDictA (CTyFun stringTy (ioTy aTy))))
        (var readDict readDictA)
        (CTyFun stringTy (ioTy aTy))
    readLnBody =
      CPrimOp
        PrimIOBind
        [ CPrimOp PrimHGetLine [CPrimOp (PrimStdHandle StdInHandle) [] handleTy] (ioTy stringTy)
        , CLam
            (CoreBinder readLnLine stringTy)
            (apply readIOFunction (var readLnLine stringTy) (ioTy aTy))
            (CTyFun stringTy (ioTy aTy))
        ]
        (ioTy aTy)

  userErrorRhs =
    lam userErrorMessage stringTy $
      ioErrorValue
        (CCon ioErrorUserTypeDataConName ioErrorTypeTy)
        (var userErrorMessage stringTy)
        (nothingCore handleTy)
        (nothingCore stringTy)

  mkIOErrorRhs =
    lam mkIOErrorType ioErrorTypeTy $
      lam mkIOErrorString stringTy $
        lam mkIOErrorHandle maybeHandleTy $
          lam mkIOErrorFile maybeFilePathTy $
            ioErrorValue
              (var mkIOErrorType ioErrorTypeTy)
              (var mkIOErrorString stringTy)
              (var mkIOErrorHandle maybeHandleTy)
              (var mkIOErrorFile maybeFilePathTy)

  annotateIOErrorRhs =
    lam annotateError ioErrorTy $
      lam annotateString stringTy $
        lam annotateHandle maybeHandleTy $
          lam annotateFile maybeFilePathTy $
            CCase
              (var annotateError ioErrorTy)
              (CoreBinder annotateCase ioErrorTy)
              [ CoreAlt
                  (ConstructorAlt ioErrorDataConName)
                  [ CoreBinder annotateOldType ioErrorTypeTy
                  , CoreBinder annotateOldString stringTy
                  , CoreBinder annotateOldHandle maybeHandleTy
                  , CoreBinder annotateOldFile maybeFilePathTy
                  ]
                  ( ioErrorValue
                      (var annotateOldType ioErrorTypeTy)
                      (var annotateString stringTy)
                      (maybeOverride handleTy (var annotateOldHandle maybeHandleTy) (var annotateHandle maybeHandleTy) annotateHandleCase annotateHandleJust)
                      (maybeOverride stringTy (var annotateOldFile maybeFilePathTy) (var annotateFile maybeFilePathTy) annotateFileCase annotateFileJust)
                  )
              ]
              ioErrorTy

  annotateCase = preludeTermName "$annotate_io_error_case" (-3220)
  annotateOldType = preludeTermName "$annotate_io_error_old_type" (-3221)
  annotateOldString = preludeTermName "$annotate_io_error_old_string" (-3222)
  annotateOldHandle = preludeTermName "$annotate_io_error_old_handle" (-3223)
  annotateOldFile = preludeTermName "$annotate_io_error_old_file" (-3224)
  annotateHandleCase = preludeTermName "$annotate_io_error_handle_case" (-3225)
  annotateHandleJust = preludeTermName "$annotate_io_error_handle_just" (-3226)
  annotateFileCase = preludeTermName "$annotate_io_error_file_case" (-3227)
  annotateFileJust = preludeTermName "$annotate_io_error_file_just" (-3228)

  ioErrorRhs =
    CTypeLam [a] (lam ioErrorRaise ioErrorTy (CPrimOp PrimIOError [var ioErrorRaise ioErrorTy] (ioTy aTy))) ioErrorTy_

  catchRhs =
    CTypeLam [a] (lam catchAction (ioTy aTy) (lam catchHandler (CTyFun ioErrorTy (ioTy aTy)) (CPrimOp PrimIOCatch [var catchAction (ioTy aTy), var catchHandler (CTyFun ioErrorTy (ioTy aTy))] (ioTy aTy)))) catchTy

  tryRhs =
    CTypeLam [a] (lam tryAction (ioTy aTy) (CPrimOp PrimIOTry [var tryAction (ioTy aTy)] (ioTy (CTyApp (CTyApp (CTyCon eitherTyConName) ioErrorTy) aTy)))) tryTy

  throwIfRhs =
    CTypeLam [a] (lam throwIfPredicate (CTyFun aTy boolTy) (lam throwIfMessage (CTyFun aTy stringTy) (lam throwIfAction ioA (CPrimOp PrimIOBind [var throwIfAction ioA, CLam (CoreBinder throwIfValue aTy) throwIfBody (CTyFun aTy ioA)] ioA)))) throwIfTy
   where
    value = var throwIfValue aTy
    throwIfBody =
      boolCase
        (apply (var throwIfPredicate (CTyFun aTy boolTy)) value boolTy)
        throwIfCase
        ioA
        (ioThrowUserError aTy (apply (var throwIfMessage (CTyFun aTy stringTy)) value stringTy))
        (ioReturn aTy value)

  throwIfUnitRhs =
    CTypeLam [a] (lam throwIfUnitPredicate (CTyFun aTy boolTy) (lam throwIfUnitMessage (CTyFun aTy stringTy) (lam throwIfUnitAction ioA (CPrimOp PrimIOBind [var throwIfUnitAction ioA, CLam (CoreBinder throwIfUnitValue aTy) throwIfUnitBody (CTyFun aTy ioUnitTy)] ioUnitTy)))) throwIfUnitTy
   where
    value = var throwIfUnitValue aTy
    throwIfUnitBody =
      boolCase
        (apply (var throwIfUnitPredicate (CTyFun aTy boolTy)) value boolTy)
        throwIfUnitCase
        ioUnitTy
        (ioThrowUserError unitTy (apply (var throwIfUnitMessage (CTyFun aTy stringTy)) value stringTy))
        (ioReturn unitTy unitValue)

  throwIfNullRhs =
    CTypeLam [a] (lam throwIfNullLocation stringTy (lam throwIfNullAction (ioTy ptrA) (CPrimOp PrimIOBind [var throwIfNullAction (ioTy ptrA), CLam (CoreBinder throwIfNullPointer ptrA) throwIfNullBody (CTyFun ptrA (ioTy ptrA))] (ioTy ptrA)))) throwIfNullTy
   where
    pointer = var throwIfNullPointer ptrA
    throwIfNullBody =
      boolCase
        (CPrimOp PrimIsNullPtr [pointer] boolTy)
        throwIfNullCase
        (ioTy ptrA)
        (ioThrowUserError ptrA (var throwIfNullLocation stringTy))
        (ioReturn ptrA pointer)

  maybeNewRhs =
    CTypeLam [a] (lam maybeNewFunction (CTyFun aTy (ioTy ptrA)) (lam maybeNewValue maybeA maybeNewBody)) maybeNewTy
   where
    maybeNewBody =
      CCase
        (var maybeNewValue maybeA)
        (CoreBinder maybeNewCase maybeA)
        [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (ioReturn ptrA (CPrimOp PrimNullPtr [] ptrA))
        , CoreAlt
            (ConstructorAlt maybeJustDataConName)
            [CoreBinder maybeNewJust aTy]
            (apply (var maybeNewFunction (CTyFun aTy (ioTy ptrA))) (var maybeNewJust aTy) (ioTy ptrA))
        ]
        (ioTy ptrA)

  maybeWithRhs =
    CTypeLam [a, b, c] (lam maybeWithFunction withFunctionTy (lam maybeWithValue maybeA (lam maybeWithContinuation continuationTy maybeWithBody))) maybeWithTy
   where
    withFunctionTy = CTyFun aTy (CTyFun continuationTy (ioTy cTy))
    continuationTy = CTyFun ptrB (ioTy cTy)
    maybeWithBody =
      CCase
        (var maybeWithValue maybeA)
        (CoreBinder maybeWithCase maybeA)
        [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (apply (var maybeWithContinuation continuationTy) (CPrimOp PrimNullPtr [] ptrB) (ioTy cTy))
        , CoreAlt
            (ConstructorAlt maybeJustDataConName)
            [CoreBinder maybeWithJust aTy]
            ( apply
                (apply (var maybeWithFunction withFunctionTy) (var maybeWithJust aTy) (CTyFun continuationTy (ioTy cTy)))
                (var maybeWithContinuation continuationTy)
                (ioTy cTy)
            )
        ]
        (ioTy cTy)

  maybePeekRhs =
    CTypeLam [a, b] (lam maybePeekFunction (CTyFun ptrA (ioTy bTy)) (lam maybePeekPointer ptrA maybePeekBody)) maybePeekTy
   where
    pointer = var maybePeekPointer ptrA
    maybePeekBody =
      boolCase
        (CPrimOp PrimIsNullPtr [pointer] boolTy)
        maybePeekCase
        (ioTy maybeB)
        (ioReturn maybeB (maybeNothing bTy))
        ( CPrimOp
            PrimIOBind
            [ apply (var maybePeekFunction (CTyFun ptrA (ioTy bTy))) pointer (ioTy bTy)
            , CLam (CoreBinder maybePeekValue bTy) (ioReturn maybeB (maybeJust bTy (var maybePeekValue bTy))) (CTyFun bTy (ioTy maybeB))
            ]
            (ioTy maybeB)
        )

  storableClassA = preludeTypeVariable "a" (-1572)
  storableClassATy = CTyVar storableClassA
  storableClassDictA = CTyApp (CTyCon (classDictionaryTypeName builtinStorableClassName)) storableClassATy
  storableClassPtrA = ptrTy storableClassATy
  sizeOfSelectorTy = CTyForall [storableClassA] (CTyFun storableClassDictA (CTyFun storableClassATy intTy))
  peekSelectorTy = CTyForall [storableClassA] (CTyFun storableClassDictA (CTyFun storableClassPtrA (ioTy storableClassATy)))
  pokeSelectorTy = CTyForall [storableClassA] (CTyFun storableClassDictA (CTyFun storableClassPtrA (CTyFun storableClassATy ioUnitTy)))
  sizeOfSelector = preludeTermName "sizeOf" (-1497)
  storableSizeA =
    storableSizeExpr a aTy storableDictA (var mallocDict storableDictA)
  storableSizeExpr typeVar valueTy dictTy dictExpr =
    CLet
      (CoreRec [(CoreBinder storableDummy valueTy, var storableDummy valueTy)])
      ( apply
          ( apply
              (specialize sizeOfSelector sizeOfSelectorTy [valueTy] (CTyFun dictTy (CTyFun valueTy intTy)))
              dictExpr
              (CTyFun valueTy intTy)
          )
          (var storableDummy valueTy)
          intTy
      )
      intTy
   where
    storableDummy = RName TermNamespace ("$storable_dummy_" <> renderRName typeVar) (-6732 - nameUnique typeVar) False

  mallocRhs =
    CTypeLam [a] (lam mallocDict storableDictA (CPrimOp PrimMallocBytes [storableSizeA] (ioTy ptrA))) mallocTy

  allocaRhs =
    CTypeLam [a, b] (lam allocaDict storableDictA (lam allocaContinuation (CTyFun ptrA (ioTy bTy)) (allocaBytesBody ptrA bTy (storableSizeExpr a aTy storableDictA (var allocaDict storableDictA)) (var allocaContinuation (CTyFun ptrA (ioTy bTy)))))) allocaTy

  allocaBytesRhs =
    CTypeLam [a, b] (lam allocaBytesSize intTy (lam allocaBytesContinuation (CTyFun ptrA (ioTy bTy)) (allocaBytesBody ptrA bTy (var allocaBytesSize intTy) (var allocaBytesContinuation (CTyFun ptrA (ioTy bTy)))))) allocaBytesTy

  allocaBytesBody pointerTy resultTy sizeExpr continuationExpr =
    CPrimOp
      PrimIOBind
      [ CPrimOp PrimMallocBytes [sizeExpr] (ioTy pointerTy)
      , CLam (CoreBinder allocaBytesPointer pointerTy) (CPrimOp PrimIOCatch [successAction, failureHandler] (ioTy resultTy)) (CTyFun pointerTy (ioTy resultTy))
      ]
      (ioTy resultTy)
   where
    pointer = var allocaBytesPointer pointerTy
    freeAction = CPrimOp PrimFree [pointer] ioUnitTy
    successAction =
      CPrimOp
        PrimIOBind
        [ apply continuationExpr pointer (ioTy resultTy)
        , CLam
            (CoreBinder allocaBytesResult resultTy)
            (CPrimOp PrimIOThen [freeAction, ioReturn resultTy (var allocaBytesResult resultTy)] (ioTy resultTy))
            (CTyFun resultTy (ioTy resultTy))
        ]
        (ioTy resultTy)
    failureHandler =
      CLam
        (CoreBinder allocaBytesError ioErrorTy)
        (CPrimOp PrimIOThen [freeAction, CPrimOp PrimIOError [var allocaBytesError ioErrorTy] (ioTy resultTy)] (ioTy resultTy))
        (CTyFun ioErrorTy (ioTy resultTy))

  withMallocedPointer pointer resultTy action =
    CPrimOp PrimIOCatch [successAction, failureHandler] (ioTy resultTy)
   where
    freeAction = CPrimOp PrimFree [pointer] ioUnitTy
    successAction =
      CPrimOp
        PrimIOBind
        [ action
        , CLam
            (CoreBinder allocaBytesResult resultTy)
            (CPrimOp PrimIOThen [freeAction, ioReturn resultTy (var allocaBytesResult resultTy)] (ioTy resultTy))
            (CTyFun resultTy (ioTy resultTy))
        ]
        (ioTy resultTy)
    failureHandler =
      CLam
        (CoreBinder allocaBytesError ioErrorTy)
        (CPrimOp PrimIOThen [freeAction, CPrimOp PrimIOError [var allocaBytesError ioErrorTy] (ioTy resultTy)] (ioTy resultTy))
        (CTyFun ioErrorTy (ioTy resultTy))

  reallocRhs =
    CTypeLam
      [a, b]
      ( lam reallocDict storableDictB $
          lam reallocPointer ptrA $
            CPrimOp PrimReallocBytes [var reallocPointer ptrA, storableSizeExpr b bTy storableDictB (var reallocDict storableDictB)] (ioTy ptrB)
      )
      reallocTy

  advancePtrRhs =
    CTypeLam
      [a]
      ( lam arrayDict storableDictA $
          lam arrayPointer ptrA $
            lam arrayCount intTy $
              CPrimOp PrimPtrPlus [var arrayPointer ptrA, CPrimOp PrimMul [var arrayCount intTy, storableSizeExpr a aTy storableDictA (var arrayDict storableDictA)] intTy] ptrA
      )
      advancePtrTy

  mallocArrayRhs extra =
    CTypeLam
      [a]
      ( lam arrayDict storableDictA $
          lam arrayCount intTy $
            CPrimOp PrimMallocBytes [arrayByteCount extra (var arrayDict storableDictA) (var arrayCount intTy)] (ioTy ptrA)
      )
      mallocArrayTy

  allocaArrayRhs extra =
    CTypeLam
      [a, b]
      ( lam arrayDict storableDictA $
          lam arrayCount intTy $
            lam arrayContinuation (CTyFun ptrA (ioTy bTy)) $
              allocaBytesBody ptrA bTy (arrayByteCount extra (var arrayDict storableDictA) (var arrayCount intTy)) (var arrayContinuation (CTyFun ptrA (ioTy bTy)))
      )
      allocaArrayTy

  reallocArrayRhs extra =
    CTypeLam
      [a]
      ( lam arrayDict storableDictA $
          lam arrayPointer ptrA $
            lam arrayCount intTy $
              CPrimOp PrimReallocBytes [var arrayPointer ptrA, arrayByteCount extra (var arrayDict storableDictA) (var arrayCount intTy)] (ioTy ptrA)
      )
      reallocArrayTy

  arrayByteCount extra dict count =
    CPrimOp PrimMul [CPrimOp PrimAdd [count, intLiteral extra] intTy, storableSizeExpr a aTy storableDictA dict] intTy

  advancePtrExpr dict pointer count =
    CPrimOp PrimPtrPlus [pointer, CPrimOp PrimMul [count, storableSizeExpr a aTy storableDictA dict] intTy] ptrA

  peekStorable dict pointer =
    apply
      (apply
        (specialize (preludeTermName "peek" (-1503)) peekSelectorTy [aTy] (CTyFun storableDictA (CTyFun ptrA (ioTy aTy))))
        dict
        (CTyFun ptrA (ioTy aTy)))
      pointer
      (ioTy aTy)

  pokeStorable dict pointer value =
    apply
      (apply
        (apply
          (specialize (preludeTermName "poke" (-1504)) pokeSelectorTy [aTy] (CTyFun storableDictA (CTyFun ptrA (CTyFun aTy ioUnitTy))))
          dict
          (CTyFun ptrA (CTyFun aTy ioUnitTy)))
        pointer
        (CTyFun aTy ioUnitTy))
      value
      ioUnitTy

  eqAValue dict lhs rhs =
    apply
      (apply
        (apply
          (specialize eqSelectorName eqSelectorTy [aTy] (CTyFun eqDictA (CTyFun aTy (CTyFun aTy boolTy))))
          dict
          (CTyFun aTy (CTyFun aTy boolTy)))
        lhs
        (CTyFun aTy boolTy))
      rhs
      boolTy
   where
    eqSelectorName = preludeTermName "==" (-1401)
    eqClassA = preludeTypeVariable "a" (-1301)
    eqClassATy = CTyVar eqClassA
    eqClassDictA = CTyApp (CTyCon (classDictionaryTypeName builtinEqClassName)) eqClassATy
    eqSelectorTy = CTyForall [eqClassA] (CTyFun eqClassDictA (CTyFun eqClassATy (CTyFun eqClassATy boolTy)))

  listLengthExpr elementTy xs =
    let lenName = builtinLocalTermName "$foreign_list_length" (-6733)
        lenArg = builtinLocalTermName "$foreign_list_length_xs" (-6734)
        lenHead = builtinLocalTermName "$foreign_list_length_x" (-6735)
        lenTail = builtinLocalTermName "$foreign_list_length_tail" (-6736)
        lenCase = builtinLocalTermName "$foreign_list_length_case" (-6737)
        listTy_ = CTyList elementTy
        lenTy = CTyFun listTy_ intTy
        recursive =
          apply (var lenName lenTy) (var lenTail listTy_) intTy
        lenRhs =
          lam lenArg listTy_ $
            listCase
              (var lenArg listTy_)
              lenCase
              elementTy
              intTy
              (intLiteral 0)
              lenHead
              lenTail
              (CPrimOp PrimAdd [intLiteral 1, recursive] intTy)
     in CLet
          (CoreRec [(CoreBinder lenName lenTy, lenRhs)])
          (apply (var lenName lenTy) xs intTy)
          intTy

  peekArrayRhs functionName =
    let dict = var arrayDict storableDictA
        count = var arrayCount intTy
        pointer = var arrayPointer ptrA
        recursive =
          \nextCount nextPtr ->
            CApp
              ( CApp
                  ( CApp
                      (specialize functionName peekArrayTy [aTy] (CTyFun storableDictA (CTyFun intTy (CTyFun ptrA (ioTy listA)))))
                      dict
                      (CTyFun intTy (CTyFun ptrA (ioTy listA)))
                  )
                  nextCount
                  (CTyFun ptrA (ioTy listA))
              )
              nextPtr
              (ioTy listA)
        peekTail =
          \value ->
            CPrimOp
              PrimIOBind
              [ recursive (CPrimOp PrimSub [count, intLiteral 1] intTy) (advancePtrExpr dict pointer (intLiteral 1))
              , CLam (CoreBinder arrayTail listA) (ioReturn listA (cons aTy value (var arrayTail listA))) (CTyFun listA (ioTy listA))
              ]
              (ioTy listA)
        peekBody =
          boolCase
            (CPrimOp PrimLt [count, intLiteral 1] boolTy)
            arrayCase
            (ioTy listA)
            (ioReturn listA (nil aTy))
            ( CPrimOp
                PrimIOBind
                [ peekStorable dict pointer
                , CLam (CoreBinder arrayValue aTy) (peekTail (var arrayValue aTy)) (CTyFun aTy (ioTy listA))
                ]
                (ioTy listA)
            )
     in CTypeLam [a] (lam arrayDict storableDictA (lam arrayCount intTy (lam arrayPointer ptrA peekBody))) peekArrayTy

  pokeArrayRhs functionName =
    let dict = var arrayDict storableDictA
        pointer = var arrayPointer ptrA
        values = var arrayValues listA
        recursive =
          \nextPtr rest ->
            CApp
              ( CApp
                  ( CApp
                      (specialize functionName pokeArrayTy [aTy] (CTyFun storableDictA (CTyFun ptrA (CTyFun listA ioUnitTy))))
                      dict
                      (CTyFun ptrA (CTyFun listA ioUnitTy))
                  )
                  nextPtr
                  (CTyFun listA ioUnitTy)
              )
              rest
              ioUnitTy
        pokeBody =
          listCase
            values
            arrayCase
            aTy
            ioUnitTy
            (ioReturn unitTy unitValue)
            arrayValue
            arrayRest
            ( CPrimOp
                PrimIOThen
                [ pokeStorable dict pointer (var arrayValue aTy)
                , recursive (advancePtrExpr dict pointer (intLiteral 1)) (var arrayRest listA)
                ]
                ioUnitTy
            )
     in CTypeLam [a] (lam arrayDict storableDictA (lam arrayPointer ptrA (lam arrayValues listA pokeBody))) pokeArrayTy

  peekArray0Rhs functionName =
    let storableDict = var arrayDict storableDictA
        equalityDict = var arrayEqDict eqDictA
        marker = var arrayMarker aTy
        pointer = var arrayPointer ptrA
        recursive nextPtr =
          CApp
            ( CApp
                ( CApp
                    ( CApp
                        (specialize functionName peekArray0Ty [aTy] (CTyFun storableDictA (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy listA))))))
                        storableDict
                        (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy listA))))
                    )
                    equalityDict
                    (CTyFun aTy (CTyFun ptrA (ioTy listA)))
                )
                marker
                (CTyFun ptrA (ioTy listA))
            )
            nextPtr
            (ioTy listA)
        consTail value =
          CPrimOp
            PrimIOBind
            [ recursive (advancePtrExpr storableDict pointer (intLiteral 1))
            , CLam (CoreBinder arrayTail listA) (ioReturn listA (cons aTy value (var arrayTail listA))) (CTyFun listA (ioTy listA))
            ]
            (ioTy listA)
        body =
          CPrimOp
            PrimIOBind
            [ peekStorable storableDict pointer
            , CLam
                (CoreBinder arrayValue aTy)
                ( boolCase
                    (eqAValue equalityDict (var arrayValue aTy) marker)
                    arrayCase
                    (ioTy listA)
                    (ioReturn listA (nil aTy))
                    (consTail (var arrayValue aTy))
                )
                (CTyFun aTy (ioTy listA))
            ]
            (ioTy listA)
     in CTypeLam [a] (lam arrayDict storableDictA (lam arrayEqDict eqDictA (lam arrayMarker aTy (lam arrayPointer ptrA body)))) peekArray0Ty

  pokeArray0Rhs =
    CTypeLam [a] (lam arrayDict storableDictA (lam arrayMarker aTy (lam arrayPointer ptrA (lam arrayValues listA body)))) pokeArray0Ty
   where
    dict = var arrayDict storableDictA
    marker = var arrayMarker aTy
    pointer = var arrayPointer ptrA
    values = var arrayValues listA
    len = listLengthExpr aTy values
    body =
      CPrimOp
        PrimIOThen
        [ CApp
            ( CApp
                ( CApp
                    (specialize (standardLibraryTermName "pokeArray") pokeArrayTy [aTy] (CTyFun storableDictA (CTyFun ptrA (CTyFun listA ioUnitTy))))
                    dict
                    (CTyFun ptrA (CTyFun listA ioUnitTy))
                )
                pointer
                (CTyFun listA ioUnitTy)
            )
            values
            ioUnitTy
        , pokeStorable dict (advancePtrExpr dict pointer len) marker
        ]
        ioUnitTy

  lengthArray0Rhs functionName =
    let storableDict = var arrayDict storableDictA
        equalityDict = var arrayEqDict eqDictA
        marker = var arrayMarker aTy
        pointer = var arrayPointer ptrA
        recursive nextPtr =
          CApp
            ( CApp
                ( CApp
                    ( CApp
                        (specialize functionName lengthArray0Ty [aTy] (CTyFun storableDictA (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy intTy))))))
                        storableDict
                        (CTyFun eqDictA (CTyFun aTy (CTyFun ptrA (ioTy intTy))))
                    )
                    equalityDict
                    (CTyFun aTy (CTyFun ptrA (ioTy intTy)))
                )
                marker
                (CTyFun ptrA (ioTy intTy))
            )
            nextPtr
            (ioTy intTy)
        countTail =
          CPrimOp
            PrimIOBind
            [ recursive (advancePtrExpr storableDict pointer (intLiteral 1))
            , CLam (CoreBinder arrayLength intTy) (ioReturn intTy (CPrimOp PrimAdd [intLiteral 1, var arrayLength intTy] intTy)) (CTyFun intTy (ioTy intTy))
            ]
            (ioTy intTy)
        body =
          CPrimOp
            PrimIOBind
            [ peekStorable storableDict pointer
            , CLam
                (CoreBinder arrayValue aTy)
                ( boolCase
                    (eqAValue equalityDict (var arrayValue aTy) marker)
                    arrayCase
                    (ioTy intTy)
                    (ioReturn intTy (intLiteral 0))
                    countTail
                )
                (CTyFun aTy (ioTy intTy))
            ]
            (ioTy intTy)
     in CTypeLam [a] (lam arrayDict storableDictA (lam arrayEqDict eqDictA (lam arrayMarker aTy (lam arrayPointer ptrA body)))) lengthArray0Ty

  newArrayRhs =
    CTypeLam [a] (lam arrayDict storableDictA (lam arrayValues listA body)) newArrayTy
   where
    dict = var arrayDict storableDictA
    values = var arrayValues listA
    len = listLengthExpr aTy values
    body =
      CPrimOp
        PrimIOBind
        [ CPrimOp PrimMallocBytes [arrayByteCount 0 dict len] (ioTy ptrA)
        , CLam
            (CoreBinder arrayPointer ptrA)
            ( CPrimOp
                PrimIOThen
                [ CApp
                    ( CApp
                        ( CApp
                            (specialize (standardLibraryTermName "pokeArray") pokeArrayTy [aTy] (CTyFun storableDictA (CTyFun ptrA (CTyFun listA ioUnitTy))))
                            dict
                            (CTyFun ptrA (CTyFun listA ioUnitTy))
                        )
                        (var arrayPointer ptrA)
                        (CTyFun listA ioUnitTy)
                    )
                    values
                    ioUnitTy
                , ioReturn ptrA (var arrayPointer ptrA)
                ]
                (ioTy ptrA)
            )
            (CTyFun ptrA (ioTy ptrA))
        ]
        (ioTy ptrA)

  newArray0Rhs =
    CTypeLam [a] (lam arrayDict storableDictA (lam arrayMarker aTy (lam arrayValues listA body))) newArray0Ty
   where
    dict = var arrayDict storableDictA
    marker = var arrayMarker aTy
    values = var arrayValues listA
    len = listLengthExpr aTy values
    body =
      CPrimOp
        PrimIOBind
        [ CPrimOp PrimMallocBytes [arrayByteCount 1 dict len] (ioTy ptrA)
        , CLam
            (CoreBinder arrayPointer ptrA)
            ( CPrimOp
                PrimIOThen
                [ CApp
                    ( CApp
                        ( CApp
                            ( CApp
                                (specialize (standardLibraryTermName "pokeArray0") pokeArray0Ty [aTy] (CTyFun storableDictA (CTyFun aTy (CTyFun ptrA (CTyFun listA ioUnitTy)))))
                                dict
                                (CTyFun aTy (CTyFun ptrA (CTyFun listA ioUnitTy)))
                            )
                            marker
                            (CTyFun ptrA (CTyFun listA ioUnitTy))
                        )
                        (var arrayPointer ptrA)
                        (CTyFun listA ioUnitTy)
                    )
                    values
                    ioUnitTy
                , ioReturn ptrA (var arrayPointer ptrA)
                ]
                (ioTy ptrA)
            )
            (CTyFun ptrA (ioTy ptrA))
        ]
        (ioTy ptrA)

  withArrayRhs =
    CTypeLam [a, b] (lam arrayDict storableDictA (lam arrayValues listA (lam arrayContinuation (CTyFun ptrA (ioTy bTy)) body))) withArrayTy
   where
    dict = var arrayDict storableDictA
    values = var arrayValues listA
    body =
      CPrimOp
        PrimIOBind
        [ CApp
            ( CApp
                (specialize (standardLibraryTermName "newArray") newArrayTy [aTy] (CTyFun storableDictA (CTyFun listA (ioTy ptrA))))
                dict
                (CTyFun listA (ioTy ptrA))
            )
            values
            (ioTy ptrA)
        , CLam (CoreBinder arrayPointer ptrA) (withMallocedPointer (var arrayPointer ptrA) bTy (var arrayContinuation (CTyFun ptrA (ioTy bTy)) `CApp` var arrayPointer ptrA $ ioTy bTy)) (CTyFun ptrA (ioTy bTy))
        ]
        (ioTy bTy)

  withArray0Rhs =
    CTypeLam [a, b] (lam arrayDict storableDictA (lam arrayMarker aTy (lam arrayValues listA (lam arrayContinuation (CTyFun ptrA (ioTy bTy)) body)))) withArray0Ty
   where
    dict = var arrayDict storableDictA
    marker = var arrayMarker aTy
    values = var arrayValues listA
    body =
      CPrimOp
        PrimIOBind
        [ CApp
            ( CApp
                ( CApp
                    (specialize (standardLibraryTermName "newArray0") newArray0Ty [aTy] (CTyFun storableDictA (CTyFun aTy (CTyFun listA (ioTy ptrA)))))
                    dict
                    (CTyFun aTy (CTyFun listA (ioTy ptrA)))
                )
                marker
                (CTyFun listA (ioTy ptrA))
            )
            values
            (ioTy ptrA)
        , CLam (CoreBinder arrayPointer ptrA) (withMallocedPointer (var arrayPointer ptrA) bTy (CApp (var arrayContinuation (CTyFun ptrA (ioTy bTy))) (var arrayPointer ptrA) (ioTy bTy))) (CTyFun ptrA (ioTy bTy))
        ]
        (ioTy bTy)

  withArrayLenRhs =
    CTypeLam [a, b] (lam arrayDict storableDictA (lam arrayValues listA (lam arrayContinuation (CTyFun intTy (CTyFun ptrA (ioTy bTy))) body))) withArrayLenTy
   where
    dict = var arrayDict storableDictA
    values = var arrayValues listA
    len = listLengthExpr aTy values
    body =
      CApp
        ( CApp
            ( CApp
                (specialize (standardLibraryTermName "withArray") withArrayTy [aTy, bTy] (CTyFun storableDictA (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))))
                dict
                (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))
            )
            values
            (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))
        )
        (CLam (CoreBinder arrayPointer ptrA) (CApp (CApp (var arrayContinuation (CTyFun intTy (CTyFun ptrA (ioTy bTy)))) len (CTyFun ptrA (ioTy bTy))) (var arrayPointer ptrA) (ioTy bTy)) (CTyFun ptrA (ioTy bTy)))
        (ioTy bTy)

  withArrayLen0Rhs =
    CTypeLam [a, b] (lam arrayDict storableDictA (lam arrayMarker aTy (lam arrayValues listA (lam arrayContinuation (CTyFun intTy (CTyFun ptrA (ioTy bTy))) body)))) withArrayLen0Ty
   where
    dict = var arrayDict storableDictA
    marker = var arrayMarker aTy
    values = var arrayValues listA
    lenWithTerminator = CPrimOp PrimAdd [listLengthExpr aTy values, intLiteral 1] intTy
    body =
      CApp
        ( CApp
            ( CApp
                ( CApp
                    (specialize (standardLibraryTermName "withArray0") withArray0Ty [aTy, bTy] (CTyFun storableDictA (CTyFun aTy (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))))))
                    dict
                    (CTyFun aTy (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))))
                )
                marker
                (CTyFun listA (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy)))
            )
            values
            (CTyFun (CTyFun ptrA (ioTy bTy)) (ioTy bTy))
        )
        (CLam (CoreBinder arrayPointer ptrA) (CApp (CApp (var arrayContinuation (CTyFun intTy (CTyFun ptrA (ioTy bTy)))) lenWithTerminator (CTyFun ptrA (ioTy bTy))) (var arrayPointer ptrA) (ioTy bTy)) (CTyFun ptrA (ioTy bTy)))
        (ioTy bTy)

  copyArrayRhs prim =
    CTypeLam
      [a]
      ( lam arrayDict storableDictA $
          lam copyDest ptrA $
            lam copySource ptrA $
              lam copyCount intTy $
                CPrimOp prim [var copyDest ptrA, var copySource ptrA, CPrimOp PrimMul [var copyCount intTy, storableSizeExpr a aTy storableDictA (var arrayDict storableDictA)] intTy] ioUnitTy
      )
      copyArrayTy

  peekCStringLenRhs prim ptrTy_ =
    lam cStringPair (CTyTuple [ptrTy_, intTy]) $
      CCase
        (var cStringPair (CTyTuple [ptrTy_, intTy]))
        (CoreBinder arrayCase (CTyTuple [ptrTy_, intTy]))
        [CoreAlt (ConstructorAlt (tupleDataConName 2)) [CoreBinder cStringPointer ptrTy_, CoreBinder cStringLength intTy] (CPrimOp prim [var cStringPointer ptrTy_, var cStringLength intTy] (ioTy stringTy))]
        (ioTy stringTy)

  newCStringLenRhs prim ptrTy_ tupleTy =
    lam cStringSource stringTy $
      CPrimOp
        PrimIOBind
        [ CPrimOp prim [var cStringSource stringTy] (ioTy ptrTy_)
        , CLam
            (CoreBinder cStringPointer ptrTy_)
            (ioReturn tupleTy (constructorApp (tupleDataConName 2) [ptrTy_, intTy] [var cStringPointer ptrTy_, listLengthExpr charTy (var cStringSource stringTy)] tupleTy))
            (CTyFun ptrTy_ (ioTy tupleTy))
        ]
        (ioTy tupleTy)

  withCStringRhs ptrTy_ =
    CTypeLam [a] (lam cStringSource stringTy (lam cStringContinuation (CTyFun ptrTy_ (ioTy aTy)) body)) (CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun ptrTy_ (ioTy aTy)) (ioTy aTy))))
   where
    body =
      CPrimOp
        PrimIOBind
        [ CPrimOp (if ptrTy_ == cWStringTy then PrimNewCWString else PrimNewCString) [var cStringSource stringTy] (ioTy ptrTy_)
        , CLam (CoreBinder cStringPointer ptrTy_) (withMallocedPointer (var cStringPointer ptrTy_) aTy (var cStringContinuation (CTyFun ptrTy_ (ioTy aTy)) `CApp` var cStringPointer ptrTy_ $ ioTy aTy)) (CTyFun ptrTy_ (ioTy aTy))
        ]
        (ioTy aTy)

  withCStringLenRhs tupleTy ptrTy_ =
    CTypeLam [a] (lam cStringSource stringTy (lam cStringContinuation (CTyFun tupleTy (ioTy aTy)) body)) (CTyForall [a] (CTyFun stringTy (CTyFun (CTyFun tupleTy (ioTy aTy)) (ioTy aTy))))
   where
    body =
      CPrimOp
        PrimIOBind
        [ newCStringLenRhs (if ptrTy_ == cWStringTy then PrimNewCWString else PrimNewCString) ptrTy_ tupleTy `CApp` var cStringSource stringTy $ ioTy tupleTy
        , CLam
            (CoreBinder cStringPair tupleTy)
            ( CCase
                (var cStringPair tupleTy)
                (CoreBinder arrayCase tupleTy)
                [ CoreAlt
                    (ConstructorAlt (tupleDataConName 2))
                    [CoreBinder cStringPointer ptrTy_, CoreBinder cStringLength intTy]
                    (withMallocedPointer (var cStringPointer ptrTy_) aTy (var cStringContinuation (CTyFun tupleTy (ioTy aTy)) `CApp` var cStringPair tupleTy $ ioTy aTy))
                ]
                (ioTy aTy)
            )
            (CTyFun tupleTy (ioTy aTy))
        ]
        (ioTy aTy)

  errnoToIOErrorRhs =
    lam errnoLocation stringTy $
      lam errnoValue errnoTy $
        lam errnoHandle maybeHandleTy $
          lam errnoFile maybeFilePathTy $
            ioErrorValue (errnoErrorType (var errnoValue errnoTy)) (var errnoLocation stringTy) (var errnoHandle maybeHandleTy) (var errnoFile maybeFilePathTy)

  isValidErrnoRhs =
    lam errnoValue errnoTy $
      boolOrChain [errnoEq (var errnoValue errnoTy) value | value <- validErrnoValues]

  boolOrChain = \case
    [] -> con falseDataConName boolTy
    predicate : rest ->
      boolCase
        predicate
        throwErrnoCase
        boolTy
        (con trueDataConName boolTy)
        (boolOrChain rest)

  errnoErrorType value =
    boolCase
      (errnoEq value 2)
      throwErrnoCase
      ioErrorTypeTy
      (CCon ioErrorDoesNotExistTypeDataConName ioErrorTypeTy)
      ( boolCase
          (boolOrChain [errnoEq value 1, errnoEq value 13])
          throwErrnoCase
          ioErrorTypeTy
          (CCon ioErrorPermissionTypeDataConName ioErrorTypeTy)
          ( boolCase
              (errnoEq value 17)
              throwErrnoCase
              ioErrorTypeTy
              (CCon ioErrorAlreadyExistsTypeDataConName ioErrorTypeTy)
              ( boolCase
                  (errnoEq value 28)
                  throwErrnoCase
                  ioErrorTypeTy
                  (CCon ioErrorFullTypeDataConName ioErrorTypeTy)
                  ( boolCase
                      (boolOrChain [errnoEq value 16, errnoEq value 48])
                      throwErrnoCase
                      ioErrorTypeTy
                      (CCon ioErrorAlreadyInUseTypeDataConName ioErrorTypeTy)
                      (CCon ioErrorIllegalOperationTypeDataConName ioErrorTypeTy)
                  )
              )
          )
      )
  errnoEq value intValue =
    CPrimOp (PrimFixedIntegral FixedInt32 FixedEq) [value, errnoLiteral intValue] boolTy
  errnoLiteral value =
    CPrimOp (PrimFixedIntegral FixedInt32 FixedFromInteger) [intLiteral value] errnoTy

  throwErrnoRhs =
    CTypeLam [a] (lam throwErrnoLocation stringTy (throwErrnoWithFile aTy (var throwErrnoLocation stringTy) (maybeNothing stringTy))) throwErrnoTy

  throwErrnoWithFile resultTy location maybeFile =
    CPrimOp
      PrimIOBind
      [ CPrimOp PrimGetErrno [] (ioTy errnoTy)
      , CLam
          (CoreBinder errnoValue errnoTy)
          (errnoIOError resultTy location maybeFile (var errnoValue errnoTy))
          (CTyFun errnoTy (ioTy resultTy))
      ]
      (ioTy resultTy)

  errnoIOError resultTy location maybeFile errno =
    CPrimOp PrimIOError [errnoToIOErrorCallWithFile location errno maybeFile] (ioTy resultTy)

  errnoToIOErrorCallWithFile location errno maybeFile =
    apply
      (apply
        (apply
          (apply errnoToIOErrorRhs location (CTyFun errnoTy (CTyFun maybeHandleTy (CTyFun maybeFilePathTy ioErrorTy))))
          errno
          (CTyFun maybeHandleTy (CTyFun maybeFilePathTy ioErrorTy)))
        (maybeNothing handleTy)
        (CTyFun maybeFilePathTy ioErrorTy))
      maybeFile
      ioErrorTy

  throwErrnoIfRhs =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoIfBody aTy (maybeNothing stringTy))))) throwErrnoIfTy
  throwErrnoIfBody resultTy maybeFile =
    CPrimOp
      PrimIOBind
      [ var throwErrnoAction (ioTy resultTy)
      , CLam
          (CoreBinder throwErrnoResult resultTy)
          ( boolCase
              (apply (var throwErrnoPredicate (CTyFun resultTy boolTy)) (var throwErrnoResult resultTy) boolTy)
              throwErrnoCase
              (ioTy resultTy)
              (throwErrnoWithFile resultTy (var throwErrnoLocation stringTy) maybeFile)
              (ioReturn resultTy (var throwErrnoResult resultTy))
          )
          (CTyFun resultTy (ioTy resultTy))
      ]
      (ioTy resultTy)

  throwErrnoIfUnitRhs =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [throwErrnoIfBody aTy (maybeNothing stringTy), ioReturn unitTy unitValue] ioUnitTy)))) throwErrnoIfUnitTy

  throwErrnoIfRetryRhs functionName =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoRetryBody aTy predicate retryAction Nothing)))) throwErrnoIfRetryTy
   where
    predicate value = apply (var throwErrnoPredicate (CTyFun aTy boolTy)) value boolTy
    retryAction = genericRetryCall functionName throwErrnoIfRetryTy aTy Nothing

  throwErrnoIfRetryUnitRhs _functionName =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [genericRetryCall (standardLibraryTermName "throwErrnoIfRetry") throwErrnoIfRetryTy aTy Nothing, ioReturn unitTy unitValue] ioUnitTy)))) throwErrnoIfRetryUnitTy

  throwErrnoIfMinus1Rhs =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoIfMinus1Body aTy (maybeNothing stringTy)))))) throwErrnoIfMinus1Ty
  throwErrnoIfMinus1UnitRhs =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [throwErrnoIfMinus1Body aTy (maybeNothing stringTy), ioReturn unitTy unitValue] ioUnitTy))))) throwErrnoIfMinus1UnitTy
  throwErrnoIfMinus1Body resultTy maybeFile =
    CPrimOp
      PrimIOBind
      [ var throwErrnoAction (ioTy resultTy)
      , CLam
          (CoreBinder throwErrnoResult resultTy)
          ( boolCase
              (minusOnePredicate resultTy (var throwErrnoResult resultTy))
              throwErrnoCase
              (ioTy resultTy)
              (throwErrnoWithFile resultTy (var throwErrnoLocation stringTy) maybeFile)
              (ioReturn resultTy (var throwErrnoResult resultTy))
          )
          (CTyFun resultTy (ioTy resultTy))
      ]
      (ioTy resultTy)

  throwErrnoIfMinus1RetryRhs functionName =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoRetryBody aTy predicate retryAction Nothing))))) throwErrnoIfMinus1RetryTy
   where
    predicate value = minusOnePredicate aTy value
    retryAction = minusOneRetryCall functionName throwErrnoIfMinus1RetryTy aTy Nothing

  throwErrnoIfMinus1RetryUnitRhs _functionName =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [minusOneRetryCall (standardLibraryTermName "throwErrnoIfMinus1Retry") throwErrnoIfMinus1RetryTy aTy Nothing, ioReturn unitTy unitValue] ioUnitTy))))) throwErrnoIfMinus1RetryUnitTy
  minusOnePredicate resultTy value =
    apply
      (apply
        (apply
          (specialize (preludeTermName "==" (-1401)) eqSelectorTy [resultTy] (CTyFun eqDictResult (CTyFun resultTy (CTyFun resultTy boolTy))))
          (var throwErrnoDictEq eqDictA)
          (CTyFun resultTy (CTyFun resultTy boolTy)))
        value
        (CTyFun resultTy boolTy))
      ( apply
          (apply
            (specialize (preludeTermName "fromInteger" (-1427)) fromIntegerSelectorTy [resultTy] (CTyFun numDictResult (CTyFun intTy resultTy)))
            (var throwErrnoDictNum numDictA)
            (CTyFun intTy resultTy))
          (intLiteral (-1))
          resultTy
      )
      boolTy
   where
    eqClassA = preludeTypeVariable "a" (-1301)
    eqClassATy = CTyVar eqClassA
    eqClassDictA = CTyApp (CTyCon (classDictionaryTypeName builtinEqClassName)) eqClassATy
    eqSelectorTy = CTyForall [eqClassA] (CTyFun eqClassDictA (CTyFun eqClassATy (CTyFun eqClassATy boolTy)))
    numClassA = preludeTypeVariable "a" (-1321)
    numClassATy = CTyVar numClassA
    numClassDictA = CTyApp (CTyCon (classDictionaryTypeName builtinNumClassName)) numClassATy
    fromIntegerSelectorTy = CTyForall [numClassA] (CTyFun numClassDictA (CTyFun intTy numClassATy))
    eqDictResult = CTyApp (CTyCon (classDictionaryTypeName builtinEqClassName)) resultTy
    numDictResult = CTyApp (CTyCon (classDictionaryTypeName builtinNumClassName)) resultTy

  throwErrnoIfNullRhs =
    CTypeLam [a] (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy ptrA) (throwErrnoIfNullBody ptrA (maybeNothing stringTy)))) throwErrnoIfNullTy

  throwErrnoIfNullBody pointerTy maybeFile =
    CPrimOp
      PrimIOBind
      [ var throwErrnoAction (ioTy pointerTy)
      , CLam
          (CoreBinder throwErrnoResult pointerTy)
          ( boolCase
              (CPrimOp PrimIsNullPtr [var throwErrnoResult pointerTy] boolTy)
              throwErrnoCase
              (ioTy pointerTy)
              (throwErrnoWithFile pointerTy (var throwErrnoLocation stringTy) maybeFile)
              (ioReturn pointerTy (var throwErrnoResult pointerTy))
          )
          (CTyFun pointerTy (ioTy pointerTy))
      ]
      (ioTy pointerTy)

  throwErrnoIfNullRetryRhs functionName =
    CTypeLam [a] (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy ptrA) (throwErrnoRetryBody ptrA predicate retryAction Nothing))) throwErrnoIfNullRetryTy
   where
    predicate value = CPrimOp PrimIsNullPtr [value] boolTy
    retryAction = nullRetryCall functionName throwErrnoIfNullRetryTy ptrA Nothing

  throwErrnoIfRetryMayBlockRhs functionName =
    CTypeLam [a, b] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (lam throwErrnoBlockAction (ioTy bTy) (throwErrnoRetryBody aTy predicate retryAction (Just bTy)))))) throwErrnoIfRetryMayBlockTy
   where
    predicate value = apply (var throwErrnoPredicate (CTyFun aTy boolTy)) value boolTy
    retryAction = genericRetryCall functionName throwErrnoIfRetryMayBlockTy aTy (Just bTy)

  throwErrnoIfRetryMayBlockUnitRhs _functionName =
    CTypeLam [a, b] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (lam throwErrnoBlockAction (ioTy bTy) (CPrimOp PrimIOThen [genericRetryCall (standardLibraryTermName "throwErrnoIfRetryMayBlock") throwErrnoIfRetryMayBlockTy aTy (Just bTy), ioReturn unitTy unitValue] ioUnitTy))))) throwErrnoIfRetryMayBlockUnitTy

  throwErrnoIfMinus1RetryMayBlockRhs functionName =
    CTypeLam [a, b] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (lam throwErrnoBlockAction (ioTy bTy) (throwErrnoRetryBody aTy predicate retryAction (Just bTy))))))) throwErrnoIfMinus1RetryMayBlockTy
   where
    predicate value = minusOnePredicate aTy value
    retryAction = minusOneRetryCall functionName throwErrnoIfMinus1RetryMayBlockTy aTy (Just bTy)

  throwErrnoIfMinus1RetryMayBlockUnitRhs _functionName =
    CTypeLam [a, b] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy aTy) (lam throwErrnoBlockAction (ioTy bTy) (CPrimOp PrimIOThen [minusOneRetryCall (standardLibraryTermName "throwErrnoIfMinus1RetryMayBlock") throwErrnoIfMinus1RetryMayBlockTy aTy (Just bTy), ioReturn unitTy unitValue] ioUnitTy)))))) throwErrnoIfMinus1RetryMayBlockUnitTy

  throwErrnoIfNullRetryMayBlockRhs functionName =
    CTypeLam [a, b] (lam throwErrnoLocation stringTy (lam throwErrnoAction (ioTy ptrA) (lam throwErrnoBlockAction (ioTy bTy) (throwErrnoRetryBody ptrA predicate retryAction (Just bTy))))) throwErrnoIfNullRetryMayBlockTy
   where
    predicate value = CPrimOp PrimIsNullPtr [value] boolTy
    retryAction = nullRetryCall functionName throwErrnoIfNullRetryMayBlockTy ptrA (Just bTy)

  throwErrnoRetryBody resultTy predicate retryAction maybeBlockTy =
    CPrimOp
      PrimIOBind
      [ var throwErrnoAction (ioTy resultTy)
      , CLam
          (CoreBinder throwErrnoResult resultTy)
          ( boolCase
              (predicate (var throwErrnoResult resultTy))
              throwErrnoCase
              (ioTy resultTy)
              ( CPrimOp
                  PrimIOBind
                  [ CPrimOp PrimGetErrno [] (ioTy errnoTy)
                  , CLam
                      (CoreBinder errnoValue errnoTy)
                      (retryErrnoDecision resultTy retryAction maybeBlockTy (var errnoValue errnoTy))
                      (CTyFun errnoTy (ioTy resultTy))
                  ]
                  (ioTy resultTy)
              )
              (ioReturn resultTy (var throwErrnoResult resultTy))
          )
          (CTyFun resultTy (ioTy resultTy))
      ]
      (ioTy resultTy)

  retryErrnoDecision resultTy retryAction maybeBlockTy currentErrno =
    boolCase
      (errnoEq currentErrno (errnoConstant "eINTR" 4))
      throwErrnoRetryCase
      (ioTy resultTy)
      retryAction
      ( case maybeBlockTy of
          Nothing ->
            errnoIOError resultTy (var throwErrnoLocation stringTy) (maybeNothing stringTy) currentErrno
          Just blockTy ->
            boolCase
              (errnoWouldBlock currentErrno)
              throwErrnoWouldBlockCase
              (ioTy resultTy)
              (CPrimOp PrimIOThen [var throwErrnoBlockAction (ioTy blockTy), retryAction] (ioTy resultTy))
              (errnoIOError resultTy (var throwErrnoLocation stringTy) (maybeNothing stringTy) currentErrno)
      )

  errnoWouldBlock currentErrno =
    boolOrChain
      [ errnoEq currentErrno (errnoConstant "eAGAIN" 35)
      , errnoEq currentErrno (errnoConstant "eWOULDBLOCK" 35)
      ]

  errnoConstant occurrence fallback =
    fromMaybe fallback (errnoConstantValue occurrence)

  genericRetryCall functionName functionTy resultTy maybeBlockTy =
    case maybeBlockTy of
      Nothing ->
        let ioResultTy = ioTy resultTy
            predicateTy = CTyFun resultTy boolTy
            functionResultTy = CTyFun predicateTy (CTyFun stringTy (CTyFun ioResultTy ioResultTy))
            afterPredicateTy = CTyFun stringTy (CTyFun ioResultTy ioResultTy)
            afterLocationTy = CTyFun ioResultTy ioResultTy
            specialized = specialize functionName functionTy [resultTy] functionResultTy
            withPredicate = apply specialized (var throwErrnoPredicate predicateTy) afterPredicateTy
            withLocation = apply withPredicate (var throwErrnoLocation stringTy) afterLocationTy
         in apply withLocation (var throwErrnoAction ioResultTy) ioResultTy
      Just blockTy ->
        let ioResultTy = ioTy resultTy
            ioBlockTy = ioTy blockTy
            predicateTy = CTyFun resultTy boolTy
            functionResultTy = CTyFun predicateTy (CTyFun stringTy (CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy)))
            afterPredicateTy = CTyFun stringTy (CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy))
            afterLocationTy = CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy)
            afterActionTy = CTyFun ioBlockTy ioResultTy
            specialized = specialize functionName functionTy [resultTy, blockTy] functionResultTy
            withPredicate = apply specialized (var throwErrnoPredicate predicateTy) afterPredicateTy
            withLocation = apply withPredicate (var throwErrnoLocation stringTy) afterLocationTy
            withAction = apply withLocation (var throwErrnoAction ioResultTy) afterActionTy
         in apply withAction (var throwErrnoBlockAction ioBlockTy) ioResultTy

  minusOneRetryCall functionName functionTy resultTy maybeBlockTy =
    case maybeBlockTy of
      Nothing ->
        let ioResultTy = ioTy resultTy
            functionResultTy = CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun ioResultTy ioResultTy)))
            afterNumTy = CTyFun eqDictA (CTyFun stringTy (CTyFun ioResultTy ioResultTy))
            afterEqTy = CTyFun stringTy (CTyFun ioResultTy ioResultTy)
            afterLocationTy = CTyFun ioResultTy ioResultTy
            specialized = specialize functionName functionTy [resultTy] functionResultTy
            withNum = apply specialized (var throwErrnoDictNum numDictA) afterNumTy
            withEq = apply withNum (var throwErrnoDictEq eqDictA) afterEqTy
            withLocation = apply withEq (var throwErrnoLocation stringTy) afterLocationTy
         in apply withLocation (var throwErrnoAction ioResultTy) ioResultTy
      Just blockTy ->
        let ioResultTy = ioTy resultTy
            ioBlockTy = ioTy blockTy
            functionResultTy = CTyFun numDictA (CTyFun eqDictA (CTyFun stringTy (CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy))))
            afterNumTy = CTyFun eqDictA (CTyFun stringTy (CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy)))
            afterEqTy = CTyFun stringTy (CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy))
            afterLocationTy = CTyFun ioResultTy (CTyFun ioBlockTy ioResultTy)
            afterActionTy = CTyFun ioBlockTy ioResultTy
            specialized = specialize functionName functionTy [resultTy, blockTy] functionResultTy
            withNum = apply specialized (var throwErrnoDictNum numDictA) afterNumTy
            withEq = apply withNum (var throwErrnoDictEq eqDictA) afterEqTy
            withLocation = apply withEq (var throwErrnoLocation stringTy) afterLocationTy
            withAction = apply withLocation (var throwErrnoAction ioResultTy) afterActionTy
         in apply withAction (var throwErrnoBlockAction ioBlockTy) ioResultTy

  nullRetryCall functionName functionTy pointerTy maybeBlockTy =
    case maybeBlockTy of
      Nothing ->
        let ioPointerTy = ioTy pointerTy
            functionResultTy = CTyFun stringTy (CTyFun ioPointerTy ioPointerTy)
            afterLocationTy = CTyFun ioPointerTy ioPointerTy
            specialized = specialize functionName functionTy [aTy] functionResultTy
            withLocation = apply specialized (var throwErrnoLocation stringTy) afterLocationTy
         in apply withLocation (var throwErrnoAction ioPointerTy) ioPointerTy
      Just blockTy ->
        let ioPointerTy = ioTy pointerTy
            ioBlockTy = ioTy blockTy
            functionResultTy = CTyFun stringTy (CTyFun ioPointerTy (CTyFun ioBlockTy ioPointerTy))
            afterLocationTy = CTyFun ioPointerTy (CTyFun ioBlockTy ioPointerTy)
            afterActionTy = CTyFun ioBlockTy ioPointerTy
            specialized = specialize functionName functionTy [aTy, blockTy] functionResultTy
            withLocation = apply specialized (var throwErrnoLocation stringTy) afterLocationTy
            withAction = apply withLocation (var throwErrnoAction ioPointerTy) afterActionTy
         in apply withAction (var throwErrnoBlockAction ioBlockTy) ioPointerTy

  throwErrnoPathRhs =
    CTypeLam [a] (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (throwErrnoWithFile aTy (var throwErrnoLocation stringTy) (maybeJust stringTy (var throwErrnoPathName stringTy))))) throwErrnoPathTy

  throwErrnoPathIfRhs =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoIfBody aTy (maybeJust stringTy (var throwErrnoPathName stringTy))))))) throwErrnoPathIfTy

  throwErrnoPathIfUnitRhs =
    CTypeLam [a] (lam throwErrnoPredicate (CTyFun aTy boolTy) (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [throwErrnoIfBody aTy (maybeJust stringTy (var throwErrnoPathName stringTy)), ioReturn unitTy unitValue] ioUnitTy))))) throwErrnoPathIfUnitTy

  throwErrnoPathIfNullRhs =
    CTypeLam [a] (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (lam throwErrnoAction (ioTy ptrA) (throwErrnoIfNullBody ptrA (maybeJust stringTy (var throwErrnoPathName stringTy)))))) throwErrnoPathIfNullTy

  throwErrnoPathIfMinus1Rhs =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (lam throwErrnoAction (ioTy aTy) (throwErrnoIfMinus1Body aTy (maybeJust stringTy (var throwErrnoPathName stringTy)))))))) throwErrnoPathIfMinus1Ty

  throwErrnoPathIfMinus1UnitRhs =
    CTypeLam [a] (lam throwErrnoDictNum numDictA (lam throwErrnoDictEq eqDictA (lam throwErrnoLocation stringTy (lam throwErrnoPathName stringTy (lam throwErrnoAction (ioTy aTy) (CPrimOp PrimIOThen [throwErrnoIfMinus1Body aTy (maybeJust stringTy (var throwErrnoPathName stringTy)), ioReturn unitTy unitValue] ioUnitTy)))))) throwErrnoPathIfMinus1UnitTy

  ioErrorValue errorType message maybeHandle maybeFile =
    constructorApp ioErrorDataConName [] [errorType, message, maybeHandle, maybeFile] ioErrorTy

  ioThrowUserError resultTy message =
    CPrimOp PrimIOError [ioErrorValue (CCon ioErrorUserTypeDataConName ioErrorTypeTy) message (maybeNothing handleTy) (maybeNothing stringTy)] (ioTy resultTy)

  ioReturn resultTy value =
    CPrimOp PrimIOReturn [value] (ioTy resultTy)

  unitValue =
    CCon unitDataConName unitTy

  maybeNothing elementTy =
    constructorApp maybeNothingDataConName [elementTy] [] (CTyApp (CTyCon maybeTyConName) elementTy)

  maybeJust elementTy value =
    constructorApp maybeJustDataConName [elementTy] [value] (CTyApp (CTyCon maybeTyConName) elementTy)


  ioErrorPredicateRhs expectedType occurrence unique =
    lam (preludeTermName (occurrence <> "_error") unique) ioErrorTy $
      CCase
        (var (preludeTermName (occurrence <> "_error") unique) ioErrorTy)
        (CoreBinder (preludeTermName (occurrence <> "_case") (unique - 1)) ioErrorTy)
        [ CoreAlt
            (ConstructorAlt ioErrorDataConName)
            [ CoreBinder (preludeTermName (occurrence <> "_type") (unique - 2)) ioErrorTypeTy
            , CoreBinder (preludeTermName (occurrence <> "_message") (unique - 3)) stringTy
            , CoreBinder (preludeTermName (occurrence <> "_handle") (unique - 4)) maybeHandleTy
            , CoreBinder (preludeTermName (occurrence <> "_file") (unique - 5)) maybeFilePathTy
            ]
            ( CCase
                (var (preludeTermName (occurrence <> "_type") (unique - 2)) ioErrorTypeTy)
                (CoreBinder (preludeTermName (occurrence <> "_type_case") (unique - 6)) ioErrorTypeTy)
                [ CoreAlt (ConstructorAlt expectedType) [] (con trueDataConName boolTy)
                , CoreAlt DefaultAlt [] (con falseDataConName boolTy)
                ]
                boolTy
            )
        ]
        boolTy

  ioErrorAccessorRhs fieldTy field occurrence unique =
    lam (preludeTermName (occurrence <> "_error") unique) ioErrorTy $
      CCase
        (var (preludeTermName (occurrence <> "_error") unique) ioErrorTy)
        (CoreBinder (preludeTermName (occurrence <> "_case") (unique - 1)) ioErrorTy)
        [ CoreAlt
            (ConstructorAlt ioErrorDataConName)
            [ CoreBinder (preludeTermName (occurrence <> "_type") (unique - 2)) ioErrorTypeTy
            , CoreBinder (preludeTermName (occurrence <> "_message") (unique - 3)) stringTy
            , CoreBinder (preludeTermName (occurrence <> "_handle") (unique - 4)) maybeHandleTy
            , CoreBinder (preludeTermName (occurrence <> "_file") (unique - 5)) maybeFilePathTy
            ]
            (field (preludeTermName (occurrence <> "_message") (unique - 3)) (preludeTermName (occurrence <> "_handle") (unique - 4)) (preludeTermName (occurrence <> "_file") (unique - 5)))
        ]
        fieldTy

  ioErrorStringField message _handle _file = var message stringTy
  ioErrorHandleField _message handle _file = var handle maybeHandleTy
  ioErrorFilePathField _message _handle file = var file maybeFilePathTy

  maybeOverride elementTy oldMaybe newMaybe caseName justName =
    CCase
      newMaybe
      (CoreBinder caseName (CTyApp (CTyCon maybeTyConName) elementTy))
      [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] oldMaybe
      , CoreAlt (ConstructorAlt maybeJustDataConName) [CoreBinder justName elementTy] newMaybe
      ]
      (CTyApp (CTyCon maybeTyConName) elementTy)

controlMonadCorePair :: RName -> Maybe (CoreBinder, CoreExpr)
controlMonadCorePair name =
  case nameOcc name of
    "mapM" -> Just (CoreBinder name mapMTy, mapMRhs name)
    "mapM_" -> Just (CoreBinder name mapMUnitTy, mapMUnitRhs name)
    "forM" -> Just (CoreBinder name forMTy, forMRhs name)
    "forM_" -> Just (CoreBinder name forMUnitTy, forMUnitRhs name)
    "sequence" -> Just (CoreBinder name sequenceTy, sequenceRhs name)
    "sequence_" -> Just (CoreBinder name sequenceUnitTy, sequenceUnitRhs name)
    "=<<" -> Just (CoreBinder name bindFlippedTy, bindFlippedRhs)
    ">=>" -> Just (CoreBinder name composeKleisliTy, composeKleisliRhs)
    "<=<" -> Just (CoreBinder name composeKleisliFlippedTy, composeKleisliFlippedRhs)
    "forever" -> Just (CoreBinder name foreverTy, foreverRhs name)
    "void" -> Just (CoreBinder name controlVoidTy, controlVoidRhs)
    "join" -> Just (CoreBinder name joinTy, joinRhs)
    "msum" -> Just (CoreBinder name msumTy, msumRhs name)
    "filterM" -> Just (CoreBinder name filterMTy, filterMRhs name)
    "mapAndUnzipM" -> Just (CoreBinder name mapAndUnzipMTy, mapAndUnzipMRhs name)
    "zipWithM" -> Just (CoreBinder name zipWithMTy, zipWithMRhs name)
    "zipWithM_" -> Just (CoreBinder name zipWithMUnitTy, zipWithMUnitRhs name)
    "foldM" -> Just (CoreBinder name foldMTy, foldMRhs name)
    "foldM_" -> Just (CoreBinder name foldMUnitTy, foldMUnitRhs name)
    "replicateM" -> Just (CoreBinder name replicateMTy, replicateMRhs name)
    "replicateM_" -> Just (CoreBinder name replicateMUnitTy, replicateMUnitRhs name)
    "guard" -> Just (CoreBinder name guardTy, guardRhs)
    "when" -> Just (CoreBinder name whenTy, whenRhs)
    "unless" -> Just (CoreBinder name unlessTy, unlessRhs)
    "liftM" -> Just (CoreBinder name liftMTy, liftMRhs)
    "liftM2" -> Just (CoreBinder name liftM2Ty, liftM2Rhs)
    "liftM3" -> Just (CoreBinder name liftM3Ty, liftM3Rhs)
    "liftM4" -> Just (CoreBinder name liftM4Ty, liftM4Rhs)
    "liftM5" -> Just (CoreBinder name liftM5Ty, liftM5Rhs)
    "ap" -> Just (CoreBinder name apTy, apRhs)
    _ -> Nothing
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  c = preludeTypeVariable "c" (-1203)
  d = preludeTypeVariable "d" (-1204)
  e = preludeTypeVariable "e" (-1205)
  r = preludeTypeVariable "r" (-1206)
  f = preludeTypeVariable "f" (-1207)
  m = preludeTypeVariable "m" (-1208)
  mTy = CTyVar m
  fTy = CTyVar f
  aTy = CTyVar a
  bTy = CTyVar b
  cTy = CTyVar c
  dTy = CTyVar d
  eTy = CTyVar e
  rTy = CTyVar r
  listA = CTyList aTy
  listB = CTyList bTy
  listC = CTyList cTy
  mA = applyMonadCoreType mTy aTy
  mB = applyMonadCoreType mTy bTy
  mC = applyMonadCoreType mTy cTy
  mD = applyMonadCoreType mTy dTy
  mE = applyMonadCoreType mTy eTy
  mR = applyMonadCoreType mTy rTy
  mUnit = applyMonadCoreType mTy unitTy
  mBool = applyMonadCoreType mTy boolTy
  mListA = applyMonadCoreType mTy listA
  mListB = applyMonadCoreType mTy listB
  mListC = applyMonadCoreType mTy listC
  listMA = CTyList mA
  tupleBC = CTyTuple [bTy, cTy]
  tupleListBC = CTyTuple [listB, listC]
  mTupleBC = applyMonadCoreType mTy tupleBC
  mTupleListBC = applyMonadCoreType mTy tupleListBC
  mMA = applyMonadCoreType mTy mA
  funAB = CTyFun aTy bTy
  funAR = CTyFun aTy rTy
  funAMB = CTyFun aTy mB
  funBMC = CTyFun bTy mC
  monadDictM = monadDictCoreType mTy
  monadPlusDictM = monadPlusDictCoreType mTy
  functorDictF = functorDictCoreType fTy

  mapMTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun funAMB (CTyFun listA mListB)))
  mapMUnitTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun funAMB (CTyFun listA mUnit)))
  forMTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun listA (CTyFun funAMB mListB)))
  forMUnitTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun listA (CTyFun funAMB mUnit)))
  sequenceTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun listMA mListA))
  sequenceUnitTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun listMA mUnit))
  bindFlippedTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun funAMB (CTyFun mA mB)))
  composeKleisliTy = CTyForall [m, a, b, c] (CTyFun monadDictM (CTyFun funAMB (CTyFun funBMC (CTyFun aTy mC))))
  composeKleisliFlippedTy = CTyForall [m, a, b, c] (CTyFun monadDictM (CTyFun funBMC (CTyFun funAMB (CTyFun aTy mC))))
  foreverTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun mA mB))
  controlVoidTy = CTyForall [f, a] (CTyFun functorDictF (CTyFun (applyFunctorCoreType fTy aTy) (applyFunctorCoreType fTy unitTy)))
  joinTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun mMA mA))
  msumTy = CTyForall [m, a] (CTyFun monadPlusDictM (CTyFun listMA mA))
  filterMTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun (CTyFun aTy mBool) (CTyFun listA mListA)))
  mapAndUnzipMTy = CTyForall [m, a, b, c] (CTyFun monadDictM (CTyFun (CTyFun aTy mTupleBC) (CTyFun listA mTupleListBC)))
  zipWithMTy = CTyForall [m, a, b, c] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy mC)) (CTyFun listA (CTyFun listB mListC))))
  zipWithMUnitTy = CTyForall [m, a, b, c] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy mC)) (CTyFun listA (CTyFun listB mUnit))))
  foldMTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy mA)) (CTyFun aTy (CTyFun listB mA))))
  foldMUnitTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy mA)) (CTyFun aTy (CTyFun listB mUnit))))
  replicateMTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun intTy (CTyFun mA mListA)))
  replicateMUnitTy = CTyForall [m, a] (CTyFun monadDictM (CTyFun intTy (CTyFun mA mUnit)))
  guardTy = CTyForall [m] (CTyFun monadPlusDictM (CTyFun boolTy mUnit))
  whenTy = CTyForall [m] (CTyFun monadDictM (CTyFun boolTy (CTyFun mUnit mUnit)))
  unlessTy = CTyForall [m] (CTyFun monadDictM (CTyFun boolTy (CTyFun mUnit mUnit)))
  liftMTy = CTyForall [m, a, r] (CTyFun monadDictM (CTyFun funAR (CTyFun mA mR)))
  liftM2Ty = CTyForall [m, a, b, r] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy rTy)) (CTyFun mA (CTyFun mB mR))))
  liftM3Ty = CTyForall [m, a, b, c, r] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy (CTyFun cTy rTy))) (CTyFun mA (CTyFun mB (CTyFun mC mR)))))
  liftM4Ty = CTyForall [m, a, b, c, d, r] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy rTy)))) (CTyFun mA (CTyFun mB (CTyFun mC (CTyFun mD mR))))))
  liftM5Ty = CTyForall [m, a, b, c, d, e, r] (CTyFun monadDictM (CTyFun (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy (CTyFun eTy rTy))))) (CTyFun mA (CTyFun mB (CTyFun mC (CTyFun mD (CTyFun mE mR)))))))
  apTy = CTyForall [m, a, b] (CTyFun monadDictM (CTyFun (applyMonadCoreType mTy funAB) (CTyFun mA mB)))

  mapMRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam function funAMB (lam xs listA (mapMBody functionName mapMTy (var dict monadDictM) (var function funAMB) (var xs listA))))) mapMTy
   where
    dict = builtinLocalTermName "$control_mapM_dict" (-7608)
    function = builtinLocalTermName "$control_mapM_f" (-7609)
    xs = builtinLocalTermName "$control_mapM_xs" (-7610)

  forMRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam xs listA (lam function funAMB (forMBody functionName forMTy (var dict monadDictM) (var xs listA) (var function funAMB))))) forMTy
   where
    dict = builtinLocalTermName "$control_forM_dict" (-7611)
    xs = builtinLocalTermName "$control_forM_xs" (-7612)
    function = builtinLocalTermName "$control_forM_f" (-7613)

  mapMUnitRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam function funAMB (lam xs listA (mapMUnitBody functionName mapMUnitTy (var dict monadDictM) (var function funAMB) (var xs listA))))) mapMUnitTy
   where
    dict = builtinLocalTermName "$control_mapM__dict" (-7614)
    function = builtinLocalTermName "$control_mapM__f" (-7615)
    xs = builtinLocalTermName "$control_mapM__xs" (-7616)

  forMUnitRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam xs listA (lam function funAMB (forMUnitBody functionName forMUnitTy (var dict monadDictM) (var xs listA) (var function funAMB))))) forMUnitTy
   where
    dict = builtinLocalTermName "$control_forM__dict" (-7617)
    xs = builtinLocalTermName "$control_forM__xs" (-7618)
    function = builtinLocalTermName "$control_forM__f" (-7619)

  sequenceRhs functionName =
    CTypeLam [m, a] (lam dict monadDictM (lam actions listMA body)) sequenceTy
   where
    dict = builtinLocalTermName "$control_sequence_dict" (-7620)
    actions = builtinLocalTermName "$control_sequence_actions" (-7621)
    x = builtinLocalTermName "$control_sequence_x" (-7622)
    xs = builtinLocalTermName "$control_sequence_xs" (-7623)
    y = builtinLocalTermName "$control_sequence_y" (-7624)
    ys = builtinLocalTermName "$control_sequence_ys" (-7625)
    caseName = builtinLocalTermName "$control_sequence_case" (-7626)
    recursive =
      callPoly functionName sequenceTy [mTy, aTy] mListA [var dict monadDictM, var xs listMA]
    consContinuation =
      lam ys listA (returnCall mTy listA (var dict monadDictM) (consCore aTy (var y aTy) (var ys listA)))
    firstContinuation =
      lam y aTy (bindCall mTy listA listA (var dict monadDictM) recursive consContinuation)
    body =
      listCaseCore
        (var actions listMA)
        caseName
        mA
        mListA
        (returnCall mTy listA (var dict monadDictM) (nilCore aTy))
        x
        xs
        (bindCall mTy aTy listA (var dict monadDictM) (var x mA) firstContinuation)

  sequenceUnitRhs functionName =
    CTypeLam [m, a] (lam dict monadDictM (lam actions listMA body)) sequenceUnitTy
   where
    dict = builtinLocalTermName "$control_sequence__dict" (-7627)
    actions = builtinLocalTermName "$control_sequence__actions" (-7628)
    x = builtinLocalTermName "$control_sequence__x" (-7629)
    xs = builtinLocalTermName "$control_sequence__xs" (-7630)
    caseName = builtinLocalTermName "$control_sequence__case" (-7631)
    recursive =
      callPoly functionName sequenceUnitTy [mTy, aTy] mUnit [var dict monadDictM, var xs listMA]
    body =
      listCaseCore
        (var actions listMA)
        caseName
        mA
        mUnit
        (returnCall mTy unitTy (var dict monadDictM) unitCore)
        x
        xs
        (thenCall mTy aTy unitTy (var dict monadDictM) (var x mA) recursive)

  bindFlippedRhs =
    CTypeLam [m, a, b] (lam dict monadDictM (lam function funAMB (lam action mA (bindCall mTy aTy bTy (var dict monadDictM) (var action mA) (var function funAMB))))) bindFlippedTy
   where
    dict = builtinLocalTermName "$control_bind_flipped_dict" (-7632)
    function = builtinLocalTermName "$control_bind_flipped_f" (-7633)
    action = builtinLocalTermName "$control_bind_flipped_action" (-7634)

  composeKleisliRhs =
    CTypeLam [m, a, b, c] (lam dict monadDictM (lam fName funAMB (lam gName funBMC (lam xName aTy body)))) composeKleisliTy
   where
    dict = builtinLocalTermName "$control_kleisli_dict" (-7635)
    fName = builtinLocalTermName "$control_kleisli_f" (-7636)
    gName = builtinLocalTermName "$control_kleisli_g" (-7637)
    xName = builtinLocalTermName "$control_kleisli_x" (-7638)
    body =
      bindCall
        mTy
        bTy
        cTy
        (var dict monadDictM)
        (applyCore (var fName funAMB) (var xName aTy) mB)
        (var gName funBMC)

  composeKleisliFlippedRhs =
    CTypeLam [m, a, b, c] (lam dict monadDictM (lam gName funBMC (lam fName funAMB (lam xName aTy body)))) composeKleisliFlippedTy
   where
    dict = builtinLocalTermName "$control_kleisli_flip_dict" (-7639)
    gName = builtinLocalTermName "$control_kleisli_flip_g" (-7640)
    fName = builtinLocalTermName "$control_kleisli_flip_f" (-7641)
    xName = builtinLocalTermName "$control_kleisli_flip_x" (-7642)
    body =
      bindCall
        mTy
        bTy
        cTy
        (var dict monadDictM)
        (applyCore (var fName funAMB) (var xName aTy) mB)
        (var gName funBMC)

  foreverRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam action mA body)) foreverTy
   where
    dict = builtinLocalTermName "$control_forever_dict" (-7643)
    action = builtinLocalTermName "$control_forever_action" (-7644)
    recursive =
      callPoly functionName foreverTy [mTy, aTy, bTy] mB [var dict monadDictM, var action mA]
    body =
      thenCall mTy aTy bTy (var dict monadDictM) (var action mA) recursive

  controlVoidRhs =
    CTypeLam [f, a] (lam dict functorDictF (lam value fA body)) controlVoidTy
   where
    dict = builtinLocalTermName "$control_void_dict" (-7645)
    value = builtinLocalTermName "$control_void_value" (-7646)
    ignored = builtinLocalTermName "$control_void_ignored" (-7647)
    fA = applyFunctorCoreType fTy aTy
    toUnit = lam ignored aTy unitCore
    body = fmapCall fTy aTy unitTy (var dict functorDictF) toUnit (var value fA)

  joinRhs =
    CTypeLam [m, a] (lam dict monadDictM (lam action mMA body)) joinTy
   where
    dict = builtinLocalTermName "$control_join_dict" (-7648)
    action = builtinLocalTermName "$control_join_action" (-7649)
    body = bindCall mTy mA aTy (var dict monadDictM) (var action mMA) (idLam mA)

  msumRhs functionName =
    CTypeLam [m, a] (lam dict monadPlusDictM (lam actions listMA body)) msumTy
   where
    dict = builtinLocalTermName "$control_msum_dict" (-7650)
    actions = builtinLocalTermName "$control_msum_actions" (-7651)
    x = builtinLocalTermName "$control_msum_x" (-7652)
    xs = builtinLocalTermName "$control_msum_xs" (-7653)
    caseName = builtinLocalTermName "$control_msum_case" (-7654)
    recursive =
      callPoly functionName msumTy [mTy, aTy] mA [var dict monadPlusDictM, var xs listMA]
    body =
      listCaseCore
        (var actions listMA)
        caseName
        mA
        mA
        (mzeroCall mTy aTy (var dict monadPlusDictM))
        x
        xs
        (mplusCall mTy aTy (var dict monadPlusDictM) (var x mA) recursive)

  filterMRhs functionName =
    CTypeLam [m, a] (lam dict monadDictM (lam predicate (CTyFun aTy mBool) (lam xs listA body))) filterMTy
   where
    dict = builtinLocalTermName "$control_filterM_dict" (-7655)
    predicate = builtinLocalTermName "$control_filterM_predicate" (-7656)
    xs = builtinLocalTermName "$control_filterM_xs" (-7657)
    x = builtinLocalTermName "$control_filterM_x" (-7658)
    rest = builtinLocalTermName "$control_filterM_rest" (-7659)
    keep = builtinLocalTermName "$control_filterM_keep" (-7660)
    ys = builtinLocalTermName "$control_filterM_ys" (-7661)
    caseName = builtinLocalTermName "$control_filterM_case" (-7662)
    recursive =
      callPoly functionName filterMTy [mTy, aTy] mListA [var dict monadDictM, var predicate (CTyFun aTy mBool), var rest listA]
    returnFiltered =
      boolCaseCore
        "$control_filterM_bool"
        (-7663)
        (var keep boolTy)
        mListA
        (returnCall mTy listA (var dict monadDictM) (consCore aTy (var x aTy) (var ys listA)))
        (returnCall mTy listA (var dict monadDictM) (var ys listA))
    restContinuation =
      lam ys listA returnFiltered
    keepContinuation =
      lam keep boolTy (bindCall mTy listA listA (var dict monadDictM) recursive restContinuation)
    body =
      listCaseCore
        (var xs listA)
        caseName
        aTy
        mListA
        (returnCall mTy listA (var dict monadDictM) (nilCore aTy))
        x
        rest
        ( bindCall
            mTy
            boolTy
            listA
            (var dict monadDictM)
            (applyCore (var predicate (CTyFun aTy mBool)) (var x aTy) mBool)
            keepContinuation
        )

  mapAndUnzipMRhs functionName =
    CTypeLam [m, a, b, c] (lam dict monadDictM (lam function (CTyFun aTy mTupleBC) (lam xs listA body))) mapAndUnzipMTy
   where
    dict = builtinLocalTermName "$control_mapAndUnzipM_dict" (-7664)
    function = builtinLocalTermName "$control_mapAndUnzipM_f" (-7665)
    xs = builtinLocalTermName "$control_mapAndUnzipM_xs" (-7666)
    x = builtinLocalTermName "$control_mapAndUnzipM_x" (-7667)
    rest = builtinLocalTermName "$control_mapAndUnzipM_rest" (-7668)
    yz = builtinLocalTermName "$control_mapAndUnzipM_yz" (-7669)
    y = builtinLocalTermName "$control_mapAndUnzipM_y" (-7670)
    z = builtinLocalTermName "$control_mapAndUnzipM_z" (-7671)
    lists = builtinLocalTermName "$control_mapAndUnzipM_lists" (-7672)
    ys = builtinLocalTermName "$control_mapAndUnzipM_ys" (-7673)
    zs = builtinLocalTermName "$control_mapAndUnzipM_zs" (-7674)
    caseName = builtinLocalTermName "$control_mapAndUnzipM_case" (-7675)
    yzCase = builtinLocalTermName "$control_mapAndUnzipM_yz_case" (-7676)
    listsCase = builtinLocalTermName "$control_mapAndUnzipM_lists_case" (-7677)
    recursive =
      callPoly functionName mapAndUnzipMTy [mTy, aTy, bTy, cTy] mTupleListBC [var dict monadDictM, var function (CTyFun aTy mTupleBC), var rest listA]
    nilPair =
      tuple2Core listB listC (nilCore bTy) (nilCore cTy)
    consPair =
      tuple2Core listB listC (consCore bTy (var y bTy) (var ys listB)) (consCore cTy (var z cTy) (var zs listC))
    listsContinuation =
      lam lists tupleListBC $
        CCase
          (var lists tupleListBC)
          (CoreBinder listsCase tupleListBC)
          [CoreAlt (ConstructorAlt (tupleDataConName 2)) [CoreBinder ys listB, CoreBinder zs listC] (returnCall mTy tupleListBC (var dict monadDictM) consPair)]
          mTupleListBC
    yzContinuation =
      lam yz tupleBC $
        CCase
          (var yz tupleBC)
          (CoreBinder yzCase tupleBC)
          [CoreAlt (ConstructorAlt (tupleDataConName 2)) [CoreBinder y bTy, CoreBinder z cTy] (bindCall mTy tupleListBC tupleListBC (var dict monadDictM) recursive listsContinuation)]
          mTupleListBC
    body =
      listCaseCore
        (var xs listA)
        caseName
        aTy
        mTupleListBC
        (returnCall mTy tupleListBC (var dict monadDictM) nilPair)
        x
        rest
        (bindCall mTy tupleBC tupleListBC (var dict monadDictM) (applyCore (var function (CTyFun aTy mTupleBC)) (var x aTy) mTupleBC) yzContinuation)

  zipWithMRhs functionName =
    CTypeLam [m, a, b, c] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy mC)) (lam xs listA (lam ys listB body)))) zipWithMTy
   where
    dict = builtinLocalTermName "$control_zipWithM_dict" (-7678)
    function = builtinLocalTermName "$control_zipWithM_f" (-7679)
    xs = builtinLocalTermName "$control_zipWithM_xs" (-7680)
    ys = builtinLocalTermName "$control_zipWithM_ys" (-7681)
    x = builtinLocalTermName "$control_zipWithM_x" (-7682)
    xt = builtinLocalTermName "$control_zipWithM_xt" (-7683)
    y = builtinLocalTermName "$control_zipWithM_y" (-7684)
    yt = builtinLocalTermName "$control_zipWithM_yt" (-7685)
    z = builtinLocalTermName "$control_zipWithM_z" (-7686)
    zs = builtinLocalTermName "$control_zipWithM_zs" (-7687)
    xCase = builtinLocalTermName "$control_zipWithM_x_case" (-7688)
    yCase = builtinLocalTermName "$control_zipWithM_y_case" (-7689)
    nilResult = returnCall mTy listC (var dict monadDictM) (nilCore cTy)
    recursive =
      callPoly functionName zipWithMTy [mTy, aTy, bTy, cTy] mListC [var dict monadDictM, var function (CTyFun aTy (CTyFun bTy mC)), var xt listA, var yt listB]
    consContinuation =
      lam zs listC (returnCall mTy listC (var dict monadDictM) (consCore cTy (var z cTy) (var zs listC)))
    zContinuation =
      lam z cTy (bindCall mTy listC listC (var dict monadDictM) recursive consContinuation)
    pairAction =
      applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy mC))) (var x aTy) (CTyFun bTy mC)) (var y bTy) mC
    body =
      listCaseCore
        (var xs listA)
        xCase
        aTy
        mListC
        nilResult
        x
        xt
        ( listCaseCore
            (var ys listB)
            yCase
            bTy
            mListC
            nilResult
            y
            yt
            (bindCall mTy cTy listC (var dict monadDictM) pairAction zContinuation)
        )

  zipWithMUnitRhs functionName =
    CTypeLam [m, a, b, c] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy mC)) (lam xs listA (lam ys listB body)))) zipWithMUnitTy
   where
    dict = builtinLocalTermName "$control_zipWithM__dict" (-7690)
    function = builtinLocalTermName "$control_zipWithM__f" (-7691)
    xs = builtinLocalTermName "$control_zipWithM__xs" (-7692)
    ys = builtinLocalTermName "$control_zipWithM__ys" (-7693)
    x = builtinLocalTermName "$control_zipWithM__x" (-7694)
    xt = builtinLocalTermName "$control_zipWithM__xt" (-7695)
    y = builtinLocalTermName "$control_zipWithM__y" (-7696)
    yt = builtinLocalTermName "$control_zipWithM__yt" (-7697)
    xCase = builtinLocalTermName "$control_zipWithM__x_case" (-7698)
    yCase = builtinLocalTermName "$control_zipWithM__y_case" (-7699)
    nilResult = returnCall mTy unitTy (var dict monadDictM) unitCore
    recursive =
      callPoly functionName zipWithMUnitTy [mTy, aTy, bTy, cTy] mUnit [var dict monadDictM, var function (CTyFun aTy (CTyFun bTy mC)), var xt listA, var yt listB]
    pairAction =
      applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy mC))) (var x aTy) (CTyFun bTy mC)) (var y bTy) mC
    body =
      listCaseCore
        (var xs listA)
        xCase
        aTy
        mUnit
        nilResult
        x
        xt
        ( listCaseCore
            (var ys listB)
            yCase
            bTy
            mUnit
            nilResult
            y
            yt
            (thenCall mTy cTy unitTy (var dict monadDictM) pairAction recursive)
        )

  foldMRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy mA)) (lam initial aTy (lam xs listB body)))) foldMTy
   where
    dict = builtinLocalTermName "$control_foldM_dict" (-7700)
    function = builtinLocalTermName "$control_foldM_f" (-7701)
    initial = builtinLocalTermName "$control_foldM_initial" (-7702)
    xs = builtinLocalTermName "$control_foldM_xs" (-7703)
    x = builtinLocalTermName "$control_foldM_x" (-7704)
    rest = builtinLocalTermName "$control_foldM_rest" (-7705)
    next = builtinLocalTermName "$control_foldM_next" (-7706)
    caseName = builtinLocalTermName "$control_foldM_case" (-7707)
    recursive =
      callPoly functionName foldMTy [mTy, aTy, bTy] mA [var dict monadDictM, var function (CTyFun aTy (CTyFun bTy mA)), var next aTy, var rest listB]
    nextContinuation = lam next aTy recursive
    step =
      applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy mA))) (var initial aTy) (CTyFun bTy mA)) (var x bTy) mA
    body =
      listCaseCore
        (var xs listB)
        caseName
        bTy
        mA
        (returnCall mTy aTy (var dict monadDictM) (var initial aTy))
        x
        rest
        (bindCall mTy aTy aTy (var dict monadDictM) step nextContinuation)

  foldMUnitRhs functionName =
    CTypeLam [m, a, b] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy mA)) (lam initial aTy (lam xs listB body)))) foldMUnitTy
   where
    dict = builtinLocalTermName "$control_foldM__dict" (-7708)
    function = builtinLocalTermName "$control_foldM__f" (-7709)
    initial = builtinLocalTermName "$control_foldM__initial" (-7710)
    xs = builtinLocalTermName "$control_foldM__xs" (-7711)
    x = builtinLocalTermName "$control_foldM__x" (-7712)
    rest = builtinLocalTermName "$control_foldM__rest" (-7713)
    next = builtinLocalTermName "$control_foldM__next" (-7714)
    caseName = builtinLocalTermName "$control_foldM__case" (-7715)
    recursive =
      callPoly functionName foldMUnitTy [mTy, aTy, bTy] mUnit [var dict monadDictM, var function (CTyFun aTy (CTyFun bTy mA)), var next aTy, var rest listB]
    nextContinuation = lam next aTy recursive
    step =
      applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy mA))) (var initial aTy) (CTyFun bTy mA)) (var x bTy) mA
    body =
      listCaseCore
        (var xs listB)
        caseName
        bTy
        mUnit
        (returnCall mTy unitTy (var dict monadDictM) unitCore)
        x
        rest
        (bindCall mTy aTy unitTy (var dict monadDictM) step nextContinuation)

  replicateMRhs functionName =
    CTypeLam [m, a] (lam dict monadDictM (lam count intTy (lam action mA body))) replicateMTy
   where
    dict = builtinLocalTermName "$control_replicateM_dict" (-7716)
    count = builtinLocalTermName "$control_replicateM_count" (-7717)
    action = builtinLocalTermName "$control_replicateM_action" (-7718)
    x = builtinLocalTermName "$control_replicateM_x" (-7719)
    xs = builtinLocalTermName "$control_replicateM_xs" (-7720)
    recursive =
      callPoly functionName replicateMTy [mTy, aTy] mListA [var dict monadDictM, intSub (var count intTy) oneInt, var action mA]
    consContinuation =
      lam xs listA (returnCall mTy listA (var dict monadDictM) (consCore aTy (var x aTy) (var xs listA)))
    xContinuation =
      lam x aTy (bindCall mTy listA listA (var dict monadDictM) recursive consContinuation)
    body =
      boolCaseCore
        "$control_replicateM_positive"
        (-7721)
        (intLt zeroInt (var count intTy))
        mListA
        (bindCall mTy aTy listA (var dict monadDictM) (var action mA) xContinuation)
        (returnCall mTy listA (var dict monadDictM) (nilCore aTy))

  replicateMUnitRhs functionName =
    CTypeLam [m, a] (lam dict monadDictM (lam count intTy (lam action mA body))) replicateMUnitTy
   where
    dict = builtinLocalTermName "$control_replicateM__dict" (-7722)
    count = builtinLocalTermName "$control_replicateM__count" (-7723)
    action = builtinLocalTermName "$control_replicateM__action" (-7724)
    recursive =
      callPoly functionName replicateMUnitTy [mTy, aTy] mUnit [var dict monadDictM, intSub (var count intTy) oneInt, var action mA]
    body =
      boolCaseCore
        "$control_replicateM__positive"
        (-7725)
        (intLt zeroInt (var count intTy))
        mUnit
        (thenCall mTy aTy unitTy (var dict monadDictM) (var action mA) recursive)
        (returnCall mTy unitTy (var dict monadDictM) unitCore)

  guardRhs =
    CTypeLam [m] (lam dict monadPlusDictM (lam test boolTy body)) guardTy
   where
    dict = builtinLocalTermName "$control_guard_dict" (-7726)
    test = builtinLocalTermName "$control_guard_test" (-7727)
    monadDict = monadPlusSuperclassDict mTy (var dict monadPlusDictM)
    body =
      boolCaseCore
        "$control_guard_case"
        (-7728)
        (var test boolTy)
        mUnit
        (returnCall mTy unitTy monadDict unitCore)
        (mzeroCall mTy unitTy (var dict monadPlusDictM))

  whenRhs =
    CTypeLam [m] (lam dict monadDictM (lam test boolTy (lam action mUnit body))) whenTy
   where
    dict = builtinLocalTermName "$control_when_dict" (-7729)
    test = builtinLocalTermName "$control_when_test" (-7730)
    action = builtinLocalTermName "$control_when_action" (-7731)
    body =
      boolCaseCore
        "$control_when_case"
        (-7732)
        (var test boolTy)
        mUnit
        (var action mUnit)
        (returnCall mTy unitTy (var dict monadDictM) unitCore)

  unlessRhs =
    CTypeLam [m] (lam dict monadDictM (lam test boolTy (lam action mUnit body))) unlessTy
   where
    dict = builtinLocalTermName "$control_unless_dict" (-7733)
    test = builtinLocalTermName "$control_unless_test" (-7734)
    action = builtinLocalTermName "$control_unless_action" (-7735)
    body =
      boolCaseCore
        "$control_unless_case"
        (-7736)
        (var test boolTy)
        mUnit
        (returnCall mTy unitTy (var dict monadDictM) unitCore)
        (var action mUnit)

  liftMRhs =
    CTypeLam [m, a, r] (lam dict monadDictM (lam function funAR (lam action mA body))) liftMTy
   where
    dict = builtinLocalTermName "$control_liftM_dict" (-7737)
    function = builtinLocalTermName "$control_liftM_f" (-7738)
    action = builtinLocalTermName "$control_liftM_action" (-7739)
    x = builtinLocalTermName "$control_liftM_x" (-7740)
    body =
      bindCall
        mTy
        aTy
        rTy
        (var dict monadDictM)
        (var action mA)
        (lam x aTy (returnCall mTy rTy (var dict monadDictM) (applyCore (var function funAR) (var x aTy) rTy)))

  liftM2Rhs =
    CTypeLam [m, a, b, r] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy rTy)) (lam actionA mA (lam actionB mB body)))) liftM2Ty
   where
    dict = builtinLocalTermName "$control_liftM2_dict" (-7741)
    function = builtinLocalTermName "$control_liftM2_f" (-7742)
    actionA = builtinLocalTermName "$control_liftM2_action_a" (-7743)
    actionB = builtinLocalTermName "$control_liftM2_action_b" (-7744)
    x = builtinLocalTermName "$control_liftM2_x" (-7745)
    y = builtinLocalTermName "$control_liftM2_y" (-7746)
    body =
      bindCall mTy aTy rTy (var dict monadDictM) (var actionA mA) $
        lam x aTy $
          bindCall mTy bTy rTy (var dict monadDictM) (var actionB mB) $
            lam y bTy $
              returnCall mTy rTy (var dict monadDictM) (applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy rTy))) (var x aTy) (CTyFun bTy rTy)) (var y bTy) rTy)

  liftM3Rhs =
    CTypeLam [m, a, b, c, r] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy (CTyFun cTy rTy))) (lam actionA mA (lam actionB mB (lam actionC mC body))))) liftM3Ty
   where
    dict = builtinLocalTermName "$control_liftM3_dict" (-7747)
    function = builtinLocalTermName "$control_liftM3_f" (-7748)
    actionA = builtinLocalTermName "$control_liftM3_action_a" (-7749)
    actionB = builtinLocalTermName "$control_liftM3_action_b" (-7750)
    actionC = builtinLocalTermName "$control_liftM3_action_c" (-7751)
    x = builtinLocalTermName "$control_liftM3_x" (-7752)
    y = builtinLocalTermName "$control_liftM3_y" (-7753)
    z = builtinLocalTermName "$control_liftM3_z" (-7754)
    applied =
      applyCore
        (applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy (CTyFun cTy rTy)))) (var x aTy) (CTyFun bTy (CTyFun cTy rTy))) (var y bTy) (CTyFun cTy rTy))
        (var z cTy)
        rTy
    body =
      bindCall mTy aTy rTy (var dict monadDictM) (var actionA mA) $
        lam x aTy $
          bindCall mTy bTy rTy (var dict monadDictM) (var actionB mB) $
            lam y bTy $
              bindCall mTy cTy rTy (var dict monadDictM) (var actionC mC) $
                lam z cTy $
                  returnCall mTy rTy (var dict monadDictM) applied

  liftM4Rhs =
    CTypeLam [m, a, b, c, d, r] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy rTy)))) (lam actionA mA (lam actionB mB (lam actionC mC (lam actionD mD body)))))) liftM4Ty
   where
    dict = builtinLocalTermName "$control_liftM4_dict" (-7755)
    function = builtinLocalTermName "$control_liftM4_f" (-7756)
    actionA = builtinLocalTermName "$control_liftM4_action_a" (-7757)
    actionB = builtinLocalTermName "$control_liftM4_action_b" (-7758)
    actionC = builtinLocalTermName "$control_liftM4_action_c" (-7759)
    actionD = builtinLocalTermName "$control_liftM4_action_d" (-7760)
    x = builtinLocalTermName "$control_liftM4_x" (-7761)
    y = builtinLocalTermName "$control_liftM4_y" (-7762)
    z = builtinLocalTermName "$control_liftM4_z" (-7763)
    w = builtinLocalTermName "$control_liftM4_w" (-7764)
    applied =
      applyCore
        ( applyCore
            (applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy rTy))))) (var x aTy) (CTyFun bTy (CTyFun cTy (CTyFun dTy rTy)))) (var y bTy) (CTyFun cTy (CTyFun dTy rTy)))
            (var z cTy)
            (CTyFun dTy rTy)
        )
        (var w dTy)
        rTy
    body =
      bindCall mTy aTy rTy (var dict monadDictM) (var actionA mA) $
        lam x aTy $
          bindCall mTy bTy rTy (var dict monadDictM) (var actionB mB) $
            lam y bTy $
              bindCall mTy cTy rTy (var dict monadDictM) (var actionC mC) $
                lam z cTy $
                  bindCall mTy dTy rTy (var dict monadDictM) (var actionD mD) $
                    lam w dTy $
                      returnCall mTy rTy (var dict monadDictM) applied

  liftM5Rhs =
    CTypeLam [m, a, b, c, d, e, r] (lam dict monadDictM (lam function (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy (CTyFun eTy rTy))))) (lam actionA mA (lam actionB mB (lam actionC mC (lam actionD mD (lam actionE mE body))))))) liftM5Ty
   where
    dict = builtinLocalTermName "$control_liftM5_dict" (-7765)
    function = builtinLocalTermName "$control_liftM5_f" (-7766)
    actionA = builtinLocalTermName "$control_liftM5_action_a" (-7767)
    actionB = builtinLocalTermName "$control_liftM5_action_b" (-7768)
    actionC = builtinLocalTermName "$control_liftM5_action_c" (-7769)
    actionD = builtinLocalTermName "$control_liftM5_action_d" (-7770)
    actionE = builtinLocalTermName "$control_liftM5_action_e" (-7771)
    x = builtinLocalTermName "$control_liftM5_x" (-7772)
    y = builtinLocalTermName "$control_liftM5_y" (-7773)
    z = builtinLocalTermName "$control_liftM5_z" (-7774)
    w = builtinLocalTermName "$control_liftM5_w" (-7775)
    v = builtinLocalTermName "$control_liftM5_v" (-7776)
    applied =
      applyCore
        ( applyCore
            ( applyCore
                (applyCore (applyCore (var function (CTyFun aTy (CTyFun bTy (CTyFun cTy (CTyFun dTy (CTyFun eTy rTy)))))) (var x aTy) (CTyFun bTy (CTyFun cTy (CTyFun dTy (CTyFun eTy rTy))))) (var y bTy) (CTyFun cTy (CTyFun dTy (CTyFun eTy rTy))))
                (var z cTy)
                (CTyFun dTy (CTyFun eTy rTy))
            )
            (var w dTy)
            (CTyFun eTy rTy)
        )
        (var v eTy)
        rTy
    body =
      bindCall mTy aTy rTy (var dict monadDictM) (var actionA mA) $
        lam x aTy $
          bindCall mTy bTy rTy (var dict monadDictM) (var actionB mB) $
            lam y bTy $
              bindCall mTy cTy rTy (var dict monadDictM) (var actionC mC) $
                lam z cTy $
                  bindCall mTy dTy rTy (var dict monadDictM) (var actionD mD) $
                    lam w dTy $
                      bindCall mTy eTy rTy (var dict monadDictM) (var actionE mE) $
                        lam v eTy $
                          returnCall mTy rTy (var dict monadDictM) applied

  apRhs =
    CTypeLam [m, a, b] (lam dict monadDictM (lam functionAction (applyMonadCoreType mTy funAB) (lam action mA body))) apTy
   where
    dict = builtinLocalTermName "$control_ap_dict" (-7777)
    functionAction = builtinLocalTermName "$control_ap_function_action" (-7778)
    action = builtinLocalTermName "$control_ap_action" (-7779)
    function = builtinLocalTermName "$control_ap_function" (-7780)
    value = builtinLocalTermName "$control_ap_value" (-7781)
    body =
      bindCall mTy funAB bTy (var dict monadDictM) (var functionAction (applyMonadCoreType mTy funAB)) $
        lam function funAB $
          bindCall mTy aTy bTy (var dict monadDictM) (var action mA) $
            lam value aTy $
              returnCall mTy bTy (var dict monadDictM) (applyCore (var function funAB) (var value aTy) bTy)

  mapMBody functionName functionTy dict function xs =
    listCaseCore xs caseName aTy mListB (returnCall mTy listB dict (nilCore bTy)) x rest consBranch
   where
    x = builtinLocalTermName "$control_mapM_x" (-7782)
    rest = builtinLocalTermName "$control_mapM_rest" (-7783)
    y = builtinLocalTermName "$control_mapM_y" (-7784)
    ys = builtinLocalTermName "$control_mapM_ys" (-7785)
    caseName = builtinLocalTermName "$control_mapM_case" (-7786)
    recursive =
      callPoly functionName functionTy [mTy, aTy, bTy] mListB [dict, function, var rest listA]
    consContinuation =
      lam ys listB (returnCall mTy listB dict (consCore bTy (var y bTy) (var ys listB)))
    yContinuation =
      lam y bTy (bindCall mTy listB listB dict recursive consContinuation)
    consBranch =
      bindCall mTy bTy listB dict (applyCore function (var x aTy) mB) yContinuation

  forMBody functionName functionTy dict xs function =
    listCaseCore xs caseName aTy mListB (returnCall mTy listB dict (nilCore bTy)) x rest consBranch
   where
    x = builtinLocalTermName "$control_forM_x" (-7787)
    rest = builtinLocalTermName "$control_forM_rest" (-7788)
    y = builtinLocalTermName "$control_forM_y" (-7789)
    ys = builtinLocalTermName "$control_forM_ys" (-7790)
    caseName = builtinLocalTermName "$control_forM_case" (-7791)
    recursive =
      callPoly functionName functionTy [mTy, aTy, bTy] mListB [dict, var rest listA, function]
    consContinuation =
      lam ys listB (returnCall mTy listB dict (consCore bTy (var y bTy) (var ys listB)))
    yContinuation =
      lam y bTy (bindCall mTy listB listB dict recursive consContinuation)
    consBranch =
      bindCall mTy bTy listB dict (applyCore function (var x aTy) mB) yContinuation

  mapMUnitBody functionName functionTy dict function xs =
    listCaseCore xs caseName aTy mUnit (returnCall mTy unitTy dict unitCore) x rest consBranch
   where
    x = builtinLocalTermName "$control_mapM__x" (-7792)
    rest = builtinLocalTermName "$control_mapM__rest" (-7793)
    caseName = builtinLocalTermName "$control_mapM__case" (-7794)
    recursive =
      callPoly functionName functionTy [mTy, aTy, bTy] mUnit [dict, function, var rest listA]
    consBranch =
      thenCall mTy bTy unitTy dict (applyCore function (var x aTy) mB) recursive

  forMUnitBody functionName functionTy dict xs function =
    listCaseCore xs caseName aTy mUnit (returnCall mTy unitTy dict unitCore) x rest consBranch
   where
    x = builtinLocalTermName "$control_forM__x" (-7795)
    rest = builtinLocalTermName "$control_forM__rest" (-7796)
    caseName = builtinLocalTermName "$control_forM__case" (-7797)
    recursive =
      callPoly functionName functionTy [mTy, aTy, bTy] mUnit [dict, var rest listA, function]
    consBranch =
      thenCall mTy bTy unitTy dict (applyCore function (var x aTy) mB) recursive

  bindCall monadTy inputTy outputTy dict action continuation =
    callPoly (preludeTermName ">>=" (-1461)) monadBindSelectorCoreType [monadTy, inputTy, outputTy] (applyMonadCoreType monadTy outputTy) [dict, action, continuation]

  thenCall monadTy inputTy outputTy dict first second =
    callPoly (preludeTermName ">>" (-1462)) monadThenSelectorCoreType [monadTy, inputTy, outputTy] (applyMonadCoreType monadTy outputTy) [dict, first, second]

  returnCall monadTy valueTy dict value =
    callPoly (preludeTermName "return" (-1463)) monadReturnSelectorCoreType [monadTy, valueTy] (applyMonadCoreType monadTy valueTy) [dict, value]

  fmapCall functorTy inputTy outputTy dict function value =
    callPoly (preludeTermName "fmap" (-1491)) functorFmapSelectorCoreType [functorTy, inputTy, outputTy] (applyFunctorCoreType functorTy outputTy) [dict, function, value]

  mzeroCall monadTy valueTy dict =
    callPoly (preludeTermName "mzero" (-1495)) monadPlusMzeroSelectorCoreType [monadTy, valueTy] (applyMonadCoreType monadTy valueTy) [dict]

  mplusCall monadTy valueTy dict lhs rhs =
    callPoly (preludeTermName "mplus" (-1496)) monadPlusMplusSelectorCoreType [monadTy, valueTy] (applyMonadCoreType monadTy valueTy) [dict, lhs, rhs]

  monadPlusSuperclassDict monadTy dict =
    callPoly monadPlusMonadSelectorName monadPlusMonadSelectorCoreType [monadTy] (monadDictCoreType monadTy) [dict]

  callPoly functionName functionTy typeArguments resultTy arguments =
    foldl applyValue typed arguments
   where
    typed = CTypeApp (CVar functionName functionTy) typeArguments (foldr CTyFun resultTy (map exprType arguments))
    applyValue callee argument =
      let remainingResult =
            case exprType callee of
              CTyFun _ result -> result
              _ -> resultTy
       in CApp callee argument remainingResult

  idLam valueTy =
    lam value valueTy (var value valueTy)
   where
    value = builtinLocalTermName "$control_id_x" (-7798)

  tuple2Core leftTy rightTy left right =
    constructorApp (tupleDataConName 2) [leftTy, rightTy] [left, right] (CTyTuple [leftTy, rightTy])

  lam = coreLam
  var = CVar
  unitCore = CCon unitDataConName unitTy

  monadDictCoreType monadTy =
    CTyApp (CTyCon (classDictionaryTypeName builtinMonadClassName)) monadTy

  monadPlusDictCoreType monadTy =
    CTyApp (CTyCon (classDictionaryTypeName builtinMonadPlusClassName)) monadTy

  functorDictCoreType functorTy =
    CTyApp (CTyCon (classDictionaryTypeName builtinFunctorClassName)) functorTy

  selectorFunctorF = preludeTypeVariable "f" (-1391)
  selectorFunctorA = preludeTypeVariable "a" (-1201)
  selectorFunctorB = preludeTypeVariable "b" (-1202)
  selectorFunctorFTy = CTyVar selectorFunctorF
  selectorFunctorATy = CTyVar selectorFunctorA
  selectorFunctorBTy = CTyVar selectorFunctorB
  selectorMonadM = preludeTypeVariable "m" (-1361)
  selectorMonadA = preludeTypeVariable "a" (-1362)
  selectorMonadB = preludeTypeVariable "b" (-1363)
  selectorMonadMTy = CTyVar selectorMonadM
  selectorMonadATy = CTyVar selectorMonadA
  selectorMonadBTy = CTyVar selectorMonadB
  selectorMonadPlusM = preludeTypeVariable "m" (-1396)
  selectorMonadPlusA = preludeTypeVariable "a" (-1397)
  selectorMonadPlusMTy = CTyVar selectorMonadPlusM
  selectorMonadPlusATy = CTyVar selectorMonadPlusA

  functorFmapSelectorCoreType =
    CTyForall
      [selectorFunctorF, selectorFunctorA, selectorFunctorB]
      ( CTyFun
          (functorDictCoreType selectorFunctorFTy)
          ( CTyFun
              (CTyFun selectorFunctorATy selectorFunctorBTy)
              (CTyFun (applyFunctorCoreType selectorFunctorFTy selectorFunctorATy) (applyFunctorCoreType selectorFunctorFTy selectorFunctorBTy))
          )
      )

  monadBindSelectorCoreType =
    CTyForall
      [selectorMonadM, selectorMonadA, selectorMonadB]
      ( CTyFun
          (monadDictCoreType selectorMonadMTy)
          ( CTyFun
              (applyMonadCoreType selectorMonadMTy selectorMonadATy)
              (CTyFun (CTyFun selectorMonadATy (applyMonadCoreType selectorMonadMTy selectorMonadBTy)) (applyMonadCoreType selectorMonadMTy selectorMonadBTy))
          )
      )

  monadThenSelectorCoreType =
    CTyForall
      [selectorMonadM, selectorMonadA, selectorMonadB]
      ( CTyFun
          (monadDictCoreType selectorMonadMTy)
          (CTyFun (applyMonadCoreType selectorMonadMTy selectorMonadATy) (CTyFun (applyMonadCoreType selectorMonadMTy selectorMonadBTy) (applyMonadCoreType selectorMonadMTy selectorMonadBTy)))
      )

  monadReturnSelectorCoreType =
    CTyForall
      [selectorMonadM, selectorMonadA]
      (CTyFun (monadDictCoreType selectorMonadMTy) (CTyFun selectorMonadATy (applyMonadCoreType selectorMonadMTy selectorMonadATy)))

  monadPlusMzeroSelectorCoreType =
    CTyForall
      [selectorMonadPlusM, selectorMonadPlusA]
      (CTyFun (monadPlusDictCoreType selectorMonadPlusMTy) (applyMonadCoreType selectorMonadPlusMTy selectorMonadPlusATy))

  monadPlusMplusSelectorCoreType =
    CTyForall
      [selectorMonadPlusM, selectorMonadPlusA]
      ( CTyFun
          (monadPlusDictCoreType selectorMonadPlusMTy)
          ( CTyFun
              (applyMonadCoreType selectorMonadPlusMTy selectorMonadPlusATy)
              (CTyFun (applyMonadCoreType selectorMonadPlusMTy selectorMonadPlusATy) (applyMonadCoreType selectorMonadPlusMTy selectorMonadPlusATy))
          )
      )

  monadPlusMonadSelectorName =
    superclassSelectorName builtinMonadPlusInfo 0 (singleClassConstraint builtinMonadClassName (TyVar (classInfoVariable builtinMonadPlusInfo)))

  monadPlusMonadSelectorCoreType =
    CTyForall
      [selectorMonadPlusM]
      (CTyFun (monadPlusDictCoreType selectorMonadPlusMTy) (monadDictCoreType selectorMonadPlusMTy))

readSupportPreludeNames :: [RName]
readSupportPreludeNames =
  [ readAppendName
  , readBindName
  , readDropSpacesName
  , readExactName
  , readExactRawName
  , readExactGoName
  , readEndName
  , readCompleteName
  , readDefaultListName
  , readDefaultListTailName
  , readParenName
  , readLexName
  , readLexIdentTailName
  , readLexDigitTailName
  , readLexSymbolTailName
  , readIntName
  , readIntStartName
  , readIntDigitsName
  , readBoolName
  , readEscapeName
  , readCharName
  , readCharBodyName
  , readStringName
  , readStringCharsName
  ]

readAppendName, readBindName, readDropSpacesName, readExactName, readExactRawName, readExactGoName, readEndName, readCompleteName :: RName
readAppendName = preludeTermName "$read_append" (-2500)
readBindName = preludeTermName "$read_bind" (-2501)
readDropSpacesName = preludeTermName "$read_drop_spaces" (-2502)
readExactName = preludeTermName "$read_exact" (-2503)
readExactRawName = preludeTermName "$read_exact_raw" (-2504)
readExactGoName = preludeTermName "$read_exact_go" (-2505)
readEndName = preludeTermName "$read_end" (-2506)
readCompleteName = preludeTermName "$read_complete" (-2507)

readDefaultListName, readDefaultListTailName, readParenName, readLexName, readLexIdentTailName, readLexDigitTailName, readLexSymbolTailName :: RName
readDefaultListName = preludeTermName "$read_default_list" (-2508)
readDefaultListTailName = preludeTermName "$read_default_list_tail" (-2509)
readParenName = preludeTermName "$read_paren" (-2510)
readLexName = preludeTermName "$read_lex" (-2511)
readLexIdentTailName = preludeTermName "$read_lex_ident_tail" (-2512)
readLexDigitTailName = preludeTermName "$read_lex_digit_tail" (-2513)
readLexSymbolTailName = preludeTermName "$read_lex_symbol_tail" (-2514)

readIntName, readIntStartName, readIntDigitsName, readBoolName, readEscapeName, readCharName, readCharBodyName, readStringName, readStringCharsName :: RName
readIntName = preludeTermName "$read_int" (-2515)
readIntStartName = preludeTermName "$read_int_start" (-2516)
readIntDigitsName = preludeTermName "$read_int_digits" (-2517)
readBoolName = preludeTermName "$read_bool" (-2518)
readEscapeName = preludeTermName "$read_escape" (-2519)
readCharName = preludeTermName "$read_char" (-2520)
readCharBodyName = preludeTermName "$read_char_body" (-2521)
readStringName = preludeTermName "$read_string" (-2522)
readStringCharsName = preludeTermName "$read_string_chars" (-2523)

ratioSupportPreludeNames :: [RName]
ratioSupportPreludeNames =
  [ ratioReduceName
  , ratioGcdName
  , ratioGcdGoName
  , ratioSimplestName
  , ratioSimplestPositiveName
  ]

ratioReduceName, ratioGcdName, ratioGcdGoName, ratioSimplestName, ratioSimplestPositiveName :: RName
ratioReduceName = preludeTermName "$ratio_reduce" (-4000)
ratioGcdName = preludeTermName "$ratio_gcd" (-4001)
ratioGcdGoName = preludeTermName "$ratio_gcd_go" (-4002)
ratioSimplestName = preludeTermName "$ratio_simplest" (-4003)
ratioSimplestPositiveName = preludeTermName "$ratio_simplest_positive" (-4004)

ratioPreludeCorePair :: RName -> Maybe (CoreBinder, CoreExpr)
ratioPreludeCorePair name =
  case nameOcc name of
    "$ratio_reduce" -> Just ratioReduceCorePair
    "$ratio_gcd" -> Just ratioGcdCorePair
    "$ratio_gcd_go" -> Just ratioGcdGoCorePair
    "$ratio_simplest" -> Just ratioSimplestCorePair
    "$ratio_simplest_positive" -> Just ratioSimplestPositiveCorePair
    _ -> Nothing

ratioPercentCoreType :: CoreType
ratioPercentCoreType =
  CTyFun intTy (CTyFun intTy rationalCoreType)

ratioAccessorCoreType :: CoreType
ratioAccessorCoreType =
  CTyFun rationalCoreType intTy

ratioApproxRationalCoreType :: CoreType
ratioApproxRationalCoreType =
  CTyFun rationalCoreType (CTyFun rationalCoreType rationalCoreType)

ratioReduceCorePair :: (CoreBinder, CoreExpr)
ratioReduceCorePair =
  (CoreBinder ratioReduceName ratioPercentCoreType, ratioReduceRhs)

ratioGcdCorePair :: (CoreBinder, CoreExpr)
ratioGcdCorePair =
  (CoreBinder ratioGcdName ratioGcdCoreType, ratioGcdRhs)

ratioGcdGoCorePair :: (CoreBinder, CoreExpr)
ratioGcdGoCorePair =
  (CoreBinder ratioGcdGoName ratioGcdCoreType, ratioGcdGoRhs)

ratioSimplestCorePair :: (CoreBinder, CoreExpr)
ratioSimplestCorePair =
  (CoreBinder ratioSimplestName ratioSimplestCoreType, ratioSimplestRhs)

ratioSimplestPositiveCorePair :: (CoreBinder, CoreExpr)
ratioSimplestPositiveCorePair =
  (CoreBinder ratioSimplestPositiveName ratioSimplestPositiveCoreType, ratioSimplestPositiveRhs)

ratioGcdCoreType :: CoreType
ratioGcdCoreType =
  CTyFun intTy (CTyFun intTy intTy)

ratioSimplestCoreType :: CoreType
ratioSimplestCoreType =
  CTyFun rationalCoreType (CTyFun rationalCoreType rationalCoreType)

ratioSimplestPositiveCoreType :: CoreType
ratioSimplestPositiveCoreType =
  CTyFun intTy (CTyFun intTy (CTyFun intTy (CTyFun intTy rationalCoreType)))

ratioReduceRhs :: CoreExpr
ratioReduceRhs =
  coreLam xName intTy $
    coreLam yName intTy $
      boolCaseCore
        "$ratio_reduce_zero"
        (-4010)
        (CPrimOp PrimEq [y, zeroInt] boolTy)
        rationalCoreType
        (bottomCore "$ratio_reduce_zero_denominator" (-4011) rationalCoreType)
        ( letCore signedName intTy (intMul x (intSignumCore y)) $
            letCore positiveDenName intTy (intAbsCore y) $
              letCore gcdName intTy (ratioGcdCall signed positiveDen) $
                ratioIntCore (intQuot signed gcdValue) (intQuot positiveDen gcdValue)
        )
 where
  xName = builtinLocalTermName "$ratio_reduce_x" (-4012)
  yName = builtinLocalTermName "$ratio_reduce_y" (-4013)
  signedName = builtinLocalTermName "$ratio_reduce_signed" (-4014)
  positiveDenName = builtinLocalTermName "$ratio_reduce_den" (-4015)
  gcdName = builtinLocalTermName "$ratio_reduce_gcd" (-4016)
  x = CVar xName intTy
  y = CVar yName intTy
  signed = CVar signedName intTy
  positiveDen = CVar positiveDenName intTy
  gcdValue = CVar gcdName intTy

ratioGcdRhs :: CoreExpr
ratioGcdRhs =
  coreLam xName intTy $
    coreLam yName intTy $
      ratioGcdGoCall (intAbsCore x) (intAbsCore y)
 where
  xName = builtinLocalTermName "$ratio_gcd_x" (-4020)
  yName = builtinLocalTermName "$ratio_gcd_y" (-4021)
  x = CVar xName intTy
  y = CVar yName intTy

ratioGcdGoRhs :: CoreExpr
ratioGcdGoRhs =
  coreLam xName intTy $
    coreLam yName intTy $
      boolCaseCore
        "$ratio_gcd_go_zero"
        (-4030)
        (CPrimOp PrimEq [y, zeroInt] boolTy)
        intTy
        x
        (ratioGcdGoCall y (intRem x y))
 where
  xName = builtinLocalTermName "$ratio_gcd_go_x" (-4031)
  yName = builtinLocalTermName "$ratio_gcd_go_y" (-4032)
  x = CVar xName intTy
  y = CVar yName intTy

ratioGcdCall :: CoreExpr -> CoreExpr -> CoreExpr
ratioGcdCall lhs rhs =
  applyCore (applyCore (CVar ratioGcdName ratioGcdCoreType) lhs (CTyFun intTy intTy)) rhs intTy

ratioGcdGoCall :: CoreExpr -> CoreExpr -> CoreExpr
ratioGcdGoCall lhs rhs =
  applyCore (applyCore (CVar ratioGcdGoName ratioGcdCoreType) lhs (CTyFun intTy intTy)) rhs intTy

ratioSimplestRhs :: CoreExpr
ratioSimplestRhs =
  coreLam xName rationalCoreType $
    coreLam yName rationalCoreType $
      boolCaseCore
        "$ratio_simplest_swap"
        (-4070)
        (ratioLtCore y x)
        rationalCoreType
        (ratioSimplestCall y x)
        ( boolCaseCore
            "$ratio_simplest_equal"
            (-4071)
            (ratioEqCore x y)
            rationalCoreType
            x
            ( boolCaseCore
                "$ratio_simplest_positive"
                (-4072)
                (ratioLtCore zeroRatio x)
                rationalCoreType
                (ratioZipCore "$ratio_simplest_positive_fields" (-4073) x y rationalCoreType ratioSimplestPositiveCall)
                ( boolCaseCore
                    "$ratio_simplest_negative"
                    (-4079)
                    (ratioLtCore y zeroRatio)
                    rationalCoreType
                    (ratioZipCore "$ratio_simplest_negative_fields" (-4080) x y rationalCoreType $ \xN xD yN yD ->
                      ratioNegateCore (ratioSimplestPositiveCall (CPrimOp PrimNegate [yN] intTy) yD (CPrimOp PrimNegate [xN] intTy) xD)
                    )
                    zeroRatio
                )
            )
        )
 where
  xName = builtinLocalTermName "$ratio_simplest_x" (-4086)
  yName = builtinLocalTermName "$ratio_simplest_y" (-4087)
  x = CVar xName rationalCoreType
  y = CVar yName rationalCoreType
  zeroRatio = ratioIntCore zeroInt oneInt

ratioSimplestPositiveRhs :: CoreExpr
ratioSimplestPositiveRhs =
  coreLam nName intTy $
    coreLam dName intTy $
      coreLam nPrimeName intTy $
        coreLam dPrimeName intTy $
          letCore qName intTy (intQuot n d) $
            letCore rName intTy (intRem n d) $
              boolCaseCore
                "$ratio_simplest_positive_exact"
                (-4090)
                (CPrimOp PrimEq [r, zeroInt] boolTy)
                rationalCoreType
                (ratioIntCore q oneInt)
                ( letCore qPrimeName intTy (intQuot nPrime dPrime) $
                    letCore rPrimeName intTy (intRem nPrime dPrime) $
                      boolCaseCore
                        "$ratio_simplest_positive_step"
                        (-4091)
                        (boolNotCore "$ratio_simplest_positive_q_ne" (-4092) (CPrimOp PrimEq [q, qPrime] boolTy))
                        rationalCoreType
                        (ratioIntCore (intAdd q oneInt) oneInt)
                        ( ratioCaseCore
                            "$ratio_simplest_positive_recurse"
                            (-4093)
                            (ratioSimplestPositiveCall dPrime rPrime d r)
                            rationalCoreType
                            (-4094)
                            (-4095)
                            (\nextN nextD -> ratioIntCore (intAdd (intMul q nextN) nextD) nextN)
                        )
                )
 where
  nName = builtinLocalTermName "$ratio_simplest_positive_n" (-4096)
  dName = builtinLocalTermName "$ratio_simplest_positive_d" (-4097)
  nPrimeName = builtinLocalTermName "$ratio_simplest_positive_n_prime" (-4098)
  dPrimeName = builtinLocalTermName "$ratio_simplest_positive_d_prime" (-4099)
  qName = builtinLocalTermName "$ratio_simplest_positive_q" (-4100)
  rName = builtinLocalTermName "$ratio_simplest_positive_r" (-4101)
  qPrimeName = builtinLocalTermName "$ratio_simplest_positive_q_prime" (-4102)
  rPrimeName = builtinLocalTermName "$ratio_simplest_positive_r_prime" (-4103)
  n = CVar nName intTy
  d = CVar dName intTy
  nPrime = CVar nPrimeName intTy
  dPrime = CVar dPrimeName intTy
  q = CVar qName intTy
  r = CVar rName intTy
  qPrime = CVar qPrimeName intTy
  rPrime = CVar rPrimeName intTy

ratioSimplestCall :: CoreExpr -> CoreExpr -> CoreExpr
ratioSimplestCall lhs rhs =
  applyCore (applyCore (CVar ratioSimplestName ratioSimplestCoreType) lhs (CTyFun rationalCoreType rationalCoreType)) rhs rationalCoreType

ratioSimplestPositiveCall :: CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
ratioSimplestPositiveCall n d nPrime dPrime =
  applyCore
    ( applyCore
        ( applyCore
            (applyCore (CVar ratioSimplestPositiveName ratioSimplestPositiveCoreType) n (CTyFun intTy (CTyFun intTy (CTyFun intTy rationalCoreType))))
            d
            (CTyFun intTy (CTyFun intTy rationalCoreType))
        )
        nPrime
        (CTyFun intTy rationalCoreType)
    )
    dPrime
    rationalCoreType

ratioNumeratorRhs :: CoreExpr
ratioNumeratorRhs =
  ratioAccessorRhs "$ratio_numerator" (-4040) $ \numeratorExpr _ -> numeratorExpr

ratioDenominatorRhs :: CoreExpr
ratioDenominatorRhs =
  ratioAccessorRhs "$ratio_denominator" (-4050) $ \_ denominatorExpr -> denominatorExpr

ratioAccessorRhs :: Text -> Int -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ratioAccessorRhs occurrence unique selectField =
  coreLam valueName rationalCoreType $
    ratioCaseCore
      (occurrence <> "_case")
      (unique - 1)
      (CVar valueName rationalCoreType)
      intTy
      (unique - 2)
      (unique - 3)
      selectField
 where
  valueName = builtinLocalTermName (occurrence <> "_value") unique

ratioApproxRationalRhs :: CoreExpr
ratioApproxRationalRhs =
  coreLam valueName rationalCoreType $
    coreLam _epsilonName rationalCoreType $
      ratioSimplestCall
        (ratioSubCore (CVar valueName rationalCoreType) (CVar _epsilonName rationalCoreType))
        (ratioAddCore (CVar valueName rationalCoreType) (CVar _epsilonName rationalCoreType))
 where
  valueName = builtinLocalTermName "$approx_rational_value" (-4060)
  _epsilonName = builtinLocalTermName "$approx_rational_epsilon" (-4061)

ratioCaseCore :: Text -> Int -> CoreExpr -> CoreType -> Int -> Int -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ratioCaseCore occurrence caseUnique scrutinee resultTy numeratorUnique denominatorUnique body =
  CCase
    scrutinee
    (CoreBinder (builtinLocalTermName occurrence caseUnique) rationalCoreType)
    [ CoreAlt
        (ConstructorAlt ratioDataConName)
        [CoreBinder numeratorName intTy, CoreBinder denominatorName intTy]
        (body (CVar numeratorName intTy) (CVar denominatorName intTy))
    ]
    resultTy
 where
  numeratorName = builtinLocalTermName (occurrence <> "_n") numeratorUnique
  denominatorName = builtinLocalTermName (occurrence <> "_d") denominatorUnique

readPreludeCorePair :: RName -> Maybe (CoreBinder, CoreExpr)
readPreludeCorePair name =
  case nameOcc name of
    "$read_append" -> Just readAppendCorePair
    "$read_bind" -> Just readBindCorePair
    "$read_drop_spaces" -> Just readDropSpacesCorePair
    "$read_exact" -> Just readExactCorePair
    "$read_exact_raw" -> Just readExactRawCorePair
    "$read_exact_go" -> Just readExactGoCorePair
    "$read_end" -> Just readEndCorePair
    "$read_complete" -> Just readCompleteCorePair
    "$read_default_list" -> Just readDefaultListCorePair
    "$read_default_list_tail" -> Just readDefaultListTailCorePair
    "$read_paren" -> Just readParenCorePair
    "$read_lex" -> Just readLexCorePair
    "$read_lex_ident_tail" -> Just (readLexTailCorePair readLexIdentTailName readIsIdentCharCore readLexIdentTailCoreType)
    "$read_lex_digit_tail" -> Just (readLexTailCorePair readLexDigitTailName readIsDigitCore readLexDigitTailCoreType)
    "$read_lex_symbol_tail" -> Just (readLexTailCorePair readLexSymbolTailName readIsSymbolCore readLexSymbolTailCoreType)
    "$read_int" -> Just readIntCorePair
    "$read_int_start" -> Just readIntStartCorePair
    "$read_int_digits" -> Just readIntDigitsCorePair
    "$read_bool" -> Just readBoolCorePair
    "$read_escape" -> Just readEscapeCorePair
    "$read_char" -> Just readCharCorePair
    "$read_char_body" -> Just readCharBodyCorePair
    "$read_string" -> Just readStringCorePair
    "$read_string_chars" -> Just readStringCharsCorePair
    _ -> Nothing

readResultCoreType :: CoreType -> CoreType
readResultCoreType valueTy =
  CTyTuple [valueTy, stringTy]

readResultsCoreType :: CoreType -> CoreType
readResultsCoreType valueTy =
  CTyList (readResultCoreType valueTy)

readSCoreType :: CoreType -> CoreType
readSCoreType valueTy =
  CTyFun stringTy (readResultsCoreType valueTy)

readAppendCoreType :: CoreType
readAppendCoreType =
  CTyForall [a] (CTyFun listA (CTyFun listA listA))
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy

readBindCoreType :: CoreType
readBindCoreType =
  CTyForall [a, b] (CTyFun resultsA (CTyFun continuation resultsB))
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  resultsA = readResultsCoreType aTy
  resultsB = readResultsCoreType bTy
  continuation = CTyFun aTy (CTyFun stringTy resultsB)

readExactCoreType, readExactRawCoreType, readExactGoCoreType, readEndCoreType :: CoreType
readExactCoreType = CTyFun stringTy (CTyFun stringTy (readResultsCoreType unitTy))
readExactRawCoreType = readExactCoreType
readExactGoCoreType = readExactCoreType
readEndCoreType = readSCoreType unitTy

readCompleteCoreType :: CoreType
readCompleteCoreType =
  CTyForall [a] (CTyFun (readResultsCoreType aTy) aTy)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a

readDefaultListCoreType, readDefaultListTailCoreType :: CoreType
readDefaultListCoreType =
  CTyForall [a] (CTyFun (readSCoreType aTy) (readSCoreType listA))
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy
readDefaultListTailCoreType = readDefaultListCoreType

readParenCoreType :: CoreType
readParenCoreType =
  CTyForall [a] (CTyFun boolTy (CTyFun (readSCoreType aTy) (readSCoreType aTy)))
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a

readLexCoreType, readLexIdentTailCoreType, readLexDigitTailCoreType, readLexSymbolTailCoreType :: CoreType
readLexCoreType = readSCoreType stringTy
readLexIdentTailCoreType = readLexCoreType
readLexDigitTailCoreType = readLexCoreType
readLexSymbolTailCoreType = readLexCoreType

readIntCoreType, readBoolCoreType, readEscapeCoreType, readCharCoreType, readCharBodyCoreType, readStringCoreType, readStringCharsCoreType :: CoreType
readIntCoreType = readSCoreType intTy
readBoolCoreType = readSCoreType boolTy
readEscapeCoreType = readSCoreType charTy
readCharCoreType = readSCoreType charTy
readCharBodyCoreType = readSCoreType charTy
readStringCoreType = readSCoreType stringTy
readStringCharsCoreType = readSCoreType stringTy

readIntStartCoreType, readIntDigitsCoreType :: CoreType
readIntStartCoreType = CTyFun intTy readIntCoreType
readIntDigitsCoreType = CTyFun intTy (CTyFun intTy readIntCoreType)

readAppendCorePair :: (CoreBinder, CoreExpr)
readAppendCorePair =
  (CoreBinder readAppendName readAppendCoreType, CTypeLam [a] (lam xsName listA (lam ysName listA body)) readAppendCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy
  xsName = builtinLocalTermName "$read_append_xs" (-2540)
  ysName = builtinLocalTermName "$read_append_ys" (-2541)
  xName = builtinLocalTermName "$read_append_x" (-2542)
  restName = builtinLocalTermName "$read_append_rest" (-2543)
  caseName = builtinLocalTermName "$read_append_case" (-2544)
  lam = coreLam
  recursive =
    applyCore
      (applyCore (CTypeApp (CVar readAppendName readAppendCoreType) [aTy] (CTyFun listA (CTyFun listA listA))) (CVar restName listA) (CTyFun listA listA))
      (CVar ysName listA)
      listA
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      listA
      (CVar ysName listA)
      xName
      restName
      (consCore aTy (CVar xName aTy) recursive)

readBindCorePair :: (CoreBinder, CoreExpr)
readBindCorePair =
  (CoreBinder readBindName readBindCoreType, CTypeLam [a, b] (lam xsName resultsA (lam kName continuation body)) readBindCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  pairA = readResultCoreType aTy
  resultsA = CTyList pairA
  resultsB = readResultsCoreType bTy
  continuation = CTyFun aTy (CTyFun stringTy resultsB)
  xsName = builtinLocalTermName "$read_bind_xs" (-2545)
  kName = builtinLocalTermName "$read_bind_k" (-2546)
  pairName = builtinLocalTermName "$read_bind_pair" (-2547)
  restName = builtinLocalTermName "$read_bind_rest" (-2548)
  xName = builtinLocalTermName "$read_bind_x" (-2549)
  sName = builtinLocalTermName "$read_bind_s" (-2550)
  listCaseName = builtinLocalTermName "$read_bind_list_case" (-2551)
  pairCaseName = builtinLocalTermName "$read_bind_pair_case" (-2552)
  lam = coreLam
  kCall =
    applyCore
      (applyCore (CVar kName continuation) (CVar xName aTy) (CTyFun stringTy resultsB))
      (CVar sName stringTy)
      resultsB
  recursive =
    applyCore
      ( applyCore
          (CTypeApp (CVar readBindName readBindCoreType) [aTy, bTy] (CTyFun resultsA (CTyFun continuation resultsB)))
          (CVar restName resultsA)
          (CTyFun continuation resultsB)
      )
      (CVar kName continuation)
      resultsB
  consBody =
    CCase
      (CVar pairName pairA)
      (CoreBinder pairCaseName pairA)
      [ CoreAlt
          (ConstructorAlt (tupleDataConName 2))
          [CoreBinder xName aTy, CoreBinder sName stringTy]
          (readAppendCallCore (readResultCoreType bTy) kCall recursive)
      ]
      resultsB
  body =
    listCaseCore
      (CVar xsName resultsA)
      listCaseName
      pairA
      resultsB
      (nilCore (readResultCoreType bTy))
      pairName
      restName
      consBody

readDropSpacesCorePair :: (CoreBinder, CoreExpr)
readDropSpacesCorePair =
  (CoreBinder readDropSpacesName (CTyFun stringTy stringTy), lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_drop_input" (-2553)
  cName = builtinLocalTermName "$read_drop_c" (-2554)
  csName = builtinLocalTermName "$read_drop_cs" (-2555)
  caseName = builtinLocalTermName "$read_drop_case" (-2556)
  lam = coreLam
  input = CVar inputName stringTy
  rest = CVar csName stringTy
  recursive = applyCore (CVar readDropSpacesName (CTyFun stringTy stringTy)) rest stringTy
  body =
    listCaseCore
      input
      caseName
      charTy
      stringTy
      input
      cName
      csName
      (boolCaseCore "$read_drop_is_space" (-2557) (readIsSpaceCore (CVar cName charTy)) stringTy recursive input)

readExactCorePair :: (CoreBinder, CoreExpr)
readExactCorePair =
  (CoreBinder readExactName readExactCoreType, lam tokenName stringTy (lam inputName stringTy body))
 where
  tokenName = builtinLocalTermName "$read_exact_token" (-2558)
  inputName = builtinLocalTermName "$read_exact_input" (-2559)
  lam = coreLam
  stripped = applyCore (CVar readDropSpacesName (CTyFun stringTy stringTy)) (CVar inputName stringTy) stringTy
  body =
    applyCore
      (applyCore (CVar readExactGoName readExactGoCoreType) (CVar tokenName stringTy) (CTyFun stringTy (readResultsCoreType unitTy)))
      stripped
      (readResultsCoreType unitTy)

readExactRawCorePair :: (CoreBinder, CoreExpr)
readExactRawCorePair =
  (CoreBinder readExactRawName readExactRawCoreType, lam tokenName stringTy (lam inputName stringTy body))
 where
  tokenName = builtinLocalTermName "$read_exact_raw_token" (-2560)
  inputName = builtinLocalTermName "$read_exact_raw_input" (-2561)
  lam = coreLam
  body =
    applyCore
      (applyCore (CVar readExactGoName readExactGoCoreType) (CVar tokenName stringTy) (CTyFun stringTy (readResultsCoreType unitTy)))
      (CVar inputName stringTy)
      (readResultsCoreType unitTy)

readExactGoCorePair :: (CoreBinder, CoreExpr)
readExactGoCorePair =
  (CoreBinder readExactGoName readExactGoCoreType, lam tokenName stringTy (lam inputName stringTy body))
 where
  tokenName = builtinLocalTermName "$read_exact_go_token" (-2562)
  inputName = builtinLocalTermName "$read_exact_go_input" (-2563)
  tName = builtinLocalTermName "$read_exact_go_t" (-2564)
  tsName = builtinLocalTermName "$read_exact_go_ts" (-2565)
  cName = builtinLocalTermName "$read_exact_go_c" (-2566)
  csName = builtinLocalTermName "$read_exact_go_cs" (-2567)
  tokenCaseName = builtinLocalTermName "$read_exact_go_token_case" (-2568)
  inputCaseName = builtinLocalTermName "$read_exact_go_input_case" (-2569)
  lam = coreLam
  resultsTy = readResultsCoreType unitTy
  empty = nilCore (readResultCoreType unitTy)
  input = CVar inputName stringTy
  recursive =
    applyCore
      ( applyCore
          (CVar readExactGoName readExactGoCoreType)
          (CVar tsName stringTy)
          (CTyFun stringTy resultsTy)
      )
      (CVar csName stringTy)
      resultsTy
  inputCase =
    listCaseCore
      input
      inputCaseName
      charTy
      resultsTy
      empty
      cName
      csName
      (boolCaseCore "$read_exact_go_eq" (-2570) (CPrimOp PrimEq [CVar tName charTy, CVar cName charTy] boolTy) resultsTy recursive empty)
  body =
    listCaseCore
      (CVar tokenName stringTy)
      tokenCaseName
      charTy
      resultsTy
      (readSingleResultCore unitTy (CCon unitDataConName unitTy) input)
      tName
      tsName
      inputCase

readEndCorePair :: (CoreBinder, CoreExpr)
readEndCorePair =
  (CoreBinder readEndName readEndCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_end_input" (-2571)
  cName = builtinLocalTermName "$read_end_c" (-2572)
  csName = builtinLocalTermName "$read_end_cs" (-2573)
  caseName = builtinLocalTermName "$read_end_case" (-2574)
  lam = coreLam
  stripped = applyCore (CVar readDropSpacesName (CTyFun stringTy stringTy)) (CVar inputName stringTy) stringTy
  body =
    listCaseCore
      stripped
      caseName
      charTy
      (readResultsCoreType unitTy)
      (readSingleResultCore unitTy (CCon unitDataConName unitTy) emptyStringCore)
      cName
      csName
      (nilCore (readResultCoreType unitTy))

readCompleteCorePair :: (CoreBinder, CoreExpr)
readCompleteCorePair =
  (CoreBinder readCompleteName readCompleteCoreType, CTypeLam [a] (lam resultsName resultsTy body) readCompleteCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  pairTy = readResultCoreType aTy
  resultsTy = CTyList pairTy
  resultsName = builtinLocalTermName "$read_complete_results" (-2575)
  pairName = builtinLocalTermName "$read_complete_pair" (-2576)
  restResultsName = builtinLocalTermName "$read_complete_rest_results" (-2577)
  xName = builtinLocalTermName "$read_complete_x" (-2578)
  restName = builtinLocalTermName "$read_complete_rest" (-2579)
  endPairName = builtinLocalTermName "$read_complete_end_pair" (-2580)
  endRestName = builtinLocalTermName "$read_complete_end_rest" (-2581)
  resultCaseName = builtinLocalTermName "$read_complete_result_case" (-2582)
  restCaseName = builtinLocalTermName "$read_complete_rest_case" (-2583)
  pairCaseName = builtinLocalTermName "$read_complete_pair_case" (-2584)
  endCaseName = builtinLocalTermName "$read_complete_end_case" (-2585)
  lam = coreLam
  failure = readFailureCore aTy
  endResults =
    applyCore (CVar readEndName readEndCoreType) (CVar restName stringTy) (readResultsCoreType unitTy)
  endCase =
    listCaseCore
      endResults
      endCaseName
      (readResultCoreType unitTy)
      aTy
      failure
      endPairName
      endRestName
      (CVar xName aTy)
  pairCase =
    CCase
      (CVar pairName pairTy)
      (CoreBinder pairCaseName pairTy)
      [CoreAlt (ConstructorAlt (tupleDataConName 2)) [CoreBinder xName aTy, CoreBinder restName stringTy] endCase]
      aTy
  oneResultCase =
    listCaseCore
      (CVar restResultsName resultsTy)
      restCaseName
      pairTy
      aTy
      pairCase
      (builtinLocalTermName "$read_complete_extra" (-2586))
      (builtinLocalTermName "$read_complete_extras" (-2587))
      failure
  body =
    listCaseCore
      (CVar resultsName resultsTy)
      resultCaseName
      pairTy
      aTy
      failure
      pairName
      restResultsName
      oneResultCase

readDefaultListCorePair :: (CoreBinder, CoreExpr)
readDefaultListCorePair =
  (CoreBinder readDefaultListName readDefaultListCoreType, CTypeLam [a] (lam parserName parserTy (lam inputName stringTy body)) readDefaultListCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy
  parserTy = readSCoreType aTy
  listParserTy = readSCoreType listA
  inputName = builtinLocalTermName "$read_list_input" (-2588)
  parserName = builtinLocalTermName "$read_list_parser" (-2589)
  openUnitName = builtinLocalTermName "$read_list_open_unit" (-2590)
  afterOpenName = builtinLocalTermName "$read_list_after_open" (-2591)
  closeUnitName = builtinLocalTermName "$read_list_close_unit" (-2592)
  afterCloseName = builtinLocalTermName "$read_list_after_close" (-2593)
  xName = builtinLocalTermName "$read_list_x" (-2594)
  afterXName = builtinLocalTermName "$read_list_after_x" (-2595)
  xsName = builtinLocalTermName "$read_list_xs" (-2596)
  restName = builtinLocalTermName "$read_list_rest" (-2597)
  lam = coreLam
  emptyListParser =
    readBindCallCore
      unitTy
      listA
      (readExactCallCore "]" (CVar afterOpenName stringTy))
      (lam closeUnitName unitTy (lam afterCloseName stringTy (readSingleResultCore listA (nilCore aTy) (CVar afterCloseName stringTy))))
  consParser =
    readBindCallCore
      aTy
      listA
      (applyCore (CVar parserName parserTy) (CVar afterOpenName stringTy) (readResultsCoreType aTy))
      ( lam xName aTy $
          lam afterXName stringTy $
            readBindCallCore
              listA
              listA
              (applyCore (applyCore (CTypeApp (CVar readDefaultListTailName readDefaultListTailCoreType) [aTy] (CTyFun parserTy listParserTy)) (CVar parserName parserTy) listParserTy) (CVar afterXName stringTy) (readResultsCoreType listA))
              (lam xsName listA (lam restName stringTy (readSingleResultCore listA (consCore aTy (CVar xName aTy) (CVar xsName listA)) (CVar restName stringTy))))
      )
  afterOpen =
    readAppendCallCore (readResultCoreType listA) emptyListParser consParser
  body =
    readBindCallCore
      unitTy
      listA
      (readExactCallCore "[" (CVar inputName stringTy))
      (lam openUnitName unitTy (lam afterOpenName stringTy afterOpen))

readDefaultListTailCorePair :: (CoreBinder, CoreExpr)
readDefaultListTailCorePair =
  (CoreBinder readDefaultListTailName readDefaultListTailCoreType, CTypeLam [a] (lam parserName parserTy (lam inputName stringTy body)) readDefaultListTailCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy
  parserTy = readSCoreType aTy
  listParserTy = readSCoreType listA
  inputName = builtinLocalTermName "$read_list_tail_input" (-2598)
  parserName = builtinLocalTermName "$read_list_tail_parser" (-2599)
  closeUnitName = builtinLocalTermName "$read_list_tail_close_unit" (-2600)
  afterCloseName = builtinLocalTermName "$read_list_tail_after_close" (-2601)
  commaUnitName = builtinLocalTermName "$read_list_tail_comma_unit" (-2602)
  afterCommaName = builtinLocalTermName "$read_list_tail_after_comma" (-2603)
  xName = builtinLocalTermName "$read_list_tail_x" (-2604)
  afterXName = builtinLocalTermName "$read_list_tail_after_x" (-2605)
  xsName = builtinLocalTermName "$read_list_tail_xs" (-2606)
  restName = builtinLocalTermName "$read_list_tail_rest" (-2607)
  lam = coreLam
  emptyListParser =
    readBindCallCore
      unitTy
      listA
      (readExactCallCore "]" (CVar inputName stringTy))
      (lam closeUnitName unitTy (lam afterCloseName stringTy (readSingleResultCore listA (nilCore aTy) (CVar afterCloseName stringTy))))
  consParser =
    readBindCallCore
      unitTy
      listA
      (readExactCallCore "," (CVar inputName stringTy))
      ( lam commaUnitName unitTy $
          lam afterCommaName stringTy $
            readBindCallCore
              aTy
              listA
              (applyCore (CVar parserName parserTy) (CVar afterCommaName stringTy) (readResultsCoreType aTy))
              ( lam xName aTy $
                  lam afterXName stringTy $
                    readBindCallCore
                      listA
                      listA
                      (applyCore (applyCore (CTypeApp (CVar readDefaultListTailName readDefaultListTailCoreType) [aTy] (CTyFun parserTy listParserTy)) (CVar parserName parserTy) listParserTy) (CVar afterXName stringTy) (readResultsCoreType listA))
                      (lam xsName listA (lam restName stringTy (readSingleResultCore listA (consCore aTy (CVar xName aTy) (CVar xsName listA)) (CVar restName stringTy))))
              )
      )
  body =
    readAppendCallCore (readResultCoreType listA) emptyListParser consParser

readParenCorePair :: (CoreBinder, CoreExpr)
readParenCorePair =
  (CoreBinder readParenName readParenCoreType, CTypeLam [a] (lam mandatoryName boolTy (lam parserName parserTy (lam inputName stringTy body))) readParenCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  parserTy = readSCoreType aTy
  mandatoryName = builtinLocalTermName "$read_paren_mandatory" (-2608)
  parserName = builtinLocalTermName "$read_paren_parser" (-2609)
  inputName = builtinLocalTermName "$read_paren_input" (-2610)
  openUnitName = builtinLocalTermName "$read_paren_open_unit" (-2611)
  afterOpenName = builtinLocalTermName "$read_paren_after_open" (-2612)
  xName = builtinLocalTermName "$read_paren_x" (-2613)
  afterXName = builtinLocalTermName "$read_paren_after_x" (-2614)
  closeUnitName = builtinLocalTermName "$read_paren_close_unit" (-2615)
  restName = builtinLocalTermName "$read_paren_rest" (-2616)
  lam = coreLam
  parenthesized =
    readBindCallCore
      unitTy
      aTy
      (readExactCallCore "(" (CVar inputName stringTy))
      ( lam openUnitName unitTy $
          lam afterOpenName stringTy $
            readBindCallCore
              aTy
              aTy
              (applyCore (CVar parserName parserTy) (CVar afterOpenName stringTy) (readResultsCoreType aTy))
              ( lam xName aTy $
                  lam afterXName stringTy $
                    readBindCallCore
                      unitTy
                      aTy
                      (readExactCallCore ")" (CVar afterXName stringTy))
                      (lam closeUnitName unitTy (lam restName stringTy (readSingleResultCore aTy (CVar xName aTy) (CVar restName stringTy))))
              )
      )
  direct =
    applyCore (CVar parserName parserTy) (CVar inputName stringTy) (readResultsCoreType aTy)
  body =
    boolCaseCore
      "$read_paren_case"
      (-2617)
      (CVar mandatoryName boolTy)
      (readResultsCoreType aTy)
      parenthesized
      (readAppendCallCore (readResultCoreType aTy) direct parenthesized)

readIntCorePair :: (CoreBinder, CoreExpr)
readIntCorePair =
  (CoreBinder readIntName readIntCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_int_input" (-2618)
  cName = builtinLocalTermName "$read_int_c" (-2619)
  csName = builtinLocalTermName "$read_int_cs" (-2620)
  caseName = builtinLocalTermName "$read_int_case" (-2621)
  lam = coreLam
  stripped = applyCore (CVar readDropSpacesName (CTyFun stringTy stringTy)) (CVar inputName stringTy) stringTy
  start sign rest =
    applyCore
      (applyCore (CVar readIntStartName readIntStartCoreType) (CLit (LInt sign) intTy) readIntCoreType)
      rest
      (readResultsCoreType intTy)
  consBranch =
    CCase
      (CVar cName charTy)
      (CoreBinder (builtinLocalTermName "$read_int_char_case" (-2622)) charTy)
      [ CoreAlt (LiteralAlt (LChar '-')) [] (start (-1) (CVar csName stringTy))
      , CoreAlt DefaultAlt [] (start 1 stripped)
      ]
      (readResultsCoreType intTy)
  body =
    listCaseCore
      stripped
      caseName
      charTy
      (readResultsCoreType intTy)
      (nilCore (readResultCoreType intTy))
      cName
      csName
      consBranch

readIntStartCorePair :: (CoreBinder, CoreExpr)
readIntStartCorePair =
  (CoreBinder readIntStartName readIntStartCoreType, lam signName intTy (lam inputName stringTy body))
 where
  signName = builtinLocalTermName "$read_int_start_sign" (-2623)
  inputName = builtinLocalTermName "$read_int_start_input" (-2624)
  cName = builtinLocalTermName "$read_int_start_c" (-2625)
  csName = builtinLocalTermName "$read_int_start_cs" (-2626)
  caseName = builtinLocalTermName "$read_int_start_case" (-2627)
  lam = coreLam
  digit = readDigitValueCore (CVar cName charTy)
  digits =
    applyCore
      ( applyCore
          (applyCore (CVar readIntDigitsName readIntDigitsCoreType) (CVar signName intTy) (CTyFun intTy readIntCoreType))
          digit
          readIntCoreType
      )
      (CVar csName stringTy)
      (readResultsCoreType intTy)
  body =
    listCaseCore
      (CVar inputName stringTy)
      caseName
      charTy
      (readResultsCoreType intTy)
      (nilCore (readResultCoreType intTy))
      cName
      csName
      (boolCaseCore "$read_int_start_digit" (-2628) (readIsDigitCore (CVar cName charTy)) (readResultsCoreType intTy) digits (nilCore (readResultCoreType intTy)))

readIntDigitsCorePair :: (CoreBinder, CoreExpr)
readIntDigitsCorePair =
  (CoreBinder readIntDigitsName readIntDigitsCoreType, lam signName intTy (lam accName intTy (lam inputName stringTy body)))
 where
  signName = builtinLocalTermName "$read_int_digits_sign" (-2629)
  accName = builtinLocalTermName "$read_int_digits_acc" (-2630)
  inputName = builtinLocalTermName "$read_int_digits_input" (-2631)
  cName = builtinLocalTermName "$read_int_digits_c" (-2632)
  csName = builtinLocalTermName "$read_int_digits_cs" (-2633)
  caseName = builtinLocalTermName "$read_int_digits_case" (-2634)
  lam = coreLam
  signed = intMul (CVar signName intTy) (CVar accName intTy)
  done rest = readSingleResultCore intTy signed rest
  advanced = intAdd (intMul (CVar accName intTy) (CLit (LInt 10) intTy)) (readDigitValueCore (CVar cName charTy))
  recursive =
    applyCore
      ( applyCore
          (applyCore (CVar readIntDigitsName readIntDigitsCoreType) (CVar signName intTy) (CTyFun intTy readIntCoreType))
          advanced
          readIntCoreType
      )
      (CVar csName stringTy)
      (readResultsCoreType intTy)
  originalRest = consCharExprCore (CVar cName charTy) (CVar csName stringTy)
  body =
    listCaseCore
      (CVar inputName stringTy)
      caseName
      charTy
      (readResultsCoreType intTy)
      (done emptyStringCore)
      cName
      csName
      (boolCaseCore "$read_int_digits_digit" (-2635) (readIsDigitCore (CVar cName charTy)) (readResultsCoreType intTy) recursive (done originalRest))

readBoolCorePair :: (CoreBinder, CoreExpr)
readBoolCorePair =
  (CoreBinder readBoolName readBoolCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_bool_input" (-2636)
  lam = coreLam
  body =
    readAppendCallCore
      (readResultCoreType boolTy)
      (readConstantParserCore boolTy "True" (CCon trueDataConName boolTy) (CVar inputName stringTy))
      (readConstantParserCore boolTy "False" (CCon falseDataConName boolTy) (CVar inputName stringTy))

readEscapeCorePair :: (CoreBinder, CoreExpr)
readEscapeCorePair =
  (CoreBinder readEscapeName readEscapeCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_escape_input" (-2637)
  cName = builtinLocalTermName "$read_escape_c" (-2638)
  csName = builtinLocalTermName "$read_escape_cs" (-2639)
  caseName = builtinLocalTermName "$read_escape_case" (-2640)
  lam = coreLam
  input = CVar inputName stringTy
  simpleEscapes =
    listCaseCore
      input
      caseName
      charTy
      (readResultsCoreType charTy)
      (nilCore (readResultCoreType charTy))
      cName
      csName
      ( CCase
          (CVar cName charTy)
          (CoreBinder (builtinLocalTermName "$read_escape_char_case" (-2641)) charTy)
          ( [CoreAlt (LiteralAlt (LChar source)) [] (readSingleResultCore charTy (CLit (LChar value) charTy) (CVar csName stringTy)) | (source, value) <- readSimpleEscapes]
              <> [CoreAlt DefaultAlt [] (nilCore (readResultCoreType charTy))]
          )
          (readResultsCoreType charTy)
      )
  body =
    foldr
      (readAppendCallCore (readResultCoreType charTy))
      simpleEscapes
      [ readConstantParserCore charTy token (CLit (LChar value) charTy) input
      | (value, token) <- readNamedEscapes
      ]

readCharCorePair :: (CoreBinder, CoreExpr)
readCharCorePair =
  (CoreBinder readCharName readCharCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_char_input" (-2642)
  openUnitName = builtinLocalTermName "$read_char_open_unit" (-2643)
  afterOpenName = builtinLocalTermName "$read_char_after_open" (-2644)
  lam = coreLam
  body =
    readBindCallCore
      unitTy
      charTy
      (readExactCallCore "'" (CVar inputName stringTy))
      (lam openUnitName unitTy (lam afterOpenName stringTy (applyCore (CVar readCharBodyName readCharBodyCoreType) (CVar afterOpenName stringTy) (readResultsCoreType charTy))))

readCharBodyCorePair :: (CoreBinder, CoreExpr)
readCharBodyCorePair =
  (CoreBinder readCharBodyName readCharBodyCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_char_body_input" (-2645)
  cName = builtinLocalTermName "$read_char_body_c" (-2646)
  csName = builtinLocalTermName "$read_char_body_cs" (-2647)
  escapedName = builtinLocalTermName "$read_char_body_escaped" (-2648)
  afterEscapeName = builtinLocalTermName "$read_char_body_after_escape" (-2649)
  closeUnitName = builtinLocalTermName "$read_char_body_close_unit" (-2650)
  restName = builtinLocalTermName "$read_char_body_rest" (-2651)
  caseName = builtinLocalTermName "$read_char_body_case" (-2652)
  charCaseName = builtinLocalTermName "$read_char_body_char_case" (-2653)
  lam = coreLam
  closeWith value afterValue =
    readBindCallCore
      unitTy
      charTy
      (readExactRawCallCore "'" afterValue)
      (lam closeUnitName unitTy (lam restName stringTy (readSingleResultCore charTy value (CVar restName stringTy))))
  escaped =
    readBindCallCore
      charTy
      charTy
      (applyCore (CVar readEscapeName readEscapeCoreType) (CVar csName stringTy) (readResultsCoreType charTy))
      (lam escapedName charTy (lam afterEscapeName stringTy (closeWith (CVar escapedName charTy) (CVar afterEscapeName stringTy))))
  regular =
    closeWith (CVar cName charTy) (CVar csName stringTy)
  charCase =
    CCase
      (CVar cName charTy)
      (CoreBinder charCaseName charTy)
      [ CoreAlt (LiteralAlt (LChar '\\')) [] escaped
      , CoreAlt (LiteralAlt (LChar '\'')) [] (nilCore (readResultCoreType charTy))
      , CoreAlt DefaultAlt [] regular
      ]
      (readResultsCoreType charTy)
  body =
    listCaseCore
      (CVar inputName stringTy)
      caseName
      charTy
      (readResultsCoreType charTy)
      (nilCore (readResultCoreType charTy))
      cName
      csName
      charCase

readStringCorePair :: (CoreBinder, CoreExpr)
readStringCorePair =
  (CoreBinder readStringName readStringCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_string_input" (-2654)
  openUnitName = builtinLocalTermName "$read_string_open_unit" (-2655)
  afterOpenName = builtinLocalTermName "$read_string_after_open" (-2656)
  lam = coreLam
  body =
    readBindCallCore
      unitTy
      stringTy
      (readExactCallCore "\"" (CVar inputName stringTy))
      (lam openUnitName unitTy (lam afterOpenName stringTy (applyCore (CVar readStringCharsName readStringCharsCoreType) (CVar afterOpenName stringTy) (readResultsCoreType stringTy))))

readStringCharsCorePair :: (CoreBinder, CoreExpr)
readStringCharsCorePair =
  (CoreBinder readStringCharsName readStringCharsCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_string_chars_input" (-2657)
  cName = builtinLocalTermName "$read_string_chars_c" (-2658)
  csName = builtinLocalTermName "$read_string_chars_cs" (-2659)
  escapedName = builtinLocalTermName "$read_string_chars_escaped" (-2660)
  afterEscapeName = builtinLocalTermName "$read_string_chars_after_escape" (-2661)
  ampUnitName = builtinLocalTermName "$read_string_chars_amp_unit" (-2662)
  afterAmpName = builtinLocalTermName "$read_string_chars_after_amp" (-2663)
  restStringName = builtinLocalTermName "$read_string_chars_rest_string" (-2664)
  restName = builtinLocalTermName "$read_string_chars_rest" (-2665)
  caseName = builtinLocalTermName "$read_string_chars_case" (-2666)
  charCaseName = builtinLocalTermName "$read_string_chars_char_case" (-2667)
  lam = coreLam
  finishString rest =
    readSingleResultCore stringTy emptyStringCore rest
  continueWithChar charExpr afterChar =
    readBindCallCore
      stringTy
      stringTy
      (applyCore (CVar readStringCharsName readStringCharsCoreType) afterChar (readResultsCoreType stringTy))
      (lam restStringName stringTy (lam restName stringTy (readSingleResultCore stringTy (consCharExprCore charExpr (CVar restStringName stringTy)) (CVar restName stringTy))))
  emptyEscape =
    readBindCallCore
      unitTy
      stringTy
      (readExactRawCallCore "&" (CVar csName stringTy))
      (lam ampUnitName unitTy (lam afterAmpName stringTy (applyCore (CVar readStringCharsName readStringCharsCoreType) (CVar afterAmpName stringTy) (readResultsCoreType stringTy))))
  escaped =
    readBindCallCore
      charTy
      stringTy
      (applyCore (CVar readEscapeName readEscapeCoreType) (CVar csName stringTy) (readResultsCoreType charTy))
      (lam escapedName charTy (lam afterEscapeName stringTy (continueWithChar (CVar escapedName charTy) (CVar afterEscapeName stringTy))))
  backslashParser =
    readAppendCallCore (readResultCoreType stringTy) emptyEscape escaped
  charCase =
    CCase
      (CVar cName charTy)
      (CoreBinder charCaseName charTy)
      [ CoreAlt (LiteralAlt (LChar '"')) [] (finishString (CVar csName stringTy))
      , CoreAlt (LiteralAlt (LChar '\\')) [] backslashParser
      , CoreAlt DefaultAlt [] regular
      ]
      (readResultsCoreType stringTy)
  regular =
    continueWithChar (CVar cName charTy) (CVar csName stringTy)
  body =
    listCaseCore
      (CVar inputName stringTy)
      caseName
      charTy
      (readResultsCoreType stringTy)
      (nilCore (readResultCoreType stringTy))
      cName
      csName
      charCase

readLexCorePair :: (CoreBinder, CoreExpr)
readLexCorePair =
  (CoreBinder readLexName readLexCoreType, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName "$read_lex_input" (-2668)
  cName = builtinLocalTermName "$read_lex_c" (-2669)
  csName = builtinLocalTermName "$read_lex_cs" (-2670)
  caseName = builtinLocalTermName "$read_lex_case" (-2671)
  lam = coreLam
  stripped = applyCore (CVar readDropSpacesName (CTyFun stringTy stringTy)) (CVar inputName stringTy) stringTy
  charExpr = CVar cName charTy
  restExpr = CVar csName stringTy
  oneCharToken =
    readSingleResultCore stringTy (consCharExprCore charExpr emptyStringCore) restExpr
  tailCall tailName tailTy =
    readBindCallCore
      stringTy
      stringTy
      (applyCore (CVar tailName tailTy) restExpr (readResultsCoreType stringTy))
      ( coreLam
          (builtinLocalTermName "$read_lex_tail_token" (-2672))
          stringTy
          ( coreLam
              (builtinLocalTermName "$read_lex_tail_rest" (-2673))
              stringTy
              ( readSingleResultCore
                  stringTy
                  (consCharExprCore charExpr (CVar (builtinLocalTermName "$read_lex_tail_token" (-2672)) stringTy))
                  (CVar (builtinLocalTermName "$read_lex_tail_rest" (-2673)) stringTy)
              )
          )
      )
  identToken = tailCall readLexIdentTailName readLexIdentTailCoreType
  digitToken = tailCall readLexDigitTailName readLexDigitTailCoreType
  symbolToken = tailCall readLexSymbolTailName readLexSymbolTailCoreType
  tokenForChar =
    boolCaseCore
      "$read_lex_is_ident"
      (-2674)
      (readIsIdentStartCore charExpr)
      (readResultsCoreType stringTy)
      identToken
      ( boolCaseCore
          "$read_lex_is_digit"
          (-2675)
          (readIsDigitCore charExpr)
          (readResultsCoreType stringTy)
          digitToken
          ( boolCaseCore
              "$read_lex_is_single"
              (-2676)
              (readIsSingleCore charExpr)
              (readResultsCoreType stringTy)
              oneCharToken
              ( boolCaseCore
                  "$read_lex_is_symbol"
                  (-2677)
                  (readIsSymbolCore charExpr)
                  (readResultsCoreType stringTy)
                  symbolToken
                  (nilCore (readResultCoreType stringTy))
              )
          )
      )
  body =
    listCaseCore
      stripped
      caseName
      charTy
      (readResultsCoreType stringTy)
      (readSingleResultCore stringTy emptyStringCore emptyStringCore)
      cName
      csName
      tokenForChar

readLexTailCorePair :: RName -> (CoreExpr -> CoreExpr) -> CoreType -> (CoreBinder, CoreExpr)
readLexTailCorePair functionName predicate functionTy =
  (CoreBinder functionName functionTy, lam inputName stringTy body)
 where
  inputName = builtinLocalTermName ("$" <> nameOcc functionName <> "_input") (nameUnique functionName * 10 - 1)
  cName = builtinLocalTermName ("$" <> nameOcc functionName <> "_c") (nameUnique functionName * 10 - 2)
  csName = builtinLocalTermName ("$" <> nameOcc functionName <> "_cs") (nameUnique functionName * 10 - 3)
  tokenName = builtinLocalTermName ("$" <> nameOcc functionName <> "_token") (nameUnique functionName * 10 - 4)
  restName = builtinLocalTermName ("$" <> nameOcc functionName <> "_rest") (nameUnique functionName * 10 - 5)
  caseName = builtinLocalTermName ("$" <> nameOcc functionName <> "_case") (nameUnique functionName * 10 - 6)
  lam = coreLam
  charExpr = CVar cName charTy
  restExpr = CVar csName stringTy
  recursive =
    readBindCallCore
      stringTy
      stringTy
      (applyCore (CVar functionName functionTy) restExpr (readResultsCoreType stringTy))
      (lam tokenName stringTy (lam restName stringTy (readSingleResultCore stringTy (consCharExprCore charExpr (CVar tokenName stringTy)) (CVar restName stringTy))))
  body =
    listCaseCore
      (CVar inputName stringTy)
      caseName
      charTy
      (readResultsCoreType stringTy)
      (readSingleResultCore stringTy emptyStringCore emptyStringCore)
      cName
      csName
      (boolCaseCore ("$" <> nameOcc functionName <> "_predicate") (nameUnique functionName * 10 - 7) (predicate charExpr) (readResultsCoreType stringTy) recursive (readSingleResultCore stringTy emptyStringCore (CVar inputName stringTy)))

readConstantParserCore :: CoreType -> Text -> CoreExpr -> CoreExpr -> CoreExpr
readConstantParserCore valueTy token value input =
  readBindCallCore
    unitTy
    valueTy
    (readExactCallCore token input)
    ( coreLam
        (builtinLocalTermName "$read_constant_unit" (-2678 - Text.length token))
        unitTy
        ( coreLam
            (builtinLocalTermName "$read_constant_rest" (-2688 - Text.length token))
            stringTy
            (readConstantResultCore valueTy token value (CVar (builtinLocalTermName "$read_constant_rest" (-2688 - Text.length token)) stringTy))
        )
    )

readConstantResultCore :: CoreType -> Text -> CoreExpr -> CoreExpr -> CoreExpr
readConstantResultCore valueTy token value rest
  | readTokenNeedsBoundary token =
      listCaseCore
        rest
        (builtinLocalTermName "$read_constant_boundary_case" (-2870 - Text.length token))
        charTy
        resultTy
        success
        (builtinLocalTermName "$read_constant_boundary_c" (-2880 - Text.length token))
        (builtinLocalTermName "$read_constant_boundary_cs" (-2890 - Text.length token))
        ( boolCaseCore
            "$read_constant_boundary_ident"
            (-2900 - Text.length token)
            (readIsIdentCharCore (CVar (builtinLocalTermName "$read_constant_boundary_c" (-2880 - Text.length token)) charTy))
            resultTy
            (nilCore (readResultCoreType valueTy))
            success
        )
  | otherwise = success
 where
  resultTy = readResultsCoreType valueTy
  success = readSingleResultCore valueTy value rest

readTokenNeedsBoundary :: Text -> Bool
readTokenNeedsBoundary token =
  case Text.unsnoc token of
    Just (_, char) -> readTokenBoundaryChar char
    Nothing -> False

readTokenBoundaryChar :: Char -> Bool
readTokenBoundaryChar char =
  ('A' <= char && char <= 'Z')
    || ('a' <= char && char <= 'z')
    || ('0' <= char && char <= '9')
    || char == '_'
    || char == '\''

readExactCallCore :: Text -> CoreExpr -> CoreExpr
readExactCallCore token input =
  applyCore
    (applyCore (CVar readExactName readExactCoreType) (stringLiteralCore token) (CTyFun stringTy (readResultsCoreType unitTy)))
    input
    (readResultsCoreType unitTy)

readExactRawCallCore :: Text -> CoreExpr -> CoreExpr
readExactRawCallCore token input =
  applyCore
    (applyCore (CVar readExactRawName readExactRawCoreType) (stringLiteralCore token) (CTyFun stringTy (readResultsCoreType unitTy)))
    input
    (readResultsCoreType unitTy)

readAppendCallCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr
readAppendCallCore elementTy lhs rhs =
  applyCore
    (applyCore (CTypeApp (CVar readAppendName readAppendCoreType) [elementTy] (CTyFun listTy (CTyFun listTy listTy))) lhs (CTyFun listTy listTy))
    rhs
    listTy
 where
  listTy = CTyList elementTy

readBindCallCore :: CoreType -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr
readBindCallCore inputTy outputTy results continuation =
  applyCore
    ( applyCore
        (CTypeApp (CVar readBindName readBindCoreType) [inputTy, outputTy] (CTyFun resultsTy (CTyFun continuationTy outputResultsTy)))
        results
        (CTyFun continuationTy outputResultsTy)
    )
    continuation
    outputResultsTy
 where
  resultsTy = readResultsCoreType inputTy
  outputResultsTy = readResultsCoreType outputTy
  continuationTy = CTyFun inputTy (CTyFun stringTy outputResultsTy)

readSingleResultCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr
readSingleResultCore valueTy value rest =
  consCore resultTy pair (nilCore resultTy)
 where
  resultTy = readResultCoreType valueTy
  pair = constructorApp (tupleDataConName 2) [valueTy, stringTy] [value, rest] resultTy

readFailureCore :: CoreType -> CoreExpr
readFailureCore resultTy =
  CCase
    (CCon falseDataConName boolTy)
    (CoreBinder (builtinLocalTermName "$read_failure" (-2698)) boolTy)
    []
    resultTy

coreLam :: RName -> CoreType -> CoreExpr -> CoreExpr
coreLam binderName ty body =
  CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))

readDigitValueCore :: CoreExpr -> CoreExpr
readDigitValueCore charExpr =
  intSub (charToIntCore charExpr) (CLit (LInt (toInteger (fromEnum '0'))) intTy)

readIsDigitCore :: CoreExpr -> CoreExpr
readIsDigitCore =
  readCharBetweenCore '0' '9' "$read_is_digit" (-2699)

readIsIdentStartCore :: CoreExpr -> CoreExpr
readIsIdentStartCore charExpr =
  boolCaseCore
    "$read_is_ident_lower"
    (-2700)
    (readCharBetweenCore 'a' 'z' "$read_ident_lower" (-2701) charExpr)
    boolTy
    (CCon trueDataConName boolTy)
    ( boolCaseCore
        "$read_is_ident_upper"
        (-2702)
        (readCharBetweenCore 'A' 'Z' "$read_ident_upper" (-2703) charExpr)
        boolTy
        (CCon trueDataConName boolTy)
        (CPrimOp PrimEq [charExpr, CLit (LChar '_') charTy] boolTy)
    )

readIsIdentCharCore :: CoreExpr -> CoreExpr
readIsIdentCharCore charExpr =
  boolCaseCore
    "$read_is_ident_start"
    (-2704)
    (readIsIdentStartCore charExpr)
    boolTy
    (CCon trueDataConName boolTy)
    ( boolCaseCore
        "$read_is_ident_digit"
        (-2705)
        (readIsDigitCore charExpr)
        boolTy
        (CCon trueDataConName boolTy)
        (CPrimOp PrimEq [charExpr, CLit (LChar '\'') charTy] boolTy)
    )

readIsSingleCore :: CoreExpr -> CoreExpr
readIsSingleCore charExpr =
  readCharMemberCore ",;()[]{}_`" charExpr

readIsSymbolCore :: CoreExpr -> CoreExpr
readIsSymbolCore charExpr =
  readCharMemberCore "!#$%&*+./<=>?@\\^|-~:" charExpr

readIsSpaceCore :: CoreExpr -> CoreExpr
readIsSpaceCore charExpr =
  readCharMemberCore " \n\t\r\f\v" charExpr

readCharMemberCore :: Text -> CoreExpr -> CoreExpr
readCharMemberCore chars charExpr =
  CCase
    charExpr
    (CoreBinder (builtinLocalTermName "$read_char_member" (-2706 - Text.length chars)) charTy)
    ([CoreAlt (LiteralAlt (LChar char)) [] (CCon trueDataConName boolTy) | char <- Text.unpack chars] <> [CoreAlt DefaultAlt [] (CCon falseDataConName boolTy)])
    boolTy

readCharBetweenCore :: Char -> Char -> Text -> Int -> CoreExpr -> CoreExpr
readCharBetweenCore low high occurrence unique charExpr =
  boolAndCore
    occurrence
    unique
    (boolNotCore (occurrence <> "_below") (unique - 1) (intLt charInt (CLit (LInt (toInteger (fromEnum low))) intTy)))
    (boolNotCore (occurrence <> "_above") (unique - 2) (intLt (CLit (LInt (toInteger (fromEnum high))) intTy) charInt))
 where
  charInt = charToIntCore charExpr

readSimpleEscapes :: [(Char, Char)]
readSimpleEscapes =
  [ ('a', '\a')
  , ('b', '\b')
  , ('t', '\t')
  , ('n', '\n')
  , ('v', '\v')
  , ('f', '\f')
  , ('r', '\r')
  , ('\\', '\\')
  , ('"', '"')
  , ('\'', '\'')
  ]

readNamedEscapes :: [(Char, Text)]
readNamedEscapes =
  [(char, token) | (char, token) <- showEscapedControlChars, Text.length token > 1]

reverseGoCorePair :: (CoreBinder, CoreExpr)
reverseGoCorePair =
  (CoreBinder reverseGoName reverseGoTy, CTypeLam [a] (lam acc listA (lam xs listA body)) reverseGoTy)
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy
  acc = preludeTermName "$reverse_acc" (-3051)
  xs = preludeTermName "$reverse_go_xs" (-3052)
  y = preludeTermName "$reverse_y" (-3053)
  ys = preludeTermName "$reverse_ys" (-3054)
  caseName = preludeTermName "$reverse_case" (-3055)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  var variable ty = CVar variable ty
  apply fn arg resultTy = CApp fn arg resultTy
  specialize functionName functionTy typeArguments resultTy =
    CTypeApp (CVar functionName functionTy) typeArguments resultTy
  cons elementTy headExpr tailExpr =
    constructorApp listConsDataConName [elementTy] [headExpr, tailExpr] (CTyList elementTy)
  body =
    CCase
      (var xs listA)
      (CoreBinder caseName listA)
      [ CoreAlt (ConstructorAlt listNilDataConName) [] (var acc listA)
      , CoreAlt
          (ConstructorAlt listConsDataConName)
          [CoreBinder y aTy, CoreBinder ys listA]
          ( apply
              ( apply
                  (specialize reverseGoName reverseGoTy [aTy] (CTyFun listA (CTyFun listA listA)))
                  (cons aTy (var y aTy) (var acc listA))
                  (CTyFun listA listA)
              )
              (var ys listA)
              listA
          )
      ]
      listA

reverseGoName :: RName
reverseGoName =
  preludeTermName "$reverse_go" (-3056)

reverseGoTy :: CoreType
reverseGoTy =
  CTyForall [a] (CTyFun listA (CTyFun listA listA))
 where
  a = preludeTypeVariable "a" (-1201)
  aTy = CTyVar a
  listA = CTyList aTy

preludeTermName :: Text -> Int -> RName
preludeTermName occurrence unique =
  RName TermNamespace occurrence unique True

standardLibraryTermName :: Text -> RName
standardLibraryTermName =
  standardLibraryExternalName TermNamespace

arithmeticSequencePreludeNames :: [RName]
arithmeticSequencePreludeNames =
  [ enumFromIntName
  , enumFromThenIntName
  , enumFromToIntName
  , enumFromThenToIntName
  , enumFromCharName
  , enumFromThenCharName
  , enumFromToCharName
  , enumFromThenToCharName
  , enumFromCharGoName
  , enumFromThenCharGoName
  , enumFromThenToCharGoName
  ]

enumFromIntName, enumFromThenIntName, enumFromToIntName, enumFromThenToIntName :: RName
enumFromIntName = preludeTermName "$enumFromInt" (-7001)
enumFromThenIntName = preludeTermName "$enumFromThenInt" (-7002)
enumFromToIntName = preludeTermName "$enumFromToInt" (-7003)
enumFromThenToIntName = preludeTermName "$enumFromThenToInt" (-7004)

enumFromCharName, enumFromThenCharName, enumFromToCharName, enumFromThenToCharName :: RName
enumFromCharName = preludeTermName "$enumFromChar" (-7011)
enumFromThenCharName = preludeTermName "$enumFromThenChar" (-7012)
enumFromToCharName = preludeTermName "$enumFromToChar" (-7013)
enumFromThenToCharName = preludeTermName "$enumFromThenToChar" (-7014)

enumFromCharGoName, enumFromThenCharGoName, enumFromThenToCharGoName :: RName
enumFromCharGoName = preludeTermName "$enumFromCharGo" (-7021)
enumFromThenCharGoName = preludeTermName "$enumFromThenCharGo" (-7022)
enumFromThenToCharGoName = preludeTermName "$enumFromThenToCharGo" (-7023)

arithmeticSequenceCorePair :: RName -> Maybe (CoreBinder, CoreExpr)
arithmeticSequenceCorePair name
  | name == enumFromIntName = Just (CoreBinder enumFromIntName enumFromIntCoreType, enumFromIntCore)
  | name == enumFromThenIntName = Just (CoreBinder enumFromThenIntName enumFromThenIntCoreType, enumFromThenIntCore)
  | name == enumFromToIntName = Just (CoreBinder enumFromToIntName enumFromToIntCoreType, enumFromToIntCore)
  | name == enumFromThenToIntName = Just (CoreBinder enumFromThenToIntName enumFromThenToIntCoreType, enumFromThenToIntCore)
  | name == enumFromCharName = Just (CoreBinder enumFromCharName enumFromCharCoreType, enumFromCharCore)
  | name == enumFromThenCharName = Just (CoreBinder enumFromThenCharName enumFromThenCharCoreType, enumFromThenCharCore)
  | name == enumFromToCharName = Just (CoreBinder enumFromToCharName enumFromToCharCoreType, enumFromToCharCore)
  | name == enumFromThenToCharName = Just (CoreBinder enumFromThenToCharName enumFromThenToCharCoreType, enumFromThenToCharCore)
  | name == enumFromCharGoName = Just (CoreBinder enumFromCharGoName enumFromCharGoCoreType, enumFromCharGoCore)
  | name == enumFromThenCharGoName = Just (CoreBinder enumFromThenCharGoName enumFromThenCharGoCoreType, enumFromThenCharGoCore)
  | name == enumFromThenToCharGoName = Just (CoreBinder enumFromThenToCharGoName enumFromThenToCharGoCoreType, enumFromThenToCharGoCore)
  | otherwise = Nothing

enumFromIntCoreType, enumFromThenIntCoreType, enumFromToIntCoreType, enumFromThenToIntCoreType :: CoreType
enumFromIntCoreType = CTyFun intTy intListCoreType
enumFromThenIntCoreType = CTyFun intTy (CTyFun intTy intListCoreType)
enumFromToIntCoreType = CTyFun intTy (CTyFun intTy intListCoreType)
enumFromThenToIntCoreType = CTyFun intTy (CTyFun intTy (CTyFun intTy intListCoreType))

enumFromCharCoreType, enumFromThenCharCoreType, enumFromToCharCoreType, enumFromThenToCharCoreType :: CoreType
enumFromCharCoreType = CTyFun charTy charListCoreType
enumFromThenCharCoreType = CTyFun charTy (CTyFun charTy charListCoreType)
enumFromToCharCoreType = CTyFun charTy (CTyFun charTy charListCoreType)
enumFromThenToCharCoreType = CTyFun charTy (CTyFun charTy (CTyFun charTy charListCoreType))

enumFromCharGoCoreType, enumFromThenCharGoCoreType, enumFromThenToCharGoCoreType :: CoreType
enumFromCharGoCoreType = CTyFun intTy charListCoreType
enumFromThenCharGoCoreType = CTyFun intTy (CTyFun intTy charListCoreType)
enumFromThenToCharGoCoreType = CTyFun intTy (CTyFun intTy (CTyFun intTy charListCoreType))

intListCoreType, charListCoreType :: CoreType
intListCoreType = CTyList intTy
charListCoreType = CTyList charTy

enumFromIntCore :: CoreExpr
enumFromIntCore =
  enumLam currentName intTy $
    applyCore (applyCore (CVar enumFromThenIntName enumFromThenIntCoreType) current intTyToIntList) (intAdd current oneInt) intListCoreType
 where
  currentName = builtinLocalTermName "$enum_from_int_current" (-7101)
  current = CVar currentName intTy
  intTyToIntList = CTyFun intTy intListCoreType

enumFromThenIntCore :: CoreExpr
enumFromThenIntCore =
  enumLam currentName intTy (enumLam nextName intTy body)
 where
  currentName = builtinLocalTermName "$enum_from_then_int_current" (-7102)
  nextName = builtinLocalTermName "$enum_from_then_int_next" (-7103)
  current = CVar currentName intTy
  next = CVar nextName intTy
  step = intSub next current
  advanced = intAdd next step
  tailExpr =
    applyCore
      (applyCore (CVar enumFromThenIntName enumFromThenIntCoreType) next (CTyFun intTy intListCoreType))
      advanced
      intListCoreType
  body = consCore intTy current tailExpr

enumFromToIntCore :: CoreExpr
enumFromToIntCore =
  enumLam currentName intTy (enumLam endName intTy body)
 where
  currentName = builtinLocalTermName "$enum_from_to_int_current" (-7104)
  endName = builtinLocalTermName "$enum_from_to_int_end" (-7105)
  current = CVar currentName intTy
  end = CVar endName intTy
  next = intAdd current oneInt
  body =
    applyCore
      ( applyCore
          (applyCore (CVar enumFromThenToIntName enumFromThenToIntCoreType) current (CTyFun intTy (CTyFun intTy intListCoreType)))
          next
          (CTyFun intTy intListCoreType)
      )
      end
      intListCoreType

enumFromThenToIntCore :: CoreExpr
enumFromThenToIntCore =
  enumLam currentName intTy (enumLam nextName intTy (enumLam endName intTy body))
 where
  currentName = builtinLocalTermName "$enum_from_then_to_int_current" (-7106)
  nextName = builtinLocalTermName "$enum_from_then_to_int_next" (-7107)
  endName = builtinLocalTermName "$enum_from_then_to_int_end" (-7108)
  current = CVar currentName intTy
  next = CVar nextName intTy
  end = CVar endName intTy
  body = enumThenToIntList "$enum_int" (-7110) enumFromThenToIntName enumFromThenToIntCoreType current next end

enumFromCharCore :: CoreExpr
enumFromCharCore =
  enumLam currentName charTy $
    applyCore (CVar enumFromCharGoName enumFromCharGoCoreType) (charToIntCore current) charListCoreType
 where
  currentName = builtinLocalTermName "$enum_from_char_current" (-7121)
  current = CVar currentName charTy

enumFromThenCharCore :: CoreExpr
enumFromThenCharCore =
  enumLam currentName charTy (enumLam nextName charTy body)
 where
  currentName = builtinLocalTermName "$enum_from_then_char_current" (-7122)
  nextName = builtinLocalTermName "$enum_from_then_char_next" (-7123)
  current = CVar currentName charTy
  next = CVar nextName charTy
  currentInt = charToIntCore current
  nextInt = charToIntCore next
  step = intSub nextInt currentInt
  body =
    applyCore
      (applyCore (CVar enumFromThenCharGoName enumFromThenCharGoCoreType) currentInt (CTyFun intTy charListCoreType))
      step
      charListCoreType

enumFromToCharCore :: CoreExpr
enumFromToCharCore =
  enumLam currentName charTy (enumLam endName charTy body)
 where
  currentName = builtinLocalTermName "$enum_from_to_char_current" (-7124)
  endName = builtinLocalTermName "$enum_from_to_char_end" (-7125)
  current = CVar currentName charTy
  end = CVar endName charTy
  body =
    applyCore
      ( applyCore
          (applyCore (CVar enumFromThenToCharGoName enumFromThenToCharGoCoreType) (charToIntCore current) (CTyFun intTy (CTyFun intTy charListCoreType)))
          oneInt
          (CTyFun intTy charListCoreType)
      )
      (charToIntCore end)
      charListCoreType

enumFromThenToCharCore :: CoreExpr
enumFromThenToCharCore =
  enumLam currentName charTy (enumLam nextName charTy (enumLam endName charTy body))
 where
  currentName = builtinLocalTermName "$enum_from_then_to_char_current" (-7126)
  nextName = builtinLocalTermName "$enum_from_then_to_char_next" (-7127)
  endName = builtinLocalTermName "$enum_from_then_to_char_end" (-7128)
  current = CVar currentName charTy
  next = CVar nextName charTy
  end = CVar endName charTy
  currentInt = charToIntCore current
  nextInt = charToIntCore next
  step = intSub nextInt currentInt
  body =
    applyCore
      ( applyCore
          (applyCore (CVar enumFromThenToCharGoName enumFromThenToCharGoCoreType) currentInt (CTyFun intTy (CTyFun intTy charListCoreType)))
          step
          (CTyFun intTy charListCoreType)
      )
      (charToIntCore end)
      charListCoreType

enumFromCharGoCore :: CoreExpr
enumFromCharGoCore =
  enumLam currentName intTy body
 where
  currentName = builtinLocalTermName "$enum_from_char_go_current" (-7131)
  current = CVar currentName intTy
  tailExpr = applyCore (CVar enumFromCharGoName enumFromCharGoCoreType) (intAdd current oneInt) charListCoreType
  body = consCore charTy (intToCharCore current) tailExpr

enumFromThenCharGoCore :: CoreExpr
enumFromThenCharGoCore =
  enumLam currentName intTy (enumLam stepName intTy body)
 where
  currentName = builtinLocalTermName "$enum_from_then_char_go_current" (-7132)
  stepName = builtinLocalTermName "$enum_from_then_char_go_step" (-7133)
  current = CVar currentName intTy
  step = CVar stepName intTy
  advanced = intAdd current step
  tailExpr =
    applyCore
      (applyCore (CVar enumFromThenCharGoName enumFromThenCharGoCoreType) advanced (CTyFun intTy charListCoreType))
      step
      charListCoreType
  body = consCore charTy (intToCharCore current) tailExpr

enumFromThenToCharGoCore :: CoreExpr
enumFromThenToCharGoCore =
  enumLam currentName intTy (enumLam stepName intTy (enumLam endName intTy body))
 where
  currentName = builtinLocalTermName "$enum_from_then_to_char_go_current" (-7134)
  stepName = builtinLocalTermName "$enum_from_then_to_char_go_step" (-7135)
  endName = builtinLocalTermName "$enum_from_then_to_char_go_end" (-7136)
  current = CVar currentName intTy
  step = CVar stepName intTy
  end = CVar endName intTy
  body = enumStepToCharList "$enum_char" (-7140) enumFromThenToCharGoName enumFromThenToCharGoCoreType current step end

enumThenToIntList :: Text -> Int -> RName -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
enumThenToIntList occurrence unique functionName functionTy current next end =
  boolCaseCore
    (occurrence <> "_step_negative")
    unique
    (intLt step zeroInt)
    intListCoreType
    descending
    ascending
 where
  step = intSub next current
  advanced = intAdd next step
  tailExpr =
    applyCore
      ( applyCore
          (applyCore (CVar functionName functionTy) next (CTyFun intTy (CTyFun intTy intListCoreType)))
          advanced
          (CTyFun intTy intListCoreType)
      )
      end
      intListCoreType
  item = consCore intTy current tailExpr
  descending = boolCaseCore (occurrence <> "_descending_stop") (unique - 1) (intLt current end) intListCoreType (nilCore intTy) item
  ascending = boolCaseCore (occurrence <> "_ascending_stop") (unique - 2) (intLt end current) intListCoreType (nilCore intTy) item

enumStepToCharList :: Text -> Int -> RName -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
enumStepToCharList occurrence unique functionName functionTy current step end =
  boolCaseCore
    (occurrence <> "_step_negative")
    unique
    (intLt step zeroInt)
    charListCoreType
    descending
    ascending
 where
  advanced = intAdd current step
  tailExpr =
    applyCore
      ( applyCore
          (applyCore (CVar functionName functionTy) advanced (CTyFun intTy (CTyFun intTy charListCoreType)))
          step
          (CTyFun intTy charListCoreType)
      )
      end
      charListCoreType
  item = consCore charTy (intToCharCore current) tailExpr
  descending = boolCaseCore (occurrence <> "_descending_stop") (unique - 1) (intLt current end) charListCoreType (nilCore charTy) item
  ascending = boolCaseCore (occurrence <> "_ascending_stop") (unique - 2) (intLt end current) charListCoreType (nilCore charTy) item

enumLam :: RName -> CoreType -> CoreExpr -> CoreExpr
enumLam binderName ty body =
  CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))

applyCore :: CoreExpr -> CoreExpr -> CoreType -> CoreExpr
applyCore fn arg resultTy =
  CApp fn arg resultTy

intAdd, intSub, intMul, intQuot, intRem, intLt :: CoreExpr -> CoreExpr -> CoreExpr
intAdd lhs rhs =
  CPrimOp PrimAdd [lhs, rhs] intTy
intSub lhs rhs =
  CPrimOp PrimSub [lhs, rhs] intTy
intMul lhs rhs =
  CPrimOp PrimMul [lhs, rhs] intTy
intQuot lhs rhs =
  CPrimOp PrimDiv [lhs, rhs] intTy
intRem lhs rhs =
  CPrimOp PrimRem [lhs, rhs] intTy
intLt lhs rhs =
  CPrimOp PrimLt [lhs, rhs] boolTy

intAbsCore :: CoreExpr -> CoreExpr
intAbsCore value =
  boolCaseCore
    "$abs_int_core"
    (-11230)
    (intLt value zeroInt)
    intTy
    (CPrimOp PrimNegate [value] intTy)
    value

intSignumCore :: CoreExpr -> CoreExpr
intSignumCore value =
  boolCaseCore
    "$signum_int_core_neg"
    (-11231)
    (intLt value zeroInt)
    intTy
    (CLit (LInt (-1)) intTy)
    ( boolCaseCore
        "$signum_int_core_zero"
        (-11232)
        (CPrimOp PrimEq [value, zeroInt] boolTy)
        intTy
        zeroInt
        oneInt
    )

charToIntCore, intToCharCore :: CoreExpr -> CoreExpr
charToIntCore value =
  CPrimOp PrimCharToInt [value] intTy
intToCharCore value =
  CPrimOp PrimIntToChar [value] charTy

zeroInt, oneInt :: CoreExpr
zeroInt = CLit (LInt 0) intTy
oneInt = CLit (LInt 1) intTy

nilCore :: CoreType -> CoreExpr
nilCore elementTy =
  constructorApp listNilDataConName [elementTy] [] (CTyList elementTy)

consCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr
consCore elementTy headExpr tailExpr =
  constructorApp listConsDataConName [elementTy] [headExpr, tailExpr] (CTyList elementTy)

data CoreElabEnv = CoreElabEnv
  { coreElabSubst :: Subst
  , coreElabMetas :: Map.Map Int RName
  , coreElabClasses :: Map.Map RName ClassInfo
  , coreElabInstances :: [InstanceDictionaryRef]
  , coreElabDictionaries :: [(ClassConstraint, CoreExpr)]
  }

data InstanceDictionaryRef = InstanceDictionaryRef
  { instanceRefConstraint :: ClassConstraint
  , instanceRefVariables :: [RName]
  , instanceRefContext :: [ClassConstraint]
  , instanceRefName :: RName
  }
  deriving stock (Show, Eq, Ord)

data BuiltinInstanceDictionary = BuiltinInstanceDictionary
  { builtinInstanceClass :: RName
  , builtinInstanceType :: MonoType
  , builtinInstanceName :: RName
  , builtinInstanceMethods :: [CoreExpr]
  }
  deriving stock (Show, Eq, Ord)

bindingToCore :: CoreElabEnv -> TypedBinding -> Either TypecheckError CoreBind
bindingToCore env binding = do
  let scheme = typedBindingScheme binding
      subst = coreElabSubst env
      ambientMetas = coreElabMetas env
      initialMetas = Map.union (typedBindingGeneralizedMetas binding) ambientMetas
      allMetas =
        Map.unions
          [ initialMetas
          , ambiguousSchemeMetas initialMetas scheme
          , ambiguousExprMetas initialMetas (typedBindingRhs binding)
          ]
      envWithMetas = env {coreElabMetas = allMetas}
  binderTy <- schemeToCoreTypeWith subst allMetas scheme
  dictBinders <- dictionaryBindersFor subst allMetas (typedBindingName binding) scheme
  let localDictionaries =
        [ (constraint, CVar (coreBinderName binder) (coreBinderType binder))
        | (constraint, binder) <- dictBinders
        ]
      rhsEnv =
        envWithMetas
          { coreElabDictionaries = localDictionaries <> coreElabDictionaries envWithMetas
          }
  rhs <- exprToCore rhsEnv (typedBindingRhs binding)
  let rhsWithDictionaryLambdas =
        foldr
          (\(_, binder) body -> CLam binder body (CTyFun (coreBinderType binder) (exprType body)))
          rhs
          dictBinders
      rhsWithTypeLambdas =
        case schemeVars scheme of
          [] -> rhsWithDictionaryLambdas
          variables -> CTypeLam variables rhsWithDictionaryLambdas binderTy
  pure (CoreNonRec (CoreBinder (typedBindingName binding) binderTy) rhsWithTypeLambdas)

ambiguousExprMetas :: Map.Map Int RName -> TypedExpr -> Map.Map Int RName
ambiguousExprMetas knownMetas expression =
  Map.fromList
    [ (meta, ambiguousMetaName meta)
    | meta <- Set.toList (typedExprMetaVars expression)
    , meta `Map.notMember` knownMetas
    ]

ambiguousSchemeMetas :: Map.Map Int RName -> Scheme -> Map.Map Int RName
ambiguousSchemeMetas knownMetas scheme =
  Map.fromList
    [ (meta, ambiguousMetaName meta)
    | meta <- Set.toList (freeMetaVarsScheme scheme)
    , meta `Map.notMember` knownMetas
    ]

ambiguousMetaName :: Int -> RName
ambiguousMetaName meta =
  RName TypeVariableNamespace ("$amb" <> renderInt meta) (2000000 + meta) False

bindPairs :: CoreBind -> [(CoreBinder, CoreExpr)]
bindPairs = \case
  CoreNonRec binder rhs -> [(binder, rhs)]
  CoreRec pairs -> pairs

bindingGroupCoreBind :: [TypedBinding] -> [CoreBind] -> Maybe CoreBind
bindingGroupCoreBind typedBindings coreBinds =
  case (typedBindings, coreBinds) of
    ([], []) ->
      Nothing
    ([binding], [coreBind])
      | bindingIsSelfRecursive binding ->
          Just (CoreRec (bindPairs coreBind))
      | otherwise ->
          Just coreBind
    _ ->
      Just (CoreRec (concatMap bindPairs coreBinds))

bindingIsSelfRecursive :: TypedBinding -> Bool
bindingIsSelfRecursive binding =
  typedBindingName binding `Set.member` typedExprFreeTermNames (typedBindingRhs binding)

exprToCore :: CoreElabEnv -> TypedExpr -> Either TypecheckError CoreExpr
exprToCore env expression =
  case newtypeApplicationToCore env expression of
    Just converted -> converted
    Nothing -> exprToCoreDefault env expression

exprToCoreDefault :: CoreElabEnv -> TypedExpr -> Either TypecheckError CoreExpr
exprToCoreDefault env = \case
  TVar name scheme typeArguments ty -> do
    let subst = coreElabSubst env
        metas = coreElabMetas env
    varTy <- schemeToCoreTypeWith subst metas scheme
    resultTy <- monoToCoreType subst metas ty
    coreTypeArguments <- traverse (monoToCoreType subst metas) typeArguments
    dictionaryArguments <- traverse (resolveDictionary env) (instantiateSchemeConstraints scheme typeArguments)
    let varExpr = CVar name varTy
        dictResultTy = foldr CTyFun resultTy (map exprType dictionaryArguments)
        typedExpr =
          case schemeVars scheme of
            [] -> CVar name dictResultTy
            _ -> CTypeApp varExpr coreTypeArguments dictResultTy
    pure (foldl applyDictionary typedExpr dictionaryArguments)
  TLit literal ty ->
    CLit literal <$> monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
  TCon name scheme typeArguments ty -> do
    let subst = coreElabSubst env
        metas = coreElabMetas env
    constructorTy <- schemeToCoreTypeWith subst metas scheme
    resultTy <- monoToCoreType subst metas ty
    coreTypeArguments <- traverse (monoToCoreType subst metas) typeArguments
    let constructorExpr = CCon name constructorTy
    pure $
      case schemeVars scheme of
        [] -> CCon name resultTy
        _ -> CTypeApp constructorExpr coreTypeArguments resultTy
  TNewtypeCon _ _ _ ty binder -> do
    let subst = coreElabSubst env
        metas = coreElabMetas env
    coreBinder <- typedBinderToCore subst metas binder
    coreTy <- monoToCoreType subst metas ty
    case coreTy of
      CTyFun _ resultTy ->
        pure
          ( CLam
              coreBinder
              (CCoerce (CVar (coreBinderName coreBinder) (coreBinderType coreBinder)) resultTy)
              coreTy
          )
      _ ->
        Left (UnsupportedCore0 "newtype constructor elaborated to non-function Core type")
  TTuple fields ty -> do
    coreFields <- traverse (exprToCore env) fields
    resultTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
    fieldTypes <- case applySubst (coreElabSubst env) ty of
      TyTuple types -> traverse (monoToCoreType subst metas) types
      other -> Left (TypeMismatch (TyTuple []) other)
    pure (constructorApp (tupleDataConName (length fields)) fieldTypes coreFields resultTy)
   where
    subst = coreElabSubst env
    metas = coreElabMetas env
  TList elements ty -> do
    coreElements <- traverse (exprToCore env) elements
    elementTy <- case applySubst subst ty of
      TyList element -> monoToCoreType subst metas element
      other -> Left (TypeMismatch (TyList (TyMeta (-1))) other)
    pure (listCoreExpr elementTy coreElements)
   where
    subst = coreElabSubst env
    metas = coreElabMetas env
  TLam binder body ty -> do
    let subst = coreElabSubst env
        metas = coreElabMetas env
    coreBinder <- typedBinderToCore subst metas binder
    coreBody <- exprToCore env body
    coreTy <- monoToCoreType subst metas ty
    pure (CLam coreBinder coreBody coreTy)
  TApp fn arg ty -> do
    coreFn <- exprToCore env fn
    coreArg <- exprToCore env arg
    coreTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
    pure (CApp coreFn coreArg coreTy)
  TLet bindings body ty -> do
    coreBindings <- traverse (bindingToCore env) bindings
    coreBody <- exprToCore env body
    coreTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
    pure
      ( CLet
          (fromMaybe (CoreRec []) (bindingGroupCoreBind bindings coreBindings))
          coreBody
          coreTy
      )
  TCase scrutinee binder alternatives ty -> do
    let subst = coreElabSubst env
        metas = coreElabMetas env
    coreScrutinee <- exprToCore env scrutinee
    coreBinder <- typedBinderToCore subst metas binder
    coreAlternatives <- traverse (altToCore env) alternatives
    coreTy <- monoToCoreType subst metas ty
    pure (CCase coreScrutinee coreBinder coreAlternatives coreTy)
  TCoerce expression' ty -> do
    coreExpression <- exprToCore env expression'
    coreTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
    pure (CCoerce coreExpression coreTy)
  TPrim op arguments ty -> do
    coreArguments <- traverse (exprToCore env) arguments
    coreTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) ty
    pure (CPrimOp op coreArguments coreTy)
 where
  applyDictionary callee dictionary =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee dictionary remainingResult

newtypeApplicationToCore :: CoreElabEnv -> TypedExpr -> Maybe (Either TypecheckError CoreExpr)
newtypeApplicationToCore env expression =
  case collectTypedValueApps expression of
    (TNewtypeCon _ _ _ _ _, [argument]) ->
      Just $ do
        coreArgument <- exprToCore env argument
        coreTy <- monoToCoreType (coreElabSubst env) (coreElabMetas env) (typedExprType expression)
        pure (CCoerce coreArgument coreTy)
    _ ->
      Nothing

collectTypedValueApps :: TypedExpr -> (TypedExpr, [TypedExpr])
collectTypedValueApps =
  go []
 where
  go arguments = \case
    TApp fn argument _ ->
      go (argument : arguments) fn
    other ->
      (other, arguments)

dictionaryBindersFor :: Subst -> Map.Map Int RName -> RName -> Scheme -> Either TypecheckError [(ClassConstraint, CoreBinder)]
dictionaryBindersFor subst metas owner scheme =
  traverse binderFor (zip [0 ..] (schemeConstraints scheme))
 where
  binderFor (index, constraint) = do
    binderTy <- classConstraintCoreType subst metas constraint
    let binderName =
          RName
            TermNamespace
            ("$d" <> renderInt index <> "_" <> nameOcc owner)
            (5300000 + (nameUnique owner * 100) + index)
            False
    pure (constraint, CoreBinder binderName binderTy)

instantiateSchemeConstraints :: Scheme -> [MonoType] -> [ClassConstraint]
instantiateSchemeConstraints scheme typeArguments =
  let replacements = Map.fromList (zip (schemeVars scheme) typeArguments)
   in map (replaceConstraintTypeVars replacements) (schemeConstraints scheme)

replaceConstraintTypeVars :: Map.Map RName MonoType -> ClassConstraint -> ClassConstraint
replaceConstraintTypeVars replacements =
  mapClassConstraintArguments (replaceTypeVars replacements)

replaceSchemeTypeVars :: Map.Map RName MonoType -> Scheme -> Scheme
replaceSchemeTypeVars replacements (Scheme variables constraints body) =
  Scheme
    variables
    (map (replaceConstraintTypeVars scopedReplacements) constraints)
    (replaceTypeVars scopedReplacements body)
 where
  scopedReplacements =
    foldr Map.delete replacements variables

resolveDictionary :: CoreElabEnv -> ClassConstraint -> Either TypecheckError CoreExpr
resolveDictionary env wanted = do
  normalized <- normalizeConstraint (coreElabSubst env) (coreElabMetas env) wanted
  case List.find (constraintMatches normalized . fst) (coreElabDictionaries env) of
    Just (_, dictionary) -> pure dictionary
    Nothing ->
      case firstJust (map (matchInstanceDictionaryRef normalized) (coreElabInstances env)) of
        Just (ref, replacements) ->
          instantiateInstanceDictionaryRef env normalized ref replacements
        Nothing ->
          case superclassDictionary env normalized of
            Just dictionary -> dictionary
            Nothing ->
              case builtinStructuralDictionary env normalized of
                Just dictionary -> dictionary
                Nothing ->
                  Left
                    ( maybe
                        id
                        TypecheckErrorAt
                        (classConstraintSpan wanted)
                        (UnsolvedClassConstraint normalized)
                    )

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Nothing : rest -> firstJust rest
  Just value : _ -> Just value

matchInstanceDictionaryRef :: ClassConstraint -> InstanceDictionaryRef -> Maybe (InstanceDictionaryRef, Map.Map RName MonoType)
matchInstanceDictionaryRef wanted ref =
  (ref,) <$> matchClassConstraint (Set.fromList (instanceRefVariables ref)) (instanceRefConstraint ref) wanted

matchClassConstraint :: Set.Set RName -> ClassConstraint -> ClassConstraint -> Maybe (Map.Map RName MonoType)
matchClassConstraint variables patternConstraint actualConstraint
  | classConstraintClass patternConstraint /= classConstraintClass actualConstraint = Nothing
  | length (classConstraintArguments patternConstraint) /= length (classConstraintArguments actualConstraint) = Nothing
  | otherwise =
      foldM
        (\acc (patternArg, actualArg) -> matchMonoTypes variables patternArg actualArg acc)
        Map.empty
        (zip (classConstraintArguments patternConstraint) (classConstraintArguments actualConstraint))

instantiateInstanceDictionaryRef ::
  CoreElabEnv ->
  ClassConstraint ->
  InstanceDictionaryRef ->
  Map.Map RName MonoType ->
  Either TypecheckError CoreExpr
instantiateInstanceDictionaryRef env wanted ref replacements = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      instantiatedContext = map (replaceConstraintTypeVars replacements) (instanceRefContext ref)
  wantedDictTy <- classConstraintCoreType subst metas wanted
  dictionaryArguments <- traverse (resolveDictionary env) instantiatedContext
  refDictMono <- classConstraintMonoType (instanceRefConstraint ref)
  refTy <- schemeToCoreTypeWith subst metas (Scheme (instanceRefVariables ref) (instanceRefContext ref) refDictMono)
  typeArguments <-
    traverse
      ( \variable ->
          monoToCoreType subst metas (Map.findWithDefault (TyVar variable) variable replacements)
      )
      (instanceRefVariables ref)
  let dictionaryResultTy = foldr CTyFun wantedDictTy (map exprType dictionaryArguments)
      typedDictionary =
        case instanceRefVariables ref of
          [] -> CVar (instanceRefName ref) dictionaryResultTy
          _ -> CTypeApp (CVar (instanceRefName ref) refTy) typeArguments dictionaryResultTy
  pure (foldl applyValue typedDictionary dictionaryArguments)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

superclassDictionary :: CoreElabEnv -> ClassConstraint -> Maybe (Either TypecheckError CoreExpr)
superclassDictionary env wanted =
  firstJustEither (map localProjection localCandidates <> map instanceProjection instanceCandidates)
 where
  localCandidates =
    [ (source, dictionary)
    | (source, dictionary) <- coreElabDictionaries env
    , not (constraintMatches wanted source)
    ]
  instanceCandidates =
    [ (instanceRefConstraint ref, instanceRefName ref)
    | ref <- coreElabInstances env
    , null (instanceRefVariables ref)
    , null (instanceRefContext ref)
    , not (constraintMatches wanted (instanceRefConstraint ref))
    ]

  localProjection (source, dictionary) = do
    normalizedSource <- normalizeConstraint (coreElabSubst env) (coreElabMetas env) source
    projectSuperclassDictionary env wanted normalizedSource dictionary

  instanceProjection (source, dictionaryName) = do
    normalizedSource <- normalizeConstraint (coreElabSubst env) (coreElabMetas env) source
    sourceTy <- classConstraintCoreType (coreElabSubst env) (coreElabMetas env) normalizedSource
    projectSuperclassDictionary env wanted normalizedSource (CVar dictionaryName sourceTy)

firstJustEither :: [Either TypecheckError (Maybe a)] -> Maybe (Either TypecheckError a)
firstJustEither = \case
  [] -> Nothing
  result : rest ->
    case result of
      Left err -> Just (Left err)
      Right Nothing -> firstJustEither rest
      Right (Just value) -> Just (Right value)

projectSuperclassDictionary :: CoreElabEnv -> ClassConstraint -> ClassConstraint -> CoreExpr -> Either TypecheckError (Maybe CoreExpr)
projectSuperclassDictionary env wanted source dictionary =
  projectFrom Set.empty source dictionary
 where
  projectFrom visited current currentDictionary
    | classConstraintClass current `Set.member` visited = pure Nothing
    | otherwise =
        case Map.lookup (classConstraintClass current) (coreElabClasses env) of
          Nothing -> pure Nothing
          Just info ->
            case classConstraintArguments current of
              [argument] -> do
                let replacements = Map.singleton (classInfoVariable info) argument
                    instantiatedSuperclasses =
                      map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
                searchSuperclasses (Set.insert (classConstraintClass current) visited) info current currentDictionary instantiatedSuperclasses
              _ -> pure Nothing

  searchSuperclasses visited info current currentDictionary superclasses =
    firstProjection
      [ do
          projected <- projectDirectSuperclass env info current currentDictionary index superclass
          if constraintMatches wanted superclass
            then pure (Just projected)
            else projectFrom visited superclass projected
      | (index, superclass) <- zip [0 ..] superclasses
      ]

firstProjection :: [Either TypecheckError (Maybe a)] -> Either TypecheckError (Maybe a)
firstProjection = \case
  [] -> Right Nothing
  result : rest ->
    case result of
      Left err -> Left err
      Right Nothing -> firstProjection rest
      Right found -> Right found

projectDirectSuperclass ::
  CoreElabEnv ->
  ClassInfo ->
  ClassConstraint ->
  CoreExpr ->
  Int ->
  ClassConstraint ->
  Either TypecheckError CoreExpr
projectDirectSuperclass env info current dictionary index superclass = do
  dictTy <- classConstraintCoreType (coreElabSubst env) (coreElabMetas env) current
  resultTy <- classConstraintCoreType (coreElabSubst env) (coreElabMetas env) superclass
  selectorTy <- superclassSelectorCoreType info index
  typeArgument <-
    case classConstraintArguments current of
      [argument] -> monoToCoreType (coreElabSubst env) (coreElabMetas env) argument
      _ -> Left (InvalidClassConstraintArity (classInfoName info) (length (classConstraintArguments current)))
  let specializedSelector =
        CTypeApp
          (CVar (superclassSelectorName info index superclass) selectorTy)
          [typeArgument]
          (CTyFun dictTy resultTy)
  pure (CApp specializedSelector dictionary resultTy)

builtinStructuralDictionary :: CoreElabEnv -> ClassConstraint -> Maybe (Either TypecheckError CoreExpr)
builtinStructuralDictionary env wanted =
  case (classConstraintClass wanted, classConstraintArguments wanted) of
    (className, [TyList elementTy])
      | className == builtinEqClassName ->
          Just (eqListDictionaryValue env elementTy)
    (className, [TyList elementTy])
      | className == builtinOrdClassName ->
          Just (ordListDictionaryValue env elementTy)
    (className, [TyList elementTy])
      | className == builtinShowClassName ->
          Just (showListDictionaryValue env elementTy)
    (className, [TyList elementTy])
      | className == builtinReadClassName ->
          Just (readListDictionaryValue env elementTy)
    (className, [TyTuple fields])
      | className == builtinEqClassName && structuralTupleArity fields ->
          Just (eqTupleDictionaryValue env fields)
    (className, [TyTuple fields])
      | className == builtinOrdClassName && structuralTupleArity fields ->
          Just (ordTupleDictionaryValue env fields)
    (className, [TyTuple fields])
      | className == builtinIxClassName && structuralTupleArity fields ->
          Just (ixTupleDictionaryValue env fields)
    (className, [TyApp (TyCon ptrName) payloadTy])
      | className == builtinStorableClassName && ptrName == ptrTyConName ->
          Just (storablePtrDictionaryValue env payloadTy)
    _ -> Nothing

eqListDictionaryValue :: CoreElabEnv -> MonoType -> Either TypecheckError CoreExpr
eqListDictionaryValue env elementTy = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedElementTy = replaceMetasWithVars metas (applySubst subst elementTy)
      elementConstraint = singleClassConstraint builtinEqClassName normalizedElementTy
      listConstraint = singleClassConstraint builtinEqClassName (TyList normalizedElementTy)
  elementDictionary <- resolveDictionary env elementConstraint
  elementCoreTy <- monoToCoreType subst metas normalizedElementTy
  elementDictionaryTy <- classConstraintCoreType subst metas elementConstraint
  listDictionaryTy <- classConstraintCoreType subst metas listConstraint
  let listDictionaryFunctionTy = eqListDictionaryCoreType
      specializedFunction =
        CTypeApp
          (CVar eqListDictionaryName listDictionaryFunctionTy)
          [elementCoreTy]
          (CTyFun elementDictionaryTy listDictionaryTy)
  pure (CApp specializedFunction elementDictionary listDictionaryTy)

ordListDictionaryValue :: CoreElabEnv -> MonoType -> Either TypecheckError CoreExpr
ordListDictionaryValue env elementTy = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedElementTy = replaceMetasWithVars metas (applySubst subst elementTy)
      elementConstraint = singleClassConstraint builtinOrdClassName normalizedElementTy
      listConstraint = singleClassConstraint builtinOrdClassName (TyList normalizedElementTy)
  elementDictionary <- resolveDictionary env elementConstraint
  elementCoreTy <- monoToCoreType subst metas normalizedElementTy
  elementDictionaryTy <- classConstraintCoreType subst metas elementConstraint
  listDictionaryTy <- classConstraintCoreType subst metas listConstraint
  let listDictionaryFunctionTy = ordListDictionaryCoreType
      specializedFunction =
        CTypeApp
          (CVar ordListDictionaryName listDictionaryFunctionTy)
          [elementCoreTy]
          (CTyFun elementDictionaryTy listDictionaryTy)
  pure (CApp specializedFunction elementDictionary listDictionaryTy)

showListDictionaryValue :: CoreElabEnv -> MonoType -> Either TypecheckError CoreExpr
showListDictionaryValue env elementTy = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedElementTy = replaceMetasWithVars metas (applySubst subst elementTy)
      elementConstraint = singleClassConstraint builtinShowClassName normalizedElementTy
      listConstraint = singleClassConstraint builtinShowClassName (TyList normalizedElementTy)
  elementDictionary <- resolveDictionary env elementConstraint
  elementCoreTy <- monoToCoreType subst metas normalizedElementTy
  elementDictionaryTy <- classConstraintCoreType subst metas elementConstraint
  listDictionaryTy <- classConstraintCoreType subst metas listConstraint
  let listDictionaryFunctionTy = showListDictionaryCoreType
      specializedFunction =
        CTypeApp
          (CVar showListDictionaryName listDictionaryFunctionTy)
          [elementCoreTy]
          (CTyFun elementDictionaryTy listDictionaryTy)
  pure (CApp specializedFunction elementDictionary listDictionaryTy)

readListDictionaryValue :: CoreElabEnv -> MonoType -> Either TypecheckError CoreExpr
readListDictionaryValue env elementTy = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedElementTy = replaceMetasWithVars metas (applySubst subst elementTy)
      elementConstraint = singleClassConstraint builtinReadClassName normalizedElementTy
      listConstraint = singleClassConstraint builtinReadClassName (TyList normalizedElementTy)
  elementDictionary <- resolveDictionary env elementConstraint
  elementCoreTy <- monoToCoreType subst metas normalizedElementTy
  elementDictionaryTy <- classConstraintCoreType subst metas elementConstraint
  listDictionaryTy <- classConstraintCoreType subst metas listConstraint
  let listDictionaryFunctionTy = readListDictionaryCoreType
      specializedFunction =
        CTypeApp
          (CVar readListDictionaryName listDictionaryFunctionTy)
          [elementCoreTy]
          (CTyFun elementDictionaryTy listDictionaryTy)
  pure (CApp specializedFunction elementDictionary listDictionaryTy)

eqTupleDictionaryValue :: CoreElabEnv -> [MonoType] -> Either TypecheckError CoreExpr
eqTupleDictionaryValue env fields = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedFields = map (replaceMetasWithVars metas . applySubst subst) fields
  fieldCoreTys <- traverse (monoToCoreType subst metas) normalizedFields
  fieldDictionaries <- traverse (resolveDictionary env . singleClassConstraint builtinEqClassName) normalizedFields
  info <- requiredClassInfo env builtinEqClassName
  eqTupleDictionaryCore info fieldCoreTys fieldDictionaries

ordTupleDictionaryValue :: CoreElabEnv -> [MonoType] -> Either TypecheckError CoreExpr
ordTupleDictionaryValue env fields = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedFields = map (replaceMetasWithVars metas . applySubst subst) fields
  fieldCoreTys <- traverse (monoToCoreType subst metas) normalizedFields
  fieldDictionaries <- traverse (resolveDictionary env . singleClassConstraint builtinOrdClassName) normalizedFields
  eqInfo <- requiredClassInfo env builtinEqClassName
  ordInfo <- requiredClassInfo env builtinOrdClassName
  ordTupleDictionaryCore eqInfo ordInfo fieldCoreTys fieldDictionaries

ixTupleDictionaryValue :: CoreElabEnv -> [MonoType] -> Either TypecheckError CoreExpr
ixTupleDictionaryValue env fields = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedFields = map (replaceMetasWithVars metas . applySubst subst) fields
  fieldCoreTys <- traverse (monoToCoreType subst metas) normalizedFields
  fieldDictionaries <- traverse (resolveDictionary env . singleClassConstraint builtinIxClassName) normalizedFields
  eqInfo <- requiredClassInfo env builtinEqClassName
  ordInfo <- requiredClassInfo env builtinOrdClassName
  ixInfo <- requiredClassInfo env builtinIxClassName
  let fieldOrdDictionaries = zipWith ixOrdSuperclassCore fieldCoreTys fieldDictionaries
  ordSuperclass <- ordTupleDictionaryCore eqInfo ordInfo fieldCoreTys fieldOrdDictionaries
  ixTupleDictionaryCore ixInfo fieldCoreTys fieldDictionaries ordSuperclass

requiredClassInfo :: CoreElabEnv -> RName -> Either TypecheckError ClassInfo
requiredClassInfo env className =
  case Map.lookup className (coreElabClasses env) <|> Map.lookup className builtinClassInfos of
    Just info -> pure info
    Nothing -> Left (UnsupportedCore0 ("missing built-in class info for structural instance `" <> renderRName className <> "`"))

eqTupleDictionaryCore :: ClassInfo -> [CoreType] -> [CoreExpr] -> Either TypecheckError CoreExpr
eqTupleDictionaryCore info fieldTys fieldDictionaries = do
  constructorTy <- classDictionaryConstructorCoreType info
  let tupleTy = CTyTuple fieldTys
      dictTy = eqDictCoreType tupleTy
      eqMethod = eqTupleMethodCore "$eq_tuple" (-8200 - length fieldTys) fieldTys fieldDictionaries
      neqMethod =
        tupleBinaryMethod "$neq_tuple" (-8250 - length fieldTys) fieldTys boolTy $ \lhs rhs ->
          boolNotCore
            "$neq_tuple_not"
            (-8290 - length fieldTys)
            (eqTupleBody "$neq_tuple_eq" (-8295 - length fieldTys) fieldTys fieldDictionaries lhs rhs)
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [tupleTy]
          (CTyFun (exprType eqMethod) (CTyFun (exprType neqMethod) dictTy))
  pure (applyCore (applyCore typedConstructor eqMethod (CTyFun (exprType neqMethod) dictTy)) neqMethod dictTy)

eqTupleMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
eqTupleMethodCore occurrence unique fieldTys fieldDictionaries =
  tupleBinaryMethod occurrence unique fieldTys boolTy (eqTupleBody occurrence (unique - 40) fieldTys fieldDictionaries)

eqTupleBody :: Text -> Int -> [CoreType] -> [CoreExpr] -> [CoreExpr] -> [CoreExpr] -> CoreExpr
eqTupleBody occurrence unique fieldTys fieldDictionaries lhsFields rhsFields =
  foldr combine (CCon trueDataConName boolTy) (List.zip4 [0 :: Int ..] fieldTys fieldDictionaries (zip lhsFields rhsFields))
 where
  combine (index, fieldTy, dictionary, (lhs, rhs)) rest =
    boolAndCore
      (occurrence <> "_field_" <> renderInt index)
      (unique - index)
      (eqElementCore fieldTy dictionary lhs rhs)
      rest

ordTupleDictionaryCore :: ClassInfo -> ClassInfo -> [CoreType] -> [CoreExpr] -> Either TypecheckError CoreExpr
ordTupleDictionaryCore eqInfo ordInfo fieldTys fieldDictionaries = do
  constructorTy <- classDictionaryFullConstructorCoreType ordInfo
  eqSuperclass <- eqTupleDictionaryCore eqInfo fieldTys (zipWith ordEqSuperclassCore fieldTys fieldDictionaries)
  let tupleTy = CTyTuple fieldTys
      dictTy = ordDictCoreType tupleTy
      compareMethod = ordTupleCompareMethodCore "$compare_tuple" (-8300 - length fieldTys) fieldTys fieldDictionaries
      ltMethod = ordTuplePredicateMethodCore "$lt_tuple" (-8350 - length fieldTys) fieldTys fieldDictionaries True False False
      leMethod = ordTuplePredicateMethodCore "$le_tuple" (-8400 - length fieldTys) fieldTys fieldDictionaries True True False
      gtMethod = ordTuplePredicateMethodCore "$gt_tuple" (-8450 - length fieldTys) fieldTys fieldDictionaries False False True
      geMethod = ordTuplePredicateMethodCore "$ge_tuple" (-8500 - length fieldTys) fieldTys fieldDictionaries False True True
      maxMethod = ordTupleChoiceMethodCore "$max_tuple" (-8550 - length fieldTys) fieldTys fieldDictionaries (\lhs rhs -> (rhs, rhs, lhs))
      minMethod = ordTupleChoiceMethodCore "$min_tuple" (-8600 - length fieldTys) fieldTys fieldDictionaries (\lhs rhs -> (lhs, lhs, rhs))
      fieldExprs = [eqSuperclass, compareMethod, ltMethod, leMethod, gtMethod, geMethod, maxMethod, minMethod]
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName ordInfo) constructorTy)
          [tupleTy]
          (foldr CTyFun dictTy (map exprType fieldExprs))
  pure (foldl applyValue typedConstructor fieldExprs)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

ordTupleCompareMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
ordTupleCompareMethodCore occurrence unique fieldTys fieldDictionaries =
  tupleBinaryMethod occurrence unique fieldTys orderingTy (ordTupleCompareBody occurrence (unique - 40) fieldTys fieldDictionaries)

ordTupleCompareBody :: Text -> Int -> [CoreType] -> [CoreExpr] -> [CoreExpr] -> [CoreExpr] -> CoreExpr
ordTupleCompareBody occurrence unique fieldTys fieldDictionaries lhsFields rhsFields =
  compareFields 0 (List.zip4 fieldTys fieldDictionaries lhsFields rhsFields)
 where
  compareFields _ [] = CCon orderingEQDataConName orderingTy
  compareFields index ((fieldTy, dictionary, lhs, rhs) : rest) =
    orderingCaseCore
      (occurrence <> "_field_" <> renderInt index)
      (unique - index)
      (ordElementCompareCore fieldTy dictionary lhs rhs)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      (compareFields (index + 1) rest)
      (CCon orderingGTDataConName orderingTy)

ordTuplePredicateMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> Bool -> Bool -> Bool -> CoreExpr
ordTuplePredicateMethodCore occurrence unique fieldTys fieldDictionaries ltResult eqResult gtResult =
  tupleBinaryMethod occurrence unique fieldTys boolTy $ \lhs rhs ->
    orderingCaseCore
      (occurrence <> "_case")
      (unique - 40)
      (ordTupleCompareBody occurrence (unique - 80) fieldTys fieldDictionaries lhs rhs)
      boolTy
      (boolExpr ltResult)
      (boolExpr eqResult)
      (boolExpr gtResult)
 where
  boolExpr result =
    if result then CCon trueDataConName boolTy else CCon falseDataConName boolTy

ordTupleChoiceMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> (CoreExpr -> CoreExpr -> (CoreExpr, CoreExpr, CoreExpr)) -> CoreExpr
ordTupleChoiceMethodCore occurrence unique fieldTys fieldDictionaries choices =
  tupleBinaryMethodWithValues occurrence unique fieldTys tupleTy $ \lhsTuple rhsTuple lhsFields rhsFields ->
    let (ltBody, eqBody, gtBody) = choices lhsTuple rhsTuple
     in orderingCaseCore
          (occurrence <> "_case")
          (unique - 40)
          (ordTupleCompareBody occurrence (unique - 80) fieldTys fieldDictionaries lhsFields rhsFields)
          tupleTy
          ltBody
          eqBody
          gtBody
 where
  tupleTy = CTyTuple fieldTys

ixTupleDictionaryCore :: ClassInfo -> [CoreType] -> [CoreExpr] -> CoreExpr -> Either TypecheckError CoreExpr
ixTupleDictionaryCore info fieldTys fieldDictionaries ordSuperclass = do
  constructorTy <- classDictionaryFullConstructorCoreType info
  let tupleTy = CTyTuple fieldTys
      dictTy = ixDictCoreType tupleTy
      rangeMethod = ixTupleRangeMethodCore "$ix_range_tuple" (-8650 - length fieldTys) fieldTys fieldDictionaries
      indexMethod = ixTupleIndexMethodCore "$ix_index_tuple" (-8750 - length fieldTys) fieldTys fieldDictionaries
      inRangeMethod = ixTupleInRangeMethodCore "$ix_in_range_tuple" (-8850 - length fieldTys) fieldTys fieldDictionaries
      rangeSizeMethod = ixTupleRangeSizeMethodCore "$ix_range_size_tuple" (-8950 - length fieldTys) fieldTys fieldDictionaries
      fieldExprs = [ordSuperclass, rangeMethod, indexMethod, inRangeMethod, rangeSizeMethod]
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [tupleTy]
          (foldr CTyFun dictTy (map exprType fieldExprs))
  pure (foldl applyValue typedConstructor fieldExprs)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

ixTupleRangeMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
ixTupleRangeMethodCore occurrence unique fieldTys fieldDictionaries =
  ixTupleBoundsCaseMethod occurrence unique fieldTys (CTyList tupleTy) $ \lowerFields upperFields ->
    ixTupleRangeProduct (occurrence <> "_product") (unique - 40) fieldTys fieldDictionaries lowerFields upperFields []
 where
  tupleTy = CTyTuple fieldTys

ixTupleIndexMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
ixTupleIndexMethodCore occurrence unique fieldTys fieldDictionaries =
  ixTupleValueMethod occurrence unique fieldTys intTy $ \lowerFields upperFields valueFields ->
    let indexes = List.zipWith4 ixIndexCallCore fieldTys fieldDictionaries (zip lowerFields upperFields) valueFields
        sizes = List.zipWith3 ixRangeSizeCallCore fieldTys fieldDictionaries (zip lowerFields upperFields)
     in case indexes of
          [] -> zeroInt
          firstIndex : restIndexes ->
            foldl
              (\acc (size, fieldIndex) -> intAdd (intMul acc size) fieldIndex)
              firstIndex
              (zip (drop 1 sizes) restIndexes)

ixTupleInRangeMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
ixTupleInRangeMethodCore occurrence unique fieldTys fieldDictionaries =
  ixTupleValueMethod occurrence unique fieldTys boolTy $ \lowerFields upperFields valueFields ->
    foldr
      (\(index, fieldTy, dictionary, bounds, value) rest -> boolAndCore (occurrence <> "_field_" <> renderInt index) (unique - 80 - index) (ixInRangeCallCore fieldTy dictionary bounds value) rest)
      (CCon trueDataConName boolTy)
      (List.zip5 [0 :: Int ..] fieldTys fieldDictionaries (zip lowerFields upperFields) valueFields)

ixTupleRangeSizeMethodCore :: Text -> Int -> [CoreType] -> [CoreExpr] -> CoreExpr
ixTupleRangeSizeMethodCore occurrence unique fieldTys fieldDictionaries =
  ixTupleBoundsCaseMethod occurrence unique fieldTys intTy $ \lowerFields upperFields ->
    foldl
      intMul
      oneInt
      (List.zipWith3 ixRangeSizeCallCore fieldTys fieldDictionaries (zip lowerFields upperFields))

ixTupleRangeProduct :: Text -> Int -> [CoreType] -> [CoreExpr] -> [CoreExpr] -> [CoreExpr] -> [CoreExpr] -> CoreExpr
ixTupleRangeProduct occurrence unique allFieldTys fieldDictionaries lowerFields upperFields selected =
  case (drop selectedCount allFieldTys, drop selectedCount fieldDictionaries, drop selectedCount lowerFields, drop selectedCount upperFields) of
    ([], [], [], []) ->
      consCore tupleTy (tupleValueCore allFieldTys selected) (nilCore tupleTy)
    (fieldTy : _, dictionary : _, lower : _, upper : _) ->
      let valueName = builtinLocalTermName (occurrence <> "_value_" <> renderInt selectedCount) (unique - selectedCount)
          value = CVar valueName fieldTy
          continuation =
            CLam
              (CoreBinder valueName fieldTy)
              (ixTupleRangeProduct occurrence unique allFieldTys fieldDictionaries lowerFields upperFields (selected <> [value]))
              (CTyFun fieldTy (CTyList tupleTy))
       in listBindCore fieldTy tupleTy (ixRangeCallCore fieldTy dictionary (lower, upper)) continuation
    _ -> bottomCore (occurrence <> "_malformed") (unique - 1000) (CTyList tupleTy)
 where
  selectedCount = length selected
  tupleTy = CTyTuple allFieldTys

tupleBinaryMethod :: Text -> Int -> [CoreType] -> CoreType -> ([CoreExpr] -> [CoreExpr] -> CoreExpr) -> CoreExpr
tupleBinaryMethod occurrence unique fieldTys resultTy body =
  tupleBinaryMethodWithValues occurrence unique fieldTys resultTy (\_ _ lhs rhs -> body lhs rhs)

tupleBinaryMethodWithValues :: Text -> Int -> [CoreType] -> CoreType -> (CoreExpr -> CoreExpr -> [CoreExpr] -> [CoreExpr] -> CoreExpr) -> CoreExpr
tupleBinaryMethodWithValues occurrence unique fieldTys resultTy body =
  CLam (CoreBinder lhsName tupleTy) (CLam (CoreBinder rhsName tupleTy) lhsCase (CTyFun tupleTy resultTy)) (CTyFun tupleTy (CTyFun tupleTy resultTy))
 where
  tupleTy = CTyTuple fieldTys
  lhsName = builtinLocalTermName (occurrence <> "_lhs") unique
  rhsName = builtinLocalTermName (occurrence <> "_rhs") (unique - 1)
  lhsCaseName = builtinLocalTermName (occurrence <> "_lhs_case") (unique - 2)
  rhsCaseName = builtinLocalTermName (occurrence <> "_rhs_case") (unique - 3)
  lhsFieldNames = [builtinLocalTermName (occurrence <> "_lhs_" <> renderInt index) (unique - 10 - index) | index <- [0 .. length fieldTys - 1]]
  rhsFieldNames = [builtinLocalTermName (occurrence <> "_rhs_" <> renderInt index) (unique - 30 - index) | index <- [0 .. length fieldTys - 1]]
  lhsFields = zipWith CVar lhsFieldNames fieldTys
  rhsFields = zipWith CVar rhsFieldNames fieldTys
  lhsTuple = CVar lhsName tupleTy
  rhsTuple = CVar rhsName tupleTy
  rhsCase =
    CCase
      rhsTuple
      (CoreBinder rhsCaseName tupleTy)
      [CoreAlt (ConstructorAlt (tupleDataConName (length fieldTys))) (zipWith CoreBinder rhsFieldNames fieldTys) (body lhsTuple rhsTuple lhsFields rhsFields)]
      resultTy
  lhsCase =
    CCase
      lhsTuple
      (CoreBinder lhsCaseName tupleTy)
      [CoreAlt (ConstructorAlt (tupleDataConName (length fieldTys))) (zipWith CoreBinder lhsFieldNames fieldTys) rhsCase]
      resultTy

ixTupleBoundsCaseMethod :: Text -> Int -> [CoreType] -> CoreType -> ([CoreExpr] -> [CoreExpr] -> CoreExpr) -> CoreExpr
ixTupleBoundsCaseMethod occurrence unique fieldTys resultTy body =
  CLam (CoreBinder boundsName boundsTy) boundsCase (CTyFun boundsTy resultTy)
 where
  tupleTy = CTyTuple fieldTys
  boundsTy = CTyTuple [tupleTy, tupleTy]
  boundsName = builtinLocalTermName (occurrence <> "_bounds") unique
  boundsCaseName = builtinLocalTermName (occurrence <> "_bounds_case") (unique - 1)
  lowerName = builtinLocalTermName (occurrence <> "_lower_tuple") (unique - 2)
  upperName = builtinLocalTermName (occurrence <> "_upper_tuple") (unique - 3)
  lowerTuple = CVar lowerName tupleTy
  upperTuple = CVar upperName tupleTy
  boundsCase =
    CCase
      (CVar boundsName boundsTy)
      (CoreBinder boundsCaseName boundsTy)
      [ CoreAlt
          (ConstructorAlt (tupleDataConName 2))
          [CoreBinder lowerName tupleTy, CoreBinder upperName tupleTy]
          (caseTupleFields (occurrence <> "_lower") (unique - 20) fieldTys lowerTuple resultTy $ \lowerFields ->
             caseTupleFields (occurrence <> "_upper") (unique - 40) fieldTys upperTuple resultTy $ \upperFields ->
               body lowerFields upperFields)
      ]
      resultTy

ixTupleValueMethod :: Text -> Int -> [CoreType] -> CoreType -> ([CoreExpr] -> [CoreExpr] -> [CoreExpr] -> CoreExpr) -> CoreExpr
ixTupleValueMethod occurrence unique fieldTys resultTy body =
  CLam (CoreBinder boundsName boundsTy) (CLam (CoreBinder valueName tupleTy) boundsCase (CTyFun tupleTy resultTy)) (CTyFun boundsTy (CTyFun tupleTy resultTy))
 where
  tupleTy = CTyTuple fieldTys
  boundsTy = CTyTuple [tupleTy, tupleTy]
  boundsName = builtinLocalTermName (occurrence <> "_bounds") unique
  valueName = builtinLocalTermName (occurrence <> "_value") (unique - 1)
  boundsCaseName = builtinLocalTermName (occurrence <> "_bounds_case") (unique - 2)
  lowerName = builtinLocalTermName (occurrence <> "_lower_tuple") (unique - 3)
  upperName = builtinLocalTermName (occurrence <> "_upper_tuple") (unique - 4)
  lowerTuple = CVar lowerName tupleTy
  upperTuple = CVar upperName tupleTy
  valueTuple = CVar valueName tupleTy
  boundsCase =
    CCase
      (CVar boundsName boundsTy)
      (CoreBinder boundsCaseName boundsTy)
      [ CoreAlt
          (ConstructorAlt (tupleDataConName 2))
          [CoreBinder lowerName tupleTy, CoreBinder upperName tupleTy]
          (caseTupleFields (occurrence <> "_lower") (unique - 20) fieldTys lowerTuple resultTy $ \lowerFields ->
             caseTupleFields (occurrence <> "_upper") (unique - 40) fieldTys upperTuple resultTy $ \upperFields ->
               caseTupleFields (occurrence <> "_value") (unique - 60) fieldTys valueTuple resultTy $ \valueFields ->
                 body lowerFields upperFields valueFields)
      ]
      resultTy

caseTupleFields :: Text -> Int -> [CoreType] -> CoreExpr -> CoreType -> ([CoreExpr] -> CoreExpr) -> CoreExpr
caseTupleFields occurrence unique fieldTys scrutinee resultTy body =
  CCase
    scrutinee
    (CoreBinder caseName tupleTy)
    [CoreAlt (ConstructorAlt (tupleDataConName (length fieldTys))) (zipWith CoreBinder fieldNames fieldTys) (body fields)]
    resultTy
 where
  tupleTy = CTyTuple fieldTys
  caseName = builtinLocalTermName (occurrence <> "_case") unique
  fieldNames = [builtinLocalTermName (occurrence <> "_field_" <> renderInt index) (unique - 1 - index) | index <- [0 .. length fieldTys - 1]]
  fields = zipWith CVar fieldNames fieldTys

tupleValueCore :: [CoreType] -> [CoreExpr] -> CoreExpr
tupleValueCore fieldTys fields =
  constructorApp (tupleDataConName (length fieldTys)) fieldTys fields (CTyTuple fieldTys)

listBindCore :: CoreType -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr
listBindCore elementTy resultElementTy xs continuation =
  applyCore (applyCore bindFunction xs (CTyFun (CTyFun elementTy resultListTy) resultListTy)) continuation resultListTy
 where
  listA = CTyList elementTy
  resultListTy = CTyList resultElementTy
  bindFunction =
    CTypeApp
      (CVar monadListBindName monadListBindCoreType)
      [elementTy, resultElementTy]
      (CTyFun listA (CTyFun (CTyFun elementTy resultListTy) resultListTy))

ixDictCoreType :: CoreType -> CoreType
ixDictCoreType ty =
  CTyApp (CTyCon (classDictionaryTypeName builtinIxClassName)) ty

ixOrdSuperclassCore :: CoreType -> CoreExpr -> CoreExpr
ixOrdSuperclassCore elementTy dictionary =
  CCase
    dictionary
    (CoreBinder caseName ixDictA)
    [ CoreAlt
        (ConstructorAlt (classDictionaryConstructorName builtinIxClassName))
        [ CoreBinder ordName ordDictA
        , CoreBinder rangeName rangeTy
        , CoreBinder indexName indexTy
        , CoreBinder inRangeName inRangeTy
        , CoreBinder rangeSizeName rangeSizeTy
        ]
        (CVar ordName ordDictA)
    ]
    ordDictA
 where
  ixDictA = ixDictCoreType elementTy
  ordDictA = ordDictCoreType elementTy
  boundsTy = CTyTuple [elementTy, elementTy]
  rangeTy = CTyFun boundsTy (CTyList elementTy)
  indexTy = CTyFun boundsTy (CTyFun elementTy intTy)
  inRangeTy = CTyFun boundsTy (CTyFun elementTy boolTy)
  rangeSizeTy = CTyFun boundsTy intTy
  caseName = builtinLocalTermName "$ix_ord_super_case" (-9000)
  ordName = builtinLocalTermName "$ix_ord_super_ord" (-9001)
  rangeName = builtinLocalTermName "$ix_ord_super_range" (-9002)
  indexName = builtinLocalTermName "$ix_ord_super_index" (-9003)
  inRangeName = builtinLocalTermName "$ix_ord_super_in_range" (-9004)
  rangeSizeName = builtinLocalTermName "$ix_ord_super_range_size" (-9005)

ixRangeCallCore :: CoreType -> CoreExpr -> (CoreExpr, CoreExpr) -> CoreExpr
ixRangeCallCore elementTy dictionary bounds =
  applyCore (applyCore ixRangeFunction dictionary (CTyFun boundsTy listTy)) (tupleValueCore [elementTy, elementTy] [fst bounds, snd bounds]) listTy
 where
  boundsTy = CTyTuple [elementTy, elementTy]
  listTy = CTyList elementTy
  ixRangeFunction =
    CTypeApp
      (CVar (preludeTermName "range" (-3601)) ixRangeSelectorCoreType)
      [elementTy]
      (CTyFun (ixDictCoreType elementTy) (CTyFun boundsTy listTy))

ixIndexCallCore :: CoreType -> CoreExpr -> (CoreExpr, CoreExpr) -> CoreExpr -> CoreExpr
ixIndexCallCore elementTy dictionary bounds value =
  applyCore (applyCore (applyCore ixIndexFunction dictionary (CTyFun boundsTy (CTyFun elementTy intTy))) (tupleValueCore [elementTy, elementTy] [fst bounds, snd bounds]) (CTyFun elementTy intTy)) value intTy
 where
  boundsTy = CTyTuple [elementTy, elementTy]
  ixIndexFunction =
    CTypeApp
      (CVar (preludeTermName "index" (-3602)) ixIndexSelectorCoreType)
      [elementTy]
      (CTyFun (ixDictCoreType elementTy) (CTyFun boundsTy (CTyFun elementTy intTy)))

ixInRangeCallCore :: CoreType -> CoreExpr -> (CoreExpr, CoreExpr) -> CoreExpr -> CoreExpr
ixInRangeCallCore elementTy dictionary bounds value =
  applyCore (applyCore (applyCore ixInRangeFunction dictionary (CTyFun boundsTy (CTyFun elementTy boolTy))) (tupleValueCore [elementTy, elementTy] [fst bounds, snd bounds]) (CTyFun elementTy boolTy)) value boolTy
 where
  boundsTy = CTyTuple [elementTy, elementTy]
  ixInRangeFunction =
    CTypeApp
      (CVar (preludeTermName "inRange" (-3603)) ixInRangeSelectorCoreType)
      [elementTy]
      (CTyFun (ixDictCoreType elementTy) (CTyFun boundsTy (CTyFun elementTy boolTy)))

ixRangeSizeCallCore :: CoreType -> CoreExpr -> (CoreExpr, CoreExpr) -> CoreExpr
ixRangeSizeCallCore elementTy dictionary bounds =
  applyCore (applyCore ixRangeSizeFunction dictionary (CTyFun boundsTy intTy)) (tupleValueCore [elementTy, elementTy] [fst bounds, snd bounds]) intTy
 where
  boundsTy = CTyTuple [elementTy, elementTy]
  ixRangeSizeFunction =
    CTypeApp
      (CVar (preludeTermName "rangeSize" (-3604)) ixRangeSizeSelectorCoreType)
      [elementTy]
      (CTyFun (ixDictCoreType elementTy) (CTyFun boundsTy intTy))

ixRangeSelectorCoreType, ixIndexSelectorCoreType, ixInRangeSelectorCoreType, ixRangeSizeSelectorCoreType :: CoreType
ixRangeSelectorCoreType =
  CTyForall [a] (CTyFun ixDictA (CTyFun boundsA (CTyList aTy)))
 where
  a = preludeTypeVariable "a" (-1398)
  aTy = CTyVar a
  ixDictA = ixDictCoreType aTy
  boundsA = CTyTuple [aTy, aTy]
ixIndexSelectorCoreType =
  CTyForall [a] (CTyFun ixDictA (CTyFun boundsA (CTyFun aTy intTy)))
 where
  a = preludeTypeVariable "a" (-1398)
  aTy = CTyVar a
  ixDictA = ixDictCoreType aTy
  boundsA = CTyTuple [aTy, aTy]
ixInRangeSelectorCoreType =
  CTyForall [a] (CTyFun ixDictA (CTyFun boundsA (CTyFun aTy boolTy)))
 where
  a = preludeTypeVariable "a" (-1398)
  aTy = CTyVar a
  ixDictA = ixDictCoreType aTy
  boundsA = CTyTuple [aTy, aTy]
ixRangeSizeSelectorCoreType =
  CTyForall [a] (CTyFun ixDictA (CTyFun boundsA intTy))
 where
  a = preludeTypeVariable "a" (-1398)
  aTy = CTyVar a
  ixDictA = ixDictCoreType aTy
  boundsA = CTyTuple [aTy, aTy]

normalizeConstraint :: Subst -> Map.Map Int RName -> ClassConstraint -> Either TypecheckError ClassConstraint
normalizeConstraint subst metas =
  pure . mapClassConstraintArguments (replaceMetasWithVars metas . applySubst subst)

constraintMatches :: ClassConstraint -> ClassConstraint -> Bool
constraintMatches lhs rhs =
  classConstraintClass lhs == classConstraintClass rhs
    && classConstraintArguments lhs == classConstraintArguments rhs

classConstraintCoreType :: Subst -> Map.Map Int RName -> ClassConstraint -> Either TypecheckError CoreType
classConstraintCoreType subst metas constraint = do
  dictTy <- classConstraintMonoType constraint
  monoToCoreType subst metas dictTy

classConstraintMonoType :: ClassConstraint -> Either TypecheckError MonoType
classConstraintMonoType constraint = do
  ty <- classConstraintSingleArgument constraint
  pure (TyApp (TyCon (classDictionaryTypeName (classConstraintClass constraint))) ty)

instanceDictionaryRefs ::
  Subst ->
  Map.Map RName ClassInfo ->
  [TypedInstanceDictionary] ->
  [InstanceDictionaryRef]
instanceDictionaryRefs subst _classes =
  map
    ( \dictionary ->
        InstanceDictionaryRef
          { instanceRefConstraint =
              singleClassConstraint
                (typedInstanceClass dictionary)
                (applySubst subst (typedInstanceType dictionary))
          , instanceRefVariables = typedInstanceVariables dictionary
          , instanceRefContext = map (applyConstraintSubst subst) (typedInstanceContext dictionary)
          , instanceRefName = typedInstanceDictName dictionary
          }
    )

builtinInstanceDictionaries :: Map.Map RName ClassInfo -> [BuiltinInstanceDictionary]
builtinInstanceDictionaries classes =
  concat
    [ maybe [] eqInstances (Map.lookup builtinEqClassName classes)
    , maybe [] ordInstances (Map.lookup builtinOrdClassName classes)
    , maybe [] numInstances (Map.lookup builtinNumClassName classes)
    , maybe [] realInstances (Map.lookup builtinRealClassName classes)
    , maybe [] integralInstances (Map.lookup builtinIntegralClassName classes)
    , maybe [] fractionalInstances (Map.lookup builtinFractionalClassName classes)
    , maybe [] floatingInstances (Map.lookup builtinFloatingClassName classes)
    , maybe [] realFracInstances (Map.lookup builtinRealFracClassName classes)
    , maybe [] realFloatInstances (Map.lookup builtinRealFloatClassName classes)
    , maybe [] bitsInstances (Map.lookup builtinBitsClassName classes)
    , maybe [] showInstances (Map.lookup builtinShowClassName classes)
    , maybe [] readInstances (Map.lookup builtinReadClassName classes)
    , maybe [] enumInstances (Map.lookup builtinEnumClassName classes)
    , maybe [] boundedInstances (Map.lookup builtinBoundedClassName classes)
    , maybe [] ixInstances (Map.lookup builtinIxClassName classes)
    , maybe [] functorInstances (Map.lookup builtinFunctorClassName classes)
    , maybe [] monadInstances (Map.lookup builtinMonadClassName classes)
    , maybe [] monadPlusInstances (Map.lookup builtinMonadPlusClassName classes)
    , maybe [] storableInstances (Map.lookup builtinStorableClassName classes)
    ]
 where
  eqInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fEqInt" (-1501))
        [intEqMethod, intNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fEqBool" (-1502))
        [boolEqMethod, boolNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fEqChar" (-1503))
        [charEqMethod, charNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        ioErrorTypeMonoType
        (preludeTermName "$fEqIOErrorType" (-1505))
        [ioErrorTypeEqMethod, ioErrorTypeNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        orderingMonoType
        (preludeTermName "$fEqOrdering" (-1506))
        [orderingEqMethod, orderingNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        exitCodeMonoType
        (preludeTermName "$fEqExitCode" (-1509))
        [exitCodeEqMethod, exitCodeNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        unitMonoType
        (preludeTermName "$fEqUnit" (-1507))
        [unitEqMethod, unitNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fEqRatioInt" (-1508))
        [ratioEqMethod, ratioNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fEqFloat" (-5801))
        [floatEqMethod, floatNotEqMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fEqDouble" (-5802))
        [doubleEqMethod, doubleNotEqMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Eq" (-6400) fixedEqMethods

  ordInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fOrdInt" (-1511))
        [ intCompareMethod
        , intLtMethod
        , intLeMethod
        , intGtMethod
        , intGeMethod
        , intMaxMethod
        , intMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fOrdBool" (-1512))
        [ boolCompareMethod
        , boolLtMethod
        , boolLeMethod
        , boolGtMethod
        , boolGeMethod
        , boolMaxMethod
        , boolMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fOrdChar" (-1513))
        [ charCompareMethod
        , charLtMethod
        , charLeMethod
        , charGtMethod
        , charGeMethod
        , charMaxMethod
        , charMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        orderingMonoType
        (preludeTermName "$fOrdOrdering" (-1515))
        [ orderingCompareMethod
        , orderingLtMethod
        , orderingLeMethod
        , orderingGtMethod
        , orderingGeMethod
        , orderingMaxMethod
        , orderingMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        exitCodeMonoType
        (preludeTermName "$fOrdExitCode" (-1518))
        [ exitCodeCompareMethod
        , exitCodeLtMethod
        , exitCodeLeMethod
        , exitCodeGtMethod
        , exitCodeGeMethod
        , exitCodeMaxMethod
        , exitCodeMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        unitMonoType
        (preludeTermName "$fOrdUnit" (-1516))
        [ unitCompareMethod
        , unitLtMethod
        , unitLeMethod
        , unitGtMethod
        , unitGeMethod
        , unitMaxMethod
        , unitMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fOrdRatioInt" (-1517))
        [ ratioCompareMethod
        , ratioLtMethod
        , ratioLeMethod
        , ratioGtMethod
        , ratioGeMethod
        , ratioMaxMethod
        , ratioMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fOrdFloat" (-5803))
        [ floatCompareMethod
        , floatLtMethod
        , floatLeMethod
        , floatGtMethod
        , floatGeMethod
        , floatMaxMethod
        , floatMinMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fOrdDouble" (-5804))
        [ doubleCompareMethod
        , doubleLtMethod
        , doubleLeMethod
        , doubleGtMethod
        , doubleGeMethod
        , doubleMaxMethod
        , doubleMinMethod
        ]
    ]
      <> fixedIntegralBuiltinInstances info "Ord" (-6420) fixedOrdMethods

  numInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fNumInt" (-1521))
        [ intAddMethod
        , intSubMethod
        , intMulMethod
        , intNegateMethod
        , intAbsMethod
        , intSignumMethod
        , intFromIntegerMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fNumRatioInt" (-1522))
        [ ratioAddMethod
        , ratioSubMethod
        , ratioMulMethod
        , ratioNegateMethod
        , ratioAbsMethod
        , ratioSignumMethod
        , ratioFromIntegerMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fNumFloat" (-5805))
        [ floatAddMethod
        , floatSubMethod
        , floatMulMethod
        , floatNegateMethod
        , floatAbsMethod
        , floatSignumMethod
        , floatFromIntegerMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fNumDouble" (-5806))
        [ doubleAddMethod
        , doubleSubMethod
        , doubleMulMethod
        , doubleNegateMethod
        , doubleAbsMethod
        , doubleSignumMethod
        , doubleFromIntegerMethod
        ]
    ]
      <> fixedIntegralBuiltinInstances info "Num" (-6440) fixedNumMethods

  realInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fRealInt" (-1571))
        [intToRationalMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fRealRatioInt" (-1572))
        [ratioToRationalMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fRealFloat" (-5807))
        [floatToRationalMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fRealDouble" (-5808))
        [doubleToRationalMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Real" (-6460) fixedRealMethods

  integralInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fIntegralInt" (-1581))
        [ intQuotMethod
        , intRemMethod
        , intDivMethod
        , intModMethod
        , intQuotRemMethod
        , intDivModMethod
        , intToIntegerMethod
        ]
    ]
      <> fixedIntegralBuiltinInstances info "Integral" (-6480) fixedIntegralMethods

  fractionalInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fFractionalFloat" (-5809))
        [floatDivMethod, floatRecipMethod, floatFromRationalMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fFractionalDouble" (-5810))
        [doubleDivMethod, doubleRecipMethod, doubleFromRationalMethod]
    ]

  floatingInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fFloatingFloat" (-5811))
        (floatingMethods FloatWidth floatTy (-3460))
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fFloatingDouble" (-5812))
        (floatingMethods DoubleWidth doubleTy (-3490))
    ]

  realFracInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fRealFracFloat" (-5813))
        (realFracMethods FloatWidth floatTy (-3520))
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fRealFracDouble" (-5814))
        (realFracMethods DoubleWidth doubleTy (-3540))
    ]

  realFloatInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fRealFloatFloat" (-5815))
        (realFloatMethods FloatWidth floatTy floatInfo (-3560))
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fRealFloatDouble" (-5816))
        (realFloatMethods DoubleWidth doubleTy doubleInfo (-3590))
    ]
  floatInfo = FloatingTypeInfo 24 (-125) 128
  doubleInfo = FloatingTypeInfo 53 (-1021) 1024

  bitsInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fBitsInt" (-3921))
        [ intBitAndMethod
        , intBitOrMethod
        , intBitXorMethod
        , intBitComplementMethod
        , intShiftMethod
        , intRotateMethod
        , intBitMethod
        , intSetBitMethod
        , intClearBitMethod
        , intComplementBitMethod
        , intTestBitMethod
        , intBitSizeMethod
        , intIsSignedMethod
        , intShiftLMethod
        , intShiftRMethod
        , intRotateLMethod
        , intRotateRMethod
        ]
    ]
      <> fixedIntegralBuiltinInstances info "Bits" (-6500) fixedBitsMethods

  showInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fShowInt" (-1531))
        [intShowsPrecMethod, intShowMethod, intShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fShowBool" (-1532))
        [boolShowsPrecMethod, boolShowMethod, boolShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fShowChar" (-1533))
        [charShowsPrecMethod, charShowMethod, charShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        stringMonoType
        (preludeTermName "$fShowString" (-1534))
        [stringShowsPrecMethod, stringShowMethod, stringShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        ioErrorTypeMonoType
        (preludeTermName "$fShowIOErrorType" (-1535))
        [ioErrorTypeShowsPrecMethod, ioErrorTypeShowMethod, ioErrorTypeShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        orderingMonoType
        (preludeTermName "$fShowOrdering" (-1536))
        [orderingShowsPrecMethod, orderingShowMethod, orderingShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        exitCodeMonoType
        (preludeTermName "$fShowExitCode" (-1539))
        [exitCodeShowsPrecMethod, exitCodeShowMethod, exitCodeShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        unitMonoType
        (preludeTermName "$fShowUnit" (-1537))
        [unitShowsPrecMethod, unitShowMethod, unitShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fShowRatioInt" (-1538))
        [ratioShowsPrecMethod, ratioShowMethod, ratioShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fShowFloat" (-5821))
        [floatShowsPrecMethod, floatShowMethod, floatShowListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fShowDouble" (-5822))
        [doubleShowsPrecMethod, doubleShowMethod, doubleShowListMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Show" (-6520) fixedShowMethods

  readInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fReadInt" (-1701))
        [intReadsPrecMethod, intReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fReadBool" (-1702))
        [boolReadsPrecMethod, boolReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fReadChar" (-1703))
        [charReadsPrecMethod, charReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        orderingMonoType
        (preludeTermName "$fReadOrdering" (-1704))
        [orderingReadsPrecMethod, orderingReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        exitCodeMonoType
        (preludeTermName "$fReadExitCode" (-1707))
        [exitCodeReadsPrecMethod, exitCodeReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        unitMonoType
        (preludeTermName "$fReadUnit" (-1705))
        [unitReadsPrecMethod, unitReadListMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        rationalMonoType
        (preludeTermName "$fReadRatioInt" (-1706))
        [ratioReadsPrecMethod, ratioReadListMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Read" (-6540) fixedReadMethods

  enumInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fEnumInt" (-1541))
        [ intSuccMethod
        , intPredMethod
        , intToEnumMethod
        , intFromEnumMethod
        , intEnumFromMethod
        , intEnumFromThenMethod
        , intEnumFromToMethod
        , intEnumFromThenToMethod
        ]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fEnumChar" (-1542))
        [ charSuccMethod
        , charPredMethod
        , charToEnumMethod
        , charFromEnumMethod
        , charEnumFromMethod
        , charEnumFromThenMethod
        , charEnumFromToMethod
        , charEnumFromThenToMethod
        ]
    ]
      <> fixedIntegralBuiltinInstances info "Enum" (-6560) fixedEnumMethods

  boundedInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fBoundedInt" (-1551))
        [intMinBoundMethod, intMaxBoundMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fBoundedChar" (-1552))
        [charMinBoundMethod, charMaxBoundMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fBoundedBool" (-1553))
        [boolMinBoundMethod, boolMaxBoundMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Bounded" (-6580) fixedBoundedMethods

  ixInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fIxInt" (-3611))
        [ixRangeIntMethod, ixIndexIntMethod, ixInRangeIntMethod, ixRangeSizeIntMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fIxChar" (-3612))
        [ixRangeCharMethod, ixIndexCharMethod, ixInRangeCharMethod, ixRangeSizeCharMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fIxBool" (-3613))
        [ixRangeBoolMethod, ixIndexBoolMethod, ixInRangeBoolMethod, ixRangeSizeBoolMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        orderingMonoType
        (preludeTermName "$fIxOrdering" (-3614))
        [ixRangeOrderingMethod, ixIndexOrderingMethod, ixInRangeOrderingMethod, ixRangeSizeOrderingMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        unitMonoType
        (preludeTermName "$fIxUnit" (-3615))
        [ixRangeUnitMethod, ixIndexUnitMethod, ixInRangeUnitMethod, ixRangeSizeUnitMethod]
    ]
      <> fixedIntegralBuiltinInstances info "Ix" (-6600) fixedIxMethods

  functorInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon ioTyConName)
        (preludeTermName "$fFunctorIO" (-1591))
        [ioFunctorFmapMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon maybeTyConName)
        (preludeTermName "$fFunctorMaybe" (-1592))
        [maybeFunctorFmapMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon listTyConName)
        (preludeTermName "$fFunctorList" (-1593))
        [listFunctorFmapMethod]
    ]

  monadInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon ioTyConName)
        (preludeTermName "$fMonadIO" (-1561))
        [ioMonadBindMethod, ioMonadThenMethod, ioMonadReturnMethod, ioMonadFailMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon maybeTyConName)
        (preludeTermName "$fMonadMaybe" (-1562))
        [maybeMonadBindMethod, maybeMonadThenMethod, maybeMonadReturnMethod, maybeMonadFailMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon listTyConName)
        (preludeTermName "$fMonadList" (-1563))
        [listMonadBindMethod, listMonadThenMethod, listMonadReturnMethod, listMonadFailMethod]
    ]

  monadPlusInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon maybeTyConName)
        (preludeTermName "$fMonadPlusMaybe" (-1594))
        [maybeMonadPlusMzeroMethod, maybeMonadPlusMplusMethod]
    , BuiltinInstanceDictionary
        (classInfoName info)
        (TyCon listTyConName)
        (preludeTermName "$fMonadPlusList" (-1595))
        [listMonadPlusMzeroMethod, listMonadPlusMplusMethod]
    ]

  storableInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fStorableInt" (-6700))
        (storableMethods StoreInt 8 8 intTy)
    , BuiltinInstanceDictionary
        (classInfoName info)
        boolMonoType
        (preludeTermName "$fStorableBool" (-6701))
        (storableMethods StoreBool 1 1 boolTy)
    , BuiltinInstanceDictionary
        (classInfoName info)
        charMonoType
        (preludeTermName "$fStorableChar" (-6702))
        (storableMethods StoreChar 4 4 charTy)
    , BuiltinInstanceDictionary
        (classInfoName info)
        floatMonoType
        (preludeTermName "$fStorableFloat" (-6703))
        (storableMethods StoreFloat 4 4 floatTy)
    , BuiltinInstanceDictionary
        (classInfoName info)
        doubleMonoType
        (preludeTermName "$fStorableDouble" (-6704))
        (storableMethods StoreDouble 8 8 doubleTy)
    ]
      <> [ BuiltinInstanceDictionary
            (classInfoName info)
            (fixedIntegralMonoType fixed)
            (preludeTermName ("$fStorable" <> fixedIntegralOccurrence fixed) (-6710 - fromEnum fixed))
            (storableMethods kind size align (fixedIntegralTy fixed))
         | fixed <- fixedIntegralAll
         , let (kind, size, align) = fixedIntegralStorableLayout fixed
         ]

  fixedIntegralBuiltinInstances info classTag uniqueBase methods =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        (fixedIntegralMonoType fixed)
        (preludeTermName ("$f" <> classTag <> fixedIntegralOccurrence fixed) (uniqueBase - fromEnum fixed))
        (methods fixed)
    | fixed <- fixedIntegralAll
    ]

builtinInstanceDictionaryRefs :: [BuiltinInstanceDictionary] -> [InstanceDictionaryRef]
builtinInstanceDictionaryRefs =
  map
    ( \dictionary ->
        InstanceDictionaryRef
          { instanceRefConstraint = singleClassConstraint (builtinInstanceClass dictionary) (builtinInstanceType dictionary)
          , instanceRefVariables = []
          , instanceRefContext = []
          , instanceRefName = builtinInstanceName dictionary
          }
    )

isBuiltinInstanceConstraint :: ClassConstraint -> Bool
isBuiltinInstanceConstraint wanted =
  any (constraintMatches wanted . instanceRefConstraint) (builtinInstanceDictionaryRefs (builtinInstanceDictionaries builtinClassInfos))
    || isBuiltinStructuralInstanceConstraint wanted

overlapsBuiltinInstanceConstraint :: ClassConstraint -> Bool
overlapsBuiltinInstanceConstraint wanted =
  any (constraintsOverlap wanted . instanceRefConstraint) (builtinInstanceDictionaryRefs (builtinInstanceDictionaries builtinClassInfos))
    || overlapsBuiltinStructuralInstanceConstraint wanted

isBuiltinStructuralInstanceConstraint :: ClassConstraint -> Bool
isBuiltinStructuralInstanceConstraint wanted =
  case (classConstraintClass wanted, classConstraintArguments wanted) of
    (className, [TyList _])
      | className == builtinEqClassName -> True
    (className, [TyList _])
      | className == builtinOrdClassName -> True
    (className, [TyList _])
      | className == builtinShowClassName -> True
    (className, [TyList _])
      | className == builtinReadClassName -> True
    (className, [TyTuple fields])
      | className == builtinEqClassName && structuralTupleArity fields -> True
    (className, [TyTuple fields])
      | className == builtinOrdClassName && structuralTupleArity fields -> True
    (className, [TyTuple fields])
      | className == builtinIxClassName && structuralTupleArity fields -> True
    (className, [TyCon typeName])
      | className == builtinFunctorClassName && typeName == listTyConName -> True
    (className, [TyCon typeName])
      | className == builtinMonadClassName && typeName == listTyConName -> True
    (className, [TyCon typeName])
      | className == builtinMonadPlusClassName && typeName == listTyConName -> True
    (className, [TyApp (TyCon ptrName) _])
      | className == builtinStorableClassName && ptrName == ptrTyConName -> True
    _ -> False

overlapsBuiltinStructuralInstanceConstraint :: ClassConstraint -> Bool
overlapsBuiltinStructuralInstanceConstraint wanted =
  case (classConstraintClass wanted, classConstraintArguments wanted) of
    (className, [argument])
      | className == builtinEqClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$eq_list_overlap" (-1598))))
            || typeMayUnifyStructuralTuple argument
    (className, [argument])
      | className == builtinOrdClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$ord_list_overlap" (-1597))))
            || typeMayUnifyStructuralTuple argument
    (className, [argument])
      | className == builtinShowClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$show_list_overlap" (-1599))))
    (className, [argument])
      | className == builtinReadClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$read_list_overlap" (-1600))))
    (className, [argument])
      | className == builtinIxClassName ->
          typeMayUnifyStructuralTuple argument
    (className, [argument])
      | className == builtinFunctorClassName ->
          typesMayUnify argument (TyCon listTyConName)
    (className, [argument])
      | className == builtinMonadClassName ->
          typesMayUnify argument (TyCon listTyConName)
    (className, [argument])
      | className == builtinMonadPlusClassName ->
          typesMayUnify argument (TyCon listTyConName)
    (className, [argument])
      | className == builtinStorableClassName ->
          case argument of
            TyApp (TyCon ptrName) _ | ptrName == ptrTyConName -> True
            TyApp fn _ -> typesMayUnify fn (TyCon ptrTyConName)
            TyVar {} -> True
            TyMeta {} -> True
            _ -> False
    _ -> False

structuralTupleArity :: [a] -> Bool
structuralTupleArity fields =
  length fields >= 2 && length fields <= 15

typeMayUnifyStructuralTuple :: MonoType -> Bool
typeMayUnifyStructuralTuple = \case
  TyTuple fields -> structuralTupleArity fields
  TyVar {} -> True
  TyMeta {} -> True
  _ -> False

builtinInstanceDictionaryToCore :: Map.Map RName ClassInfo -> BuiltinInstanceDictionary -> Either TypecheckError CoreBind
builtinInstanceDictionaryToCore classes dictionary = do
  info <-
    case Map.lookup (builtinInstanceClass dictionary) classes of
      Nothing -> Left (UnsupportedCore0 ("missing built-in class info for instance `" <> renderRName (builtinInstanceClass dictionary) <> "`"))
      Just classInfo -> pure classInfo
  dictTy <- monoToCoreType Map.empty Map.empty (classDictionaryType info (builtinInstanceType dictionary))
  instanceTypeArg <- monoToCoreType Map.empty Map.empty (builtinInstanceType dictionary)
  let replacements = Map.singleton (classInfoVariable info) (builtinInstanceType dictionary)
      superclassConstraints = map (replaceConstraintTypeVars replacements) (classInfoSuperclasses info)
      instanceRefs = builtinInstanceDictionaryRefs (builtinInstanceDictionaries classes)
      env = CoreElabEnv Map.empty Map.empty classes instanceRefs []
  superclassExprs <- traverse (resolveDictionary env) superclassConstraints
  let fieldExprs = superclassExprs <> builtinInstanceMethods dictionary
  constructorTy <- classDictionaryFullConstructorCoreType info
  let constructorResultTy = foldr CTyFun dictTy (map exprType fieldExprs)
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [instanceTypeArg]
          constructorResultTy
      rhs = foldl applyValue typedConstructor fieldExprs
  pure (CoreNonRec (CoreBinder (builtinInstanceName dictionary) dictTy) rhs)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

fixedIntegralStorableLayout :: FixedIntegral -> (ForeignStorableKind, Integer, Integer)
fixedIntegralStorableLayout = \case
  FixedInt8 -> (StoreInt8, 1, 1)
  FixedInt16 -> (StoreInt16, 2, 2)
  FixedInt32 -> (StoreInt32, 4, 4)
  FixedInt64 -> (StoreInt64, 8, 8)
  FixedWord -> (StoreWord, 8, 8)
  FixedWord8 -> (StoreWord8, 1, 1)
  FixedWord16 -> (StoreWord16, 2, 2)
  FixedWord32 -> (StoreWord32, 4, 4)
  FixedWord64 -> (StoreWord64, 8, 8)

storableMethods :: ForeignStorableKind -> Integer -> Integer -> CoreType -> [CoreExpr]
storableMethods kind size align valueTy =
  [ sizeOfMethod
  , alignmentMethod
  , peekElemOffMethod
  , pokeElemOffMethod
  , peekByteOffMethod
  , pokeByteOffMethod
  , peekMethod
  , pokeMethod
  ]
 where
  b = preludeTypeVariable "b" (-1573)
  bTy = CTyVar b
  ptrValueTy = ptrTy valueTy
  ptrBTy = ptrTy bTy
  ioValueTy = ioTy valueTy
  ioUnitTy = ioTy unitTy
  intLit n = CLit (LInt n) intTy
  var name ty = CVar name ty
  lam name ty body = CLam (CoreBinder name ty) body (CTyFun ty (exprType body))
  byteOffset index =
    CPrimOp PrimMul [index, intLit size] intTy
  sizeOfArg = builtinLocalTermName "$storable_size_arg" (-6721)
  alignmentArg = builtinLocalTermName "$storable_alignment_arg" (-6722)
  elemPtr = builtinLocalTermName "$storable_elem_ptr" (-6723)
  elemIndex = builtinLocalTermName "$storable_elem_index" (-6724)
  elemValue = builtinLocalTermName "$storable_elem_value" (-6725)
  bytePtr = builtinLocalTermName "$storable_byte_ptr" (-6726)
  byteOffsetArg = builtinLocalTermName "$storable_byte_offset" (-6727)
  byteValue = builtinLocalTermName "$storable_byte_value" (-6728)
  peekPtr = builtinLocalTermName "$storable_peek_ptr" (-6729)
  pokePtr = builtinLocalTermName "$storable_poke_ptr" (-6730)
  pokeValue = builtinLocalTermName "$storable_poke_value" (-6731)
  sizeOfMethod =
    lam sizeOfArg valueTy (intLit size)
  alignmentMethod =
    lam alignmentArg valueTy (intLit align)
  peekElemOffMethod =
    lam elemPtr ptrValueTy $
      lam elemIndex intTy $
        CPrimOp (PrimPeek kind) [var elemPtr ptrValueTy, byteOffset (var elemIndex intTy)] ioValueTy
  pokeElemOffMethod =
    lam elemPtr ptrValueTy $
      lam elemIndex intTy $
        lam elemValue valueTy $
          CPrimOp (PrimPoke kind) [var elemPtr ptrValueTy, byteOffset (var elemIndex intTy), var elemValue valueTy] ioUnitTy
  peekByteOffMethod =
    CTypeLam
      [b]
      ( lam bytePtr ptrBTy $
          lam byteOffsetArg intTy $
            CPrimOp (PrimPeek kind) [var bytePtr ptrBTy, var byteOffsetArg intTy] ioValueTy
      )
      (CTyForall [b] (CTyFun ptrBTy (CTyFun intTy ioValueTy)))
  pokeByteOffMethod =
    CTypeLam
      [b]
      ( lam bytePtr ptrBTy $
          lam byteOffsetArg intTy $
            lam byteValue valueTy $
              CPrimOp (PrimPoke kind) [var bytePtr ptrBTy, var byteOffsetArg intTy, var byteValue valueTy] ioUnitTy
      )
      (CTyForall [b] (CTyFun ptrBTy (CTyFun intTy (CTyFun valueTy ioUnitTy))))
  peekMethod =
    lam peekPtr ptrValueTy (CPrimOp (PrimPeek kind) [var peekPtr ptrValueTy, intLit 0] ioValueTy)
  pokeMethod =
    lam pokePtr ptrValueTy $
      lam pokeValue valueTy $
        CPrimOp (PrimPoke kind) [var pokePtr ptrValueTy, intLit 0, var pokeValue valueTy] ioUnitTy

storablePtrDictionaryValue :: CoreElabEnv -> MonoType -> Either TypecheckError CoreExpr
storablePtrDictionaryValue env payloadTy = do
  let subst = coreElabSubst env
      metas = coreElabMetas env
      normalizedPayload = replaceMetasWithVars metas (applySubst subst payloadTy)
      ptrMono = TyApp (TyCon ptrTyConName) normalizedPayload
      constraint = singleClassConstraint builtinStorableClassName ptrMono
      info = builtinStorableInfo
  dictTy <- classConstraintCoreType subst metas constraint
  ptrCoreTy <- monoToCoreType subst metas ptrMono
  let fieldExprs = storableMethods StorePtr 8 8 ptrCoreTy
  constructorTy <- classDictionaryFullConstructorCoreType info
  let constructorResultTy = foldr CTyFun dictTy (map exprType fieldExprs)
      typedConstructor = CTypeApp (CCon (classInfoDictConstructorName info) constructorTy) [ptrCoreTy] constructorResultTy
  pure (foldl applyValue typedConstructor fieldExprs)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

intEqMethod :: CoreExpr
intEqMethod =
  binaryPrimMethod "$eq_int" (-1601) intTy boolTy PrimEq

intNotEqMethod :: CoreExpr
intNotEqMethod =
  binaryBoolMethod "$neq_int" (-1611) intTy (\lhs rhs -> boolNotCore "$neq_int_not" (-1614) (CPrimOp PrimEq [lhs, rhs] boolTy))

boolEqMethod :: CoreExpr
boolEqMethod =
  binaryPrimMethod "$eq_bool" (-1621) boolTy boolTy PrimEq

boolNotEqMethod :: CoreExpr
boolNotEqMethod =
  binaryBoolMethod "$neq_bool" (-1631) boolTy (\lhs rhs -> boolNotCore "$neq_bool_not" (-1634) (CPrimOp PrimEq [lhs, rhs] boolTy))

charEqMethod :: CoreExpr
charEqMethod =
  binaryPrimMethod "$eq_char" (-1871) charTy boolTy PrimEq

charNotEqMethod :: CoreExpr
charNotEqMethod =
  binaryBoolMethod "$neq_char" (-1881) charTy (\lhs rhs -> boolNotCore "$neq_char_not" (-1884) (CPrimOp PrimEq [lhs, rhs] boolTy))

ioErrorTypeEqMethod :: CoreExpr
ioErrorTypeEqMethod =
  binaryBoolMethod "$eq_io_error_type" (-2801) ioErrorTypeTy ioErrorTypeEqCore

ioErrorTypeNotEqMethod :: CoreExpr
ioErrorTypeNotEqMethod =
  binaryBoolMethod "$neq_io_error_type" (-2811) ioErrorTypeTy (\lhs rhs -> boolNotCore "$neq_io_error_type_not" (-2814) (ioErrorTypeEqCore lhs rhs))

ioErrorTypeEqCore :: CoreExpr -> CoreExpr -> CoreExpr
ioErrorTypeEqCore lhs rhs =
  CCase lhs (CoreBinder lhsCase ioErrorTypeTy) lhsAlts boolTy
 where
  lhsCase = builtinLocalTermName "$eq_io_error_type_lhs_case" (-2820)
  lhsAlts =
    [ CoreAlt (ConstructorAlt constructorName) [] (rhsCase constructorName index)
    | (index, constructorName) <- zip [0 :: Int ..] ioErrorTypeConstructors
    ]
  rhsCase constructorName index =
    CCase
      rhs
      (CoreBinder (builtinLocalTermName ("$eq_io_error_type_rhs_case" <> renderInt index) (-2821 - index)) ioErrorTypeTy)
      [ CoreAlt (ConstructorAlt constructorName) [] (CCon trueDataConName boolTy)
      , CoreAlt DefaultAlt [] (CCon falseDataConName boolTy)
      ]
      boolTy

ioErrorTypeConstructors :: [RName]
ioErrorTypeConstructors =
  [ ioErrorAlreadyExistsTypeDataConName
  , ioErrorDoesNotExistTypeDataConName
  , ioErrorAlreadyInUseTypeDataConName
  , ioErrorFullTypeDataConName
  , ioErrorEOFTypeDataConName
  , ioErrorIllegalOperationTypeDataConName
  , ioErrorPermissionTypeDataConName
  , ioErrorUserTypeDataConName
  ]

intCompareMethod :: CoreExpr
intCompareMethod =
  binaryMethod "$compare_int" (-1641) intTy orderingTy $ \lhs rhs ->
    boolCaseCore
      "$compare_int_lt"
      (-1644)
      (CPrimOp PrimLt [lhs, rhs] boolTy)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      ( boolCaseCore
          "$compare_int_gt"
          (-1645)
          (CPrimOp PrimLt [rhs, lhs] boolTy)
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingEQDataConName orderingTy)
      )

intLtMethod :: CoreExpr
intLtMethod =
  binaryPrimMethod "$lt_int" (-1651) intTy boolTy PrimLt

intLeMethod :: CoreExpr
intLeMethod =
  binaryBoolMethod "$le_int" (-1661) intTy (\lhs rhs -> boolNotCore "$le_int_not" (-1664) (CPrimOp PrimLt [rhs, lhs] boolTy))

intGtMethod :: CoreExpr
intGtMethod =
  binaryBoolMethod "$gt_int" (-1671) intTy (\lhs rhs -> CPrimOp PrimLt [rhs, lhs] boolTy)

intGeMethod :: CoreExpr
intGeMethod =
  binaryBoolMethod "$ge_int" (-1681) intTy (\lhs rhs -> boolNotCore "$ge_int_not" (-1684) (CPrimOp PrimLt [lhs, rhs] boolTy))

intMaxMethod :: CoreExpr
intMaxMethod =
  binaryMethod "$max_int" (-1691) intTy intTy $ \lhs rhs ->
    boolCaseCore "$max_int_case" (-1694) (CPrimOp PrimLt [lhs, rhs] boolTy) intTy rhs lhs

intMinMethod :: CoreExpr
intMinMethod =
  binaryMethod "$min_int" (-1701) intTy intTy $ \lhs rhs ->
    boolCaseCore "$min_int_case" (-1704) (CPrimOp PrimLt [lhs, rhs] boolTy) intTy lhs rhs

boolCompareMethod :: CoreExpr
boolCompareMethod =
  binaryMethod "$compare_bool" (-1711) boolTy orderingTy $ \lhs rhs ->
    boolCaseCore
      "$compare_bool_eq"
      (-1714)
      (CPrimOp PrimEq [lhs, rhs] boolTy)
      orderingTy
      (CCon orderingEQDataConName orderingTy)
      ( boolCaseCore
          "$compare_bool_lt"
          (-1715)
          lhs
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingLTDataConName orderingTy)
      )

boolLtMethod :: CoreExpr
boolLtMethod =
  binaryMethod "$lt_bool" (-1721) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$lt_bool_case" (-1724) lhs boolTy (CCon falseDataConName boolTy) rhs

boolLeMethod :: CoreExpr
boolLeMethod =
  binaryMethod "$le_bool" (-1731) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$le_bool_case" (-1734) lhs boolTy rhs (CCon trueDataConName boolTy)

boolGtMethod :: CoreExpr
boolGtMethod =
  binaryMethod "$gt_bool" (-1741) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$gt_bool_case" (-1744) lhs boolTy (boolNotCore "$gt_bool_not" (-1745) rhs) (CCon falseDataConName boolTy)

boolGeMethod :: CoreExpr
boolGeMethod =
  binaryMethod "$ge_bool" (-1751) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$ge_bool_case" (-1754) lhs boolTy (CCon trueDataConName boolTy) (boolNotCore "$ge_bool_not" (-1755) rhs)

boolMaxMethod :: CoreExpr
boolMaxMethod =
  binaryMethod "$max_bool" (-1761) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$max_bool_case" (-1764) lhs boolTy (CCon trueDataConName boolTy) rhs

boolMinMethod :: CoreExpr
boolMinMethod =
  binaryMethod "$min_bool" (-1771) boolTy boolTy $ \lhs rhs ->
    boolCaseCore "$min_bool_case" (-1774) lhs boolTy rhs (CCon falseDataConName boolTy)

charCompareMethod :: CoreExpr
charCompareMethod =
  binaryMethod "$compare_char" (-1901) charTy orderingTy $ \lhs rhs ->
    boolCaseCore
      "$compare_char_lt"
      (-1904)
      (charLtCore lhs rhs)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      ( boolCaseCore
          "$compare_char_gt"
          (-1905)
          (charLtCore rhs lhs)
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingEQDataConName orderingTy)
      )

charLtMethod :: CoreExpr
charLtMethod =
  binaryBoolMethod "$lt_char" (-1911) charTy charLtCore

charLeMethod :: CoreExpr
charLeMethod =
  binaryBoolMethod "$le_char" (-1921) charTy (\lhs rhs -> boolNotCore "$le_char_not" (-1924) (charLtCore rhs lhs))

charGtMethod :: CoreExpr
charGtMethod =
  binaryBoolMethod "$gt_char" (-1931) charTy (\lhs rhs -> charLtCore rhs lhs)

charGeMethod :: CoreExpr
charGeMethod =
  binaryBoolMethod "$ge_char" (-1941) charTy (\lhs rhs -> boolNotCore "$ge_char_not" (-1944) (charLtCore lhs rhs))

charMaxMethod :: CoreExpr
charMaxMethod =
  binaryMethod "$max_char" (-1951) charTy charTy $ \lhs rhs ->
    boolCaseCore "$max_char_case" (-1954) (charLtCore lhs rhs) charTy rhs lhs

charMinMethod :: CoreExpr
charMinMethod =
  binaryMethod "$min_char" (-1961) charTy charTy $ \lhs rhs ->
    boolCaseCore "$min_char_case" (-1964) (charLtCore lhs rhs) charTy lhs rhs

charLtCore :: CoreExpr -> CoreExpr -> CoreExpr
charLtCore lhs rhs =
  CPrimOp
    PrimLt
    [ CPrimOp PrimCharToInt [lhs] intTy
    , CPrimOp PrimCharToInt [rhs] intTy
    ]
    boolTy

unitEqMethod :: CoreExpr
unitEqMethod =
  binaryMethod "$eq_unit" (-1991) unitTy boolTy (\_ _ -> CCon trueDataConName boolTy)

unitNotEqMethod :: CoreExpr
unitNotEqMethod =
  binaryMethod "$neq_unit" (-1992) unitTy boolTy (\_ _ -> CCon falseDataConName boolTy)

orderingEqMethod :: CoreExpr
orderingEqMethod =
  binaryMethod "$eq_ordering" (-1993) orderingTy boolTy $ \lhs rhs ->
    CPrimOp PrimEq [orderingOrdinalCore "$eq_ordering_lhs" (-19931) lhs, orderingOrdinalCore "$eq_ordering_rhs" (-19932) rhs] boolTy

orderingNotEqMethod :: CoreExpr
orderingNotEqMethod =
  binaryMethod "$neq_ordering" (-1994) orderingTy boolTy $ \lhs rhs ->
    boolNotCore
      "$neq_ordering_not"
      (-19941)
      (CPrimOp PrimEq [orderingOrdinalCore "$neq_ordering_lhs" (-19942) lhs, orderingOrdinalCore "$neq_ordering_rhs" (-19943) rhs] boolTy)

orderingCompareMethod :: CoreExpr
orderingCompareMethod =
  binaryMethod "$compare_ordering" (-1995) orderingTy orderingTy $ \lhs rhs ->
    intCompareCore "$compare_ordering" (-19951) (orderingOrdinalCore "$compare_ordering_lhs" (-19952) lhs) (orderingOrdinalCore "$compare_ordering_rhs" (-19953) rhs)

orderingLtMethod :: CoreExpr
orderingLtMethod =
  binaryBoolMethod "$lt_ordering" (-1996) orderingTy $ \lhs rhs ->
    intLt (orderingOrdinalCore "$lt_ordering_lhs" (-19961) lhs) (orderingOrdinalCore "$lt_ordering_rhs" (-19962) rhs)

orderingLeMethod :: CoreExpr
orderingLeMethod =
  binaryBoolMethod "$le_ordering" (-1997) orderingTy $ \lhs rhs ->
    intLeCore "$le_ordering" (-19971) (orderingOrdinalCore "$le_ordering_lhs" (-19972) lhs) (orderingOrdinalCore "$le_ordering_rhs" (-19973) rhs)

orderingGtMethod :: CoreExpr
orderingGtMethod =
  binaryBoolMethod "$gt_ordering" (-1998) orderingTy $ \lhs rhs ->
    intLt (orderingOrdinalCore "$gt_ordering_rhs" (-19981) rhs) (orderingOrdinalCore "$gt_ordering_lhs" (-19982) lhs)

orderingGeMethod :: CoreExpr
orderingGeMethod =
  binaryBoolMethod "$ge_ordering" (-1999) orderingTy $ \lhs rhs ->
    intLeCore "$ge_ordering" (-19991) (orderingOrdinalCore "$ge_ordering_rhs" (-19992) rhs) (orderingOrdinalCore "$ge_ordering_lhs" (-19993) lhs)

orderingMaxMethod :: CoreExpr
orderingMaxMethod =
  binaryMethod "$max_ordering" (-2001) orderingTy orderingTy $ \lhs rhs ->
    boolCaseCore "$max_ordering_case" (-20011) (intLt (orderingOrdinalCore "$max_ordering_lhs" (-20012) lhs) (orderingOrdinalCore "$max_ordering_rhs" (-20013) rhs)) orderingTy rhs lhs

orderingMinMethod :: CoreExpr
orderingMinMethod =
  binaryMethod "$min_ordering" (-2002) orderingTy orderingTy $ \lhs rhs ->
    boolCaseCore "$min_ordering_case" (-20021) (intLt (orderingOrdinalCore "$min_ordering_lhs" (-20022) lhs) (orderingOrdinalCore "$min_ordering_rhs" (-20023) rhs)) orderingTy lhs rhs

exitCodeEqMethod :: CoreExpr
exitCodeEqMethod =
  binaryBoolMethod "$eq_exit_code" (-2021) exitCodeTy exitCodeEqCore

exitCodeNotEqMethod :: CoreExpr
exitCodeNotEqMethod =
  binaryBoolMethod "$neq_exit_code" (-2022) exitCodeTy $ \lhs rhs ->
    boolNotCore "$neq_exit_code_not" (-20221) (exitCodeEqCore lhs rhs)

exitCodeCompareMethod :: CoreExpr
exitCodeCompareMethod =
  binaryMethod "$compare_exit_code" (-2023) exitCodeTy orderingTy exitCodeCompareCore

exitCodeLtMethod :: CoreExpr
exitCodeLtMethod =
  binaryBoolMethod "$lt_exit_code" (-2024) exitCodeTy $ \lhs rhs ->
    orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingLTDataConName orderingTy)

exitCodeLeMethod :: CoreExpr
exitCodeLeMethod =
  binaryBoolMethod "$le_exit_code" (-2025) exitCodeTy $ \lhs rhs ->
    boolNotCore "$le_exit_code_not" (-20251) (orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingGTDataConName orderingTy))

exitCodeGtMethod :: CoreExpr
exitCodeGtMethod =
  binaryBoolMethod "$gt_exit_code" (-2026) exitCodeTy $ \lhs rhs ->
    orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingGTDataConName orderingTy)

exitCodeGeMethod :: CoreExpr
exitCodeGeMethod =
  binaryBoolMethod "$ge_exit_code" (-2027) exitCodeTy $ \lhs rhs ->
    boolNotCore "$ge_exit_code_not" (-20271) (orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingLTDataConName orderingTy))

exitCodeMaxMethod :: CoreExpr
exitCodeMaxMethod =
  binaryMethod "$max_exit_code" (-2028) exitCodeTy exitCodeTy $ \lhs rhs ->
    boolCaseCore "$max_exit_code_case" (-20281) (orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingLTDataConName orderingTy)) exitCodeTy rhs lhs

exitCodeMinMethod :: CoreExpr
exitCodeMinMethod =
  binaryMethod "$min_exit_code" (-2029) exitCodeTy exitCodeTy $ \lhs rhs ->
    boolCaseCore "$min_exit_code_case" (-20291) (orderingEqualCore (exitCodeCompareCore lhs rhs) (CCon orderingGTDataConName orderingTy)) exitCodeTy rhs lhs

orderingEqualCore :: CoreExpr -> CoreExpr -> CoreExpr
orderingEqualCore lhs rhs =
  CPrimOp
    PrimEq
    [ orderingOrdinalCore "$ordering_equal_lhs" (-20300) lhs
    , orderingOrdinalCore "$ordering_equal_rhs" (-20301) rhs
    ]
    boolTy

exitCodeEqCore :: CoreExpr -> CoreExpr -> CoreExpr
exitCodeEqCore lhs rhs =
  CCase lhs (CoreBinder lhsCase exitCodeTy) lhsAlts boolTy
 where
  lhsCase = builtinLocalTermName "$eq_exit_code_lhs_case" (-2030)
  rhsCaseSuccess = builtinLocalTermName "$eq_exit_code_rhs_success_case" (-2031)
  rhsCaseFailure = builtinLocalTermName "$eq_exit_code_rhs_failure_case" (-2032)
  lhsFailureCode = builtinLocalTermName "$eq_exit_code_lhs_failure" (-2033)
  rhsFailureCode = builtinLocalTermName "$eq_exit_code_rhs_failure" (-2034)
  lhsAlts =
    [ CoreAlt
        (ConstructorAlt exitSuccessDataConName)
        []
        ( CCase
            rhs
            (CoreBinder rhsCaseSuccess exitCodeTy)
            [ CoreAlt (ConstructorAlt exitSuccessDataConName) [] (CCon trueDataConName boolTy)
            , CoreAlt (ConstructorAlt exitFailureDataConName) [CoreBinder rhsFailureCode intTy] (CCon falseDataConName boolTy)
            ]
            boolTy
        )
    , CoreAlt
        (ConstructorAlt exitFailureDataConName)
        [CoreBinder lhsFailureCode intTy]
        ( CCase
            rhs
            (CoreBinder rhsCaseFailure exitCodeTy)
            [ CoreAlt (ConstructorAlt exitSuccessDataConName) [] (CCon falseDataConName boolTy)
            , CoreAlt
                (ConstructorAlt exitFailureDataConName)
                [CoreBinder rhsFailureCode intTy]
                (CPrimOp PrimEq [CVar lhsFailureCode intTy, CVar rhsFailureCode intTy] boolTy)
            ]
            boolTy
        )
    ]

exitCodeCompareCore :: CoreExpr -> CoreExpr -> CoreExpr
exitCodeCompareCore lhs rhs =
  CCase lhs (CoreBinder lhsCase exitCodeTy) lhsAlts orderingTy
 where
  lhsCase = builtinLocalTermName "$compare_exit_code_lhs_case" (-2040)
  rhsCaseSuccess = builtinLocalTermName "$compare_exit_code_rhs_success_case" (-2041)
  rhsCaseFailure = builtinLocalTermName "$compare_exit_code_rhs_failure_case" (-2042)
  lhsFailureCode = builtinLocalTermName "$compare_exit_code_lhs_failure" (-2043)
  rhsFailureCode = builtinLocalTermName "$compare_exit_code_rhs_failure" (-2044)
  lhsAlts =
    [ CoreAlt
        (ConstructorAlt exitSuccessDataConName)
        []
        ( CCase
            rhs
            (CoreBinder rhsCaseSuccess exitCodeTy)
            [ CoreAlt (ConstructorAlt exitSuccessDataConName) [] (CCon orderingEQDataConName orderingTy)
            , CoreAlt (ConstructorAlt exitFailureDataConName) [CoreBinder rhsFailureCode intTy] (CCon orderingLTDataConName orderingTy)
            ]
            orderingTy
        )
    , CoreAlt
        (ConstructorAlt exitFailureDataConName)
        [CoreBinder lhsFailureCode intTy]
        ( CCase
            rhs
            (CoreBinder rhsCaseFailure exitCodeTy)
            [ CoreAlt (ConstructorAlt exitSuccessDataConName) [] (CCon orderingGTDataConName orderingTy)
            , CoreAlt
                (ConstructorAlt exitFailureDataConName)
                [CoreBinder rhsFailureCode intTy]
                (intCompareCore "$compare_exit_code_failure" (-2045) (CVar lhsFailureCode intTy) (CVar rhsFailureCode intTy))
            ]
            orderingTy
        )
    ]

unitCompareMethod :: CoreExpr
unitCompareMethod =
  binaryMethod "$compare_unit" (-2003) unitTy orderingTy (\_ _ -> CCon orderingEQDataConName orderingTy)

unitLtMethod :: CoreExpr
unitLtMethod =
  binaryMethod "$lt_unit" (-2004) unitTy boolTy (\_ _ -> CCon falseDataConName boolTy)

unitLeMethod :: CoreExpr
unitLeMethod =
  binaryMethod "$le_unit" (-2005) unitTy boolTy (\_ _ -> CCon trueDataConName boolTy)

unitGtMethod :: CoreExpr
unitGtMethod =
  binaryMethod "$gt_unit" (-2006) unitTy boolTy (\_ _ -> CCon falseDataConName boolTy)

unitGeMethod :: CoreExpr
unitGeMethod =
  binaryMethod "$ge_unit" (-2007) unitTy boolTy (\_ _ -> CCon trueDataConName boolTy)

unitMaxMethod :: CoreExpr
unitMaxMethod =
  binaryMethod "$max_unit" (-2008) unitTy unitTy (\lhs _ -> lhs)

unitMinMethod :: CoreExpr
unitMinMethod =
  binaryMethod "$min_unit" (-2009) unitTy unitTy (\lhs _ -> lhs)

orderingOrdinalCore :: Text -> Int -> CoreExpr -> CoreExpr
orderingOrdinalCore occurrence unique value =
  orderingCaseCore
    occurrence
    unique
    value
    intTy
    (CLit (LInt 0) intTy)
    (CLit (LInt 1) intTy)
    (CLit (LInt 2) intTy)

intCompareCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
intCompareCore occurrence unique lhs rhs =
  boolCaseCore
    (occurrence <> "_lt")
    unique
    (intLt lhs rhs)
    orderingTy
    (CCon orderingLTDataConName orderingTy)
    ( boolCaseCore
        (occurrence <> "_gt")
        (unique - 1)
        (intLt rhs lhs)
        orderingTy
        (CCon orderingGTDataConName orderingTy)
        (CCon orderingEQDataConName orderingTy)
    )

intLeCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
intLeCore occurrence unique lhs rhs =
  boolNotCore (occurrence <> "_not_gt") unique (intLt rhs lhs)

ixRangeIntMethod, ixIndexIntMethod, ixInRangeIntMethod, ixRangeSizeIntMethod :: CoreExpr
ixRangeIntMethod =
  ixRangeDirectMethod "$ix_range_int" (-3630) intTy intListCoreType enumFromToIntName enumFromToIntCoreType
ixIndexIntMethod =
  ixIndexOrdinalMethod "$ix_index_int" (-3640) intTy id
ixInRangeIntMethod =
  ixInRangeOrdinalMethod "$ix_in_range_int" (-3650) intTy id
ixRangeSizeIntMethod =
  ixRangeSizeOrdinalMethod "$ix_range_size_int" (-3660) intTy id

ixRangeCharMethod, ixIndexCharMethod, ixInRangeCharMethod, ixRangeSizeCharMethod :: CoreExpr
ixRangeCharMethod =
  ixRangeDirectMethod "$ix_range_char" (-3670) charTy charListCoreType enumFromToCharName enumFromToCharCoreType
ixIndexCharMethod =
  ixIndexOrdinalMethod "$ix_index_char" (-3680) charTy charToIntCore
ixInRangeCharMethod =
  ixInRangeOrdinalMethod "$ix_in_range_char" (-3690) charTy charToIntCore
ixRangeSizeCharMethod =
  ixRangeSizeOrdinalMethod "$ix_range_size_char" (-3700) charTy charToIntCore

ixRangeBoolMethod, ixIndexBoolMethod, ixInRangeBoolMethod, ixRangeSizeBoolMethod :: CoreExpr
ixRangeBoolMethod =
  ixRangeMappedOrdinalMethod "$ix_range_bool" (-3710) boolTy boolOrdinalCore intToBoolCore
ixIndexBoolMethod =
  ixIndexOrdinalMethod "$ix_index_bool" (-3720) boolTy boolOrdinalCore
ixInRangeBoolMethod =
  ixInRangeOrdinalMethod "$ix_in_range_bool" (-3730) boolTy boolOrdinalCore
ixRangeSizeBoolMethod =
  ixRangeSizeOrdinalMethod "$ix_range_size_bool" (-3740) boolTy boolOrdinalCore

ixRangeOrderingMethod, ixIndexOrderingMethod, ixInRangeOrderingMethod, ixRangeSizeOrderingMethod :: CoreExpr
ixRangeOrderingMethod =
  ixRangeMappedOrdinalMethod "$ix_range_ordering" (-3750) orderingTy (orderingOrdinalCore "$ix_range_ordering_ord" (-3755)) (intToOrderingCore "$ix_range_ordering_from" (-3756))
ixIndexOrderingMethod =
  ixIndexOrdinalMethod "$ix_index_ordering" (-3760) orderingTy (orderingOrdinalCore "$ix_index_ordering_ord" (-3765))
ixInRangeOrderingMethod =
  ixInRangeOrdinalMethod "$ix_in_range_ordering" (-3770) orderingTy (orderingOrdinalCore "$ix_in_range_ordering_ord" (-3775))
ixRangeSizeOrderingMethod =
  ixRangeSizeOrdinalMethod "$ix_range_size_ordering" (-3780) orderingTy (orderingOrdinalCore "$ix_range_size_ordering_ord" (-3785))

ixRangeUnitMethod, ixIndexUnitMethod, ixInRangeUnitMethod, ixRangeSizeUnitMethod :: CoreExpr
ixRangeUnitMethod =
  ixBoundsCaseMethod "$ix_range_unit" (-3790) unitTy (CTyList unitTy) (\_ _ -> consCore unitTy (CCon unitDataConName unitTy) (nilCore unitTy))
ixIndexUnitMethod =
  ixIndexMethod "$ix_index_unit" (-3800) unitTy (\_ _ _ -> zeroInt)
ixInRangeUnitMethod =
  ixIndexMethod "$ix_in_range_unit" (-3810) unitTy (\_ _ _ -> CCon trueDataConName boolTy)
ixRangeSizeUnitMethod =
  ixBoundsCaseMethod "$ix_range_size_unit" (-3820) unitTy intTy (\_ _ -> oneInt)

ixRangeDirectMethod :: Text -> Int -> CoreType -> CoreType -> RName -> CoreType -> CoreExpr
ixRangeDirectMethod occurrence unique valueTy listTy functionName functionTy =
  ixBoundsCaseMethod occurrence unique valueTy listTy $ \lower upper ->
    applyCore (applyCore (CVar functionName functionTy) lower (CTyFun valueTy listTy)) upper listTy

ixRangeMappedOrdinalMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> (CoreExpr -> CoreExpr) -> CoreExpr
ixRangeMappedOrdinalMethod occurrence unique valueTy toOrdinal fromOrdinal =
  ixBoundsCaseMethod occurrence unique valueTy (CTyList valueTy) $ \lower upper ->
    mapIntListCore
      (occurrence <> "_map")
      (unique - 4)
      valueTy
      fromOrdinal
      (applyCore (applyCore (CVar enumFromToIntName enumFromToIntCoreType) (toOrdinal lower) (CTyFun intTy intListCoreType)) (toOrdinal upper) intListCoreType)

ixIndexOrdinalMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
ixIndexOrdinalMethod occurrence unique valueTy toOrdinal =
  ixIndexMethod occurrence unique valueTy $ \lower upper value ->
    let lowerOrdinal = toOrdinal lower
        upperOrdinal = toOrdinal upper
        valueOrdinal = toOrdinal value
        inBounds = ixInRangeOrdinalCore (occurrence <> "_check") (unique - 4) lowerOrdinal upperOrdinal valueOrdinal
     in boolCaseCore
          (occurrence <> "_case")
          (unique - 5)
          inBounds
          intTy
          (intSub valueOrdinal lowerOrdinal)
          (bottomCore (occurrence <> "_bottom") (unique - 6) intTy)

ixInRangeOrdinalMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
ixInRangeOrdinalMethod occurrence unique valueTy toOrdinal =
  ixIndexMethod occurrence unique valueTy $ \lower upper value ->
    ixInRangeOrdinalCore (occurrence <> "_check") (unique - 4) (toOrdinal lower) (toOrdinal upper) (toOrdinal value)

ixRangeSizeOrdinalMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
ixRangeSizeOrdinalMethod occurrence unique valueTy toOrdinal =
  ixBoundsCaseMethod occurrence unique valueTy intTy $ \lower upper ->
    let lowerOrdinal = toOrdinal lower
        upperOrdinal = toOrdinal upper
     in boolCaseCore
          (occurrence <> "_case")
          (unique - 4)
          (intLeCore (occurrence <> "_le") (unique - 5) lowerOrdinal upperOrdinal)
          intTy
          (intAdd (intSub upperOrdinal lowerOrdinal) oneInt)
          zeroInt

ixInRangeOrdinalCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
ixInRangeOrdinalCore occurrence unique lower upper value =
  boolAndCore
    (occurrence <> "_and")
    unique
    (intLeCore (occurrence <> "_lower") (unique - 1) lower value)
    (intLeCore (occurrence <> "_upper") (unique - 2) value upper)

ixBoundsCaseMethod :: Text -> Int -> CoreType -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ixBoundsCaseMethod occurrence unique valueTy resultTy body =
  CLam (CoreBinder boundsName boundsTy) boundsCase (CTyFun boundsTy resultTy)
 where
  boundsTy = CTyTuple [valueTy, valueTy]
  boundsName = builtinLocalTermName (occurrence <> "_bounds") unique
  caseName = builtinLocalTermName (occurrence <> "_case_bounds") (unique - 1)
  lowerName = builtinLocalTermName (occurrence <> "_lower") (unique - 2)
  upperName = builtinLocalTermName (occurrence <> "_upper") (unique - 3)
  boundsCase =
    CCase
      (CVar boundsName boundsTy)
      (CoreBinder caseName boundsTy)
      [ CoreAlt
          (ConstructorAlt (tupleDataConName 2))
          [CoreBinder lowerName valueTy, CoreBinder upperName valueTy]
          (body (CVar lowerName valueTy) (CVar upperName valueTy))
      ]
      resultTy

ixIndexMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ixIndexMethod occurrence unique valueTy body =
  CLam (CoreBinder boundsName boundsTy) (CLam (CoreBinder valueName valueTy) boundsCase (CTyFun valueTy (exprType boundsCase))) (CTyFun boundsTy (CTyFun valueTy (exprType boundsCase)))
 where
  boundsTy = CTyTuple [valueTy, valueTy]
  boundsName = builtinLocalTermName (occurrence <> "_bounds") unique
  valueName = builtinLocalTermName (occurrence <> "_value") (unique - 1)
  caseName = builtinLocalTermName (occurrence <> "_case_bounds") (unique - 2)
  lowerName = builtinLocalTermName (occurrence <> "_lower") (unique - 3)
  upperName = builtinLocalTermName (occurrence <> "_upper") (unique - 4)
  value = CVar valueName valueTy
  boundsCase =
    CCase
      (CVar boundsName boundsTy)
      (CoreBinder caseName boundsTy)
      [ CoreAlt
          (ConstructorAlt (tupleDataConName 2))
          [CoreBinder lowerName valueTy, CoreBinder upperName valueTy]
          (body (CVar lowerName valueTy) (CVar upperName valueTy) value)
      ]
      (exprType (body (CVar lowerName valueTy) (CVar upperName valueTy) value))

boolOrdinalCore :: CoreExpr -> CoreExpr
boolOrdinalCore value =
  boolCaseCore "$bool_ordinal" (-3830) value intTy oneInt zeroInt

intToBoolCore :: CoreExpr -> CoreExpr
intToBoolCore value =
  CCase
    value
    (CoreBinder (builtinLocalTermName "$int_to_bool" (-3831)) intTy)
    [ CoreAlt (LiteralAlt (LInt 0)) [] (CCon falseDataConName boolTy)
    , CoreAlt (LiteralAlt (LInt 1)) [] (CCon trueDataConName boolTy)
    , CoreAlt DefaultAlt [] (bottomCore "$int_to_bool_bottom" (-3832) boolTy)
    ]
    boolTy

intToOrderingCore :: Text -> Int -> CoreExpr -> CoreExpr
intToOrderingCore occurrence unique value =
  CCase
    value
    (CoreBinder (builtinLocalTermName occurrence unique) intTy)
    [ CoreAlt (LiteralAlt (LInt 0)) [] (CCon orderingLTDataConName orderingTy)
    , CoreAlt (LiteralAlt (LInt 1)) [] (CCon orderingEQDataConName orderingTy)
    , CoreAlt (LiteralAlt (LInt 2)) [] (CCon orderingGTDataConName orderingTy)
    , CoreAlt DefaultAlt [] (bottomCore (occurrence <> "_bottom") (unique - 1) orderingTy)
    ]
    orderingTy

mapIntListCore :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr -> CoreExpr
mapIntListCore occurrence unique valueTy mapper intList =
  applyCore (applyCore mapFunction mapperExpr (CTyFun intListCoreType resultListTy)) intList resultListTy
 where
  resultListTy = CTyList valueTy
  argumentName = builtinLocalTermName (occurrence <> "_arg") unique
  mapperExpr = CLam (CoreBinder argumentName intTy) (mapper (CVar argumentName intTy)) (CTyFun intTy valueTy)
  mapFunction =
    CTypeApp
      (CVar derivedMapName mapPreludeCoreType)
      [intTy, valueTy]
      (CTyFun (CTyFun intTy valueTy) (CTyFun intListCoreType resultListTy))

mapPreludeCoreType :: CoreType
mapPreludeCoreType =
  CTyForall [a, b] (CTyFun (CTyFun aTy bTy) (CTyFun (CTyList aTy) (CTyList bTy)))
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b

bottomCore :: Text -> Int -> CoreType -> CoreExpr
bottomCore occurrence unique resultTy =
  CCase (CCon falseDataConName boolTy) (CoreBinder (builtinLocalTermName occurrence unique) boolTy) [] resultTy

intAddMethod :: CoreExpr
intAddMethod =
  binaryPrimMethod "$add_int" (-1781) intTy intTy PrimAdd

intSubMethod :: CoreExpr
intSubMethod =
  binaryPrimMethod "$sub_int" (-1791) intTy intTy PrimSub

intMulMethod :: CoreExpr
intMulMethod =
  binaryPrimMethod "$mul_int" (-1801) intTy intTy PrimMul

intNegateMethod :: CoreExpr
intNegateMethod =
  unaryPrimMethod "$negate_int" (-1811) intTy intTy PrimNegate

intAbsMethod :: CoreExpr
intAbsMethod =
  unaryMethod "$abs_int" (-1821) intTy intTy $ \value ->
    boolCaseCore
      "$abs_int_case"
      (-1823)
      (CPrimOp PrimLt [value, CLit (LInt 0) intTy] boolTy)
      intTy
      (CPrimOp PrimNegate [value] intTy)
      value

intSignumMethod :: CoreExpr
intSignumMethod =
  unaryMethod "$signum_int" (-1831) intTy intTy $ \value ->
    boolCaseCore
      "$signum_int_neg"
      (-1833)
      (CPrimOp PrimLt [value, CLit (LInt 0) intTy] boolTy)
      intTy
      (CLit (LInt (-1)) intTy)
      ( boolCaseCore
          "$signum_int_zero"
          (-1834)
          (CPrimOp PrimEq [value, CLit (LInt 0) intTy] boolTy)
          intTy
          (CLit (LInt 0) intTy)
          (CLit (LInt 1) intTy)
      )

intFromIntegerMethod :: CoreExpr
intFromIntegerMethod =
  unaryMethod "$fromInteger_int" (-1861) intTy intTy id

intToRationalMethod :: CoreExpr
intToRationalMethod =
  unaryMethod "$toRational_int" (-1862) intTy rationalCoreType $ \value ->
    ratioIntCore value oneInt

intQuotMethod :: CoreExpr
intQuotMethod =
  binaryPrimMethod "$quot_int" (-1863) intTy intTy PrimDiv

intRemMethod :: CoreExpr
intRemMethod =
  binaryPrimMethod "$rem_int" (-1864) intTy intTy PrimRem

intDivMethod :: CoreExpr
intDivMethod =
  binaryMethod "$div_int" (-1865) intTy intTy (intDivCoreWith "$div_int" (-18650))

intModMethod :: CoreExpr
intModMethod =
  binaryMethod "$mod_int" (-1866) intTy intTy (intModCoreWith "$mod_int" (-18660))

intQuotRemMethod :: CoreExpr
intQuotRemMethod =
  binaryMethod "$quotRem_int" (-1867) intTy intPairCoreType $ \lhs rhs ->
    tuple2IntCore (intQuot lhs rhs) (intRem lhs rhs)

intDivModMethod :: CoreExpr
intDivModMethod =
  binaryMethod "$divMod_int" (-1868) intTy intPairCoreType $ \lhs rhs ->
    letCore dName intTy (intDivCoreWith "$divMod_int" (-18680) lhs rhs) $
      letCore mName intTy (intSub lhs (intMul dVar rhs)) $
        tuple2IntCore dVar mVar
 where
  dName = builtinLocalTermName "$divMod_int_d" (-18688)
  mName = builtinLocalTermName "$divMod_int_m" (-18689)
  dVar = CVar dName intTy
  mVar = CVar mName intTy

intToIntegerMethod :: CoreExpr
intToIntegerMethod =
  unaryMethod "$toInteger_int" (-1869) intTy intTy id

ratioEqMethod :: CoreExpr
ratioEqMethod =
  ratioBinaryBoolMethod "$eq_ratio_int" (-18700) ratioEqCore

ratioNotEqMethod :: CoreExpr
ratioNotEqMethod =
  ratioBinaryBoolMethod "$neq_ratio_int" (-18710) (\lhs rhs -> boolNotCore "$neq_ratio_int_not" (-18714) (ratioEqCore lhs rhs))

ratioCompareMethod :: CoreExpr
ratioCompareMethod =
  ratioBinaryMethod "$compare_ratio_int" (-18720) orderingTy $ \lhs rhs ->
    boolCaseCore
      "$compare_ratio_int_lt"
      (-18724)
      (ratioLtCore lhs rhs)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      ( boolCaseCore
          "$compare_ratio_int_gt"
          (-18725)
          (ratioLtCore rhs lhs)
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingEQDataConName orderingTy)
      )

ratioLtMethod :: CoreExpr
ratioLtMethod =
  ratioBinaryBoolMethod "$lt_ratio_int" (-18730) ratioLtCore

ratioLeMethod :: CoreExpr
ratioLeMethod =
  ratioBinaryBoolMethod "$le_ratio_int" (-18740) (\lhs rhs -> boolNotCore "$le_ratio_int_not" (-18744) (ratioLtCore rhs lhs))

ratioGtMethod :: CoreExpr
ratioGtMethod =
  ratioBinaryBoolMethod "$gt_ratio_int" (-18750) (\lhs rhs -> ratioLtCore rhs lhs)

ratioGeMethod :: CoreExpr
ratioGeMethod =
  ratioBinaryBoolMethod "$ge_ratio_int" (-18760) (\lhs rhs -> boolNotCore "$ge_ratio_int_not" (-18764) (ratioLtCore lhs rhs))

ratioMaxMethod :: CoreExpr
ratioMaxMethod =
  ratioBinaryMethod "$max_ratio_int" (-18770) rationalCoreType $ \lhs rhs ->
    boolCaseCore "$max_ratio_int_case" (-18774) (ratioLtCore lhs rhs) rationalCoreType rhs lhs

ratioMinMethod :: CoreExpr
ratioMinMethod =
  ratioBinaryMethod "$min_ratio_int" (-18780) rationalCoreType $ \lhs rhs ->
    boolCaseCore "$min_ratio_int_case" (-18784) (ratioLtCore lhs rhs) rationalCoreType lhs rhs

ratioAddMethod :: CoreExpr
ratioAddMethod =
  ratioBinaryMethod "$add_ratio_int" (-18790) rationalCoreType ratioAddCore

ratioSubMethod :: CoreExpr
ratioSubMethod =
  ratioBinaryMethod "$sub_ratio_int" (-18800) rationalCoreType ratioSubCore

ratioMulMethod :: CoreExpr
ratioMulMethod =
  ratioBinaryMethod "$mul_ratio_int" (-18810) rationalCoreType ratioMulCore

ratioNegateMethod :: CoreExpr
ratioNegateMethod =
  unaryMethod "$negate_ratio_int" (-18820) rationalCoreType rationalCoreType $ \value ->
    ratioCaseCore "$negate_ratio_int_case" (-18822) value rationalCoreType (-18823) (-18824) $ \n d ->
      ratioIntCore (CPrimOp PrimNegate [n] intTy) d

ratioAbsMethod :: CoreExpr
ratioAbsMethod =
  unaryMethod "$abs_ratio_int" (-18830) rationalCoreType rationalCoreType $ \value ->
    ratioCaseCore "$abs_ratio_int_case" (-18832) value rationalCoreType (-18833) (-18834) $ \n d ->
      ratioIntCore (intAbsCore n) d

ratioSignumMethod :: CoreExpr
ratioSignumMethod =
  unaryMethod "$signum_ratio_int" (-18840) rationalCoreType rationalCoreType $ \value ->
    ratioCaseCore "$signum_ratio_int_case" (-18842) value rationalCoreType (-18843) (-18844) $ \n _ ->
      ratioIntCore (intSignumCore n) oneInt

ratioFromIntegerMethod :: CoreExpr
ratioFromIntegerMethod =
  unaryMethod "$fromInteger_ratio_int" (-18850) intTy rationalCoreType $ \value ->
    ratioIntCore value oneInt

ratioToRationalMethod :: CoreExpr
ratioToRationalMethod =
  unaryMethod "$toRational_ratio_int" (-18860) rationalCoreType rationalCoreType id

data FloatingTypeInfo = FloatingTypeInfo
  { floatingInfoDigits :: Integer
  , floatingInfoRangeLow :: Integer
  , floatingInfoRangeHigh :: Integer
  }

floatEqMethod, floatNotEqMethod, doubleEqMethod, doubleNotEqMethod :: CoreExpr
floatEqMethod = floatingEqMethod FloatWidth floatTy "$eq_float" (-6001)
floatNotEqMethod = floatingNotEqMethod FloatWidth floatTy "$neq_float" (-6005)
doubleEqMethod = floatingEqMethod DoubleWidth doubleTy "$eq_double" (-6011)
doubleNotEqMethod = floatingNotEqMethod DoubleWidth doubleTy "$neq_double" (-6015)

floatCompareMethod, floatLtMethod, floatLeMethod, floatGtMethod, floatGeMethod, floatMaxMethod, floatMinMethod :: CoreExpr
floatCompareMethod = floatingCompareMethod FloatWidth floatTy "$compare_float" (-6021)
floatLtMethod = floatingLtMethod FloatWidth floatTy "$lt_float" (-6031)
floatLeMethod = floatingLeMethod FloatWidth floatTy "$le_float" (-6035)
floatGtMethod = floatingGtMethod FloatWidth floatTy "$gt_float" (-6041)
floatGeMethod = floatingGeMethod FloatWidth floatTy "$ge_float" (-6045)
floatMaxMethod = floatingMaxMethod FloatWidth floatTy "$max_float" (-6051)
floatMinMethod = floatingMinMethod FloatWidth floatTy "$min_float" (-6055)

doubleCompareMethod, doubleLtMethod, doubleLeMethod, doubleGtMethod, doubleGeMethod, doubleMaxMethod, doubleMinMethod :: CoreExpr
doubleCompareMethod = floatingCompareMethod DoubleWidth doubleTy "$compare_double" (-6061)
doubleLtMethod = floatingLtMethod DoubleWidth doubleTy "$lt_double" (-6071)
doubleLeMethod = floatingLeMethod DoubleWidth doubleTy "$le_double" (-6075)
doubleGtMethod = floatingGtMethod DoubleWidth doubleTy "$gt_double" (-6081)
doubleGeMethod = floatingGeMethod DoubleWidth doubleTy "$ge_double" (-6085)
doubleMaxMethod = floatingMaxMethod DoubleWidth doubleTy "$max_double" (-6091)
doubleMinMethod = floatingMinMethod DoubleWidth doubleTy "$min_double" (-6095)

floatAddMethod, floatSubMethod, floatMulMethod, floatNegateMethod, floatAbsMethod, floatSignumMethod, floatFromIntegerMethod :: CoreExpr
floatAddMethod = floatingBinaryPrimMethod FloatWidth floatTy FloatAdd "$add_float" (-6101)
floatSubMethod = floatingBinaryPrimMethod FloatWidth floatTy FloatSub "$sub_float" (-6105)
floatMulMethod = floatingBinaryPrimMethod FloatWidth floatTy FloatMul "$mul_float" (-6111)
floatNegateMethod = floatingUnaryPrimMethod FloatWidth floatTy FloatNegate "$negate_float" (-6115)
floatAbsMethod = floatingUnaryPrimMethod FloatWidth floatTy FloatAbs "$abs_float" (-6121)
floatSignumMethod = floatingUnaryPrimMethod FloatWidth floatTy FloatSignum "$signum_float" (-6125)
floatFromIntegerMethod = floatingFromIntegerMethod FloatWidth floatTy "$fromInteger_float" (-6131)

doubleAddMethod, doubleSubMethod, doubleMulMethod, doubleNegateMethod, doubleAbsMethod, doubleSignumMethod, doubleFromIntegerMethod :: CoreExpr
doubleAddMethod = floatingBinaryPrimMethod DoubleWidth doubleTy FloatAdd "$add_double" (-6141)
doubleSubMethod = floatingBinaryPrimMethod DoubleWidth doubleTy FloatSub "$sub_double" (-6145)
doubleMulMethod = floatingBinaryPrimMethod DoubleWidth doubleTy FloatMul "$mul_double" (-6151)
doubleNegateMethod = floatingUnaryPrimMethod DoubleWidth doubleTy FloatNegate "$negate_double" (-6155)
doubleAbsMethod = floatingUnaryPrimMethod DoubleWidth doubleTy FloatAbs "$abs_double" (-6161)
doubleSignumMethod = floatingUnaryPrimMethod DoubleWidth doubleTy FloatSignum "$signum_double" (-6165)
doubleFromIntegerMethod = floatingFromIntegerMethod DoubleWidth doubleTy "$fromInteger_double" (-6171)

floatToRationalMethod, doubleToRationalMethod :: CoreExpr
floatToRationalMethod = floatingToRationalMethod FloatWidth floatTy "$toRational_float" (-6181)
doubleToRationalMethod = floatingToRationalMethod DoubleWidth doubleTy "$toRational_double" (-6191)

floatDivMethod, floatRecipMethod, floatFromRationalMethod :: CoreExpr
floatDivMethod = floatingBinaryPrimMethod FloatWidth floatTy FloatDiv "$div_float" (-6201)
floatRecipMethod = floatingRecipMethod FloatWidth floatTy "$recip_float" (-6205)
floatFromRationalMethod = floatingFromRationalMethod FloatWidth floatTy "$fromRational_float" (-6211)

doubleDivMethod, doubleRecipMethod, doubleFromRationalMethod :: CoreExpr
doubleDivMethod = floatingBinaryPrimMethod DoubleWidth doubleTy FloatDiv "$div_double" (-6221)
doubleRecipMethod = floatingRecipMethod DoubleWidth doubleTy "$recip_double" (-6225)
doubleFromRationalMethod = floatingFromRationalMethod DoubleWidth doubleTy "$fromRational_double" (-6231)

floatingMethods :: FloatingWidth -> CoreType -> Int -> [CoreExpr]
floatingMethods width ty unique =
  [ floatingConstant ty (floatingLiteral width pi)
  , floatingUnaryPrimMethod width ty FloatExp "$exp_float" unique
  , floatingUnaryPrimMethod width ty FloatLog "$log_float" (unique - 1)
  , floatingUnaryPrimMethod width ty FloatSqrt "$sqrt_float" (unique - 2)
  , floatingBinaryPrimMethod width ty FloatPow "$pow_float" (unique - 3)
  , floatingLogBaseMethod width ty "$log_base_float" (unique - 4)
  , floatingUnaryPrimMethod width ty FloatSin "$sin_float" (unique - 5)
  , floatingUnaryPrimMethod width ty FloatCos "$cos_float" (unique - 6)
  , floatingUnaryPrimMethod width ty FloatTan "$tan_float" (unique - 7)
  , floatingUnaryPrimMethod width ty FloatAsin "$asin_float" (unique - 8)
  , floatingUnaryPrimMethod width ty FloatAcos "$acos_float" (unique - 9)
  , floatingUnaryPrimMethod width ty FloatAtan "$atan_float" (unique - 10)
  , floatingUnaryPrimMethod width ty FloatSinh "$sinh_float" (unique - 11)
  , floatingUnaryPrimMethod width ty FloatCosh "$cosh_float" (unique - 12)
  , floatingUnaryPrimMethod width ty FloatTanh "$tanh_float" (unique - 13)
  , floatingUnaryPrimMethod width ty FloatAsinh "$asinh_float" (unique - 14)
  , floatingUnaryPrimMethod width ty FloatAcosh "$acosh_float" (unique - 15)
  , floatingUnaryPrimMethod width ty FloatAtanh "$atanh_float" (unique - 16)
  ]

realFracMethods :: FloatingWidth -> CoreType -> Int -> [CoreExpr]
realFracMethods width ty unique =
  [ floatingProperFractionMethod width ty "$proper_fraction_float" unique
  , floatingToIntMethod width ty FloatTruncate "$truncate_float" (unique - 1)
  , floatingToIntMethod width ty FloatRound "$round_float" (unique - 2)
  , floatingToIntMethod width ty FloatCeiling "$ceiling_float" (unique - 3)
  , floatingToIntMethod width ty FloatFloor "$floor_float" (unique - 4)
  ]

realFloatMethods :: FloatingWidth -> CoreType -> FloatingTypeInfo -> Int -> [CoreExpr]
realFloatMethods width ty info unique =
  [ unaryMethod "$float_radix" unique ty intTy (const (CLit (LInt 2) intTy))
  , unaryMethod "$float_digits" (unique - 1) ty intTy (const (CLit (LInt (floatingInfoDigits info)) intTy))
  , unaryMethod "$float_range" (unique - 2) ty intPairCoreType (const (tuple2IntCore (CLit (LInt (floatingInfoRangeLow info)) intTy) (CLit (LInt (floatingInfoRangeHigh info)) intTy)))
  , floatingDecodeMethod width ty "$decode_float" (unique - 3)
  , floatingEncodeMethod width ty "$encode_float" (unique - 4)
  , floatingExponentMethod width ty "$exponent_float" (unique - 5)
  , floatingSignificandMethod width ty "$significand_float" (unique - 6)
  , floatingScaleFloatMethod width ty "$scale_float" (unique - 7)
  , floatingPredicateMethod width ty FloatIsNaN "$is_nan_float" (unique - 8)
  , floatingPredicateMethod width ty FloatIsInfinite "$is_infinite_float" (unique - 9)
  , floatingPredicateMethod width ty FloatIsDenormalized "$is_denormalized_float" (unique - 10)
  , floatingPredicateMethod width ty FloatIsNegativeZero "$is_negative_zero_float" (unique - 11)
  , unaryMethod "$is_ieee_float" (unique - 12) ty boolTy (const (CCon trueDataConName boolTy))
  , floatingBinaryPrimMethod width ty FloatAtan2 "$atan2_float" (unique - 13)
  ]

floatingEqMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingEqMethod width ty occurrence unique =
  binaryPrimMethod occurrence unique ty boolTy (PrimFloat width FloatEq)

floatingNotEqMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingNotEqMethod width ty occurrence unique =
  binaryBoolMethod occurrence unique ty (\lhs rhs -> boolNotCore (occurrence <> "_not") (unique - 1) (CPrimOp (PrimFloat width FloatEq) [lhs, rhs] boolTy))

floatingCompareMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingCompareMethod width ty occurrence unique =
  binaryMethod occurrence unique ty orderingTy $ \lhs rhs ->
    boolCaseCore
      (occurrence <> "_lt")
      (unique - 1)
      (floatingLtCore width lhs rhs)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      ( boolCaseCore
          (occurrence <> "_gt")
          (unique - 2)
          (floatingLtCore width rhs lhs)
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingEQDataConName orderingTy)
      )

floatingLtMethod, floatingLeMethod, floatingGtMethod, floatingGeMethod, floatingMaxMethod, floatingMinMethod ::
  FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingLtMethod width ty occurrence unique =
  binaryPrimMethod occurrence unique ty boolTy (PrimFloat width FloatLt)
floatingLeMethod width ty occurrence unique =
  binaryBoolMethod occurrence unique ty (\lhs rhs -> boolNotCore (occurrence <> "_not") (unique - 1) (floatingLtCore width rhs lhs))
floatingGtMethod width ty occurrence unique =
  binaryBoolMethod occurrence unique ty (\lhs rhs -> floatingLtCore width rhs lhs)
floatingGeMethod width ty occurrence unique =
  binaryBoolMethod occurrence unique ty (\lhs rhs -> boolNotCore (occurrence <> "_not") (unique - 1) (floatingLtCore width lhs rhs))
floatingMaxMethod width ty occurrence unique =
  binaryMethod occurrence unique ty ty $ \lhs rhs ->
    boolCaseCore (occurrence <> "_case") (unique - 1) (floatingLtCore width lhs rhs) ty rhs lhs
floatingMinMethod width ty occurrence unique =
  binaryMethod occurrence unique ty ty $ \lhs rhs ->
    boolCaseCore (occurrence <> "_case") (unique - 1) (floatingLtCore width lhs rhs) ty lhs rhs

floatingBinaryPrimMethod :: FloatingWidth -> CoreType -> FloatingPrimOp -> Text -> Int -> CoreExpr
floatingBinaryPrimMethod width ty op occurrence unique =
  binaryMethod occurrence unique ty ty (\lhs rhs -> CPrimOp (PrimFloat width op) [lhs, rhs] ty)

floatingUnaryPrimMethod :: FloatingWidth -> CoreType -> FloatingPrimOp -> Text -> Int -> CoreExpr
floatingUnaryPrimMethod width ty op occurrence unique =
  unaryMethod occurrence unique ty ty (\value -> CPrimOp (PrimFloat width op) [value] ty)

floatingFromIntegerMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingFromIntegerMethod width ty occurrence unique =
  unaryMethod occurrence unique intTy ty (\value -> CPrimOp (PrimFloat width FloatFromInt) [value] ty)

floatingToRationalMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingToRationalMethod width ty occurrence unique =
  unaryMethod occurrence unique ty rationalCoreType $ \value ->
    ratioIntCore (CPrimOp (PrimFloatInt width FloatRound) [value] intTy) oneInt

floatingRecipMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingRecipMethod width ty occurrence unique =
  unaryMethod occurrence unique ty ty (\value -> CPrimOp (PrimFloat width FloatDiv) [floatingOne width, value] ty)

floatingFromRationalMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingFromRationalMethod width ty occurrence unique =
  unaryMethod occurrence unique rationalCoreType ty $ \value ->
    ratioCaseCore (occurrence <> "_case") (unique - 1) value ty (unique - 2) (unique - 3) $ \numerator denominator ->
      CPrimOp
        (PrimFloat width FloatDiv)
        [ CPrimOp (PrimFloat width FloatFromInt) [numerator] ty
        , CPrimOp (PrimFloat width FloatFromInt) [denominator] ty
        ]
        ty

floatingLogBaseMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingLogBaseMethod width ty occurrence unique =
  binaryMethod occurrence unique ty ty $ \base value ->
    CPrimOp
      (PrimFloat width FloatDiv)
      [CPrimOp (PrimFloat width FloatLog) [value] ty, CPrimOp (PrimFloat width FloatLog) [base] ty]
      ty

floatingProperFractionMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingProperFractionMethod width ty occurrence unique =
  unaryMethod occurrence unique ty (CTyTuple [intTy, ty]) $ \value ->
    letCore wholeName intTy (CPrimOp (PrimFloatInt width FloatTruncate) [value] intTy) $
      constructorApp
        (tupleDataConName 2)
        [intTy, ty]
        [ CVar wholeName intTy
        , CPrimOp (PrimFloat width FloatSub) [value, CPrimOp (PrimFloat width FloatFromInt) [CVar wholeName intTy] ty] ty
        ]
        (CTyTuple [intTy, ty])
 where
  wholeName = builtinLocalTermName (occurrence <> "_whole") (unique - 1)

floatingToIntMethod :: FloatingWidth -> CoreType -> FloatingIntPrimOp -> Text -> Int -> CoreExpr
floatingToIntMethod width ty op occurrence unique =
  unaryMethod occurrence unique ty intTy (\value -> CPrimOp (PrimFloatInt width op) [value] intTy)

floatingDecodeMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingDecodeMethod width ty occurrence unique =
  unaryMethod occurrence unique ty intPairCoreType $ \value ->
    tuple2IntCore (CPrimOp (PrimFloatInt width FloatTruncate) [value] intTy) zeroInt

floatingEncodeMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingEncodeMethod width ty occurrence unique =
  coreLam significandName intTy $
    coreLam exponentName intTy $
      CPrimOp
        (PrimFloat width FloatMul)
        [ CPrimOp (PrimFloat width FloatFromInt) [CVar significandName intTy] ty
        , floatingPow2 width ty (CVar exponentName intTy)
        ]
        ty
 where
  significandName = builtinLocalTermName (occurrence <> "_significand") unique
  exponentName = builtinLocalTermName (occurrence <> "_exponent") (unique - 1)

floatingExponentMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingExponentMethod width ty occurrence unique =
  unaryMethod occurrence unique ty intTy $ \value ->
    boolCaseCore
      (occurrence <> "_zero")
      (unique - 1)
      (CPrimOp (PrimFloat width FloatEq) [value, floatingZero width] boolTy)
      intTy
      zeroInt
      ( intAdd
          ( CPrimOp
              (PrimFloatInt width FloatFloor)
              [ CPrimOp
                  (PrimFloat width FloatDiv)
                  [ CPrimOp (PrimFloat width FloatLog) [CPrimOp (PrimFloat width FloatAbs) [value] ty] ty
                  , CPrimOp (PrimFloat width FloatLog) [floatingLiteral width 2] ty
                  ]
                  ty
              ]
              intTy
          )
          oneInt
      )

floatingSignificandMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingSignificandMethod width ty occurrence unique =
  unaryMethod occurrence unique ty ty $ \value ->
    letCore exponentName intTy (floatingExponentCore width ty value) $
      CPrimOp
        (PrimFloat width FloatDiv)
        [value, floatingPow2 width ty (CVar exponentName intTy)]
        ty
 where
  exponentName = builtinLocalTermName (occurrence <> "_exponent") (unique - 1)

floatingScaleFloatMethod :: FloatingWidth -> CoreType -> Text -> Int -> CoreExpr
floatingScaleFloatMethod width ty occurrence unique =
  coreLam exponentName intTy $
    coreLam valueName ty $
      CPrimOp
        (PrimFloat width FloatMul)
        [CVar valueName ty, floatingPow2 width ty (CVar exponentName intTy)]
        ty
 where
  exponentName = builtinLocalTermName (occurrence <> "_exponent") unique
  valueName = builtinLocalTermName (occurrence <> "_value") (unique - 1)

floatingPredicateMethod :: FloatingWidth -> CoreType -> FloatingIntPrimOp -> Text -> Int -> CoreExpr
floatingPredicateMethod width ty op occurrence unique =
  unaryMethod occurrence unique ty boolTy (\value -> CPrimOp (PrimFloatInt width op) [value] boolTy)

floatingExponentCore :: FloatingWidth -> CoreType -> CoreExpr -> CoreExpr
floatingExponentCore width ty value =
  boolCaseCore
    "$floating_exponent_zero"
    (-6241)
    (CPrimOp (PrimFloat width FloatEq) [value, floatingZero width] boolTy)
    intTy
    zeroInt
    ( intAdd
        ( CPrimOp
            (PrimFloatInt width FloatFloor)
            [ CPrimOp
                (PrimFloat width FloatDiv)
                [ CPrimOp (PrimFloat width FloatLog) [CPrimOp (PrimFloat width FloatAbs) [value] ty] ty
                , CPrimOp (PrimFloat width FloatLog) [floatingLiteral width 2] ty
                ]
                ty
            ]
            intTy
        )
        oneInt
    )

floatingPow2 :: FloatingWidth -> CoreType -> CoreExpr -> CoreExpr
floatingPow2 width ty exponentExpr =
  CPrimOp
    (PrimFloat width FloatPow)
    [floatingLiteral width 2, CPrimOp (PrimFloat width FloatFromInt) [exponentExpr] ty]
    ty

floatingLtCore :: FloatingWidth -> CoreExpr -> CoreExpr -> CoreExpr
floatingLtCore width lhs rhs =
  CPrimOp (PrimFloat width FloatLt) [lhs, rhs] boolTy

floatingConstant :: CoreType -> CoreExpr -> CoreExpr
floatingConstant _ value =
  value

floatingZero, floatingOne :: FloatingWidth -> CoreExpr
floatingZero width = floatingLiteral width 0
floatingOne width = floatingLiteral width 1

floatingLiteral :: FloatingWidth -> Double -> CoreExpr
floatingLiteral width value =
  case width of
    FloatWidth -> CLit (LFloat (realToFrac value)) floatTy
    DoubleWidth -> CLit (LDouble value) doubleTy

ratioBinaryBoolMethod :: Text -> Int -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ratioBinaryBoolMethod occurrence unique =
  ratioBinaryMethod occurrence unique boolTy

ratioBinaryMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ratioBinaryMethod occurrence unique resultTy body =
  CLam lhsBinder (CLam rhsBinder methodBody (CTyFun rationalCoreType resultTy)) (CTyFun rationalCoreType (CTyFun rationalCoreType resultTy))
 where
  lhsName = builtinLocalTermName (occurrence <> "_lhs") unique
  rhsName = builtinLocalTermName (occurrence <> "_rhs") (unique - 1)
  lhsBinder = CoreBinder lhsName rationalCoreType
  rhsBinder = CoreBinder rhsName rationalCoreType
  lhs = CVar lhsName rationalCoreType
  rhs = CVar rhsName rationalCoreType
  methodBody = body lhs rhs

ratioEqCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioEqCore lhs rhs =
  ratioZipCore "$ratio_eq" (-18870) lhs rhs boolTy $ \lhsN lhsD rhsN rhsD ->
    boolAndCore
      "$ratio_eq_and"
      (-18875)
      (CPrimOp PrimEq [lhsN, rhsN] boolTy)
      (CPrimOp PrimEq [lhsD, rhsD] boolTy)

ratioLtCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioLtCore lhs rhs =
  ratioZipCore "$ratio_lt" (-18880) lhs rhs boolTy $ \lhsN lhsD rhsN rhsD ->
    intLt (intMul lhsN rhsD) (intMul rhsN lhsD)

ratioAddCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioAddCore lhs rhs =
  ratioZipCore "$ratio_add" (-18890) lhs rhs rationalCoreType $ \lhsN lhsD rhsN rhsD ->
    ratioReduceCall (intAdd (intMul lhsN rhsD) (intMul rhsN lhsD)) (intMul lhsD rhsD)

ratioSubCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioSubCore lhs rhs =
  ratioZipCore "$ratio_sub" (-18900) lhs rhs rationalCoreType $ \lhsN lhsD rhsN rhsD ->
    ratioReduceCall (intSub (intMul lhsN rhsD) (intMul rhsN lhsD)) (intMul lhsD rhsD)

ratioMulCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioMulCore lhs rhs =
  ratioZipCore "$ratio_mul" (-18910) lhs rhs rationalCoreType $ \lhsN lhsD rhsN rhsD ->
    ratioReduceCall (intMul lhsN rhsN) (intMul lhsD rhsD)

ratioNegateCore :: CoreExpr -> CoreExpr
ratioNegateCore value =
  ratioCaseCore "$ratio_negate_core" (-18920) value rationalCoreType (-18921) (-18922) $ \n d ->
    ratioIntCore (CPrimOp PrimNegate [n] intTy) d

ratioReduceCall :: CoreExpr -> CoreExpr -> CoreExpr
ratioReduceCall numeratorExpr denominatorExpr =
  applyCore (applyCore (CVar ratioReduceName ratioPercentCoreType) numeratorExpr (CTyFun intTy rationalCoreType)) denominatorExpr rationalCoreType

ratioZipCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
ratioZipCore occurrence unique lhs rhs resultTy body =
  ratioCaseCore (occurrence <> "_lhs_case") unique lhs resultTy (unique - 1) (unique - 2) $ \lhsN lhsD ->
    ratioCaseCore (occurrence <> "_rhs_case") (unique - 3) rhs resultTy (unique - 4) (unique - 5) $ \rhsN rhsD ->
      body lhsN lhsD rhsN rhsD

intBitAndMethod :: CoreExpr
intBitAndMethod =
  binaryPrimMethod "$bit_and_int" (-3931) intTy intTy PrimBitAnd

intBitOrMethod :: CoreExpr
intBitOrMethod =
  binaryPrimMethod "$bit_or_int" (-3932) intTy intTy PrimBitOr

intBitXorMethod :: CoreExpr
intBitXorMethod =
  binaryPrimMethod "$bit_xor_int" (-3933) intTy intTy PrimBitXor

intBitComplementMethod :: CoreExpr
intBitComplementMethod =
  unaryPrimMethod "$bit_complement_int" (-3934) intTy intTy PrimBitComplement

intShiftMethod :: CoreExpr
intShiftMethod =
  binaryPrimMethod "$shift_int" (-3935) intTy intTy PrimShift

intRotateMethod :: CoreExpr
intRotateMethod =
  binaryPrimMethod "$rotate_int" (-3936) intTy intTy PrimRotate

intBitMethod :: CoreExpr
intBitMethod =
  unaryPrimMethod "$bit_int" (-3937) intTy intTy PrimBit

intSetBitMethod :: CoreExpr
intSetBitMethod =
  binaryMethod "$set_bit_int" (-3938) intTy intTy $ \value amount ->
    CPrimOp PrimBitOr [value, CPrimOp PrimBit [amount] intTy] intTy

intClearBitMethod :: CoreExpr
intClearBitMethod =
  binaryMethod "$clear_bit_int" (-3939) intTy intTy $ \value amount ->
    CPrimOp PrimBitAnd [value, CPrimOp PrimBitComplement [CPrimOp PrimBit [amount] intTy] intTy] intTy

intComplementBitMethod :: CoreExpr
intComplementBitMethod =
  binaryMethod "$complement_bit_int" (-3940) intTy intTy $ \value amount ->
    CPrimOp PrimBitXor [value, CPrimOp PrimBit [amount] intTy] intTy

intTestBitMethod :: CoreExpr
intTestBitMethod =
  binaryPrimMethod "$test_bit_int" (-3941) intTy boolTy PrimTestBit

intBitSizeMethod :: CoreExpr
intBitSizeMethod =
  unaryMethod "$bit_size_int" (-3942) intTy intTy (const (CLit (LInt 64) intTy))

intIsSignedMethod :: CoreExpr
intIsSignedMethod =
  unaryMethod "$is_signed_int" (-3943) intTy boolTy (const (CCon trueDataConName boolTy))

intShiftLMethod :: CoreExpr
intShiftLMethod =
  binaryPrimMethod "$shift_l_int" (-3944) intTy intTy PrimShiftL

intShiftRMethod :: CoreExpr
intShiftRMethod =
  binaryPrimMethod "$shift_r_int" (-3945) intTy intTy PrimShiftR

intRotateLMethod :: CoreExpr
intRotateLMethod =
  binaryPrimMethod "$rotate_l_int" (-3946) intTy intTy PrimRotateL

intRotateRMethod :: CoreExpr
intRotateRMethod =
  binaryPrimMethod "$rotate_r_int" (-3947) intTy intTy PrimRotateR

fixedEqMethods :: FixedIntegral -> [CoreExpr]
fixedEqMethods fixed =
  [ fixedBinaryPrimMethod fixed FixedEq "eq" (-8001) boolTy
  , fixedBinaryBoolMethod fixed "neq" (-8002) (\lhs rhs -> boolNotCore "$neq_fixed_not" (-8003) (fixedPrim fixed FixedEq [lhs, rhs] boolTy))
  ]

fixedOrdMethods :: FixedIntegral -> [CoreExpr]
fixedOrdMethods fixed =
  [ fixedCompareMethod fixed
  , fixedBinaryPrimMethod fixed FixedLt "lt" (-8011) boolTy
  , fixedBinaryBoolMethod fixed "le" (-8012) (\lhs rhs -> boolNotCore "$le_fixed_not" (-8013) (fixedPrim fixed FixedLt [rhs, lhs] boolTy))
  , fixedBinaryBoolMethod fixed "gt" (-8014) (\lhs rhs -> fixedPrim fixed FixedLt [rhs, lhs] boolTy)
  , fixedBinaryBoolMethod fixed "ge" (-8015) (\lhs rhs -> boolNotCore "$ge_fixed_not" (-8016) (fixedPrim fixed FixedLt [lhs, rhs] boolTy))
  , fixedBinaryMethod fixed "max" (-8017) fixedTy $ \lhs rhs ->
      boolCaseCore "$max_fixed_case" (-8018) (fixedPrim fixed FixedLt [lhs, rhs] boolTy) fixedTy rhs lhs
  , fixedBinaryMethod fixed "min" (-8019) fixedTy $ \lhs rhs ->
      boolCaseCore "$min_fixed_case" (-8020) (fixedPrim fixed FixedLt [lhs, rhs] boolTy) fixedTy lhs rhs
  ]
 where
  fixedTy = fixedIntegralTy fixed

fixedCompareMethod :: FixedIntegral -> CoreExpr
fixedCompareMethod fixed =
  fixedBinaryMethod fixed "compare" (-8021) orderingTy $ \lhs rhs ->
    boolCaseCore
      "$compare_fixed_lt"
      (-8022)
      (fixedPrim fixed FixedLt [lhs, rhs] boolTy)
      orderingTy
      (CCon orderingLTDataConName orderingTy)
      ( boolCaseCore
          "$compare_fixed_gt"
          (-8023)
          (fixedPrim fixed FixedLt [rhs, lhs] boolTy)
          orderingTy
          (CCon orderingGTDataConName orderingTy)
          (CCon orderingEQDataConName orderingTy)
      )

fixedNumMethods :: FixedIntegral -> [CoreExpr]
fixedNumMethods fixed =
  [ fixedBinaryPrimMethod fixed FixedAdd "add" (-8031) fixedTy
  , fixedBinaryPrimMethod fixed FixedSub "sub" (-8032) fixedTy
  , fixedBinaryPrimMethod fixed FixedMul "mul" (-8033) fixedTy
  , fixedUnaryPrimMethod fixed FixedNegate "negate" (-8034) fixedTy
  , fixedUnaryPrimMethod fixed FixedAbs "abs" (-8035) fixedTy
  , fixedUnaryPrimMethod fixed FixedSignum "signum" (-8036) fixedTy
  , unaryMethod ("$fromInteger_" <> fixedOccurrence) (-8037) intTy fixedTy (\value -> fixedPrim fixed FixedFromInteger [value] fixedTy)
  ]
 where
  fixedTy = fixedIntegralTy fixed
  fixedOccurrence = fixedIntegralOccurrence fixed

fixedRealMethods :: FixedIntegral -> [CoreExpr]
fixedRealMethods fixed =
  [ unaryMethod ("$toRational_" <> fixedIntegralOccurrence fixed) (-8041) fixedTy rationalCoreType $ \value ->
      ratioIntCore (fixedPrim fixed FixedToInteger [value] intTy) oneInt
  ]
 where
  fixedTy = fixedIntegralTy fixed

fixedIntegralMethods :: FixedIntegral -> [CoreExpr]
fixedIntegralMethods fixed =
  [ fixedBinaryPrimMethod fixed FixedQuot "quot" (-8051) fixedTy
  , fixedBinaryPrimMethod fixed FixedRem "rem" (-8052) fixedTy
  , fixedBinaryMethod fixed "div" (-8053) fixedTy (fixedDivCore fixed)
  , fixedBinaryMethod fixed "mod" (-8054) fixedTy (\lhs rhs -> fixedSub fixed lhs (fixedMul fixed (fixedDivCore fixed lhs rhs) rhs))
  , fixedBinaryMethod fixed "quotRem" (-8055) fixedPairTy $ \lhs rhs -> fixedTuple2 fixed (fixedQuot fixed lhs rhs) (fixedRem fixed lhs rhs)
  , fixedBinaryMethod fixed "divMod" (-8056) fixedPairTy $ \lhs rhs ->
      letCore dName fixedTy (fixedDivCore fixed lhs rhs) $
        fixedTuple2 fixed dVar (fixedSub fixed lhs (fixedMul fixed dVar rhs))
  , fixedUnaryPrimMethod fixed FixedToInteger "toInteger" (-8057) intTy
  ]
 where
  fixedTy = fixedIntegralTy fixed
  fixedPairTy = CTyTuple [fixedTy, fixedTy]
  dName = builtinLocalTermName ("$divMod_" <> fixedIntegralOccurrence fixed <> "_d") (-8058 - fromEnum fixed)
  dVar = CVar dName fixedTy

fixedBitsMethods :: FixedIntegral -> [CoreExpr]
fixedBitsMethods fixed =
  [ fixedBinaryPrimMethod fixed FixedBitAnd "bit_and" (-8061) fixedTy
  , fixedBinaryPrimMethod fixed FixedBitOr "bit_or" (-8062) fixedTy
  , fixedBinaryPrimMethod fixed FixedBitXor "bit_xor" (-8063) fixedTy
  , fixedUnaryPrimMethod fixed FixedBitComplement "bit_complement" (-8064) fixedTy
  , fixedIntBinaryPrimMethod fixed FixedShift "shift" (-8065)
  , fixedIntBinaryPrimMethod fixed FixedRotate "rotate" (-8066)
  , unaryMethod ("$bit_" <> fixedIntegralOccurrence fixed) (-8067) intTy fixedTy (\amount -> fixedPrim fixed FixedBit [amount] fixedTy)
  , fixedIntBinaryMethod fixed "set_bit" (-8068) (\value amount -> fixedOr fixed value (fixedPrim fixed FixedBit [amount] fixedTy))
  , fixedIntBinaryMethod fixed "clear_bit" (-8069) (\value amount -> fixedAnd fixed value (fixedComplement fixed (fixedPrim fixed FixedBit [amount] fixedTy)))
  , fixedIntBinaryMethod fixed "complement_bit" (-8070) (\value amount -> fixedXor fixed value (fixedPrim fixed FixedBit [amount] fixedTy))
  , fixedIntBinaryPrimMethodResult fixed FixedTestBit "test_bit" (-8071) boolTy
  , unaryMethod ("$bit_size_" <> fixedIntegralOccurrence fixed) (-8072) fixedTy intTy (const (CLit (LInt (fixedIntegralBitSize fixed)) intTy))
  , unaryMethod ("$is_signed_" <> fixedIntegralOccurrence fixed) (-8073) fixedTy boolTy (const (if fixedIntegralIsSigned fixed then CCon trueDataConName boolTy else CCon falseDataConName boolTy))
  , fixedIntBinaryPrimMethod fixed FixedShiftL "shift_l" (-8074)
  , fixedIntBinaryPrimMethod fixed FixedShiftR "shift_r" (-8075)
  , fixedIntBinaryPrimMethod fixed FixedRotateL "rotate_l" (-8076)
  , fixedIntBinaryPrimMethod fixed FixedRotateR "rotate_r" (-8077)
  ]
 where
  fixedTy = fixedIntegralTy fixed

fixedShowMethods :: FixedIntegral -> [CoreExpr]
fixedShowMethods fixed =
  [ showsPrecFromRenderedMethod ("$shows_prec_" <> fixedIntegralOccurrence fixed) (-8081) fixedTy (\value -> fixedPrim fixed FixedShow [value] stringTy)
  , fixedUnaryPrimMethod fixed FixedShow "show" (-8082) stringTy
  , showListFromShowsMethod fixedTy (showsPrecFromRenderedMethod ("$show_list_shows_" <> fixedIntegralOccurrence fixed) (-8083) fixedTy (\value -> fixedPrim fixed FixedShow [value] stringTy))
  ]
 where
  fixedTy = fixedIntegralTy fixed

fixedReadMethods :: FixedIntegral -> [CoreExpr]
fixedReadMethods fixed =
  [ readsPrecFromParserMethod ("$reads_prec_" <> fixedIntegralOccurrence fixed) (-8091) fixedTy (fixedReadParserCore fixed)
  , readListFromParserMethod fixedTy (fixedReadParserCore fixed)
  ]
 where
  fixedTy = fixedIntegralTy fixed

fixedReadParserCore :: FixedIntegral -> CoreExpr
fixedReadParserCore fixed =
  coreLam inputName stringTy $
    readBindCallCore
      intTy
      fixedTy
      (applyCore (CVar readIntName readIntCoreType) (CVar inputName stringTy) (readResultsCoreType intTy))
      ( coreLam valueName intTy $
          coreLam restName stringTy $
            readSingleResultCore fixedTy (fixedPrim fixed FixedFromInteger [CVar valueName intTy] fixedTy) (CVar restName stringTy)
      )
 where
  fixedTy = fixedIntegralTy fixed
  inputName = builtinLocalTermName ("$read_" <> fixedIntegralOccurrence fixed <> "_input") (-8092 - fromEnum fixed)
  valueName = builtinLocalTermName ("$read_" <> fixedIntegralOccurrence fixed <> "_value") (-8110 - fromEnum fixed)
  restName = builtinLocalTermName ("$read_" <> fixedIntegralOccurrence fixed <> "_rest") (-8120 - fromEnum fixed)

fixedEnumMethods :: FixedIntegral -> [CoreExpr]
fixedEnumMethods fixed =
  [ fixedUnaryMethod fixed "succ" (-8131) fixedTy (\value -> fixedAdd fixed value fixedOne)
  , fixedUnaryMethod fixed "pred" (-8132) fixedTy (\value -> fixedSub fixed value fixedOne)
  , unaryMethod ("$toEnum_" <> fixedIntegralOccurrence fixed) (-8133) intTy fixedTy (\value -> fixedPrim fixed FixedFromInteger [value] fixedTy)
  , fixedUnaryPrimMethod fixed FixedToInteger "fromEnum" (-8134) intTy
  , fixedUnaryMethod fixed "enum_from" (-8135) listTy (\current -> fixedEnumFromToList fixed current (fixedMaxBound fixed))
  , fixedBinaryMethod fixed "enum_from_then" (-8136) listTy $ \current next ->
      boolCaseCore "$enum_fixed_from_then_desc" (-8137) (fixedLt fixed next current) listTy (fixedEnumFromThenToList fixed current next (fixedMinBound fixed)) (fixedEnumFromThenToList fixed current next (fixedMaxBound fixed))
  , fixedBinaryMethod fixed "enum_from_to" (-8138) listTy (fixedEnumFromToList fixed)
  , fixedTernaryMethod fixed "enum_from_then_to" (-8139) listTy (fixedEnumFromThenToList fixed)
  ]
 where
  fixedTy = fixedIntegralTy fixed
  listTy = CTyList fixedTy
  fixedOne = fixedPrim fixed FixedFromInteger [oneInt] fixedTy

fixedBoundedMethods :: FixedIntegral -> [CoreExpr]
fixedBoundedMethods fixed =
  [fixedMinBound fixed, fixedMaxBound fixed]

fixedIxMethods :: FixedIntegral -> [CoreExpr]
fixedIxMethods fixed =
  [ fixedLam boundsName boundsTy (fixedBoundsCase "range" (-8142) (CTyList fixedTy) (fixedEnumFromToList fixed low high))
  , fixedLam boundsName boundsTy (fixedLam valueName fixedTy (fixedBoundsCase "index" (-8143) intTy (fixedSubInt (fixedToInt value) (fixedToInt low))))
  , fixedLam boundsName boundsTy (fixedLam valueName fixedTy (fixedBoundsCase "in_range" (-8144) boolTy (boolAndCore "$ix_fixed_in_range" (-8151) (boolNotCore "$ix_fixed_low" (-8152) (fixedLt fixed value low)) (boolNotCore "$ix_fixed_high" (-8153) (fixedLt fixed high value)))))
  , fixedLam boundsName boundsTy (fixedBoundsCase "range_size" (-8145) intTy (intAdd (fixedSubInt (fixedToInt high) (fixedToInt low)) oneInt))
  ]
 where
  fixedTy = fixedIntegralTy fixed
  boundsTy = CTyTuple [fixedTy, fixedTy]
  boundsName = builtinLocalTermName ("$ix_" <> fixedIntegralOccurrence fixed <> "_bounds") (-8141 - fromEnum fixed)
  valueName = builtinLocalTermName ("$ix_" <> fixedIntegralOccurrence fixed <> "_value") (-8150 - fromEnum fixed)
  lowName = builtinLocalTermName ("$ix_" <> fixedIntegralOccurrence fixed <> "_low") (-8160 - fromEnum fixed)
  highName = builtinLocalTermName ("$ix_" <> fixedIntegralOccurrence fixed <> "_high") (-8170 - fromEnum fixed)
  bounds = CVar boundsName boundsTy
  value = CVar valueName fixedTy
  low = CVar lowName fixedTy
  high = CVar highName fixedTy
  fixedLam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  fixedBoundsCase occurrence unique resultTy body =
    CCase
      bounds
      (CoreBinder caseName boundsTy)
      [CoreAlt (ConstructorAlt (tupleDataConName 2)) [CoreBinder lowName fixedTy, CoreBinder highName fixedTy] body]
      resultTy
   where
    caseName = builtinLocalTermName ("$ix_" <> fixedIntegralOccurrence fixed <> "_" <> occurrence <> "_case") (unique - fromEnum fixed)

fixedBinaryPrimMethod :: FixedIntegral -> FixedIntegralOp -> Text -> Int -> CoreType -> CoreExpr
fixedBinaryPrimMethod fixed op occurrence unique resultTy =
  fixedBinaryMethod fixed occurrence unique resultTy (\lhs rhs -> fixedPrim fixed op [lhs, rhs] resultTy)

fixedBinaryBoolMethod :: FixedIntegral -> Text -> Int -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
fixedBinaryBoolMethod fixed occurrence unique =
  fixedBinaryMethod fixed occurrence unique boolTy

fixedBinaryMethod :: FixedIntegral -> Text -> Int -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
fixedBinaryMethod fixed occurrence unique resultTy =
  binaryMethod ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed) (unique - fromEnum fixed) (fixedIntegralTy fixed) resultTy

fixedUnaryPrimMethod :: FixedIntegral -> FixedIntegralOp -> Text -> Int -> CoreType -> CoreExpr
fixedUnaryPrimMethod fixed op occurrence unique resultTy =
  fixedUnaryMethod fixed occurrence unique resultTy (\value -> fixedPrim fixed op [value] resultTy)

fixedUnaryMethod :: FixedIntegral -> Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
fixedUnaryMethod fixed occurrence unique resultTy =
  unaryMethod ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed) (unique - fromEnum fixed) (fixedIntegralTy fixed) resultTy

fixedIntBinaryPrimMethod :: FixedIntegral -> FixedIntegralOp -> Text -> Int -> CoreExpr
fixedIntBinaryPrimMethod fixed op occurrence unique =
  fixedIntBinaryPrimMethodResult fixed op occurrence unique (fixedIntegralTy fixed)

fixedIntBinaryPrimMethodResult :: FixedIntegral -> FixedIntegralOp -> Text -> Int -> CoreType -> CoreExpr
fixedIntBinaryPrimMethodResult fixed op occurrence unique resultTy =
  fixedIntBinaryMethod fixed occurrence unique (\value amount -> fixedPrim fixed op [value, amount] resultTy)

fixedIntBinaryMethod :: FixedIntegral -> Text -> Int -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
fixedIntBinaryMethod fixed occurrence unique body =
  CLam valueBinder (CLam amountBinder methodBody (CTyFun intTy (exprType methodBody))) (CTyFun fixedTy (CTyFun intTy (exprType methodBody)))
 where
  fixedTy = fixedIntegralTy fixed
  valueName = builtinLocalTermName ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed <> "_value") (unique - fromEnum fixed)
  amountName = builtinLocalTermName ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed <> "_amount") (unique - 20 - fromEnum fixed)
  valueBinder = CoreBinder valueName fixedTy
  amountBinder = CoreBinder amountName intTy
  methodBody = body (CVar valueName fixedTy) (CVar amountName intTy)

fixedTernaryMethod :: FixedIntegral -> Text -> Int -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
fixedTernaryMethod fixed occurrence unique resultTy body =
  CLam firstBinder (CLam secondBinder (CLam thirdBinder methodBody (CTyFun fixedTy resultTy)) (CTyFun fixedTy (CTyFun fixedTy resultTy))) (CTyFun fixedTy (CTyFun fixedTy (CTyFun fixedTy resultTy)))
 where
  fixedTy = fixedIntegralTy fixed
  firstName = builtinLocalTermName ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed <> "_first") (unique - fromEnum fixed)
  secondName = builtinLocalTermName ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed <> "_second") (unique - 20 - fromEnum fixed)
  thirdName = builtinLocalTermName ("$" <> occurrence <> "_" <> fixedIntegralOccurrence fixed <> "_third") (unique - 40 - fromEnum fixed)
  firstBinder = CoreBinder firstName fixedTy
  secondBinder = CoreBinder secondName fixedTy
  thirdBinder = CoreBinder thirdName fixedTy
  methodBody = body (CVar firstName fixedTy) (CVar secondName fixedTy) (CVar thirdName fixedTy)

fixedPrim :: FixedIntegral -> FixedIntegralOp -> [CoreExpr] -> CoreType -> CoreExpr
fixedPrim fixed op arguments resultTy =
  CPrimOp (PrimFixedIntegral fixed op) arguments resultTy

fixedAdd, fixedSub, fixedMul, fixedQuot, fixedRem, fixedLt, fixedAnd, fixedOr, fixedXor :: FixedIntegral -> CoreExpr -> CoreExpr -> CoreExpr
fixedAdd fixed lhs rhs = fixedPrim fixed FixedAdd [lhs, rhs] (fixedIntegralTy fixed)
fixedSub fixed lhs rhs = fixedPrim fixed FixedSub [lhs, rhs] (fixedIntegralTy fixed)
fixedMul fixed lhs rhs = fixedPrim fixed FixedMul [lhs, rhs] (fixedIntegralTy fixed)
fixedQuot fixed lhs rhs = fixedPrim fixed FixedQuot [lhs, rhs] (fixedIntegralTy fixed)
fixedRem fixed lhs rhs = fixedPrim fixed FixedRem [lhs, rhs] (fixedIntegralTy fixed)
fixedLt fixed lhs rhs = fixedPrim fixed FixedLt [lhs, rhs] boolTy
fixedAnd fixed lhs rhs = fixedPrim fixed FixedBitAnd [lhs, rhs] (fixedIntegralTy fixed)
fixedOr fixed lhs rhs = fixedPrim fixed FixedBitOr [lhs, rhs] (fixedIntegralTy fixed)
fixedXor fixed lhs rhs = fixedPrim fixed FixedBitXor [lhs, rhs] (fixedIntegralTy fixed)

fixedComplement :: FixedIntegral -> CoreExpr -> CoreExpr
fixedComplement fixed value =
  fixedPrim fixed FixedBitComplement [value] (fixedIntegralTy fixed)

fixedMinBound, fixedMaxBound :: FixedIntegral -> CoreExpr
fixedMinBound fixed =
  fixedPrim fixed FixedMinBound [] (fixedIntegralTy fixed)
fixedMaxBound fixed =
  fixedPrim fixed FixedMaxBound [] (fixedIntegralTy fixed)

fixedToInt :: CoreExpr -> CoreExpr
fixedToInt value =
  case exprType value of
    ty
      | Just fixed <- fixedIntegralTypeByCoreType ty ->
          fixedPrim fixed FixedToInteger [value] intTy
    _ ->
      value

fixedSubInt :: CoreExpr -> CoreExpr -> CoreExpr
fixedSubInt =
  intSub

fixedTuple2 :: FixedIntegral -> CoreExpr -> CoreExpr -> CoreExpr
fixedTuple2 fixed lhs rhs =
  constructorApp (tupleDataConName 2) [fixedTy, fixedTy] [lhs, rhs] (CTyTuple [fixedTy, fixedTy])
 where
  fixedTy = fixedIntegralTy fixed

fixedDivCore :: FixedIntegral -> CoreExpr -> CoreExpr -> CoreExpr
fixedDivCore fixed lhs rhs =
  letCore qName fixedTy (fixedQuot fixed lhs rhs) $
    letCore rName fixedTy (fixedRem fixed lhs rhs) $
      boolCaseCore (fixedIntegralOccurrence fixed <> "_div_adjust") (unique - 3) needsAdjust fixedTy (fixedSub fixed qVar fixedOne) qVar
 where
  fixedTy = fixedIntegralTy fixed
  unique = -8180 - fromEnum fixed
  qName = builtinLocalTermName ("$div_" <> fixedIntegralOccurrence fixed <> "_q") (unique - 1)
  rName = builtinLocalTermName ("$div_" <> fixedIntegralOccurrence fixed <> "_r") (unique - 2)
  qVar = CVar qName fixedTy
  rVar = CVar rName fixedTy
  fixedZero = fixedPrim fixed FixedFromInteger [zeroInt] fixedTy
  fixedOne = fixedPrim fixed FixedFromInteger [oneInt] fixedTy
  remainderNonZero = boolNotCore "$fixed_div_rem_nonzero" (unique - 4) (fixedPrim fixed FixedEq [rVar, fixedZero] boolTy)
  signsDiffer = boolXorCore "$fixed_div_signs_differ" (unique - 5) (fixedLt fixed lhs fixedZero) (fixedLt fixed rhs fixedZero)
  needsAdjust = boolAndCore "$fixed_div_needs_adjust" (unique - 6) remainderNonZero signsDiffer

fixedEnumFromToList :: FixedIntegral -> CoreExpr -> CoreExpr -> CoreExpr
fixedEnumFromToList fixed current end =
  fixedMapIntList fixed $
    applyCore
      (applyCore (CVar enumFromToIntName enumFromToIntCoreType) (fixedToInt current) (CTyFun intTy intListCoreType))
      (fixedToInt end)
      intListCoreType

fixedEnumFromThenToList :: FixedIntegral -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
fixedEnumFromThenToList fixed current next end =
  fixedMapIntList fixed $
    applyCore
      ( applyCore
          (applyCore (CVar enumFromThenToIntName enumFromThenToIntCoreType) (fixedToInt current) (CTyFun intTy (CTyFun intTy intListCoreType)))
          (fixedToInt next)
          (CTyFun intTy intListCoreType)
      )
      (fixedToInt end)
      intListCoreType

fixedMapIntList :: FixedIntegral -> CoreExpr -> CoreExpr
fixedMapIntList fixed intList =
  applyCore
    (applyCore mapFunction fromIntFunction (CTyFun intListCoreType resultListTy))
    intList
    resultListTy
 where
  fixedTy = fixedIntegralTy fixed
  resultListTy = CTyList fixedTy
  argumentName = builtinLocalTermName ("$map_" <> fixedIntegralOccurrence fixed <> "_int") (-8190 - fromEnum fixed)
  fromIntFunction =
    CLam
      (CoreBinder argumentName intTy)
      (fixedPrim fixed FixedFromInteger [CVar argumentName intTy] fixedTy)
      (CTyFun intTy fixedTy)
  mapFunction =
    CTypeApp
      (CVar derivedMapName mapPreludeCoreType)
      [intTy, fixedTy]
      (CTyFun (CTyFun intTy fixedTy) (CTyFun intListCoreType resultListTy))

fixedIntegralTypeByCoreType :: CoreType -> Maybe FixedIntegral
fixedIntegralTypeByCoreType = \case
  CTyCon name -> fixedIntegralTypeByOccurrence (nameOcc name)
  _ -> Nothing

intDivCoreWith :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
intDivCoreWith occurrence unique lhs rhs =
  letCore qName intTy (intQuot lhs rhs) $
    letCore rName intTy (intRem lhs rhs) $
      intDivFromQuotRem occurrence (unique - 3) lhs rhs qVar rVar
 where
  qName = builtinLocalTermName (occurrence <> "_q") (unique - 1)
  rName = builtinLocalTermName (occurrence <> "_r") (unique - 2)
  qVar = CVar qName intTy
  rVar = CVar rName intTy

intModCoreWith :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
intModCoreWith occurrence unique lhs rhs =
  letCore dName intTy (intDivCoreWith occurrence (unique - 10) lhs rhs) $
    intSub lhs (intMul dVar rhs)
 where
  dName = builtinLocalTermName (occurrence <> "_d") (unique - 1)
  dVar = CVar dName intTy

intDivFromQuotRem :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
intDivFromQuotRem occurrence unique lhs rhs quotient remainder =
  boolCaseCore (occurrence <> "_adjust") unique needsAdjust intTy (intSub quotient oneInt) quotient
 where
  remainderNonZero =
    boolNotCore (occurrence <> "_rem_nonzero") (unique - 1) (CPrimOp PrimEq [remainder, zeroInt] boolTy)
  signsDiffer =
    boolXorCore (occurrence <> "_signs_differ") (unique - 2) (intLt lhs zeroInt) (intLt rhs zeroInt)
  needsAdjust =
    boolAndCore (occurrence <> "_needs_adjust") (unique - 4) remainderNonZero signsDiffer

rationalCoreType :: CoreType
rationalCoreType =
  ratioTy intTy

intPairCoreType :: CoreType
intPairCoreType =
  CTyTuple [intTy, intTy]

tuple2IntCore :: CoreExpr -> CoreExpr -> CoreExpr
tuple2IntCore lhs rhs =
  constructorApp (tupleDataConName 2) [intTy, intTy] [lhs, rhs] intPairCoreType

ratioIntCore :: CoreExpr -> CoreExpr -> CoreExpr
ratioIntCore numeratorExpr denominatorExpr =
  constructorApp ratioDataConName [intTy] [numeratorExpr, denominatorExpr] rationalCoreType

letCore :: RName -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr
letCore name ty rhs body =
  CLet (CoreNonRec (CoreBinder name ty) rhs) body (exprType body)

intSuccMethod :: CoreExpr
intSuccMethod =
  unaryMethod "$succ_int" (-1971) intTy intTy (`intAdd` oneInt)

intPredMethod :: CoreExpr
intPredMethod =
  unaryMethod "$pred_int" (-1972) intTy intTy (`intSub` oneInt)

intToEnumMethod :: CoreExpr
intToEnumMethod =
  unaryMethod "$toEnum_int" (-1973) intTy intTy id

intFromEnumMethod :: CoreExpr
intFromEnumMethod =
  unaryMethod "$fromEnum_int" (-1974) intTy intTy id

intEnumFromMethod :: CoreExpr
intEnumFromMethod =
  CVar enumFromIntName enumFromIntCoreType

intEnumFromThenMethod :: CoreExpr
intEnumFromThenMethod =
  CVar enumFromThenIntName enumFromThenIntCoreType

intEnumFromToMethod :: CoreExpr
intEnumFromToMethod =
  CVar enumFromToIntName enumFromToIntCoreType

intEnumFromThenToMethod :: CoreExpr
intEnumFromThenToMethod =
  CVar enumFromThenToIntName enumFromThenToIntCoreType

charSuccMethod :: CoreExpr
charSuccMethod =
  unaryMethod "$succ_char" (-1981) charTy charTy (intToCharCore . (`intAdd` oneInt) . charToIntCore)

charPredMethod :: CoreExpr
charPredMethod =
  unaryMethod "$pred_char" (-1982) charTy charTy (intToCharCore . (`intSub` oneInt) . charToIntCore)

charToEnumMethod :: CoreExpr
charToEnumMethod =
  unaryMethod "$toEnum_char" (-1983) intTy charTy intToCharCore

charFromEnumMethod :: CoreExpr
charFromEnumMethod =
  unaryMethod "$fromEnum_char" (-1984) charTy intTy charToIntCore

charEnumFromMethod :: CoreExpr
charEnumFromMethod =
  CVar enumFromCharName enumFromCharCoreType

charEnumFromThenMethod :: CoreExpr
charEnumFromThenMethod =
  CVar enumFromThenCharName enumFromThenCharCoreType

charEnumFromToMethod :: CoreExpr
charEnumFromToMethod =
  CVar enumFromToCharName enumFromToCharCoreType

charEnumFromThenToMethod :: CoreExpr
charEnumFromThenToMethod =
  CVar enumFromThenToCharName enumFromThenToCharCoreType

intMinBoundMethod :: CoreExpr
intMinBoundMethod =
  CLit (LInt (-9223372036854775808)) intTy

intMaxBoundMethod :: CoreExpr
intMaxBoundMethod =
  CLit (LInt 9223372036854775807) intTy

charMinBoundMethod :: CoreExpr
charMinBoundMethod =
  intToCharCore zeroInt

charMaxBoundMethod :: CoreExpr
charMaxBoundMethod =
  intToCharCore (CLit (LInt 1114111) intTy)

boolMinBoundMethod :: CoreExpr
boolMinBoundMethod =
  CCon falseDataConName boolTy

boolMaxBoundMethod :: CoreExpr
boolMaxBoundMethod =
  CCon trueDataConName boolTy

intShowsPrecMethod :: CoreExpr
intShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_int" (-1840) intTy (\value -> CPrimOp PrimShowInt [value] stringTy)

intShowMethod :: CoreExpr
intShowMethod =
  unaryPrimMethod "$show_int" (-1841) intTy stringTy PrimShowInt

intShowListMethod :: CoreExpr
intShowListMethod =
  showListFromShowsMethod intTy (showsPrecFromRenderedMethod "$show_list_shows_int" (-2401) intTy (\value -> CPrimOp PrimShowInt [value] stringTy))

boolShowsPrecMethod :: CoreExpr
boolShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_bool" (-1850) boolTy (\value -> CPrimOp PrimShowBool [value] stringTy)

boolShowMethod :: CoreExpr
boolShowMethod =
  unaryPrimMethod "$show_bool" (-1851) boolTy stringTy PrimShowBool

boolShowListMethod :: CoreExpr
boolShowListMethod =
  showListFromShowsMethod boolTy (showsPrecFromRenderedMethod "$show_list_shows_bool" (-2411) boolTy (\value -> CPrimOp PrimShowBool [value] stringTy))

charShowsPrecMethod :: CoreExpr
charShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_char" (-1880) charTy (showCharLiteralCoreWith "$shows_prec_char_case" (-1883))

charShowMethod :: CoreExpr
charShowMethod =
  unaryMethod "$show_char" (-1881) charTy stringTy showCharLiteralCore

charShowListMethod :: CoreExpr
charShowListMethod =
  binaryMethod "$show_char_list" (-1882) stringTy stringTy $ \value rest ->
    appendStringCore (showStringLiteralCore value) rest

stringShowsPrecMethod :: CoreExpr
stringShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_string" (-1890) stringTy showStringLiteralCore

stringShowMethod :: CoreExpr
stringShowMethod =
  unaryMethod "$show_string" (-1891) stringTy stringTy showStringLiteralCore

stringShowListMethod :: CoreExpr
stringShowListMethod =
  showListFromShowsMethod stringTy (showsPrecFromRenderedMethod "$show_list_shows_string" (-2421) stringTy showStringLiteralCore)

ioErrorTypeShowsPrecMethod :: CoreExpr
ioErrorTypeShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_io_error_type" (-2830) ioErrorTypeTy ioErrorTypeShowCore

ioErrorTypeShowMethod :: CoreExpr
ioErrorTypeShowMethod =
  unaryMethod "$show_io_error_type" (-2831) ioErrorTypeTy stringTy ioErrorTypeShowCore

ioErrorTypeShowListMethod :: CoreExpr
ioErrorTypeShowListMethod =
  showListFromShowsMethod ioErrorTypeTy (showsPrecFromRenderedMethod "$show_list_shows_io_error_type" (-2832) ioErrorTypeTy ioErrorTypeShowCore)

ioErrorTypeShowCore :: CoreExpr -> CoreExpr
ioErrorTypeShowCore value =
  CCase value (CoreBinder caseName ioErrorTypeTy) alts stringTy
 where
  caseName = builtinLocalTermName "$show_io_error_type_case" (-2833)
  alts =
    [ CoreAlt (ConstructorAlt ioErrorAlreadyExistsTypeDataConName) [] (stringLiteralCore "already exists")
    , CoreAlt (ConstructorAlt ioErrorDoesNotExistTypeDataConName) [] (stringLiteralCore "does not exist")
    , CoreAlt (ConstructorAlt ioErrorAlreadyInUseTypeDataConName) [] (stringLiteralCore "already in use")
    , CoreAlt (ConstructorAlt ioErrorFullTypeDataConName) [] (stringLiteralCore "resource exhausted")
    , CoreAlt (ConstructorAlt ioErrorEOFTypeDataConName) [] (stringLiteralCore "end of file")
    , CoreAlt (ConstructorAlt ioErrorIllegalOperationTypeDataConName) [] (stringLiteralCore "illegal operation")
    , CoreAlt (ConstructorAlt ioErrorPermissionTypeDataConName) [] (stringLiteralCore "permission denied")
    , CoreAlt (ConstructorAlt ioErrorUserTypeDataConName) [] (stringLiteralCore "user error")
    ]

orderingShowsPrecMethod, orderingShowMethod, orderingShowListMethod :: CoreExpr
orderingShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_ordering" (-2840) orderingTy orderingShowCore

orderingShowMethod =
  unaryMethod "$show_ordering" (-2841) orderingTy stringTy orderingShowCore

orderingShowListMethod =
  showListFromShowsMethod orderingTy (showsPrecFromRenderedMethod "$show_list_shows_ordering" (-2842) orderingTy orderingShowCore)

orderingShowCore :: CoreExpr -> CoreExpr
orderingShowCore value =
  orderingCaseCore
    "$show_ordering_case"
    (-2843)
    value
    stringTy
    (stringLiteralCore "LT")
    (stringLiteralCore "EQ")
    (stringLiteralCore "GT")

exitCodeShowsPrecMethod, exitCodeShowMethod, exitCodeShowListMethod :: CoreExpr
exitCodeShowsPrecMethod =
  CLam precBinder (CLam valueBinder (CLam restBinder body showSCoreType) (CTyFun exitCodeTy showSCoreType)) (showsPrecFunctionCoreType exitCodeTy)
 where
  precName = builtinLocalTermName "$shows_prec_exit_code_prec" (-2890)
  valueName = builtinLocalTermName "$shows_prec_exit_code_value" (-2891)
  restName = builtinLocalTermName "$shows_prec_exit_code_rest" (-2892)
  precBinder = CoreBinder precName intTy
  valueBinder = CoreBinder valueName exitCodeTy
  restBinder = CoreBinder restName stringTy
  body = appendStringCore (exitCodeShowWithPrecCore (CVar precName intTy) (CVar valueName exitCodeTy)) (CVar restName stringTy)

exitCodeShowMethod =
  unaryMethod "$show_exit_code" (-2893) exitCodeTy stringTy (exitCodeShowWithPrecCore (CLit (LInt 0) intTy))

exitCodeShowListMethod =
  showListFromShowsMethod exitCodeTy exitCodeShowsPrecMethod

exitCodeShowWithPrecCore :: CoreExpr -> CoreExpr -> CoreExpr
exitCodeShowWithPrecCore prec value =
  CCase value (CoreBinder caseName exitCodeTy) alts stringTy
 where
  caseName = builtinLocalTermName "$show_exit_code_case" (-2894)
  failureCode = builtinLocalTermName "$show_exit_code_failure" (-2895)
  failureBody =
    boolCaseCore
      "$show_exit_code_parens"
      (-2896)
      (intLt (CLit (LInt 10) intTy) prec)
      stringTy
      (appendStringCore (stringLiteralCore "(") (appendStringCore rawFailure (stringLiteralCore ")")))
      rawFailure
  rawFailure =
    appendStringCore (stringLiteralCore "ExitFailure ") (CPrimOp PrimShowInt [CVar failureCode intTy] stringTy)
  alts =
    [ CoreAlt (ConstructorAlt exitSuccessDataConName) [] (stringLiteralCore "ExitSuccess")
    , CoreAlt (ConstructorAlt exitFailureDataConName) [CoreBinder failureCode intTy] failureBody
    ]

unitShowsPrecMethod, unitShowMethod, unitShowListMethod :: CoreExpr
unitShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_unit" (-2850) unitTy (const (stringLiteralCore "()"))

unitShowMethod =
  unaryMethod "$show_unit" (-2851) unitTy stringTy (const (stringLiteralCore "()"))

unitShowListMethod =
  showListFromShowsMethod unitTy (showsPrecFromRenderedMethod "$show_list_shows_unit" (-2852) unitTy (const (stringLiteralCore "()")))

ratioShowsPrecMethod, ratioShowMethod, ratioShowListMethod :: CoreExpr
ratioShowsPrecMethod =
  CLam precBinder (CLam valueBinder (CLam restBinder methodBody showSCoreType) (CTyFun rationalCoreType showSCoreType)) (showsPrecFunctionCoreType rationalCoreType)
 where
  precName = builtinLocalTermName "$shows_prec_ratio_int_prec" (-2860)
  valueName = builtinLocalTermName "$shows_prec_ratio_int_value" (-2861)
  restName = builtinLocalTermName "$shows_prec_ratio_int_rest" (-2862)
  precBinder = CoreBinder precName intTy
  valueBinder = CoreBinder valueName rationalCoreType
  restBinder = CoreBinder restName stringTy
  rendered = ratioShowBodyCore (CVar valueName rationalCoreType)
  wrapped =
    boolCaseCore
      "$shows_prec_ratio_int_paren"
      (-2863)
      (intLt (CLit (LInt 7) intTy) (CVar precName intTy))
      stringTy
      (appendStringCore (stringLiteralCore "(") (appendStringCore rendered (stringLiteralCore ")")))
      rendered
  methodBody = appendStringCore wrapped (CVar restName stringTy)

ratioShowMethod =
  unaryMethod "$show_ratio_int" (-2864) rationalCoreType stringTy ratioShowBodyCore

ratioShowListMethod =
  showListFromShowsMethod rationalCoreType ratioShowsPrecMethod

ratioShowBodyCore :: CoreExpr -> CoreExpr
ratioShowBodyCore value =
  ratioCaseCore "$show_ratio_int_case" (-2865) value stringTy (-2866) (-2867) $ \n d ->
    appendStringCore (CPrimOp PrimShowInt [n] stringTy) (appendStringCore (stringLiteralCore " % ") (CPrimOp PrimShowInt [d] stringTy))

floatShowsPrecMethod, floatShowMethod, floatShowListMethod :: CoreExpr
floatShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_float" (-2870) floatTy (\value -> CPrimOp (PrimFloat FloatWidth FloatShow) [value] stringTy)
floatShowMethod =
  unaryPrimMethod "$show_float" (-2871) floatTy stringTy (PrimFloat FloatWidth FloatShow)
floatShowListMethod =
  showListFromShowsMethod floatTy floatShowsPrecMethod

doubleShowsPrecMethod, doubleShowMethod, doubleShowListMethod :: CoreExpr
doubleShowsPrecMethod =
  showsPrecFromRenderedMethod "$shows_prec_double" (-2880) doubleTy (\value -> CPrimOp (PrimFloat DoubleWidth FloatShow) [value] stringTy)
doubleShowMethod =
  unaryPrimMethod "$show_double" (-2881) doubleTy stringTy (PrimFloat DoubleWidth FloatShow)
doubleShowListMethod =
  showListFromShowsMethod doubleTy doubleShowsPrecMethod

intReadsPrecMethod, boolReadsPrecMethod, charReadsPrecMethod, orderingReadsPrecMethod, exitCodeReadsPrecMethod, unitReadsPrecMethod, ratioReadsPrecMethod :: CoreExpr
intReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_int" (-2707) intTy (CVar readIntName readIntCoreType)
boolReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_bool" (-2708) boolTy (CVar readBoolName readBoolCoreType)
charReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_char" (-2709) charTy (CVar readCharName readCharCoreType)
orderingReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_ordering" (-2710) orderingTy orderingReadParserCore
exitCodeReadsPrecMethod =
  coreLam precName intTy $
    applyCore
      ( applyCore
          (CTypeApp (CVar readParenName readParenCoreType) [exitCodeTy] (CTyFun boolTy (CTyFun exitCodeParserTy exitCodeParserTy)))
          (intLt (CLit (LInt 10) intTy) (CVar precName intTy))
          (CTyFun exitCodeParserTy exitCodeParserTy)
      )
      exitCodeReadParserCore
      exitCodeParserTy
 where
  precName = builtinLocalTermName "$reads_prec_exit_code_prec" (-2722)
  exitCodeParserTy = readSCoreType exitCodeTy
unitReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_unit" (-2711) unitTy unitReadParserCore
ratioReadsPrecMethod =
  coreLam precName intTy $
    applyCore
      ( applyCore
          (CTypeApp (CVar readParenName readParenCoreType) [rationalCoreType] (CTyFun boolTy (CTyFun ratioParserTy ratioParserTy)))
          (intLt (CLit (LInt 7) intTy) (CVar precName intTy))
          (CTyFun ratioParserTy ratioParserTy)
      )
      ratioReadParserCore
      ratioParserTy
 where
  precName = builtinLocalTermName "$reads_prec_ratio_int_prec" (-2714)
  ratioParserTy = readSCoreType rationalCoreType

intReadListMethod, boolReadListMethod, charReadListMethod, orderingReadListMethod, exitCodeReadListMethod, unitReadListMethod, ratioReadListMethod :: CoreExpr
intReadListMethod =
  readListFromParserMethod intTy (CVar readIntName readIntCoreType)
boolReadListMethod =
  readListFromParserMethod boolTy (CVar readBoolName readBoolCoreType)
charReadListMethod =
  CVar readStringName readStringCoreType
orderingReadListMethod =
  readListFromParserMethod orderingTy orderingReadParserCore
exitCodeReadListMethod =
  readListFromParserMethod exitCodeTy exitCodeReadParserCore
unitReadListMethod =
  readListFromParserMethod unitTy unitReadParserCore
ratioReadListMethod =
  readListFromParserMethod rationalCoreType ratioReadParserCore

readsPrecFromParserMethod :: Text -> Int -> CoreType -> CoreExpr -> CoreExpr
readsPrecFromParserMethod occurrence unique _valueTy parser =
  coreLam (builtinLocalTermName (occurrence <> "_prec") unique) intTy parser

readListFromParserMethod :: CoreType -> CoreExpr -> CoreExpr
readListFromParserMethod valueTy parser =
  applyCore
    (CTypeApp (CVar readDefaultListName readDefaultListCoreType) [valueTy] (CTyFun (readSCoreType valueTy) (readSCoreType (CTyList valueTy))))
    parser
    (readSCoreType (CTyList valueTy))

orderingReadParserCore :: CoreExpr
orderingReadParserCore =
  coreLam inputName stringTy body
 where
  inputName = builtinLocalTermName "$read_ordering_input" (-2712)
  input = CVar inputName stringTy
  body =
    readAppendCallCore
      (readResultCoreType orderingTy)
      (readConstantParserCore orderingTy "LT" (CCon orderingLTDataConName orderingTy) input)
      ( readAppendCallCore
          (readResultCoreType orderingTy)
          (readConstantParserCore orderingTy "EQ" (CCon orderingEQDataConName orderingTy) input)
          (readConstantParserCore orderingTy "GT" (CCon orderingGTDataConName orderingTy) input)
      )

exitCodeReadParserCore :: CoreExpr
exitCodeReadParserCore =
  coreLam inputName stringTy body
 where
  inputName = builtinLocalTermName "$read_exit_code_input" (-2723)
  afterConstructorName = builtinLocalTermName "$read_exit_code_after_constructor" (-2724)
  constructorUnitName = builtinLocalTermName "$read_exit_code_constructor_unit" (-2725)
  codeName = builtinLocalTermName "$read_exit_code_failure_code" (-2726)
  restName = builtinLocalTermName "$read_exit_code_failure_rest" (-2727)
  input = CVar inputName stringTy
  successParser =
    readConstantParserCore exitCodeTy "ExitSuccess" (CCon exitSuccessDataConName exitCodeTy) input
  failureParser =
    readBindCallCore
      unitTy
      exitCodeTy
      (readExactCallCore "ExitFailure" input)
      ( coreLam constructorUnitName unitTy $
          coreLam afterConstructorName stringTy $
            readBindCallCore
              intTy
              exitCodeTy
              (applyCore (CVar readIntName readIntCoreType) (CVar afterConstructorName stringTy) (readResultsCoreType intTy))
              ( coreLam codeName intTy $
                  coreLam restName stringTy $
                    readSingleResultCore
                      exitCodeTy
                      (constructorApp exitFailureDataConName [] [CVar codeName intTy] exitCodeTy)
                      (CVar restName stringTy)
              )
      )
  body =
    readAppendCallCore (readResultCoreType exitCodeTy) successParser failureParser

unitReadParserCore :: CoreExpr
unitReadParserCore =
  coreLam inputName stringTy (readConstantParserCore unitTy "()" (CCon unitDataConName unitTy) (CVar inputName stringTy))
 where
  inputName = builtinLocalTermName "$read_unit_input" (-2713)

ratioReadParserCore :: CoreExpr
ratioReadParserCore =
  coreLam inputName stringTy $
    readBindCallCore
      intTy
      rationalCoreType
      (applyCore (CVar readIntName readIntCoreType) (CVar inputName stringTy) (readResultsCoreType intTy))
      ( coreLam numeratorName intTy $
          coreLam afterNumeratorName stringTy $
            readBindCallCore
              unitTy
              rationalCoreType
              (readExactCallCore "%" (CVar afterNumeratorName stringTy))
              ( coreLam percentName unitTy $
                  coreLam afterPercentName stringTy $
                    readBindCallCore
                      intTy
                      rationalCoreType
                      (applyCore (CVar readIntName readIntCoreType) (CVar afterPercentName stringTy) (readResultsCoreType intTy))
                      ( coreLam denominatorName intTy $
                          coreLam restName stringTy $
                            readSingleResultCore
                              rationalCoreType
                              (ratioReduceCall (CVar numeratorName intTy) (CVar denominatorName intTy))
                              (CVar restName stringTy)
                      )
              )
      )
 where
  inputName = builtinLocalTermName "$read_ratio_int_input" (-2715)
  numeratorName = builtinLocalTermName "$read_ratio_int_numerator" (-2716)
  afterNumeratorName = builtinLocalTermName "$read_ratio_int_after_numerator" (-2717)
  percentName = builtinLocalTermName "$read_ratio_int_percent" (-2718)
  afterPercentName = builtinLocalTermName "$read_ratio_int_after_percent" (-2719)
  denominatorName = builtinLocalTermName "$read_ratio_int_denominator" (-2720)
  restName = builtinLocalTermName "$read_ratio_int_rest" (-2721)

ioFunctorFmapMethod :: CoreExpr
ioFunctorFmapMethod =
  CTypeLam [a, b] (lam function (CTyFun aTy bTy) (lam action ioA body)) ioFunctorFmapCoreType
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  ioA = ioTy aTy
  ioB = ioTy bTy
  function = builtinLocalTermName "$io_functor_fmap_f" (-2260)
  action = builtinLocalTermName "$io_functor_fmap_action" (-2261)
  value = builtinLocalTermName "$io_functor_fmap_value" (-2262)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  var name ty = CVar name ty
  mappedValue =
    CApp (var function (CTyFun aTy bTy)) (var value aTy) bTy
  continuation =
    CLam (CoreBinder value aTy) (CPrimOp PrimIOReturn [mappedValue] ioB) (CTyFun aTy ioB)
  body =
    CPrimOp PrimIOBind [var action ioA, continuation] ioB

maybeFunctorFmapMethod :: CoreExpr
maybeFunctorFmapMethod =
  CTypeLam [a, b] (lam function (CTyFun aTy bTy) (lam value maybeA body)) maybeFunctorFmapCoreType
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  maybeB = CTyApp (CTyCon maybeTyConName) bTy
  function = builtinLocalTermName "$maybe_functor_fmap_f" (-2263)
  value = builtinLocalTermName "$maybe_functor_fmap_value" (-2264)
  justValue = builtinLocalTermName "$maybe_functor_fmap_just" (-2265)
  caseName = builtinLocalTermName "$maybe_functor_fmap_case" (-2266)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    CCase
      (CVar value maybeA)
      (CoreBinder caseName maybeA)
      [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (nothingCore bTy)
      , CoreAlt
          (ConstructorAlt maybeJustDataConName)
          [CoreBinder justValue aTy]
          (justCore bTy (CApp (CVar function (CTyFun aTy bTy)) (CVar justValue aTy) bTy))
      ]
      maybeB

listFunctorFmapMethod :: CoreExpr
listFunctorFmapMethod =
  CTypeLam [a, b] (lam functionName (CTyFun aTy bTy) (lam xsName listA body)) listFunctorFmapCoreType
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy
  functionName = builtinLocalTermName "$list_functor_fmap_f" (-2267)
  xsName = builtinLocalTermName "$list_functor_fmap_xs" (-2268)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    CApp
      ( CApp
          (CTypeApp (CVar functorListMapName listFunctorFmapCoreType) [aTy, bTy] (CTyFun (CTyFun aTy bTy) (CTyFun listA listB)))
          (CVar functionName (CTyFun aTy bTy))
          (CTyFun listA listB)
      )
      (CVar xsName listA)
      listB

ioMonadBindMethod :: CoreExpr
ioMonadBindMethod =
  CTypeLam [a, b] (lam first ioA (lam continuation (CTyFun aTy ioB) (CPrimOp PrimIOBind [var first ioA, var continuation (CTyFun aTy ioB)] ioB))) ioMonadBindCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  ioA = ioTy aTy
  ioB = ioTy bTy
  first = builtinLocalTermName "$io_monad_bind_first" (-2201)
  continuation = builtinLocalTermName "$io_monad_bind_k" (-2202)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

ioMonadThenMethod :: CoreExpr
ioMonadThenMethod =
  CTypeLam [a, b] (lam first ioA (lam second ioB (CPrimOp PrimIOThen [var first ioA, var second ioB] ioB))) ioMonadThenCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  ioA = ioTy aTy
  ioB = ioTy bTy
  first = builtinLocalTermName "$io_monad_then_first" (-2203)
  second = builtinLocalTermName "$io_monad_then_second" (-2204)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

ioMonadReturnMethod :: CoreExpr
ioMonadReturnMethod =
  CTypeLam [a] (lam value aTy (CPrimOp PrimIOReturn [var value aTy] (ioTy aTy))) ioMonadReturnCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  value = builtinLocalTermName "$io_monad_return_x" (-2205)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

ioMonadFailMethod :: CoreExpr
ioMonadFailMethod =
  CTypeLam [a] (lam message stringTy (CPrimOp PrimIOFail [var message stringTy] (ioTy aTy))) ioMonadFailCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  message = builtinLocalTermName "$io_monad_fail_message" (-2206)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

maybeMonadBindMethod :: CoreExpr
maybeMonadBindMethod =
  CTypeLam [a, b] (lam value maybeA (lam continuation (CTyFun aTy maybeB) body)) maybeMonadBindCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  maybeB = CTyApp (CTyCon maybeTyConName) bTy
  value = builtinLocalTermName "$maybe_monad_bind_value" (-2210)
  continuation = builtinLocalTermName "$maybe_monad_bind_k" (-2211)
  justValue = builtinLocalTermName "$maybe_monad_bind_just" (-2212)
  caseName = builtinLocalTermName "$maybe_monad_bind_case" (-2213)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    CCase
      (CVar value maybeA)
      (CoreBinder caseName maybeA)
      [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (nothingCore bTy)
      , CoreAlt
          (ConstructorAlt maybeJustDataConName)
          [CoreBinder justValue aTy]
          (CApp (CVar continuation (CTyFun aTy maybeB)) (CVar justValue aTy) maybeB)
      ]
      maybeB

maybeMonadThenMethod :: CoreExpr
maybeMonadThenMethod =
  CTypeLam [a, b] (lam first maybeA (lam second maybeB body)) maybeMonadThenCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  maybeB = CTyApp (CTyCon maybeTyConName) bTy
  first = builtinLocalTermName "$maybe_monad_then_first" (-2214)
  second = builtinLocalTermName "$maybe_monad_then_second" (-2215)
  ignored = builtinLocalTermName "$maybe_monad_then_ignored" (-2216)
  caseName = builtinLocalTermName "$maybe_monad_then_case" (-2217)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    CCase
      (CVar first maybeA)
      (CoreBinder caseName maybeA)
      [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (nothingCore bTy)
      , CoreAlt (ConstructorAlt maybeJustDataConName) [CoreBinder ignored aTy] (CVar second maybeB)
      ]
      maybeB

maybeMonadReturnMethod :: CoreExpr
maybeMonadReturnMethod =
  CTypeLam [a] (lam value aTy (justCore aTy (var value aTy))) maybeMonadReturnCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  value = builtinLocalTermName "$maybe_monad_return_x" (-2218)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

maybeMonadFailMethod :: CoreExpr
maybeMonadFailMethod =
  CTypeLam [a] (lam message stringTy (nothingCore aTy)) maybeMonadFailCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  message = builtinLocalTermName "$maybe_monad_fail_message" (-2219)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))

listMonadBindMethod :: CoreExpr
listMonadBindMethod =
  CVar monadListBindName monadListBindCoreType

listMonadThenMethod :: CoreExpr
listMonadThenMethod =
  CTypeLam [a, b] (lam first listA (lam second listB body)) listMonadThenCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy
  first = builtinLocalTermName "$list_monad_then_first" (-2220)
  second = builtinLocalTermName "$list_monad_then_second" (-2221)
  ignored = builtinLocalTermName "$list_monad_then_ignored" (-2222)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    CApp
      ( CApp
          (CTypeApp (CVar monadListBindName monadListBindCoreType) [aTy, bTy] (CTyFun listA (CTyFun (CTyFun aTy listB) listB)))
          (CVar first listA)
          (CTyFun (CTyFun aTy listB) listB)
      )
      (CLam (CoreBinder ignored aTy) (CVar second listB) (CTyFun aTy listB))
      listB

listMonadReturnMethod :: CoreExpr
listMonadReturnMethod =
  CTypeLam [a] (lam value aTy (consCore aTy (var value aTy) (nilCore aTy))) listMonadReturnCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  value = builtinLocalTermName "$list_monad_return_x" (-2223)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))
  var name ty = CVar name ty

listMonadFailMethod :: CoreExpr
listMonadFailMethod =
  CTypeLam [a] (lam message stringTy (nilCore aTy)) listMonadFailCoreType
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  message = builtinLocalTermName "$list_monad_fail_message" (-2224)
  lam binderName ty body = CLam (CoreBinder binderName ty) body (CTyFun ty (exprType body))

maybeMonadPlusMzeroMethod :: CoreExpr
maybeMonadPlusMzeroMethod =
  CTypeLam [a] (nothingCore aTy) maybeMonadPlusMzeroCoreType
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a

maybeMonadPlusMplusMethod :: CoreExpr
maybeMonadPlusMplusMethod =
  CTypeLam [a] (coreLam lhs maybeA (coreLam rhs maybeA body)) maybeMonadPlusMplusCoreType
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  lhs = builtinLocalTermName "$maybe_monadplus_mplus_lhs" (-2242)
  rhs = builtinLocalTermName "$maybe_monadplus_mplus_rhs" (-2243)
  justValue = builtinLocalTermName "$maybe_monadplus_mplus_just" (-2244)
  caseName = builtinLocalTermName "$maybe_monadplus_mplus_case" (-2245)
  body =
    CCase
      (CVar lhs maybeA)
      (CoreBinder caseName maybeA)
      [ CoreAlt (ConstructorAlt maybeNothingDataConName) [] (CVar rhs maybeA)
      , CoreAlt (ConstructorAlt maybeJustDataConName) [CoreBinder justValue aTy] (justCore aTy (CVar justValue aTy))
      ]
      maybeA

listMonadPlusMzeroMethod :: CoreExpr
listMonadPlusMzeroMethod =
  CTypeLam [a] (nilCore aTy) listMonadPlusMzeroCoreType
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a

listMonadPlusMplusMethod :: CoreExpr
listMonadPlusMplusMethod =
  CTypeLam [a] (coreLam lhs listA (coreLam rhs listA body)) listMonadPlusMplusCoreType
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a
  listA = CTyList aTy
  lhs = builtinLocalTermName "$list_monadplus_mplus_lhs" (-2246)
  rhs = builtinLocalTermName "$list_monadplus_mplus_rhs" (-2247)
  body =
    applyCore
      ( applyCore
          (CTypeApp (CVar monadListAppendName monadListAppendCoreType) [aTy] (CTyFun listA (CTyFun listA listA)))
          (CVar lhs listA)
          (CTyFun listA listA)
      )
      (CVar rhs listA)
      listA

ioMonadBindCoreType, ioMonadThenCoreType, ioMonadReturnCoreType, ioMonadFailCoreType :: CoreType
ioMonadBindCoreType = monadBindFieldCoreType (CTyCon ioTyConName)
ioMonadThenCoreType = monadThenFieldCoreType (CTyCon ioTyConName)
ioMonadReturnCoreType = monadReturnFieldCoreType (CTyCon ioTyConName)
ioMonadFailCoreType = monadFailFieldCoreType (CTyCon ioTyConName)

maybeMonadBindCoreType, maybeMonadThenCoreType, maybeMonadReturnCoreType, maybeMonadFailCoreType :: CoreType
maybeMonadBindCoreType = monadBindFieldCoreType (CTyCon maybeTyConName)
maybeMonadThenCoreType = monadThenFieldCoreType (CTyCon maybeTyConName)
maybeMonadReturnCoreType = monadReturnFieldCoreType (CTyCon maybeTyConName)
maybeMonadFailCoreType = monadFailFieldCoreType (CTyCon maybeTyConName)

ioFunctorFmapCoreType, maybeFunctorFmapCoreType, listFunctorFmapCoreType :: CoreType
ioFunctorFmapCoreType = functorFmapFieldCoreType (CTyCon ioTyConName)
maybeFunctorFmapCoreType = functorFmapFieldCoreType (CTyCon maybeTyConName)
listFunctorFmapCoreType = functorFmapFieldCoreType listTyConCore

functorFmapFieldCoreType :: CoreType -> CoreType
functorFmapFieldCoreType functorTy =
  CTyForall [a, b] (CTyFun (CTyFun aTy bTy) (CTyFun functorA functorB))
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  functorA = applyFunctorCoreType functorTy aTy
  functorB = applyFunctorCoreType functorTy bTy

applyFunctorCoreType :: CoreType -> CoreType -> CoreType
applyFunctorCoreType functorTy argumentTy
  | functorTy == listTyConCore = CTyList argumentTy
  | otherwise = CTyApp functorTy argumentTy

listMonadThenCoreType, listMonadReturnCoreType, listMonadFailCoreType :: CoreType
listMonadThenCoreType = monadThenFieldCoreType listTyConCore
listMonadReturnCoreType = monadReturnFieldCoreType listTyConCore
listMonadFailCoreType = monadFailFieldCoreType listTyConCore

maybeMonadPlusMzeroCoreType, maybeMonadPlusMplusCoreType :: CoreType
maybeMonadPlusMzeroCoreType = monadPlusMzeroFieldCoreType (CTyCon maybeTyConName)
maybeMonadPlusMplusCoreType = monadPlusMplusFieldCoreType (CTyCon maybeTyConName)

listMonadPlusMzeroCoreType, listMonadPlusMplusCoreType :: CoreType
listMonadPlusMzeroCoreType = monadPlusMzeroFieldCoreType listTyConCore
listMonadPlusMplusCoreType = monadPlusMplusFieldCoreType listTyConCore

monadBindFieldCoreType :: CoreType -> CoreType
monadBindFieldCoreType monadTy =
  CTyForall [a, b] (CTyFun monadA (CTyFun (CTyFun aTy monadB) monadB))
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  monadA = applyMonadCoreType monadTy aTy
  monadB = applyMonadCoreType monadTy bTy

monadThenFieldCoreType :: CoreType -> CoreType
monadThenFieldCoreType monadTy =
  CTyForall [a, b] (CTyFun monadA (CTyFun monadB monadB))
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  monadA = applyMonadCoreType monadTy aTy
  monadB = applyMonadCoreType monadTy bTy

monadReturnFieldCoreType :: CoreType -> CoreType
monadReturnFieldCoreType monadTy =
  CTyForall [a] (CTyFun aTy (applyMonadCoreType monadTy aTy))
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a

monadFailFieldCoreType :: CoreType -> CoreType
monadFailFieldCoreType monadTy =
  CTyForall [a] (CTyFun stringTy (applyMonadCoreType monadTy aTy))
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a

monadPlusMzeroFieldCoreType :: CoreType -> CoreType
monadPlusMzeroFieldCoreType monadTy =
  CTyForall [a] (applyMonadCoreType monadTy aTy)
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a

monadPlusMplusFieldCoreType :: CoreType -> CoreType
monadPlusMplusFieldCoreType monadTy =
  CTyForall [a] (CTyFun monadA (CTyFun monadA monadA))
 where
  a = preludeTypeVariable "a" (-1397)
  aTy = CTyVar a
  monadA = applyMonadCoreType monadTy aTy

applyMonadCoreType :: CoreType -> CoreType -> CoreType
applyMonadCoreType monadTy argumentTy
  | monadTy == listTyConCore = CTyList argumentTy
  | otherwise = CTyApp monadTy argumentTy

listTyConCore :: CoreType
listTyConCore =
  CTyCon listTyConName

monadListAppendName :: RName
monadListAppendName =
  preludeTermName "$monad_list_append" (-2230)

monadListBindName :: RName
monadListBindName =
  preludeTermName "$monad_list_bind" (-2231)

monadListAppendCoreType :: CoreType
monadListAppendCoreType =
  CTyForall [a] (CTyFun listA (CTyFun listA listA))
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  listA = CTyList aTy

monadListBindCoreType :: CoreType
monadListBindCoreType =
  CTyForall [a, b] (CTyFun listA (CTyFun (CTyFun aTy listB) listB))
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy

nothingCore :: CoreType -> CoreExpr
nothingCore elementTy =
  constructorApp maybeNothingDataConName [elementTy] [] (CTyApp (CTyCon maybeTyConName) elementTy)

justCore :: CoreType -> CoreExpr -> CoreExpr
justCore elementTy value =
  constructorApp maybeJustDataConName [elementTy] [value] (CTyApp (CTyCon maybeTyConName) elementTy)

binaryPrimMethod :: Text -> Int -> CoreType -> CoreType -> CorePrimOp -> CoreExpr
binaryPrimMethod occurrence unique argumentTy resultTy prim =
  binaryMethod occurrence unique argumentTy resultTy (\lhs rhs -> CPrimOp prim [lhs, rhs] resultTy)

binaryBoolMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
binaryBoolMethod occurrence unique argumentTy body =
  binaryMethod occurrence unique argumentTy boolTy body

binaryMethod :: Text -> Int -> CoreType -> CoreType -> (CoreExpr -> CoreExpr -> CoreExpr) -> CoreExpr
binaryMethod occurrence unique argumentTy resultTy body =
  CLam lhsBinder (CLam rhsBinder methodBody (CTyFun argumentTy resultTy)) (CTyFun argumentTy (CTyFun argumentTy resultTy))
 where
  lhsName = builtinLocalTermName (occurrence <> "_lhs") unique
  rhsName = builtinLocalTermName (occurrence <> "_rhs") (unique - 1)
  lhsBinder = CoreBinder lhsName argumentTy
  rhsBinder = CoreBinder rhsName argumentTy
  lhs = CVar lhsName argumentTy
  rhs = CVar rhsName argumentTy
  methodBody = body lhs rhs

unaryPrimMethod :: Text -> Int -> CoreType -> CoreType -> CorePrimOp -> CoreExpr
unaryPrimMethod occurrence unique argumentTy resultTy prim =
  unaryMethod occurrence unique argumentTy resultTy (\value -> CPrimOp prim [value] resultTy)

unaryMethod :: Text -> Int -> CoreType -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
unaryMethod occurrence unique argumentTy resultTy body =
  CLam valueBinder methodBody (CTyFun argumentTy resultTy)
 where
  valueName = builtinLocalTermName (occurrence <> "_x") unique
  valueBinder = CoreBinder valueName argumentTy
  value = CVar valueName argumentTy
  methodBody = body value

boolNotCore :: Text -> Int -> CoreExpr -> CoreExpr
boolNotCore binderOccurrence binderUnique scrutinee =
  boolCaseCore binderOccurrence binderUnique scrutinee boolTy (CCon falseDataConName boolTy) (CCon trueDataConName boolTy)

boolAndCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
boolAndCore binderOccurrence binderUnique lhs rhs =
  boolCaseCore binderOccurrence binderUnique lhs boolTy rhs (CCon falseDataConName boolTy)

boolXorCore :: Text -> Int -> CoreExpr -> CoreExpr -> CoreExpr
boolXorCore binderOccurrence binderUnique lhs rhs =
  boolCaseCore
    binderOccurrence
    binderUnique
    lhs
    boolTy
    (boolNotCore (binderOccurrence <> "_not") (binderUnique - 1) rhs)
    rhs

boolCaseCore :: Text -> Int -> CoreExpr -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr
boolCaseCore binderOccurrence binderUnique scrutinee resultTy trueBody falseBody =
  CCase
    scrutinee
    (CoreBinder (builtinLocalTermName binderOccurrence binderUnique) boolTy)
    [ CoreAlt (ConstructorAlt trueDataConName) [] trueBody
    , CoreAlt (ConstructorAlt falseDataConName) [] falseBody
    ]
    resultTy

orderingCaseCore :: Text -> Int -> CoreExpr -> CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
orderingCaseCore binderOccurrence binderUnique scrutinee resultTy ltBody eqBody gtBody =
  CCase
    scrutinee
    (CoreBinder (builtinLocalTermName binderOccurrence binderUnique) orderingTy)
    [ CoreAlt (ConstructorAlt orderingLTDataConName) [] ltBody
    , CoreAlt (ConstructorAlt orderingEQDataConName) [] eqBody
    , CoreAlt (ConstructorAlt orderingGTDataConName) [] gtBody
    ]
    resultTy

builtinEqSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinEqSupportCoreBinds classes =
  case Map.lookup builtinEqClassName classes of
    Nothing -> Right []
    Just info -> do
      listDictionaryPair <- eqListDictionaryCorePair info
      pure
        [ CoreRec
            [ eqListMethodCorePair
            , listDictionaryPair
            ]
        ]

eqListTypeVariable :: RName
eqListTypeVariable =
  preludeTypeVariable "a" (-8061)

eqListDictionaryName :: RName
eqListDictionaryName =
  preludeTermName "$fEqList" (-1504)

eqListMethodName :: RName
eqListMethodName =
  preludeTermName "$eq_list" (-8062)

eqDictCoreType :: CoreType -> CoreType
eqDictCoreType ty =
  CTyApp (CTyCon (classDictionaryTypeName builtinEqClassName)) ty

eqListDictionaryCoreType :: CoreType
eqListDictionaryCoreType =
  CTyForall [a] (CTyFun eqDictA eqDictListA)
 where
  a = eqListTypeVariable
  aTy = CTyVar a
  eqDictA = eqDictCoreType aTy
  eqDictListA = eqDictCoreType (CTyList aTy)

eqListMethodCoreType :: CoreType
eqListMethodCoreType =
  CTyForall [a] (CTyFun eqDictA (CTyFun listA (CTyFun listA boolTy)))
 where
  a = eqListTypeVariable
  aTy = CTyVar a
  eqDictA = eqDictCoreType aTy
  listA = CTyList aTy

eqSelectorCoreType :: CoreType
eqSelectorCoreType =
  CTyForall [a] (CTyFun eqDictA (CTyFun aTy (CTyFun aTy boolTy)))
 where
  a = preludeTypeVariable "a" (-1301)
  aTy = CTyVar a
  eqDictA = eqDictCoreType aTy

eqListMethodCorePair :: (CoreBinder, CoreExpr)
eqListMethodCorePair =
  (CoreBinder eqListMethodName eqListMethodCoreType, CTypeLam [a] (lam dictName eqDictA (lam xsName listA (lam ysName listA body))) eqListMethodCoreType)
 where
  a = eqListTypeVariable
  aTy = CTyVar a
  listA = CTyList aTy
  eqDictA = eqDictCoreType aTy
  dictName = builtinLocalTermName "$eq_list_dict" (-8063)
  xsName = builtinLocalTermName "$eq_list_xs" (-8064)
  ysName = builtinLocalTermName "$eq_list_ys" (-8065)
  xName = builtinLocalTermName "$eq_list_x" (-8066)
  xsTailName = builtinLocalTermName "$eq_list_xs_tail" (-8067)
  yNilName = builtinLocalTermName "$eq_list_y_nil" (-8068)
  ysNilTailName = builtinLocalTermName "$eq_list_ys_nil_tail" (-8069)
  yConsName = builtinLocalTermName "$eq_list_y_cons" (-8070)
  ysConsTailName = builtinLocalTermName "$eq_list_ys_cons_tail" (-8071)
  xsCaseName = builtinLocalTermName "$eq_list_xs_case" (-8072)
  ysNilCaseName = builtinLocalTermName "$eq_list_ys_nil_case" (-8073)
  ysConsCaseName = builtinLocalTermName "$eq_list_ys_cons_case" (-8074)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  falseExpr = CCon falseDataConName boolTy
  trueExpr = CCon trueDataConName boolTy
  dictExpr = CVar dictName eqDictA
  xsTail = CVar xsTailName listA
  ysConsTail = CVar ysConsTailName listA
  headEqual =
    eqElementCore aTy dictExpr (CVar xName aTy) (CVar yConsName aTy)
  recursiveTailEqual =
    eqListCallCore aTy dictExpr xsTail ysConsTail
  consBody =
    listCaseCore
      (CVar ysName listA)
      ysConsCaseName
      aTy
      boolTy
      falseExpr
      yConsName
      ysConsTailName
      (boolCaseCore "$eq_list_head" (-8075) headEqual boolTy recursiveTailEqual falseExpr)
  body =
    listCaseCore
      (CVar xsName listA)
      xsCaseName
      aTy
      boolTy
      ( listCaseCore
          (CVar ysName listA)
          ysNilCaseName
          aTy
          boolTy
          trueExpr
          yNilName
          ysNilTailName
          falseExpr
      )
      xName
      xsTailName
      consBody

eqListDictionaryCorePair :: ClassInfo -> Either TypecheckError (CoreBinder, CoreExpr)
eqListDictionaryCorePair info = do
  constructorTy <- classDictionaryConstructorCoreType info
  let a = eqListTypeVariable
      aTy = CTyVar a
      listA = CTyList aTy
      eqDictA = eqDictCoreType aTy
      eqDictListA = eqDictCoreType listA
      dictName = builtinLocalTermName "$eq_list_instance_dict" (-8076)
      xsName = builtinLocalTermName "$neq_list_xs" (-8077)
      ysName = builtinLocalTermName "$neq_list_ys" (-8078)
      eqMethod =
        CApp
          ( CTypeApp
              (CVar eqListMethodName eqListMethodCoreType)
              [aTy]
              (CTyFun eqDictA (CTyFun listA (CTyFun listA boolTy)))
          )
          (CVar dictName eqDictA)
          (CTyFun listA (CTyFun listA boolTy))
      neqBody =
        boolNotCore
          "$neq_list_not"
          (-8079)
          ( CApp
              (CApp eqMethod (CVar xsName listA) (CTyFun listA boolTy))
              (CVar ysName listA)
              boolTy
          )
      neqMethod =
        CLam
          (CoreBinder xsName listA)
          (CLam (CoreBinder ysName listA) neqBody (CTyFun listA boolTy))
          (CTyFun listA (CTyFun listA boolTy))
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [listA]
          (CTyFun (exprType eqMethod) (CTyFun (exprType neqMethod) eqDictListA))
      body = CApp (CApp typedConstructor eqMethod (CTyFun (exprType neqMethod) eqDictListA)) neqMethod eqDictListA
      rhs = CTypeLam [a] (CLam (CoreBinder dictName eqDictA) body (CTyFun eqDictA eqDictListA)) eqListDictionaryCoreType
  pure (CoreBinder eqListDictionaryName eqListDictionaryCoreType, rhs)

eqElementCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
eqElementCore elementTy dictionary lhs rhs =
  CApp (CApp eqFunction lhs (CTyFun elementTy boolTy)) rhs boolTy
 where
  dictionaryTy = eqDictCoreType elementTy
  eqFunction =
    CApp
      (CTypeApp (CVar (preludeTermName "==" (-1401)) eqSelectorCoreType) [elementTy] (CTyFun dictionaryTy (CTyFun elementTy (CTyFun elementTy boolTy))))
      dictionary
      (CTyFun elementTy (CTyFun elementTy boolTy))

eqListCallCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
eqListCallCore elementTy dictionary lhs rhs =
  CApp (CApp eqFunction lhs (CTyFun listTy boolTy)) rhs boolTy
 where
  listTy = CTyList elementTy
  dictionaryTy = eqDictCoreType elementTy
  eqFunction =
    CApp
      (CTypeApp (CVar eqListMethodName eqListMethodCoreType) [elementTy] (CTyFun dictionaryTy (CTyFun listTy (CTyFun listTy boolTy))))
      dictionary
      (CTyFun listTy (CTyFun listTy boolTy))

builtinOrdSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinOrdSupportCoreBinds classes =
  case Map.lookup builtinOrdClassName classes of
    Nothing -> Right []
    Just info -> do
      listDictionaryPair <- ordListDictionaryCorePair info
      pure
        [ CoreRec
            [ ordListCompareMethodCorePair
            , listDictionaryPair
            ]
        ]

ordListTypeVariable :: RName
ordListTypeVariable =
  preludeTypeVariable "a" (-8081)

ordListDictionaryName :: RName
ordListDictionaryName =
  preludeTermName "$fOrdList" (-1514)

ordListCompareMethodName :: RName
ordListCompareMethodName =
  preludeTermName "$compare_list" (-8082)

ordDictCoreType :: CoreType -> CoreType
ordDictCoreType ty =
  CTyApp (CTyCon (classDictionaryTypeName builtinOrdClassName)) ty

ordListDictionaryCoreType :: CoreType
ordListDictionaryCoreType =
  CTyForall [a] (CTyFun ordDictA ordDictListA)
 where
  a = ordListTypeVariable
  aTy = CTyVar a
  ordDictA = ordDictCoreType aTy
  ordDictListA = ordDictCoreType (CTyList aTy)

ordListCompareMethodCoreType :: CoreType
ordListCompareMethodCoreType =
  CTyForall [a] (CTyFun ordDictA (CTyFun listA (CTyFun listA orderingTy)))
 where
  a = ordListTypeVariable
  aTy = CTyVar a
  ordDictA = ordDictCoreType aTy
  listA = CTyList aTy

ordSelectorCoreType :: CoreType
ordSelectorCoreType =
  CTyForall [a] (CTyFun ordDictA (CTyFun aTy (CTyFun aTy orderingTy)))
 where
  a = preludeTypeVariable "a" (-1311)
  aTy = CTyVar a
  ordDictA = ordDictCoreType aTy

ordListCompareMethodCorePair :: (CoreBinder, CoreExpr)
ordListCompareMethodCorePair =
  (CoreBinder ordListCompareMethodName ordListCompareMethodCoreType, CTypeLam [a] (lam dictName ordDictA (lam xsName listA (lam ysName listA body))) ordListCompareMethodCoreType)
 where
  a = ordListTypeVariable
  aTy = CTyVar a
  listA = CTyList aTy
  ordDictA = ordDictCoreType aTy
  dictName = builtinLocalTermName "$compare_list_dict" (-8083)
  xsName = builtinLocalTermName "$compare_list_xs" (-8084)
  ysName = builtinLocalTermName "$compare_list_ys" (-8085)
  xName = builtinLocalTermName "$compare_list_x" (-8086)
  xsTailName = builtinLocalTermName "$compare_list_xs_tail" (-8087)
  yNilName = builtinLocalTermName "$compare_list_y_nil" (-8088)
  ysNilTailName = builtinLocalTermName "$compare_list_ys_nil_tail" (-8089)
  yConsName = builtinLocalTermName "$compare_list_y_cons" (-8090)
  ysConsTailName = builtinLocalTermName "$compare_list_ys_cons_tail" (-8091)
  xsCaseName = builtinLocalTermName "$compare_list_xs_case" (-8092)
  ysNilCaseName = builtinLocalTermName "$compare_list_ys_nil_case" (-8093)
  ysConsCaseName = builtinLocalTermName "$compare_list_ys_cons_case" (-8094)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  ltExpr = CCon orderingLTDataConName orderingTy
  eqExpr = CCon orderingEQDataConName orderingTy
  gtExpr = CCon orderingGTDataConName orderingTy
  dictExpr = CVar dictName ordDictA
  xsTail = CVar xsTailName listA
  ysConsTail = CVar ysConsTailName listA
  headCompare =
    ordElementCompareCore aTy dictExpr (CVar xName aTy) (CVar yConsName aTy)
  recursiveTailCompare =
    ordListCompareCallCore aTy dictExpr xsTail ysConsTail
  consBody =
    listCaseCore
      (CVar ysName listA)
      ysConsCaseName
      aTy
      orderingTy
      gtExpr
      yConsName
      ysConsTailName
      ( orderingCaseCore
          "$compare_list_head"
          (-8095)
          headCompare
          orderingTy
          ltExpr
          recursiveTailCompare
          gtExpr
      )
  body =
    listCaseCore
      (CVar xsName listA)
      xsCaseName
      aTy
      orderingTy
      ( listCaseCore
          (CVar ysName listA)
          ysNilCaseName
          aTy
          orderingTy
          eqExpr
          yNilName
          ysNilTailName
          ltExpr
      )
      xName
      xsTailName
      consBody

ordListDictionaryCorePair :: ClassInfo -> Either TypecheckError (CoreBinder, CoreExpr)
ordListDictionaryCorePair info = do
  constructorTy <- classDictionaryFullConstructorCoreType info
  let a = ordListTypeVariable
      aTy = CTyVar a
      listA = CTyList aTy
      ordDictA = ordDictCoreType aTy
      ordDictListA = ordDictCoreType listA
      dictName = builtinLocalTermName "$ord_list_instance_dict" (-8096)
      dictExpr = CVar dictName ordDictA
      eqSuperclass =
        eqListForOrdListCore aTy dictExpr
      compareMethod =
        ordListCompareFunctionCore aTy dictExpr
      ltMethod =
        ordListPredicateMethodCore "$lt_list" (-8110) aTy dictExpr True False False
      leMethod =
        ordListPredicateMethodCore "$le_list" (-8120) aTy dictExpr True True False
      gtMethod =
        ordListPredicateMethodCore "$gt_list" (-8130) aTy dictExpr False False True
      geMethod =
        ordListPredicateMethodCore "$ge_list" (-8140) aTy dictExpr False True True
      maxMethod =
        ordListChoiceMethodCore "$max_list" (-8150) aTy dictExpr (\left right -> (right, right, left))
      minMethod =
        ordListChoiceMethodCore "$min_list" (-8160) aTy dictExpr (\left right -> (left, left, right))
      fieldExprs =
        [ eqSuperclass
        , compareMethod
        , ltMethod
        , leMethod
        , gtMethod
        , geMethod
        , maxMethod
        , minMethod
        ]
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [listA]
          (foldr CTyFun ordDictListA (map exprType fieldExprs))
      body = foldl applyValue typedConstructor fieldExprs
      rhs = CTypeLam [a] (CLam (CoreBinder dictName ordDictA) body (CTyFun ordDictA ordDictListA)) ordListDictionaryCoreType
  pure (CoreBinder ordListDictionaryName ordListDictionaryCoreType, rhs)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

eqListForOrdListCore :: CoreType -> CoreExpr -> CoreExpr
eqListForOrdListCore elementTy ordDictionary =
  CApp eqListDictionary eqElementDictionary eqListTy
 where
  eqElementTy = eqDictCoreType elementTy
  eqListTy = eqDictCoreType (CTyList elementTy)
  eqElementDictionary =
    ordEqSuperclassCore elementTy ordDictionary
  eqListDictionary =
    CTypeApp
      (CVar eqListDictionaryName eqListDictionaryCoreType)
      [elementTy]
      (CTyFun eqElementTy eqListTy)

ordEqSuperclassCore :: CoreType -> CoreExpr -> CoreExpr
ordEqSuperclassCore elementTy dictionary =
  CCase
    dictionary
    (CoreBinder caseName ordDictA)
    [ CoreAlt
        (ConstructorAlt (classDictionaryConstructorName builtinOrdClassName))
        [ CoreBinder eqName eqDictA
        , CoreBinder compareName compareTy
        , CoreBinder ltName predicateTy
        , CoreBinder leName predicateTy
        , CoreBinder gtName predicateTy
        , CoreBinder geName predicateTy
        , CoreBinder maxName choiceTy
        , CoreBinder minName choiceTy
        ]
        (CVar eqName eqDictA)
    ]
    eqDictA
 where
  ordDictA = ordDictCoreType elementTy
  eqDictA = eqDictCoreType elementTy
  compareTy = CTyFun elementTy (CTyFun elementTy orderingTy)
  predicateTy = CTyFun elementTy (CTyFun elementTy boolTy)
  choiceTy = CTyFun elementTy (CTyFun elementTy elementTy)
  caseName = builtinLocalTermName "$ord_eq_super_case" (-8170)
  eqName = builtinLocalTermName "$ord_eq_super_eq" (-8171)
  compareName = builtinLocalTermName "$ord_eq_super_compare" (-8172)
  ltName = builtinLocalTermName "$ord_eq_super_lt" (-8173)
  leName = builtinLocalTermName "$ord_eq_super_le" (-8174)
  gtName = builtinLocalTermName "$ord_eq_super_gt" (-8175)
  geName = builtinLocalTermName "$ord_eq_super_ge" (-8176)
  maxName = builtinLocalTermName "$ord_eq_super_max" (-8177)
  minName = builtinLocalTermName "$ord_eq_super_min" (-8178)

ordListCompareFunctionCore :: CoreType -> CoreExpr -> CoreExpr
ordListCompareFunctionCore elementTy dictionary =
  CApp compareFunction dictionary (CTyFun listTy (CTyFun listTy orderingTy))
 where
  listTy = CTyList elementTy
  dictionaryTy = ordDictCoreType elementTy
  compareFunction =
    CTypeApp
      (CVar ordListCompareMethodName ordListCompareMethodCoreType)
      [elementTy]
      (CTyFun dictionaryTy (CTyFun listTy (CTyFun listTy orderingTy)))

ordElementCompareCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
ordElementCompareCore elementTy dictionary lhs rhs =
  CApp (CApp compareFunction lhs (CTyFun elementTy orderingTy)) rhs orderingTy
 where
  dictionaryTy = ordDictCoreType elementTy
  compareFunction =
    CApp
      (CTypeApp (CVar derivedCompareName ordSelectorCoreType) [elementTy] (CTyFun dictionaryTy (CTyFun elementTy (CTyFun elementTy orderingTy))))
      dictionary
      (CTyFun elementTy (CTyFun elementTy orderingTy))

ordListCompareCallCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
ordListCompareCallCore elementTy dictionary lhs rhs =
  CApp (CApp compareFunction lhs (CTyFun listTy orderingTy)) rhs orderingTy
 where
  listTy = CTyList elementTy
  dictionaryTy = ordDictCoreType elementTy
  compareFunction =
    CApp
      (CTypeApp (CVar ordListCompareMethodName ordListCompareMethodCoreType) [elementTy] (CTyFun dictionaryTy (CTyFun listTy (CTyFun listTy orderingTy))))
      dictionary
      (CTyFun listTy (CTyFun listTy orderingTy))

ordListPredicateMethodCore :: Text -> Int -> CoreType -> CoreExpr -> Bool -> Bool -> Bool -> CoreExpr
ordListPredicateMethodCore occurrence unique elementTy dictionary ltResult eqResult gtResult =
  CLam lhsBinder (CLam rhsBinder methodBody (CTyFun listTy boolTy)) (CTyFun listTy (CTyFun listTy boolTy))
 where
  listTy = CTyList elementTy
  lhsName = builtinLocalTermName (occurrence <> "_lhs") unique
  rhsName = builtinLocalTermName (occurrence <> "_rhs") (unique - 1)
  lhsBinder = CoreBinder lhsName listTy
  rhsBinder = CoreBinder rhsName listTy
  lhs = CVar lhsName listTy
  rhs = CVar rhsName listTy
  boolExpr result =
    if result then CCon trueDataConName boolTy else CCon falseDataConName boolTy
  methodBody =
    orderingCaseCore
      (occurrence <> "_case")
      (unique - 2)
      (ordListCompareCallCore elementTy dictionary lhs rhs)
      boolTy
      (boolExpr ltResult)
      (boolExpr eqResult)
      (boolExpr gtResult)

ordListChoiceMethodCore :: Text -> Int -> CoreType -> CoreExpr -> (CoreExpr -> CoreExpr -> (CoreExpr, CoreExpr, CoreExpr)) -> CoreExpr
ordListChoiceMethodCore occurrence unique elementTy dictionary choices =
  CLam lhsBinder (CLam rhsBinder methodBody (CTyFun listTy listTy)) (CTyFun listTy (CTyFun listTy listTy))
 where
  listTy = CTyList elementTy
  lhsName = builtinLocalTermName (occurrence <> "_lhs") unique
  rhsName = builtinLocalTermName (occurrence <> "_rhs") (unique - 1)
  lhsBinder = CoreBinder lhsName listTy
  rhsBinder = CoreBinder rhsName listTy
  lhs = CVar lhsName listTy
  rhs = CVar rhsName listTy
  (ltBody, eqBody, gtBody) = choices lhs rhs
  methodBody =
    orderingCaseCore
      (occurrence <> "_case")
      (unique - 2)
      (ordListCompareCallCore elementTy dictionary lhs rhs)
      listTy
      ltBody
      eqBody
      gtBody

builtinShowSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinShowSupportCoreBinds classes =
  case Map.lookup builtinShowClassName classes of
    Nothing -> Right []
    Just info -> do
      listDictionaryPair <- showListDictionaryCorePair info
      pure
        [ CoreRec
            [ showAppendCorePair
            , showStringCharsCorePair
            , showListMethodCorePair
            , showListTailCorePair
            , listDictionaryPair
            ]
        ]

showListTypeVariable :: RName
showListTypeVariable =
  preludeTypeVariable "a" (-1541)

showListDictionaryName :: RName
showListDictionaryName =
  preludeTermName "$fShowList" (-1535)

showListMethodName :: RName
showListMethodName =
  preludeTermName "$show_list" (-1892)

showListTailName :: RName
showListTailName =
  preludeTermName "$show_list_tail" (-1893)

showAppendName :: RName
showAppendName =
  preludeTermName "$show_append" (-1894)

showStringCharsName :: RName
showStringCharsName =
  preludeTermName "$show_string_chars" (-1895)

showDictCoreType :: CoreType -> CoreType
showDictCoreType ty =
  CTyApp (CTyCon (classDictionaryTypeName builtinShowClassName)) ty

showSCoreType :: CoreType
showSCoreType =
  CTyFun stringTy stringTy

showsPrecFunctionCoreType :: CoreType -> CoreType
showsPrecFunctionCoreType valueTy =
  CTyFun intTy (CTyFun valueTy showSCoreType)

showListFieldCoreType :: CoreType -> CoreType
showListFieldCoreType valueTy =
  CTyFun (CTyList valueTy) showSCoreType

showListDictionaryCoreType :: CoreType
showListDictionaryCoreType =
  CTyForall [a] (CTyFun showDictA showDictListA)
 where
  a = showListTypeVariable
  aTy = CTyVar a
  showDictA = showDictCoreType aTy
  showDictListA = showDictCoreType (CTyList aTy)

showListMethodCoreType :: CoreType
showListMethodCoreType =
  CTyForall [a] (CTyFun (showsPrecFunctionCoreType aTy) (CTyFun listA showSCoreType))
 where
  a = showListTypeVariable
  aTy = CTyVar a
  listA = CTyList aTy

showListTailCoreType :: CoreType
showListTailCoreType =
  showListMethodCoreType

showAppendCoreType :: CoreType
showAppendCoreType =
  CTyFun stringTy (CTyFun stringTy stringTy)

showStringCharsCoreType :: CoreType
showStringCharsCoreType =
  CTyFun stringTy stringTy

showListSelectorCoreType :: CoreType
showListSelectorCoreType =
  CTyForall [a] (CTyFun showDictA (showListFieldCoreType aTy))
 where
  a = preludeTypeVariable "a" (-1331)
  aTy = CTyVar a
  showDictA = showDictCoreType aTy

showAppendCorePair :: (CoreBinder, CoreExpr)
showAppendCorePair =
  (CoreBinder showAppendName showAppendCoreType, lam xsName stringTy (lam ysName stringTy body))
 where
  xsName = builtinLocalTermName "$show_append_xs" (-1896)
  ysName = builtinLocalTermName "$show_append_ys" (-1897)
  cName = builtinLocalTermName "$show_append_c" (-1898)
  csName = builtinLocalTermName "$show_append_cs" (-1899)
  caseName = builtinLocalTermName "$show_append_case" (-1900)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    listCaseCore
      (CVar xsName stringTy)
      caseName
      charTy
      stringTy
      (CVar ysName stringTy)
      cName
      csName
      (consCharExprCore (CVar cName charTy) (appendStringCore (CVar csName stringTy) (CVar ysName stringTy)))

showStringCharsCorePair :: (CoreBinder, CoreExpr)
showStringCharsCorePair =
  (CoreBinder showStringCharsName showStringCharsCoreType, lam xsName stringTy body)
 where
  xsName = builtinLocalTermName "$show_string_xs" (-1901)
  cName = builtinLocalTermName "$show_string_c" (-1902)
  csName = builtinLocalTermName "$show_string_cs" (-1903)
  caseName = builtinLocalTermName "$show_string_case" (-1904)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    listCaseCore
      (CVar xsName stringTy)
      caseName
      charTy
      stringTy
      (stringLiteralCore (Text.singleton '"'))
      cName
      csName
      (showStringCharCore (CVar cName charTy) (CApp (CVar showStringCharsName showStringCharsCoreType) (CVar csName stringTy) stringTy))

showListMethodCorePair :: (CoreBinder, CoreExpr)
showListMethodCorePair =
  (CoreBinder showListMethodName showListMethodCoreType, CTypeLam [a] (lam showsName showsTy (lam xsName listA (lam restName stringTy body))) showListMethodCoreType)
 where
  a = showListTypeVariable
  aTy = CTyVar a
  listA = CTyList aTy
  showsTy = showsPrecFunctionCoreType aTy
  showsName = builtinLocalTermName "$show_list_shows" (-1905)
  xsName = builtinLocalTermName "$show_list_xs" (-1906)
  yName = builtinLocalTermName "$show_list_y" (-1907)
  ysName = builtinLocalTermName "$show_list_ys" (-1908)
  caseName = builtinLocalTermName "$show_list_case" (-1909)
  restName = builtinLocalTermName "$show_list_rest" (-1930)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      stringTy
      (appendStringCore (stringLiteralCore "[]") (CVar restName stringTy))
      yName
      ysName
      ( consCharCore
          '['
          (showElementWithShowsCore aTy (CVar showsName showsTy) (CVar yName aTy) (showListTailCallCore aTy (CVar showsName showsTy) (CVar ysName listA) (CVar restName stringTy)))
      )

showListTailCorePair :: (CoreBinder, CoreExpr)
showListTailCorePair =
  (CoreBinder showListTailName showListTailCoreType, CTypeLam [a] (lam showsName showsTy (lam xsName listA (lam restName stringTy body))) showListTailCoreType)
 where
  a = showListTypeVariable
  aTy = CTyVar a
  listA = CTyList aTy
  showsTy = showsPrecFunctionCoreType aTy
  showsName = builtinLocalTermName "$show_tail_shows" (-1910)
  xsName = builtinLocalTermName "$show_tail_xs" (-1911)
  yName = builtinLocalTermName "$show_tail_y" (-1912)
  ysName = builtinLocalTermName "$show_tail_ys" (-1913)
  caseName = builtinLocalTermName "$show_tail_case" (-1914)
  restName = builtinLocalTermName "$show_tail_rest" (-1931)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      stringTy
      (consCharCore ']' (CVar restName stringTy))
      yName
      ysName
      ( consCharCore
          ','
          (showElementWithShowsCore aTy (CVar showsName showsTy) (CVar yName aTy) (showListTailCallCore aTy (CVar showsName showsTy) (CVar ysName listA) (CVar restName stringTy)))
      )

showListDictionaryCorePair :: ClassInfo -> Either TypecheckError (CoreBinder, CoreExpr)
showListDictionaryCorePair info = do
  constructorTy <- classDictionaryConstructorCoreType info
  let a = showListTypeVariable
      aTy = CTyVar a
      listA = CTyList aTy
      showDictA = showDictCoreType aTy
      showDictListA = showDictCoreType listA
      dictName = builtinLocalTermName "$show_list_instance_dict" (-1915)
      precName = builtinLocalTermName "$show_list_instance_prec" (-1932)
      xsName = builtinLocalTermName "$show_list_instance_xs" (-1933)
      restName = builtinLocalTermName "$show_list_instance_rest" (-1934)
      showXsName = builtinLocalTermName "$show_list_instance_show_xs" (-1935)
      listPrecName = builtinLocalTermName "$show_list_instance_list_prec" (-2431)
      listXsName = builtinLocalTermName "$show_list_instance_list_xs" (-2432)
      listRestName = builtinLocalTermName "$show_list_instance_list_rest" (-2433)
      elementShowList =
        CApp
          ( CTypeApp
              (CVar (preludeTermName "showList" (-1432)) showListSelectorCoreType)
              [aTy]
              (CTyFun showDictA (showListFieldCoreType aTy))
          )
          (CVar dictName showDictA)
          (showListFieldCoreType aTy)
      showsPrecMethodWith precBinderName xsBinderName restBinderName =
        CLam
          (CoreBinder precBinderName intTy)
          ( CLam
              (CoreBinder xsBinderName listA)
              ( CLam
                  (CoreBinder restBinderName stringTy)
                  (CApp (CApp elementShowList (CVar xsBinderName listA) showSCoreType) (CVar restBinderName stringTy) stringTy)
                  showSCoreType
              )
              (CTyFun listA showSCoreType)
          )
          (showsPrecFunctionCoreType listA)
      showsPrecMethod =
        showsPrecMethodWith precName xsName restName
      showListShowsPrecMethod =
        showsPrecMethodWith listPrecName listXsName listRestName
      showMethod =
        CLam
          (CoreBinder showXsName listA)
          (CApp (CApp elementShowList (CVar showXsName listA) showSCoreType) emptyStringCore stringTy)
          (CTyFun listA stringTy)
      showListMethod =
        showListFromShowsMethod listA showListShowsPrecMethod
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [listA]
          (CTyFun (exprType showsPrecMethod) (CTyFun (exprType showMethod) (CTyFun (exprType showListMethod) showDictListA)))
      body =
        CApp
          (CApp (CApp typedConstructor showsPrecMethod (CTyFun (exprType showMethod) (CTyFun (exprType showListMethod) showDictListA))) showMethod (CTyFun (exprType showListMethod) showDictListA))
          showListMethod
          showDictListA
      rhs = CTypeLam [a] (CLam (CoreBinder dictName showDictA) body (CTyFun showDictA showDictListA)) showListDictionaryCoreType
  pure (CoreBinder showListDictionaryName showListDictionaryCoreType, rhs)

builtinReadSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinReadSupportCoreBinds classes =
  case Map.lookup builtinReadClassName classes of
    Nothing -> Right []
    Just info -> do
      listDictionaryPair <- readListDictionaryCorePair info
      pure [CoreRec [listDictionaryPair]]

readListDictionaryName :: RName
readListDictionaryName =
  preludeTermName "$fReadList" (-1706)

readDictCoreType :: CoreType -> CoreType
readDictCoreType ty =
  CTyApp (CTyCon (classDictionaryTypeName builtinReadClassName)) ty

readListDictionaryCoreType :: CoreType
readListDictionaryCoreType =
  CTyForall [a] (CTyFun readDictA readDictListA)
 where
  a = preludeTypeVariable "a" (-2530)
  aTy = CTyVar a
  readDictA = readDictCoreType aTy
  readDictListA = readDictCoreType (CTyList aTy)

readListSelectorCoreType :: CoreType
readListSelectorCoreType =
  CTyForall [a] (CTyFun readDictA (readSCoreType listA))
 where
  a = preludeTypeVariable "a" (-1561)
  aTy = CTyVar a
  listA = CTyList aTy
  readDictA = readDictCoreType aTy

readListDictionaryCorePair :: ClassInfo -> Either TypecheckError (CoreBinder, CoreExpr)
readListDictionaryCorePair info = do
  constructorTy <- classDictionaryConstructorCoreType info
  let a = preludeTypeVariable "a" (-2530)
      aTy = CTyVar a
      listA = CTyList aTy
      readDictA = readDictCoreType aTy
      readDictListA = readDictCoreType listA
      dictName = builtinLocalTermName "$read_list_instance_dict" (-2714)
      precName = builtinLocalTermName "$read_list_instance_prec" (-2715)
      xsName = builtinLocalTermName "$read_list_instance_xs" (-2716)
      showListPrecName = builtinLocalTermName "$read_list_instance_list_prec" (-2717)
      showListXsName = builtinLocalTermName "$read_list_instance_list_xs" (-2718)
      elementReadList =
        applyCore
          ( CTypeApp
              (CVar (preludeTermName "readList" (-1434)) readListSelectorCoreType)
              [aTy]
              (CTyFun readDictA (readSCoreType listA))
          )
          (CVar dictName readDictA)
          (readSCoreType listA)
      readsPrecMethodWith precBinderName xsBinderName =
        coreLam precBinderName intTy (coreLam xsBinderName stringTy (applyCore elementReadList (CVar xsBinderName stringTy) (readResultsCoreType listA)))
      readsPrecMethod =
        readsPrecMethodWith precName xsName
      readListShowsPrecMethod =
        readsPrecMethodWith showListPrecName showListXsName
      readListParser =
        applyCore readListShowsPrecMethod zeroInt (readSCoreType listA)
      readListMethod =
        readListFromParserMethod listA readListParser
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [listA]
          (CTyFun (exprType readsPrecMethod) (CTyFun (exprType readListMethod) readDictListA))
      body =
        applyCore
          (applyCore typedConstructor readsPrecMethod (CTyFun (exprType readListMethod) readDictListA))
          readListMethod
          readDictListA
      rhs = CTypeLam [a] (coreLam dictName readDictA body) readListDictionaryCoreType
  pure (CoreBinder readListDictionaryName readListDictionaryCoreType, rhs)

builtinFunctorSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinFunctorSupportCoreBinds classes
  | builtinFunctorClassName `Map.member` classes =
      Right [CoreRec [functorListMapCorePair]]
  | otherwise =
      Right []

functorListMapName :: RName
functorListMapName =
  preludeTermName "$functor_list_map" (-2250)

functorListMapCorePair :: (CoreBinder, CoreExpr)
functorListMapCorePair =
  (CoreBinder functorListMapName listFunctorFmapCoreType, CTypeLam [a, b] (lam functionName (CTyFun aTy bTy) (lam xsName listA body)) listFunctorFmapCoreType)
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy
  functionName = builtinLocalTermName "$functor_list_map_f" (-2251)
  xsName = builtinLocalTermName "$functor_list_map_xs" (-2252)
  headName = builtinLocalTermName "$functor_list_map_head" (-2253)
  tailName = builtinLocalTermName "$functor_list_map_tail" (-2254)
  caseName = builtinLocalTermName "$functor_list_map_case" (-2255)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  function = CVar functionName (CTyFun aTy bTy)
  recursiveTail =
    CApp
      ( CApp
          (CTypeApp (CVar functorListMapName listFunctorFmapCoreType) [aTy, bTy] (CTyFun (CTyFun aTy bTy) (CTyFun listA listB)))
          function
          (CTyFun listA listB)
      )
      (CVar tailName listA)
      listB
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      listB
      (nilCore bTy)
      headName
      tailName
      ( consCore
          bTy
          (CApp function (CVar headName aTy) bTy)
          recursiveTail
      )

builtinMonadSupportCoreBinds :: Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
builtinMonadSupportCoreBinds classes
  | builtinMonadClassName `Map.member` classes || builtinIxClassName `Map.member` classes =
      Right [CoreRec [monadListAppendCorePair, monadListBindCorePair]]
  | otherwise =
      Right []

monadListAppendCorePair :: (CoreBinder, CoreExpr)
monadListAppendCorePair =
  (CoreBinder monadListAppendName monadListAppendCoreType, CTypeLam [a] (lam xsName listA (lam ysName listA body)) monadListAppendCoreType)
 where
  a = preludeTypeVariable "a" (-1362)
  aTy = CTyVar a
  listA = CTyList aTy
  xsName = builtinLocalTermName "$monad_list_append_xs" (-2232)
  ysName = builtinLocalTermName "$monad_list_append_ys" (-2233)
  headName = builtinLocalTermName "$monad_list_append_head" (-2234)
  tailName = builtinLocalTermName "$monad_list_append_tail" (-2235)
  caseName = builtinLocalTermName "$monad_list_append_case" (-2236)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      listA
      (CVar ysName listA)
      headName
      tailName
      ( consCore
          aTy
          (CVar headName aTy)
          ( CApp
              ( CApp
                  (CTypeApp (CVar monadListAppendName monadListAppendCoreType) [aTy] (CTyFun listA (CTyFun listA listA)))
                  (CVar tailName listA)
                  (CTyFun listA listA)
              )
              (CVar ysName listA)
              listA
          )
      )

monadListBindCorePair :: (CoreBinder, CoreExpr)
monadListBindCorePair =
  (CoreBinder monadListBindName monadListBindCoreType, CTypeLam [a, b] (lam xsName listA (lam continuationName (CTyFun aTy listB) body)) monadListBindCoreType)
 where
  a = preludeTypeVariable "a" (-1362)
  b = preludeTypeVariable "b" (-1363)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy
  xsName = builtinLocalTermName "$monad_list_bind_xs" (-2237)
  continuationName = builtinLocalTermName "$monad_list_bind_k" (-2238)
  headName = builtinLocalTermName "$monad_list_bind_head" (-2239)
  tailName = builtinLocalTermName "$monad_list_bind_tail" (-2240)
  caseName = builtinLocalTermName "$monad_list_bind_case" (-2241)
  lam binderName ty bodyExpr = CLam (CoreBinder binderName ty) bodyExpr (CTyFun ty (exprType bodyExpr))
  continuation = CVar continuationName (CTyFun aTy listB)
  mappedHead = CApp continuation (CVar headName aTy) listB
  recursiveTail =
    CApp
      ( CApp
          (CTypeApp (CVar monadListBindName monadListBindCoreType) [aTy, bTy] (CTyFun listA (CTyFun (CTyFun aTy listB) listB)))
          (CVar tailName listA)
          (CTyFun (CTyFun aTy listB) listB)
      )
      continuation
      listB
  appended =
    CApp
      ( CApp
          (CTypeApp (CVar monadListAppendName monadListAppendCoreType) [bTy] (CTyFun listB (CTyFun listB listB)))
          mappedHead
          (CTyFun listB listB)
      )
      recursiveTail
      listB
  body =
    listCaseCore
      (CVar xsName listA)
      caseName
      aTy
      listB
      (nilCore bTy)
      headName
      tailName
      appended

classDictionaryConstructorCoreType :: ClassInfo -> Either TypecheckError CoreType
classDictionaryConstructorCoreType info = do
  resultTy <- monoToCoreType Map.empty Map.empty (classDictionaryType info (TyVar (classInfoVariable info)))
  fieldTypes <- traverse (classMethodFieldCoreType Map.empty Map.empty) (classInfoMethods info)
  pure (CTyForall [classInfoVariable info] (foldr CTyFun resultTy fieldTypes))

classDictionaryFullConstructorCoreType :: ClassInfo -> Either TypecheckError CoreType
classDictionaryFullConstructorCoreType info = do
  resultTy <- monoToCoreType Map.empty Map.empty (classDictionaryType info (TyVar (classInfoVariable info)))
  fieldTypes <- classDictionaryCoreFieldTypes Map.empty Map.empty info
  pure (CTyForall [classInfoVariable info] (foldr CTyFun resultTy fieldTypes))

showElementWithShowsCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
showElementWithShowsCore elementTy showsFunction element rest =
  CApp (CApp (CApp showsFunction zeroInt (CTyFun elementTy showSCoreType)) element showSCoreType) rest stringTy

showListTailCallCore :: CoreType -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
showListTailCallCore elementTy showsFunction listValue rest =
  CApp (CApp tailFunction listValue showSCoreType) rest stringTy
 where
  listTy = CTyList elementTy
  tailFunction =
    CApp
      (CTypeApp (CVar showListTailName showListTailCoreType) [elementTy] (CTyFun (showsPrecFunctionCoreType elementTy) (CTyFun listTy showSCoreType)))
      showsFunction
      (CTyFun listTy showSCoreType)

showListFromShowsMethod :: CoreType -> CoreExpr -> CoreExpr
showListFromShowsMethod elementTy showsFunction =
  CApp listFunction showsFunction (showListFieldCoreType elementTy)
 where
  listTy = CTyList elementTy
  listFunction =
    CTypeApp
      (CVar showListMethodName showListMethodCoreType)
      [elementTy]
      (CTyFun (showsPrecFunctionCoreType elementTy) (CTyFun listTy showSCoreType))

showsPrecFromRenderedMethod :: Text -> Int -> CoreType -> (CoreExpr -> CoreExpr) -> CoreExpr
showsPrecFromRenderedMethod occurrence unique valueTy renderValue =
  CLam precBinder (CLam valueBinder (CLam restBinder methodBody showSCoreType) (CTyFun valueTy showSCoreType)) (showsPrecFunctionCoreType valueTy)
 where
  precBinder = CoreBinder (builtinLocalTermName (occurrence <> "_prec") unique) intTy
  valueName = builtinLocalTermName (occurrence <> "_value") (unique - 1)
  restName = builtinLocalTermName (occurrence <> "_rest") (unique - 2)
  valueBinder = CoreBinder valueName valueTy
  restBinder = CoreBinder restName stringTy
  methodBody =
    appendStringCore (renderValue (CVar valueName valueTy)) (CVar restName stringTy)

appendStringCore :: CoreExpr -> CoreExpr -> CoreExpr
appendStringCore lhs rhs =
  CApp (CApp (CVar showAppendName showAppendCoreType) lhs (CTyFun stringTy stringTy)) rhs stringTy

listCaseCore :: CoreExpr -> RName -> CoreType -> CoreType -> CoreExpr -> RName -> RName -> CoreExpr -> CoreExpr
listCaseCore scrutinee caseName elementTy resultTy nilBody headName tailName consBody =
  CCase
    scrutinee
    (CoreBinder caseName (CTyList elementTy))
    [ CoreAlt (ConstructorAlt listNilDataConName) [] nilBody
    , CoreAlt
        (ConstructorAlt listConsDataConName)
        [CoreBinder headName elementTy, CoreBinder tailName (CTyList elementTy)]
        consBody
    ]
    resultTy

showCharLiteralCore :: CoreExpr -> CoreExpr
showCharLiteralCore value =
  showCharLiteralCoreWith "$show_char_case" (-1916) value

showCharLiteralCoreWith :: Text -> Int -> CoreExpr -> CoreExpr
showCharLiteralCoreWith caseOccurrence caseUnique value =
  CCase value (CoreBinder caseName charTy) (specialCases <> [defaultCase]) stringTy
 where
  caseName = builtinLocalTermName caseOccurrence caseUnique
  specialCases =
    [ charCase char ("'\\" <> escaped <> "'")
    | (char, escaped) <- showEscapedControlChars
    ]
      <> [ charCase '\'' "'\\''"
         , charCase '\\' "'\\\\'"
         ]
  charCase char rendered =
    CoreAlt (LiteralAlt (LChar char)) [] (stringLiteralCore rendered)
  defaultCase =
    CoreAlt DefaultAlt [] (quotedCharCore (CVar caseName charTy))

showStringCharCore :: CoreExpr -> CoreExpr -> CoreExpr
showStringCharCore value rest =
  CCase value (CoreBinder caseName charTy) (specialCases <> [defaultCase]) stringTy
 where
  caseName = builtinLocalTermName "$show_string_char_case" (-1917)
  specialCases =
    [ charCase char ("\\" <> escaped)
    | (char, escaped) <- showEscapedControlChars
    , char /= '\SO'
    ]
      <> [CoreAlt (LiteralAlt (LChar '\SO')) [] (prefixStringCore "\\SO" (protectSOEscapeRestCore rest))]
      <> [ charCase '"' "\\\""
         , charCase '\\' "\\\\"
         ]
  charCase char rendered =
    CoreAlt (LiteralAlt (LChar char)) [] (prefixStringCore rendered rest)
  defaultCase =
    CoreAlt DefaultAlt [] (consCharExprCore (CVar caseName charTy) rest)

protectSOEscapeRestCore :: CoreExpr -> CoreExpr
protectSOEscapeRestCore rest =
  listCaseCore
    rest
    caseName
    charTy
    stringTy
    emptyStringCore
    headName
    tailName
    (boolCaseCore "$show_string_so_escape_ambiguous" (-2437) headIsH stringTy escapedRest originalRest)
 where
  caseName = builtinLocalTermName "$show_string_so_escape_case" (-2434)
  headName = builtinLocalTermName "$show_string_so_escape_head" (-2435)
  tailName = builtinLocalTermName "$show_string_so_escape_tail" (-2436)
  headExpr = CVar headName charTy
  tailExpr = CVar tailName stringTy
  originalRest = consCharExprCore headExpr tailExpr
  escapedRest = prefixStringCore "\\&" originalRest
  headIsH = CPrimOp PrimEq [headExpr, CLit (LChar 'H') charTy] boolTy

showEscapedControlChars :: [(Char, Text)]
showEscapedControlChars =
  [ ('\NUL', "NUL")
  , ('\SOH', "SOH")
  , ('\STX', "STX")
  , ('\ETX', "ETX")
  , ('\EOT', "EOT")
  , ('\ENQ', "ENQ")
  , ('\ACK', "ACK")
  , ('\a', "a")
  , ('\b', "b")
  , ('\t', "t")
  , ('\n', "n")
  , ('\v', "v")
  , ('\f', "f")
  , ('\r', "r")
  , ('\SO', "SO")
  , ('\SI', "SI")
  , ('\DLE', "DLE")
  , ('\DC1', "DC1")
  , ('\DC2', "DC2")
  , ('\DC3', "DC3")
  , ('\DC4', "DC4")
  , ('\NAK', "NAK")
  , ('\SYN', "SYN")
  , ('\ETB', "ETB")
  , ('\CAN', "CAN")
  , ('\EM', "EM")
  , ('\SUB', "SUB")
  , ('\ESC', "ESC")
  , ('\FS', "FS")
  , ('\GS', "GS")
  , ('\RS', "RS")
  , ('\US', "US")
  , ('\DEL', "DEL")
  ]

quotedCharCore :: CoreExpr -> CoreExpr
quotedCharCore charExpr =
  consCharCore '\'' (consCharExprCore charExpr (consCharCore '\'' emptyStringCore))

showStringLiteralCore :: CoreExpr -> CoreExpr
showStringLiteralCore value =
  consCharCore '"' (CApp (CVar showStringCharsName showStringCharsCoreType) value stringTy)

stringLiteralCore :: Text -> CoreExpr
stringLiteralCore value =
  listCoreExpr charTy [CLit (LChar char) charTy | char <- Text.unpack value]

prefixStringCore :: Text -> CoreExpr -> CoreExpr
prefixStringCore prefix rest =
  foldr consCharCore rest (Text.unpack prefix)

consCharCore :: Char -> CoreExpr -> CoreExpr
consCharCore char =
  consCharExprCore (CLit (LChar char) charTy)

consCharExprCore :: CoreExpr -> CoreExpr -> CoreExpr
consCharExprCore headExpr tailExpr =
  constructorApp listConsDataConName [charTy] [headExpr, tailExpr] stringTy

emptyStringCore :: CoreExpr
emptyStringCore =
  listCoreExpr charTy []

builtinLocalTermName :: Text -> Int -> RName
builtinLocalTermName occurrence unique =
  RName TermNamespace occurrence unique False

uniquifyCoreModuleBinders :: CoreModule -> CoreModule
uniquifyCoreModuleBinders coreModule =
  coreModule {coreModuleBinds = uniquifiedBinds}
 where
  (uniquifiedBinds, _) =
    runState (traverse uniquifyTopCoreBind (coreModuleBinds coreModule)) (-9000000)

uniquifyTopCoreBind :: CoreBind -> State Int CoreBind
uniquifyTopCoreBind = \case
  CoreNonRec binder rhs -> do
    rhs' <- uniquifyCoreExpr Map.empty rhs
    pure (CoreNonRec binder rhs')
  CoreRec pairs -> do
    pairs' <- traverse (\(binder, rhs) -> (binder,) <$> uniquifyCoreExpr Map.empty rhs) pairs
    pure (CoreRec pairs')

uniquifyCoreBind :: Map.Map RName RName -> CoreBind -> State Int (CoreBind, Map.Map RName RName)
uniquifyCoreBind env = \case
  CoreNonRec binder rhs -> do
    newBinder <- freshCoreLocalBinder binder
    rhs' <- uniquifyCoreExpr env rhs
    let env' = Map.insert (coreBinderName binder) (coreBinderName newBinder) env
    pure (CoreNonRec newBinder rhs', env')
  CoreRec pairs -> do
    newBinders <- traverse (freshCoreLocalBinder . fst) pairs
    let oldNames = map (coreBinderName . fst) pairs
        newNames = map coreBinderName newBinders
        env' = Map.union (Map.fromList (zip oldNames newNames)) env
    rhs' <- traverse (uniquifyCoreExpr env' . snd) pairs
    pure (CoreRec (zip newBinders rhs'), env')

uniquifyCoreExpr :: Map.Map RName RName -> CoreExpr -> State Int CoreExpr
uniquifyCoreExpr env = \case
  CVar name ty ->
    pure (CVar (Map.findWithDefault name name env) ty)
  CLit literal ty ->
    pure (CLit literal ty)
  CCon name ty ->
    pure (CCon name ty)
  CLam binder body ty -> do
    newBinder <- freshCoreLocalBinder binder
    body' <- uniquifyCoreExpr (Map.insert (coreBinderName binder) (coreBinderName newBinder) env) body
    pure (CLam newBinder body' ty)
  CApp fn arg ty ->
    CApp <$> uniquifyCoreExpr env fn <*> uniquifyCoreExpr env arg <*> pure ty
  CTypeLam variables body ty ->
    CTypeLam variables <$> uniquifyCoreExpr env body <*> pure ty
  CTypeApp fn arguments ty ->
    CTypeApp <$> uniquifyCoreExpr env fn <*> pure arguments <*> pure ty
  CLet bind body ty -> do
    (bind', env') <- uniquifyCoreBind env bind
    body' <- uniquifyCoreExpr env' body
    pure (CLet bind' body' ty)
  CCase scrutinee binder alternatives ty -> do
    scrutinee' <- uniquifyCoreExpr env scrutinee
    newBinder <- freshCoreLocalBinder binder
    let env' = Map.insert (coreBinderName binder) (coreBinderName newBinder) env
    alternatives' <- traverse (uniquifyCoreAlt env') alternatives
    pure (CCase scrutinee' newBinder alternatives' ty)
  CCoerce expression ty ->
    CCoerce <$> uniquifyCoreExpr env expression <*> pure ty
  CPrimOp op arguments ty ->
    CPrimOp op <$> traverse (uniquifyCoreExpr env) arguments <*> pure ty
  CForeignCall foreignImport arguments ty ->
    CForeignCall foreignImport <$> traverse (uniquifyCoreExpr env) arguments <*> pure ty
  CForeignImportValue foreignImport ty ->
    pure (CForeignImportValue foreignImport ty)

uniquifyCoreAlt :: Map.Map RName RName -> CoreAlt -> State Int CoreAlt
uniquifyCoreAlt env (CoreAlt altCon binders body) = do
  newBinders <- traverse freshCoreLocalBinder binders
  let env' =
        Map.union
          (Map.fromList (zip (map coreBinderName binders) (map coreBinderName newBinders)))
          env
  body' <- uniquifyCoreExpr env' body
  pure (CoreAlt altCon newBinders body')

freshCoreLocalBinder :: CoreBinder -> State Int CoreBinder
freshCoreLocalBinder (CoreBinder name ty) = do
  name' <- freshCoreLocalName name
  pure (CoreBinder name' ty)

freshCoreLocalName :: RName -> State Int RName
freshCoreLocalName name = do
  unique <- get
  modify (subtract 1)
  pure name {nameUnique = unique}

superclassSelectorName :: ClassInfo -> Int -> ClassConstraint -> RName
superclassSelectorName info index superclass =
  RName
    TermNamespace
    ("$super_" <> nameOcc (classInfoName info) <> "_" <> nameOcc (classConstraintClass superclass) <> renderInt index)
    (5450000 + nameUnique (classInfoName info) * 1000 + nameUnique (classConstraintClass superclass) * 10 + index)
    False

superclassSelectorCoreType :: ClassInfo -> Int -> Either TypecheckError CoreType
superclassSelectorCoreType info index =
  case drop index (classInfoSuperclasses info) of
    superclass : _ ->
      schemeToCoreType
        ( Scheme
            [classInfoVariable info]
            []
            ( TyFun
                (classDictionaryType info (TyVar (classInfoVariable info)))
                (superclassDictionaryFieldType superclass)
            )
        )
    [] ->
      Left (UnsupportedCore0 ("missing superclass selector for `" <> renderRName (classInfoName info) <> "`"))

classSelectorCoreBinds :: Subst -> Map.Map RName ClassInfo -> Either TypecheckError [CoreBind]
classSelectorCoreBinds subst classes =
  concat <$> traverse selectorBinds (Map.elems classes)
 where
  selectorBinds info =
    (<>) <$> traverse (superclassSelectorBind info) (zip [0 ..] (classInfoSuperclasses info)) <*> traverse (selectorBind info) (classInfoMethods info)

  superclassSelectorBind info (index, superclass) = do
    binderTy <- superclassSelectorCoreType info index
    dictTy <- monoToCoreType subst Map.empty (classDictionaryType info (TyVar (classInfoVariable info)))
    resultTy <- monoToCoreType subst Map.empty (superclassDictionaryFieldType superclass)
    fieldTypes <- classDictionaryCoreFieldTypes subst Map.empty info
    let selectorName = superclassSelectorName info index superclass
        dictBinder =
          CoreBinder
            ( RName
                TermNamespace
                ("$dict_" <> nameOcc selectorName)
                (5450000 + nameUnique selectorName)
                False
            )
            dictTy
        caseBinder =
          CoreBinder
            ( RName
                TermNamespace
                ("$case_" <> nameOcc selectorName)
                (5451000 + nameUnique selectorName)
                False
            )
            dictTy
        fieldBinders =
          [ CoreBinder
              ( RName
                  TermNamespace
                  ("$super" <> renderInt fieldIndex <> "_" <> nameOcc (classInfoName info) <> "_" <> renderInt index)
                  (5452000 + nameUnique (classInfoName info) * 1000 + index * 100 + fieldIndex)
                  False
              )
              fieldTy
          | (fieldIndex, fieldTy) <- zip [0 ..] fieldTypes
          ]
        selectedBinder = fieldBinders !! index
        selected = CVar (coreBinderName selectedBinder) (coreBinderType selectedBinder)
        caseExpr =
          CCase
            (CVar (coreBinderName dictBinder) dictTy)
            caseBinder
            [CoreAlt (ConstructorAlt (classInfoDictConstructorName info)) fieldBinders selected]
            resultTy
        body = CTypeLam [classInfoVariable info] (CLam dictBinder caseExpr (CTyFun dictTy resultTy)) binderTy
    pure (CoreNonRec (CoreBinder selectorName binderTy) body)

  selectorBind info method = do
    binderTy <- schemeToCoreType (classMethodScheme method)
    dictTy <- monoToCoreType subst Map.empty (classDictionaryType info (TyVar (classInfoVariable info)))
    methodTy <- monoToCoreType subst Map.empty (classMethodFieldType method)
    fieldTypes <- classDictionaryCoreFieldTypes subst Map.empty info
    let dictBinder =
          CoreBinder
            ( RName
                TermNamespace
                ("$dict_" <> nameOcc (classMethodName method))
                (5400000 + nameUnique (classMethodName method))
                False
            )
            dictTy
        caseBinder =
          CoreBinder
            ( RName
                TermNamespace
                ("$case_" <> nameOcc (classMethodName method))
                (5410000 + nameUnique (classMethodName method))
                False
            )
            dictTy
        fieldBinders =
          [ CoreBinder
              ( RName
                  TermNamespace
                  ("$method" <> renderInt index <> "_" <> nameOcc (classInfoName info) <> "_" <> nameOcc (classMethodName method))
                  (5420000 + nameUnique (classInfoName info) * 1000 + nameUnique (classMethodName method) * 10 + index)
                  False
              )
              fieldTy
          | (index, fieldTy) <- zip [0 ..] fieldTypes
          ]
        selectedBinder = fieldBinders !! classMethodFieldIndex method
        selected = CVar (coreBinderName selectedBinder) (coreBinderType selectedBinder)
        selectedMethod =
          case schemeVars (classMethodFieldScheme method) of
            [] -> selected
            variables ->
              CTypeApp
                selected
                (map CTyVar variables)
                methodTy
        caseExpr =
          CCase
            (CVar (coreBinderName dictBinder) dictTy)
            caseBinder
            [CoreAlt (ConstructorAlt (classInfoDictConstructorName info)) fieldBinders selectedMethod]
            methodTy
        body = CTypeLam (schemeVars (classMethodScheme method)) (CLam dictBinder caseExpr (CTyFun dictTy methodTy)) binderTy
    pure (CoreNonRec (CoreBinder (classMethodName method) binderTy) body)

recordSelectorCoreBinds :: Subst -> Map.Map RName RecordSelectorInfo -> Either TypecheckError [CoreBind]
recordSelectorCoreBinds subst selectors =
  traverse selectorBind (Map.elems selectors)
 where
  selectorBind selector = do
    binderTy <- schemeToCoreTypeWith subst Map.empty (recordSelectorScheme selector)
    argumentTy <- monoToCoreType subst Map.empty (recordSelectorResultType selector)
    resultTy <- monoToCoreType subst Map.empty (recordSelectorFieldType selector)
    let selectorName = recordSelectorName selector
    coreAlternatives <- traverse (selectorAlternative selectorName) (recordSelectorAlternatives selector)
    let argumentBinder =
          CoreBinder
            ( RName
                TermNamespace
                ("$record_" <> nameOcc selectorName)
                (5430000 + nameUnique selectorName)
                False
            )
            argumentTy
        body =
          case recordSelectorAlternatives selector of
            [alternative]
              | recordSelectorConstructorRepresentation alternative == CoreNewtypeConstructor ->
                  CCoerce (CVar (coreBinderName argumentBinder) argumentTy) resultTy
            _ ->
              CCase
                (CVar (coreBinderName argumentBinder) argumentTy)
                ( CoreBinder
                    ( RName
                        TermNamespace
                        ("$record_case_" <> nameOcc selectorName)
                        (5440000 + nameUnique selectorName)
                        False
                    )
                    argumentTy
                )
                coreAlternatives
                resultTy
        lambdaBody = CLam argumentBinder body (CTyFun argumentTy resultTy)
        rhs =
          case recordSelectorTyVars selector of
            [] -> lambdaBody
            variables -> CTypeLam variables lambdaBody binderTy
    pure (CoreNonRec (CoreBinder selectorName binderTy) rhs)

  selectorAlternative selectorName alternative = do
    fieldTypes <- traverse (monoToCoreType subst Map.empty) (recordSelectorConstructorFields alternative)
    let constructorName = recordSelectorConstructor alternative
        fieldBinders =
          [ CoreBinder
              ( RName
                  TermNamespace
                  ( "$record_field"
                      <> renderInt index
                      <> "_"
                      <> nameOcc selectorName
                      <> "_"
                      <> nameOcc constructorName
                  )
                  (5450000 + nameUnique selectorName * 10000 + nameUnique constructorName * 100 + index)
                  False
              )
              fieldTy
          | (index, fieldTy) <- zip [0 ..] fieldTypes
          ]
        selectedBinder = fieldBinders !! recordSelectorFieldIndex alternative
    pure $
      CoreAlt
        (ConstructorAlt constructorName)
        fieldBinders
        (CVar (coreBinderName selectedBinder) (coreBinderType selectedBinder))

instanceDictionaryToCore ::
  Subst ->
  Map.Map RName ClassInfo ->
  [InstanceDictionaryRef] ->
  TypedInstanceDictionary ->
  Either TypecheckError CoreBind
instanceDictionaryToCore subst classes instances dictionary = do
  info <-
    case Map.lookup (typedInstanceClass dictionary) classes of
      Nothing -> Left (UnsupportedCore0 ("missing class info for instance `" <> renderRName (typedInstanceClass dictionary) <> "`"))
      Just classInfo -> pure classInfo
  let dictMono = classDictionaryType info (typedInstanceType dictionary)
      dictScheme = Scheme (typedInstanceVariables dictionary) (typedInstanceContext dictionary) dictMono
  binderTy <- schemeToCoreTypeWith subst Map.empty dictScheme
  dictTy <- monoToCoreType subst Map.empty dictMono
  instanceTypeArg <- monoToCoreType subst Map.empty (typedInstanceType dictionary)
  dictBinders <- dictionaryBindersFor subst Map.empty (typedInstanceDictName dictionary) dictScheme
  let localDictionaries =
        [ (constraint, CVar (coreBinderName binder) (coreBinderType binder))
        | (constraint, binder) <- dictBinders
        ]
      env = CoreElabEnv subst Map.empty classes instances localDictionaries
  superclassExprs <- traverse (resolveDictionary env) (typedInstanceSuperclasses dictionary)
  methodExprs <- traverse (uncurry (instanceMethodToCore env info (typedInstanceType dictionary))) (zip (classInfoMethods info) (typedInstanceMethods dictionary))
  constructorTy <- classDictionaryFullConstructorCoreType info
  let fieldExprs = superclassExprs <> methodExprs
      constructorResultTy = foldr CTyFun dictTy (map exprType fieldExprs)
      typedConstructor =
        CTypeApp
          (CCon (classInfoDictConstructorName info) constructorTy)
          [instanceTypeArg]
          constructorResultTy
      dictBody = foldl applyValue typedConstructor fieldExprs
      rhsWithDictionaryLambdas =
        foldr
          (\(_, binder) body -> CLam binder body (CTyFun (coreBinderType binder) (exprType body)))
          dictBody
          dictBinders
      rhsWithTypeLambdas =
        case typedInstanceVariables dictionary of
          [] -> rhsWithDictionaryLambdas
          variables -> CTypeLam variables rhsWithDictionaryLambdas binderTy
  pure (CoreNonRec (CoreBinder (typedInstanceDictName dictionary) binderTy) rhsWithTypeLambdas)
 where
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> exprType callee
     in CApp callee argument remainingResult

instanceMethodToCore ::
  CoreElabEnv ->
  ClassInfo ->
  MonoType ->
  ClassMethodInfo ->
  TypedExpr ->
  Either TypecheckError CoreExpr
instanceMethodToCore env info instanceType method expression = do
  coreExpression <- exprToCore env expression
  let replacements = Map.singleton (classInfoVariable info) instanceType
      fieldScheme = replaceSchemeTypeVars replacements (classMethodFieldScheme method)
      fieldVariables = schemeVars fieldScheme
  fieldTy <- schemeToCoreTypeWith (coreElabSubst env) (coreElabMetas env) fieldScheme
  pure $
    case fieldVariables of
      [] -> coreExpression
      variables -> CTypeLam variables coreExpression fieldTy

constructorApp :: RName -> [CoreType] -> [CoreExpr] -> CoreType -> CoreExpr
constructorApp name typeArguments arguments resultTy =
  foldl applyValue typedConstructor arguments
 where
  constructorTy =
    case Map.lookup name (CoreValidate.coreConstructorTypes CoreValidate.defaultValidationEnv) of
      Just info -> CoreValidate.constructorFunctionType info
      Nothing
        | name == tupleDataConName (length arguments) ->
            CoreValidate.constructorFunctionType (tupleConstructorInfo (length arguments))
        | otherwise ->
            let fields = map exprType arguments
             in CoreValidate.constructorFunctionType (CoreConstructorInfo [] fields resultTy CoreDataConstructor)
  typedConstructor =
    case typeArguments of
      [] -> CCon name constructorTy
      _ -> CTypeApp (CCon name constructorTy) typeArguments (foldr CTyFun resultTy (map exprType arguments))
  applyValue callee argument =
    let remainingResult =
          case exprType callee of
            CTyFun _ result -> result
            _ -> resultTy
     in CApp callee argument remainingResult

listCoreExpr :: CoreType -> [CoreExpr] -> CoreExpr
listCoreExpr elementTy =
  foldr cons nil
 where
  listTy = CTyList elementTy
  nil = constructorApp listNilDataConName [elementTy] [] listTy
  cons headExpr tailExpr =
    constructorApp listConsDataConName [elementTy] [headExpr, tailExpr] listTy

altToCore :: CoreElabEnv -> TypedAlt -> Either TypecheckError CoreAlt
altToCore env (TypedAlt altCon binders body) =
  CoreAlt altCon
    <$> traverse (typedBinderToCore (coreElabSubst env) (coreElabMetas env)) binders
    <*> exprToCore env body

typedBinderToCore :: Subst -> Map.Map Int RName -> TypedBinder -> Either TypecheckError CoreBinder
typedBinderToCore subst metas (TypedBinder name ty) =
  CoreBinder name <$> monoToCoreType subst metas ty

schemeToCoreType :: Scheme -> Either TypecheckError CoreType
schemeToCoreType =
  schemeToCoreTypeWith Map.empty Map.empty

schemeToCoreTypeWith :: Subst -> Map.Map Int RName -> Scheme -> Either TypecheckError CoreType
schemeToCoreTypeWith subst metas (Scheme variables constraints ty) = do
  body <- monoToCoreType subst metas ty
  dictionaryTypes <- traverse (classConstraintCoreType subst metas) constraints
  let qualifiedBody = foldr CTyFun body dictionaryTypes
  pure $
    case variables of
      [] -> qualifiedBody
      _ -> CTyForall variables qualifiedBody

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
    TyApp (TyCon name) arg
      | name == listTyConName ->
          CTyList <$> go arg
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
  TCon _ _ _ ty -> ty
  TNewtypeCon _ _ _ ty _ -> ty
  TTuple _ ty -> ty
  TList _ ty -> ty
  TLam _ _ ty -> ty
  TApp _ _ ty -> ty
  TLet _ _ ty -> ty
  TCase _ _ _ ty -> ty
  TCoerce _ ty -> ty
  TPrim _ _ ty -> ty

typedExprMetaVars :: TypedExpr -> Set.Set Int
typedExprMetaVars expression =
  freeMetaVars (typedExprType expression)
    <> case expression of
      TVar _ scheme typeArguments _ ->
        freeMetaVarsScheme scheme <> Set.unions (map freeMetaVars typeArguments)
      TLit {} -> Set.empty
      TCon _ scheme typeArguments _ ->
        freeMetaVarsScheme scheme <> Set.unions (map freeMetaVars typeArguments)
      TNewtypeCon _ scheme typeArguments _ binder ->
        freeMetaVarsScheme scheme
          <> Set.unions (map freeMetaVars typeArguments)
          <> freeMetaVars (typedBinderType binder)
      TTuple fields _ ->
        Set.unions (map typedExprMetaVars fields)
      TList elements _ ->
        Set.unions (map typedExprMetaVars elements)
      TLam binder body _ ->
        freeMetaVars (typedBinderType binder) <> typedExprMetaVars body
      TApp fn arg _ ->
        typedExprMetaVars fn <> typedExprMetaVars arg
      TLet bindings body _ ->
        Set.unions (map typedBindingMetaVars bindings) <> typedExprMetaVars body
      TCase scrutinee binder alternatives _ ->
        typedExprMetaVars scrutinee
          <> freeMetaVars (typedBinderType binder)
          <> Set.unions (map typedAltMetaVars alternatives)
      TCoerce inner _ ->
        typedExprMetaVars inner
      TPrim _ arguments _ ->
        Set.unions (map typedExprMetaVars arguments)

typedBindingMetaVars :: TypedBinding -> Set.Set Int
typedBindingMetaVars binding =
  freeMetaVarsScheme (typedBindingScheme binding)
    <> typedExprMetaVars (typedBindingRhs binding)

typedAltMetaVars :: TypedAlt -> Set.Set Int
typedAltMetaVars (TypedAlt _ binders body) =
  Set.unions (map (freeMetaVars . typedBinderType) binders) <> typedExprMetaVars body

typedExprFreeTermNames :: TypedExpr -> Set.Set RName
typedExprFreeTermNames = \case
  TVar name _ _ _ ->
    Set.singleton name
  TLit {} ->
    Set.empty
  TCon {} ->
    Set.empty
  TNewtypeCon _ _ _ _ _ ->
    Set.empty
  TTuple fields _ ->
    Set.unions (map typedExprFreeTermNames fields)
  TList elements _ ->
    Set.unions (map typedExprFreeTermNames elements)
  TLam binder body _ ->
    Set.delete (typedBinderName binder) (typedExprFreeTermNames body)
  TApp fn arg _ ->
    typedExprFreeTermNames fn <> typedExprFreeTermNames arg
  TLet bindings body _ ->
    let bindingFreeNames =
          Set.unions (map (typedExprFreeTermNames . typedBindingRhs) bindings)
        localNames =
          Set.fromList (map typedBindingName bindings)
     in (bindingFreeNames <> typedExprFreeTermNames body) `Set.difference` localNames
  TCase scrutinee binder alternatives _ ->
    typedExprFreeTermNames scrutinee
      <> Set.unions (map typedAltFreeTermNames alternatives)
      `Set.difference` Set.singleton (typedBinderName binder)
  TCoerce expression _ ->
    typedExprFreeTermNames expression
  TPrim _ arguments _ ->
    Set.unions (map typedExprFreeTermNames arguments)

typedAltFreeTermNames :: TypedAlt -> Set.Set RName
typedAltFreeTermNames (TypedAlt _ binders body) =
  typedExprFreeTermNames body `Set.difference` Set.fromList (map typedBinderName binders)

typedBinderName :: TypedBinder -> RName
typedBinderName (TypedBinder name _) =
  name

typedBinderType :: TypedBinder -> MonoType
typedBinderType (TypedBinder _ ty) =
  ty

schemeVars :: Scheme -> [RName]
schemeVars (Scheme variables _ _) =
  variables

schemeConstraints :: Scheme -> [ClassConstraint]
schemeConstraints (Scheme _ constraints _) =
  constraints

schemeBody :: Scheme -> MonoType
schemeBody (Scheme _ _ body) =
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
  LFloat {} -> floatMonoType
  LDouble {} -> doubleMonoType
  LChar {} -> charMonoType
  LString {} -> stringMonoType

stringLiteralTypedExpr :: Text -> TypedExpr
stringLiteralTypedExpr value =
  TList [TLit (LChar char) charMonoType | char <- Text.unpack value] stringMonoType

stringLiteralPattern :: Text -> [RPat]
stringLiteralPattern value =
  [RPLit (LChar char) | char <- Text.unpack value]

intMonoType :: MonoType
intMonoType =
  coreTypeToMono intTy

floatMonoType :: MonoType
floatMonoType =
  coreTypeToMono floatTy

doubleMonoType :: MonoType
doubleMonoType =
  coreTypeToMono doubleTy

boolMonoType :: MonoType
boolMonoType =
  coreTypeToMono boolTy

charMonoType :: MonoType
charMonoType =
  coreTypeToMono charTy

unitMonoType :: MonoType
unitMonoType =
  coreTypeToMono unitTy

orderingMonoType :: MonoType
orderingMonoType =
  coreTypeToMono orderingTy

stringMonoType :: MonoType
stringMonoType =
  coreTypeToMono stringTy

filePathMonoType :: MonoType
filePathMonoType =
  stringMonoType

ioErrorMonoType :: MonoType
ioErrorMonoType =
  coreTypeToMono ioErrorTy

ioErrorTypeMonoType :: MonoType
ioErrorTypeMonoType =
  coreTypeToMono ioErrorTypeTy

handleMonoType :: MonoType
handleMonoType =
  coreTypeToMono handleTy

handlePosnMonoType :: MonoType
handlePosnMonoType =
  coreTypeToMono handlePosnTy

ioModeMonoType :: MonoType
ioModeMonoType =
  coreTypeToMono ioModeTy

bufferModeMonoType :: MonoType
bufferModeMonoType =
  coreTypeToMono bufferModeTy

seekModeMonoType :: MonoType
seekModeMonoType =
  coreTypeToMono seekModeTy

exitCodeMonoType :: MonoType
exitCodeMonoType =
  coreTypeToMono exitCodeTy

rationalMonoType :: MonoType
rationalMonoType =
  TyApp (TyCon ratioTyConName) intMonoType

ioMonoType :: MonoType -> MonoType
ioMonoType resultTy =
  TyApp (TyCon ioTyConName) resultTy

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

andM :: Monad m => [m Bool] -> m Bool
andM [] =
  pure True
andM (action : rest) = do
  result <- action
  if result
    then andM rest
    else pure False

throwTypecheck :: TypecheckError -> InferM a
throwTypecheck err = do
  spans <- typecheckSpanStack <$> get
  lift . Left $
    case err of
      TypecheckErrorAt {} ->
        err
      _ ->
        maybe err (`TypecheckErrorAt` err) (listToMaybe spans)

emitTypecheckWarning :: TypecheckWarning -> InferM ()
emitTypecheckWarning warning = do
  spans <- typecheckSpanStack <$> get
  unless (any isStandardLibrarySpan spans) $ do
    let spanned =
          case warning of
            TypecheckWarningAt {} ->
              warning
            _ ->
              maybe warning (`TypecheckWarningAt` warning) (listToMaybe spans)
    modify (\state -> state {typecheckWarnings = typecheckWarnings state <> [spanned]})
 where
  isStandardLibrarySpan sourceRange =
    "<standard-library>" `List.isPrefixOf` spanFile sourceRange

withTypecheckSpan :: Maybe SourceSpan -> InferM a -> InferM a
withTypecheckSpan Nothing action =
  action
withTypecheckSpan (Just sourceRange) action = do
  modify (\state -> state {typecheckSpanStack = sourceRange : typecheckSpanStack state})
  result <- action
  modify (\state -> state {typecheckSpanStack = drop 1 (typecheckSpanStack state)})
  pure result

currentTypecheckSpan :: InferM (Maybe SourceSpan)
currentTypecheckSpan =
  listToMaybe . typecheckSpanStack <$> get

renderMonoType :: MonoType -> Text
renderMonoType =
  renderMonoTypePrec 0

renderClassConstraint :: ClassConstraint -> Text
renderClassConstraint constraint =
  Text.unwords (renderRName (classConstraintClass constraint) : map (renderMonoTypePrec 2) (classConstraintArguments constraint))

renderClassConstraintContext :: ClassConstraintContext -> Text
renderClassConstraintContext = \case
  SuperclassConstraintContext className ->
    "superclass constraints for class `" <> renderRName className <> "`"
  MethodConstraintContext methodName ->
    "method-specific constraints for `" <> renderRName methodName <> "`"
  InstanceConstraintContext instanceHead ->
    "instance context for `" <> Text.pack (show instanceHead) <> "`"
  ExpressionSignatureConstraintContext ->
    "expression type signature constraints"

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

renderInt :: Int -> Text
renderInt =
  Text.pack . show

parensIf :: Bool -> Text -> Text
parensIf needsParens text
  | needsParens = "(" <> text <> ")"
  | otherwise = text
