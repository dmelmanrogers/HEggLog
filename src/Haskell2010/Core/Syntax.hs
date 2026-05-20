module Haskell2010.Core.Syntax
  ( CoreAlt (..)
  , CoreAltCon (..)
  , CoreBind (..)
  , CoreBinder (..)
  , CoreConstructorInfo (..)
  , CoreConstructorRepresentation (..)
  , CoreExpr (..)
  , CoreModule (..)
  , CorePrimOp (..)
  , CoreType (..)
  , boolTy
  , charTy
  , eitherLeftDataConName
  , eitherRightDataConName
  , eitherTyConName
  , falseDataConName
  , funTy
  , intTy
  , ioTy
  , ioTyConName
  , listConsDataConName
  , listNilDataConName
  , maybeJustDataConName
  , maybeNothingDataConName
  , maybeTyConName
  , orderingEQDataConName
  , orderingGTDataConName
  , orderingLTDataConName
  , orderingTy
  , stringTy
  , trueDataConName
  , tupleDataConName
  , unitTy
  , unitDataConName
  , exprType
  , bindersOf
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Names (Namespace (..), RName (..))
import Haskell2010.Syntax (Literal, ModuleName)

data CoreModule = CoreModule
  { coreModuleName :: Maybe ModuleName
  , coreModuleConstructors :: Map.Map RName CoreConstructorInfo
  , coreModuleBinds :: [CoreBind]
  }
  deriving stock (Show, Eq, Ord)

data CoreConstructorInfo = CoreConstructorInfo
  { constructorTyVars :: [RName]
  , constructorFields :: [CoreType]
  , constructorResult :: CoreType
  , constructorRepresentation :: CoreConstructorRepresentation
  }
  deriving stock (Show, Eq, Ord)

data CoreConstructorRepresentation
  = CoreDataConstructor
  | CoreNewtypeConstructor
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
  | CCoerce CoreExpr CoreType
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
  | PrimCharToInt
  | PrimIntToChar
  | PrimShowInt
  | PrimShowBool
  | PrimPutStrLn
  | PrimIOThen
  | PrimIOBind
  | PrimIOReturn
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
  CCoerce _ ty -> ty
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

maybeTyConName :: RName
maybeTyConName =
  builtinTypeName "Maybe" (-4)

eitherTyConName :: RName
eitherTyConName =
  builtinTypeName "Either" (-5)

orderingTy :: CoreType
orderingTy =
  builtinType "Ordering" (-6)

ioTyConName :: RName
ioTyConName =
  builtinTypeName "IO" (-7)

ioTy :: CoreType -> CoreType
ioTy =
  CTyApp (CTyCon ioTyConName)

trueDataConName :: RName
trueDataConName =
  builtinCon "True" (-10)

falseDataConName :: RName
falseDataConName =
  builtinCon "False" (-11)

listNilDataConName :: RName
listNilDataConName =
  builtinCon "[]" (-12)

listConsDataConName :: RName
listConsDataConName =
  builtinCon ":" (-13)

unitDataConName :: RName
unitDataConName =
  tupleDataConName 0

maybeNothingDataConName :: RName
maybeNothingDataConName =
  builtinCon "Nothing" (-15)

maybeJustDataConName :: RName
maybeJustDataConName =
  builtinCon "Just" (-16)

eitherLeftDataConName :: RName
eitherLeftDataConName =
  builtinCon "Left" (-17)

eitherRightDataConName :: RName
eitherRightDataConName =
  builtinCon "Right" (-18)

orderingLTDataConName :: RName
orderingLTDataConName =
  builtinCon "LT" (-19)

orderingEQDataConName :: RName
orderingEQDataConName =
  builtinCon "EQ" (-20)

orderingGTDataConName :: RName
orderingGTDataConName =
  builtinCon "GT" (-21)

tupleDataConName :: Int -> RName
tupleDataConName arity =
  builtinCon tupleOccurrence (-100 - arity)
 where
  tupleOccurrence
    | arity == 0 = "()"
    | otherwise = "(" <> Text.replicate (arity - 1) "," <> ")"

builtinType :: Text -> Int -> CoreType
builtinType occurrence unique =
  CTyCon (builtinTypeName occurrence unique)

builtinTypeName :: Text -> Int -> RName
builtinTypeName occurrence unique =
  RName TypeNamespace occurrence unique True

builtinCon :: Text -> Int -> RName
builtinCon occurrence unique =
  RName ConstructorNamespace occurrence unique True
