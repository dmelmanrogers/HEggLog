module Main (main) where

import Backend.Compile
import Backend.LLVM.Toolchain
import CLI.Report (compileReport, renderCompileError, renderFullReport)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.Directory (createDirectoryIfMissing)
import System.IO (stderr)

data CompileCLIOptions = CompileCLIOptions
  { cliOutput :: Maybe FilePath
  , cliUseEgglog :: Bool
  , cliRunLLVM :: Bool
  }
  deriving stock (Show, Eq)

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
          emitCompileResult cliOptions result
          if cliRunLLVM cliOptions
            then runGeneratedLLVM result
            else pure ()

emitCompileResult :: CompileCLIOptions -> LLVMCompileResult -> IO ()
emitCompileResult cliOptions result =
  case cliOutput cliOptions of
    Nothing ->
      Text.IO.putStr (llvmText result)
    Just path -> do
      ensureParentDirectory path
      Text.IO.writeFile path (llvmText result)
      Text.IO.putStrLn ("wrote LLVM IR to " <> Text.pack path)
      Text.IO.putStrLn (renderLLVMOptimizationStatus (llvmOptimizationStatus result))

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

parseCompileFlags :: [String] -> Either Text CompileCLIOptions
parseCompileFlags =
  go
    CompileCLIOptions
      { cliOutput = Nothing
      , cliUseEgglog = True
      , cliRunLLVM = False
      }
 where
  go options = \case
    [] ->
      Right options
    "--emit-llvm" : rest ->
      go options rest
    "--no-egglog" : rest ->
      go options {cliUseEgglog = False} rest
    "--run-llvm" : rest ->
      go options {cliRunLLVM = True} rest
    "-o" : output : rest ->
      go options {cliOutput = Just output} rest
    "--output" : output : rest ->
      go options {cliOutput = Just output} rest
    "-o" : [] ->
      Left "-o requires a file path"
    "--output" : [] ->
      Left "--output requires a file path"
    flag : _ ->
      Left ("unknown compile option: " <> Text.pack flag)

usage :: Text
usage =
  Text.unlines
    [ "usage:"
    , "  cabal run hegglog -- examples/test.hg"
    , "  cabal run hegglog -- compile examples/test.hg --emit-llvm [-o build/test.ll] [--no-egglog] [--run-llvm]"
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
