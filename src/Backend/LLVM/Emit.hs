module Backend.LLVM.Emit
  ( emitLLVMModule
  )
where

import Data.Char (ord)
import Data.Text (Text)
import qualified Data.Text as Text
import Backend.LLVM.IR

emitLLVMModule :: LLVMModule -> Text
emitLLVMModule llvmModule =
  Text.intercalate
    "\n"
    ( filter
        (not . Text.null)
        [ emitComments (moduleComments llvmModule)
        , emitGlobals (moduleGlobals llvmModule)
        , emitDeclarations (moduleDeclarations llvmModule)
        , emitFunctions (moduleFunctions llvmModule)
        ]
    )
    <> "\n"

emitComments :: [Text] -> Text
emitComments comments =
  Text.unlines ["; " <> comment | comment <- comments]

emitGlobals :: [LLVMGlobal] -> Text
emitGlobals =
  Text.intercalate "\n" . map emitGlobal

emitGlobal :: LLVMGlobal -> Text
emitGlobal (LLVMStringGlobal name bytes) =
  "@"
    <> name
    <> " = private unnamed_addr constant ["
    <> Text.pack (show (Text.length bytes))
    <> " x i8] c\""
    <> escapeCString bytes
    <> "\""

emitDeclarations :: [Text] -> Text
emitDeclarations =
  Text.intercalate "\n"

emitFunctions :: [LLVMFunction] -> Text
emitFunctions =
  Text.intercalate "\n\n" . map emitFunction

emitFunction :: LLVMFunction -> Text
emitFunction function =
  "define "
    <> emitType (functionReturnType function)
    <> " @"
    <> functionName function
    <> "("
    <> Text.intercalate ", " [emitType ty <> " %" <> registerName reg | (ty, reg) <- functionParams function]
    <> ") {\n"
    <> Text.concat (map emitBlock (functionBlocks function))
    <> "}"

emitBlock :: LLVMBlock -> Text
emitBlock block =
  blockLabel block
    <> ":\n"
    <> Text.concat [emitInstruction instruction <> "\n" | instruction <- blockInstructions block]
    <> emitTerminator (blockTerminator block)
    <> "\n"

emitInstruction :: LLVMInstruction -> Text
emitInstruction = \case
  IAdd reg ty lhs rhs ->
    assign reg ("add " <> emitTypedOperands ty lhs rhs)
  ISub reg ty lhs rhs ->
    assign reg ("sub " <> emitTypedOperands ty lhs rhs)
  IMul reg ty lhs rhs ->
    assign reg ("mul " <> emitTypedOperands ty lhs rhs)
  IDiv reg ty lhs rhs ->
    assign reg ("sdiv " <> emitTypedOperands ty lhs rhs)
  IIcmp reg predicate ty lhs rhs ->
    assign reg ("icmp " <> emitPredicate predicate <> " " <> emitTypedOperands ty lhs rhs)
  IZext reg value targetType ->
    assign reg ("zext " <> emitType (operandType value) <> " " <> emitOperand value <> " to " <> emitType targetType)
  ISext reg value targetType ->
    assign reg ("sext " <> emitType (operandType value) <> " " <> emitOperand value <> " to " <> emitType targetType)
  ITrunc reg value targetType ->
    assign reg ("trunc " <> emitType (operandType value) <> " " <> emitOperand value <> " to " <> emitType targetType)
  IGetElementPtr reg elementType base indices ->
    assign reg $
      "getelementptr inbounds "
        <> emitType elementType
        <> ", "
        <> emitType (operandType base)
        <> " "
        <> emitOperand base
        <> Text.concat [", " <> emitType ty <> " " <> emitOperand operand | (ty, operand) <- indices]
  ILoad reg ty pointer ->
    assign reg ("load " <> emitType ty <> ", ptr " <> emitOperand pointer)
  IStore ty value pointer ->
    "  store " <> emitType ty <> " " <> emitOperand value <> ", ptr " <> emitOperand pointer
  ICall maybeReg returnType callee varArg args ->
    case maybeReg of
      Just reg -> assign reg (emitCall returnType callee varArg args)
      Nothing -> "  " <> emitCall returnType callee varArg args
  IExtractValue reg _ aggregate index ->
    assign reg $
      "extractvalue "
        <> emitType (operandType aggregate)
        <> " "
        <> emitOperand aggregate
        <> ", "
        <> Text.pack (show index)
  IPhi reg ty incoming ->
    assign reg $
      "phi "
        <> emitType ty
        <> " "
        <> Text.intercalate
          ", "
          [ "[ " <> emitOperand operand <> ", %" <> label <> " ]"
          | (operand, label) <- incoming
          ]

emitCall :: LLVMType -> LLVMCallTarget -> Bool -> [(LLVMType, LLVMOperand)] -> Text
emitCall returnType callee varArg args =
  "call "
    <> emitCallType returnType varArg args
    <> " "
    <> emitCallTarget callee
    <> "("
    <> Text.intercalate ", " [emitType ty <> " " <> emitOperand operand | (ty, operand) <- args]
    <> ")"

emitCallTarget :: LLVMCallTarget -> Text
emitCallTarget = \case
  DirectCall name ->
    "@" <> name
  IndirectCall operand ->
    emitOperand operand

emitCallType :: LLVMType -> Bool -> [(LLVMType, LLVMOperand)] -> Text
emitCallType returnType varArg args
  | varArg =
      emitType returnType
        <> " ("
        <> Text.intercalate ", " (map (emitType . fst) fixedArgs)
        <> ", ...)"
  | otherwise =
      emitType returnType
 where
  fixedArgs =
    take 1 args

emitTypedOperands :: LLVMType -> LLVMOperand -> LLVMOperand -> Text
emitTypedOperands ty lhs rhs =
  emitType ty <> " " <> emitOperand lhs <> ", " <> emitOperand rhs

emitTerminator :: LLVMTerminator -> Text
emitTerminator = \case
  TRet ty operand ->
    "  ret " <> emitType ty <> " " <> emitOperand operand
  TRetVoid ->
    "  ret void"
  TBr label ->
    "  br label %" <> label
  TCondBr cond thenLabel elseLabel ->
    "  br i1 "
      <> emitOperand cond
      <> ", label %"
      <> thenLabel
      <> ", label %"
      <> elseLabel
  TUnreachable ->
    "  unreachable"

assign :: Register -> Text -> Text
assign reg rhs =
  "  %" <> registerName reg <> " = " <> rhs

emitOperand :: LLVMOperand -> Text
emitOperand = \case
  OLocal _ reg ->
    "%" <> registerName reg
  OGlobal _ name ->
    "@" <> name
  OConstInt LI1 0 ->
    "false"
  OConstInt LI1 1 ->
    "true"
  OConstInt _ n ->
    Text.pack (show n)
  OConstNull ->
    "null"

emitType :: LLVMType -> Text
emitType = \case
  LI64 -> "i64"
  LI32 -> "i32"
  LI16 -> "i16"
  LI1 -> "i1"
  LI8 -> "i8"
  LFloat -> "float"
  LDouble -> "double"
  LPtr -> "ptr"
  LArray count ty -> "[" <> Text.pack (show count) <> " x " <> emitType ty <> "]"
  LStruct fields -> "{ " <> Text.intercalate ", " (map emitType fields) <> " }"
  LVoid -> "void"

emitPredicate :: LLVMPredicate -> Text
emitPredicate = \case
  ICmpEq -> "eq"
  ICmpSlt -> "slt"

escapeCString :: Text -> Text
escapeCString =
  Text.concatMap escapeChar
 where
  escapeChar char =
    case char of
      '\n' -> "\\0A"
      '\0' -> "\\00"
      '"' -> "\\22"
      '\\' -> "\\5C"
      _ | ord char >= 32 && ord char <= 126 -> Text.singleton char
      _ -> "\\" <> hex2 (ord char)

hex2 :: Int -> Text
hex2 value =
  let digits = "0123456789ABCDEF" :: String
      hi = value `div` 16
      lo = value `mod` 16
   in Text.pack [digits !! hi, digits !! lo]
