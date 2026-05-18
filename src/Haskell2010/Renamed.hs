module Haskell2010.Renamed
  ( RAlt (..)
  , RConDecl (..)
  , RDecl (..)
  , RExpr (..)
  , RExport (..)
  , RHsModule (..)
  , RHsType (..)
  , RImportDecl (..)
  , RPat (..)
  , RRhs (..)
  , RStmt (..)
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Haskell2010.Names (RName)
import Haskell2010.Syntax (Fixity, ImportDecl, Literal, ModuleName)

data RHsModule = RHsModule
  { rModuleName :: Maybe ModuleName
  , rModuleExports :: Maybe [RExport]
  , rModuleImports :: [RImportDecl]
  , rModuleFixities :: Map.Map RName Fixity
  , rModuleDecls :: [RDecl]
  }
  deriving stock (Show, Eq, Ord)

data RExport
  = RExportName RName
  | RExportThing RName [Text]
  | RExportModule ModuleName
  deriving stock (Show, Eq, Ord)

newtype RImportDecl = RImportDecl ImportDecl
  deriving stock (Show, Eq, Ord)

data RDecl
  = RTypeSignature [RName] RHsType
  | RFunctionBinding RName [RPat] RRhs [RDecl]
  | RPatternBinding RPat RRhs [RDecl]
  | RFixityDecl Fixity [RName]
  | RDataDecl RName [RName] [RConDecl] [RName]
  | RNewtypeDecl RName [RName] RConDecl [RName]
  | RTypeSynonym RName [RName] RHsType
  | RClassDecl [RHsType] RName RName [RDecl]
  | RInstanceDecl [RHsType] RHsType [RDecl]
  | RDefaultDecl [RHsType]
  | RForeignDecl Text
  deriving stock (Show, Eq, Ord)

data RConDecl = RConDecl RName [RHsType]
  deriving stock (Show, Eq, Ord)

data RRhs
  = RUnguarded RExpr
  | RGuarded [(RExpr, RExpr)]
  deriving stock (Show, Eq, Ord)

data RExpr
  = RVar RName
  | RCon RName
  | RLit Literal
  | RApp RExpr RExpr
  | RInfixApp RExpr RName RExpr
  | RLambda [RPat] RExpr
  | RLet [RDecl] RExpr
  | RIf RExpr RExpr RExpr
  | RCase RExpr [RAlt]
  | RDo [RStmt]
  | RList [RExpr]
  | RTuple [RExpr]
  | RUnit
  | RParen RExpr
  | RLeftSection RExpr RName
  | RRightSection RName RExpr
  | RArithmeticSeq RExpr (Maybe RExpr) (Maybe RExpr)
  | RListComp RExpr [RStmt]
  | RExprTypeSig RExpr RHsType
  deriving stock (Show, Eq, Ord)

data RStmt
  = RBindStmt RPat RExpr
  | RLetStmt [RDecl]
  | RExprStmt RExpr
  deriving stock (Show, Eq, Ord)

data RAlt = RAlt RPat RRhs [RDecl]
  deriving stock (Show, Eq, Ord)

data RPat
  = RPVar RName
  | RPCon RName [RPat]
  | RPLit Literal
  | RPWildcard
  | RPTuple [RPat]
  | RPList [RPat]
  | RPAs RName RPat
  | RPIrrefutable RPat
  | RPParen RPat
  deriving stock (Show, Eq, Ord)

data RHsType
  = RTyVar RName
  | RTyCon RName
  | RTyApp RHsType RHsType
  | RTyFun RHsType RHsType
  | RTyContext [RHsType] RHsType
  | RTyTuple [RHsType]
  | RTyList RHsType
  | RTyParen RHsType
  deriving stock (Show, Eq, Ord)
