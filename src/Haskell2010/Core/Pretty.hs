module Haskell2010.Core.Pretty
  ( renderCoreAlt
  , renderCoreAltCon
  , renderCoreBind
  , renderCoreExpr
  , renderCoreModule
  , renderCorePrimOp
  , renderCoreType
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import Haskell2010.Names (renderRName)
import qualified Haskell2010.Syntax as S
import Haskell2010.Syntax (Literal (..), ModuleName (..))

renderCoreModule :: CoreModule -> Text
renderCoreModule (CoreModule maybeName _ binds foreignExports) =
  Text.unlines $
    header <> map renderCoreBind binds <> map renderForeignExport foreignExports
 where
  header =
    case maybeName of
      Nothing -> []
      Just moduleName -> ["module " <> renderModuleName moduleName]

renderCoreBind :: CoreBind -> Text
renderCoreBind = \case
  CoreNonRec binder rhs ->
    renderCoreBinder binder <> " = " <> renderCoreExpr rhs
  CoreRec pairs ->
    "rec {\n"
      <> Text.unlines (map (("  " <>) . renderRecPair) pairs)
      <> "}"
 where
  renderRecPair (binder, rhs) =
    renderCoreBinder binder <> " = " <> renderCoreExpr rhs

renderCoreExpr :: CoreExpr -> Text
renderCoreExpr = \case
  CVar name ty ->
    withType (renderRName name) ty
  CLit literal ty ->
    withType (renderLiteral literal) ty
  CCon name ty ->
    withType (renderRName name) ty
  CLam binder body ty ->
    withType ("(\\" <> renderCoreBinder binder <> " -> " <> renderCoreExpr body <> ")") ty
  CApp fn arg ty ->
    withType ("(" <> renderCoreExpr fn <> " " <> renderCoreExpr arg <> ")") ty
  CTypeLam variables body ty ->
    withType
      ( "(/\\"
          <> Text.unwords (map renderRName variables)
          <> " -> "
          <> renderCoreExpr body
          <> ")"
      )
      ty
  CTypeApp fn arguments ty ->
    withType
      ( "("
          <> renderCoreExpr fn
          <> " @"
          <> Text.intercalate " @" (map renderCoreType arguments)
          <> ")"
      )
      ty
  CLet bind body ty ->
    withType ("(let " <> renderCoreBind bind <> " in " <> renderCoreExpr body <> ")") ty
  CCase scrutinee binder alternatives ty ->
    withType
      ( "case "
          <> renderCoreExpr scrutinee
          <> " of "
          <> renderCoreBinder binder
          <> " { "
          <> Text.intercalate "; " (map renderCoreAlt alternatives)
          <> " }"
      )
      ty
  CCoerce expression ty ->
    withType ("coerce[" <> renderCoreType ty <> "] " <> renderCoreExpr expression) ty
  CPrimOp op arguments ty ->
    withType
      ( renderCorePrimOp op
          <> "("
          <> Text.intercalate ", " (map renderCoreExpr arguments)
          <> ")"
      )
      ty
  CForeignCall foreignImport arguments ty ->
    withType
      ( "foreign-call "
          <> renderForeignImport foreignImport
          <> "("
          <> Text.intercalate ", " (map renderCoreExpr arguments)
          <> ")"
      )
      ty
  CForeignImportValue foreignImport ty ->
    withType ("foreign-import " <> renderForeignImport foreignImport) ty

renderCoreAlt :: CoreAlt -> Text
renderCoreAlt (CoreAlt altCon binders body) =
  renderCoreAltCon altCon
    <> renderAltBinders binders
    <> " -> "
    <> renderCoreExpr body

renderCoreAltCon :: CoreAltCon -> Text
renderCoreAltCon = \case
  DefaultAlt -> "default"
  LiteralAlt literal -> renderLiteral literal
  ConstructorAlt name -> renderRName name

renderCorePrimOp :: CorePrimOp -> Text
renderCorePrimOp = \case
  PrimAdd -> "+"
  PrimSub -> "-"
  PrimMul -> "*"
  PrimDiv -> "div#"
  PrimRem -> "rem#"
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
  PrimFloat width op -> renderFloatingWidth width <> "." <> renderFloatingPrimOp op <> "#"
  PrimFloatInt width op -> renderFloatingWidth width <> "." <> renderFloatingIntPrimOp op <> "#"

renderFloatingWidth :: FloatingWidth -> Text
renderFloatingWidth = \case
  FloatWidth -> "float"
  DoubleWidth -> "double"

renderFloatingPrimOp :: FloatingPrimOp -> Text
renderFloatingPrimOp = \case
  FloatAdd -> "add"
  FloatSub -> "sub"
  FloatMul -> "mul"
  FloatDiv -> "div"
  FloatEq -> "eq"
  FloatLt -> "lt"
  FloatNegate -> "negate"
  FloatAbs -> "abs"
  FloatSignum -> "signum"
  FloatFromInt -> "fromInt"
  FloatShow -> "show"
  FloatExp -> "exp"
  FloatLog -> "log"
  FloatSqrt -> "sqrt"
  FloatSin -> "sin"
  FloatCos -> "cos"
  FloatTan -> "tan"
  FloatAsin -> "asin"
  FloatAcos -> "acos"
  FloatAtan -> "atan"
  FloatSinh -> "sinh"
  FloatCosh -> "cosh"
  FloatTanh -> "tanh"
  FloatAsinh -> "asinh"
  FloatAcosh -> "acosh"
  FloatAtanh -> "atanh"
  FloatPow -> "pow"
  FloatAtan2 -> "atan2"

renderFloatingIntPrimOp :: FloatingIntPrimOp -> Text
renderFloatingIntPrimOp = \case
  FloatTruncate -> "truncate"
  FloatRound -> "round"
  FloatCeiling -> "ceiling"
  FloatFloor -> "floor"
  FloatIsNaN -> "isNaN"
  FloatIsInfinite -> "isInfinite"
  FloatIsDenormalized -> "isDenormalized"
  FloatIsNegativeZero -> "isNegativeZero"

renderForeignImport :: CoreForeignImport -> Text
renderForeignImport foreignImport =
  renderRName (coreForeignImportName foreignImport)
    <> "["
    <> renderForeignCallConv (coreForeignImportCallConv foreignImport)
    <> ", "
    <> renderForeignSafety (coreForeignImportSafety foreignImport)
    <> ", "
    <> renderForeignImportEntity (coreForeignImportEntity foreignImport)
    <> "]"

renderForeignExport :: CoreForeignExport -> Text
renderForeignExport foreignExport =
  "foreign-export "
    <> renderRName (coreForeignExportName foreignExport)
    <> "["
    <> renderForeignCallConv (coreForeignExportCallConv foreignExport)
    <> ", "
    <> renderForeignExportEntity (coreForeignExportEntity foreignExport)
    <> "] :: "
    <> renderCoreType (coreForeignExportType foreignExport)

renderForeignCallConv :: S.ForeignCallConv -> Text
renderForeignCallConv = \case
  S.ForeignCCall -> "ccall"
  S.ForeignStdCall -> "stdcall"
  S.ForeignCPlusPlus -> "cplusplus"
  S.ForeignJvm -> "jvm"
  S.ForeignDotNet -> "dotnet"
  S.ForeignOtherCallConv occurrence -> occurrence

renderForeignSafety :: S.ForeignSafety -> Text
renderForeignSafety = \case
  S.ForeignSafe -> "safe"
  S.ForeignUnsafe -> "unsafe"

renderForeignImportEntity :: S.ForeignImportEntity -> Text
renderForeignImportEntity entity =
  case S.foreignImportEntityKind entity of
    S.ForeignImportDefault -> "default"
    S.ForeignImportStatic header symbol -> "static " <> renderMaybeHeader header <> symbol
    S.ForeignImportAddress header symbol -> "address " <> renderMaybeHeader header <> symbol
    S.ForeignImportDynamic -> "dynamic"
    S.ForeignImportWrapper -> "wrapper"
    S.ForeignImportUnknown raw -> "unknown " <> raw
 where
  renderMaybeHeader = \case
    Nothing -> ""
    Just header -> "[" <> header <> "] "

renderForeignExportEntity :: S.ForeignExportEntity -> Text
renderForeignExportEntity entity =
  case S.foreignExportEntitySymbol entity of
    Nothing -> "default"
    Just symbol -> symbol

renderCoreType :: CoreType -> Text
renderCoreType =
  renderTypePrec 0

renderTypePrec :: Int -> CoreType -> Text
renderTypePrec contextPrec = \case
  CTyVar name -> renderRName name
  CTyCon name -> renderRName name
  CTyApp fn arg ->
    parensIf (contextPrec > 1) $
      renderTypePrec 1 fn <> " " <> renderTypePrec 2 arg
  CTyFun arg result ->
    parensIf (contextPrec > 0) $
      renderTypePrec 1 arg <> " -> " <> renderTypePrec 0 result
  CTyForall variables body ->
    parensIf (contextPrec > 0) $
      "forall "
        <> Text.unwords (map renderRName variables)
        <> ". "
        <> renderCoreType body
  CTyTuple fields ->
    "(" <> Text.intercalate ", " (map renderCoreType fields) <> ")"
  CTyList elementTy ->
    "[" <> renderCoreType elementTy <> "]"

renderCoreBinder :: CoreBinder -> Text
renderCoreBinder (CoreBinder name ty) =
  renderRName name <> " : " <> renderCoreType ty

renderAltBinders :: [CoreBinder] -> Text
renderAltBinders [] =
  ""
renderAltBinders binders =
  " " <> Text.unwords (map renderCoreBinder binders)

withType :: Text -> CoreType -> Text
withType expression ty =
  expression <> " : " <> renderCoreType ty

renderLiteral :: Literal -> Text
renderLiteral = \case
  LInt n -> Text.pack (show n)
  LFloat n -> Text.pack (show n) <> "f"
  LDouble n -> Text.pack (show n)
  LChar c -> Text.pack (show c)
  LString value -> Text.pack (show (Text.unpack value))

renderModuleName :: ModuleName -> Text
renderModuleName (ModuleName parts) =
  Text.intercalate "." parts

parensIf :: Bool -> Text -> Text
parensIf needsParens text
  | needsParens = "(" <> text <> ")"
  | otherwise = text
