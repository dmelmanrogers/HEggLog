module Syntax.Pretty
  ( prettyName
  , prettyType
  , prettyBinOp
  , prettyExpr
  , renderDoc
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Prettyprinter
  ( Doc
  , Pretty (pretty)
  , align
  , defaultLayoutOptions
  , group
  , hardline
  , layoutPretty
  , parens
  , (<+>)
  )
import Prettyprinter.Render.Text (renderStrict)
import Syntax.AST

prettyName :: Name -> Doc ann
prettyName = pretty . unName

prettyType :: Type -> Doc ann
prettyType = \case
  TInt -> "Int"
  TBool -> "Bool"
  TFun arg result ->
    parens (prettyType arg <+> "->" <+> prettyType result)

prettyBinOp :: BinOp -> Doc ann
prettyBinOp = \case
  Add -> "+"
  Sub -> "-"
  Mul -> "*"
  Div -> "/"
  Eq -> "=="
  Lt -> "<"

prettyExpr :: Expr -> Doc ann
prettyExpr = go 0
 where
  go :: Int -> Expr -> Doc ann
  go outerPrec = \case
    EInt n -> pretty n
    EBool True -> "true"
    EBool False -> "false"
    EVar name -> prettyName name
    ELet name rhs body ->
      withParens 0 $
        group $
          align $
            "let"
              <+> prettyName name
              <+> "="
              <+> go 0 rhs
              <+> "in"
              <> hardline
              <> go 0 body
    EIf cond thenBranch elseBranch ->
      withParens 0 $
        group $
          align $
            "if"
              <+> go 0 cond
              <+> "then"
              <+> go 0 thenBranch
              <+> "else"
              <+> go 0 elseBranch
    EBin op lhs rhs ->
      withParens (binPrec op) $
        go (binPrec op) lhs <+> prettyBinOp op <+> go (binPrec op + 1) rhs
    ELam name argTy body ->
      withParens 0 $
        "\\"
          <> prettyName name
          <+> ":"
          <+> prettyType argTy
          <+> "->"
          <+> go 0 body
    EApp fn arg ->
      withParens 7 $
        go 7 fn <+> go 8 arg
   where
    withParens :: Int -> Doc ann -> Doc ann
    withParens innerPrec doc
      | outerPrec > innerPrec = parens doc
      | otherwise = doc

  binPrec :: BinOp -> Int
  binPrec = \case
    Eq -> 3
    Lt -> 4
    Add -> 5
    Sub -> 5
    Mul -> 6
    Div -> 6

renderDoc :: Doc ann -> Text
renderDoc =
  Text.stripEnd . renderStrict . layoutPretty defaultLayoutOptions
