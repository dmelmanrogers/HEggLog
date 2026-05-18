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
import Data.Maybe (fromMaybe)
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

data DataConstructorInfo = DataConstructorInfo
  { dataConstructorTyVars :: [RName]
  , dataConstructorFields :: [MonoType]
  , dataConstructorResult :: MonoType
  , dataConstructorScheme :: Scheme
  }
  deriving stock (Show, Eq, Ord)

data PatternPlan = PatternPlan
  { patternAltCon :: CoreAltCon
  , patternAltBinders :: [TypedBinder]
  , patternEnv :: TypeEnv
  , patternWrapBody :: TypedExpr -> TypedExpr
  }

data TypedExpr
  = TVar RName Scheme [MonoType] MonoType
  | TLit Literal MonoType
  | TCon RName Scheme [MonoType] MonoType
  | TTuple [TypedExpr] MonoType
  | TList [TypedExpr] MonoType
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
  , typeConstructors :: Map.Map RName Int
  , dataConstructors :: Map.Map RName DataConstructorInfo
  }
  deriving stock (Show, Eq)

type InferM = StateT InferState (Either TypecheckError)

typecheckModuleToCore :: RHsModule -> Either TypecheckError CoreModule
typecheckModuleToCore sourceModule = do
  let sourceDecls = rModuleDecls sourceModule
      typeConstructors = collectTypeConstructors sourceDecls
      tupleArities = collectTupleArities sourceDecls
      preludeValues = collectPreludeValueNames sourceDecls
  ((typedBindings, _typedEnv), finalState) <-
    runInfer typeConstructors $ do
      constructors <- collectDataConstructors sourceDecls
      modify (\state -> state {dataConstructors = Map.union constructors builtinDataConstructors})
      inferBindingGroup Map.empty sourceDecls
  coreBinds <- traverse (bindingToCore (substitution finalState) Map.empty) typedBindings
  preludeCoreBinds <- preludeCoreBindings preludeValues
  let sourceCoreBinds = maybe [] (: []) (bindingGroupCoreBind typedBindings coreBinds)
  coreConstructors <-
    Map.union (tupleConstructorInfos tupleArities)
      <$> constructorInfosToCore (substitution finalState) (dataConstructors finalState)
  let coreModule =
        CoreModule
          { coreModuleName = rModuleName sourceModule
          , coreModuleConstructors = coreConstructors
          , coreModuleBinds =
              case preludeCoreBinds <> sourceCoreBinds of
                [] -> []
                [one] -> [one]
                many -> [CoreRec (concatMap bindPairs many)]
          }
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv coreModule) coreModule of
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

runInfer :: Map.Map RName Int -> InferM a -> Either TypecheckError (a, InferState)
runInfer initialTypeConstructors action =
  let initialState =
        InferState
          { nextMeta = 0
          , substitution = Map.empty
          , nextGeneratedUnique = 100000
          , typeConstructors = initialTypeConstructors
          , dataConstructors = Map.empty
          }
   in swapState <$> runStateT action initialState
 where
  swapState (value, state) =
    (value, state)

collectTypeConstructors :: [RDecl] -> Map.Map RName Int
collectTypeConstructors =
  foldr collect Map.empty
 where
  collect decl acc =
    case decl of
      RDataDecl name params _ _ ->
        Map.insert name (length params) acc
      RNewtypeDecl name params _ _ ->
        Map.insert name (length params) acc
      _ ->
        acc

collectDataConstructors :: [RDecl] -> InferM (Map.Map RName DataConstructorInfo)
collectDataConstructors =
  foldM collect Map.empty
 where
  collect acc = \case
    RDataDecl typeName params constructors _ ->
      foldM (insertConstructor typeName params) acc constructors
    RNewtypeDecl typeName params constructor _ ->
      insertConstructor typeName params acc constructor
    _ ->
      pure acc

  insertConstructor typeName params acc (RConDecl constructorName fields) = do
    fieldTypes <- traverse sourceMonoType fields
    let resultTy = foldl TyApp (TyCon typeName) (map TyVar params)
        scheme = Scheme params (foldr TyFun resultTy fieldTypes)
        info =
          DataConstructorInfo
            { dataConstructorTyVars = params
            , dataConstructorFields = fieldTypes
            , dataConstructorResult = resultTy
            , dataConstructorScheme = scheme
            }
    pure (Map.insert constructorName info acc)

builtinDataConstructors :: Map.Map RName DataConstructorInfo
builtinDataConstructors =
  Map.fromList
    [ (listNilDataConName, DataConstructorInfo [a] [] listA (Scheme [a] listA))
    ,
      ( listConsDataConName
      , DataConstructorInfo
          [a]
          [aTy, listA]
          listA
          (Scheme [a] (TyFun aTy (TyFun listA listA)))
      )
    , (unitDataConName, DataConstructorInfo [] [] unitMonoType (Scheme [] unitMonoType))
    , (maybeNothingDataConName, DataConstructorInfo [a] [] maybeA (Scheme [a] maybeA))
    ,
      ( maybeJustDataConName
      , DataConstructorInfo
          [a]
          [aTy]
          maybeA
          (Scheme [a] (TyFun aTy maybeA))
      )
    ,
      ( eitherLeftDataConName
      , DataConstructorInfo
          [a, b]
          [aTy]
          eitherAB
          (Scheme [a, b] (TyFun aTy eitherAB))
      )
    ,
      ( eitherRightDataConName
      , DataConstructorInfo
          [a, b]
          [bTy]
          eitherAB
          (Scheme [a, b] (TyFun bTy eitherAB))
      )
    , (orderingLTDataConName, DataConstructorInfo [] [] orderingMonoType (Scheme [] orderingMonoType))
    , (orderingEQDataConName, DataConstructorInfo [] [] orderingMonoType (Scheme [] orderingMonoType))
    , (orderingGTDataConName, DataConstructorInfo [] [] orderingMonoType (Scheme [] orderingMonoType))
    ]
 where
  a = preludeTypeVariable "a" (-1001)
  b = preludeTypeVariable "b" (-1002)
  aTy = TyVar a
  bTy = TyVar b
  listA = TyList aTy
  maybeA = TyApp (TyCon maybeTyConName) aTy
  eitherAB = TyApp (TyApp (TyCon eitherTyConName) aTy) bTy

preludeTypeVariable :: Text -> Int -> RName
preludeTypeVariable occurrence unique =
  RName TypeVariableNamespace occurrence unique True

constructorInfosToCore ::
  Subst ->
  Map.Map RName DataConstructorInfo ->
  Either TypecheckError (Map.Map RName CoreConstructorInfo)
constructorInfosToCore subst =
  traverse toCore
 where
  toCore info =
    CoreConstructorInfo (dataConstructorTyVars info)
      <$> traverse (monoToCoreType subst Map.empty) (dataConstructorFields info)
      <*> monoToCoreType subst Map.empty (dataConstructorResult info)

tupleConstructorInfos :: Set.Set Int -> Map.Map RName CoreConstructorInfo
tupleConstructorInfos =
  Map.fromList . map (\arity -> (tupleDataConName arity, tupleConstructorInfo arity)) . Set.toList

tupleConstructorInfo :: Int -> CoreConstructorInfo
tupleConstructorInfo arity =
  CoreConstructorInfo variables fields (CTyTuple fields)
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
    Set.unions [Set.unions (map typeTupleArities fields) | RConDecl _ fields <- constructors]
  RNewtypeDecl _ _ (RConDecl _ fields) _ ->
    Set.unions (map typeTupleArities fields)
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
  RPLit {} -> Set.empty
  RPWildcard -> Set.empty
  RPTuple patterns -> Set.insert (length patterns) (Set.unions (map patternTupleArities patterns))
  RPList patterns -> Set.unions (map patternTupleArities patterns)
  RPAs _ pat -> patternTupleArities pat
  RPIrrefutable pat -> patternTupleArities pat
  RPParen pat -> patternTupleArities pat

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
  RInfixApp lhs _ rhs -> exprPreludeValueNames lhs <> exprPreludeValueNames rhs
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
  RLeftSection expr _ -> exprPreludeValueNames expr
  RRightSection _ expr -> exprPreludeValueNames expr
  RArithmeticSeq start step end ->
    exprPreludeValueNames start <> foldMap exprPreludeValueNames step <> foldMap exprPreludeValueNames end
  RListComp body statements -> exprPreludeValueNames body <> concatMap stmtPreludeValueNames statements
  RExprTypeSig expr _ -> exprPreludeValueNames expr

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
  ["id", "const", "not", "otherwise", "map", "foldr", "length", "filter", "reverse"]

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
    RDataDecl {} ->
      pure acc
    RNewtypeDecl {} ->
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
  (binders, bodyEnv, wrapPatterns) <- inferLambdaPatterns env patterns
  body <- wrapPatterns <$> inferExpr bodyEnv bodyExpr
  pure (foldr wrapLambda body binders)
 where
  wrapLambda binder body =
    TLam binder body (TyFun (typedBinderType binder) (typedExprType body))

inferLambdaPatterns :: TypeEnv -> [RPat] -> InferM ([TypedBinder], TypeEnv, TypedExpr -> TypedExpr)
inferLambdaPatterns initialEnv =
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
            (Map.insert name (Scheme [] (typedBinderType binder)) env)
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
          plan <- inferPatternPlan env patTy pat
          let scrutinee = TVar (typedBinderName binder) (Scheme [] patTy) [] patTy
              wrapOne body =
                TCase
                  scrutinee
                  caseBinder
                  [ TypedAlt
                      (patternAltCon plan)
                      (patternAltBinders plan)
                      (patternWrapBody plan body)
                  ]
                  (typedExprType body)
          go (binders <> [binder]) (patternEnv plan) (wrap . wrapOne) rest

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
        inferPreludeValue name
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
    scrutineeTy <- applyCurrent (typedExprType typedScrutinee)
    resultTy <- freshMeta
    caseBinder <- caseBinderFor scrutineeTy alternatives
    typedAlternatives <- traverse (inferCaseAlt env scrutineeTy caseBinder resultTy) alternatives
    pure (TCase typedScrutinee caseBinder typedAlternatives resultTy)
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
      pure (TCon trueDataConName (Scheme [] boolMonoType) [] boolMonoType)
  | nameOcc name == "False" =
      pure (TCon falseDataConName (Scheme [] boolMonoType) [] boolMonoType)
  | otherwise = do
      constructors <- dataConstructors <$> get
      case Map.lookup name constructors of
        Nothing ->
          case preludeConstructorInfo name of
            Nothing ->
              throwTypecheck (UnsupportedCore0 ("constructor `" <> renderRName name <> "`"))
            Just (coreName, info) -> do
              (instantiatedTy, typeArguments) <- instantiate (dataConstructorScheme info)
              pure (TCon coreName (dataConstructorScheme info) typeArguments instantiatedTy)
        Just info -> do
          (instantiatedTy, typeArguments) <- instantiate (dataConstructorScheme info)
          pure (TCon name (dataConstructorScheme info) typeArguments instantiatedTy)

inferPreludeValue :: RName -> InferM TypedExpr
inferPreludeValue name =
  case preludeValueScheme name of
    Nothing ->
      throwTypecheck (UnknownCore0Variable name)
    Just scheme -> do
      (instantiatedTy, typeArguments) <- instantiate scheme
      pure (TVar name scheme typeArguments instantiatedTy)

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
      case nameOcc name of
        "id" -> Just (Scheme [a] (TyFun aTy aTy))
        "const" -> Just (Scheme [a, b] (TyFun aTy (TyFun bTy aTy)))
        "not" -> Just (Scheme [] (TyFun boolMonoType boolMonoType))
        "otherwise" -> Just (Scheme [] boolMonoType)
        "map" -> Just (Scheme [a, b] (TyFun (TyFun aTy bTy) (TyFun listA listB)))
        "foldr" ->
          Just
            ( Scheme
                [a, b]
                (TyFun (TyFun aTy (TyFun bTy bTy)) (TyFun bTy (TyFun listA bTy)))
            )
        "length" -> Just (Scheme [a] (TyFun listA intMonoType))
        "filter" -> Just (Scheme [a] (TyFun (TyFun aTy boolMonoType) (TyFun listA listA)))
        "reverse" -> Just (Scheme [a] (TyFun listA listA))
        _ -> Nothing
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = TyVar a
  bTy = TyVar b
  listA = TyList aTy
  listB = TyList bTy

inferPrimitive :: TypeEnv -> RExpr -> RName -> RExpr -> InferM TypedExpr
inferPrimitive env lhs op rhs =
  case nameOcc op of
    ":" -> inferExpr env (RApp (RApp (RCon op) lhs) rhs)
    "+" -> fixedInt PrimAdd
    "-" -> fixedInt PrimSub
    "*" -> fixedInt PrimMul
    "/" -> fixedInt PrimDiv
    "<" -> fixedCompare PrimLt
    "==" -> equality
    "&&" -> shortCircuit falseTyped trueDataConName
    "||" -> shortCircuit trueTyped falseDataConName
    other -> throwTypecheck (UnsupportedCore0 ("operator `" <> other <> "`"))
 where
  trueTyped = TCon trueDataConName (Scheme [] boolMonoType) [] boolMonoType
  falseTyped = TCon falseDataConName (Scheme [] boolMonoType) [] boolMonoType

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

inferCaseAlt :: TypeEnv -> MonoType -> TypedBinder -> MonoType -> RAlt -> InferM TypedAlt
inferCaseAlt env scrutineeTy _caseBinder resultTy (RAlt pat rhs whereDecls) = do
  plan <- inferPatternPlan env scrutineeTy pat
  bodyExpr <- rhsToExpr rhs whereDecls
  typedBody <- patternWrapBody plan <$> inferExpr (patternEnv plan) bodyExpr
  unify resultTy (typedExprType typedBody)
  pure (TypedAlt (patternAltCon plan) (patternAltBinders plan) typedBody)

inferPatternPlan :: TypeEnv -> MonoType -> RPat -> InferM PatternPlan
inferPatternPlan env expectedTy = \case
  RPVar name ->
    pure
      PatternPlan
        { patternAltCon = DefaultAlt
        , patternAltBinders = []
        , patternEnv = Map.insert name (Scheme [] expectedTy) env
        , patternWrapBody = id
        }
  RPWildcard ->
    pure
      PatternPlan
        { patternAltCon = DefaultAlt
        , patternAltBinders = []
        , patternEnv = env
        , patternWrapBody = id
        }
  RPLit literal -> do
    unify expectedTy (literalMonoType literal)
    pure
      PatternPlan
        { patternAltCon = LiteralAlt literal
        , patternAltBinders = []
        , patternEnv = env
        , patternWrapBody = id
        }
  RPCon name args ->
    inferConstructorPattern env expectedTy name args
  RPTuple patterns ->
    inferTuplePattern env expectedTy patterns
  RPList patterns ->
    inferListPattern env expectedTy patterns
  RPParen pat ->
    inferPatternPlan env expectedTy pat
  pat ->
    throwTypecheck (UnsupportedCore0 ("pattern " <> renderPatternShape pat))

inferConstructorPattern :: TypeEnv -> MonoType -> RName -> [RPat] -> InferM PatternPlan
inferConstructorPattern env expectedTy name args
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
              inferKnownConstructorPattern env expectedTy coreName args info
        Just info -> do
          inferKnownConstructorPattern env expectedTy name args info

inferKnownConstructorPattern :: TypeEnv -> MonoType -> RName -> [RPat] -> DataConstructorInfo -> InferM PatternPlan
inferKnownConstructorPattern env expectedTy name args info = do
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
      }

inferListPattern :: TypeEnv -> MonoType -> [RPat] -> InferM PatternPlan
inferListPattern env expectedTy patterns = do
  elementTy <- freshMeta
  unify expectedTy (TyList elementTy)
  case patterns of
    [] ->
      pure (nullaryConstructorPlan env listNilDataConName)
    headPat : tailPats ->
      inferConstructorPattern env expectedTy listConsDataConName [headPat, RPList tailPats]

nullaryConstructorPlan :: TypeEnv -> RName -> PatternPlan
nullaryConstructorPlan env name =
  PatternPlan
    { patternAltCon = ConstructorAlt name
    , patternAltBinders = []
    , patternEnv = env
    , patternWrapBody = id
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
              , fieldPatternEnv = Map.singleton name (Scheme [] fieldTy)
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
      nestedPlan <- inferPatternPlan Map.empty fieldTy pat
      let scrutinee = TVar (typedBinderName fieldBinder) (Scheme [] fieldTy) [] fieldTy
          wrap body =
            TCase
              scrutinee
              nestedCaseBinder
              [ TypedAlt
                  (patternAltCon nestedPlan)
                  (patternAltBinders nestedPlan)
                  (patternWrapBody nestedPlan body)
              ]
              (typedExprType body)
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

caseBinderFor :: MonoType -> [RAlt] -> InferM TypedBinder
caseBinderFor scrutineeTy alternatives =
  case [name | RAlt (RPVar name) _ _ <- alternatives] of
    name : _ ->
      pure (TypedBinder name scrutineeTy)
    [] ->
      freshTermBinder "$case" scrutineeTy

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
typeConstructorMonoType name = do
  knownTypes <- typeConstructors <$> get
  if Map.member name knownTypes
    then pure (TyCon name)
    else
      case nameOcc name of
        "Int" -> pure intMonoType
        "Bool" -> pure boolMonoType
        "Char" -> pure charMonoType
        "String" -> pure stringMonoType
        "Maybe" -> pure (TyCon maybeTyConName)
        "Either" -> pure (TyCon eitherTyConName)
        "Ordering" -> pure orderingMonoType
        "()" -> pure unitMonoType
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

preludeCoreBindings :: [RName] -> Either TypecheckError [CoreBind]
preludeCoreBindings names =
  pure $
    case pairs of
      [] -> []
      _ -> [CoreRec pairs]
 where
  pairs =
    [ pair
    | name <- names
    , pair <- maybe [] (: []) (preludeCorePair name)
    ]
      <> [reverseGoCorePair | any ((== "reverse") . nameOcc) names]

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
    "map" ->
      Just (binderFor name mapTy, mapRhs name)
    "foldr" ->
      Just (binderFor name foldrTy, foldrRhs name)
    "length" ->
      Just (binderFor name lengthTy, lengthRhs name)
    "filter" ->
      Just (binderFor name filterTy, filterRhs name)
    "reverse" ->
      Just (binderFor name reverseTy, reverseRhs)
    _ -> Nothing
 where
  a = preludeTypeVariable "a" (-1201)
  b = preludeTypeVariable "b" (-1202)
  aTy = CTyVar a
  bTy = CTyVar b
  listA = CTyList aTy
  listB = CTyList bTy

  idTy = CTyForall [a] (CTyFun aTy aTy)
  constTy = CTyForall [a, b] (CTyFun aTy (CTyFun bTy aTy))
  notTy = CTyFun boolTy boolTy
  mapTy = CTyForall [a, b] (CTyFun (CTyFun aTy bTy) (CTyFun listA listB))
  foldrTy = CTyForall [a, b] (CTyFun (CTyFun aTy (CTyFun bTy bTy)) (CTyFun bTy (CTyFun listA bTy)))
  lengthTy = CTyForall [a] (CTyFun listA intTy)
  filterTy = CTyForall [a] (CTyFun (CTyFun aTy boolTy) (CTyFun listA listA))
  reverseTy = CTyForall [a] (CTyFun listA listA)

  idX = preludeTermName "$id_x" (-3001)
  constX = preludeTermName "$const_x" (-3002)
  constY = preludeTermName "$const_y" (-3003)
  notX = preludeTermName "$not_x" (-3004)
  notCase = preludeTermName "$not_case" (-3005)

  mapF = preludeTermName "$map_f" (-3010)
  mapXs = preludeTermName "$map_xs" (-3011)
  mapY = preludeTermName "$map_y" (-3012)
  mapYs = preludeTermName "$map_ys" (-3013)
  mapCase = preludeTermName "$map_case" (-3014)

  foldrF = preludeTermName "$foldr_f" (-3020)
  foldrZ = preludeTermName "$foldr_z" (-3021)
  foldrXs = preludeTermName "$foldr_xs" (-3022)
  foldrY = preludeTermName "$foldr_y" (-3023)
  foldrYs = preludeTermName "$foldr_ys" (-3024)
  foldrCase = preludeTermName "$foldr_case" (-3025)

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

  mapRhs functionName =
    CTypeLam [a, b] (lam mapF (CTyFun aTy bTy) (lam mapXs listA mapBody)) mapTy
   where
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

bindingToCore :: Subst -> Map.Map Int RName -> TypedBinding -> Either TypecheckError CoreBind
bindingToCore subst ambientMetas binding = do
  let scheme = typedBindingScheme binding
      initialMetas = Map.union (typedBindingGeneralizedMetas binding) ambientMetas
      allMetas = Map.union initialMetas (ambiguousExprMetas initialMetas (typedBindingRhs binding))
  binderTy <- schemeToCoreType scheme
  rhs <- exprToCore subst allMetas (typedBindingRhs binding)
  let rhsWithTypeLambdas =
        case schemeVars scheme of
          [] -> rhs
          variables -> CTypeLam variables rhs binderTy
  pure (CoreNonRec (CoreBinder (typedBindingName binding) binderTy) rhsWithTypeLambdas)

ambiguousExprMetas :: Map.Map Int RName -> TypedExpr -> Map.Map Int RName
ambiguousExprMetas knownMetas expression =
  Map.fromList
    [ (meta, ambiguousMetaName meta)
    | meta <- Set.toList (typedExprMetaVars expression)
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
  TCon name scheme typeArguments ty -> do
    constructorTy <- schemeToCoreTypeWith subst metas scheme
    resultTy <- monoToCoreType subst metas ty
    coreTypeArguments <- traverse (monoToCoreType subst metas) typeArguments
    let constructorExpr = CCon name constructorTy
    pure $
      case schemeVars scheme of
        [] -> CCon name resultTy
        _ -> CTypeApp constructorExpr coreTypeArguments resultTy
  TTuple fields ty -> do
    coreFields <- traverse (exprToCore subst metas) fields
    resultTy <- monoToCoreType subst metas ty
    fieldTypes <- case applySubst subst ty of
      TyTuple types -> traverse (monoToCoreType subst metas) types
      other -> Left (TypeMismatch (TyTuple []) other)
    pure (constructorApp (tupleDataConName (length fields)) fieldTypes coreFields resultTy)
  TList elements ty -> do
    coreElements <- traverse (exprToCore subst metas) elements
    elementTy <- case applySubst subst ty of
      TyList element -> monoToCoreType subst metas element
      other -> Left (TypeMismatch (TyList (TyMeta (-1))) other)
    pure (listCoreExpr elementTy coreElements)
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
          (fromMaybe (CoreRec []) (bindingGroupCoreBind bindings coreBindings))
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
             in CoreValidate.constructorFunctionType (CoreConstructorInfo [] fields resultTy)
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
  TCon _ _ _ ty -> ty
  TTuple _ ty -> ty
  TList _ ty -> ty
  TLam _ _ ty -> ty
  TApp _ _ ty -> ty
  TLet _ _ ty -> ty
  TCase _ _ _ ty -> ty
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

unitMonoType :: MonoType
unitMonoType =
  coreTypeToMono unitTy

orderingMonoType :: MonoType
orderingMonoType =
  coreTypeToMono orderingTy

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
