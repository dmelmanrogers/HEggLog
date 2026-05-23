module Haskell2010.Core.Eval
  ( CoreEvalError (..)
  , CoreValue (..)
  , evalCoreExpr
  , evalCoreModuleBinding
  , evalCoreModuleBindingByOccurrence
  , renderCoreEvalError
  , renderCoreValue
  )
where

import Data.Char (chr, ord)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names (RName, nameOcc, renderRName)
import Haskell2010.Syntax (Literal (..))
import Runtime.Int
  ( HInt
  , IntError
  , addHInt
  , andHInt
  , bitHInt
  , complementHInt
  , divHInt
  , eqHInt
  , hintToInteger
  , ltHInt
  , mkHIntLiteral
  , mulHInt
  , orHInt
  , rotateHInt
  , rotateLHInt
  , rotateRHInt
  , remHInt
  , renderHInt
  , renderIntError
  , shiftHInt
  , shiftLHInt
  , shiftRHInt
  , subHInt
  , testBitHInt
  , xorHInt
  )

data CoreValue
  = CoreInt HInt
  | CoreBool Bool
  | CoreChar Char
  | CoreString Text
  | CoreIO [Text] CoreIOResult
  | CorePointer (Maybe CoreValue)
  | CoreStablePtr CoreValue
  | CoreForeignPtr CoreValue
  | CoreClosure Env CoreBinder CoreExpr
  | CoreTypeClosure Env [RName] CoreExpr
  | CoreConstructor RName [CoreThunk]
  | CoreData RName [CoreThunk]
  deriving stock (Show)

data CoreIOResult
  = CoreIOSuccess CoreValue
  | CoreIOFailure CoreValue
  deriving stock (Show)

data CoreEvalError
  = CoreEvalInvalid [CoreValidate.CoreValidationError]
  | CoreEvalUnknownVariable RName
  | CoreEvalUnknownBinding RName
  | CoreEvalUnknownBindingOccurrence Text
  | CoreEvalAmbiguousBindingOccurrence Text [RName]
  | CoreEvalTypeError Text
  | CoreEvalDivisionByZero
  | CoreEvalIntError IntError
  | CoreEvalNoMatchingAlternative CoreValue
  | CoreEvalUnsupportedForeign Text
  deriving stock (Show)

type Env = Map.Map RName CoreThunk

data CoreThunk
  = Evaluated CoreValue
  | Unevaluated Env CoreExpr
  deriving stock (Show)

evalCoreExpr :: CoreExpr -> Either CoreEvalError CoreValue
evalCoreExpr expression =
  case CoreValidate.validateExpr expression of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () -> evalExpr CoreValidate.defaultValidationEnv Map.empty expression

evalCoreModuleBinding :: RName -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBinding name coreModule =
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv coreModule) coreModule of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () -> evalCoreModuleBindingUnchecked name coreModule

evalCoreModuleBindingUnchecked :: RName -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBindingUnchecked name coreModule =
  case Map.lookup name env of
    Nothing -> Left (CoreEvalUnknownBinding name)
    Just thunk -> force coreEnv thunk
 where
  coreEnv =
    CoreValidate.moduleValidationEnv coreModule
  env =
    moduleEnv coreModule

evalCoreModuleBindingByOccurrence :: Text -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBindingByOccurrence occurrence coreModule =
  case CoreValidate.validateModule (CoreValidate.moduleValidationEnv coreModule) coreModule of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () ->
      case matchingNames of
        [] ->
          Left (CoreEvalUnknownBindingOccurrence occurrence)
        [name] ->
          evalCoreModuleBindingUnchecked name coreModule
        names ->
          Left (CoreEvalAmbiguousBindingOccurrence occurrence names)
 where
  matchingNames =
    [ coreBinderName binder
    | bind <- coreModuleBinds coreModule
    , binder <- bindersOf bind
    , nameOcc (coreBinderName binder) == occurrence
    ]

evalExpr :: CoreValidate.CoreValidationEnv -> Env -> CoreExpr -> Either CoreEvalError CoreValue
evalExpr coreEnv env = \case
  CVar name _ ->
    case Map.lookup name env of
      Nothing -> Left (CoreEvalUnknownVariable name)
      Just thunk -> force coreEnv thunk
  CLit literal _ ->
    evalLiteral literal
  CCon name _
    | name == trueDataConName ->
        Right (CoreBool True)
    | name == falseDataConName ->
        Right (CoreBool False)
    | otherwise ->
        evalDataConstructor coreEnv name []
  CLam binder body _ ->
    Right (CoreClosure env binder body)
  CApp function argument _ -> do
    functionValue <- evalExpr coreEnv env function
    case functionValue of
      CoreClosure closureEnv binder body ->
        evalExpr coreEnv (Map.insert (coreBinderName binder) (Unevaluated env argument) closureEnv) body
      CoreConstructor name fields ->
        evalDataConstructor coreEnv name (fields <> [Unevaluated env argument])
      other ->
        Left (CoreEvalTypeError ("expected Core function, got " <> renderCoreValue other))
  CTypeLam variables body _ ->
    Right (CoreTypeClosure env variables body)
  CTypeApp function _ _ -> do
    functionValue <- evalExpr coreEnv env function
    case functionValue of
      CoreTypeClosure closureEnv _ body ->
        evalExpr coreEnv closureEnv body
      CoreConstructor {} ->
        Right functionValue
      CoreData {} ->
        Right functionValue
      other ->
        Left (CoreEvalTypeError ("expected Core type function, got " <> renderCoreValue other))
  CLet bind body _ ->
    evalExpr coreEnv (extendEnv bind env) body
  CCase scrutinee binder alternatives _ -> do
    scrutineeValue <- evalExpr coreEnv env scrutinee
    evalCaseAlternative coreEnv env binder alternatives scrutineeValue
  CCoerce expression _ ->
    evalExpr coreEnv env expression
  CPrimOp op arguments _ ->
    evalPrimitiveExpr coreEnv env op arguments
  CForeignCall foreignImport arguments _ -> do
    _ <- traverse (evalExpr coreEnv env) arguments
    Left (CoreEvalUnsupportedForeign ("foreign call `" <> renderRName (coreForeignImportName foreignImport) <> "` requires native FFI ABI support"))
  CForeignImportValue foreignImport _ ->
    Left (CoreEvalUnsupportedForeign ("foreign import `" <> renderRName (coreForeignImportName foreignImport) <> "` requires native FFI ABI support"))

evalDataConstructor ::
  CoreValidate.CoreValidationEnv ->
  RName ->
  [CoreThunk] ->
  Either CoreEvalError CoreValue
evalDataConstructor coreEnv name fields =
  case Map.lookup name (CoreValidate.coreConstructorTypes coreEnv) of
    Nothing ->
      Left (CoreEvalTypeError ("unknown Core constructor `" <> renderRName name <> "`"))
    Just info ->
      case compare (length fields) (length (constructorFields info)) of
        LT -> Right (CoreConstructor name fields)
        EQ -> Right (CoreData name fields)
        GT ->
          Left
            ( CoreEvalTypeError
                ( "too many fields for Core constructor `"
                    <> renderRName name
                    <> "`"
                )
            )

evalLiteral :: Literal -> Either CoreEvalError CoreValue
evalLiteral = \case
  LInt value ->
    case mkHIntLiteral value of
      Right intValue -> Right (CoreInt intValue)
      Left err -> Left (CoreEvalIntError err)
  LChar value ->
    Right (CoreChar value)
  LString value ->
    Right (coreStringList value)

force :: CoreValidate.CoreValidationEnv -> CoreThunk -> Either CoreEvalError CoreValue
force coreEnv = \case
  Evaluated value ->
    Right value
  Unevaluated env expression ->
    evalExpr coreEnv env expression

moduleEnv :: CoreModule -> Env
moduleEnv coreModule =
  env
 where
  env =
    Map.fromList
      [ (coreBinderName binder, Unevaluated env rhs)
      | (binder, rhs) <- concatMap bindPairs (coreModuleBinds coreModule)
      ]

extendEnv :: CoreBind -> Env -> Env
extendEnv bind env =
  case bind of
    CoreNonRec binder rhs ->
      Map.insert (coreBinderName binder) (Unevaluated env rhs) env
    CoreRec pairs ->
      recEnv
     where
      recEnv =
        Map.union
          ( Map.fromList
              [ (coreBinderName binder, Unevaluated recEnv rhs)
              | (binder, rhs) <- pairs
              ]
          )
          env

bindPairs :: CoreBind -> [(CoreBinder, CoreExpr)]
bindPairs = \case
  CoreNonRec binder rhs -> [(binder, rhs)]
  CoreRec pairs -> pairs

evalCaseAlternative ::
  CoreValidate.CoreValidationEnv ->
  Env ->
  CoreBinder ->
  [CoreAlt] ->
  CoreValue ->
  Either CoreEvalError CoreValue
evalCaseAlternative coreEnv env binder alternatives scrutineeValue =
  case firstMatching alternatives of
    Nothing ->
      Left (CoreEvalNoMatchingAlternative scrutineeValue)
    Just (CoreAlt _ altBinders body, fields) ->
      evalExpr coreEnv (extendCaseEnv binder scrutineeValue altBinders fields env) body
 where
  firstMatching [] =
    Nothing
  firstMatching (alternative@(CoreAlt altCon _ _) : rest)
    | Just fields <- alternativeFields altCon scrutineeValue = Just (alternative, fields)
    | otherwise = firstMatching rest

extendCaseEnv :: CoreBinder -> CoreValue -> [CoreBinder] -> [CoreThunk] -> Env -> Env
extendCaseEnv binder scrutineeValue altBinders fields env =
  Map.union
    (Map.fromList (zip (map coreBinderName altBinders) fields))
    (Map.insert (coreBinderName binder) (Evaluated scrutineeValue) env)

alternativeFields :: CoreAltCon -> CoreValue -> Maybe [CoreThunk]
alternativeFields altCon value =
  case (altCon, value) of
    (DefaultAlt, _) ->
      Just []
    (LiteralAlt (LInt expected), CoreInt actual) ->
      if hintToInteger actual == expected then Just [] else Nothing
    (LiteralAlt (LChar expected), CoreChar actual) ->
      if actual == expected then Just [] else Nothing
    (LiteralAlt (LString expected), CoreString actual) ->
      if actual == expected then Just [] else Nothing
    (ConstructorAlt name, CoreBool True) ->
      if name == trueDataConName then Just [] else Nothing
    (ConstructorAlt name, CoreBool False) ->
      if name == falseDataConName then Just [] else Nothing
    (ConstructorAlt expectedName, CoreData actualName fields)
      | expectedName == actualName -> Just fields
    _ ->
      Nothing

evalPrimitiveExpr :: CoreValidate.CoreValidationEnv -> Env -> CorePrimOp -> [CoreExpr] -> Either CoreEvalError CoreValue
evalPrimitiveExpr coreEnv env op arguments =
  case (op, arguments) of
    (PrimIOThen, [firstExpr, secondExpr]) -> do
      first <- evalExpr coreEnv env firstExpr
      case first of
        CoreIO firstChunks (CoreIOFailure err) ->
          Right (CoreIO firstChunks (CoreIOFailure err))
        CoreIO firstChunks (CoreIOSuccess _) -> do
          second <- evalExpr coreEnv env secondExpr
          case second of
            CoreIO secondChunks result ->
              Right (CoreIO (firstChunks <> secondChunks) result)
            other ->
              Left (CoreEvalTypeError ("expected Core IO action from then continuation, got " <> renderCoreValue other))
        other ->
          Left (CoreEvalTypeError ("expected Core IO action, got " <> renderCoreValue other))
    (PrimIOBind, [firstExpr, continuationExpr]) -> do
      first <- evalExpr coreEnv env firstExpr
      case first of
        CoreIO firstChunks (CoreIOFailure err) ->
          Right (CoreIO firstChunks (CoreIOFailure err))
        CoreIO firstChunks (CoreIOSuccess value) -> do
          continuation <- evalExpr coreEnv env continuationExpr
          case continuation of
            CoreClosure closureEnv binder body -> do
              second <- evalExpr coreEnv (Map.insert (coreBinderName binder) (Evaluated value) closureEnv) body
              case second of
                CoreIO secondChunks result ->
                  Right (CoreIO (firstChunks <> secondChunks) result)
                other ->
                  Left (CoreEvalTypeError ("expected Core IO action from bind continuation, got " <> renderCoreValue other))
            other ->
              Left (CoreEvalTypeError ("expected Core IO bind continuation, got " <> renderCoreValue other))
        other ->
          Left (CoreEvalTypeError ("expected Core IO action, got " <> renderCoreValue other))
    (PrimIOCatch, [actionExpr, handlerExpr]) -> do
      action <- evalExpr coreEnv env actionExpr
      case action of
        CoreIO chunks (CoreIOSuccess value) ->
          Right (CoreIO chunks (CoreIOSuccess value))
        CoreIO chunks (CoreIOFailure err) -> do
          handler <- evalExpr coreEnv env handlerExpr
          case handler of
            CoreClosure closureEnv binder body -> do
              handled <- evalExpr coreEnv (Map.insert (coreBinderName binder) (Evaluated err) closureEnv) body
              case handled of
                CoreIO handledChunks result ->
                  Right (CoreIO (chunks <> handledChunks) result)
                other ->
                  Left (CoreEvalTypeError ("expected Core IO action from catch handler, got " <> renderCoreValue other))
            other ->
              Left (CoreEvalTypeError ("expected Core IO catch handler, got " <> renderCoreValue other))
        other ->
          Left (CoreEvalTypeError ("expected Core IO action, got " <> renderCoreValue other))
    (PrimIOTry, [actionExpr]) -> do
      action <- evalExpr coreEnv env actionExpr
      case action of
        CoreIO chunks (CoreIOSuccess value) ->
          Right (CoreIO chunks (CoreIOSuccess (CoreData eitherRightDataConName [Evaluated value])))
        CoreIO chunks (CoreIOFailure err) ->
          Right (CoreIO chunks (CoreIOSuccess (CoreData eitherLeftDataConName [Evaluated err])))
        other ->
          Left (CoreEvalTypeError ("expected Core IO action, got " <> renderCoreValue other))
    _ ->
      traverse (evalExpr coreEnv env) arguments >>= evalPrimitive coreEnv op

evalPrimitive :: CoreValidate.CoreValidationEnv -> CorePrimOp -> [CoreValue] -> Either CoreEvalError CoreValue
evalPrimitive coreEnv op values =
  case (op, values) of
    (PrimAdd, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (addHInt lhs rhs)
    (PrimSub, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (subHInt lhs rhs)
    (PrimMul, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (mulHInt lhs rhs)
    (PrimDiv, [CoreInt _, CoreInt rhs])
      | hintToInteger rhs == 0 ->
          Left CoreEvalDivisionByZero
    (PrimDiv, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (divHInt lhs rhs)
    (PrimRem, [CoreInt _, CoreInt rhs])
      | hintToInteger rhs == 0 ->
          Left CoreEvalDivisionByZero
    (PrimRem, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (remHInt lhs rhs)
    (PrimEq, [lhs, rhs]) ->
      CoreBool <$> valueEquals lhs rhs
    (PrimLt, [CoreInt lhs, CoreInt rhs]) ->
      Right (CoreBool (ltHInt lhs rhs))
    (PrimNegate, [CoreInt value]) ->
      checkedIntValue (subHInt zero value)
    (PrimBitAnd, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (andHInt lhs rhs)
    (PrimBitOr, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (orHInt lhs rhs)
    (PrimBitXor, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (xorHInt lhs rhs)
    (PrimBitComplement, [CoreInt value]) ->
      checkedIntValue (complementHInt value)
    (PrimShift, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (shiftHInt value amount)
    (PrimShiftL, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (shiftLHInt value amount)
    (PrimShiftR, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (shiftRHInt value amount)
    (PrimRotate, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (rotateHInt value amount)
    (PrimRotateL, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (rotateLHInt value amount)
    (PrimRotateR, [CoreInt value, CoreInt amount]) ->
      checkedIntValue (rotateRHInt value amount)
    (PrimBit, [CoreInt amount]) ->
      checkedIntValue (bitHInt amount)
    (PrimTestBit, [CoreInt value, CoreInt amount]) ->
      either (Left . CoreEvalIntError) (Right . CoreBool) (testBitHInt value amount)
    (PrimCharToInt, [CoreChar value]) ->
      checkedIntValue (mkHIntLiteral (fromIntegral (ord value)))
    (PrimIntToChar, [CoreInt value]) ->
      case hintToInteger value of
        code
          | 0 <= code && code <= 0x10FFFF -> Right (CoreChar (chr (fromIntegral code)))
          | otherwise -> Left (CoreEvalTypeError ("invalid Char code point " <> Text.pack (show code)))
    (PrimShowInt, [CoreInt value]) ->
      Right (coreStringList (renderHInt value))
    (PrimShowBool, [CoreBool True]) ->
      Right (coreStringList "True")
    (PrimShowBool, [CoreBool False]) ->
      Right (coreStringList "False")
    (PrimPutStrLn, [value]) ->
      (\text -> CoreIO [text <> "\n"] (CoreIOSuccess (CoreData unitDataConName []))) <$> coreStringText coreEnv value
    (PrimGetLine, []) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimIOReturn, [value]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimIOFail, [value]) ->
      coreStringText coreEnv value >>= \message -> Right (CoreIO [] (CoreIOFailure (coreUserIOError message)))
    (PrimIOError, [value]) ->
      Right (CoreIO [] (CoreIOFailure value))
    (PrimNullPtr, []) ->
      Right (CorePointer Nothing)
    (PrimCastPtr, [CorePointer value]) ->
      Right (CorePointer value)
    (PrimIsNullPtr, [CorePointer Nothing]) ->
      Right (CoreBool True)
    (PrimIsNullPtr, [CorePointer (Just _)]) ->
      Right (CoreBool False)
    (PrimNewStablePtr, [value]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreStablePtr value)))
    (PrimDeRefStablePtr, [CoreStablePtr value]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimFreeStablePtr, [CoreStablePtr _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimCastStablePtrToPtr, [CoreStablePtr value]) ->
      Right (CorePointer (Just value))
    (PrimCastPtrToStablePtr, [CorePointer (Just value)]) ->
      Right (CoreStablePtr value)
    (PrimFreeHaskellFunPtr, [CorePointer _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimNewForeignPtr, [_finalizer, pointer]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreForeignPtr pointer)))
    (PrimNewForeignPtr_, [pointer]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreForeignPtr pointer)))
    (PrimAddForeignPtrFinalizer, [_finalizer, CoreForeignPtr _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimFinalizeForeignPtr, [CoreForeignPtr _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimWithForeignPtr, [CoreForeignPtr pointer, CoreClosure closureEnv binder body]) -> do
      action <- evalExpr coreEnv (Map.insert (coreBinderName binder) (Evaluated pointer) closureEnv) body
      case action of
        CoreIO chunks result ->
          Right (CoreIO chunks result)
        other ->
          Left (CoreEvalTypeError ("expected Core IO action from withForeignPtr continuation, got " <> renderCoreValue other))
    (PrimTouchForeignPtr, [CoreForeignPtr _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimUnsafeForeignPtrToPtr, [CoreForeignPtr pointer]) ->
      Right pointer
    (PrimCastForeignPtr, [CoreForeignPtr pointer]) ->
      Right (CoreForeignPtr pointer)
    _ ->
      Left (CoreEvalTypeError ("invalid Core primitive operands for " <> renderCorePrimOpName op))
 where
  checkedIntValue =
    \case
      Right value -> Right (CoreInt value)
      Left err -> Left (CoreEvalIntError err)
  zero =
    case mkHIntLiteral 0 of
      Right value -> value
      Left err -> error (Text.unpack (renderIntError err))

coreUserIOError :: Text -> CoreValue
coreUserIOError message =
  CoreData
    ioErrorDataConName
    [ Evaluated (CoreData ioErrorUserTypeDataConName [])
    , Evaluated (coreStringList message)
    , Evaluated (CoreData maybeNothingDataConName [])
    , Evaluated (CoreData maybeNothingDataConName [])
    ]

coreStringText :: CoreValidate.CoreValidationEnv -> CoreValue -> Either CoreEvalError Text
coreStringText coreEnv = \case
  CoreString value ->
    Right value
  CoreData name []
    | name == listNilDataConName ->
        Right ""
  CoreData name [headThunk, tailThunk]
    | name == listConsDataConName -> do
        headValue <- force coreEnv headThunk
        tailValue <- force coreEnv tailThunk
        case headValue of
          CoreChar char -> Text.cons char <$> coreStringText coreEnv tailValue
          other -> Left (CoreEvalTypeError ("expected Char in String list, got " <> renderCoreValue other))
  other ->
    Left (CoreEvalTypeError ("expected String, got " <> renderCoreValue other))

coreStringList :: Text -> CoreValue
coreStringList =
  Text.foldr cons nil
 where
  nil =
    CoreData listNilDataConName []
  cons char tailValue =
    CoreData listConsDataConName [Evaluated (CoreChar char), Evaluated tailValue]

valueEquals :: CoreValue -> CoreValue -> Either CoreEvalError Bool
valueEquals lhs rhs =
  case (lhs, rhs) of
    (CoreInt lhsInt, CoreInt rhsInt) ->
      Right (eqHInt lhsInt rhsInt)
    (CoreBool lhsBool, CoreBool rhsBool) ->
      Right (lhsBool == rhsBool)
    (CoreChar lhsChar, CoreChar rhsChar) ->
      Right (lhsChar == rhsChar)
    (CoreString lhsText, CoreString rhsText) ->
      Right (lhsText == rhsText)
    _ ->
      Left
        ( CoreEvalTypeError
            ("cannot compare Core values " <> renderCoreValue lhs <> " and " <> renderCoreValue rhs)
        )

renderCoreValue :: CoreValue -> Text
renderCoreValue = \case
  CoreInt value ->
    renderHInt value
  CoreBool True ->
    "True"
  CoreBool False ->
    "False"
  CoreChar value ->
    Text.pack (show value)
  CoreString value ->
    Text.pack (show (Text.unpack value))
  CoreIO chunks _ ->
    "<Core IO " <> Text.pack (show (Text.unpack (Text.concat chunks))) <> ">"
  CorePointer {} ->
    "<Core Ptr>"
  CoreStablePtr {} ->
    "<Core StablePtr>"
  CoreForeignPtr {} ->
    "<Core ForeignPtr>"
  CoreClosure {} ->
    "<Core function>"
  CoreTypeClosure {} ->
    "<Core type function>"
  CoreConstructor name fields ->
    "<Core constructor " <> renderRName name <> " applied to " <> Text.pack (show (length fields)) <> " fields>"
  CoreData name fields ->
    renderRName name <> renderFields fields
 where
  renderFields fields =
    case fields of
      [] -> ""
      _ -> " <" <> Text.pack (show (length fields)) <> " lazy fields>"

renderCoreEvalError :: CoreEvalError -> Text
renderCoreEvalError = \case
  CoreEvalInvalid errors ->
    "invalid Core before evaluation: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)
  CoreEvalUnknownVariable name ->
    "unknown Core variable `" <> renderRName name <> "`"
  CoreEvalUnknownBinding name ->
    "unknown Core module binding `" <> renderRName name <> "`"
  CoreEvalUnknownBindingOccurrence occurrence ->
    "unknown Core module binding occurrence `" <> occurrence <> "`"
  CoreEvalAmbiguousBindingOccurrence occurrence names ->
    "ambiguous Core module binding occurrence `"
      <> occurrence
      <> "`: "
      <> Text.intercalate ", " (map renderRName names)
  CoreEvalTypeError message ->
    message
  CoreEvalDivisionByZero ->
    "division by zero"
  CoreEvalIntError err ->
    renderIntError err
  CoreEvalNoMatchingAlternative value ->
    "no Core case alternative matched " <> renderCoreValue value
  CoreEvalUnsupportedForeign message ->
    message

renderCorePrimOpName :: CorePrimOp -> Text
renderCorePrimOpName = \case
  PrimAdd -> "+"
  PrimSub -> "-"
  PrimMul -> "*"
  PrimDiv -> "/"
  PrimRem -> "rem"
  PrimEq -> "=="
  PrimLt -> "<"
  PrimNegate -> "negate#"
  PrimBitAnd -> "and#"
  PrimBitOr -> "or#"
  PrimBitXor -> "xor#"
  PrimBitComplement -> "complement#"
  PrimShift -> "shift#"
  PrimShiftL -> "shiftL#"
  PrimShiftR -> "shiftR#"
  PrimRotate -> "rotate#"
  PrimRotateL -> "rotateL#"
  PrimRotateR -> "rotateR#"
  PrimBit -> "bit#"
  PrimTestBit -> "testBit#"
  PrimCharToInt -> "charToInt#"
  PrimIntToChar -> "intToChar#"
  PrimShowInt -> "showInt#"
  PrimShowBool -> "showBool#"
  PrimPutStrLn -> "putStrLn#"
  PrimGetLine -> "getLine#"
  PrimIOThen -> "thenIO#"
  PrimIOBind -> "bindIO#"
  PrimIOReturn -> "returnIO#"
  PrimIOFail -> "failIO#"
  PrimIOError -> "ioError#"
  PrimIOCatch -> "catchIO#"
  PrimIOTry -> "tryIO#"
  PrimNullPtr -> "nullPtr#"
  PrimCastPtr -> "castPtr#"
  PrimIsNullPtr -> "isNullPtr#"
  PrimNewStablePtr -> "newStablePtr#"
  PrimDeRefStablePtr -> "deRefStablePtr#"
  PrimFreeStablePtr -> "freeStablePtr#"
  PrimCastStablePtrToPtr -> "castStablePtrToPtr#"
  PrimCastPtrToStablePtr -> "castPtrToStablePtr#"
  PrimFreeHaskellFunPtr -> "freeHaskellFunPtr#"
  PrimNewForeignPtr -> "newForeignPtr#"
  PrimNewForeignPtr_ -> "newForeignPtr_#"
  PrimAddForeignPtrFinalizer -> "addForeignPtrFinalizer#"
  PrimFinalizeForeignPtr -> "finalizeForeignPtr#"
  PrimWithForeignPtr -> "withForeignPtr#"
  PrimTouchForeignPtr -> "touchForeignPtr#"
  PrimUnsafeForeignPtrToPtr -> "unsafeForeignPtrToPtr#"
  PrimCastForeignPtr -> "castForeignPtr#"
