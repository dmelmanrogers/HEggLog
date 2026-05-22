module CLI.Compile
  ( CompileCLIOptions (..)
  , CompileLinkOptions (..)
  , CompileOutputMode (..)
  , emptyCompileLinkOptions
  , parseCompileFlags
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

data CompileCLIOptions = CompileCLIOptions
  { cliOutputMode :: CompileOutputMode
  , cliUseEgglog :: Bool
  , cliLinkOptions :: CompileLinkOptions
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

data CompileFlagState = CompileFlagState
  { flagOutput :: Maybe FilePath
  , flagEmitLLVM :: Bool
  , flagUseEgglog :: Bool
  , flagRunLLVM :: Bool
  , flagRunNative :: Bool
  , flagLinkOptions :: CompileLinkOptions
  }
  deriving stock (Show, Eq, Ord)

parseCompileFlags :: [String] -> Either Text CompileCLIOptions
parseCompileFlags flags = do
  parsed <- go defaultCompileFlagState flags
  mode <- selectOutputMode parsed
  pure
    CompileCLIOptions
      { cliOutputMode = mode
      , cliUseEgglog = flagUseEgglog parsed
      , cliLinkOptions = flagLinkOptions parsed
      }
 where
  go options = \case
    [] ->
      Right options
    "--emit-llvm" : rest ->
      go options {flagEmitLLVM = True} rest
    "--no-egglog" : rest ->
      go options {flagUseEgglog = False} rest
    "--run-llvm" : rest ->
      go options {flagRunLLVM = True} rest
    "--run" : rest ->
      go options {flagRunNative = True} rest
    "-o" : output : rest ->
      setOutput "-o" output options >>= \next -> go next rest
    "--output" : output : rest ->
      setOutput "--output" output options >>= \next -> go next rest
    "--link-object" : objectPath : rest ->
      go (addLinkObject objectPath options) rest
    "--link-library" : libraryName : rest ->
      go (addLinkLibrary libraryName options) rest
    "--library-path" : libraryPath : rest ->
      go (addLibraryPath libraryPath options) rest
    "--framework" : framework : rest ->
      go (addFramework framework options) rest
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
    flag : _ ->
      Left ("unknown compile option: " <> Text.pack flag)

defaultCompileFlagState :: CompileFlagState
defaultCompileFlagState =
  CompileFlagState
    { flagOutput = Nothing
    , flagEmitLLVM = False
    , flagUseEgglog = True
    , flagRunLLVM = False
    , flagRunNative = False
    , flagLinkOptions = emptyCompileLinkOptions
    }

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

setOutput :: Text -> FilePath -> CompileFlagState -> Either Text CompileFlagState
setOutput flag output options =
  case flagOutput options of
    Nothing ->
      Right options {flagOutput = Just output}
    Just {} ->
      Left (flag <> " was provided more than once")

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
