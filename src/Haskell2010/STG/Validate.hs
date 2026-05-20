module Haskell2010.STG.Validate
  ( STGValidationError (..)
  , renderSTGValidationError
  , validateExpr
  , validateExprWith
  , validateProgram
  , validateProgramWith
  )
where

import Control.Applicative ((<|>))
import Control.Monad (foldM)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Pretty (renderCoreAltCon, renderCorePrimOp, renderCoreType)
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names (Namespace (..), RName (..), nameNamespace, renderNamespace, renderRName)
import Haskell2010.STG.Syntax

data STGValidationError
  = STGDuplicateBinder RName
  | STGInvalidBinderNamespace RName Namespace
  | STGUnboundVariable RName
  | STGUnboundCallee RName
  | STGUnknownConstructor RName
  | STGTypeMismatch CoreType CoreType
  | STGExpectedFunction CoreType
  | STGAppArgumentMismatch Int CoreType CoreType
  | STGCaseBinderMismatch CoreType CoreType
  | STGAlternativeTypeMismatch CoreAltCon CoreType CoreType
  | STGAlternativeArityMismatch CoreAltCon Int Int
  | STGConstructorArityMismatch RName Int Int
  | STGConstructorFieldMismatch RName Int CoreType CoreType
  | STGConstructorResultMismatch RName CoreType CoreType
  | STGMultipleDefaultAlternatives Int
  | STGPrimitiveArityMismatch CorePrimOp Int Int
  | STGPrimitiveArgumentMismatch CorePrimOp Int CoreType CoreType
  | STGPrimitiveResultMismatch CorePrimOp CoreType CoreType
  deriving stock (Show, Eq, Ord)

type Scope = Map.Map RName CoreType

validateProgram :: STGProgram -> Either [STGValidationError] ()
validateProgram program =
  validateProgramWith (programValidationEnv program) program

validateProgramWith :: CoreValidate.CoreValidationEnv -> STGProgram -> Either [STGValidationError] ()
validateProgramWith env (STGProgram _ binds) =
  collectValidations
    [ failWith duplicateErrors
    , collectValidations (map (validateScopedBind env moduleScope) binds)
    ]
 where
  moduleBinders =
    concatMap stgBindersOf binds
  moduleScope =
    Map.union (scopeFromBinders moduleBinders) (CoreValidate.coreValueTypes env)
  duplicateErrors =
    map STGDuplicateBinder (duplicates (concatMap bindBinderNames binds))

validateExpr :: STGExpr -> Either [STGValidationError] ()
validateExpr =
  validateExprWith CoreValidate.defaultValidationEnv

validateExprWith :: CoreValidate.CoreValidationEnv -> STGExpr -> Either [STGValidationError] ()
validateExprWith env expression =
  collectValidations [validateScopedExpr env (CoreValidate.coreValueTypes env) expression]

validateScopedBind ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  STGBind ->
  Either [STGValidationError] ()
validateScopedBind env scope = \case
  STGNonRec binder rhs ->
    collectValidations
      [ validateBinder binder
      , validateScopedRhs env scope rhs
      , checkType (stgBinderType binder) (stgRhsType rhs)
      ]
  STGRec pairs ->
    let binders = map fst pairs
        recScope = extendScope binders scope
     in collectValidations $
          map validateBinder binders
            <> map (validateRecRhs recScope) pairs
 where
  validateRecRhs recScope (binder, rhs) =
    collectValidations
      [ validateScopedRhs env recScope rhs
      , checkType (stgBinderType binder) (stgRhsType rhs)
      ]

validateScopedRhs ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  STGRhs ->
  Either [STGValidationError] ()
validateScopedRhs env scope = \case
  STGFunction binders body ->
    collectValidations
      [ collectValidations (map validateBinder binders)
      , failWith (map STGDuplicateBinder (duplicates (map stgBinderName binders)))
      , validateScopedExpr env (extendScope binders scope) body
      ]
  STGThunk _ body ->
    validateScopedExpr env scope body
  STGConstructor name fields resultTy ->
    validateConstructorRhs env scope name fields resultTy

validateScopedExpr ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  STGExpr ->
  Either [STGValidationError] ()
validateScopedExpr env scope = \case
  STGAtom atom ->
    validateAtom env scope atom
  STGApp callee arguments resultTy ->
    collectValidations
      [ validateCalleeApplication scope callee arguments resultTy
      , collectValidations (map (validateAtom env scope) arguments)
      ]
  STGLet bind body ty ->
    collectValidations
      [ validateScopedBind env scope bind
      , validateScopedExpr env (extendScope (stgBindersOf bind) scope) body
      , checkType (stgExprType body) ty
      ]
  STGCase scrutinee binder alternatives ty ->
    collectValidations
      [ validateBinder binder
      , validateScopedExpr env scope scrutinee
      , checkCaseBinder (stgExprType scrutinee) (stgBinderType binder)
      , failWith (defaultAlternativeErrors alternatives)
      , collectValidations $
          map (validateCaseAlt env (extendScope [binder] scope) binder ty) alternatives
      ]
  STGPrim op arguments resultTy ->
    collectValidations $
      map (validateAtom env scope) arguments
        <> validatePrimitive op arguments resultTy

validateAtom ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  STGAtom ->
  Either [STGValidationError] ()
validateAtom env scope = \case
  STGVar name ty ->
    case Map.lookup name scope <|> Map.lookup name (CoreValidate.coreValueTypes env) of
      Nothing ->
        Left [STGUnboundVariable name]
      Just expectedTy ->
        checkType expectedTy ty
  STGLit literal ty ->
    checkType (CoreValidate.literalType literal) ty
  STGCon name ty ->
    case Map.lookup name (CoreValidate.coreConstructorTypes env) of
      Nothing ->
        Left [STGUnknownConstructor name]
      Just info
        | Just [] <- CoreValidate.constructorFieldsForResult info ty ->
            Right ()
        | Just expectedFields <- CoreValidate.constructorFieldsForResult info ty ->
            Left [STGConstructorArityMismatch name (length expectedFields) 0]
        | otherwise ->
            Left [STGConstructorResultMismatch name (CoreValidate.constructorResult info) ty]

validateConstructorRhs ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  RName ->
  [STGAtom] ->
  CoreType ->
  Either [STGValidationError] ()
validateConstructorRhs env scope name fields resultTy =
  case Map.lookup name (CoreValidate.coreConstructorTypes env) of
    Nothing ->
      Left [STGUnknownConstructor name]
    Just info ->
      case CoreValidate.constructorFieldsForResult info resultTy of
        Nothing ->
          Left [STGConstructorResultMismatch name (CoreValidate.constructorResult info) resultTy]
        Just expectedFields ->
          let expectedRuntimeFields = map (CoreValidate.eraseNewtypeType env) expectedFields
           in collectValidations $
                [checkConstructorArity name expectedRuntimeFields fields]
                  <> map (validateAtom env scope) fields
                  <> zipWith
                    (checkConstructorField name)
                    [0 ..]
                    (zip expectedRuntimeFields (map stgAtomType fields))

validateCalleeApplication :: Scope -> RName -> [STGAtom] -> CoreType -> Either [STGValidationError] ()
validateCalleeApplication scope callee arguments resultTy =
  case Map.lookup callee scope of
    Nothing ->
      Left [STGUnboundCallee callee]
    Just calleeTy ->
      validateApplication calleeTy (map stgAtomType arguments) resultTy

validateApplication :: CoreType -> [CoreType] -> CoreType -> Either [STGValidationError] ()
validateApplication fnTy argumentTypes resultTy =
  case fnTy of
    CTyForall variables bodyTy
      | instantiateMatches variables bodyTy expectedApplicationTy -> Right ()
      | otherwise -> Left [STGAppArgumentMismatch 0 expectedApplicationTy fnTy]
    _ -> go 0 fnTy argumentTypes
 where
  expectedApplicationTy =
    foldr CTyFun resultTy argumentTypes

  go _ currentTy [] =
    checkType currentTy resultTy
  go index (CTyFun expectedArgTy result) (actualArgTy : rest)
    | typesCompatible expectedArgTy actualArgTy = go (index + 1) result rest
    | otherwise = Left [STGAppArgumentMismatch index expectedArgTy actualArgTy]
  go _ nonFunction _ =
    Left [STGExpectedFunction nonFunction]

validateCaseAlt ::
  CoreValidate.CoreValidationEnv ->
  Scope ->
  STGBinder ->
  CoreType ->
  STGAlt ->
  Either [STGValidationError] ()
validateCaseAlt env scope caseBinder caseResultTy (STGAlt altCon binders body) =
  collectValidations
    [ collectValidations (map validateBinder binders)
    , validateAltCon env (stgBinderType caseBinder) altCon binders
    , validateScopedExpr env (extendScope binders scope) body
    , checkAltType altCon caseResultTy (stgExprType body)
    ]

validateAltCon ::
  CoreValidate.CoreValidationEnv ->
  CoreType ->
  CoreAltCon ->
  [STGBinder] ->
  Either [STGValidationError] ()
validateAltCon env scrutineeTy altCon binders =
  case altCon of
    DefaultAlt ->
      checkAltArity altCon 0 binders
    LiteralAlt literal ->
      collectValidations
        [ checkAltArity altCon 0 binders
        , checkAltPatternType altCon scrutineeTy (CoreValidate.literalType literal)
        ]
    ConstructorAlt name ->
      case Map.lookup name (CoreValidate.coreConstructorTypes env) of
        Nothing ->
          Left [STGUnknownConstructor name]
        Just info ->
          case CoreValidate.constructorFieldsForResult info scrutineeTy of
            Nothing ->
              Left [STGConstructorResultMismatch name (CoreValidate.constructorResult info) scrutineeTy]
            Just expectedFields ->
              let expectedRuntimeFields = map (CoreValidate.eraseNewtypeType env) expectedFields
               in collectValidations
                    [ checkAltArity altCon (length expectedRuntimeFields) binders
                    , collectValidations $
                        zipWith
                          (checkAltField name)
                          [0 ..]
                          (zip expectedRuntimeFields binders)
                    ]

validatePrimitive :: CorePrimOp -> [STGAtom] -> CoreType -> [Either [STGValidationError] ()]
validatePrimitive op arguments resultTy =
  case op of
    PrimAdd -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimSub -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimMul -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimDiv -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimLt -> validateFixedPrimitive op [intTy, intTy] boolTy arguments resultTy
    PrimNegate -> validateFixedPrimitive op [intTy] intTy arguments resultTy
    PrimShowInt -> validateFixedPrimitive op [intTy] stringTy arguments resultTy
    PrimShowBool -> validateFixedPrimitive op [boolTy] stringTy arguments resultTy
    PrimPutStrLn -> validateFixedPrimitive op [stringTy] (ioTy unitTy) arguments resultTy
    PrimIOThen -> validateIOThenPrimitive op arguments resultTy
    PrimIOBind -> validateIOBindPrimitive op arguments resultTy
    PrimIOReturn -> validateIOReturnPrimitive op arguments resultTy
    PrimEq ->
      [ checkPrimitiveArity op 2 arguments
      , validatePrimitiveEq op arguments
      , checkPrimitiveResult op boolTy resultTy
      ]

validateFixedPrimitive ::
  CorePrimOp ->
  [CoreType] ->
  CoreType ->
  [STGAtom] ->
  CoreType ->
  [Either [STGValidationError] ()]
validateFixedPrimitive op expectedArgs expectedResult arguments resultTy =
  checkPrimitiveArity op (length expectedArgs) arguments
    : zipWith (checkPrimitiveArgument op) [0 ..] (zip expectedArgs (map stgAtomType arguments))
      <> [checkPrimitiveResult op expectedResult resultTy]

validatePrimitiveEq :: CorePrimOp -> [STGAtom] -> Either [STGValidationError] ()
validatePrimitiveEq op arguments =
  case map stgAtomType arguments of
    [lhsTy, rhsTy]
      | lhsTy /= rhsTy -> Left [STGPrimitiveArgumentMismatch op 1 lhsTy rhsTy]
      | supportsEquality lhsTy -> Right ()
      | otherwise -> Left [STGPrimitiveArgumentMismatch op 0 intTy lhsTy]
    _ -> Right ()
 where
  supportsEquality ty =
    ty == intTy || ty == boolTy || ty == charTy || ty == stringTy

validateIOThenPrimitive :: CorePrimOp -> [STGAtom] -> CoreType -> [Either [STGValidationError] ()]
validateIOThenPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map stgAtomType arguments of
      [firstTy, secondTy]
        | Just _ <- ioResultType firstTy
        , Just _ <- ioResultType secondTy ->
            checkPrimitiveResult op secondTy resultTy
        | Just _ <- ioResultType firstTy ->
            Left [STGPrimitiveArgumentMismatch op 1 (ioTy (CTyVar unknownIOTypeVariable)) secondTy]
        | otherwise ->
            Left [STGPrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) firstTy]
      _ -> Right ()
  ]

validateIOReturnPrimitive :: CorePrimOp -> [STGAtom] -> CoreType -> [Either [STGValidationError] ()]
validateIOReturnPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map stgAtomType arguments of
      [valueTy] -> checkPrimitiveResult op (ioTy valueTy) resultTy
      _ -> Right ()
  ]

validateIOBindPrimitive :: CorePrimOp -> [STGAtom] -> CoreType -> [Either [STGValidationError] ()]
validateIOBindPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map stgAtomType arguments of
      [actionTy, continuationTy]
        | Just actionResultTy <- ioResultType actionTy
        , CTyFun continuationArgTy continuationResultTy <- continuationTy
        , continuationArgTy == actionResultTy
        , Just _ <- ioResultType continuationResultTy ->
            checkPrimitiveResult op continuationResultTy resultTy
        | Just actionResultTy <- ioResultType actionTy ->
            Left [STGPrimitiveArgumentMismatch op 1 (CTyFun actionResultTy (ioTy (CTyVar unknownIOTypeVariable))) continuationTy]
        | otherwise ->
            Left [STGPrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) actionTy]
      _ -> Right ()
  ]

ioResultType :: CoreType -> Maybe CoreType
ioResultType = \case
  CTyApp (CTyCon name) resultTy
    | name == ioTyConName -> Just resultTy
  _ -> Nothing

unknownIOTypeVariable :: RName
unknownIOTypeVariable =
  RName TypeVariableNamespace "$io" (-7999) True

checkConstructorArity :: RName -> [CoreType] -> [STGAtom] -> Either [STGValidationError] ()
checkConstructorArity name expectedFields actualFields
  | length expectedFields == length actualFields = Right ()
  | otherwise =
      Left [STGConstructorArityMismatch name (length expectedFields) (length actualFields)]

checkConstructorField ::
  RName ->
  Int ->
  (CoreType, CoreType) ->
  Either [STGValidationError] ()
checkConstructorField name index (expected, actual)
  | expected == actual = Right ()
  | otherwise = Left [STGConstructorFieldMismatch name index expected actual]

checkAltField ::
  RName ->
  Int ->
  (CoreType, STGBinder) ->
  Either [STGValidationError] ()
checkAltField name index (expected, binder)
  | expected == stgBinderType binder = Right ()
  | otherwise = Left [STGConstructorFieldMismatch name index expected (stgBinderType binder)]

checkCaseBinder :: CoreType -> CoreType -> Either [STGValidationError] ()
checkCaseBinder expected actual
  | expected == actual = Right ()
  | otherwise = Left [STGCaseBinderMismatch expected actual]

checkAltType :: CoreAltCon -> CoreType -> CoreType -> Either [STGValidationError] ()
checkAltType altCon expected actual
  | expected == actual = Right ()
  | otherwise = Left [STGAlternativeTypeMismatch altCon expected actual]

checkAltPatternType :: CoreAltCon -> CoreType -> CoreType -> Either [STGValidationError] ()
checkAltPatternType altCon expected actual
  | expected == actual = Right ()
  | otherwise = Left [STGAlternativeTypeMismatch altCon expected actual]

checkAltArity :: CoreAltCon -> Int -> [STGBinder] -> Either [STGValidationError] ()
checkAltArity altCon expected binders
  | expected == actual = Right ()
  | otherwise = Left [STGAlternativeArityMismatch altCon expected actual]
 where
  actual =
    length binders

checkPrimitiveArity :: CorePrimOp -> Int -> [STGAtom] -> Either [STGValidationError] ()
checkPrimitiveArity op expected arguments
  | expected == actual = Right ()
  | otherwise = Left [STGPrimitiveArityMismatch op expected actual]
 where
  actual =
    length arguments

programValidationEnv :: STGProgram -> CoreValidate.CoreValidationEnv
programValidationEnv program =
  CoreValidate.defaultValidationEnv
    { CoreValidate.coreConstructorTypes =
        Map.union (stgProgramConstructors program) (CoreValidate.coreConstructorTypes CoreValidate.defaultValidationEnv)
    }

checkPrimitiveArgument ::
  CorePrimOp ->
  Int ->
  (CoreType, CoreType) ->
  Either [STGValidationError] ()
checkPrimitiveArgument op index (expected, actual)
  | expected == actual = Right ()
  | otherwise = Left [STGPrimitiveArgumentMismatch op index expected actual]

checkPrimitiveResult :: CorePrimOp -> CoreType -> CoreType -> Either [STGValidationError] ()
checkPrimitiveResult op expected actual
  | expected == actual = Right ()
  | otherwise = Left [STGPrimitiveResultMismatch op expected actual]

checkType :: CoreType -> CoreType -> Either [STGValidationError] ()
checkType expected actual
  | typesCompatible expected actual = Right ()
  | otherwise = Left [STGTypeMismatch expected actual]

typesCompatible :: CoreType -> CoreType -> Bool
typesCompatible expected actual =
  expected == actual
    || case expected of
      CTyForall variables bodyTy ->
        instantiateMatches variables bodyTy actual
      _ ->
        False

instantiateMatches :: [RName] -> CoreType -> CoreType -> Bool
instantiateMatches variables expected actual =
  case unifyTypes variableSet Map.empty expected actual of
    Just _ -> True
    Nothing -> False
 where
  variableSet =
    Map.fromList [(variable, ()) | variable <- variables]

unifyTypes ::
  Map.Map RName () ->
  Map.Map RName CoreType ->
  CoreType ->
  CoreType ->
  Maybe (Map.Map RName CoreType)
unifyTypes variables substitution expected actual =
  case expected of
    CTyVar name
      | Map.member name variables ->
          case Map.lookup name substitution of
            Nothing -> Just (Map.insert name actual substitution)
            Just assigned
              | assigned == actual -> Just substitution
              | otherwise -> Nothing
    CTyVar name ->
      case actual of
        CTyVar actualName
          | name == actualName -> Just substitution
        _ -> Nothing
    CTyCon name ->
      case actual of
        CTyCon actualName
          | name == actualName -> Just substitution
        _ -> Nothing
    CTyApp expectedFn expectedArg ->
      case actual of
        CTyApp actualFn actualArg -> do
          substAfterFn <- unifyTypes variables substitution expectedFn actualFn
          unifyTypes variables substAfterFn expectedArg actualArg
        _ -> Nothing
    CTyFun expectedArg expectedResult ->
      case actual of
        CTyFun actualArg actualResult -> do
          substAfterArg <- unifyTypes variables substitution expectedArg actualArg
          unifyTypes variables substAfterArg expectedResult actualResult
        _ -> Nothing
    CTyForall expectedVariables expectedBody ->
      case actual of
        CTyForall actualVariables actualBody
          | length expectedVariables == length actualVariables ->
              unifyTypes variables substitution expectedBody actualBody
        _ -> Nothing
    CTyTuple expectedFields ->
      case actual of
        CTyTuple actualFields
          | length expectedFields == length actualFields ->
              foldM
                (\subst (expectedField, actualField) -> unifyTypes variables subst expectedField actualField)
                substitution
                (zip expectedFields actualFields)
        _ -> Nothing
    CTyList expectedElement ->
      case actual of
        CTyList actualElement ->
          unifyTypes variables substitution expectedElement actualElement
        _ -> Nothing

validateBinder :: STGBinder -> Either [STGValidationError] ()
validateBinder binder
  | nameNamespace name == TermNamespace = Right ()
  | otherwise = Left [STGInvalidBinderNamespace name (nameNamespace name)]
 where
  name =
    stgBinderName binder

extendScope :: [STGBinder] -> Scope -> Scope
extendScope binders scope =
  Map.union (scopeFromBinders binders) scope

scopeFromBinders :: [STGBinder] -> Scope
scopeFromBinders binders =
  Map.fromList [(stgBinderName binder, stgBinderType binder) | binder <- binders]

bindBinderNames :: STGBind -> [RName]
bindBinderNames = \case
  STGNonRec binder _ -> [stgBinderName binder]
  STGRec pairs -> map (stgBinderName . fst) pairs

defaultAlternativeErrors :: [STGAlt] -> [STGValidationError]
defaultAlternativeErrors alternatives =
  case length [() | STGAlt DefaultAlt _ _ <- alternatives] of
    0 -> []
    1 -> []
    count -> [STGMultipleDefaultAlternatives count]

duplicates :: Ord a => [a] -> [a]
duplicates =
  go Map.empty []
 where
  go _ duplicatesFound [] =
    reverse duplicatesFound
  go seen duplicatesFound (item : rest)
    | Map.member item seen = go seen (item : duplicatesFound) rest
    | otherwise = go (Map.insert item () seen) duplicatesFound rest

failWith :: [STGValidationError] -> Either [STGValidationError] ()
failWith [] = Right ()
failWith errors = Left errors

collectValidations :: [Either [STGValidationError] ()] -> Either [STGValidationError] ()
collectValidations validations =
  case concat [errors | Left errors <- validations] of
    [] -> Right ()
    errors -> Left errors

renderSTGValidationError :: STGValidationError -> Text
renderSTGValidationError = \case
  STGDuplicateBinder name ->
    "duplicate STG binder: " <> renderRName name
  STGInvalidBinderNamespace name namespace ->
    "STG binder " <> renderRName name <> " is in the " <> renderNamespace namespace <> " namespace"
  STGUnboundVariable name ->
    "unbound STG variable: " <> renderRName name
  STGUnboundCallee name ->
    "unbound STG callee: " <> renderRName name
  STGUnknownConstructor name ->
    "unknown STG constructor: " <> renderRName name
  STGTypeMismatch expected actual ->
    "STG type mismatch: expected " <> renderCoreType expected <> ", got " <> renderCoreType actual
  STGExpectedFunction actual ->
    "STG application expected a function, got " <> renderCoreType actual
  STGAppArgumentMismatch index expected actual ->
    "STG application argument "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGCaseBinderMismatch expected actual ->
    "STG case binder mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGAlternativeTypeMismatch altCon expected actual ->
    "STG alternative "
      <> renderCoreAltCon altCon
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGAlternativeArityMismatch altCon expected actual ->
    "STG alternative "
      <> renderCoreAltCon altCon
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  STGConstructorArityMismatch name expected actual ->
    "STG constructor "
      <> renderRName name
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  STGConstructorFieldMismatch name index expected actual ->
    "STG constructor "
      <> renderRName name
      <> " field "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGConstructorResultMismatch name expected actual ->
    "STG constructor "
      <> renderRName name
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGMultipleDefaultAlternatives count ->
    "STG case has " <> renderInt count <> " default alternatives"
  STGPrimitiveArityMismatch op expected actual ->
    "STG primitive "
      <> renderCorePrimOp op
      <> " arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  STGPrimitiveArgumentMismatch op index expected actual ->
    "STG primitive "
      <> renderCorePrimOp op
      <> " argument "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  STGPrimitiveResultMismatch op expected actual ->
    "STG primitive "
      <> renderCorePrimOp op
      <> " result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual

renderInt :: Int -> Text
renderInt =
  Text.pack . show
