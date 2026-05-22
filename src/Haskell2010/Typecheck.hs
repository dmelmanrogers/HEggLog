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
import Control.Monad (foldM, unless, when)
import Control.Monad.State.Strict (State, StateT, get, lift, modify, runState, runStateT)
import Data.Foldable (traverse_)
import qualified Data.Graph as Graph
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names
import Haskell2010.Renamed
import Haskell2010.Syntax (Literal (..))
import qualified Haskell2010.Syntax as S
import Syntax.Span (SourceSpan, renderSourceDiagnostic)

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
          , defaultTypes = [intMonoType]
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
    fieldTypes <- traverse sourceMonoType sourceFields
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
    , (builtinShowClassName, showInfo)
    , (builtinReadClassName, readInfo)
    , (builtinEnumClassName, enumInfo)
    , (builtinBoundedClassName, boundedInfo)
    , (builtinFunctorClassName, functorInfo)
    , (builtinMonadClassName, monadInfo)
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

builtinFunctorClassName :: RName
builtinFunctorClassName =
  preludeClassName "Functor" (-1390)

builtinMonadClassName :: RName
builtinMonadClassName =
  preludeClassName "Monad" (-1360)

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
        "Show" -> builtinShowClassName
        "Read" -> builtinReadClassName
        "Enum" -> builtinEnumClassName
        "Bounded" -> builtinBoundedClassName
        "Functor" -> builtinFunctorClassName
        "Monad" -> builtinMonadClassName
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
          "Show" -> builtinShowClassName
          "Read" -> builtinReadClassName
          "Enum" -> builtinEnumClassName
          "Bounded" -> builtinBoundedClassName
          "Functor" -> builtinFunctorClassName
          "Monad" -> builtinMonadClassName
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
    ]
 where
  a = preludeTypeVariable "a" (-1001)
  b = preludeTypeVariable "b" (-1002)
  aTy = TyVar a
  bTy = TyVar b
  listA = TyList aTy
  maybeA = TyApp (TyCon maybeTyConName) aTy
  eitherAB = TyApp (TyApp (TyCon eitherTyConName) aTy) bTy
  maybeHandleMonoType = TyApp (TyCon maybeTyConName) handleMonoType
  maybeFilePathMonoType = TyApp (TyCon maybeTyConName) filePathMonoType
  ioErrorTypeDataConstructorInfo =
    positionalDataConstructorInfo [] [] ioErrorTypeMonoType (Scheme [] [] ioErrorTypeMonoType) CoreDataConstructor

preludeTypeVariable :: Text -> Int -> RName
preludeTypeVariable occurrence unique =
  RName TypeVariableNamespace occurrence unique True

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
  , "nullPtr"
  , "castPtr"
  , "nullFunPtr"
  , "castFunPtr"
  , "castFunPtrToPtr"
  , "castPtrToFunPtr"
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
  , "quot"
  , "rem"
  , "div"
  , "mod"
  , "quotRem"
  , "divMod"
  , "toInteger"
  ]

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
  case defaults of
    [] -> pure ()
    defaultTy : _ -> do
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
      traverse_ (\meta -> unify (TyMeta meta) defaultTy) candidates

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

defaultableConstraintMetas :: Set.Set Int -> [ClassConstraint] -> [Int]
defaultableConstraintMetas protectedMetas constraints =
  [ meta
  | (meta, metaConstraints) <- Map.toAscList constraintsByMeta
  , meta `Set.notMember` protectedMetas
  , all (isDefaultingCompatibleConstraint meta) metaConstraints
  , any ((== builtinNumClassName) . constraintClassName) metaConstraints
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
    , builtinShowClassName
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
      pure [intMonoType]
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
    RInstanceDecl [] instanceHead decls -> do
      dictionary <- inferInstanceDictionary env instanceHead decls
      validateInstanceDictionary acc dictionary
      pure (acc <> [dictionary])
    RInstanceDecl constraints instanceHead _ ->
      unsupportedSourceClassConstraintContext (InstanceConstraintContext instanceHead) constraints
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
  fieldTypes <- concat <$> traverse (traverse sourceMonoType . conDeclFieldTypes) constructors
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
  fieldTypes <- concat <$> traverse (traverse sourceMonoType . conDeclFieldTypes) constructors
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
  fieldTypes <- concat <$> traverse (traverse sourceMonoType . conDeclFieldTypes) constructors
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
  fieldTypes <- concat <$> traverse (traverse sourceMonoType . conDeclFieldTypes) constructors
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
  fieldTypes <- concat <$> traverse (traverse sourceMonoType . conDeclFieldTypes) constructors
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

inferInstanceDictionary :: TypeEnv -> RHsType -> [RDecl] -> InferM TypedInstanceDictionary
inferInstanceDictionary env instanceHead decls = do
  (className, instanceType) <- splitInstanceHead instanceHead
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
      , typedInstanceContext = []
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
            "$read_append" -> Just (Scheme [a] [] (TyFun listA (TyFun listA listA)))
            "$read_exact" -> Just (Scheme [] [] (TyFun stringMonoType (TyFun stringMonoType (TyList (TyTuple [unitMonoType, stringMonoType])))))
            "$read_default_list" -> Just (Scheme [a] [] (TyFun readSA readListSA))
            "$read_paren" -> Just (Scheme [a] [] (TyFun boolMonoType (TyFun readSA readSA)))
            "$read_lex" -> Just (Scheme [] [] (TyFun stringMonoType (TyList (TyTuple [stringMonoType, stringMonoType]))))
            "$read_int" -> Just (Scheme [] [] intReadS)
            "$read_bool" -> Just (Scheme [] [] boolReadS)
            "$read_char" -> Just (Scheme [] [] charReadS)
            "$read_string" -> Just (Scheme [] [] stringReadS)
            "putStrLn" -> Just (Scheme [] [] (TyFun stringMonoType ioUnit))
            "getLine" -> Just (Scheme [] [] (ioMonoType stringMonoType))
            "print" -> Just (Scheme [a] [singleClassConstraint builtinShowClassName aTy] (TyFun aTy ioUnit))
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
            "void" -> Just (Scheme [a] [] (TyFun (ioMonoType aTy) ioUnit))
            "maybeNew" -> Just (Scheme [a] [] (TyFun (TyFun aTy (ioMonoType ptrA)) (TyFun maybeA (ioMonoType ptrA))))
            "maybeWith" -> Just (Scheme [a, b, c] [] (TyFun (TyFun aTy (TyFun (TyFun ptrB (ioMonoType cTy)) (ioMonoType cTy))) (TyFun maybeA (TyFun (TyFun ptrB (ioMonoType cTy)) (ioMonoType cTy)))))
            "maybePeek" -> Just (Scheme [a, b] [] (TyFun (TyFun ptrA (ioMonoType bTy)) (TyFun ptrA (ioMonoType maybeB))))
            _ -> Nothing
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  c = preludeTypeVariable "c" (-1203)
  aTy = TyVar a
  bTy = TyVar b
  cTy = TyVar c
  listA = TyList aTy
  listB = TyList bTy
  tupleAB = TyTuple [aTy, bTy]
  maybeA = TyApp (TyCon maybeTyConName) aTy
  maybeB = TyApp (TyCon maybeTyConName) bTy
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
    "/" -> fixedInt PrimDiv
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

  fixedInt prim = do
    typedLhs <- inferExpr env lhs
    typedRhs <- inferExpr env rhs
    unify (typedExprType typedLhs) intMonoType
    unify (typedExprType typedRhs) intMonoType
    pure (TPrim prim [typedLhs, typedRhs] intMonoType)

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

unsupportedSourceClassConstraintContext :: ClassConstraintContext -> [RHsType] -> InferM a
unsupportedSourceClassConstraintContext context sourceConstraints = do
  constraints <- traverse sourceClassConstraint sourceConstraints
  throwUnsupportedClassConstraintContext context constraints

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
        "Bool" -> pure boolMonoType
        "Char" -> pure charMonoType
        "Rational" -> pure rationalMonoType
        "String" -> pure stringMonoType
        "ShowS" -> pure (TyFun stringMonoType stringMonoType)
        "FilePath" -> pure filePathMonoType
        "[]" -> pure (TyCon listTyConName)
        "IO" -> pure (TyCon ioTyConName)
        "IOError" -> pure ioErrorMonoType
        "IOErrorType" -> pure ioErrorTypeMonoType
        "Handle" -> pure handleMonoType
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
        "CStringLen" -> pure (TyCon name)
        "CWStringLen" -> pure (TyCon name)
        other
          | isBuiltinForeignTypeOccurrence other -> pure (TyCon name)
          | otherwise -> throwTypecheck (UnsupportedCore0 ("type constructor `" <> other <> "`"))

builtinTypeConstructorInfo :: RName -> Maybe TypeConstructorInfo
builtinTypeConstructorInfo name
  | not (nameExternal name) = Nothing
  | otherwise =
      typeConstructorInfo
        <$> case nameOcc name of
          "Int" -> Just 0
          "Integer" -> Just 0
          "Bool" -> Just 0
          "Char" -> Just 0
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
          "Maybe" -> Just 1
          "Either" -> Just 2
          "Ordering" -> Just 0
          "()" -> Just 0
          "FinalizerPtr" -> Just 1
          "FinalizerEnvPtr" -> Just 2
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
  Set.fromList
    [ "Int"
    , "Bool"
    , "Char"
    , "Float"
    , "Double"
    , "Word"
    , "Int8"
    , "Int16"
    , "Int32"
    , "Int64"
    , "Word8"
    , "Word16"
    , "Word32"
    , "Word64"
    , "CString"
    , "CWString"
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
  expandedNames = List.nub (names <> concatMap preludeCoreDependencies names)
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
    "readParen" -> readSupportPreludeNames
    occurrence
      | "$read_" `Text.isPrefixOf` occurrence -> []
    _ -> []

classPreludeSupportNames :: Map.Map RName ClassInfo -> [RName]
classPreludeSupportNames classes =
  enumSupport <> readSupport
 where
  enumSupport
    | builtinEnumClassName `Map.member` classes = derivedMapName : arithmeticSequencePreludeNames
    | otherwise = []
  readSupport
    | builtinReadClassName `Map.member` classes = readSupportPreludeNames
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
    "putStrLn" ->
      Just
        ( binderFor name putStrLnTy
        , lam putStrLnS stringTy (CPrimOp PrimPutStrLn [var putStrLnS stringTy] ioUnitTy)
        )
    "getLine" ->
      Just (binderFor name getLineTy, CPrimOp PrimGetLine [] getLineTy)
    "print" ->
      Just (binderFor name printTy, printRhs)
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
      Just (binderFor name voidTy, voidRhs)
    "maybeNew" ->
      Just (binderFor name maybeNewTy, maybeNewRhs)
    "maybeWith" ->
      Just (binderFor name maybeWithTy, maybeWithRhs)
    "maybePeek" ->
      Just (binderFor name maybePeekTy, maybePeekRhs)
    _ -> readPreludeCorePair name <|> arithmeticSequenceCorePair name
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  c = preludeTypeVariable "c" (-1203)
  aTy = CTyVar a
  bTy = CTyVar b
  cTy = CTyVar c
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
  putStrLnTy = CTyFun stringTy ioUnitTy
  getLineTy = ioTy stringTy
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
  voidTy = CTyForall [a] (CTyFun ioA ioUnitTy)
  maybeNewTy = CTyForall [a] (CTyFun (CTyFun aTy (ioTy ptrA)) (CTyFun maybeA (ioTy ptrA)))
  maybeWithTy = CTyForall [a, b, c] (CTyFun (CTyFun aTy (CTyFun (CTyFun ptrB (ioTy cTy)) (ioTy cTy))) (CTyFun maybeA (CTyFun (CTyFun ptrB (ioTy cTy)) (ioTy cTy))))
  maybePeekTy = CTyForall [a, b] (CTyFun (CTyFun ptrA (ioTy bTy)) (CTyFun ptrA (ioTy maybeB)))

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
  voidAction = preludeTermName "$void_action" (-3524)
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
      CPrimOp PrimPutStrLn [shownValue] ioUnitTy

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

  voidRhs =
    CTypeLam [a] (lam voidAction ioA (CPrimOp PrimIOThen [var voidAction ioA, ioReturn unitTy unitValue] ioUnitTy)) voidTy

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
    , maybe [] showInstances (Map.lookup builtinShowClassName classes)
    , maybe [] readInstances (Map.lookup builtinReadClassName classes)
    , maybe [] enumInstances (Map.lookup builtinEnumClassName classes)
    , maybe [] boundedInstances (Map.lookup builtinBoundedClassName classes)
    , maybe [] functorInstances (Map.lookup builtinFunctorClassName classes)
    , maybe [] monadInstances (Map.lookup builtinMonadClassName classes)
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
    ]

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
    ]

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
    ]

  realInstances info =
    [ BuiltinInstanceDictionary
        (classInfoName info)
        intMonoType
        (preludeTermName "$fRealInt" (-1571))
        [intToRationalMethod]
    ]

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
    ]

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
        unitMonoType
        (preludeTermName "$fReadUnit" (-1705))
        [unitReadsPrecMethod, unitReadListMethod]
    ]

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
    (className, [TyCon typeName])
      | className == builtinFunctorClassName && typeName == listTyConName -> True
    (className, [TyCon typeName])
      | className == builtinMonadClassName && typeName == listTyConName -> True
    _ -> False

overlapsBuiltinStructuralInstanceConstraint :: ClassConstraint -> Bool
overlapsBuiltinStructuralInstanceConstraint wanted =
  case (classConstraintClass wanted, classConstraintArguments wanted) of
    (className, [argument])
      | className == builtinEqClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$eq_list_overlap" (-1598))))
    (className, [argument])
      | className == builtinOrdClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$ord_list_overlap" (-1597))))
    (className, [argument])
      | className == builtinShowClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$show_list_overlap" (-1599))))
    (className, [argument])
      | className == builtinReadClassName ->
          typesMayUnify argument (TyList (TyVar (preludeTypeVariable "$read_list_overlap" (-1600))))
    (className, [argument])
      | className == builtinFunctorClassName ->
          typesMayUnify argument (TyCon listTyConName)
    (className, [argument])
      | className == builtinMonadClassName ->
          typesMayUnify argument (TyCon listTyConName)
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
    tuple2IntCore value oneInt

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
  binaryMethod "$quotRem_int" (-1867) intTy rationalCoreType $ \lhs rhs ->
    tuple2IntCore (intQuot lhs rhs) (intRem lhs rhs)

intDivModMethod :: CoreExpr
intDivModMethod =
  binaryMethod "$divMod_int" (-1868) intTy rationalCoreType $ \lhs rhs ->
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
  CTyTuple [intTy, intTy]

tuple2IntCore :: CoreExpr -> CoreExpr -> CoreExpr
tuple2IntCore lhs rhs =
  constructorApp (tupleDataConName 2) [intTy, intTy] [lhs, rhs] rationalCoreType

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

intReadsPrecMethod, boolReadsPrecMethod, charReadsPrecMethod, orderingReadsPrecMethod, unitReadsPrecMethod :: CoreExpr
intReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_int" (-2707) intTy (CVar readIntName readIntCoreType)
boolReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_bool" (-2708) boolTy (CVar readBoolName readBoolCoreType)
charReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_char" (-2709) charTy (CVar readCharName readCharCoreType)
orderingReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_ordering" (-2710) orderingTy orderingReadParserCore
unitReadsPrecMethod =
  readsPrecFromParserMethod "$reads_prec_unit" (-2711) unitTy unitReadParserCore

intReadListMethod, boolReadListMethod, charReadListMethod, orderingReadListMethod, unitReadListMethod :: CoreExpr
intReadListMethod =
  readListFromParserMethod intTy (CVar readIntName readIntCoreType)
boolReadListMethod =
  readListFromParserMethod boolTy (CVar readBoolName readBoolCoreType)
charReadListMethod =
  CVar readStringName readStringCoreType
orderingReadListMethod =
  readListFromParserMethod orderingTy orderingReadParserCore
unitReadListMethod =
  readListFromParserMethod unitTy unitReadParserCore

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

unitReadParserCore :: CoreExpr
unitReadParserCore =
  coreLam inputName stringTy (readConstantParserCore unitTy "()" (CCon unitDataConName unitTy) (CVar inputName stringTy))
 where
  inputName = builtinLocalTermName "$read_unit_input" (-2713)

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
  | builtinMonadClassName `Map.member` classes =
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

rationalMonoType :: MonoType
rationalMonoType =
  TyTuple [intMonoType, intMonoType]

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
  let spanned =
        case warning of
          TypecheckWarningAt {} ->
            warning
          _ ->
            maybe warning (`TypecheckWarningAt` warning) (listToMaybe spans)
  modify (\state -> state {typecheckWarnings = typecheckWarnings state <> [spanned]})

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
