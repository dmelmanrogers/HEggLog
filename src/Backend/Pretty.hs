module Backend.Pretty
  ( renderBackendProgram
  , renderBackendType
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Backend.IR
import Runtime.Int (renderHInt)
import Syntax.Pretty (prettyName, renderDoc)

renderBackendProgram :: BackendProgram -> Text
renderBackendProgram program =
  "root : "
    <> renderBackendType (backendRootType program)
    <> "\n"
    <> renderBackendExpr 0 (backendRoot program)

renderBackendExpr :: Int -> BackendExpr -> Text
renderBackendExpr outerPrec = \case
  BEAtom _ atom ->
    renderBackendAtom atom
  BEPrim _ prim lhs rhs ->
    parenthesize (outerPrec > 5) $
      Text.unwords [renderBackendAtom lhs, renderBackendPrim prim, renderBackendAtom rhs]
  BEIf _ cond thenBranch elseBranch ->
    parenthesize (outerPrec > 0) $
      Text.unwords
        [ "if"
        , renderBackendAtom cond
        , "then"
        , renderBackendExpr 0 thenBranch
        , "else"
        , renderBackendExpr 0 elseBranch
        ]
  BELet _ name rhs body ->
    parenthesize (outerPrec > 0) $
      "let "
        <> renderDoc (prettyName name)
        <> " = "
        <> renderBackendExpr 0 rhs
        <> " in\n"
        <> renderBackendExpr 0 body

renderBackendAtom :: BackendAtom -> Text
renderBackendAtom = \case
  BVar name -> renderDoc (prettyName name)
  BInt n -> renderHInt n
  BBool True -> "true"
  BBool False -> "false"

renderBackendPrim :: BackendPrim -> Text
renderBackendPrim = \case
  BPAdd -> "+"
  BPSub -> "-"
  BPMul -> "*"
  BPLt -> "<"
  BPEq {} -> "=="

renderBackendType :: BackendType -> Text
renderBackendType = \case
  BI64 -> "i64"
  BI1 -> "i1"

parenthesize :: Bool -> Text -> Text
parenthesize shouldWrap text
  | shouldWrap = "(" <> text <> ")"
  | otherwise = text
