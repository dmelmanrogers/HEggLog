module Backend.LLVM.Validate
  ( LLVMValidationError (..)
  , renderLLVMValidationError
  , validateLLVMModule
  )
where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Backend.LLVM.IR

data LLVMValidationError
  = DuplicateLLVMFunction Text
  | DuplicateLLVMBlock Text Text
  | DuplicateLLVMRegister Text Register
  | UnknownLLVMBlock Text Text
  | UnknownLLVMRegister Text Register
  | LLVMOperandTypeMismatch LLVMType LLVMType LLVMOperand
  | LLVMConditionTypeMismatch LLVMType
  | LLVMPhiHasNoIncoming Register
  | LLVMPhiIncomingBlockMissing Register Text
  | LLVMReturnTypeMismatch Text LLVMType LLVMType
  deriving stock (Show, Eq, Ord)

validateLLVMModule :: LLVMModule -> Either LLVMValidationError ()
validateLLVMModule llvmModule = do
  checkUniqueFunctions (moduleFunctions llvmModule)
  mapM_ validateFunction (moduleFunctions llvmModule)

checkUniqueFunctions :: [LLVMFunction] -> Either LLVMValidationError ()
checkUniqueFunctions functions =
  go Set.empty functions
 where
  go _ [] =
    Right ()
  go seen (function : rest)
    | functionName function `Set.member` seen = Left (DuplicateLLVMFunction (functionName function))
    | otherwise = go (Set.insert (functionName function) seen) rest

validateFunction :: LLVMFunction -> Either LLVMValidationError ()
validateFunction function = do
  checkUniqueBlocks (functionName function) (functionBlocks function)
  checkRegisters (functionName function) (functionBlocks function)
  let labels = Set.fromList (map blockLabel (functionBlocks function))
      registers = registerTypes (functionBlocks function)
  mapM_ (validateBlock function labels registers) (functionBlocks function)

checkUniqueBlocks :: Text -> [LLVMBlock] -> Either LLVMValidationError ()
checkUniqueBlocks function blocks =
  go Set.empty blocks
 where
  go _ [] =
    Right ()
  go seen (block : rest)
    | blockLabel block `Set.member` seen = Left (DuplicateLLVMBlock function (blockLabel block))
    | otherwise = go (Set.insert (blockLabel block) seen) rest

checkRegisters :: Text -> [LLVMBlock] -> Either LLVMValidationError ()
checkRegisters function blocks =
  go Set.empty [reg | block <- blocks, instruction <- blockInstructions block, reg <- maybeToList (instructionResult instruction)]
 where
  go _ [] =
    Right ()
  go seen (reg : rest)
    | reg `Set.member` seen = Left (DuplicateLLVMRegister function reg)
    | otherwise = go (Set.insert reg seen) rest

validateBlock :: LLVMFunction -> Set.Set Text -> Map.Map Register LLVMType -> LLVMBlock -> Either LLVMValidationError ()
validateBlock function labels registers block = do
  mapM_ (validateInstruction (functionName function) labels registers) (blockInstructions block)
  validateTerminator function labels registers (blockTerminator block)

validateInstruction :: Text -> Set.Set Text -> Map.Map Register LLVMType -> LLVMInstruction -> Either LLVMValidationError ()
validateInstruction function labels registers = \case
  IAdd _ ty lhs rhs -> validateBinary function registers ty lhs rhs
  ISub _ ty lhs rhs -> validateBinary function registers ty lhs rhs
  IMul _ ty lhs rhs -> validateBinary function registers ty lhs rhs
  IIcmp _ _ ty lhs rhs -> validateBinary function registers ty lhs rhs
  IZext _ value _ -> validateOperand function registers value
  IGetElementPtr _ _ base indices -> do
    assertOperandType function registers LPtr base
    mapM_ (validateOperand function registers . snd) indices
  ICall _ _ _ _ args ->
    mapM_ (validateOperand function registers . snd) args
  IPhi reg ty incoming -> do
    if null incoming
      then Left (LLVMPhiHasNoIncoming reg)
      else Right ()
    mapM_ (validateIncoming reg ty) incoming
 where
  validateIncoming reg ty (operand, label) = do
    if label `Set.member` labels
      then Right ()
      else Left (LLVMPhiIncomingBlockMissing reg label)
    assertOperandType function registers ty operand

validateTerminator :: LLVMFunction -> Set.Set Text -> Map.Map Register LLVMType -> LLVMTerminator -> Either LLVMValidationError ()
validateTerminator function labels registers = \case
  TRet ty operand -> do
    if ty == functionReturnType function
      then Right ()
      else Left (LLVMReturnTypeMismatch (functionName function) (functionReturnType function) ty)
    assertOperandType (functionName function) registers ty operand
  TBr label ->
    assertBlock (functionName function) labels label
  TCondBr cond thenLabel elseLabel -> do
    assertOperandType (functionName function) registers LI1 cond
    assertBlock (functionName function) labels thenLabel
    assertBlock (functionName function) labels elseLabel

validateBinary :: Text -> Map.Map Register LLVMType -> LLVMType -> LLVMOperand -> LLVMOperand -> Either LLVMValidationError ()
validateBinary function registers ty lhs rhs = do
  assertOperandType function registers ty lhs
  assertOperandType function registers ty rhs

assertBlock :: Text -> Set.Set Text -> Text -> Either LLVMValidationError ()
assertBlock function labels label
  | label `Set.member` labels = Right ()
  | otherwise = Left (UnknownLLVMBlock function label)

assertOperandType :: Text -> Map.Map Register LLVMType -> LLVMType -> LLVMOperand -> Either LLVMValidationError ()
assertOperandType function registers expected operand = do
  validateOperand function registers operand
  let actual = operandType operand
  if actual == expected
    then Right ()
    else Left (LLVMOperandTypeMismatch expected actual operand)

validateOperand :: Text -> Map.Map Register LLVMType -> LLVMOperand -> Either LLVMValidationError ()
validateOperand function registers = \case
  OLocal ty reg ->
    case Map.lookup reg registers of
      Just actual
        | actual == ty -> Right ()
        | otherwise -> Left (LLVMOperandTypeMismatch ty actual (OLocal ty reg))
      Nothing -> Left (UnknownLLVMRegister function reg)
  OGlobal {} ->
    Right ()
  OConstInt {} ->
    Right ()

registerTypes :: [LLVMBlock] -> Map.Map Register LLVMType
registerTypes blocks =
  Map.fromList
    [ (reg, instructionResultType instruction)
    | block <- blocks
    , instruction <- blockInstructions block
    , reg <- maybeToList (instructionResult instruction)
    ]

instructionResult :: LLVMInstruction -> Maybe Register
instructionResult = \case
  IAdd reg _ _ _ -> Just reg
  ISub reg _ _ _ -> Just reg
  IMul reg _ _ _ -> Just reg
  IIcmp reg _ _ _ _ -> Just reg
  IZext reg _ _ -> Just reg
  IGetElementPtr reg _ _ _ -> Just reg
  ICall maybeReg _ _ _ _ -> maybeReg
  IPhi reg _ _ -> Just reg

instructionResultType :: LLVMInstruction -> LLVMType
instructionResultType = \case
  IAdd _ ty _ _ -> ty
  ISub _ ty _ _ -> ty
  IMul _ ty _ _ -> ty
  IIcmp {} -> LI1
  IZext _ _ ty -> ty
  IGetElementPtr {} -> LPtr
  ICall _ ty _ _ _ -> ty
  IPhi _ ty _ -> ty

renderLLVMValidationError :: LLVMValidationError -> Text
renderLLVMValidationError = \case
  DuplicateLLVMFunction name ->
    "duplicate LLVM function @" <> name
  DuplicateLLVMBlock function label ->
    "duplicate LLVM block %" <> label <> " in @" <> function
  DuplicateLLVMRegister function reg ->
    "duplicate LLVM register %" <> registerName reg <> " in @" <> function
  UnknownLLVMBlock function label ->
    "unknown LLVM block %" <> label <> " in @" <> function
  UnknownLLVMRegister function reg ->
    "unknown LLVM register %" <> registerName reg <> " in @" <> function
  LLVMOperandTypeMismatch expected actual operand ->
    "LLVM operand type mismatch for " <> Text.pack (show operand) <> ": expected " <> renderLLVMType expected <> ", got " <> renderLLVMType actual
  LLVMConditionTypeMismatch actual ->
    "LLVM branch condition must be i1, got " <> renderLLVMType actual
  LLVMPhiHasNoIncoming reg ->
    "LLVM phi %" <> registerName reg <> " has no incoming edges"
  LLVMPhiIncomingBlockMissing reg label ->
    "LLVM phi %" <> registerName reg <> " references missing block %" <> label
  LLVMReturnTypeMismatch function expected actual ->
    "LLVM return type mismatch in @" <> function <> ": expected " <> renderLLVMType expected <> ", got " <> renderLLVMType actual

renderLLVMType :: LLVMType -> Text
renderLLVMType = \case
  LI64 -> "i64"
  LI32 -> "i32"
  LI1 -> "i1"
  LI8 -> "i8"
  LPtr -> "ptr"
  LArray count ty -> "[" <> Text.pack (show count) <> " x " <> renderLLVMType ty <> "]"
  LVoid -> "void"

maybeToList :: Maybe a -> [a]
maybeToList = \case
  Just value -> [value]
  Nothing -> []
