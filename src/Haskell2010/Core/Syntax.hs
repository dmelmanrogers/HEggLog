module Haskell2010.Core.Syntax
  ( CoreAlt (..)
  , CoreAltCon (..)
  , CoreBind (..)
  , CoreBinder (..)
  , CoreExpr (..)
  , CoreModule (..)
  , CorePrimOp (..)
  , CoreType (..)
  , boolTy
  , charTy
  , falseDataConName
  , funTy
  , intTy
  , stringTy
  , trueDataConName
  , unitTy
  , exprType
  , bindersOf
  )
where

import Data.Text (Text)
import Haskell2010.Names (Namespace (..), RName (..))
import Haskell2010.Syntax (Literal, ModuleName)

data CoreModule = CoreModule
  { coreModuleName :: Maybe ModuleName
  , coreModuleBinds :: [CoreBind]
  }
  deriving stock (Show, Eq, Ord)

data CoreType
  = CTyVar RName
  | CTyCon RName
  | CTyApp CoreType CoreType
  | CTyFun CoreType CoreType
  | CTyForall [RName] CoreType
  | CTyTuple [CoreType]
  | CTyList CoreType
  deriving stock (Show, Eq, Ord)

data CoreBinder = CoreBinder
  { coreBinderName :: RName
  , coreBinderType :: CoreType
  }
  deriving stock (Show, Eq, Ord)

data CoreBind
  = CoreNonRec CoreBinder CoreExpr
  | CoreRec [(CoreBinder, CoreExpr)]
  deriving stock (Show, Eq, Ord)

data CoreExpr
  = CVar RName CoreType
  | CLit Literal CoreType
  | CCon RName CoreType
  | CLam CoreBinder CoreExpr CoreType
  | CApp CoreExpr CoreExpr CoreType
  | CTypeLam [RName] CoreExpr CoreType
  | CTypeApp CoreExpr [CoreType] CoreType
  | CLet CoreBind CoreExpr CoreType
  | CCase CoreExpr CoreBinder [CoreAlt] CoreType
  | CPrimOp CorePrimOp [CoreExpr] CoreType
  deriving stock (Show, Eq, Ord)

data CoreAlt = CoreAlt CoreAltCon [CoreBinder] CoreExpr
  deriving stock (Show, Eq, Ord)

data CoreAltCon
  = DefaultAlt
  | LiteralAlt Literal
  | ConstructorAlt RName
  deriving stock (Show, Eq, Ord)

data CorePrimOp
  = PrimAdd
  | PrimSub
  | PrimMul
  | PrimDiv
  | PrimEq
  | PrimLt
  | PrimNegate
  deriving stock (Show, Eq, Ord)

exprType :: CoreExpr -> CoreType
exprType = \case
  CVar _ ty -> ty
  CLit _ ty -> ty
  CCon _ ty -> ty
  CLam _ _ ty -> ty
  CApp _ _ ty -> ty
  CTypeLam _ _ ty -> ty
  CTypeApp _ _ ty -> ty
  CLet _ _ ty -> ty
  CCase _ _ _ ty -> ty
  CPrimOp _ _ ty -> ty

bindersOf :: CoreBind -> [CoreBinder]
bindersOf = \case
  CoreNonRec binder _ -> [binder]
  CoreRec pairs -> map fst pairs

funTy :: CoreType -> CoreType -> CoreType
funTy =
  CTyFun

intTy :: CoreType
intTy =
  builtinType "Int" (-1)

boolTy :: CoreType
boolTy =
  builtinType "Bool" (-2)

charTy :: CoreType
charTy =
  builtinType "Char" (-3)

unitTy :: CoreType
unitTy =
  CTyTuple []

stringTy :: CoreType
stringTy =
  CTyList charTy

trueDataConName :: RName
trueDataConName =
  builtinCon "True" (-10)

falseDataConName :: RName
falseDataConName =
  builtinCon "False" (-11)

builtinType :: Text -> Int -> CoreType
builtinType occurrence unique =
  CTyCon (RName TypeNamespace occurrence unique True)

builtinCon :: Text -> Int -> RName
builtinCon occurrence unique =
  RName ConstructorNamespace occurrence unique True
