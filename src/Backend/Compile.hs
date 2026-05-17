module Backend.Compile
  ( CompileLLVMError (..)
  , CompileLLVMOptions (..)
  , LLVMCompileResult (..)
  , LLVMOptimizationStatus (..)
  , compileToLLVM
  , defaultCompileLLVMOptions
  , renderCompileLLVMError
  , renderLLVMOptimizationStatus
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Backend.IR
import Backend.LLVM.Emit
import Backend.LLVM.IR
import Backend.LLVM.Lower
import Backend.Lower
import IR.ANF
import IR.ANF.Validate
import Optimize.EgglogBackend
import qualified Egglog.Eval as Egglog
import Syntax.AST (Expr, Type)
import Syntax.Parser (parseProgram)
import Syntax.Pretty (prettyType, renderDoc)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (infer)
import Typecheck.Types (TypeError, renderTypeError)

data CompileLLVMOptions = CompileLLVMOptions
  { compileUseEgglog :: Bool
  }
  deriving stock (Show, Eq, Ord)

defaultCompileLLVMOptions :: CompileLLVMOptions
defaultCompileLLVMOptions =
  CompileLLVMOptions
    { compileUseEgglog = True
    }

data LLVMOptimizationStatus
  = LLVMOptimizationDisabled
  | LLVMOptimizationApplied EgglogOptimizationResult
  | LLVMOptimizationUnsupported EgglogBackendError
  deriving stock (Show, Eq)

data LLVMCompileResult = LLVMCompileResult
  { llvmParsed :: Expr
  , llvmSourceType :: Type
  , llvmOriginalANF :: AExpr
  , llvmSelectedANF :: AExpr
  , llvmOptimizationStatus :: LLVMOptimizationStatus
  , llvmBackendProgram :: BackendProgram
  , llvmModule :: LLVMModule
  , llvmText :: Text
  }
  deriving stock (Show, Eq)

data CompileLLVMError
  = LLVMCompileParseError Text
  | LLVMCompileTypeError TypeError
  | LLVMCompileInvalidANF ANFValidationError
  | LLVMCompileEgglogFailed EgglogBackendError
  | LLVMCompileBackendLowerError BackendLowerError
  | LLVMCompileLowerError LLVMLowerError
  deriving stock (Show, Eq)

compileToLLVM :: CompileLLVMOptions -> FilePath -> Text -> Either CompileLLVMError LLVMCompileResult
compileToLLVM options path source = do
  parsed <-
    case parseProgram path source of
      Left parseError -> Left (LLVMCompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  inferredType <- mapLeft LLVMCompileTypeError (infer parsed)
  let anf = toANF parsed
  mapLeft LLVMCompileInvalidANF (validateANF anf)
  (selectedANF, optimizationStatus) <- selectANF options anf
  mapLeft LLVMCompileInvalidANF (validateANF selectedANF)
  backend <- mapLeft LLVMCompileBackendLowerError (lowerANFToBackend selectedANF)
  llvmModule0 <- mapLeft LLVMCompileLowerError (lowerBackendToLLVM backend)
  let llvmModule1 =
        llvmModule0
          { moduleComments =
              moduleComments llvmModule0
                <> [ "source type: " <> renderDoc (prettyType inferredType)
                   , renderLLVMOptimizationStatus optimizationStatus
                   ]
          }
      emitted = emitLLVMModule llvmModule1
  pure
    LLVMCompileResult
      { llvmParsed = parsed
      , llvmSourceType = inferredType
      , llvmOriginalANF = anf
      , llvmSelectedANF = selectedANF
      , llvmOptimizationStatus = optimizationStatus
      , llvmBackendProgram = backend
      , llvmModule = llvmModule1
      , llvmText = emitted
      }

selectANF :: CompileLLVMOptions -> AExpr -> Either CompileLLVMError (AExpr, LLVMOptimizationStatus)
selectANF options anf
  | not (compileUseEgglog options) =
      Right (anf, LLVMOptimizationDisabled)
  | otherwise =
      case tryOptimizeWithEgglog Egglog.defaultRunConfig anf of
        EgglogOptimized result ->
          Right (optimizedANF result, LLVMOptimizationApplied result)
        EgglogUnsupported err ->
          Right (anf, LLVMOptimizationUnsupported err)
        EgglogFailed err ->
          Left (LLVMCompileEgglogFailed err)

renderCompileLLVMError :: CompileLLVMError -> Text
renderCompileLLVMError = \case
  LLVMCompileParseError parseError ->
    "parse error:\n" <> parseError
  LLVMCompileTypeError typeError ->
    "type error: " <> renderTypeError typeError
  LLVMCompileInvalidANF err ->
    "invalid ANF before LLVM compilation: " <> renderANFValidationError err
  LLVMCompileEgglogFailed err ->
    "Egglog optimization failed before LLVM compilation: " <> renderEgglogBackendError err
  LLVMCompileBackendLowerError err ->
    renderBackendLowerError err
  LLVMCompileLowerError err ->
    renderLLVMLowerError err

renderLLVMOptimizationStatus :: LLVMOptimizationStatus -> Text
renderLLVMOptimizationStatus = \case
  LLVMOptimizationDisabled ->
    "egglog: disabled"
  LLVMOptimizationApplied result ->
    "egglog: optimized; cost " <> Text.pack (show (originalCost (extractionStats result))) <> " -> " <> Text.pack (show (optimizedCost (extractionStats result)))
  LLVMOptimizationUnsupported err ->
    "egglog: unsupported; using unoptimized ANF; reason: " <> renderEgglogBackendError err

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
