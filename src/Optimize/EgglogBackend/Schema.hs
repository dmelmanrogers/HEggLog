module Optimize.EgglogBackend.Schema
  ( BackendSymbols (..)
  , backendDecls
  , symbols
  )
where

import Egglog.Function
import Egglog.Sort

data BackendSymbols = BackendSymbols
  { iExprSortName :: SortName
  , bExprSortName :: SortName
  , iExprSort :: Sort
  , bExprSort :: Sort
  , iNumFn :: FunctionName
  , iVarFn :: FunctionName
  , iAddFn :: FunctionName
  , iMulFn :: FunctionName
  , iLtFn :: FunctionName
  , iEqFn :: FunctionName
  , iIfFn :: FunctionName
  , bBoolFn :: FunctionName
  , bVarFn :: FunctionName
  , bEqFn :: FunctionName
  , bIfFn :: FunctionName
  , iConstFn :: FunctionName
  , bConstFn :: FunctionName
  , iZeroFn :: FunctionName
  , iRootFn :: FunctionName
  , bRootFn :: FunctionName
  }
  deriving stock (Show, Eq, Ord)

symbols :: BackendSymbols
symbols =
  BackendSymbols
    { iExprSortName = SortName "IExpr"
    , bExprSortName = SortName "BExpr"
    , iExprSort = SUser (SortName "IExpr")
    , bExprSort = SUser (SortName "BExpr")
    , iNumFn = FunctionName "INum"
    , iVarFn = FunctionName "IVar"
    , iAddFn = FunctionName "IAdd"
    , iMulFn = FunctionName "IMul"
    , iLtFn = FunctionName "ILt"
    , iEqFn = FunctionName "IEq"
    , iIfFn = FunctionName "IIf"
    , bBoolFn = FunctionName "BBool"
    , bVarFn = FunctionName "BVar"
    , bEqFn = FunctionName "BEq"
    , bIfFn = FunctionName "BIf"
    , iConstFn = FunctionName "IConst"
    , bConstFn = FunctionName "BConst"
    , iZeroFn = FunctionName "IZero"
    , iRootFn = FunctionName "__IRoot"
    , bRootFn = FunctionName "__BRoot"
    }

backendDecls :: [FunctionDecl]
backendDecls =
  [ FunctionDecl (iNumFn symbols) [SInt] (iExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iVarFn symbols) [SString] (iExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iAddFn symbols) [iExprSort symbols, iExprSort symbols] (iExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iMulFn symbols) [iExprSort symbols, iExprSort symbols] (iExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iLtFn symbols) [iExprSort symbols, iExprSort symbols] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iEqFn symbols) [iExprSort symbols, iExprSort symbols] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iIfFn symbols) [bExprSort symbols, iExprSort symbols, iExprSort symbols] (iExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (bBoolFn symbols) [SBool] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (bVarFn symbols) [SString] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (bEqFn symbols) [bExprSort symbols, bExprSort symbols] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (bIfFn symbols) [bExprSort symbols, bExprSort symbols, bExprSort symbols] (bExprSort symbols) DefaultFreshId MergeUnion
  , FunctionDecl (iConstFn symbols) [iExprSort symbols] SConstInt DefaultNone MergeConstInt
  , FunctionDecl (bConstFn symbols) [bExprSort symbols] SConstBool DefaultNone MergeConstBool
  , FunctionDecl (iZeroFn symbols) [iExprSort symbols] SZeroInfo DefaultNone MergeZeroInfo
  , FunctionDecl (iRootFn symbols) [] (iExprSort symbols) DefaultNone MergeKeepOld
  , FunctionDecl (bRootFn symbols) [] (bExprSort symbols) DefaultNone MergeKeepOld
  ]
