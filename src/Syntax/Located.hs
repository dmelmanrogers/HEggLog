module Syntax.Located
  ( LocatedExpr (..)
  , LocatedExprNode (..)
  , LocatedParam (..)
  , LocatedProgram (..)
  , LocatedTopDef (..)
  , locatedExprSpan
  , locatedExprNode
  , stripLocatedExpr
  , stripLocatedProgram
  )
where

import Syntax.AST
import Syntax.Span (SourceSpan)

data LocatedExpr = LocatedExpr SourceSpan LocatedExprNode
  deriving stock (Show, Eq)

data LocatedParam = LocatedParam SourceSpan Param
  deriving stock (Show, Eq)

data LocatedTopDef = LocatedTopDef
  { locatedTopDefSpan :: SourceSpan
  , locatedTopDefName :: Name
  , locatedTopDefParams :: [LocatedParam]
  , locatedTopDefReturnType :: Type
  , locatedTopDefBody :: LocatedExpr
  }
  deriving stock (Show, Eq)

data LocatedProgram = LocatedProgram
  { locatedProgramDefs :: [LocatedTopDef]
  , locatedProgramMain :: LocatedExpr
  }
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

stripLocatedProgram :: LocatedProgram -> Program
stripLocatedProgram program =
  Program
    { programDefs = map stripLocatedTopDef (locatedProgramDefs program)
    , programMain = stripLocatedExpr (locatedProgramMain program)
    }

stripLocatedTopDef :: LocatedTopDef -> TopDef
stripLocatedTopDef topDef =
  TopDef
    { topDefName = locatedTopDefName topDef
    , topDefParams = map stripLocatedParam (locatedTopDefParams topDef)
    , topDefReturnType = locatedTopDefReturnType topDef
    , topDefBody = stripLocatedExpr (locatedTopDefBody topDef)
    }

stripLocatedParam :: LocatedParam -> Param
stripLocatedParam (LocatedParam _ param) =
  param
