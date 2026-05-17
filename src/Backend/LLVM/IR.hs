module Backend.LLVM.IR
  ( LLVMBlock (..)
  , LLVMFunction (..)
  , LLVMGlobal (..)
  , LLVMInstruction (..)
  , LLVMModule (..)
  , LLVMOperand (..)
  , LLVMPredicate (..)
  , LLVMTerminator (..)
  , LLVMType (..)
  , Register (..)
  , operandType
  )
where

import Data.Text (Text)

newtype Register = Register {registerName :: Text}
  deriving stock (Show, Eq, Ord)

data LLVMType
  = LI64
  | LI32
  | LI1
  | LI8
  | LPtr
  | LArray Int LLVMType
  | LStruct [LLVMType]
  | LVoid
  deriving stock (Show, Eq, Ord)

data LLVMOperand
  = OLocal LLVMType Register
  | OGlobal LLVMType Text
  | OConstInt LLVMType Integer
  deriving stock (Show, Eq, Ord)

data LLVMPredicate
  = ICmpEq
  | ICmpSlt
  deriving stock (Show, Eq, Ord)

data LLVMInstruction
  = IAdd Register LLVMType LLVMOperand LLVMOperand
  | ISub Register LLVMType LLVMOperand LLVMOperand
  | IMul Register LLVMType LLVMOperand LLVMOperand
  | IIcmp Register LLVMPredicate LLVMType LLVMOperand LLVMOperand
  | IZext Register LLVMOperand LLVMType
  | IGetElementPtr Register LLVMType LLVMOperand [(LLVMType, LLVMOperand)]
  | ICall (Maybe Register) LLVMType Text Bool [(LLVMType, LLVMOperand)]
  | IExtractValue Register LLVMType LLVMOperand Int
  | IPhi Register LLVMType [(LLVMOperand, Text)]
  deriving stock (Show, Eq, Ord)

data LLVMTerminator
  = TRet LLVMType LLVMOperand
  | TBr Text
  | TCondBr LLVMOperand Text Text
  | TUnreachable
  deriving stock (Show, Eq, Ord)

data LLVMBlock = LLVMBlock
  { blockLabel :: Text
  , blockInstructions :: [LLVMInstruction]
  , blockTerminator :: LLVMTerminator
  }
  deriving stock (Show, Eq, Ord)

data LLVMFunction = LLVMFunction
  { functionName :: Text
  , functionReturnType :: LLVMType
  , functionParams :: [(LLVMType, Register)]
  , functionBlocks :: [LLVMBlock]
  }
  deriving stock (Show, Eq, Ord)

data LLVMGlobal = LLVMStringGlobal
  { globalName :: Text
  , globalBytes :: Text
  }
  deriving stock (Show, Eq, Ord)

data LLVMModule = LLVMModule
  { moduleComments :: [Text]
  , moduleGlobals :: [LLVMGlobal]
  , moduleDeclarations :: [Text]
  , moduleFunctions :: [LLVMFunction]
  }
  deriving stock (Show, Eq, Ord)

operandType :: LLVMOperand -> LLVMType
operandType = \case
  OLocal ty _ -> ty
  OGlobal ty _ -> ty
  OConstInt ty _ -> ty
