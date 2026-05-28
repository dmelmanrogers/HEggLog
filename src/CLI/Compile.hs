module CLI.Compile
  ( CheckCLIOptions (..)
  , CompileCLIOptions (..)
  , CompileLinkOptions (..)
  , CompileOutputMode (..)
  , DumpCLIOptions (..)
  , EmitCoreCLIOptions (..)
  , EmitCoreSelection (..)
  , EmitSTGCLIOptions (..)
  , ReportCLIOptions (..)
  , RunCLIOptions (..)
  , defaultReportCLIOptions
  , emptyCompileLinkOptions
  , emptyDumpCLIOptions
  , dumpOptionsEnabled
  , parseCheckFlags
  , parseCompileFlags
  , parseEmitCoreFlags
  , parseEmitSTGFlags
  , parseReportFlags
  , parseRunFlags
  )
where

import Data.Text (Text)
import qualified Data.Text as Text

data CompileOutputMode
  = EmitLLVM (Maybe FilePath)
  | EmitAndRunLLVM (Maybe FilePath)
  | BuildExecutable FilePath
  | BuildAndRunExecutable FilePath
  deriving stock (Show, Eq, Ord)

data DumpCLIOptions = DumpCLIOptions
  { dumpCore :: Bool
  , dumpOptimizedCore :: Bool
  , dumpSTG :: Bool
  }
  deriving stock (Show, Eq, Ord)

data CompileCLIOptions = CompileCLIOptions
  { cliOutputMode :: CompileOutputMode
  , cliUseEgglog :: Bool
  , cliStrictEgglog :: Bool
  , cliImportPaths :: [FilePath]
  , cliLinkOptions :: CompileLinkOptions
  , cliDumpOptions :: DumpCLIOptions
  , cliKeepIntermediates :: Bool
  }
  deriving stock (Show, Eq, Ord)

data CheckCLIOptions = CheckCLIOptions
  { checkUseEgglog :: Bool
  , checkStrictEgglog :: Bool
  , checkImportPaths :: [FilePath]
  , checkDumpOptions :: DumpCLIOptions
  }
  deriving stock (Show, Eq, Ord)

data EmitCoreSelection
  = EmitCoreOptimized
  | EmitCoreOriginal
  | EmitCoreBoth
  deriving stock (Show, Eq, Ord)

data EmitCoreCLIOptions = EmitCoreCLIOptions
  { emitCoreUseEgglog :: Bool
  , emitCoreStrictEgglog :: Bool
  , emitCoreImportPaths :: [FilePath]
  , emitCoreOutput :: Maybe FilePath
  , emitCoreSelection :: EmitCoreSelection
  }
  deriving stock (Show, Eq, Ord)

data EmitSTGCLIOptions = EmitSTGCLIOptions
  { emitSTGUseEgglog :: Bool
  , emitSTGStrictEgglog :: Bool
  , emitSTGImportPaths :: [FilePath]
  , emitSTGOutput :: Maybe FilePath
  }
  deriving stock (Show, Eq, Ord)

data ReportCLIOptions = ReportCLIOptions
  { reportUseEgglog :: Bool
  , reportStrictEgglog :: Bool
  , reportImportPaths :: [FilePath]
  }
  deriving stock (Show, Eq, Ord)

data RunCLIOptions = RunCLIOptions
  { runUseEgglog :: Bool
  , runStrictEgglog :: Bool
  , runImportPaths :: [FilePath]
  , runLinkOptions :: CompileLinkOptions
  , runDumpOptions :: DumpCLIOptions
  , runKeepIntermediates :: Bool
  }
  deriving stock (Show, Eq, Ord)

data CompileLinkOptions = CompileLinkOptions
  { cliLinkObjects :: [FilePath]
  , cliLinkLibraries :: [String]
  , cliLinkLibraryPaths :: [FilePath]
  , cliLinkFrameworks :: [String]
  }
  deriving stock (Show, Eq, Ord)

emptyCompileLinkOptions :: CompileLinkOptions
emptyCompileLinkOptions =
  CompileLinkOptions
    { cliLinkObjects = []
    , cliLinkLibraries = []
    , cliLinkLibraryPaths = []
    , cliLinkFrameworks = []
    }

emptyDumpCLIOptions :: DumpCLIOptions
emptyDumpCLIOptions =
  DumpCLIOptions
    { dumpCore = False
    , dumpOptimizedCore = False
    , dumpSTG = False
    }

defaultReportCLIOptions :: ReportCLIOptions
defaultReportCLIOptions =
  ReportCLIOptions
    { reportUseEgglog = True
    , reportStrictEgglog = False
    , reportImportPaths = []
    }

dumpOptionsEnabled :: DumpCLIOptions -> Bool
dumpOptionsEnabled options =
  dumpCore options || dumpOptimizedCore options || dumpSTG options

parseCheckFlags :: [String] -> Either Text CheckCLIOptions
parseCheckFlags flags = do
  parsed <- go defaultCheckFlagState flags
  validateEgglogFlags (checkFlagUseEgglog parsed) (checkFlagStrictEgglog parsed)
  pure
    CheckCLIOptions
      { checkUseEgglog = checkFlagUseEgglog parsed
      , checkStrictEgglog = checkFlagStrictEgglog parsed
      , checkImportPaths = checkFlagImportPaths parsed
      , checkDumpOptions = checkFlagDumpOptions parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--no-egglog" : rest ->
      go options {checkFlagUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {checkFlagStrictEgglog = True} rest
    "-i" : importPath : rest ->
      go (addCheckImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addCheckImportPath importPath options) rest
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    flag : rest
      | Just dumpOptions <- setDumpOption flag (checkFlagDumpOptions options) ->
          go options {checkFlagDumpOptions = dumpOptions} rest
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addCheckImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addCheckImportPath (Text.unpack importPath) options) rest
      | isNativeLinkFlag flag ->
          Left (Text.pack flag <> " is not valid for check; check does not link native code")
      | flag == "--keep-intermediates" ->
          Left "--keep-intermediates is not valid for check; check does not generate native intermediates"
      | flag `elem` ["--emit-llvm", "--run", "--run-llvm", "-o", "--output"] ->
          Left (Text.pack flag <> " is not valid for check; use compile or run for output-producing commands")
      | otherwise ->
          Left ("unknown check option: " <> Text.pack flag)

parseEmitCoreFlags :: [String] -> Either Text EmitCoreCLIOptions
parseEmitCoreFlags flags = do
  parsed <- go defaultEmitCoreFlagState flags
  validateEgglogFlags (emitCoreFlagUseEgglog parsed) (emitCoreFlagStrictEgglog parsed)
  pure
    EmitCoreCLIOptions
      { emitCoreUseEgglog = emitCoreFlagUseEgglog parsed
      , emitCoreStrictEgglog = emitCoreFlagStrictEgglog parsed
      , emitCoreImportPaths = emitCoreFlagImportPaths parsed
      , emitCoreOutput = emitCoreFlagOutput parsed
      , emitCoreSelection = emitCoreFlagSelection parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--no-egglog" : rest ->
      go options {emitCoreFlagUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {emitCoreFlagStrictEgglog = True} rest
    "--original" : rest ->
      setEmitCoreSelection "--original" EmitCoreOriginal options >>= \next -> go next rest
    "--optimized" : rest ->
      setEmitCoreSelection "--optimized" EmitCoreOptimized options >>= \next -> go next rest
    "--both" : rest ->
      setEmitCoreSelection "--both" EmitCoreBoth options >>= \next -> go next rest
    "-o" : output : rest ->
      setEmitCoreOutput "-o" output options >>= \next -> go next rest
    "--output" : output : rest ->
      setEmitCoreOutput "--output" output options >>= \next -> go next rest
    "-i" : importPath : rest ->
      go (addEmitCoreImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addEmitCoreImportPath importPath options) rest
    "-o" : [] ->
      Left "-o requires a file path"
    "--output" : [] ->
      Left "--output requires a file path"
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    flag : rest
      | isDumpFlag flag ->
          Left (Text.pack flag <> " is not valid for emit-core; emit-core is already an IR output command")
      | flag == "--keep-intermediates" ->
          Left "--keep-intermediates is not valid for emit-core; emit-core does not generate native intermediates"
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addEmitCoreImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addEmitCoreImportPath (Text.unpack importPath) options) rest
      | Just output <- Text.stripPrefix "--output=" (Text.pack flag) ->
          if Text.null output
            then Left "--output requires a file path"
            else setEmitCoreOutput "--output" (Text.unpack output) options >>= \next -> go next rest
      | isNativeLinkFlag flag ->
          Left (Text.pack flag <> " is not valid for emit-core; emit-core does not link native code")
      | flag `elem` ["--emit-llvm", "--run", "--run-llvm"] ->
          Left (Text.pack flag <> " is not valid for emit-core; use compile or run for codegen output modes")
      | otherwise ->
          Left ("unknown emit-core option: " <> Text.pack flag)

parseEmitSTGFlags :: [String] -> Either Text EmitSTGCLIOptions
parseEmitSTGFlags flags = do
  parsed <- go defaultEmitSTGFlagState flags
  validateEgglogFlags (emitSTGFlagUseEgglog parsed) (emitSTGFlagStrictEgglog parsed)
  pure
    EmitSTGCLIOptions
      { emitSTGUseEgglog = emitSTGFlagUseEgglog parsed
      , emitSTGStrictEgglog = emitSTGFlagStrictEgglog parsed
      , emitSTGImportPaths = emitSTGFlagImportPaths parsed
      , emitSTGOutput = emitSTGFlagOutput parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--no-egglog" : rest ->
      go options {emitSTGFlagUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {emitSTGFlagStrictEgglog = True} rest
    "-o" : output : rest ->
      setEmitSTGOutput "-o" output options >>= \next -> go next rest
    "--output" : output : rest ->
      setEmitSTGOutput "--output" output options >>= \next -> go next rest
    "-i" : importPath : rest ->
      go (addEmitSTGImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addEmitSTGImportPath importPath options) rest
    "-o" : [] ->
      Left "-o requires a file path"
    "--output" : [] ->
      Left "--output requires a file path"
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    flag : rest
      | isDumpFlag flag ->
          Left (Text.pack flag <> " is not valid for emit-stg; emit-stg is already an IR output command")
      | flag == "--keep-intermediates" ->
          Left "--keep-intermediates is not valid for emit-stg; emit-stg does not generate native intermediates"
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addEmitSTGImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addEmitSTGImportPath (Text.unpack importPath) options) rest
      | Just output <- Text.stripPrefix "--output=" (Text.pack flag) ->
          if Text.null output
            then Left "--output requires a file path"
            else setEmitSTGOutput "--output" (Text.unpack output) options >>= \next -> go next rest
      | isNativeLinkFlag flag ->
          Left (Text.pack flag <> " is not valid for emit-stg; emit-stg does not link native code")
      | flag `elem` ["--emit-llvm", "--run", "--run-llvm"] ->
          Left (Text.pack flag <> " is not valid for emit-stg; use compile or run for codegen output modes")
      | flag `elem` ["--original", "--optimized", "--both"] ->
          Left (Text.pack flag <> " is not valid for emit-stg; use emit-core for Core selection")
      | otherwise ->
          Left ("unknown emit-stg option: " <> Text.pack flag)

parseReportFlags :: [String] -> Either Text ReportCLIOptions
parseReportFlags flags = do
  parsed <- go defaultReportCLIOptions flags
  validateEgglogFlags (reportUseEgglog parsed) (reportStrictEgglog parsed)
  pure parsed
 where
  go options = \case
    [] ->
      Right options
    "--no-egglog" : rest ->
      go options {reportUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {reportStrictEgglog = True} rest
    "-i" : importPath : rest ->
      go (addReportImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addReportImportPath importPath options) rest
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    flag : rest
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addReportImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addReportImportPath (Text.unpack importPath) options) rest
      | isDumpFlag flag ->
          Left (Text.pack flag <> " is not valid for report; report emits its own diagnostic sections")
      | flag == "--keep-intermediates" ->
          Left "--keep-intermediates is not valid for report; report does not generate native intermediates"
      | isNativeLinkFlag flag ->
          Left (Text.pack flag <> " is not valid for report; report does not link native code")
      | flag `elem` ["--emit-llvm", "--run", "--run-llvm", "-o", "--output"] ->
          Left (Text.pack flag <> " is not valid for report; use compile or run for output-producing commands")
      | flag `elem` ["--original", "--optimized", "--both"] ->
          Left (Text.pack flag <> " is not valid for report; report includes the available diagnostic IR sections")
      | not ("-" `Text.isPrefixOf` Text.pack flag) ->
          Left "report accepts exactly one source file"
      | otherwise ->
          Left ("unknown report option: " <> Text.pack flag)

parseRunFlags :: [String] -> Either Text RunCLIOptions
parseRunFlags flags = do
  parsed <- go defaultRunFlagState flags
  validateEgglogFlags (runFlagUseEgglog parsed) (runFlagStrictEgglog parsed)
  pure
    RunCLIOptions
      { runUseEgglog = runFlagUseEgglog parsed
      , runStrictEgglog = runFlagStrictEgglog parsed
      , runImportPaths = runFlagImportPaths parsed
      , runLinkOptions = runFlagLinkOptions parsed
      , runDumpOptions = runFlagDumpOptions parsed
      , runKeepIntermediates = runFlagKeepIntermediates parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--no-egglog" : rest ->
      go options {runFlagUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {runFlagStrictEgglog = True} rest
    "--keep-intermediates" : rest ->
      go options {runFlagKeepIntermediates = True} rest
    "-i" : importPath : rest ->
      go (addRunImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addRunImportPath importPath options) rest
    "--link-object" : objectPath : rest ->
      go (addRunLinkObject objectPath options) rest
    "--link-library" : libraryName : rest ->
      go (addRunLinkLibrary libraryName options) rest
    "--library-path" : libraryPath : rest ->
      go (addRunLibraryPath libraryPath options) rest
    "--framework" : framework : rest ->
      go (addRunFramework framework options) rest
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    "--link-object" : [] ->
      Left "--link-object requires a file path"
    "--link-library" : [] ->
      Left "--link-library requires a library name"
    "--library-path" : [] ->
      Left "--library-path requires a directory path"
    "--framework" : [] ->
      Left "--framework requires a framework name"
    flag : rest
      | Just dumpOptions <- setDumpOption flag (runFlagDumpOptions options) ->
          go options {runFlagDumpOptions = dumpOptions} rest
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addRunImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addRunImportPath (Text.unpack importPath) options) rest
      | flag `elem` ["--emit-llvm", "--run-llvm"] ->
          Left (Text.pack flag <> " is not valid for run; use compile for LLVM output modes")
      | flag == "--run" ->
          Left "--run is redundant for the run command"
      | flag `elem` ["-o", "--output"] ->
          Left (Text.pack flag <> " is not valid for run; run uses a temporary native executable")
      | otherwise ->
          Left ("unknown run option: " <> Text.pack flag)

data CompileFlagState = CompileFlagState
  { flagOutput :: Maybe FilePath
  , flagEmitLLVM :: Bool
  , flagUseEgglog :: Bool
  , flagStrictEgglog :: Bool
  , flagRunLLVM :: Bool
  , flagRunNative :: Bool
  , flagImportPaths :: [FilePath]
  , flagLinkOptions :: CompileLinkOptions
  , flagDumpOptions :: DumpCLIOptions
  , flagKeepIntermediates :: Bool
  }
  deriving stock (Show, Eq, Ord)

data CheckFlagState = CheckFlagState
  { checkFlagUseEgglog :: Bool
  , checkFlagStrictEgglog :: Bool
  , checkFlagImportPaths :: [FilePath]
  , checkFlagDumpOptions :: DumpCLIOptions
  }
  deriving stock (Show, Eq, Ord)

data EmitCoreFlagState = EmitCoreFlagState
  { emitCoreFlagUseEgglog :: Bool
  , emitCoreFlagStrictEgglog :: Bool
  , emitCoreFlagImportPaths :: [FilePath]
  , emitCoreFlagOutput :: Maybe FilePath
  , emitCoreFlagSelection :: EmitCoreSelection
  , emitCoreFlagSelectionExplicit :: Maybe Text
  }
  deriving stock (Show, Eq, Ord)

data EmitSTGFlagState = EmitSTGFlagState
  { emitSTGFlagUseEgglog :: Bool
  , emitSTGFlagStrictEgglog :: Bool
  , emitSTGFlagImportPaths :: [FilePath]
  , emitSTGFlagOutput :: Maybe FilePath
  }
  deriving stock (Show, Eq, Ord)

data RunFlagState = RunFlagState
  { runFlagUseEgglog :: Bool
  , runFlagStrictEgglog :: Bool
  , runFlagImportPaths :: [FilePath]
  , runFlagLinkOptions :: CompileLinkOptions
  , runFlagDumpOptions :: DumpCLIOptions
  , runFlagKeepIntermediates :: Bool
  }
  deriving stock (Show, Eq, Ord)

parseCompileFlags :: [String] -> Either Text CompileCLIOptions
parseCompileFlags flags = do
  parsed <- go defaultCompileFlagState flags
  validateEgglogFlags (flagUseEgglog parsed) (flagStrictEgglog parsed)
  mode <- selectOutputMode parsed
  pure
    CompileCLIOptions
      { cliOutputMode = mode
      , cliUseEgglog = flagUseEgglog parsed
      , cliStrictEgglog = flagStrictEgglog parsed
      , cliImportPaths = flagImportPaths parsed
      , cliLinkOptions = flagLinkOptions parsed
      , cliDumpOptions = flagDumpOptions parsed
      , cliKeepIntermediates = flagKeepIntermediates parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--emit-llvm" : rest ->
      go options {flagEmitLLVM = True} rest
    "--no-egglog" : rest ->
      go options {flagUseEgglog = False} rest
    "--strict-egglog" : rest ->
      go options {flagStrictEgglog = True} rest
    "--keep-intermediates" : rest ->
      go options {flagKeepIntermediates = True} rest
    "--run-llvm" : rest ->
      go options {flagRunLLVM = True} rest
    "--run" : rest ->
      go options {flagRunNative = True} rest
    "-o" : output : rest ->
      setOutput "-o" output options >>= \next -> go next rest
    "--output" : output : rest ->
      setOutput "--output" output options >>= \next -> go next rest
    "-i" : importPath : rest ->
      go (addImportPath importPath options) rest
    "--import-path" : importPath : rest ->
      go (addImportPath importPath options) rest
    "--link-object" : objectPath : rest ->
      go (addLinkObject objectPath options) rest
    "--link-library" : libraryName : rest ->
      go (addLinkLibrary libraryName options) rest
    "--library-path" : libraryPath : rest ->
      go (addLibraryPath libraryPath options) rest
    "--framework" : framework : rest ->
      go (addFramework framework options) rest
    "-i" : [] ->
      Left "-i requires a directory path"
    "--import-path" : [] ->
      Left "--import-path requires a directory path"
    "-o" : [] ->
      Left "-o requires a file path"
    "--output" : [] ->
      Left "--output requires a file path"
    "--link-object" : [] ->
      Left "--link-object requires a file path"
    "--link-library" : [] ->
      Left "--link-library requires a library name"
    "--library-path" : [] ->
      Left "--library-path requires a directory path"
    "--framework" : [] ->
      Left "--framework requires a framework name"
    flag : rest
      | Just dumpOptions <- setDumpOption flag (flagDumpOptions options) ->
          go options {flagDumpOptions = dumpOptions} rest
      | Just importPath <- Text.stripPrefix "-i" (Text.pack flag) ->
          if Text.null importPath
            then Left "-i requires a directory path"
            else go (addImportPath (Text.unpack importPath) options) rest
      | Just importPath <- Text.stripPrefix "--import-path=" (Text.pack flag) ->
          if Text.null importPath
            then Left "--import-path requires a directory path"
            else go (addImportPath (Text.unpack importPath) options) rest
      | otherwise ->
          Left ("unknown compile option: " <> Text.pack flag)

defaultCompileFlagState :: CompileFlagState
defaultCompileFlagState =
  CompileFlagState
    { flagOutput = Nothing
    , flagEmitLLVM = False
    , flagUseEgglog = True
    , flagStrictEgglog = False
    , flagRunLLVM = False
    , flagRunNative = False
    , flagImportPaths = []
    , flagLinkOptions = emptyCompileLinkOptions
    , flagDumpOptions = emptyDumpCLIOptions
    , flagKeepIntermediates = False
    }

defaultCheckFlagState :: CheckFlagState
defaultCheckFlagState =
  CheckFlagState
    { checkFlagUseEgglog = True
    , checkFlagStrictEgglog = False
    , checkFlagImportPaths = []
    , checkFlagDumpOptions = emptyDumpCLIOptions
    }

defaultEmitCoreFlagState :: EmitCoreFlagState
defaultEmitCoreFlagState =
  EmitCoreFlagState
    { emitCoreFlagUseEgglog = True
    , emitCoreFlagStrictEgglog = False
    , emitCoreFlagImportPaths = []
    , emitCoreFlagOutput = Nothing
    , emitCoreFlagSelection = EmitCoreOptimized
    , emitCoreFlagSelectionExplicit = Nothing
    }

defaultEmitSTGFlagState :: EmitSTGFlagState
defaultEmitSTGFlagState =
  EmitSTGFlagState
    { emitSTGFlagUseEgglog = True
    , emitSTGFlagStrictEgglog = False
    , emitSTGFlagImportPaths = []
    , emitSTGFlagOutput = Nothing
    }

defaultRunFlagState :: RunFlagState
defaultRunFlagState =
  RunFlagState
    { runFlagUseEgglog = True
    , runFlagStrictEgglog = False
    , runFlagImportPaths = []
    , runFlagLinkOptions = emptyCompileLinkOptions
    , runFlagDumpOptions = emptyDumpCLIOptions
    , runFlagKeepIntermediates = False
    }

addImportPath :: FilePath -> CompileFlagState -> CompileFlagState
addImportPath importPath options =
  options {flagImportPaths = flagImportPaths options <> [importPath]}

addCheckImportPath :: FilePath -> CheckFlagState -> CheckFlagState
addCheckImportPath importPath options =
  options {checkFlagImportPaths = checkFlagImportPaths options <> [importPath]}

addEmitCoreImportPath :: FilePath -> EmitCoreFlagState -> EmitCoreFlagState
addEmitCoreImportPath importPath options =
  options {emitCoreFlagImportPaths = emitCoreFlagImportPaths options <> [importPath]}

addEmitSTGImportPath :: FilePath -> EmitSTGFlagState -> EmitSTGFlagState
addEmitSTGImportPath importPath options =
  options {emitSTGFlagImportPaths = emitSTGFlagImportPaths options <> [importPath]}

addReportImportPath :: FilePath -> ReportCLIOptions -> ReportCLIOptions
addReportImportPath importPath options =
  options {reportImportPaths = reportImportPaths options <> [importPath]}

addRunImportPath :: FilePath -> RunFlagState -> RunFlagState
addRunImportPath importPath options =
  options {runFlagImportPaths = runFlagImportPaths options <> [importPath]}

addLinkObject :: FilePath -> CompileFlagState -> CompileFlagState
addLinkObject objectPath =
  overLinkOptions $ \linkOptions ->
    linkOptions {cliLinkObjects = cliLinkObjects linkOptions <> [objectPath]}

addLinkLibrary :: String -> CompileFlagState -> CompileFlagState
addLinkLibrary libraryName =
  overLinkOptions $ \linkOptions ->
    linkOptions {cliLinkLibraries = cliLinkLibraries linkOptions <> [libraryName]}

addLibraryPath :: FilePath -> CompileFlagState -> CompileFlagState
addLibraryPath libraryPath =
  overLinkOptions $ \linkOptions ->
    linkOptions {cliLinkLibraryPaths = cliLinkLibraryPaths linkOptions <> [libraryPath]}

addFramework :: String -> CompileFlagState -> CompileFlagState
addFramework framework =
  overLinkOptions $ \linkOptions ->
    linkOptions {cliLinkFrameworks = cliLinkFrameworks linkOptions <> [framework]}

overLinkOptions :: (CompileLinkOptions -> CompileLinkOptions) -> CompileFlagState -> CompileFlagState
overLinkOptions update options =
  options {flagLinkOptions = update (flagLinkOptions options)}

addRunLinkObject :: FilePath -> RunFlagState -> RunFlagState
addRunLinkObject objectPath =
  overRunLinkOptions $ \linkOptions ->
    linkOptions {cliLinkObjects = cliLinkObjects linkOptions <> [objectPath]}

addRunLinkLibrary :: String -> RunFlagState -> RunFlagState
addRunLinkLibrary libraryName =
  overRunLinkOptions $ \linkOptions ->
    linkOptions {cliLinkLibraries = cliLinkLibraries linkOptions <> [libraryName]}

addRunLibraryPath :: FilePath -> RunFlagState -> RunFlagState
addRunLibraryPath libraryPath =
  overRunLinkOptions $ \linkOptions ->
    linkOptions {cliLinkLibraryPaths = cliLinkLibraryPaths linkOptions <> [libraryPath]}

addRunFramework :: String -> RunFlagState -> RunFlagState
addRunFramework framework =
  overRunLinkOptions $ \linkOptions ->
    linkOptions {cliLinkFrameworks = cliLinkFrameworks linkOptions <> [framework]}

overRunLinkOptions :: (CompileLinkOptions -> CompileLinkOptions) -> RunFlagState -> RunFlagState
overRunLinkOptions update options =
  options {runFlagLinkOptions = update (runFlagLinkOptions options)}

setOutput :: Text -> FilePath -> CompileFlagState -> Either Text CompileFlagState
setOutput flag output options =
  case flagOutput options of
    Nothing ->
      Right options {flagOutput = Just output}
    Just {} ->
      Left (flag <> " was provided more than once")

setEmitCoreOutput :: Text -> FilePath -> EmitCoreFlagState -> Either Text EmitCoreFlagState
setEmitCoreOutput flag output options =
  case emitCoreFlagOutput options of
    Nothing ->
      Right options {emitCoreFlagOutput = Just output}
    Just {} ->
      Left (flag <> " was provided more than once")

setEmitSTGOutput :: Text -> FilePath -> EmitSTGFlagState -> Either Text EmitSTGFlagState
setEmitSTGOutput flag output options =
  case emitSTGFlagOutput options of
    Nothing ->
      Right options {emitSTGFlagOutput = Just output}
    Just {} ->
      Left (flag <> " was provided more than once")

setEmitCoreSelection ::
  Text ->
  EmitCoreSelection ->
  EmitCoreFlagState ->
  Either Text EmitCoreFlagState
setEmitCoreSelection flag selection options =
  case emitCoreFlagSelectionExplicit options of
    Nothing ->
      Right
        options
          { emitCoreFlagSelection = selection
          , emitCoreFlagSelectionExplicit = Just flag
          }
    Just previous ->
      Left (flag <> " cannot be combined with " <> previous)

selectOutputMode :: CompileFlagState -> Either Text CompileOutputMode
selectOutputMode options
  | flagRunLLVM options && flagRunNative options =
      Left "--run and --run-llvm cannot be combined"
  | flagRunNative options && flagEmitLLVM options =
      Left "--run builds and runs a native executable; use --run-llvm with --emit-llvm"
  | flagEmitLLVM options && flagRunLLVM options =
      Right (EmitAndRunLLVM (flagOutput options))
  | flagEmitLLVM options =
      Right (EmitLLVM (flagOutput options))
  | flagRunLLVM options =
      Right (EmitAndRunLLVM (flagOutput options))
  | flagRunNative options =
      case flagOutput options of
        Just output -> Right (BuildAndRunExecutable output)
        Nothing -> Left "--run requires -o/--output for native executable output; use --run-llvm to run generated LLVM without an executable"
  | otherwise =
      case flagOutput options of
        Just output -> Right (BuildExecutable output)
        Nothing -> Right (EmitLLVM Nothing)

isNativeLinkFlag :: String -> Bool
isNativeLinkFlag flag =
  flag `elem` ["--link-object", "--link-library", "--library-path", "--framework"]

isDumpFlag :: String -> Bool
isDumpFlag flag =
  flag `elem` ["--dump-core", "--dump-optimized-core", "--dump-stg"]

setDumpOption :: String -> DumpCLIOptions -> Maybe DumpCLIOptions
setDumpOption flag options =
  case flag of
    "--dump-core" ->
      Just options {dumpCore = True}
    "--dump-optimized-core" ->
      Just options {dumpOptimizedCore = True}
    "--dump-stg" ->
      Just options {dumpSTG = True}
    _ ->
      Nothing

validateEgglogFlags :: Bool -> Bool -> Either Text ()
validateEgglogFlags useEgglog strictEgglog
  | not useEgglog && strictEgglog =
      Left "--strict-egglog cannot be combined with --no-egglog"
  | otherwise =
      Right ()
