module Main (main) where

import Backend.Compile
import Backend.LLVM.Toolchain
import CLI.Compile (CompileCLIOptions (..), CompileOutputMode (..), parseCompileFlags)
import CLI.Report (compileReport, renderCompileError, renderFullReport)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure)
import System.IO (stderr)

main :: IO ()
main = do
  getArgs >>= \case
    "compile" : path : flags ->
      runCompile path flags
    [path] -> runFile path
    path : flags
      | "--emit-llvm" `elem` flags -> runCompile path flags
    _ -> do
      Text.IO.putStrLn usage
      exitFailure

runFile :: FilePath -> IO ()
runFile path = do
  source <- Text.IO.readFile path
  case compileReport path source of
    Left err -> do
      Text.IO.putStr (renderCompileError err)
      exitFailure
    Right report ->
      Text.IO.putStr (renderFullReport report)

runCompile :: FilePath -> [String] -> IO ()
runCompile path flags =
  case parseCompileFlags flags of
    Left message -> do
      Text.IO.putStrLn message
      Text.IO.putStrLn usage
      exitFailure
    Right cliOptions -> do
      source <- Text.IO.readFile path
      let options =
            defaultCompileLLVMOptions
              { compileUseEgglog = cliUseEgglog cliOptions
              }
      case compileToLLVM options path source of
        Left err -> do
          Text.IO.putStrLn (renderCompileLLVMError err)
          exitFailure
        Right result -> do
          handleCompileOutput cliOptions result

handleCompileOutput :: CompileCLIOptions -> LLVMCompileResult -> IO ()
handleCompileOutput cliOptions result =
  case cliOutputMode cliOptions of
    EmitLLVM maybePath ->
      emitLLVMOutput maybePath result
    EmitAndRunLLVM maybePath -> do
      emitLLVMOutput maybePath result
      runGeneratedLLVM result
    BuildExecutable outputPath ->
      buildNativeOutput outputPath result
    BuildAndRunExecutable outputPath -> do
      buildNativeOutput outputPath result
      runGeneratedExecutable outputPath

emitLLVMOutput :: Maybe FilePath -> LLVMCompileResult -> IO ()
emitLLVMOutput maybePath result =
  case maybePath of
    Nothing ->
      Text.IO.putStr (llvmText result)
    Just path -> do
      ensureParentDirectory path
      Text.IO.writeFile path (llvmText result)
      Text.IO.putStrLn ("wrote LLVM IR to " <> Text.pack path)
      Text.IO.putStrLn (renderLLVMOptimizationStatus (llvmOptimizationStatus result))

buildNativeOutput :: FilePath -> LLVMCompileResult -> IO ()
buildNativeOutput outputPath result = do
  ensureParentDirectory outputPath
  tools <- findLLVMTools
  nativeResult <- buildNativeExecutable tools (llvmText result) outputPath
  case nativeResult of
    NativeBuildSucceeded -> do
      Text.IO.hPutStrLn stderr ("wrote native executable to " <> Text.pack outputPath)
      Text.IO.hPutStrLn stderr (renderLLVMOptimizationStatus (llvmOptimizationStatus result))
    NativeBuildToolchainMissing message -> do
      Text.IO.hPutStrLn stderr ("native executable build unavailable: " <> Text.pack message)
      exitFailure
    NativeBuildFailed clangPath args code stdoutText stderrText -> do
      Text.IO.hPutStrLn stderr ("native executable build failed: " <> renderExitCode code)
      Text.IO.hPutStrLn stderr ("command: " <> Text.pack (unwords (clangPath : args)))
      if null stdoutText then pure () else Text.IO.hPutStrLn stderr ("stdout:\n" <> Text.pack stdoutText)
      if null stderrText then pure () else Text.IO.hPutStrLn stderr ("stderr:\n" <> Text.pack stderrText)
      exitFailure
    NativeBuildIOError message -> do
      Text.IO.hPutStrLn stderr ("native executable build I/O error: " <> Text.pack message)
      exitFailure

runGeneratedLLVM :: LLVMCompileResult -> IO ()
runGeneratedLLVM result = do
  tools <- findLLVMTools
  runResult <- runLLVMText tools (llvmText result)
  case runResult of
    LLVMRunSkipped message ->
      Text.IO.hPutStrLn stderr (Text.pack message)
    LLVMRunFailed stdoutText stderrText -> do
      Text.IO.hPutStrLn stderr ("LLVM execution failed with tools: " <> Text.pack (renderLLVMTools tools))
      if null stdoutText then pure () else Text.IO.hPutStrLn stderr ("stdout:\n" <> Text.pack stdoutText)
      if null stderrText then pure () else Text.IO.hPutStrLn stderr ("stderr:\n" <> Text.pack stderrText)
      exitFailure
    LLVMRunSucceeded stdoutText ->
      Text.IO.hPutStr stderr (Text.pack stdoutText)

runGeneratedExecutable :: FilePath -> IO ()
runGeneratedExecutable outputPath = do
  runResult <- runNativeExecutable outputPath
  case runResult of
    NativeRunSucceeded stdoutText ->
      Text.IO.putStr (Text.pack stdoutText)
    NativeRunFailed code stdoutText stderrText -> do
      Text.IO.hPutStrLn stderr ("native executable failed: " <> Text.pack outputPath <> " exited with " <> renderExitCode code)
      if null stdoutText then pure () else Text.IO.hPutStrLn stderr ("stdout:\n" <> Text.pack stdoutText)
      if null stderrText then pure () else Text.IO.hPutStrLn stderr ("stderr:\n" <> Text.pack stderrText)
      exitFailure
    NativeRunIOError message -> do
      Text.IO.hPutStrLn stderr ("native executable run I/O error: " <> Text.pack message)
      exitFailure

renderExitCode :: ExitCode -> Text
renderExitCode = \case
  ExitSuccess ->
    "exit 0"
  ExitFailure code ->
    "exit " <> Text.pack (show code)

usage :: Text
usage =
  Text.unlines
    [ "usage:"
    , "  cabal run hegglog -- examples/test.hg"
    , "  cabal run hegglog -- compile examples/test.hg --emit-llvm [-o build/test.ll] [--no-egglog] [--run-llvm]"
    , "  cabal run hegglog -- compile examples/test.hg -o build/test [--no-egglog] [--run]"
    , "  cabal run hegglog -- examples/test.hg --emit-llvm [-o build/test.ll] [--no-egglog] [--run-llvm]"
    ]

ensureParentDirectory :: FilePath -> IO ()
ensureParentDirectory path =
  case parentDirectory path of
    Nothing -> pure ()
    Just directory -> createDirectoryIfMissing True directory

parentDirectory :: FilePath -> Maybe FilePath
parentDirectory path =
  case break (== '/') (reverse path) of
    (_, "") -> Nothing
    (_file, slashAndParent) ->
      case reverse (drop 1 slashAndParent) of
        "" -> Nothing
        directory -> Just directory
