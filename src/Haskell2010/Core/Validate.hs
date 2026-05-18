module Haskell2010.Core.Validate
  ( CoreConstructorInfo (..)
  , CoreValidationEnv (..)
  , CoreValidationError (..)
  , constructorFunctionType
  , constructorFieldsForResult
  , defaultValidationEnv
  , emptyValidationEnv
  , literalType
  , moduleValidationEnv
  , renderValidationError
  , validateExpr
  , validateExprWith
  , validateModule
  )
where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Pretty (renderCoreAltCon, renderCorePrimOp, renderCoreType)
import Haskell2010.Core.Syntax
import Haskell2010.Names (Namespace (..), RName, nameNamespace, renderNamespace, renderRName)
import Haskell2010.Syntax (Literal (..))

data CoreValidationEnv = CoreValidationEnv
  { coreValueTypes :: Map.Map RName CoreType
  , coreConstructorTypes :: Map.Map RName CoreConstructorInfo
  }
  deriving stock (Show, Eq, Ord)

data CoreValidationError
  = CoreDuplicateBinder RName
  | CoreInvalidBinderNamespace RName Namespace
  | CoreUnboundVariable RName
  | CoreUnknownConstructor RName
  | CoreTypeMismatch CoreType CoreType
  | CoreExpectedFunction CoreType
  | CoreExpectedForall CoreType
  | CoreTypeApplicationArityMismatch Int Int
  | CoreAppArgumentMismatch CoreType CoreType
  | CoreCaseBinderMismatch CoreType CoreType
  | CoreAlternativeTypeMismatch CoreAltCon CoreType CoreType
  | CoreAlternativeArityMismatch CoreAltCon Int Int
  | CoreConstructorArityMismatch RName Int Int
  | CoreConstructorFieldMismatch RName Int CoreType CoreType
  | CoreConstructorResultMismatch RName CoreType CoreType
  | CoreMultipleDefaultAlternatives Int
  | CorePrimitiveArityMismatch CorePrimOp Int Int
  | CorePrimitiveArgumentMismatch CorePrimOp Int CoreType CoreType
  | CorePrimitiveResultMismatch CorePrimOp CoreType CoreType
  deriving stock (Show, Eq, Ord)

type Scope = Map.Map RName CoreType

emptyValidationEnv :: CoreValidationEnv
emptyValidationEnv =
  CoreValidationEnv
    { coreValueTypes = Map.empty
    , coreConstructorTypes = Map.empty
    }

defaultValidationEnv :: CoreValidationEnv
defaultValidationEnv =
  emptyValidationEnv
    { coreConstructorTypes =
        Map.fromList
          [ (trueDataConName, CoreConstructorInfo [] [] boolTy)
          , (falseDataConName, CoreConstructorInfo [] [] boolTy)
          ]
    }

moduleValidationEnv :: CoreModule -> CoreValidationEnv
moduleValidationEnv coreModule =
  defaultValidationEnv
    { coreConstructorTypes =
        Map.union (coreModuleConstructors coreModule) (coreConstructorTypes defaultValidationEnv)
    }

validateModule :: CoreValidationEnv -> CoreModule -> Either [CoreValidationError] ()
validateModule env (CoreModule _ _ binds) =
  collectValidations
    [ failWith duplicateErrors
    , collectValidations (map (validateScopedBind env moduleScope) binds)
    ]
 where
  moduleBinders =
    concatMap bindersOf binds
  moduleScope =
    Map.union (scopeFromBinders moduleBinders) (coreValueTypes env)
  duplicateErrors =
    map CoreDuplicateBinder (duplicates (concatMap bindBinderNames binds))

validateExpr :: CoreExpr -> Either [CoreValidationError] ()
validateExpr =
  validateExprWith defaultValidationEnv

validateExprWith :: CoreValidationEnv -> CoreExpr -> Either [CoreValidationError] ()
validateExprWith env expression =
  collectValidations
    [ failWith duplicateErrors
    , validateScopedExpr env (coreValueTypes env) expression
    ]
 where
  duplicateErrors =
    map CoreDuplicateBinder (duplicates (exprBinderNames expression))

validateScopedExpr :: CoreValidationEnv -> Scope -> CoreExpr -> Either [CoreValidationError] ()
validateScopedExpr env scope = \case
  CVar name ty ->
    case Map.lookup name scope <|> Map.lookup name (coreValueTypes env) of
      Nothing ->
        Left [CoreUnboundVariable name]
      Just expectedTy ->
        checkType expectedTy ty
  CLit literal ty ->
    checkType (literalType literal) ty
  CCon name ty ->
    case Map.lookup name (coreConstructorTypes env) of
      Nothing ->
        Left [CoreUnknownConstructor name]
      Just info ->
        checkType (constructorFunctionType info) ty
  CLam binder body ty ->
    collectValidations
      [ validateBinder binder
      , validateScopedExpr env (extendScope [binder] scope) body
      , checkType (CTyFun (coreBinderType binder) (exprType body)) ty
      ]
  CApp fn arg ty ->
    collectValidations $
      [ validateScopedExpr env scope fn
      , validateScopedExpr env scope arg
      ]
        <> validateApplication (exprType fn) (exprType arg) ty
  CTypeLam variables body ty ->
    collectValidations
      [ collectValidations (map validateTypeBinder variables)
      , failWith (map CoreDuplicateBinder (duplicates variables))
      , validateScopedExpr env scope body
      , checkType (CTyForall variables (exprType body)) ty
      ]
  CTypeApp fn arguments ty ->
    collectValidations
      [ validateScopedExpr env scope fn
      , validateTypeApplication (exprType fn) arguments ty
      ]
  CLet bind body ty ->
    collectValidations
      [ validateScopedBind env scope bind
      , validateScopedExpr env (extendScope (bindersOf bind) scope) body
      , checkType (exprType body) ty
      ]
  CCase scrutinee binder alternatives ty ->
    collectValidations
      [ validateBinder binder
      , validateScopedExpr env scope scrutinee
      , checkCaseBinder (exprType scrutinee) (coreBinderType binder)
      , failWith (defaultAlternativeErrors alternatives)
      , collectValidations (map (validateCaseAlt env (extendScope [binder] scope) binder ty) alternatives)
      ]
  CPrimOp op arguments ty ->
    collectValidations $
      map (validateScopedExpr env scope) arguments
        <> validatePrimitive op arguments ty

validateScopedBind :: CoreValidationEnv -> Scope -> CoreBind -> Either [CoreValidationError] ()
validateScopedBind env scope = \case
  CoreNonRec binder rhs ->
    collectValidations
      [ validateBinder binder
      , validateScopedExpr env scope rhs
      , checkType (coreBinderType binder) (exprType rhs)
      ]
  CoreRec pairs ->
    let binders = map fst pairs
        recScope = extendScope binders scope
     in collectValidations $
          map validateBinder binders
            <> map (validateRecRhs recScope) pairs
 where
  validateRecRhs recScope (binder, rhs) =
    collectValidations
      [ validateScopedExpr env recScope rhs
      , checkType (coreBinderType binder) (exprType rhs)
      ]

validateCaseAlt ::
  CoreValidationEnv ->
  Scope ->
  CoreBinder ->
  CoreType ->
  CoreAlt ->
  Either [CoreValidationError] ()
validateCaseAlt env scope caseBinder caseResultTy (CoreAlt altCon binders body) =
  collectValidations
    [ collectValidations (map validateBinder binders)
    , validateAltCon env (coreBinderType caseBinder) altCon binders
    , validateScopedExpr env (extendScope binders scope) body
    , checkAltType altCon caseResultTy (exprType body)
    ]

validateAltCon :: CoreValidationEnv -> CoreType -> CoreAltCon -> [CoreBinder] -> Either [CoreValidationError] ()
validateAltCon env scrutineeTy altCon binders =
  case altCon of
    DefaultAlt ->
      checkAltArity altCon 0 binders
    LiteralAlt literal ->
      collectValidations
        [ checkAltArity altCon 0 binders
        , checkAltPatternType altCon scrutineeTy (literalType literal)
        ]
    ConstructorAlt name ->
      case Map.lookup name (coreConstructorTypes env) of
        Nothing ->
          Left [CoreUnknownConstructor name]
        Just info ->
          case constructorFieldsForResult info scrutineeTy of
            Nothing ->
              Left [CoreConstructorResultMismatch name scrutineeTy (constructorResult info)]
            Just fields ->
              collectValidations
                [ checkConstructorArity name fields binders
                , collectValidations (zipWith (checkConstructorField name) [0 ..] (zip fields binders))
                ]

validateApplication :: CoreType -> CoreType -> CoreType -> [Either [CoreValidationError] ()]
validateApplication fnTy argTy resultTy =
  case fnTy of
    CTyFun expectedArgTy expectedResultTy ->
      [ checkAppArgument expectedArgTy argTy
      , checkType expectedResultTy resultTy
      ]
    _ ->
      [Left [CoreExpectedFunction fnTy]]

validateTypeApplication :: CoreType -> [CoreType] -> CoreType -> Either [CoreValidationError] ()
validateTypeApplication fnTy arguments resultTy =
  case fnTy of
    CTyForall variables bodyTy
      | length variables /= length arguments ->
          Left [CoreTypeApplicationArityMismatch (length variables) (length arguments)]
      | otherwise ->
          checkType (substCoreType (Map.fromList (zip variables arguments)) bodyTy) resultTy
    _ ->
      Left [CoreExpectedForall fnTy]

validatePrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validatePrimitive op arguments resultTy =
  case op of
    PrimAdd -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimSub -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimMul -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimDiv -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimLt -> validateFixedPrimitive op [intTy, intTy] boolTy arguments resultTy
    PrimNegate -> validateFixedPrimitive op [intTy] intTy arguments resultTy
    PrimEq ->
      [ checkPrimitiveArity op 2 arguments
      , validatePrimitiveEq op arguments
      , checkPrimitiveResult op boolTy resultTy
      ]

validateFixedPrimitive ::
  CorePrimOp ->
  [CoreType] ->
  CoreType ->
  [CoreExpr] ->
  CoreType ->
  [Either [CoreValidationError] ()]
validateFixedPrimitive op expectedArgs expectedResult arguments resultTy =
  checkPrimitiveArity op (length expectedArgs) arguments
    : zipWith (checkPrimitiveArgument op) [0 ..] (zip expectedArgs (map exprType arguments))
      <> [checkPrimitiveResult op expectedResult resultTy]

validatePrimitiveEq :: CorePrimOp -> [CoreExpr] -> Either [CoreValidationError] ()
validatePrimitiveEq op arguments =
  case map exprType arguments of
    [lhsTy, rhsTy]
      | lhsTy == rhsTy -> Right ()
      | otherwise -> Left [CorePrimitiveArgumentMismatch op 1 lhsTy rhsTy]
    _ -> Right ()

literalType :: Literal -> CoreType
literalType = \case
  LInt {} -> intTy
  LChar {} -> charTy
  LString {} -> stringTy

constructorFunctionType :: CoreConstructorInfo -> CoreType
constructorFunctionType (CoreConstructorInfo variables fields result) =
  case variables of
    [] -> body
    _ -> CTyForall variables body
 where
  body =
    foldr CTyFun result fields

constructorFieldsForResult :: CoreConstructorInfo -> CoreType -> Maybe [CoreType]
constructorFieldsForResult info actualResult = do
  substitutions <- matchCoreType (Set.fromList (constructorTyVars info)) Map.empty (constructorResult info) actualResult
  pure (map (substCoreType substitutions) (constructorFields info))

validateBinder :: CoreBinder -> Either [CoreValidationError] ()
validateBinder binder
  | nameNamespace (coreBinderName binder) == TermNamespace = Right ()
  | otherwise = Left [CoreInvalidBinderNamespace (coreBinderName binder) (nameNamespace (coreBinderName binder))]

validateTypeBinder :: RName -> Either [CoreValidationError] ()
validateTypeBinder name
  | nameNamespace name == TypeVariableNamespace = Right ()
  | otherwise = Left [CoreInvalidBinderNamespace name (nameNamespace name)]

checkType :: CoreType -> CoreType -> Either [CoreValidationError] ()
checkType expected actual
  | expected == actual = Right ()
  | otherwise = Left [CoreTypeMismatch expected actual]

checkAppArgument :: CoreType -> CoreType -> Either [CoreValidationError] ()
checkAppArgument expected actual
  | expected == actual = Right ()
  | otherwise = Left [CoreAppArgumentMismatch expected actual]

checkAltType :: CoreAltCon -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkAltType altCon expected actual
  | expected == actual = Right ()
  | otherwise = Left [CoreAlternativeTypeMismatch altCon expected actual]

checkCaseBinder :: CoreType -> CoreType -> Either [CoreValidationError] ()
checkCaseBinder expected actual
  | expected == actual = Right ()
  | otherwise = Left [CoreCaseBinderMismatch expected actual]

checkAltArity :: CoreAltCon -> Int -> [CoreBinder] -> Either [CoreValidationError] ()
checkAltArity altCon expected binders
  | expected == length binders = Right ()
  | otherwise = Left [CoreAlternativeArityMismatch altCon expected (length binders)]

checkAltPatternType :: CoreAltCon -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkAltPatternType altCon expected actual
  | expected == actual = Right ()
  | otherwise = Left [CoreAlternativeTypeMismatch altCon expected actual]

checkConstructorArity :: RName -> [CoreType] -> [CoreBinder] -> Either [CoreValidationError] ()
checkConstructorArity name expectedFields binders
  | length expectedFields == length binders = Right ()
  | otherwise = Left [CoreConstructorArityMismatch name (length expectedFields) (length binders)]

checkConstructorField :: RName -> Int -> (CoreType, CoreBinder) -> Either [CoreValidationError] ()
checkConstructorField name index (expected, binder)
  | expected == coreBinderType binder = Right ()
  | otherwise = Left [CoreConstructorFieldMismatch name index expected (coreBinderType binder)]

checkPrimitiveArity :: CorePrimOp -> Int -> [CoreExpr] -> Either [CoreValidationError] ()
checkPrimitiveArity op expected arguments
  | expected == length arguments = Right ()
  | otherwise = Left [CorePrimitiveArityMismatch op expected (length arguments)]

checkPrimitiveArgument :: CorePrimOp -> Int -> (CoreType, CoreType) -> Either [CoreValidationError] ()
checkPrimitiveArgument op index (expected, actual)
  | expected == actual = Right ()
  | otherwise = Left [CorePrimitiveArgumentMismatch op index expected actual]

checkPrimitiveResult :: CorePrimOp -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkPrimitiveResult op expected actual
  | expected == actual = Right ()
  | otherwise = Left [CorePrimitiveResultMismatch op expected actual]

defaultAlternativeErrors :: [CoreAlt] -> [CoreValidationError]
defaultAlternativeErrors alternatives =
  case length [() | CoreAlt DefaultAlt _ _ <- alternatives] of
    count
      | count > 1 -> [CoreMultipleDefaultAlternatives count]
      | otherwise -> []

extendScope :: [CoreBinder] -> Scope -> Scope
extendScope binders scope =
  Map.union (scopeFromBinders binders) scope

scopeFromBinders :: [CoreBinder] -> Scope
scopeFromBinders binders =
  Map.fromList [(coreBinderName binder, coreBinderType binder) | binder <- binders]

exprBinderNames :: CoreExpr -> [RName]
exprBinderNames = \case
  CVar {} -> []
  CLit {} -> []
  CCon {} -> []
  CLam binder body _ ->
    coreBinderName binder : exprBinderNames body
  CApp fn arg _ ->
    exprBinderNames fn <> exprBinderNames arg
  CTypeLam _ body _ ->
    exprBinderNames body
  CTypeApp fn _ _ ->
    exprBinderNames fn
  CLet bind body _ ->
    bindBinderNames bind <> exprBinderNames body
  CCase scrutinee binder alternatives _ ->
    exprBinderNames scrutinee
      <> [coreBinderName binder]
      <> concatMap altBinderNames alternatives
  CPrimOp _ arguments _ ->
    concatMap exprBinderNames arguments

bindBinderNames :: CoreBind -> [RName]
bindBinderNames = \case
  CoreNonRec binder rhs ->
    coreBinderName binder : exprBinderNames rhs
  CoreRec pairs ->
    map (coreBinderName . fst) pairs <> concatMap (exprBinderNames . snd) pairs

altBinderNames :: CoreAlt -> [RName]
altBinderNames (CoreAlt _ binders body) =
  map coreBinderName binders <> exprBinderNames body

substCoreType :: Map.Map RName CoreType -> CoreType -> CoreType
substCoreType substitution = \case
  CTyVar name ->
    Map.findWithDefault (CTyVar name) name substitution
  CTyCon name ->
    CTyCon name
  CTyApp fn arg ->
    CTyApp (substCoreType substitution fn) (substCoreType substitution arg)
  CTyFun arg result ->
    CTyFun (substCoreType substitution arg) (substCoreType substitution result)
  CTyForall variables body ->
    CTyForall variables (substCoreType (foldr Map.delete substitution variables) body)
  CTyTuple fields ->
    CTyTuple (map (substCoreType substitution) fields)
  CTyList elementTy ->
    CTyList (substCoreType substitution elementTy)

matchCoreType ::
  Set.Set RName ->
  Map.Map RName CoreType ->
  CoreType ->
  CoreType ->
  Maybe (Map.Map RName CoreType)
matchCoreType variables substitutions expected actual =
  case expected of
    CTyVar name
      | name `Set.member` variables ->
          case Map.lookup name substitutions of
            Nothing -> Just (Map.insert name actual substitutions)
            Just previous
              | previous == actual -> Just substitutions
              | otherwise -> Nothing
      | expected == actual -> Just substitutions
      | otherwise -> Nothing
    CTyCon {}
      | expected == actual -> Just substitutions
      | otherwise -> Nothing
    CTyApp expectedFn expectedArg ->
      case actual of
        CTyApp actualFn actualArg ->
          matchCoreType variables substitutions expectedFn actualFn
            >>= \next -> matchCoreType variables next expectedArg actualArg
        _ -> Nothing
    CTyFun expectedArg expectedResult ->
      case actual of
        CTyFun actualArg actualResult ->
          matchCoreType variables substitutions expectedArg actualArg
            >>= \next -> matchCoreType variables next expectedResult actualResult
        _ -> Nothing
    CTyForall expectedVars expectedBody ->
      case actual of
        CTyForall actualVars actualBody
          | expectedVars == actualVars ->
              matchCoreType variables substitutions expectedBody actualBody
        _ -> Nothing
    CTyTuple expectedFields ->
      case actual of
        CTyTuple actualFields
          | length expectedFields == length actualFields ->
              foldMMatch variables substitutions expectedFields actualFields
        _ -> Nothing
    CTyList expectedElement ->
      case actual of
        CTyList actualElement ->
          matchCoreType variables substitutions expectedElement actualElement
        _ -> Nothing

foldMMatch ::
  Set.Set RName ->
  Map.Map RName CoreType ->
  [CoreType] ->
  [CoreType] ->
  Maybe (Map.Map RName CoreType)
foldMMatch variables =
  go
 where
  go substitutions [] [] =
    Just substitutions
  go substitutions (expected : expectedRest) (actual : actualRest) =
    matchCoreType variables substitutions expected actual
      >>= \next -> go next expectedRest actualRest
  go _ _ _ =
    Nothing

duplicates :: Ord a => [a] -> [a]
duplicates values =
  Map.keys (Map.filter (> 1) counts)
 where
  counts =
    foldr (\value -> Map.insertWith (+) value (1 :: Int)) Map.empty values

collectValidations :: [Either [CoreValidationError] ()] -> Either [CoreValidationError] ()
collectValidations validations =
  case concat [errors | Left errors <- validations] of
    [] -> Right ()
    errors -> Left errors

failWith :: [CoreValidationError] -> Either [CoreValidationError] ()
failWith [] =
  Right ()
failWith errors =
  Left errors

renderValidationError :: CoreValidationError -> Text
renderValidationError = \case
  CoreDuplicateBinder name ->
    "duplicate Core binder: " <> renderRName name
  CoreInvalidBinderNamespace name namespace ->
    "Core binder " <> renderRName name <> " is in the " <> renderNamespace namespace <> " namespace"
  CoreUnboundVariable name ->
    "unbound Core variable: " <> renderRName name
  CoreUnknownConstructor name ->
    "unknown Core constructor: " <> renderRName name
  CoreTypeMismatch expected actual ->
    "Core type mismatch: expected " <> renderCoreType expected <> ", got " <> renderCoreType actual
  CoreExpectedFunction actual ->
    "Core application expected a function, got " <> renderCoreType actual
  CoreExpectedForall actual ->
    "Core type application expected a forall type, got " <> renderCoreType actual
  CoreTypeApplicationArityMismatch expected actual ->
    "Core type application arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  CoreAppArgumentMismatch expected actual ->
    "Core application argument mismatch: expected " <> renderCoreType expected <> ", got " <> renderCoreType actual
  CoreCaseBinderMismatch expected actual ->
    "Core case binder mismatch: expected " <> renderCoreType expected <> ", got " <> renderCoreType actual
  CoreAlternativeTypeMismatch altCon expected actual ->
    "Core alternative "
      <> renderCoreAltCon altCon
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreAlternativeArityMismatch altCon expected actual ->
    "Core alternative "
      <> renderCoreAltCon altCon
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  CoreConstructorArityMismatch name expected actual ->
    "Core constructor "
      <> renderRName name
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  CoreConstructorFieldMismatch name index expected actual ->
    "Core constructor "
      <> renderRName name
      <> " field "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreConstructorResultMismatch name expected actual ->
    "Core constructor "
      <> renderRName name
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreMultipleDefaultAlternatives count ->
    "Core case has "
      <> renderInt count
      <> " default alternatives"
  CorePrimitiveArityMismatch op expected actual ->
    "Core primitive "
      <> renderCorePrimOp op
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  CorePrimitiveArgumentMismatch op index expected actual ->
    "Core primitive "
      <> renderCorePrimOp op
      <> " argument "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CorePrimitiveResultMismatch op expected actual ->
    "Core primitive "
      <> renderCorePrimOp op
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual

renderInt :: Int -> Text
renderInt =
  Text.pack . show

(<|>) :: Maybe a -> Maybe a -> Maybe a
Nothing <|> fallback =
  fallback
value <|> _ =
  value
