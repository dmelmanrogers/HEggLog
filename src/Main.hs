module Main (main) where

import Backend.Compile
import Backend.LLVM.Toolchain
import CLI.Compile (CompileCLIOptions (..), CompileLinkOptions (..), CompileOutputMode (..), parseCompileFlags)
import CLI.Report (compileReport, renderCompileError, renderFullReport)
import Control.Monad (unless)
import Control.Exception (IOException, try)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Haskell2010.Native
  ( compileHaskell2010FileToLLVMWithOptions
  , compileHaskell2010ToLLVMWithOptions
  , defaultHaskell2010NativeOptions
  , haskell2010ImportPaths
  , haskell2010LLVMText
  , haskell2010OptimizationStatus
  , haskell2010UseEgglog
  , haskell2010Warnings
  , renderHaskell2010LLVMError
  , renderHaskell2010OptimizationStatus
  )
import Haskell2010.Typecheck (renderTypecheckWarning)
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
      let options =
            defaultCompileLLVMOptions
              { compileUseEgglog = cliUseEgglog cliOptions
              }
      compilePathToLLVM options (cliImportPaths cliOptions) path >>= \case
        Left err -> do
          Text.IO.hPutStrLn stderr err
          exitFailure
        Right result ->
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
  , compiledWarnings :: [Text]
  }
  deriving stock (Show, Eq)

compileSourceToLLVM :: CompileLLVMOptions -> FilePath -> Text -> Either Text CompiledLLVMOutput
compileSourceToLLVM options path source
  | isHaskell2010Source path =
      case compileHaskell2010ToLLVMWithOptions haskellOptions path source of
        Left err ->
          Left (renderHaskell2010LLVMError err)
        Right result ->
          Right
            CompiledLLVMOutput
              { compiledLLVMText = haskell2010LLVMText result
              , compiledStatus = renderHaskell2010OptimizationStatus (haskell2010OptimizationStatus result)
              , compiledWarnings = map renderTypecheckWarning (haskell2010Warnings result)
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
              , compiledWarnings = []
              }
 where
  haskellOptions =
    defaultHaskell2010NativeOptions
      { haskell2010UseEgglog = compileUseEgglog options
      }

compilePathToLLVM :: CompileLLVMOptions -> [FilePath] -> FilePath -> IO (Either Text CompiledLLVMOutput)
compilePathToLLVM options importPaths path
  | isHaskell2010Source path = do
      let haskellOptions =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = compileUseEgglog options
              , haskell2010ImportPaths = importPaths
              }
      result <- compileHaskell2010FileToLLVMWithOptions haskellOptions path
      pure $
        case result of
          Left err ->
            Left (renderHaskell2010LLVMError err)
          Right compiled ->
            Right
              CompiledLLVMOutput
                { compiledLLVMText = haskell2010LLVMText compiled
                , compiledStatus = renderHaskell2010OptimizationStatus (haskell2010OptimizationStatus compiled)
                , compiledWarnings = map renderTypecheckWarning (haskell2010Warnings compiled)
                }
  | otherwise =
      readSourceFile path >>= \case
        Left message ->
          pure (Left message)
        Right source ->
          pure (compileSourceToLLVM options path source)

isHaskell2010Source :: FilePath -> Bool
isHaskell2010Source path =
  fileExtension path == ".hs"

fileExtension :: FilePath -> String
fileExtension path =
  case break (== '.') (reverse path) of
    (reversedExtension, '.' : _) -> "." <> reverse reversedExtension
    _ -> ""

handleCompileOutput :: CompileCLIOptions -> CompiledLLVMOutput -> IO ()
handleCompileOutput cliOptions result = do
  emitCompileWarnings result
  case cliOutputMode cliOptions of
    EmitLLVM maybePath ->
      emitLLVMOutput maybePath result
    EmitAndRunLLVM maybePath -> do
      emitLLVMOutput maybePath result
      runGeneratedLLVM result
    BuildExecutable outputPath ->
      buildNativeOutput (cliLinkOptions cliOptions) outputPath result
    BuildAndRunExecutable outputPath -> do
      buildNativeOutput (cliLinkOptions cliOptions) outputPath result
      runGeneratedExecutable outputPath

emitCompileWarnings :: CompiledLLVMOutput -> IO ()
emitCompileWarnings result =
  unless (null (compiledWarnings result)) $
    Text.IO.hPutStr stderr (Text.unlines (compiledWarnings result))

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

buildNativeOutput :: CompileLinkOptions -> FilePath -> CompiledLLVMOutput -> IO ()
buildNativeOutput linkOptions outputPath result = do
  ensureParentDirectory outputPath
  tools <- findLLVMTools
  nativeResult <-
    buildNativeExecutableWithLinkOptions
      tools
      (compiledLLVMText result)
      (nativeLinkOptionsFromCLI linkOptions)
      outputPath
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

nativeLinkOptionsFromCLI :: CompileLinkOptions -> NativeLinkOptions
nativeLinkOptionsFromCLI linkOptions =
  defaultNativeLinkOptions
    { nativeLinkObjects = cliLinkObjects linkOptions
    , nativeLinkLibraries = cliLinkLibraries linkOptions
    , nativeLinkLibraryPaths = cliLinkLibraryPaths linkOptions
    , nativeLinkFrameworks = cliLinkFrameworks linkOptions
    }

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
    , "  -i, --import-path PATH"
    , "      Add a source module import search directory. May be repeated; the root module directory is searched first."
    , "  --link-object PATH"
    , "      Add an object file or native archive to the clang link command. May be repeated."
    , "  --link-library NAME"
    , "      Link with -lNAME. May be repeated."
    , "  --library-path PATH"
    , "      Add -LPATH to the native link command. May be repeated."
    , "  --framework NAME"
    , "      Link with a macOS framework. May be repeated."
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
