module Haskell2010.STG.Pretty
  ( renderSTGAlt
  , renderSTGAtom
  , renderSTGBind
  , renderSTGBinder
  , renderSTGExpr
  , renderSTGProgram
  , renderSTGRhs
  , renderSTGUpdateFlag
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Pretty (renderCoreAltCon, renderCorePrimOp, renderCoreType)
import Haskell2010.Core.Syntax
  ( CoreForeignExport (..)
  , CoreForeignImport (..)
  , CoreType
  )
import Haskell2010.Names (renderRName)
import Haskell2010.STG.Syntax
import qualified Haskell2010.Syntax as S
import Haskell2010.Syntax (Literal (..))

renderSTGProgram :: STGProgram -> Text
renderSTGProgram (STGProgram _ binds foreignExports _) =
  Text.unlines $
    ["stg {"]
      <> concatMap (indentLines . renderSTGBind) binds
      <> concatMap (indentLines . renderSTGForeignExport) foreignExports
      <> ["}"]

renderSTGBind :: STGBind -> Text
renderSTGBind = \case
  STGNonRec binder rhs ->
    renderSTGBinder binder <> " = " <> renderSTGRhs rhs
  STGRec pairs ->
    Text.unlines $
      ["rec {"]
        <> concatMap (indentLines . renderRecPair) pairs
        <> ["}"]
 where
  renderRecPair (binder, rhs) =
    renderSTGBinder binder <> " = " <> renderSTGRhs rhs

renderSTGRhs :: STGRhs -> Text
renderSTGRhs = \case
  STGFunction binders body ->
    "fun"
      <> renderFunctionBinders binders
      <> " -> "
      <> renderSTGExpr body
  STGThunk updateFlag body ->
    "thunk[" <> renderSTGUpdateFlag updateFlag <> "] " <> renderSTGExpr body
  STGConstructor name arguments ty ->
    "con "
      <> renderRName name
      <> "("
      <> Text.intercalate ", " (map renderSTGAtom arguments)
      <> ") : "
      <> renderCoreType ty

renderSTGExpr :: STGExpr -> Text
renderSTGExpr = \case
  STGAtom atom ->
    renderSTGAtom atom
  STGSpanned _ expression ->
    renderSTGExpr expression
  STGApp name arguments ty ->
    withType
      ( renderRName name
          <> "("
          <> Text.intercalate ", " (map renderSTGAtom arguments)
          <> ")"
      )
      ty
  STGLet bind body ty ->
    withType ("(let " <> renderSTGBind bind <> " in " <> renderSTGExpr body <> ")") ty
  STGCase scrutinee binder alternatives ty ->
    withType
      ( "case "
          <> renderSTGExpr scrutinee
          <> " of "
          <> renderSTGBinder binder
          <> " { "
          <> Text.intercalate "; " (map renderSTGAlt alternatives)
          <> " }"
      )
      ty
  STGPrim op arguments ty ->
    withType
      ( renderCorePrimOp op
          <> "("
          <> Text.intercalate ", " (map renderSTGAtom arguments)
          <> ")"
      )
      ty
  STGForeignCall foreignImport arguments ty ->
    withType
      ( "foreign-call "
          <> renderSTGForeignImport foreignImport
          <> "("
          <> Text.intercalate ", " (map renderSTGAtom arguments)
          <> ")"
      )
      ty
  STGForeignImportValue foreignImport ty ->
    withType ("foreign-import " <> renderSTGForeignImport foreignImport) ty

renderSTGAtom :: STGAtom -> Text
renderSTGAtom = \case
  STGVar name ty ->
    withType (renderRName name) ty
  STGLit literal ty ->
    withType (renderLiteral literal) ty
  STGCon name ty ->
    withType (renderRName name) ty

renderSTGAlt :: STGAlt -> Text
renderSTGAlt (STGAlt altCon binders body) =
  renderCoreAltCon altCon
    <> renderAltBinders binders
    <> " -> "
    <> renderSTGExpr body

renderSTGBinder :: STGBinder -> Text
renderSTGBinder (STGBinder name ty) =
  renderRName name <> " : " <> renderCoreType ty

renderSTGUpdateFlag :: STGUpdateFlag -> Text
renderSTGUpdateFlag = \case
  Updatable -> "updatable"
  SingleEntry -> "single-entry"

renderAltBinders :: [STGBinder] -> Text
renderAltBinders [] =
  ""
renderAltBinders binders =
  " " <> Text.unwords (map renderSTGBinder binders)

renderFunctionBinders :: [STGBinder] -> Text
renderFunctionBinders [] =
  ""
renderFunctionBinders binders =
  " " <> Text.unwords (map renderSTGBinder binders)

renderSTGForeignImport :: CoreForeignImport -> Text
renderSTGForeignImport foreignImport =
  renderRName (coreForeignImportName foreignImport)
    <> "["
    <> renderForeignCallConv (coreForeignImportCallConv foreignImport)
    <> ", "
    <> renderForeignSafety (coreForeignImportSafety foreignImport)
    <> ", "
    <> renderForeignImportEntity (coreForeignImportEntity foreignImport)
    <> "]"

renderSTGForeignExport :: CoreForeignExport -> Text
renderSTGForeignExport foreignExport =
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

withType :: Text -> CoreType -> Text
withType expression ty =
  expression <> " : " <> renderCoreType ty

renderLiteral :: Literal -> Text
renderLiteral = \case
  LInt n -> Text.pack (show n)
  LInteger n -> Text.pack (show n) <> "i"
  LFloat n -> Text.pack (show n) <> "f"
  LDouble n -> Text.pack (show n)
  LChar c -> Text.pack (show c)
  LString value -> Text.pack (show (Text.unpack value))

indentLines :: Text -> [Text]
indentLines text =
  map ("  " <>) (Text.lines text)
