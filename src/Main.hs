module Main (main) where

import Backend.Compile
import Backend.LLVM.Toolchain
import CLI.Compile (CompileCLIOptions (..), CompileOutputMode (..), parseCompileFlags)
import CLI.Report (compileReport, renderCompileError, renderFullReport)
import Control.Exception (IOException, try)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Haskell2010.Native (compileHaskell2010ToLLVM, haskell2010LLVMText, renderHaskell2010LLVMError)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure)
import System.IO (stderr)

main :: IO ()
main = do
  getArgs >>= \case
    [] -> do
      Text.IO.putStrLn usage
      exitFailure
    ["--help"] ->
      Text.IO.putStrLn usage
    ["help"] ->
      Text.IO.putStrLn usage
    "compile" : "--help" : [] ->
      Text.IO.putStrLn compileUsage
    "compile" : [] -> do
      Text.IO.putStrLn compileUsage
      exitFailure
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
  readSourceFile path >>= \case
    Left message -> do
      Text.IO.hPutStrLn stderr message
      exitFailure
    Right source ->
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
      Text.IO.hPutStrLn stderr message
      Text.IO.hPutStrLn stderr compileUsage
      exitFailure
    Right cliOptions -> do
      readSourceFile path >>= \case
        Left message -> do
          Text.IO.hPutStrLn stderr message
          exitFailure
        Right source -> do
          let options =
                defaultCompileLLVMOptions
                  { compileUseEgglog = cliUseEgglog cliOptions
                  }
          case compileSourceToLLVM options path source of
            Left err -> do
              Text.IO.hPutStrLn stderr err
              exitFailure
            Right result -> do
              handleCompileOutput cliOptions result

readSourceFile :: FilePath -> IO (Either Text Text)
readSourceFile path = do
  result <- try (Text.IO.readFile path) :: IO (Either IOException Text)
  pure $
    case result of
      Left err ->
        Left ("could not read source file " <> Text.pack path <> ": " <> Text.pack (show err))
      Right source ->
        Right source

data CompiledLLVMOutput = CompiledLLVMOutput
  { compiledLLVMText :: Text
  , compiledStatus :: Text
  }
  deriving stock (Show, Eq)

compileSourceToLLVM :: CompileLLVMOptions -> FilePath -> Text -> Either Text CompiledLLVMOutput
compileSourceToLLVM options path source
  | isHaskell2010Source path =
      case compileHaskell2010ToLLVM path source of
        Left err ->
          Left (renderHaskell2010LLVMError err)
        Right result ->
          Right
            CompiledLLVMOutput
              { compiledLLVMText = haskell2010LLVMText result
              , compiledStatus = "haskell2010: Core-0 STG native path; egglog: not applied"
              }
  | otherwise =
      case compileToLLVM options path source of
        Left err ->
          Left (renderCompileLLVMError err)
        Right result ->
          Right
            CompiledLLVMOutput
              { compiledLLVMText = llvmText result
              , compiledStatus = renderLLVMOptimizationStatus (llvmOptimizationStatus result)
              }

isHaskell2010Source :: FilePath -> Bool
isHaskell2010Source path =
  fileExtension path == ".hs"

fileExtension :: FilePath -> String
fileExtension path =
  case break (== '.') (reverse path) of
    (reversedExtension, '.' : _) -> "." <> reverse reversedExtension
    _ -> ""

handleCompileOutput :: CompileCLIOptions -> CompiledLLVMOutput -> IO ()
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

emitLLVMOutput :: Maybe FilePath -> CompiledLLVMOutput -> IO ()
emitLLVMOutput maybePath result =
  case maybePath of
    Nothing ->
      Text.IO.putStr (compiledLLVMText result)
    Just path -> do
      ensureParentDirectory path
      Text.IO.writeFile path (compiledLLVMText result)
      Text.IO.putStrLn ("wrote LLVM IR to " <> Text.pack path)
      Text.IO.putStrLn (compiledStatus result)

buildNativeOutput :: FilePath -> CompiledLLVMOutput -> IO ()
buildNativeOutput outputPath result = do
  ensureParentDirectory outputPath
  tools <- findLLVMTools
  nativeResult <- buildNativeExecutable tools (compiledLLVMText result) outputPath
  case nativeResult of
    NativeBuildSucceeded -> do
      Text.IO.hPutStrLn stderr ("wrote native executable to " <> Text.pack outputPath)
      Text.IO.hPutStrLn stderr (compiledStatus result)
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

runGeneratedLLVM :: CompiledLLVMOutput -> IO ()
runGeneratedLLVM result = do
  tools <- findLLVMTools
  runResult <- runLLVMText tools (compiledLLVMText result)
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
    [ "HeggLog compiler"
    , ""
    , "usage:"
    , "  hegglog FILE"
    , "  hegglog compile FILE [compile options]"
    , "  hegglog FILE --emit-llvm [compile options]"
    , ""
    , "modes:"
    , "  FILE"
    , "      Run report/interpreter mode for a source file."
    , "  compile FILE -o PROGRAM"
    , "      Build a native executable with clang."
    , "  compile FILE --emit-llvm [-o FILE.ll]"
    , "      Emit textual LLVM IR."
    , ""
    , "examples:"
    , "  cabal run hegglog -- examples/test.hg"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic --run"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/hegglog.ll"
    , ""
    , "run `hegglog compile --help` for compile options."
    ]

compileUsage :: Text
compileUsage =
  Text.unlines
    [ "HeggLog compile mode"
    , ""
    , "usage:"
    , "  hegglog compile FILE --emit-llvm [-o FILE.ll] [--no-egglog] [--run-llvm]"
    , "  hegglog compile FILE -o PROGRAM [--no-egglog] [--run]"
    , "  hegglog FILE --emit-llvm [-o FILE.ll] [--no-egglog] [--run-llvm]"
    , ""
    , "options:"
    , "  --emit-llvm"
    , "      Emit textual LLVM IR instead of building a native executable."
    , "  -o, --output PATH"
    , "      Write LLVM IR to PATH with --emit-llvm, or build native executable PATH otherwise."
    , "  --run"
    , "      Build the native executable and run it. Requires -o/--output."
    , "  --run-llvm"
    , "      Run generated LLVM text through lli, or through a temporary clang executable."
    , "  --no-egglog"
    , "      Compile without Egglog optimization."
    , ""
    , "toolchain:"
    , "  Native executable output requires clang. LLVM text output does not."
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
