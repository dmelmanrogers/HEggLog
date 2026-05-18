module Syntax.AST
  ( Name (..)
  , Type (..)
  , BinOp (..)
  , Param (..)
  , TopDef (..)
  , Program (..)
  , Expr (..)
  )
where

import Data.Text (Text)

newtype Name = Name {unName :: Text}
  deriving stock (Show, Eq, Ord)

data Type
  = TInt
  | TBool
  | TFun Type Type
  deriving stock (Show, Eq, Ord)

data BinOp
  = Add
  | Sub
  | Mul
  | Div
  | Eq
  | Lt
  deriving stock (Show, Eq, Ord)

data Param = Param
  { paramName :: Name
  , paramType :: Type
  }
  deriving stock (Show, Eq, Ord)

data TopDef = TopDef
  { topDefName :: Name
  , topDefParams :: [Param]
  , topDefReturnType :: Type
  , topDefBody :: Expr
  }
  deriving stock (Show, Eq, Ord)

data Program = Program
  { programDefs :: [TopDef]
  , programMain :: Expr
  }
  deriving stock (Show, Eq, Ord)

data Expr
  = EInt Integer
  | EBool Bool
  | EVar Name
  | ELet Name Expr Expr
  | EIf Expr Expr Expr
  | EBin BinOp Expr Expr
  | ELam Name Type Expr
  | EApp Expr Expr
  deriving stock (Show, Eq, Ord)
