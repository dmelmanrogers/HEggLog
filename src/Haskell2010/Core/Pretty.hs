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
import Haskell2010.Syntax (Literal (..), ModuleName (..))

renderCoreModule :: CoreModule -> Text
renderCoreModule (CoreModule maybeName _ binds) =
  Text.unlines $
    header <> map renderCoreBind binds
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
  CPrimOp op arguments ty ->
    withType
      ( renderCorePrimOp op
          <> "("
          <> Text.intercalate ", " (map renderCoreExpr arguments)
          <> ")"
      )
      ty

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
  PrimEq -> "=="
  PrimLt -> "<"
  PrimNegate -> "negate#"

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
  LChar c -> Text.pack (show c)
  LString value -> Text.pack (show (Text.unpack value))

renderModuleName :: ModuleName -> Text
renderModuleName (ModuleName parts) =
  Text.intercalate "." parts

parensIf :: Bool -> Text -> Text
parensIf needsParens text
  | needsParens = "(" <> text <> ")"
  | otherwise = text
