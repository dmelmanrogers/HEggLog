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
import qualified Data.Bits as Bits
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.FixedWidth
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
  | CoreInteger Integer
  | CoreFloat Float
  | CoreDouble Double
  | CoreBool Bool
  | CoreChar Char
  | CoreString Text
  | CoreIO [Text] CoreIOResult
  | CoreHandle StdHandle Bool
  | CoreHandlePosn StdHandle HInt
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
  | CoreIOExit HInt
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
  LInteger value ->
    Right (CoreInteger value)
  LFloat value ->
    Right (CoreFloat value)
  LDouble value ->
    Right (CoreDouble value)
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
    (LiteralAlt (LInteger expected), CoreInteger actual) ->
      if actual == expected then Just [] else Nothing
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
        CoreIO firstChunks (CoreIOExit code) ->
          Right (CoreIO firstChunks (CoreIOExit code))
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
        CoreIO firstChunks (CoreIOExit code) ->
          Right (CoreIO firstChunks (CoreIOExit code))
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
        CoreIO chunks (CoreIOExit code) ->
          Right (CoreIO chunks (CoreIOExit code))
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
        CoreIO chunks (CoreIOExit code) ->
          Right (CoreIO chunks (CoreIOExit code))
        other ->
          Left (CoreEvalTypeError ("expected Core IO action, got " <> renderCoreValue other))
    (PrimIOFix, [functionExpr]) -> do
      function <- evalExpr coreEnv env functionExpr
      case function of
        CoreClosure closureEnv binder body ->
          let fixedValue =
                case evalExpr coreEnv (Map.insert (coreBinderName binder) (Evaluated fixedValue) closureEnv) body of
                  Right (CoreIO _ (CoreIOSuccess value)) -> value
                  Right other -> error ("fixIO expected Core IO success, got " <> Text.unpack (renderCoreValue other))
                  Left err -> error ("fixIO evaluation failed: " <> Text.unpack (renderCoreEvalError err))
           in Right (CoreIO [] (CoreIOSuccess fixedValue))
        other ->
          Left (CoreEvalTypeError ("expected Core IO fix function, got " <> renderCoreValue other))
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
    (PrimIntegerAdd, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreInteger (lhs + rhs))
    (PrimIntegerSub, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreInteger (lhs - rhs))
    (PrimIntegerMul, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreInteger (lhs * rhs))
    (PrimIntegerQuot, [CoreInteger _, CoreInteger 0]) ->
      Left CoreEvalDivisionByZero
    (PrimIntegerQuot, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreInteger (lhs `quot` rhs))
    (PrimIntegerRem, [CoreInteger _, CoreInteger 0]) ->
      Left CoreEvalDivisionByZero
    (PrimIntegerRem, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreInteger (lhs `rem` rhs))
    (PrimIntegerEq, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreBool (lhs == rhs))
    (PrimIntegerLt, [CoreInteger lhs, CoreInteger rhs]) ->
      Right (CoreBool (lhs < rhs))
    (PrimIntegerNegate, [CoreInteger value]) ->
      Right (CoreInteger (negate value))
    (PrimIntegerAbs, [CoreInteger value]) ->
      Right (CoreInteger (abs value))
    (PrimIntegerSignum, [CoreInteger value]) ->
      Right (CoreInteger (signum value))
    (PrimIntegerToInt, [CoreInteger value]) ->
      checkedIntValue (mkHIntLiteral value)
    (PrimIntToInteger, [CoreInt value]) ->
      Right (CoreInteger (hintToInteger value))
    (PrimIntegerToFloat FloatWidth, [CoreInteger value]) ->
      Right (CoreFloat (fromInteger value))
    (PrimIntegerToFloat DoubleWidth, [CoreInteger value]) ->
      Right (CoreDouble (fromInteger value))
    (PrimShowInteger, [CoreInteger value]) ->
      Right (coreStringList (Text.pack (show value)))
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
    (PrimFloat width floatingOp, arguments) ->
      evalFloatingPrimitive width floatingOp arguments
    (PrimFloatInt width floatingOp, arguments) ->
      evalFloatingIntPrimitive width floatingOp arguments
    (PrimFixedIntegral fixed fixedOp, arguments) ->
      evalFixedIntegralPrimitive fixed fixedOp arguments
    (PrimPutStrLn, [value]) ->
      (\text -> CoreIO [text <> "\n"] (CoreIOSuccess (CoreData unitDataConName []))) <$> coreStringText coreEnv value
    (PrimGetLine, []) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimGetArgs, []) ->
      Right (CoreIO [] (CoreIOSuccess (coreList stringTy [])))
    (PrimGetProgName, []) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "hegglog")))
    (PrimGetEnv, [nameValue]) ->
      coreStringText coreEnv nameValue >>= \nameText ->
        Right (CoreIO [] (CoreIOFailure (coreDoesNotExistIOError ("environment variable not found: " <> nameText))))
    (PrimExitWith, [exitCode]) ->
      coreExitWithResult coreEnv exitCode >>= \result -> Right (CoreIO [] result)
    (PrimStdHandle handle, []) ->
      Right (CoreHandle handle False)
    (PrimOpenFile, [_path, _mode]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreHandle StdInHandle False)))
    (PrimHClose, [CoreHandle _ _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimReadFile, [_path]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimWriteFile, [_path, _contents]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimAppendFile, [_path, _contents]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHFileSize, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreInt (expectHInt 0))))
    (PrimHSetFileSize, [_handle, _size]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHIsEOF, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool True)))
    (PrimHSetBuffering, [_handle, _mode]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHGetBuffering, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData bufferModeLineDataConName [])))
    (PrimHFlush, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHGetPosn, [CoreHandle handle _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreHandlePosn handle (expectHInt 0))))
    (PrimHSetPosn, [_posn]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHSeek, [_handle, _mode, _offset]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHTell, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreInt (expectHInt 0))))
    (PrimHIsOpen, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool True)))
    (PrimHIsClosed, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHIsReadable, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool True)))
    (PrimHIsWritable, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool True)))
    (PrimHIsSeekable, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHIsTerminalDevice, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHSetEcho, [_handle, _enabled]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHGetEcho, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHShow, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "<handle>")))
    (PrimHWaitForInput, [_handle, _timeout]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHReady, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreBool False)))
    (PrimHGetChar, [_handle]) ->
      Right (CoreIO [] (CoreIOFailure (coreEOFIOError "end of file")))
    (PrimHGetLine, [CoreHandle StdInHandle _]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimHGetLine, [_handle]) ->
      Right (CoreIO [] (CoreIOFailure (coreEOFIOError "end of file")))
    (PrimHLookAhead, [_handle]) ->
      Right (CoreIO [] (CoreIOFailure (coreEOFIOError "end of file")))
    (PrimHGetContents, [_handle]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimHPutChar, [CoreHandle StdOutHandle _, CoreChar char]) ->
      Right (CoreIO [Text.singleton char] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHPutChar, [CoreHandle StdErrHandle _, CoreChar _char]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHPutChar, [_handle, _char]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHPutStr, [CoreHandle StdOutHandle _, value]) ->
      (\text -> CoreIO [text] (CoreIOSuccess (CoreData unitDataConName []))) <$> coreStringText coreEnv value
    (PrimHPutStr, [_handle, _value]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimHPutStrLn, [CoreHandle StdOutHandle _, value]) ->
      (\text -> CoreIO [text <> "\n"] (CoreIOSuccess (CoreData unitDataConName []))) <$> coreStringText coreEnv value
    (PrimHPutStrLn, [_handle, _value]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
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
    (PrimPtrPlus, [CorePointer value, _]) ->
      Right (CorePointer value)
    (PrimPtrMinus, [CorePointer _, CorePointer _]) ->
      Right (CoreInt (expectHInt 0))
    (PrimPtrAlign, [CorePointer value, _]) ->
      Right (CorePointer value)
    (PrimMallocBytes, [_]) ->
      Right (CoreIO [] (CoreIOSuccess (CorePointer Nothing)))
    (PrimReallocBytes, [CorePointer _, _]) ->
      Right (CoreIO [] (CoreIOSuccess (CorePointer Nothing)))
    (PrimFree, [CorePointer _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimFinalizerFree, []) ->
      Right (CorePointer Nothing)
    (PrimPeek kind, [CorePointer (Just value), _]) ->
      Right (CoreIO [] (CoreIOSuccess (coerceStorableValue kind value)))
    (PrimPeek kind, [CorePointer Nothing, _]) ->
      Right (CoreIO [] (CoreIOSuccess (zeroStorableValue kind)))
    (PrimPoke _, [CorePointer _, _, _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimCopyBytes, [CorePointer _, CorePointer _, _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimMoveBytes, [CorePointer _, CorePointer _, _]) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimGetErrno, []) ->
      Right (CoreIO [] (CoreIOSuccess (CoreInt (expectHInt 0))))
    (PrimResetErrno, []) ->
      Right (CoreIO [] (CoreIOSuccess (CoreData unitDataConName [])))
    (PrimPeekCString, [CorePointer (Just value)]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimPeekCString, [CorePointer Nothing]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimPeekCStringLen, [CorePointer (Just value), _]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimPeekCStringLen, [CorePointer Nothing, _]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimNewCString, [value]) ->
      Right (CoreIO [] (CoreIOSuccess (CorePointer (Just value))))
    (PrimPeekCWString, [CorePointer (Just value)]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimPeekCWString, [CorePointer Nothing]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimPeekCWStringLen, [CorePointer (Just value), _]) ->
      Right (CoreIO [] (CoreIOSuccess value))
    (PrimPeekCWStringLen, [CorePointer Nothing, _]) ->
      Right (CoreIO [] (CoreIOSuccess (coreStringList "")))
    (PrimNewCWString, [value]) ->
      Right (CoreIO [] (CoreIOSuccess (CorePointer (Just value))))
    _ ->
      Left (CoreEvalTypeError ("invalid Core primitive operands for " <> renderCorePrimOpName op))
 where
  expectHInt value =
    case mkHIntLiteral value of
      Right intValue -> intValue
      Left err -> error ("internal HInt literal failed: " <> Text.unpack (renderIntError err))

  checkedIntValue =
    \case
      Right value -> Right (CoreInt value)
      Left err -> Left (CoreEvalIntError err)
  zero =
    case mkHIntLiteral 0 of
      Right value -> value
      Left err -> error (Text.unpack (renderIntError err))

  coerceStorableValue kind value =
    case (kind, value) of
      (StoreBool, CoreBool _) -> value
      (StoreChar, CoreChar _) -> value
      (StoreFloat, CoreFloat _) -> value
      (StoreDouble, CoreDouble _) -> value
      (StorePtr, CorePointer _) -> value
      _ -> value

  zeroStorableValue = \case
    StoreBool -> CoreBool False
    StoreChar -> CoreChar '\0'
    StoreFloat -> CoreFloat 0
    StoreDouble -> CoreDouble 0
    StorePtr -> CorePointer Nothing
    _ -> CoreInt zero

evalFixedIntegralPrimitive :: FixedIntegral -> FixedIntegralOp -> [CoreValue] -> Either CoreEvalError CoreValue
evalFixedIntegralPrimitive fixed op values =
  case (op, values) of
    (FixedAdd, [CoreInt lhs, CoreInt rhs]) -> fixedValue (fixedInput lhs + fixedInput rhs)
    (FixedSub, [CoreInt lhs, CoreInt rhs]) -> fixedValue (fixedInput lhs - fixedInput rhs)
    (FixedMul, [CoreInt lhs, CoreInt rhs]) -> fixedValue (fixedInput lhs * fixedInput rhs)
    (FixedQuot, [CoreInt _, CoreInt rhs])
      | fixedInput rhs == 0 -> Left CoreEvalDivisionByZero
    (FixedQuot, [CoreInt lhs, CoreInt rhs]) -> fixedValue (fixedInput lhs `quot` fixedInput rhs)
    (FixedRem, [CoreInt _, CoreInt rhs])
      | fixedInput rhs == 0 -> Left CoreEvalDivisionByZero
    (FixedRem, [CoreInt lhs, CoreInt rhs]) -> fixedValue (fixedInput lhs `rem` fixedInput rhs)
    (FixedEq, [CoreInt lhs, CoreInt rhs]) -> Right (CoreBool (fixedInput lhs == fixedInput rhs))
    (FixedLt, [CoreInt lhs, CoreInt rhs]) -> Right (CoreBool (fixedInput lhs < fixedInput rhs))
    (FixedNegate, [CoreInt value]) -> fixedValue (negate (fixedInput value))
    (FixedAbs, [CoreInt value]) -> fixedValue (abs (fixedInput value))
    (FixedSignum, [CoreInt value]) -> fixedValue (signum (fixedInput value))
    (FixedFromInteger, [CoreInteger value]) -> fixedValue value
    (FixedToInteger, [CoreInt value]) -> Right (CoreInteger (fixedInput value))
    (FixedShow, [CoreInt value]) -> Right (coreStringList (fixedIntegralRender fixed (fixedInput value)))
    (FixedBitAnd, [CoreInt lhs, CoreInt rhs]) -> fixedBitsValue ((Bits..&.) (fixedInputBits lhs) (fixedInputBits rhs))
    (FixedBitOr, [CoreInt lhs, CoreInt rhs]) -> fixedBitsValue ((Bits..|.) (fixedInputBits lhs) (fixedInputBits rhs))
    (FixedBitXor, [CoreInt lhs, CoreInt rhs]) -> fixedBitsValue (Bits.xor (fixedInputBits lhs) (fixedInputBits rhs))
    (FixedBitComplement, [CoreInt value]) -> fixedBitsValue (Bits.complement (fixedInputBits value))
    (shiftOp@FixedShift, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (shiftOp@FixedShiftL, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (shiftOp@FixedShiftR, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (shiftOp@FixedRotate, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (shiftOp@FixedRotateL, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (shiftOp@FixedRotateR, [CoreInt value, CoreInt amount]) -> shifted shiftOp value amount
    (FixedBit, [CoreInt amount])
      | hintToInteger amount < 0 ->
          Left (CoreEvalTypeError "negative fixed-width bit index")
      | hintToInteger amount >= fixedIntegralBitSize fixed ->
          fixedValue 0
      | otherwise ->
          fixedValue (2 ^ hintToInteger amount)
    (FixedTestBit, [CoreInt value, CoreInt amount])
      | hintToInteger amount < 0 ->
          Left (CoreEvalTypeError "negative fixed-width bit index")
      | hintToInteger amount >= fixedIntegralBitSize fixed ->
          Right (CoreBool False)
      | otherwise ->
          Right (CoreBool (Bits.testBit (fixedInputBits value) (fromInteger (hintToInteger amount))))
    (FixedMinBound, []) -> fixedValue (fixedIntegralMinValue fixed)
    (FixedMaxBound, []) -> fixedValue (fixedIntegralMaxValue fixed)
    _ ->
      Left (CoreEvalTypeError ("fixed-width primitive received unsupported values " <> Text.pack (show (map renderCoreValue values))))
 where
  fixedInput value
    | fixedIntegralIsSigned fixed = fixedIntegralNormalize fixed (hintToInteger value)
    | otherwise = fixedIntegralToBits fixed (hintToInteger value)
  fixedInputBits =
    fixedIntegralToBits fixed . hintToInteger
  fixedValue value =
    checkedCoreIntValue (mkHIntLiteral (fixedRuntimePayload fixed value))
  fixedBitsValue bits =
    checkedCoreIntValue (mkHIntLiteral (fixedRuntimePayloadFromBits fixed bits))
  shifted shiftOp value amount =
    case fixedIntegralShift fixed shiftOp (fixedInput value) (hintToInteger amount) of
      Left message -> Left (CoreEvalTypeError message)
      Right shiftedValue -> fixedValue shiftedValue

fixedRuntimePayload :: FixedIntegral -> Integer -> Integer
fixedRuntimePayload fixed =
  fixedRuntimePayloadFromBits fixed . fixedIntegralToBits fixed

fixedRuntimePayloadFromBits :: FixedIntegral -> Integer -> Integer
fixedRuntimePayloadFromBits fixed bits
  | normalizedBits >= 2 ^ (runtimeWordSize - 1) = normalizedBits - 2 ^ runtimeWordSize
  | otherwise = normalizedBits
 where
  runtimeWordSize = 64 :: Integer
  normalizedBits = fixedIntegralToBits fixed bits

evalFloatingPrimitive :: FloatingWidth -> FloatingPrimOp -> [CoreValue] -> Either CoreEvalError CoreValue
evalFloatingPrimitive width op values =
  case (width, op, values) of
    (FloatWidth, FloatEq, [CoreFloat lhs, CoreFloat rhs]) -> Right (CoreBool (lhs == rhs))
    (FloatWidth, FloatLt, [CoreFloat lhs, CoreFloat rhs]) -> Right (CoreBool (lhs < rhs))
    (FloatWidth, FloatShow, [CoreFloat value]) -> Right (coreStringList (Text.pack (show value)))
    (FloatWidth, FloatFromInt, [CoreInt value]) -> Right (CoreFloat (fromInteger (hintToInteger value)))
    (FloatWidth, _, [CoreFloat lhs, CoreFloat rhs])
      | Just f <- binaryFloating op -> Right (CoreFloat (realToFrac (f (realToFrac lhs) (realToFrac rhs) :: Double)))
    (FloatWidth, _, [CoreFloat value])
      | Just f <- unaryFloating op -> Right (CoreFloat (realToFrac (f (realToFrac value) :: Double)))
    (DoubleWidth, FloatEq, [CoreDouble lhs, CoreDouble rhs]) -> Right (CoreBool (lhs == rhs))
    (DoubleWidth, FloatLt, [CoreDouble lhs, CoreDouble rhs]) -> Right (CoreBool (lhs < rhs))
    (DoubleWidth, FloatShow, [CoreDouble value]) -> Right (coreStringList (Text.pack (show value)))
    (DoubleWidth, FloatFromInt, [CoreInt value]) -> Right (CoreDouble (fromInteger (hintToInteger value)))
    (DoubleWidth, _, [CoreDouble lhs, CoreDouble rhs])
      | Just f <- binaryFloating op -> Right (CoreDouble (f lhs rhs))
    (DoubleWidth, _, [CoreDouble value])
      | Just f <- unaryFloating op -> Right (CoreDouble (f value))
    _ -> Left (CoreEvalTypeError ("floating primitive received unsupported values " <> Text.pack (show (map renderCoreValue values))))
 where
  unaryFloating = \case
    FloatNegate -> Just negate
    FloatAbs -> Just abs
    FloatSignum -> Just signum
    FloatExp -> Just exp
    FloatLog -> Just log
    FloatSqrt -> Just sqrt
    FloatSin -> Just sin
    FloatCos -> Just cos
    FloatTan -> Just tan
    FloatAsin -> Just asin
    FloatAcos -> Just acos
    FloatAtan -> Just atan
    FloatSinh -> Just sinh
    FloatCosh -> Just cosh
    FloatTanh -> Just tanh
    FloatAsinh -> Just asinh
    FloatAcosh -> Just acosh
    FloatAtanh -> Just atanh
    _ -> Nothing

  binaryFloating = \case
    FloatAdd -> Just (+)
    FloatSub -> Just (-)
    FloatMul -> Just (*)
    FloatDiv -> Just (/)
    FloatPow -> Just (**)
    FloatAtan2 -> Just atan2
    _ -> Nothing

evalFloatingIntPrimitive :: FloatingWidth -> FloatingIntPrimOp -> [CoreValue] -> Either CoreEvalError CoreValue
evalFloatingIntPrimitive width op values =
  case (width, values) of
    (FloatWidth, [CoreFloat value]) -> evalRealFloatInt op value
    (DoubleWidth, [CoreDouble value]) -> evalRealFloatInt op value
    _ -> Left (CoreEvalTypeError ("floating/int primitive received unsupported values " <> Text.pack (show (map renderCoreValue values))))

evalRealFloatInt :: RealFloat a => FloatingIntPrimOp -> a -> Either CoreEvalError CoreValue
evalRealFloatInt op value =
  case op of
    FloatTruncate -> checkedCoreIntValue (mkHIntLiteral (toInteger (truncate value :: Integer)))
    FloatRound -> checkedCoreIntValue (mkHIntLiteral (toInteger (round value :: Integer)))
    FloatCeiling -> checkedCoreIntValue (mkHIntLiteral (toInteger (ceiling value :: Integer)))
    FloatFloor -> checkedCoreIntValue (mkHIntLiteral (toInteger (floor value :: Integer)))
    FloatIsNaN -> Right (CoreBool (isNaN value))
    FloatIsInfinite -> Right (CoreBool (isInfinite value))
    FloatIsDenormalized -> Right (CoreBool (isDenormalized value))
    FloatIsNegativeZero -> Right (CoreBool (isNegativeZero value))

checkedCoreIntValue :: Either IntError HInt -> Either CoreEvalError CoreValue
checkedCoreIntValue = \case
  Right value -> Right (CoreInt value)
  Left err -> Left (CoreEvalIntError err)

coreUserIOError :: Text -> CoreValue
coreUserIOError message =
  CoreData
    ioErrorDataConName
    [ Evaluated (CoreData ioErrorUserTypeDataConName [])
    , Evaluated (coreStringList message)
    , Evaluated (CoreData maybeNothingDataConName [])
    , Evaluated (CoreData maybeNothingDataConName [])
    ]

coreEOFIOError :: Text -> CoreValue
coreEOFIOError message =
  CoreData
    ioErrorDataConName
    [ Evaluated (CoreData ioErrorEOFTypeDataConName [])
    , Evaluated (coreStringList message)
    , Evaluated (CoreData maybeNothingDataConName [])
    , Evaluated (CoreData maybeNothingDataConName [])
    ]

coreDoesNotExistIOError :: Text -> CoreValue
coreDoesNotExistIOError message =
  CoreData
    ioErrorDataConName
    [ Evaluated (CoreData ioErrorDoesNotExistTypeDataConName [])
    , Evaluated (coreStringList message)
    , Evaluated (CoreData maybeNothingDataConName [])
    , Evaluated (CoreData maybeNothingDataConName [])
    ]

coreIllegalOperationIOError :: Text -> CoreValue
coreIllegalOperationIOError message =
  CoreData
    ioErrorDataConName
    [ Evaluated (CoreData ioErrorIllegalOperationTypeDataConName [])
    , Evaluated (coreStringList message)
    , Evaluated (CoreData maybeNothingDataConName [])
    , Evaluated (CoreData maybeNothingDataConName [])
    ]

coreExitWithResult :: CoreValidate.CoreValidationEnv -> CoreValue -> Either CoreEvalError CoreIOResult
coreExitWithResult _ (CoreData name [])
  | name == exitSuccessDataConName =
      CoreIOExit <$> checkedExitCode 0
coreExitWithResult coreEnv (CoreData name [codeThunk])
  | name == exitFailureDataConName = do
      code <- force coreEnv codeThunk
      case code of
        CoreInt value
          | hintToInteger value == 0 -> Right (CoreIOFailure (coreIllegalOperationIOError "ExitFailure 0"))
          | otherwise -> Right (CoreIOExit value)
        other -> Left (CoreEvalTypeError ("expected Int in ExitFailure, got " <> renderCoreValue other))
coreExitWithResult _ other =
  Left (CoreEvalTypeError ("expected ExitCode, got " <> renderCoreValue other))

checkedExitCode :: Integer -> Either CoreEvalError HInt
checkedExitCode value =
  case mkHIntLiteral value of
    Right intValue -> Right intValue
    Left err -> Left (CoreEvalIntError err)

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

coreList :: CoreType -> [CoreValue] -> CoreValue
coreList _ =
  foldr cons nil
 where
  nil =
    CoreData listNilDataConName []
  cons headValue tailValue =
    CoreData listConsDataConName [Evaluated headValue, Evaluated tailValue]

valueEquals :: CoreValue -> CoreValue -> Either CoreEvalError Bool
valueEquals lhs rhs =
  case (lhs, rhs) of
    (CoreInt lhsInt, CoreInt rhsInt) ->
      Right (eqHInt lhsInt rhsInt)
    (CoreInteger lhsInteger, CoreInteger rhsInteger) ->
      Right (lhsInteger == rhsInteger)
    (CoreFloat lhsFloat, CoreFloat rhsFloat) ->
      Right (lhsFloat == rhsFloat)
    (CoreDouble lhsDouble, CoreDouble rhsDouble) ->
      Right (lhsDouble == rhsDouble)
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
  CoreInteger value ->
    Text.pack (show value)
  CoreFloat value ->
    Text.pack (show value)
  CoreDouble value ->
    Text.pack (show value)
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
  CoreHandle handle closed ->
    "<Core Handle " <> renderStdHandlePrim handle <> " closed=" <> Text.pack (show closed) <> ">"
  CoreHandlePosn handle posn ->
    "<Core HandlePosn " <> renderStdHandlePrim handle <> " " <> renderHInt posn <> ">"
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
  PrimIntegerAdd -> "integerAdd#"
  PrimIntegerSub -> "integerSub#"
  PrimIntegerMul -> "integerMul#"
  PrimIntegerQuot -> "integerQuot#"
  PrimIntegerRem -> "integerRem#"
  PrimIntegerEq -> "integerEq#"
  PrimIntegerLt -> "integerLt#"
  PrimIntegerNegate -> "integerNegate#"
  PrimIntegerAbs -> "integerAbs#"
  PrimIntegerSignum -> "integerSignum#"
  PrimIntegerToInt -> "integerToInt#"
  PrimIntToInteger -> "intToInteger#"
  PrimIntegerToFloat width -> renderEvalFloatingWidth width <> ".fromInteger#"
  PrimShowInteger -> "showInteger#"
  PrimCharToInt -> "charToInt#"
  PrimIntToChar -> "intToChar#"
  PrimShowInt -> "showInt#"
  PrimShowBool -> "showBool#"
  PrimPutStrLn -> "putStrLn#"
  PrimGetLine -> "getLine#"
  PrimGetArgs -> "getArgs#"
  PrimGetProgName -> "getProgName#"
  PrimGetEnv -> "getEnv#"
  PrimExitWith -> "exitWith#"
  PrimStdHandle handle -> renderStdHandlePrim handle
  PrimOpenFile -> "openFile#"
  PrimHClose -> "hClose#"
  PrimReadFile -> "readFile#"
  PrimWriteFile -> "writeFile#"
  PrimAppendFile -> "appendFile#"
  PrimHFileSize -> "hFileSize#"
  PrimHSetFileSize -> "hSetFileSize#"
  PrimHIsEOF -> "hIsEOF#"
  PrimHSetBuffering -> "hSetBuffering#"
  PrimHGetBuffering -> "hGetBuffering#"
  PrimHFlush -> "hFlush#"
  PrimHGetPosn -> "hGetPosn#"
  PrimHSetPosn -> "hSetPosn#"
  PrimHSeek -> "hSeek#"
  PrimHTell -> "hTell#"
  PrimHIsOpen -> "hIsOpen#"
  PrimHIsClosed -> "hIsClosed#"
  PrimHIsReadable -> "hIsReadable#"
  PrimHIsWritable -> "hIsWritable#"
  PrimHIsSeekable -> "hIsSeekable#"
  PrimHIsTerminalDevice -> "hIsTerminalDevice#"
  PrimHSetEcho -> "hSetEcho#"
  PrimHGetEcho -> "hGetEcho#"
  PrimHShow -> "hShow#"
  PrimHWaitForInput -> "hWaitForInput#"
  PrimHReady -> "hReady#"
  PrimHGetChar -> "hGetChar#"
  PrimHGetLine -> "hGetLine#"
  PrimHLookAhead -> "hLookAhead#"
  PrimHGetContents -> "hGetContents#"
  PrimHPutChar -> "hPutChar#"
  PrimHPutStr -> "hPutStr#"
  PrimHPutStrLn -> "hPutStrLn#"
  PrimIOThen -> "thenIO#"
  PrimIOBind -> "bindIO#"
  PrimIOReturn -> "returnIO#"
  PrimIOFail -> "failIO#"
  PrimIOError -> "ioError#"
  PrimIOCatch -> "catchIO#"
  PrimIOTry -> "tryIO#"
  PrimIOFix -> "fixIO#"
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
  PrimPtrPlus -> "plusPtr#"
  PrimPtrMinus -> "minusPtr#"
  PrimPtrAlign -> "alignPtr#"
  PrimMallocBytes -> "mallocBytes#"
  PrimReallocBytes -> "reallocBytes#"
  PrimFree -> "free#"
  PrimFinalizerFree -> "finalizerFree#"
  PrimPeek kind -> "peek#" <> renderForeignStorableKind kind
  PrimPoke kind -> "poke#" <> renderForeignStorableKind kind
  PrimCopyBytes -> "copyBytes#"
  PrimMoveBytes -> "moveBytes#"
  PrimGetErrno -> "getErrno#"
  PrimResetErrno -> "resetErrno#"
  PrimPeekCString -> "peekCString#"
  PrimPeekCStringLen -> "peekCStringLen#"
  PrimNewCString -> "newCString#"
  PrimPeekCWString -> "peekCWString#"
  PrimPeekCWStringLen -> "peekCWStringLen#"
  PrimNewCWString -> "newCWString#"
  PrimFixedIntegral fixed op -> fixedIntegralOccurrence fixed <> "." <> Text.pack (show op) <> "#"
  PrimFloat width op -> Text.pack (show width) <> "." <> Text.pack (show op) <> "#"
  PrimFloatInt width op -> Text.pack (show width) <> "." <> Text.pack (show op) <> "#"

renderEvalFloatingWidth :: FloatingWidth -> Text
renderEvalFloatingWidth = \case
  FloatWidth -> "Float"
  DoubleWidth -> "Double"

renderForeignStorableKind :: ForeignStorableKind -> Text
renderForeignStorableKind = \case
  StoreInt -> "Int"
  StoreBool -> "Bool"
  StoreChar -> "Char"
  StoreInt8 -> "Int8"
  StoreWord8 -> "Word8"
  StoreInt16 -> "Int16"
  StoreWord16 -> "Word16"
  StoreInt32 -> "Int32"
  StoreWord32 -> "Word32"
  StoreInt64 -> "Int64"
  StoreWord -> "Word"
  StoreWord64 -> "Word64"
  StoreFloat -> "Float"
  StoreDouble -> "Double"
  StorePtr -> "Ptr"

renderStdHandlePrim :: StdHandle -> Text
renderStdHandlePrim = \case
  StdInHandle -> "stdin#"
  StdOutHandle -> "stdout#"
  StdErrHandle -> "stderr#"
