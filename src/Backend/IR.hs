module Backend.IR
  ( BackendAtom (..)
  , BackendExpr (..)
  , BackendFunction (..)
  , BackendPrim (..)
  , BackendProgram (..)
  , BackendType (..)
  , backendExprType
  , backendPrimOperandType
  , backendPrimResultType
  )
where

import Data.Text (Text)
import Runtime.Int (HInt)
import Syntax.AST (Name)

data BackendType
  = BI64
  | BI1
  | BClosure BackendType BackendType
  | BEnv [BackendType]
  deriving stock (Show, Eq, Ord)

data BackendAtom
  = BVar Name
  | BInt HInt
  | BBool Bool
  deriving stock (Show, Eq, Ord)

data BackendPrim
  = BPAdd
  | BPSub
  | BPMul
  | BPLt
  | BPEq BackendType
  deriving stock (Show, Eq, Ord)

data BackendExpr
  = BEAtom BackendType BackendAtom
  | BEPrim BackendType BackendPrim BackendAtom BackendAtom
  | BEIf BackendType BackendAtom BackendExpr BackendExpr
  | BECall BackendType Name [BackendAtom]
  | BEMakeClosure BackendType Name [(BackendType, BackendAtom)]
  | BEApply BackendType BackendAtom BackendAtom
  | BEEnvGet BackendType [BackendType] BackendAtom Int
  | BELet BackendType Name BackendExpr BackendExpr
  deriving stock (Show, Eq, Ord)

data BackendFunction = BackendFunction
  { backendFunctionName :: Name
  , backendFunctionParams :: [(Name, BackendType)]
  , backendFunctionReturnType :: BackendType
  , backendFunctionBody :: BackendExpr
  }
  deriving stock (Show, Eq, Ord)

data BackendProgram = BackendProgram
  { backendRootType :: BackendType
  , backendRoot :: BackendExpr
  , backendFunctions :: [BackendFunction]
  , backendProvenance :: [Text]
  }
  deriving stock (Show, Eq, Ord)

backendExprType :: BackendExpr -> BackendType
backendExprType = \case
  BEAtom ty _ ->
    ty
  BEPrim ty _ _ _ ->
    ty
  BEIf ty _ _ _ ->
    ty
  BECall ty _ _ ->
    ty
  BEMakeClosure ty _ _ ->
    ty
  BEApply ty _ _ ->
    ty
  BEEnvGet ty _ _ _ ->
    ty
  BELet ty _ _ _ ->
    ty

backendPrimOperandType :: BackendPrim -> BackendType
backendPrimOperandType = \case
  BPAdd -> BI64
  BPSub -> BI64
  BPMul -> BI64
  BPLt -> BI64
  BPEq ty -> ty

backendPrimResultType :: BackendPrim -> BackendType
backendPrimResultType = \case
  BPAdd -> BI64
  BPSub -> BI64
  BPMul -> BI64
  BPLt -> BI1
  BPEq {} -> BI1
