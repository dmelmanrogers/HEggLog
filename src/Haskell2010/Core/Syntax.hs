module Haskell2010.Core.Syntax
  ( CoreAlt (..)
  , CoreAltCon (..)
  , CoreBind (..)
  , CoreBinder (..)
  , CoreConstructorInfo (..)
  , CoreConstructorRepresentation (..)
  , CoreExpr (..)
  , CoreForeignExport (..)
  , CoreForeignImport (..)
  , CoreModule (..)
  , CorePrimOp (..)
  , CoreType (..)
  , boolTy
  , charTy
  , eitherLeftDataConName
  , eitherRightDataConName
  , eitherTyConName
  , falseDataConName
  , foreignPtrTy
  , foreignPtrTyConName
  , funTy
  , funPtrTy
  , funPtrTyConName
  , handleTy
  , handleTyConName
  , intTy
  , ioErrorAlreadyExistsTypeDataConName
  , ioErrorAlreadyInUseTypeDataConName
  , ioErrorDataConName
  , ioErrorDoesNotExistTypeDataConName
  , ioErrorEOFTypeDataConName
  , ioErrorFullTypeDataConName
  , ioErrorIllegalOperationTypeDataConName
  , ioErrorPermissionTypeDataConName
  , ioErrorTy
  , ioErrorTyConName
  , ioErrorTypeTy
  , ioErrorTypeTyConName
  , ioErrorUserTypeDataConName
  , ioTy
  , ioTyConName
  , listTyConName
  , listConsDataConName
  , listNilDataConName
  , maybeJustDataConName
  , maybeNothingDataConName
  , maybeTyConName
  , orderingEQDataConName
  , orderingGTDataConName
  , orderingLTDataConName
  , orderingTy
  , ptrTy
  , ptrTyConName
  , stablePtrTy
  , stablePtrTyConName
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
import Haskell2010.Syntax (ForeignCallConv, ForeignExportEntity, ForeignImportEntity, ForeignSafety, Literal, ModuleName)

data CoreModule = CoreModule
  { coreModuleName :: Maybe ModuleName
  , coreModuleConstructors :: Map.Map RName CoreConstructorInfo
  , coreModuleBinds :: [CoreBind]
  , coreModuleForeignExports :: [CoreForeignExport]
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

data CoreForeignImport = CoreForeignImport
  { coreForeignImportCallConv :: ForeignCallConv
  , coreForeignImportSafety :: ForeignSafety
  , coreForeignImportEntity :: ForeignImportEntity
  , coreForeignImportName :: RName
  , coreForeignImportType :: CoreType
  }
  deriving stock (Show, Eq, Ord)

data CoreForeignExport = CoreForeignExport
  { coreForeignExportCallConv :: ForeignCallConv
  , coreForeignExportEntity :: ForeignExportEntity
  , coreForeignExportName :: RName
  , coreForeignExportType :: CoreType
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
  | CCoerce CoreExpr CoreType
  | CPrimOp CorePrimOp [CoreExpr] CoreType
  | CForeignCall CoreForeignImport [CoreExpr] CoreType
  | CForeignImportValue CoreForeignImport CoreType
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
  | PrimRem
  | PrimEq
  | PrimLt
  | PrimNegate
  | PrimCharToInt
  | PrimIntToChar
  | PrimShowInt
  | PrimShowBool
  | PrimPutStrLn
  | PrimGetLine
  | PrimIOThen
  | PrimIOBind
  | PrimIOReturn
  | PrimIOFail
  | PrimIOError
  | PrimIOCatch
  | PrimIOTry
  | PrimNullPtr
  | PrimCastPtr
  | PrimIsNullPtr
  | PrimNewStablePtr
  | PrimDeRefStablePtr
  | PrimFreeStablePtr
  | PrimCastStablePtrToPtr
  | PrimCastPtrToStablePtr
  | PrimNewForeignPtr
  | PrimNewForeignPtr_
  | PrimAddForeignPtrFinalizer
  | PrimFinalizeForeignPtr
  | PrimWithForeignPtr
  | PrimTouchForeignPtr
  | PrimUnsafeForeignPtrToPtr
  | PrimCastForeignPtr
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
  CForeignCall _ _ ty -> ty
  CForeignImportValue _ ty -> ty

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

ioErrorTyConName :: RName
ioErrorTyConName =
  builtinTypeName "IOError" (-22)

ioErrorTy :: CoreType
ioErrorTy =
  CTyCon ioErrorTyConName

ioErrorTypeTyConName :: RName
ioErrorTypeTyConName =
  builtinTypeName "IOErrorType" (-23)

ioErrorTypeTy :: CoreType
ioErrorTypeTy =
  CTyCon ioErrorTypeTyConName

handleTyConName :: RName
handleTyConName =
  builtinTypeName "Handle" (-24)

handleTy :: CoreType
handleTy =
  CTyCon handleTyConName

listTyConName :: RName
listTyConName =
  builtinTypeName "[]" (-8)

ptrTyConName :: RName
ptrTyConName =
  builtinTypeName "Ptr" (-30)

ptrTy :: CoreType -> CoreType
ptrTy =
  CTyApp (CTyCon ptrTyConName)

funPtrTyConName :: RName
funPtrTyConName =
  builtinTypeName "FunPtr" (-31)

funPtrTy :: CoreType -> CoreType
funPtrTy =
  CTyApp (CTyCon funPtrTyConName)

stablePtrTyConName :: RName
stablePtrTyConName =
  builtinTypeName "StablePtr" (-32)

stablePtrTy :: CoreType -> CoreType
stablePtrTy =
  CTyApp (CTyCon stablePtrTyConName)

foreignPtrTyConName :: RName
foreignPtrTyConName =
  builtinTypeName "ForeignPtr" (-33)

foreignPtrTy :: CoreType -> CoreType
foreignPtrTy =
  CTyApp (CTyCon foreignPtrTyConName)

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

ioErrorDataConName :: RName
ioErrorDataConName =
  builtinCon "$IOError" (-40)

ioErrorAlreadyExistsTypeDataConName :: RName
ioErrorAlreadyExistsTypeDataConName =
  builtinCon "$AlreadyExistsErrorType" (-41)

ioErrorDoesNotExistTypeDataConName :: RName
ioErrorDoesNotExistTypeDataConName =
  builtinCon "$DoesNotExistErrorType" (-42)

ioErrorAlreadyInUseTypeDataConName :: RName
ioErrorAlreadyInUseTypeDataConName =
  builtinCon "$AlreadyInUseErrorType" (-43)

ioErrorFullTypeDataConName :: RName
ioErrorFullTypeDataConName =
  builtinCon "$FullErrorType" (-44)

ioErrorEOFTypeDataConName :: RName
ioErrorEOFTypeDataConName =
  builtinCon "$EOFErrorType" (-45)

ioErrorIllegalOperationTypeDataConName :: RName
ioErrorIllegalOperationTypeDataConName =
  builtinCon "$IllegalOperationErrorType" (-46)

ioErrorPermissionTypeDataConName :: RName
ioErrorPermissionTypeDataConName =
  builtinCon "$PermissionErrorType" (-47)

ioErrorUserTypeDataConName :: RName
ioErrorUserTypeDataConName =
  builtinCon "$UserErrorType" (-48)

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
