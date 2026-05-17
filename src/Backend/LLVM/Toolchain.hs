module Backend.LLVM.Toolchain
  ( LLVMRunResult (..)
  , LLVMTools (..)
  , findLLVMTools
  , renderLLVMTools
  , runLLVMText
  )
where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import System.Directory (createDirectoryIfMissing, findExecutable)
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

data LLVMTools = LLVMTools
  { llvmLli :: Maybe FilePath
  , llvmAs :: Maybe FilePath
  , llvmClang :: Maybe FilePath
  }
  deriving stock (Show, Eq, Ord)

data LLVMRunResult
  = LLVMRunSkipped String
  | LLVMRunFailed String String
  | LLVMRunSucceeded String
  deriving stock (Show, Eq, Ord)

findLLVMTools :: IO LLVMTools
findLLVMTools =
  LLVMTools
    <$> findExecutable "lli"
    <*> findExecutable "llvm-as"
    <*> findExecutable "clang"

renderLLVMTools :: LLVMTools -> String
renderLLVMTools tools =
  "lli="
    <> renderTool (llvmLli tools)
    <> ", llvm-as="
    <> renderTool (llvmAs tools)
    <> ", clang="
    <> renderTool (llvmClang tools)
 where
  renderTool = \case
    Just path -> path
    Nothing -> "unavailable"

runLLVMText :: LLVMTools -> Text.Text -> IO LLVMRunResult
runLLVMText tools llvmText =
  case llvmLli tools of
    Just lli ->
      runWithLli lli llvmText
    Nothing ->
      case llvmClang tools of
        Just clang ->
          runWithClang clang llvmText
        Nothing ->
          pure (LLVMRunSkipped ("LLVM execution tools unavailable: " <> renderLLVMTools tools))

runWithLli :: FilePath -> Text.Text -> IO LLVMRunResult
runWithLli lli llvmText = do
  path <- writeLLVMText llvmText
  (code, stdoutText, stderrText) <- readProcessWithExitCode lli [path] ""
  pure (processResult code stdoutText stderrText)

runWithClang :: FilePath -> Text.Text -> IO LLVMRunResult
runWithClang clang llvmText = do
  path <- writeLLVMText llvmText
  let exePath = ".context/llvm/latest"
  (compileCode, compileOut, compileErr) <- readProcessWithExitCode clang [path, "-o", exePath] ""
  case compileCode of
    ExitFailure {} ->
      pure (LLVMRunFailed compileOut compileErr)
    ExitSuccess -> do
      (runCode, runOut, runErr) <- readProcessWithExitCode exePath [] ""
      pure (processResult runCode runOut runErr)

writeLLVMText :: Text.Text -> IO FilePath
writeLLVMText llvmText = do
  createDirectoryIfMissing True ".context/llvm"
  let path = ".context/llvm/latest.ll"
  Text.IO.writeFile path llvmText
  pure path

processResult :: ExitCode -> String -> String -> LLVMRunResult
processResult = \case
  ExitSuccess ->
    \stdoutText _ -> LLVMRunSucceeded stdoutText
  ExitFailure {} ->
    \stdoutText stderrText -> LLVMRunFailed stdoutText stderrText
