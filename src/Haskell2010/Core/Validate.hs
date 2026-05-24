module Haskell2010.Core.Validate
  ( CoreConstructorInfo (..)
  , CoreValidationEnv (..)
  , CoreValidationError (..)
  , constructorFunctionType
  , constructorFieldsForResult
  , defaultValidationEnv
  , emptyValidationEnv
  , eraseNewtypeType
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
import Haskell2010.Names (Namespace (..), RName (..), nameNamespace, renderNamespace, renderRName)
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
  | CoreForeignCallArityMismatch RName Int Int
  | CoreForeignCallArgumentMismatch RName Int CoreType CoreType
  | CoreForeignCallResultMismatch RName CoreType CoreType
  | CoreForeignExportUnbound RName
  | CoreForeignExportTypeMismatch RName CoreType CoreType
  | CoreInvalidCoercion CoreType CoreType
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
          builtinConstructorInfos
    }

builtinConstructorInfos :: [(RName, CoreConstructorInfo)]
builtinConstructorInfos =
  [ (trueDataConName, dataConstructor [] [] boolTy)
  , (falseDataConName, dataConstructor [] [] boolTy)
  , (listNilDataConName, dataConstructor [a] [] (CTyList aTy))
  , (listConsDataConName, dataConstructor [a] [aTy, CTyList aTy] (CTyList aTy))
  , (unitDataConName, dataConstructor [] [] unitTy)
  , (maybeNothingDataConName, dataConstructor [a] [] maybeA)
  , (maybeJustDataConName, dataConstructor [a] [aTy] maybeA)
  , (eitherLeftDataConName, dataConstructor [a, b] [aTy] eitherAB)
  , (eitherRightDataConName, dataConstructor [a, b] [bTy] eitherAB)
  , (orderingLTDataConName, dataConstructor [] [] orderingTy)
  , (orderingEQDataConName, dataConstructor [] [] orderingTy)
  , (orderingGTDataConName, dataConstructor [] [] orderingTy)
  , (ratioDataConName, dataConstructor [a] [aTy, aTy] (ratioTy aTy))
  ]
 where
  a = builtinTypeVariable "a" (-1001)
  b = builtinTypeVariable "b" (-1002)
  aTy = CTyVar a
  bTy = CTyVar b
  maybeA = CTyApp (CTyCon maybeTyConName) aTy
  eitherAB = CTyApp (CTyApp (CTyCon eitherTyConName) aTy) bTy
  dataConstructor variables fields result =
    CoreConstructorInfo variables fields result CoreDataConstructor

builtinTypeVariable :: Text -> Int -> RName
builtinTypeVariable occurrence unique =
  RName TypeVariableNamespace occurrence unique True

moduleValidationEnv :: CoreModule -> CoreValidationEnv
moduleValidationEnv coreModule =
  defaultValidationEnv
    { coreConstructorTypes =
        Map.union (coreModuleConstructors coreModule) (coreConstructorTypes defaultValidationEnv)
    }

validateModule :: CoreValidationEnv -> CoreModule -> Either [CoreValidationError] ()
validateModule env (CoreModule _ _ binds exports) =
  collectValidations
    [ failWith duplicateErrors
    , collectValidations (map (validateScopedBind env moduleScope) binds)
    , collectValidations (map (validateForeignExport moduleScope) exports)
    ]
 where
  moduleBinders =
    concatMap bindersOf binds
  moduleScope =
    Map.union (scopeFromBinders moduleBinders) (coreValueTypes env)
  duplicateErrors =
    map CoreDuplicateBinder (duplicates (concatMap bindBinderNames binds))

validateForeignExport :: Scope -> CoreForeignExport -> Either [CoreValidationError] ()
validateForeignExport moduleScope foreignExport =
  case Map.lookup (coreForeignExportName foreignExport) moduleScope of
    Nothing ->
      Left [CoreForeignExportUnbound (coreForeignExportName foreignExport)]
    Just actualTy
      | normalizeCoreType (coreForeignExportType foreignExport) == normalizeCoreType actualTy ->
          Right ()
      | otherwise ->
          Left
            [ CoreForeignExportTypeMismatch
                (coreForeignExportName foreignExport)
                (coreForeignExportType foreignExport)
                actualTy
            ]

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
  CCoerce expression ty ->
    collectValidations
      [ validateScopedExpr env scope expression
      , validateCoercion env (exprType expression) ty
      ]
  CPrimOp op arguments ty ->
    collectValidations $
      map (validateScopedExpr env scope) arguments
        <> validatePrimitive op arguments ty
  CForeignCall foreignImport arguments ty ->
    collectValidations $
      map (validateScopedExpr env scope) arguments
        <> validateForeignCall foreignImport arguments ty
  CForeignImportValue foreignImport ty ->
    checkType (coreForeignImportType foreignImport) ty

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
    PrimRem -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimLt -> validateFixedPrimitive op [intTy, intTy] boolTy arguments resultTy
    PrimNegate -> validateFixedPrimitive op [intTy] intTy arguments resultTy
    PrimCharToInt -> validateFixedPrimitive op [charTy] intTy arguments resultTy
    PrimIntToChar -> validateFixedPrimitive op [intTy] charTy arguments resultTy
    PrimShowInt -> validateFixedPrimitive op [intTy] stringTy arguments resultTy
    PrimShowBool -> validateFixedPrimitive op [boolTy] stringTy arguments resultTy
    PrimPutStrLn -> validateFixedPrimitive op [stringTy] (ioTy unitTy) arguments resultTy
    PrimGetLine -> validateFixedPrimitive op [] (ioTy stringTy) arguments resultTy
    PrimStdHandle {} -> validateFixedPrimitive op [] handleTy arguments resultTy
    PrimOpenFile -> validateFixedPrimitive op [stringTy, ioModeTy] (ioTy handleTy) arguments resultTy
    PrimHClose -> validateFixedPrimitive op [handleTy] (ioTy unitTy) arguments resultTy
    PrimReadFile -> validateFixedPrimitive op [stringTy] (ioTy stringTy) arguments resultTy
    PrimWriteFile -> validateFixedPrimitive op [stringTy, stringTy] (ioTy unitTy) arguments resultTy
    PrimAppendFile -> validateFixedPrimitive op [stringTy, stringTy] (ioTy unitTy) arguments resultTy
    PrimHFileSize -> validateFixedPrimitive op [handleTy] (ioTy intTy) arguments resultTy
    PrimHSetFileSize -> validateFixedPrimitive op [handleTy, intTy] (ioTy unitTy) arguments resultTy
    PrimHIsEOF -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHSetBuffering -> validateFixedPrimitive op [handleTy, bufferModeTy] (ioTy unitTy) arguments resultTy
    PrimHGetBuffering -> validateFixedPrimitive op [handleTy] (ioTy bufferModeTy) arguments resultTy
    PrimHFlush -> validateFixedPrimitive op [handleTy] (ioTy unitTy) arguments resultTy
    PrimHGetPosn -> validateFixedPrimitive op [handleTy] (ioTy handlePosnTy) arguments resultTy
    PrimHSetPosn -> validateFixedPrimitive op [handlePosnTy] (ioTy unitTy) arguments resultTy
    PrimHSeek -> validateFixedPrimitive op [handleTy, seekModeTy, intTy] (ioTy unitTy) arguments resultTy
    PrimHTell -> validateFixedPrimitive op [handleTy] (ioTy intTy) arguments resultTy
    PrimHIsOpen -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHIsClosed -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHIsReadable -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHIsWritable -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHIsSeekable -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHIsTerminalDevice -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHSetEcho -> validateFixedPrimitive op [handleTy, boolTy] (ioTy unitTy) arguments resultTy
    PrimHGetEcho -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHShow -> validateFixedPrimitive op [handleTy] (ioTy stringTy) arguments resultTy
    PrimHWaitForInput -> validateFixedPrimitive op [handleTy, intTy] (ioTy boolTy) arguments resultTy
    PrimHReady -> validateFixedPrimitive op [handleTy] (ioTy boolTy) arguments resultTy
    PrimHGetChar -> validateFixedPrimitive op [handleTy] (ioTy charTy) arguments resultTy
    PrimHGetLine -> validateFixedPrimitive op [handleTy] (ioTy stringTy) arguments resultTy
    PrimHLookAhead -> validateFixedPrimitive op [handleTy] (ioTy charTy) arguments resultTy
    PrimHGetContents -> validateFixedPrimitive op [handleTy] (ioTy stringTy) arguments resultTy
    PrimHPutChar -> validateFixedPrimitive op [handleTy, charTy] (ioTy unitTy) arguments resultTy
    PrimHPutStr -> validateFixedPrimitive op [handleTy, stringTy] (ioTy unitTy) arguments resultTy
    PrimHPutStrLn -> validateFixedPrimitive op [handleTy, stringTy] (ioTy unitTy) arguments resultTy
    PrimIOThen -> validateIOThenPrimitive op arguments resultTy
    PrimIOBind -> validateIOBindPrimitive op arguments resultTy
    PrimIOReturn -> validateIOReturnPrimitive op arguments resultTy
    PrimIOFail -> validateIOFailPrimitive op arguments resultTy
    PrimIOError -> validateIOErrorPrimitive op arguments resultTy
    PrimIOCatch -> validateIOCatchPrimitive op arguments resultTy
    PrimIOTry -> validateIOTryPrimitive op arguments resultTy
    PrimNullPtr -> validateNullPtrPrimitive op arguments resultTy
    PrimCastPtr -> validateCastPtrPrimitive op arguments resultTy
    PrimIsNullPtr -> validateIsNullPtrPrimitive op arguments resultTy
    PrimNewStablePtr -> validateNewStablePtrPrimitive op arguments resultTy
    PrimDeRefStablePtr -> validateDeRefStablePtrPrimitive op arguments resultTy
    PrimFreeStablePtr -> validateFreeStablePtrPrimitive op arguments resultTy
    PrimCastStablePtrToPtr -> validateCastStablePtrToPtrPrimitive op arguments resultTy
    PrimCastPtrToStablePtr -> validateCastPtrToStablePtrPrimitive op arguments resultTy
    PrimFreeHaskellFunPtr -> validateFreeHaskellFunPtrPrimitive op arguments resultTy
    PrimNewForeignPtr -> validateNewForeignPtrPrimitive op arguments resultTy
    PrimNewForeignPtr_ -> validateNewForeignPtrNoFinalizerPrimitive op arguments resultTy
    PrimAddForeignPtrFinalizer -> validateAddForeignPtrFinalizerPrimitive op arguments resultTy
    PrimFinalizeForeignPtr -> validateFinalizeForeignPtrPrimitive op arguments resultTy
    PrimWithForeignPtr -> validateWithForeignPtrPrimitive op arguments resultTy
    PrimTouchForeignPtr -> validateTouchForeignPtrPrimitive op arguments resultTy
    PrimUnsafeForeignPtrToPtr -> validateUnsafeForeignPtrToPtrPrimitive op arguments resultTy
    PrimCastForeignPtr -> validateCastForeignPtrPrimitive op arguments resultTy
    PrimFloat width floatingOp -> validateFloatingPrimitive op width floatingOp arguments resultTy
    PrimFloatInt width floatingOp -> validateFloatingIntPrimitive op width floatingOp arguments resultTy
    PrimFixedIntegral fixed fixedOp -> validateFixedIntegralPrimitive op fixed fixedOp arguments resultTy
    PrimEq ->
      [ checkPrimitiveArity op 2 arguments
      , validatePrimitiveEq op arguments
      , checkPrimitiveResult op boolTy resultTy
      ]
    PrimBitAnd -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimBitOr -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimBitXor -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimBitComplement -> validateFixedPrimitive op [intTy] intTy arguments resultTy
    PrimShift -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimShiftL -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimShiftR -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimRotate -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimRotateL -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimRotateR -> validateFixedPrimitive op [intTy, intTy] intTy arguments resultTy
    PrimBit -> validateFixedPrimitive op [intTy] intTy arguments resultTy
    PrimTestBit -> validateFixedPrimitive op [intTy, intTy] boolTy arguments resultTy

validateFixedIntegralPrimitive ::
  CorePrimOp ->
  FixedIntegral ->
  FixedIntegralOp ->
  [CoreExpr] ->
  CoreType ->
  [Either [CoreValidationError] ()]
validateFixedIntegralPrimitive op fixed fixedOp arguments resultTy =
  case fixedOp of
    FixedAdd -> binaryValue
    FixedSub -> binaryValue
    FixedMul -> binaryValue
    FixedQuot -> binaryValue
    FixedRem -> binaryValue
    FixedEq -> binaryBool
    FixedLt -> binaryBool
    FixedNegate -> unaryValue
    FixedAbs -> unaryValue
    FixedSignum -> unaryValue
    FixedFromInteger -> validateFixedPrimitive op [intTy] valueTy arguments resultTy
    FixedToInteger -> validateFixedPrimitive op [valueTy] intTy arguments resultTy
    FixedShow -> validateFixedPrimitive op [valueTy] stringTy arguments resultTy
    FixedBitAnd -> binaryValue
    FixedBitOr -> binaryValue
    FixedBitXor -> binaryValue
    FixedBitComplement -> unaryValue
    FixedShift -> fixedByInt
    FixedShiftL -> fixedByInt
    FixedShiftR -> fixedByInt
    FixedRotate -> fixedByInt
    FixedRotateL -> fixedByInt
    FixedRotateR -> fixedByInt
    FixedBit -> validateFixedPrimitive op [intTy] valueTy arguments resultTy
    FixedTestBit -> validateFixedPrimitive op [valueTy, intTy] boolTy arguments resultTy
    FixedMinBound -> validateFixedPrimitive op [] valueTy arguments resultTy
    FixedMaxBound -> validateFixedPrimitive op [] valueTy arguments resultTy
 where
  valueTy = fixedIntegralTy fixed
  unaryValue = validateFixedPrimitive op [valueTy] valueTy arguments resultTy
  binaryValue = validateFixedPrimitive op [valueTy, valueTy] valueTy arguments resultTy
  binaryBool = validateFixedPrimitive op [valueTy, valueTy] boolTy arguments resultTy
  fixedByInt = validateFixedPrimitive op [valueTy, intTy] valueTy arguments resultTy

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

validateFloatingPrimitive ::
  CorePrimOp ->
  FloatingWidth ->
  FloatingPrimOp ->
  [CoreExpr] ->
  CoreType ->
  [Either [CoreValidationError] ()]
validateFloatingPrimitive op width floatingOp arguments resultTy =
  case floatingOp of
    FloatAdd -> binaryValue
    FloatSub -> binaryValue
    FloatMul -> binaryValue
    FloatDiv -> binaryValue
    FloatEq -> binaryBool
    FloatLt -> binaryBool
    FloatNegate -> unaryValue
    FloatAbs -> unaryValue
    FloatSignum -> unaryValue
    FloatFromInt -> validateFixedPrimitive op [intTy] valueTy arguments resultTy
    FloatShow -> validateFixedPrimitive op [valueTy] stringTy arguments resultTy
    FloatExp -> unaryValue
    FloatLog -> unaryValue
    FloatSqrt -> unaryValue
    FloatSin -> unaryValue
    FloatCos -> unaryValue
    FloatTan -> unaryValue
    FloatAsin -> unaryValue
    FloatAcos -> unaryValue
    FloatAtan -> unaryValue
    FloatSinh -> unaryValue
    FloatCosh -> unaryValue
    FloatTanh -> unaryValue
    FloatAsinh -> unaryValue
    FloatAcosh -> unaryValue
    FloatAtanh -> unaryValue
    FloatPow -> binaryValue
    FloatAtan2 -> binaryValue
 where
  valueTy = floatingWidthType width
  unaryValue = validateFixedPrimitive op [valueTy] valueTy arguments resultTy
  binaryValue = validateFixedPrimitive op [valueTy, valueTy] valueTy arguments resultTy
  binaryBool = validateFixedPrimitive op [valueTy, valueTy] boolTy arguments resultTy

validateFloatingIntPrimitive ::
  CorePrimOp ->
  FloatingWidth ->
  FloatingIntPrimOp ->
  [CoreExpr] ->
  CoreType ->
  [Either [CoreValidationError] ()]
validateFloatingIntPrimitive op width floatingOp arguments resultTy =
  case floatingOp of
    FloatTruncate -> intResult
    FloatRound -> intResult
    FloatCeiling -> intResult
    FloatFloor -> intResult
    FloatIsNaN -> boolResult
    FloatIsInfinite -> boolResult
    FloatIsDenormalized -> boolResult
    FloatIsNegativeZero -> boolResult
 where
  valueTy = floatingWidthType width
  intResult = validateFixedPrimitive op [valueTy] intTy arguments resultTy
  boolResult = validateFixedPrimitive op [valueTy] boolTy arguments resultTy

floatingWidthType :: FloatingWidth -> CoreType
floatingWidthType = \case
  FloatWidth -> floatTy
  DoubleWidth -> doubleTy

validatePrimitiveEq :: CorePrimOp -> [CoreExpr] -> Either [CoreValidationError] ()
validatePrimitiveEq op arguments =
  case map exprType arguments of
    [lhsTy, rhsTy]
      | normalizeCoreType lhsTy == normalizeCoreType rhsTy -> Right ()
      | otherwise -> Left [CorePrimitiveArgumentMismatch op 1 lhsTy rhsTy]
    _ -> Right ()

validateForeignCall :: CoreForeignImport -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateForeignCall foreignImport arguments resultTy
  | expectedArity /= actualArity =
      [Left [CoreForeignCallArityMismatch name expectedArity actualArity]]
  | otherwise =
      zipWith
        (checkForeignCallArgument name)
        [0 ..]
        (zip expectedArguments (map exprType arguments))
        <> [checkForeignCallResult name expectedResult resultTy]
 where
  name =
    coreForeignImportName foreignImport
  (expectedArguments, expectedResult) =
    splitFunctionType (coreForeignImportType foreignImport)
  expectedArity =
    length expectedArguments
  actualArity =
    length arguments

splitFunctionType :: CoreType -> ([CoreType], CoreType)
splitFunctionType =
  go []
 where
  go arguments = \case
    CTyFun argument result ->
      go (arguments <> [argument]) result
    result ->
      (arguments, result)

validateIOThenPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOThenPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [firstTy, secondTy]
        | Just _ <- ioResultType firstTy
        , Just _ <- ioResultType secondTy ->
            checkPrimitiveResult op secondTy resultTy
        | Just _ <- ioResultType firstTy ->
            Left [CorePrimitiveArgumentMismatch op 1 (ioTy (CTyVar unknownIOTypeVariable)) secondTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) firstTy]
      _ -> Right ()
  ]

validateIOReturnPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOReturnPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [valueTy] -> checkPrimitiveResult op (ioTy valueTy) resultTy
      _ -> Right ()
  ]

validateIOBindPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOBindPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [actionTy, continuationTy]
        | Just actionResultTy <- ioResultType actionTy
        , CTyFun continuationArgTy continuationResultTy <- continuationTy
        , normalizeCoreType continuationArgTy == normalizeCoreType actionResultTy
        , Just _ <- ioResultType continuationResultTy ->
            checkPrimitiveResult op continuationResultTy resultTy
        | Just actionResultTy <- ioResultType actionTy ->
            Left [CorePrimitiveArgumentMismatch op 1 (CTyFun actionResultTy (ioTy (CTyVar unknownIOTypeVariable))) continuationTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) actionTy]
      _ -> Right ()
  ]

validateIOFailPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOFailPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [messageTy]
        | normalizeCoreType messageTy == stringTy
        , Just _ <- ioResultType resultTy ->
            Right ()
        | normalizeCoreType messageTy == stringTy ->
            Left [CorePrimitiveResultMismatch op (ioTy (CTyVar unknownIOTypeVariable)) resultTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 stringTy messageTy]
      _ -> Right ()
  ]

validateIOErrorPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOErrorPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [errorTy]
        | normalizeCoreType errorTy == ioErrorTy
        , Just _ <- ioResultType resultTy ->
            Right ()
        | normalizeCoreType errorTy == ioErrorTy ->
            Left [CorePrimitiveResultMismatch op (ioTy (CTyVar unknownIOTypeVariable)) resultTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 ioErrorTy errorTy]
      _ -> Right ()
  ]

validateIOCatchPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOCatchPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [actionTy, handlerTy]
        | Just _ <- ioResultType actionTy
        , handlerTy == CTyFun ioErrorTy actionTy ->
            checkPrimitiveResult op actionTy resultTy
        | Just actionResultTy <- ioResultType actionTy ->
            Left [CorePrimitiveArgumentMismatch op 1 (CTyFun ioErrorTy (ioTy actionResultTy)) handlerTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) actionTy]
      _ -> Right ()
  ]

validateIOTryPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIOTryPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [actionTy]
        | Just actionResultTy <- ioResultType actionTy ->
            checkPrimitiveResult op (ioTy (eitherTy ioErrorTy actionResultTy)) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ioTy (CTyVar unknownIOTypeVariable)) actionTy]
      _ -> Right ()
  ]

validateNullPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateNullPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 0 arguments
  , if isPtrLikeType resultTy
      then Right ()
      else Left [CorePrimitiveResultMismatch op (ptrTy unknownForeignTypeVariableTy) resultTy]
  ]

validateCastPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateCastPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [pointerTy]
        | isPtrLikeType pointerTy && isPtrLikeType resultTy -> Right ()
        | isPtrLikeType pointerTy -> Left [CorePrimitiveResultMismatch op (ptrTy unknownForeignTypeVariableTy) resultTy]
        | otherwise -> Left [CorePrimitiveArgumentMismatch op 0 (ptrTy unknownForeignTypeVariableTy) pointerTy]
      _ -> Right ()
  ]

validateIsNullPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateIsNullPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [pointerTy]
        | isPtrLikeType pointerTy -> checkPrimitiveResult op boolTy resultTy
        | otherwise -> Left [CorePrimitiveArgumentMismatch op 0 (ptrTy unknownForeignTypeVariableTy) pointerTy]
      _ -> Right ()
  ]

validateNewStablePtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateNewStablePtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [valueTy] -> checkPrimitiveResult op (ioTy (stablePtrTy valueTy)) resultTy
      _ -> Right ()
  ]

validateDeRefStablePtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateDeRefStablePtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [stableTy]
        | Just payloadTy <- stablePtrPayloadType stableTy ->
            checkPrimitiveResult op (ioTy payloadTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (stablePtrTy unknownForeignTypeVariableTy) stableTy]
      _ -> Right ()
  ]

validateFreeStablePtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateFreeStablePtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [stableTy]
        | Just _ <- stablePtrPayloadType stableTy ->
            checkPrimitiveResult op (ioTy unitTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (stablePtrTy unknownForeignTypeVariableTy) stableTy]
      _ -> Right ()
  ]

validateCastStablePtrToPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateCastStablePtrToPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [stableTy]
        | Just _ <- stablePtrPayloadType stableTy ->
            checkPrimitiveResult op (ptrTy unitTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (stablePtrTy unknownForeignTypeVariableTy) stableTy]
      _ -> Right ()
  ]

validateCastPtrToStablePtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateCastPtrToStablePtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [pointerTy]
        | normalizeCoreType pointerTy == normalizeCoreType (ptrTy unitTy) ->
            Right ()
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ptrTy unitTy) pointerTy]
      _ -> Right ()
  , case stablePtrPayloadType resultTy of
      Just _ -> Right ()
      Nothing -> Left [CorePrimitiveResultMismatch op (stablePtrTy unknownForeignTypeVariableTy) resultTy]
  ]

validateFreeHaskellFunPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateFreeHaskellFunPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [funPtrTy_]
        | Just _ <- funPtrPayloadType funPtrTy_ ->
            checkPrimitiveResult op (ioTy unitTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (funPtrTy unknownForeignTypeVariableTy) funPtrTy_]
      _ -> Right ()
  ]

validateNewForeignPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateNewForeignPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [finalizerTy, pointerTy]
        | Just payloadTy <- ptrPayloadType pointerTy
        , normalizeCoreType finalizerTy == normalizeCoreType (foreignFinalizerPtrTy payloadTy) ->
            checkPrimitiveResult op (ioTy (foreignPtrTy payloadTy)) resultTy
        | Just payloadTy <- ptrPayloadType pointerTy ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignFinalizerPtrTy payloadTy) finalizerTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 1 (ptrTy unknownForeignTypeVariableTy) pointerTy]
      _ -> Right ()
  ]

validateNewForeignPtrNoFinalizerPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateNewForeignPtrNoFinalizerPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [pointerTy]
        | Just payloadTy <- ptrPayloadType pointerTy ->
            checkPrimitiveResult op (ioTy (foreignPtrTy payloadTy)) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (ptrTy unknownForeignTypeVariableTy) pointerTy]
      _ -> Right ()
  ]

validateAddForeignPtrFinalizerPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateAddForeignPtrFinalizerPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [finalizerTy, foreignTy]
        | Just payloadTy <- foreignPtrPayloadType foreignTy
        , normalizeCoreType finalizerTy == normalizeCoreType (foreignFinalizerPtrTy payloadTy) ->
            checkPrimitiveResult op (ioTy unitTy) resultTy
        | Just payloadTy <- foreignPtrPayloadType foreignTy ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignFinalizerPtrTy payloadTy) finalizerTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 1 (foreignPtrTy unknownForeignTypeVariableTy) foreignTy]
      _ -> Right ()
  ]

validateFinalizeForeignPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateFinalizeForeignPtrPrimitive op arguments resultTy =
  validateForeignPtrUnitPrimitive op arguments resultTy

validateTouchForeignPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateTouchForeignPtrPrimitive op arguments resultTy =
  validateForeignPtrUnitPrimitive op arguments resultTy

validateForeignPtrUnitPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateForeignPtrUnitPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [foreignTy]
        | Just _ <- foreignPtrPayloadType foreignTy ->
            checkPrimitiveResult op (ioTy unitTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignPtrTy unknownForeignTypeVariableTy) foreignTy]
      _ -> Right ()
  ]

validateWithForeignPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateWithForeignPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 2 arguments
  , case map exprType arguments of
      [foreignTy, continuationTy]
        | Just payloadTy <- foreignPtrPayloadType foreignTy
        , CTyFun pointerArgTy continuationResultTy <- normalizeCoreType continuationTy
        , normalizeCoreType pointerArgTy == normalizeCoreType (ptrTy payloadTy)
        , Just _ <- ioResultType continuationResultTy ->
            checkPrimitiveResult op continuationResultTy resultTy
        | Just payloadTy <- foreignPtrPayloadType foreignTy ->
            Left [CorePrimitiveArgumentMismatch op 1 (CTyFun (ptrTy payloadTy) (ioTy unknownForeignTypeVariableTy)) continuationTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignPtrTy unknownForeignTypeVariableTy) foreignTy]
      _ -> Right ()
  ]

validateUnsafeForeignPtrToPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateUnsafeForeignPtrToPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [foreignTy]
        | Just payloadTy <- foreignPtrPayloadType foreignTy ->
            checkPrimitiveResult op (ptrTy payloadTy) resultTy
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignPtrTy unknownForeignTypeVariableTy) foreignTy]
      _ -> Right ()
  ]

validateCastForeignPtrPrimitive :: CorePrimOp -> [CoreExpr] -> CoreType -> [Either [CoreValidationError] ()]
validateCastForeignPtrPrimitive op arguments resultTy =
  [ checkPrimitiveArity op 1 arguments
  , case map exprType arguments of
      [foreignTy]
        | Just _ <- foreignPtrPayloadType foreignTy
        , Just _ <- foreignPtrPayloadType resultTy ->
            Right ()
        | Just _ <- foreignPtrPayloadType foreignTy ->
            Left [CorePrimitiveResultMismatch op (foreignPtrTy unknownForeignTypeVariableTy) resultTy]
        | otherwise ->
            Left [CorePrimitiveArgumentMismatch op 0 (foreignPtrTy unknownForeignTypeVariableTy) foreignTy]
      _ -> Right ()
  ]

ptrPayloadType :: CoreType -> Maybe CoreType
ptrPayloadType = \case
  CTyApp (CTyCon name) payloadTy
    | nameOcc name == "Ptr" -> Just payloadTy
  _ -> Nothing

funPtrPayloadType :: CoreType -> Maybe CoreType
funPtrPayloadType = \case
  CTyApp (CTyCon name) payloadTy
    | nameOcc name == "FunPtr" -> Just payloadTy
  _ -> Nothing

isPtrLikeType :: CoreType -> Bool
isPtrLikeType ty =
  case ty of
    CTyApp (CTyCon name) _
      | nameOcc name == "Ptr" || nameOcc name == "FunPtr" -> True
    _ -> False

stablePtrPayloadType :: CoreType -> Maybe CoreType
stablePtrPayloadType = \case
  CTyApp (CTyCon name) payloadTy
    | nameOcc name == "StablePtr" -> Just payloadTy
  _ -> Nothing

foreignPtrPayloadType :: CoreType -> Maybe CoreType
foreignPtrPayloadType = \case
  CTyApp (CTyCon name) payloadTy
    | nameOcc name == "ForeignPtr" -> Just payloadTy
  _ -> Nothing

foreignFinalizerPtrTy :: CoreType -> CoreType
foreignFinalizerPtrTy payloadTy =
  funPtrTy (CTyFun (ptrTy payloadTy) (ioTy unitTy))

unknownForeignTypeVariableTy :: CoreType
unknownForeignTypeVariableTy =
  CTyVar (RName TypeVariableNamespace "$foreign" (-7998) True)

ioResultType :: CoreType -> Maybe CoreType
ioResultType = \case
  CTyApp (CTyCon name) resultTy
    | name == ioTyConName -> Just resultTy
  _ -> Nothing

eitherTy :: CoreType -> CoreType -> CoreType
eitherTy lhs rhs =
  CTyApp (CTyApp (CTyCon eitherTyConName) lhs) rhs

unknownIOTypeVariable :: RName
unknownIOTypeVariable =
  RName TypeVariableNamespace "$io" (-7999) True

literalType :: Literal -> CoreType
literalType = \case
  LInt {} -> intTy
  LFloat {} -> floatTy
  LDouble {} -> doubleTy
  LChar {} -> charTy
  LString {} -> stringTy

constructorFunctionType :: CoreConstructorInfo -> CoreType
constructorFunctionType (CoreConstructorInfo variables fields result _) =
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

eraseNewtypeType :: CoreValidationEnv -> CoreType -> CoreType
eraseNewtypeType env =
  go Set.empty
 where
  go seen ty =
    let structurallyErased =
          case ty of
            CTyVar {} -> ty
            CTyCon {} -> ty
            CTyApp fn arg -> CTyApp (go seen fn) (go seen arg)
            CTyFun arg result -> CTyFun (go seen arg) (go seen result)
            CTyForall variables body -> CTyForall variables (go seen body)
            CTyTuple fields -> CTyTuple (map (go seen) fields)
            CTyList elementTy -> CTyList (go seen elementTy)
     in case matchingNewtypeField seen structurallyErased of
          Nothing -> structurallyErased
          Just (constructorName, fieldTy) ->
            go (Set.insert constructorName seen) fieldTy

  matchingNewtypeField seen actualResult =
    firstJust
      [ (constructorName,) <$> instantiatedNewtypeField info actualResult
      | (constructorName, info) <- Map.toList (coreConstructorTypes env)
      , constructorName `Set.notMember` seen
      , constructorRepresentation info == CoreNewtypeConstructor
      ]

instantiatedNewtypeField :: CoreConstructorInfo -> CoreType -> Maybe CoreType
instantiatedNewtypeField info actualResult =
  case constructorFields info of
    [fieldTy] -> do
      substitutions <- matchCoreType (Set.fromList (constructorTyVars info)) Map.empty (constructorResult info) actualResult
      pure (substCoreType substitutions fieldTy)
    _ ->
      Nothing

validateCoercion :: CoreValidationEnv -> CoreType -> CoreType -> Either [CoreValidationError] ()
validateCoercion env sourceTy targetTy
  | sourceTy == targetTy = Right ()
  | any (newtypeCoercionMatches sourceTy targetTy) (Map.elems (coreConstructorTypes env)) = Right ()
  | otherwise = Left [CoreInvalidCoercion sourceTy targetTy]

newtypeCoercionMatches :: CoreType -> CoreType -> CoreConstructorInfo -> Bool
newtypeCoercionMatches sourceTy targetTy info
  | constructorRepresentation info /= CoreNewtypeConstructor = False
  | otherwise =
      wraps || unwraps
 where
  wraps =
    case instantiatedNewtypeField info targetTy of
      Just fieldTy -> fieldTy == sourceTy
      Nothing -> False
  unwraps =
    case instantiatedNewtypeField info sourceTy of
      Just fieldTy -> fieldTy == targetTy
      Nothing -> False

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
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreTypeMismatch expected actual]

checkAppArgument :: CoreType -> CoreType -> Either [CoreValidationError] ()
checkAppArgument expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreAppArgumentMismatch expected actual]

checkAltType :: CoreAltCon -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkAltType altCon expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreAlternativeTypeMismatch altCon expected actual]

checkCaseBinder :: CoreType -> CoreType -> Either [CoreValidationError] ()
checkCaseBinder expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreCaseBinderMismatch expected actual]

checkAltArity :: CoreAltCon -> Int -> [CoreBinder] -> Either [CoreValidationError] ()
checkAltArity altCon expected binders
  | expected == length binders = Right ()
  | otherwise = Left [CoreAlternativeArityMismatch altCon expected (length binders)]

checkAltPatternType :: CoreAltCon -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkAltPatternType altCon expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreAlternativeTypeMismatch altCon expected actual]

checkConstructorArity :: RName -> [CoreType] -> [CoreBinder] -> Either [CoreValidationError] ()
checkConstructorArity name expectedFields binders
  | length expectedFields == length binders = Right ()
  | otherwise = Left [CoreConstructorArityMismatch name (length expectedFields) (length binders)]

checkConstructorField :: RName -> Int -> (CoreType, CoreBinder) -> Either [CoreValidationError] ()
checkConstructorField name index (expected, binder)
  | normalizeCoreType expected == normalizeCoreType (coreBinderType binder) = Right ()
  | otherwise = Left [CoreConstructorFieldMismatch name index expected (coreBinderType binder)]

checkPrimitiveArity :: CorePrimOp -> Int -> [CoreExpr] -> Either [CoreValidationError] ()
checkPrimitiveArity op expected arguments
  | expected == length arguments = Right ()
  | otherwise = Left [CorePrimitiveArityMismatch op expected (length arguments)]

checkPrimitiveArgument :: CorePrimOp -> Int -> (CoreType, CoreType) -> Either [CoreValidationError] ()
checkPrimitiveArgument op index (expected, actual)
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CorePrimitiveArgumentMismatch op index expected actual]

checkPrimitiveResult :: CorePrimOp -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkPrimitiveResult op expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CorePrimitiveResultMismatch op expected actual]

checkForeignCallArgument :: RName -> Int -> (CoreType, CoreType) -> Either [CoreValidationError] ()
checkForeignCallArgument name index (expected, actual)
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreForeignCallArgumentMismatch name index expected actual]

checkForeignCallResult :: RName -> CoreType -> CoreType -> Either [CoreValidationError] ()
checkForeignCallResult name expected actual
  | normalizeCoreType expected == normalizeCoreType actual = Right ()
  | otherwise = Left [CoreForeignCallResultMismatch name expected actual]

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
  CCoerce expression _ ->
    exprBinderNames expression
  CPrimOp _ arguments _ ->
    concatMap exprBinderNames arguments
  CForeignCall _ arguments _ ->
    concatMap exprBinderNames arguments
  CForeignImportValue {} ->
    []

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
    normalizeCoreType (CTyApp (substCoreType substitution fn) (substCoreType substitution arg))
  CTyFun arg result ->
    CTyFun (substCoreType substitution arg) (substCoreType substitution result)
  CTyForall variables body ->
    CTyForall variables (substCoreType (foldr Map.delete substitution variables) body)
  CTyTuple fields ->
    CTyTuple (map (substCoreType substitution) fields)
  CTyList elementTy ->
    CTyList (substCoreType substitution elementTy)

normalizeCoreType :: CoreType -> CoreType
normalizeCoreType = \case
  CTyApp (CTyCon name) elementTy
    | name == listTyConName -> CTyList (normalizeCoreType elementTy)
  CTyApp fn arg -> CTyApp (normalizeCoreType fn) (normalizeCoreType arg)
  CTyFun arg result -> CTyFun (normalizeCoreType arg) (normalizeCoreType result)
  CTyForall variables body -> CTyForall variables (normalizeCoreType body)
  CTyTuple fields -> CTyTuple (map normalizeCoreType fields)
  CTyList elementTy -> CTyList (normalizeCoreType elementTy)
  other -> other

matchCoreType ::
  Set.Set RName ->
  Map.Map RName CoreType ->
  CoreType ->
  CoreType ->
  Maybe (Map.Map RName CoreType)
matchCoreType variables substitutions expected actual =
  case normalizeCoreType expected of
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
      case normalizeCoreType actual of
        CTyApp actualFn actualArg ->
          matchCoreType variables substitutions expectedFn actualFn
            >>= \next -> matchCoreType variables next expectedArg actualArg
        _ -> Nothing
    CTyFun expectedArg expectedResult ->
      case normalizeCoreType actual of
        CTyFun actualArg actualResult ->
          matchCoreType variables substitutions expectedArg actualArg
            >>= \next -> matchCoreType variables next expectedResult actualResult
        _ -> Nothing
    CTyForall expectedVars expectedBody ->
      case normalizeCoreType actual of
        CTyForall actualVars actualBody
          | expectedVars == actualVars ->
              matchCoreType variables substitutions expectedBody actualBody
        _ -> Nothing
    CTyTuple expectedFields ->
      case normalizeCoreType actual of
        CTyTuple actualFields
          | length expectedFields == length actualFields ->
              foldMMatch variables substitutions expectedFields actualFields
        _ -> Nothing
    CTyList expectedElement ->
      case normalizeCoreType actual of
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
  CoreForeignCallArityMismatch name expected actual ->
    "Core foreign call `"
      <> renderRName name
      <> "` arity mismatch: expected "
      <> renderInt expected
      <> ", got "
      <> renderInt actual
  CoreForeignCallArgumentMismatch name index expected actual ->
    "Core foreign call `"
      <> renderRName name
      <> "` argument "
      <> renderInt index
      <> " mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreForeignCallResultMismatch name expected actual ->
    "Core foreign call `"
      <> renderRName name
      <> "` result mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreForeignExportUnbound name ->
    "Core foreign export target is unbound: " <> renderRName name
  CoreForeignExportTypeMismatch name expected actual ->
    "Core foreign export `"
      <> renderRName name
      <> "` type mismatch: expected "
      <> renderCoreType expected
      <> ", got "
      <> renderCoreType actual
  CoreInvalidCoercion sourceTy targetTy ->
    "Core coercion is not backed by a newtype constructor: "
      <> renderCoreType sourceTy
      <> " to "
      <> renderCoreType targetTy

renderInt :: Int -> Text
renderInt =
  Text.pack . show

firstJust :: [Maybe a] -> Maybe a
firstJust [] =
  Nothing
firstJust (value : rest) =
  case value of
    Just found -> Just found
    Nothing -> firstJust rest

(<|>) :: Maybe a -> Maybe a -> Maybe a
Nothing <|> fallback =
  fallback
value <|> _ =
  value
