module Backend.LLVM.Toolchain
  ( LLVMAssemblyResult (..)
  , LLVMRunResult (..)
  , LLVMTools (..)
  , NativeBuildResult (..)
  , NativeRunResult (..)
  , buildNativeExecutable
  , buildNativeExecutableWithObjects
  , findLLVMTools
  , runNativeExecutable
  , runNativeExecutableWithInput
  , renderLLVMTools
  , runLLVMText
  , validateLLVMText
  )
where

import Control.Exception (IOException, bracket, catch, try)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import System.Directory (createDirectoryIfMissing, findExecutable, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (..))
import System.IO (hClose, openTempFile)
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

data LLVMAssemblyResult
  = LLVMAssemblySkipped String
  | LLVMAssemblyFailed String String
  | LLVMAssemblySucceeded
  deriving stock (Show, Eq, Ord)

data NativeBuildResult
  = NativeBuildSucceeded
  | NativeBuildToolchainMissing String
  | NativeBuildFailed FilePath [String] ExitCode String String
  | NativeBuildIOError String
  deriving stock (Show, Eq, Ord)

data NativeRunResult
  = NativeRunSucceeded String
  | NativeRunFailed ExitCode String String
  | NativeRunIOError String
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

validateLLVMText :: LLVMTools -> Text.Text -> IO LLVMAssemblyResult
validateLLVMText tools llvmText =
  case llvmAs tools of
    Just llvmAsPath ->
      runWithLlvmAs llvmAsPath llvmText
    Nothing ->
      pure (LLVMAssemblySkipped ("llvm-as unavailable: " <> renderLLVMTools tools))

buildNativeExecutable :: LLVMTools -> Text.Text -> FilePath -> IO NativeBuildResult
buildNativeExecutable tools llvmText outputPath =
  buildNativeExecutableWithObjects tools llvmText [] outputPath

buildNativeExecutableWithObjects :: LLVMTools -> Text.Text -> [FilePath] -> FilePath -> IO NativeBuildResult
buildNativeExecutableWithObjects tools llvmText extraInputs outputPath =
  case llvmClang tools of
    Nothing ->
      pure (NativeBuildToolchainMissing ("clang unavailable: " <> renderLLVMTools tools))
    Just clangPath -> do
      result <- try (withTempLLVMFile llvmText (runClang clangPath)) :: IO (Either IOException NativeBuildResult)
      pure $
        case result of
          Right value -> value
          Left err -> NativeBuildIOError (show err)
 where
  runClang clangPath llvmPath = do
    let args = llvmPath : extraInputs <> ["-o", outputPath]
    (code, stdoutText, stderrText) <- readProcessWithExitCode clangPath args ""
    pure $
      case code of
        ExitSuccess -> NativeBuildSucceeded
        ExitFailure {} -> NativeBuildFailed clangPath args code stdoutText stderrText

runNativeExecutable :: FilePath -> IO NativeRunResult
runNativeExecutable path =
  runNativeExecutableWithInput path ""

runNativeExecutableWithInput :: FilePath -> String -> IO NativeRunResult
runNativeExecutableWithInput path stdinText = do
  result <- try (readProcessWithExitCode (nativeExecutableCommand path) [] stdinText) :: IO (Either IOException (ExitCode, String, String))
  pure $
    case result of
      Left err ->
        NativeRunIOError (show err)
      Right (code, stdoutText, stderrText) ->
        case code of
          ExitSuccess -> NativeRunSucceeded stdoutText
          ExitFailure {} -> NativeRunFailed code stdoutText stderrText

nativeExecutableCommand :: FilePath -> FilePath
nativeExecutableCommand path
  | '/' `elem` path = path
  | otherwise = "." <> "/" <> path

runWithLlvmAs :: FilePath -> Text.Text -> IO LLVMAssemblyResult
runWithLlvmAs llvmAsPath llvmText = do
  path <- writeLLVMText llvmText
  let bitcodePath = ".context/llvm/latest.bc"
  (code, stdoutText, stderrText) <- readProcessWithExitCode llvmAsPath [path, "-o", bitcodePath] ""
  pure $
    case code of
      ExitSuccess -> LLVMAssemblySucceeded
      ExitFailure {} -> LLVMAssemblyFailed stdoutText stderrText

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

withTempLLVMFile :: Text.Text -> (FilePath -> IO a) -> IO a
withTempLLVMFile llvmText action =
  bracket create cleanup action
 where
  create = do
    tempDirectory <- getTemporaryDirectory
    (path, handle) <- openTempFile tempDirectory "hegglog-native.ll"
    Text.IO.hPutStr handle llvmText
    hClose handle
    pure path

  cleanup path =
    removeFile path `catch` ignoreRemoveError

  ignoreRemoveError :: IOException -> IO ()
  ignoreRemoveError _ =
    pure ()

processResult :: ExitCode -> String -> String -> LLVMRunResult
processResult = \case
  ExitSuccess ->
    \stdoutText _ -> LLVMRunSucceeded stdoutText
  ExitFailure {} ->
    \stdoutText stderrText -> LLVMRunFailed stdoutText stderrText
