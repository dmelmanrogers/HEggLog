module Haskell2010.STG.Syntax
  ( STGAlt (..)
  , STGAtom (..)
  , STGBind (..)
  , STGBinder (..)
  , STGExpr (..)
  , STGProgram (..)
  , STGRhs (..)
  , STGUpdateFlag (..)
  , stgAtomType
  , stgBindersOf
  , stgExprType
  , stgRhsType
  )
where

import Haskell2010.Core.Syntax (CoreAltCon, CorePrimOp, CoreType (..))
import Haskell2010.Names (RName)
import Haskell2010.Syntax (Literal)

data STGProgram = STGProgram
  { stgProgramBinds :: [STGBind]
  }
  deriving stock (Show, Eq, Ord)

data STGBind
  = STGNonRec STGBinder STGRhs
  | STGRec [(STGBinder, STGRhs)]
  deriving stock (Show, Eq, Ord)

data STGBinder = STGBinder
  { stgBinderName :: RName
  , stgBinderType :: CoreType
  }
  deriving stock (Show, Eq, Ord)

data STGRhs
  = STGFunction [STGBinder] STGExpr
  | STGThunk STGUpdateFlag STGExpr
  | STGConstructor RName [STGAtom] CoreType
  deriving stock (Show, Eq, Ord)

data STGUpdateFlag
  = Updatable
  | SingleEntry
  deriving stock (Show, Eq, Ord)

data STGExpr
  = STGAtom STGAtom
  | STGApp RName [STGAtom] CoreType
  | STGLet STGBind STGExpr CoreType
  | STGCase STGExpr STGBinder [STGAlt] CoreType
  | STGPrim CorePrimOp [STGAtom] CoreType
  deriving stock (Show, Eq, Ord)

data STGAtom
  = STGVar RName CoreType
  | STGLit Literal CoreType
  | STGCon RName CoreType
  deriving stock (Show, Eq, Ord)

data STGAlt = STGAlt CoreAltCon [STGBinder] STGExpr
  deriving stock (Show, Eq, Ord)

stgExprType :: STGExpr -> CoreType
stgExprType = \case
  STGAtom atom -> stgAtomType atom
  STGApp _ _ ty -> ty
  STGLet _ _ ty -> ty
  STGCase _ _ _ ty -> ty
  STGPrim _ _ ty -> ty

stgAtomType :: STGAtom -> CoreType
stgAtomType = \case
  STGVar _ ty -> ty
  STGLit _ ty -> ty
  STGCon _ ty -> ty

stgRhsType :: STGRhs -> CoreType
stgRhsType = \case
  STGFunction binders body ->
    foldr (CTyFun . stgBinderType) (stgExprType body) binders
  STGThunk _ body ->
    stgExprType body
  STGConstructor _ _ ty ->
    ty

stgBindersOf :: STGBind -> [STGBinder]
stgBindersOf = \case
  STGNonRec binder _ -> [binder]
  STGRec pairs -> map fst pairs
