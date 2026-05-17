module Syntax.Located
  ( LocatedExpr (..)
  , LocatedExprNode (..)
  , locatedExprSpan
  , locatedExprNode
  , stripLocatedExpr
  )
where

import Syntax.AST
import Syntax.Span (SourceSpan)

data LocatedExpr = LocatedExpr SourceSpan LocatedExprNode
  deriving stock (Show, Eq)

data LocatedExprNode
  = LInt Integer
  | LBool Bool
  | LVar Name
  | LLet Name LocatedExpr LocatedExpr
  | LIf LocatedExpr LocatedExpr LocatedExpr
  | LBin BinOp LocatedExpr LocatedExpr
  | LLam Name Type LocatedExpr
  | LApp LocatedExpr LocatedExpr
  deriving stock (Show, Eq)

locatedExprSpan :: LocatedExpr -> SourceSpan
locatedExprSpan (LocatedExpr sourceRange _) =
  sourceRange

locatedExprNode :: LocatedExpr -> LocatedExprNode
locatedExprNode (LocatedExpr _ node) =
  node

stripLocatedExpr :: LocatedExpr -> Expr
stripLocatedExpr (LocatedExpr _ node) =
  case node of
    LInt value ->
      EInt value
    LBool value ->
      EBool value
    LVar name ->
      EVar name
    LLet name rhs body ->
      ELet name (stripLocatedExpr rhs) (stripLocatedExpr body)
    LIf cond thenBranch elseBranch ->
      EIf (stripLocatedExpr cond) (stripLocatedExpr thenBranch) (stripLocatedExpr elseBranch)
    LBin op lhs rhs ->
      EBin op (stripLocatedExpr lhs) (stripLocatedExpr rhs)
    LLam name argType body ->
      ELam name argType (stripLocatedExpr body)
    LApp fn arg ->
      EApp (stripLocatedExpr fn) (stripLocatedExpr arg)
