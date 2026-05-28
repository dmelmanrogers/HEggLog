module Main (main) where

import Backend.Compile
import Backend.LLVM.Toolchain
import CLI.Command
  ( CLICommand (..)
  , CLICommandError (..)
  , checkUsage
  , compileUsage
  , emitCoreUsage
  , emitSTGUsage
  , generalUsage
  , parseCLICommand
  , reportUsage
  , runUsage
  , usageForTopic
  )
import CLI.Compile (CheckCLIOptions (..), CompileCLIOptions (..), CompileLinkOptions (..), CompileOutputMode (..), DumpCLIOptions (..), EmitCoreCLIOptions (..), EmitCoreSelection (..), EmitSTGCLIOptions (..), ReportCLIOptions (..), RunCLIOptions (..), dumpOptionsEnabled)
import CLI.Report (LegacyReportOptions (..), compileLegacyCore, compileReportWithOptions, defaultLegacyReportOptions, renderCompileError, renderFullReport)
import Control.Monad (unless, when)
import Control.Exception (IOException, finally, try)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Haskell2010.Core.Pretty (renderCoreModule)
import Haskell2010.Native
  ( Haskell2010CheckResult
  , Haskell2010LLVMResult
  , checkHaskell2010FileWithOptions
  , checkHaskell2010WithOptions
  , compileHaskell2010FileToLLVMWithOptions
  , compileHaskell2010ToLLVMWithOptions
  , defaultHaskell2010NativeOptions
  , haskell2010Core
  , haskell2010CheckCore
  , haskell2010CheckOriginalCore
  , haskell2010CheckOptimizationStatus
  , haskell2010CheckSTG
  , haskell2010CheckWarnings
  , haskell2010ImportPaths
  , haskell2010LLVMText
  , haskell2010OriginalCore
  , haskell2010OptimizationStatus
  , haskell2010STG
  , haskell2010StrictEgglog
  , haskell2010UseEgglog
  , haskell2010Warnings
  , renderHaskell2010CheckError
  , renderHaskell2010LLVMError
  , renderHaskell2010OptimizationStatus
  )
import Haskell2010.STG.Pretty (renderSTGProgram)
import Haskell2010.Typecheck (TypecheckWarning, renderTypecheckWarning)
import qualified IR.Core as LegacyCore
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removeFile)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath ((<.>), (</>), takeBaseName)
import System.IO (hClose, openTempFile, stderr)

main :: IO ()
main = do
  getArgs >>= \args ->
    case parseCLICommand args of
      Left err -> do
        renderCommandError err
        exitFailure
      Right CommandGeneralHelp ->
        Text.IO.putStrLn generalUsage
      Right CommandCheckHelp ->
        Text.IO.putStrLn checkUsage
      Right CommandCompileHelp ->
        Text.IO.putStrLn compileUsage
      Right CommandEmitCoreHelp ->
        Text.IO.putStrLn emitCoreUsage
      Right CommandEmitSTGHelp ->
        Text.IO.putStrLn emitSTGUsage
      Right CommandReportHelp ->
        Text.IO.putStrLn reportUsage
      Right CommandRunHelp ->
        Text.IO.putStrLn runUsage
      Right (CommandCheck path cliOptions) ->
        runCheck path cliOptions
      Right (CommandReport path cliOptions) ->
        runReport path cliOptions
      Right (CommandEmitCore path cliOptions) ->
        runEmitCore path cliOptions
      Right (CommandEmitSTG path cliOptions) ->
        runEmitSTG path cliOptions
      Right (CommandRun path cliOptions) ->
        runSource path cliOptions
      Right (CommandCompile path cliOptions) ->
        runCompile path cliOptions

renderCommandError :: CLICommandError -> IO ()
renderCommandError err = do
  Text.IO.hPutStrLn stderr (commandErrorMessage err)
  Text.IO.hPutStrLn stderr (usageForTopic (commandErrorUsageTopic err))

runReport :: FilePath -> ReportCLIOptions -> IO ()
runReport path cliOptions
  | isHaskell2010Source path = do
      let options =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = reportUseEgglog cliOptions
              , haskell2010StrictEgglog = reportStrictEgglog cliOptions
              , haskell2010ImportPaths = reportImportPaths cliOptions
              }
      checkHaskell2010FileWithOptions options path >>= \case
        Left err -> do
          Text.IO.hPutStrLn stderr (renderHaskell2010CheckError err)
          exitFailure
        Right checked -> do
          Text.IO.putStr (renderHaskell2010Report path checked)
  | not (null (reportImportPaths cliOptions)) = do
      Text.IO.hPutStrLn stderr "legacy .hg report does not support Haskell 2010 import search paths"
      exitFailure
  | otherwise = do
      readSourceFile path >>= \case
        Left message -> do
          Text.IO.hPutStrLn stderr message
          exitFailure
        Right source ->
          case compileReportWithOptions (legacyReportOptionsFromCLI cliOptions) path source of
            Left err -> do
              Text.IO.hPutStr stderr (renderCompileError err)
              exitFailure
            Right report ->
              Text.IO.putStr (renderFullReport report)

legacyReportOptionsFromCLI :: ReportCLIOptions -> LegacyReportOptions
legacyReportOptionsFromCLI cliOptions =
  defaultLegacyReportOptions
    { legacyReportUseEgglog = reportUseEgglog cliOptions
    , legacyReportStrictEgglog = reportStrictEgglog cliOptions
    }

runCompile :: FilePath -> CompileCLIOptions -> IO ()
runCompile path cliOptions =
  case validateDumpSource (cliDumpOptions cliOptions) path of
    Just err -> do
      Text.IO.hPutStrLn stderr err
      exitFailure
    Nothing -> do
      let options =
            defaultCompileLLVMOptions
              { compileUseEgglog = cliUseEgglog cliOptions
              , compileStrictEgglog = cliStrictEgglog cliOptions
              }
      compilePathToLLVM options (cliImportPaths cliOptions) path >>= \case
        Left err -> do
          Text.IO.hPutStrLn stderr err
          exitFailure
        Right result ->
          handleCompileOutput path cliOptions result

runCheck :: FilePath -> CheckCLIOptions -> IO ()
runCheck path cliOptions =
  case validateDumpSource (checkDumpOptions cliOptions) path of
    Just err -> do
      Text.IO.hPutStrLn stderr err
      exitFailure
    Nothing -> do
      let options =
            defaultCompileLLVMOptions
              { compileUseEgglog = checkUseEgglog cliOptions
              , compileStrictEgglog = checkStrictEgglog cliOptions
              }
      checkPath options (checkImportPaths cliOptions) path >>= \case
        Left err -> do
          Text.IO.hPutStrLn stderr err
          exitFailure
        Right result -> do
          emitWarnings (checkOutputWarnings result)
          emitDumpArtifacts (checkDumpOptions cliOptions) (checkOutputDumpArtifacts result)

runEmitCore :: FilePath -> EmitCoreCLIOptions -> IO ()
runEmitCore path cliOptions =
  emitCorePath path cliOptions >>= \case
    Left err -> do
      Text.IO.hPutStrLn stderr err
      exitFailure
    Right result -> do
      emitWarnings (textOutputWarnings result)
      writeTextOutput (emitCoreOutput cliOptions) (textOutputText result)

runEmitSTG :: FilePath -> EmitSTGCLIOptions -> IO ()
runEmitSTG path cliOptions =
  emitSTGPath path cliOptions >>= \case
    Left err -> do
      Text.IO.hPutStrLn stderr err
      exitFailure
    Right result -> do
      emitWarnings (textOutputWarnings result)
      writeTextOutput (emitSTGOutput cliOptions) (textOutputText result)

runSource :: FilePath -> RunCLIOptions -> IO ()
runSource path cliOptions =
  case validateDumpSource (runDumpOptions cliOptions) path of
    Just err -> do
      Text.IO.hPutStrLn stderr err
      exitFailure
    Nothing ->
      runWithOutputPath $ \outputPath keepPolicy -> do
        let options =
              defaultCompileLLVMOptions
                { compileUseEgglog = runUseEgglog cliOptions
                , compileStrictEgglog = runStrictEgglog cliOptions
                }
        compilePathToLLVM options (runImportPaths cliOptions) path >>= \case
          Left err -> do
            Text.IO.hPutStrLn stderr err
            exitFailure
          Right result -> do
            emitCompileWarnings result
            emitDumpArtifacts (runDumpOptions cliOptions) (compiledDumpArtifacts result)
            buildNativeOutputWithVerbosity False keepPolicy (runLinkOptions cliOptions) outputPath result
            runGeneratedExecutable outputPath
 where
  runWithOutputPath action
    | runKeepIntermediates cliOptions =
        let outputPath = keptExecutablePath path
            keepPolicy =
              NativeKeepPolicy
                { nativeKeepPaths = keptNativeIntermediatePaths path
                , nativeKeepExecutable = Just outputPath
                }
         in action outputPath (Just keepPolicy)
    | otherwise =
        withTemporaryExecutable $ \outputPath -> action outputPath Nothing

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
  , compiledDumpArtifacts :: Maybe DumpArtifacts
  }
  deriving stock (Show, Eq)

data CheckOutput = CheckOutput
  { checkOutputWarnings :: [Text]
  , checkOutputDumpArtifacts :: Maybe DumpArtifacts
  }
  deriving stock (Show, Eq)

data DumpArtifacts = DumpArtifacts
  { dumpArtifactsCore :: Text
  , dumpArtifactsOptimizedCore :: Text
  , dumpArtifactsSTG :: Text
  }
  deriving stock (Show, Eq)

data NativeKeepPolicy = NativeKeepPolicy
  { nativeKeepPaths :: NativeIntermediatePaths
  , nativeKeepExecutable :: Maybe FilePath
  }
  deriving stock (Show, Eq)

data TextOutput = TextOutput
  { textOutputText :: Text
  , textOutputWarnings :: [Text]
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
              , compiledDumpArtifacts = Just (dumpArtifactsFromLLVMResult result)
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
              , compiledDumpArtifacts = Nothing
              }
 where
  haskellOptions =
    defaultHaskell2010NativeOptions
      { haskell2010UseEgglog = compileUseEgglog options
      , haskell2010StrictEgglog = compileStrictEgglog options
      }

compilePathToLLVM :: CompileLLVMOptions -> [FilePath] -> FilePath -> IO (Either Text CompiledLLVMOutput)
compilePathToLLVM options importPaths path
  | isHaskell2010Source path = do
      let haskellOptions =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = compileUseEgglog options
              , haskell2010StrictEgglog = compileStrictEgglog options
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
                , compiledDumpArtifacts = Just (dumpArtifactsFromLLVMResult compiled)
                }
  | otherwise =
      readSourceFile path >>= \case
        Left message ->
          pure (Left message)
        Right source ->
          pure (compileSourceToLLVM options path source)

checkPath :: CompileLLVMOptions -> [FilePath] -> FilePath -> IO (Either Text CheckOutput)
checkPath options importPaths path
  | isHaskell2010Source path = do
      let haskellOptions =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = compileUseEgglog options
              , haskell2010StrictEgglog = compileStrictEgglog options
              , haskell2010ImportPaths = importPaths
              }
      result <- checkHaskell2010FileWithOptions haskellOptions path
      pure $
        case result of
          Left err ->
            Left (renderHaskell2010CheckError err)
          Right checked ->
            Right
              CheckOutput
                { checkOutputWarnings = map renderTypecheckWarning (haskell2010CheckWarnings checked)
                , checkOutputDumpArtifacts = Just (dumpArtifactsFromCheckResult checked)
                }
  | otherwise =
      readSourceFile path >>= \case
        Left message ->
          pure (Left message)
        Right source ->
          pure (checkSource options path source)

checkSource :: CompileLLVMOptions -> FilePath -> Text -> Either Text CheckOutput
checkSource options path source
  | isHaskell2010Source path =
      case checkHaskell2010WithOptions haskellOptions path source of
        Left err ->
          Left (renderHaskell2010CheckError err)
        Right checked ->
          Right
            CheckOutput
              { checkOutputWarnings = map renderTypecheckWarning (haskell2010CheckWarnings checked)
              , checkOutputDumpArtifacts = Just (dumpArtifactsFromCheckResult checked)
              }
  | otherwise =
      case checkToBackend options path source of
        Left err ->
          Left (renderCompileLLVMError err)
        Right _ ->
          Right
            CheckOutput
              { checkOutputWarnings = []
              , checkOutputDumpArtifacts = Nothing
              }
 where
  haskellOptions =
    defaultHaskell2010NativeOptions
      { haskell2010UseEgglog = compileUseEgglog options
      , haskell2010StrictEgglog = compileStrictEgglog options
      }

emitCorePath :: FilePath -> EmitCoreCLIOptions -> IO (Either Text TextOutput)
emitCorePath path cliOptions
  | isHaskell2010Source path = do
      let haskellOptions =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = emitCoreUseEgglog cliOptions
              , haskell2010StrictEgglog = emitCoreStrictEgglog cliOptions
              , haskell2010ImportPaths = emitCoreImportPaths cliOptions
              }
      result <- checkHaskell2010FileWithOptions haskellOptions path
      pure $
        case result of
          Left err ->
            Left (renderHaskell2010CheckError err)
          Right checked ->
            Right
              TextOutput
                { textOutputText = renderHaskell2010CoreSelection (emitCoreSelection cliOptions) checked
                , textOutputWarnings = map renderTypecheckWarning (haskell2010CheckWarnings checked)
                }
  | otherwise =
      case validateLegacyEmitCoreOptions cliOptions of
        Just message ->
          pure (Left message)
        Nothing ->
          readSourceFile path >>= \case
            Left message ->
              pure (Left message)
            Right source ->
              pure (emitLegacyCore path source)

validateLegacyEmitCoreOptions :: EmitCoreCLIOptions -> Maybe Text
validateLegacyEmitCoreOptions cliOptions
  | not (emitCoreUseEgglog cliOptions) =
      Just "legacy .hg emit-core does not support --no-egglog; use report for the legacy optimizer report"
  | emitCoreStrictEgglog cliOptions =
      Just "legacy .hg emit-core does not support --strict-egglog; use report for the legacy optimizer report"
  | not (null (emitCoreImportPaths cliOptions)) =
      Just "legacy .hg emit-core does not support Haskell 2010 import search paths"
  | emitCoreSelection cliOptions /= EmitCoreOptimized =
      Just "legacy .hg emit-core exposes one Core IR form; --original, --optimized, and --both are Haskell 2010 typed-Core options"
  | otherwise =
      Nothing

emitLegacyCore :: FilePath -> Text -> Either Text TextOutput
emitLegacyCore path source =
  case compileLegacyCore path source of
    Left err ->
      Left (renderCompileError err)
    Right core ->
      Right
        TextOutput
          { textOutputText = LegacyCore.renderCore core
          , textOutputWarnings = []
          }

emitSTGPath :: FilePath -> EmitSTGCLIOptions -> IO (Either Text TextOutput)
emitSTGPath path cliOptions
  | isHaskell2010Source path = do
      let haskellOptions =
            defaultHaskell2010NativeOptions
              { haskell2010UseEgglog = emitSTGUseEgglog cliOptions
              , haskell2010StrictEgglog = emitSTGStrictEgglog cliOptions
              , haskell2010ImportPaths = emitSTGImportPaths cliOptions
              }
      result <- checkHaskell2010FileWithOptions haskellOptions path
      pure $
        case result of
          Left err ->
            Left (renderHaskell2010CheckError err)
          Right checked ->
            Right
              TextOutput
                { textOutputText = renderSTGProgram (haskell2010CheckSTG checked)
                , textOutputWarnings = map renderTypecheckWarning (haskell2010CheckWarnings checked)
                }
  | otherwise =
      pure (Left "emit-stg supports Haskell 2010 .hs sources only; legacy .hg has no STG IR")

renderHaskell2010Report :: FilePath -> Haskell2010CheckResult -> Text
renderHaskell2010Report path checked =
  Text.concat
    [ "Status: ok\n"
    , coreSection
        "Source"
        ( Text.unlines
            [ "path: " <> Text.pack path
            , "mode: Haskell 2010"
            ]
        )
    , coreSection "Warnings" (renderHaskell2010ReportWarnings (haskell2010CheckWarnings checked))
    , coreSection "Optimization" (renderHaskell2010OptimizationStatus (haskell2010CheckOptimizationStatus checked))
    , coreSection "Original Typed Core" (renderCoreModule (haskell2010CheckOriginalCore checked))
    , coreSection "Optimized Typed Core" (renderCoreModule (haskell2010CheckCore checked))
    , coreSection "STG" (renderSTGProgram (haskell2010CheckSTG checked))
    ]

renderHaskell2010ReportWarnings :: [TypecheckWarning] -> Text
renderHaskell2010ReportWarnings warnings =
  case warnings of
    [] -> "none\n"
    _ -> Text.unlines (map renderTypecheckWarning warnings)

renderHaskell2010CoreSelection :: EmitCoreSelection -> Haskell2010CheckResult -> Text
renderHaskell2010CoreSelection selection checked =
  case selection of
    EmitCoreOptimized ->
      renderCoreModule (haskell2010CheckCore checked)
    EmitCoreOriginal ->
      renderCoreModule (haskell2010CheckOriginalCore checked)
    EmitCoreBoth ->
      Text.concat
        [ coreSection "Original Typed Core" (renderCoreModule (haskell2010CheckOriginalCore checked))
        , coreSection "Optimized Typed Core" (renderCoreModule (haskell2010CheckCore checked))
        ]

coreSection :: Text -> Text -> Text
coreSection title body =
  "== " <> title <> " ==\n" <> Text.stripEnd body <> "\n"

dumpArtifactsFromCheckResult :: Haskell2010CheckResult -> DumpArtifacts
dumpArtifactsFromCheckResult checked =
  DumpArtifacts
    { dumpArtifactsCore = renderCoreModule (haskell2010CheckOriginalCore checked)
    , dumpArtifactsOptimizedCore = renderCoreModule (haskell2010CheckCore checked)
    , dumpArtifactsSTG = renderSTGProgram (haskell2010CheckSTG checked)
    }

dumpArtifactsFromLLVMResult :: Haskell2010LLVMResult -> DumpArtifacts
dumpArtifactsFromLLVMResult compiled =
  DumpArtifacts
    { dumpArtifactsCore = renderCoreModule (haskell2010OriginalCore compiled)
    , dumpArtifactsOptimizedCore = renderCoreModule (haskell2010Core compiled)
    , dumpArtifactsSTG = renderSTGProgram (haskell2010STG compiled)
    }

validateDumpSource :: DumpCLIOptions -> FilePath -> Maybe Text
validateDumpSource dumpOptions path
  | dumpOptionsEnabled dumpOptions && not (isHaskell2010Source path) =
      Just "dump flags are supported for Haskell 2010 .hs sources only; legacy .hg sources have no typed Core/STG artifact pipeline"
  | otherwise =
      Nothing

emitDumpArtifacts :: DumpCLIOptions -> Maybe DumpArtifacts -> IO ()
emitDumpArtifacts dumpOptions maybeArtifacts
  | not (dumpOptionsEnabled dumpOptions) =
      pure ()
  | Just artifacts <- maybeArtifacts =
      Text.IO.hPutStr stderr (renderDumpArtifacts dumpOptions artifacts)
  | otherwise = do
      Text.IO.hPutStrLn stderr "internal error: dump artifacts were not available for this source"
      exitFailure

renderDumpArtifacts :: DumpCLIOptions -> DumpArtifacts -> Text
renderDumpArtifacts dumpOptions artifacts =
  Text.concat $
    [coreSection "Core" (dumpArtifactsCore artifacts) | dumpCore dumpOptions]
      <> [coreSection "Optimized Core" (dumpArtifactsOptimizedCore artifacts) | dumpOptimizedCore dumpOptions]
      <> [coreSection "STG" (dumpArtifactsSTG artifacts) | dumpSTG dumpOptions]

writeTextOutput :: Maybe FilePath -> Text -> IO ()
writeTextOutput maybePath output =
  case maybePath of
    Nothing ->
      Text.IO.putStr output
    Just path -> do
      ensureParentDirectory path
      Text.IO.writeFile path output

isHaskell2010Source :: FilePath -> Bool
isHaskell2010Source path =
  fileExtension path == ".hs"

fileExtension :: FilePath -> String
fileExtension path =
  case break (== '.') (reverse path) of
    (reversedExtension, '.' : _) -> "." <> reverse reversedExtension
    _ -> ""

keptIntermediateDirectory :: FilePath
keptIntermediateDirectory =
  ".context" </> "hegglog" </> "intermediates"

keptIntermediateBase :: FilePath -> String
keptIntermediateBase path =
  case takeBaseName path of
    "" -> "source"
    base -> base

keptLLVMPath :: FilePath -> FilePath
keptLLVMPath path =
  keptIntermediateDirectory </> keptIntermediateBase path <.> "ll"

keptNativeIntermediatePaths :: FilePath -> NativeIntermediatePaths
keptNativeIntermediatePaths path =
  NativeIntermediatePaths
    { nativeIntermediateLLVM = keptLLVMPath path
    , nativeIntermediateObject = keptIntermediateDirectory </> keptIntermediateBase path <.> "o"
    }

keptExecutablePath :: FilePath -> FilePath
keptExecutablePath path =
  keptIntermediateDirectory </> keptIntermediateBase path

writeKeptLLVMIntermediate :: FilePath -> CompiledLLVMOutput -> IO ()
writeKeptLLVMIntermediate sourcePath result = do
  let llvmPath = keptLLVMPath sourcePath
  ensureParentDirectory llvmPath
  Text.IO.writeFile llvmPath (compiledLLVMText result)
  Text.IO.hPutStrLn stderr ("kept LLVM intermediate at " <> Text.pack llvmPath)

emitKeptNativeIntermediates :: NativeKeepPolicy -> IO ()
emitKeptNativeIntermediates keepPolicy = do
  Text.IO.hPutStrLn stderr ("kept LLVM intermediate at " <> Text.pack (nativeIntermediateLLVM (nativeKeepPaths keepPolicy)))
  Text.IO.hPutStrLn stderr ("kept object intermediate at " <> Text.pack (nativeIntermediateObject (nativeKeepPaths keepPolicy)))
  case nativeKeepExecutable keepPolicy of
    Nothing ->
      pure ()
    Just outputPath ->
      Text.IO.hPutStrLn stderr ("kept executable intermediate at " <> Text.pack outputPath)

compileNativeKeepPolicy :: FilePath -> CompileCLIOptions -> Maybe NativeKeepPolicy
compileNativeKeepPolicy sourcePath cliOptions
  | cliKeepIntermediates cliOptions =
      Just
        NativeKeepPolicy
          { nativeKeepPaths = keptNativeIntermediatePaths sourcePath
          , nativeKeepExecutable = Nothing
          }
  | otherwise =
      Nothing

handleCompileOutput :: FilePath -> CompileCLIOptions -> CompiledLLVMOutput -> IO ()
handleCompileOutput sourcePath cliOptions result = do
  emitCompileWarnings result
  emitDumpArtifacts (cliDumpOptions cliOptions) (compiledDumpArtifacts result)
  case cliOutputMode cliOptions of
    EmitLLVM maybePath -> do
      when (cliKeepIntermediates cliOptions) $
        writeKeptLLVMIntermediate sourcePath result
      emitLLVMOutput maybePath result
    EmitAndRunLLVM maybePath -> do
      when (cliKeepIntermediates cliOptions) $
        writeKeptLLVMIntermediate sourcePath result
      emitLLVMOutput maybePath result
      runGeneratedLLVM result
    BuildExecutable outputPath ->
      buildNativeOutputWithVerbosity True (compileNativeKeepPolicy sourcePath cliOptions) (cliLinkOptions cliOptions) outputPath result
    BuildAndRunExecutable outputPath -> do
      buildNativeOutputWithVerbosity True (compileNativeKeepPolicy sourcePath cliOptions) (cliLinkOptions cliOptions) outputPath result
      runGeneratedExecutable outputPath

emitCompileWarnings :: CompiledLLVMOutput -> IO ()
emitCompileWarnings result =
  emitWarnings (compiledWarnings result)

emitWarnings :: [Text] -> IO ()
emitWarnings warnings =
  unless (null warnings) $
    Text.IO.hPutStr stderr (Text.unlines warnings)

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

buildNativeOutputWithVerbosity :: Bool -> Maybe NativeKeepPolicy -> CompileLinkOptions -> FilePath -> CompiledLLVMOutput -> IO ()
buildNativeOutputWithVerbosity verbose keepPolicy linkOptions outputPath result = do
  ensureParentDirectory outputPath
  tools <- findLLVMTools
  nativeResult <-
    case keepPolicy of
      Nothing ->
        buildNativeExecutableWithLinkOptions
          tools
          (compiledLLVMText result)
          (nativeLinkOptionsFromCLI linkOptions)
          outputPath
      Just policy ->
        buildNativeExecutableWithIntermediatePaths
          tools
          (compiledLLVMText result)
          (nativeLinkOptionsFromCLI linkOptions)
          (nativeKeepPaths policy)
          outputPath
  case nativeResult of
    NativeBuildSucceeded -> do
      when verbose $ do
        Text.IO.hPutStrLn stderr ("wrote native executable to " <> Text.pack outputPath)
        Text.IO.hPutStrLn stderr (compiledStatus result)
      case keepPolicy of
        Nothing ->
          pure ()
        Just policy ->
          emitKeptNativeIntermediates policy
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
      unless (null stdoutText) $
        Text.IO.putStr (Text.pack stdoutText)
      unless (null stderrText) $
        Text.IO.hPutStr stderr (Text.pack stderrText)
      Text.IO.hPutStrLn stderr ("native executable exited with " <> renderExitCode code)
      exitWith code
    NativeRunIOError message -> do
      Text.IO.hPutStrLn stderr ("native executable run I/O error: " <> Text.pack message)
      exitFailure

renderExitCode :: ExitCode -> Text
renderExitCode = \case
  ExitSuccess ->
    "exit 0"
  ExitFailure code ->
    "exit " <> Text.pack (show code)

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

withTemporaryExecutable :: (FilePath -> IO a) -> IO a
withTemporaryExecutable action = do
  tempDir <- getTemporaryDirectory
  (outputPath, handle) <- openTempFile tempDir "hegglog-run"
  hClose handle
  action outputPath `finally` removeFileIfExists outputPath

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = do
  result <- try (removeFile path) :: IO (Either IOException ())
  case result of
    Left _ -> pure ()
    Right () -> pure ()
