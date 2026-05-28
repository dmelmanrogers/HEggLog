module CLI.Command
  ( CLICommand (..)
  , CLICommandError (..)
  , CLIUsageTopic (..)
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
where

import CLI.Compile
  ( CheckCLIOptions
  , CompileCLIOptions
  , EmitCoreCLIOptions
  , EmitSTGCLIOptions
  , ReportCLIOptions
  , RunCLIOptions
  , defaultReportCLIOptions
  , parseCheckFlags
  , parseCompileFlags
  , parseEmitCoreFlags
  , parseEmitSTGFlags
  , parseReportFlags
  , parseRunFlags
  )
import Data.Text (Text)
import qualified Data.Text as Text

data CLICommand
  = CommandGeneralHelp
  | CommandCheckHelp
  | CommandCompileHelp
  | CommandEmitCoreHelp
  | CommandEmitSTGHelp
  | CommandReportHelp
  | CommandRunHelp
  | CommandCheck FilePath CheckCLIOptions
  | CommandCompile FilePath CompileCLIOptions
  | CommandEmitCore FilePath EmitCoreCLIOptions
  | CommandEmitSTG FilePath EmitSTGCLIOptions
  | CommandReport FilePath ReportCLIOptions
  | CommandRun FilePath RunCLIOptions
  deriving stock (Show, Eq, Ord)

data CLIUsageTopic
  = GeneralUsage
  | CheckUsage
  | CompileUsage
  | EmitCoreUsage
  | EmitSTGUsage
  | ReportUsage
  | RunUsage
  deriving stock (Show, Eq, Ord)

data CLICommandError = CLICommandError
  { commandErrorMessage :: Text
  , commandErrorUsageTopic :: CLIUsageTopic
  }
  deriving stock (Show, Eq, Ord)

parseCLICommand :: [String] -> Either CLICommandError CLICommand
parseCLICommand = \case
  [] ->
    Left (CLICommandError "missing command or source file" GeneralUsage)
  ["--help"] ->
    Right CommandGeneralHelp
  ["-h"] ->
    Right CommandGeneralHelp
  ["help"] ->
    Right CommandGeneralHelp
  "check" : rest ->
    parseCheckCommand rest
  "compile" : rest ->
    parseCompileCommand rest
  "emit-core" : rest ->
    parseEmitCoreCommand rest
  "emit-stg" : rest ->
    parseEmitSTGCommand rest
  "report" : rest ->
    parseReportCommand rest
  "run" : rest ->
    parseRunCommand rest
  [path] ->
    Right (CommandReport path defaultReportCLIOptions)
  path : flags
    | "--emit-llvm" `elem` flags ->
        parseCompileCommand (path : flags)
  command : _ ->
    Left (CLICommandError ("unknown command or unsupported file invocation: " <> Text.pack command) GeneralUsage)

parseCheckCommand :: [String] -> Either CLICommandError CLICommand
parseCheckCommand = \case
  [] ->
    Left (CLICommandError "check requires a source file" CheckUsage)
  ["--help"] ->
    Right CommandCheckHelp
  ["-h"] ->
    Right CommandCheckHelp
  path : flags ->
    case parseCheckFlags flags of
      Left err ->
        Left (CLICommandError err CheckUsage)
      Right options ->
        Right (CommandCheck path options)

parseCompileCommand :: [String] -> Either CLICommandError CLICommand
parseCompileCommand = \case
  [] ->
    Left (CLICommandError "compile requires a source file" CompileUsage)
  ["--help"] ->
    Right CommandCompileHelp
  ["-h"] ->
    Right CommandCompileHelp
  path : flags ->
    case parseCompileFlags flags of
      Left err ->
        Left (CLICommandError err CompileUsage)
      Right options ->
        Right (CommandCompile path options)

parseEmitCoreCommand :: [String] -> Either CLICommandError CLICommand
parseEmitCoreCommand = \case
  [] ->
    Left (CLICommandError "emit-core requires a source file" EmitCoreUsage)
  ["--help"] ->
    Right CommandEmitCoreHelp
  ["-h"] ->
    Right CommandEmitCoreHelp
  path : flags ->
    case parseEmitCoreFlags flags of
      Left err ->
        Left (CLICommandError err EmitCoreUsage)
      Right options ->
        Right (CommandEmitCore path options)

parseEmitSTGCommand :: [String] -> Either CLICommandError CLICommand
parseEmitSTGCommand = \case
  [] ->
    Left (CLICommandError "emit-stg requires a source file" EmitSTGUsage)
  ["--help"] ->
    Right CommandEmitSTGHelp
  ["-h"] ->
    Right CommandEmitSTGHelp
  path : flags ->
    case parseEmitSTGFlags flags of
      Left err ->
        Left (CLICommandError err EmitSTGUsage)
      Right options ->
        Right (CommandEmitSTG path options)

parseReportCommand :: [String] -> Either CLICommandError CLICommand
parseReportCommand = \case
  [] ->
    Left (CLICommandError "report requires a source file" ReportUsage)
  ["--help"] ->
    Right CommandReportHelp
  ["-h"] ->
    Right CommandReportHelp
  path : flags ->
    case parseReportFlags flags of
      Left err ->
        Left (CLICommandError err ReportUsage)
      Right options ->
        Right (CommandReport path options)

parseRunCommand :: [String] -> Either CLICommandError CLICommand
parseRunCommand = \case
  [] ->
    Left (CLICommandError "run requires a source file" RunUsage)
  ["--help"] ->
    Right CommandRunHelp
  ["-h"] ->
    Right CommandRunHelp
  path : flags ->
    case parseRunFlags flags of
      Left err ->
        Left (CLICommandError err RunUsage)
      Right options ->
        Right (CommandRun path options)

usageForTopic :: CLIUsageTopic -> Text
usageForTopic = \case
  GeneralUsage -> generalUsage
  CheckUsage -> checkUsage
  CompileUsage -> compileUsage
  EmitCoreUsage -> emitCoreUsage
  EmitSTGUsage -> emitSTGUsage
  ReportUsage -> reportUsage
  RunUsage -> runUsage

generalUsage :: Text
generalUsage =
  Text.unlines
    [ "HeggLog compiler"
    , ""
    , "usage:"
    , "  hegglog FILE"
    , "  hegglog check FILE [check options]"
    , "  hegglog emit-core FILE [emit-core options]"
    , "  hegglog emit-stg FILE [emit-stg options]"
    , "  hegglog report FILE [report options]"
    , "  hegglog run FILE [run options]"
    , "  hegglog compile FILE [compile options]"
    , "  hegglog FILE --emit-llvm [compile options]"
    , ""
    , "commands:"
    , "  FILE"
    , "      Run legacy .hg report/interpreter mode for a source file."
    , "  check FILE"
    , "      Parse, typecheck, and validate a source file without LLVM or native codegen."
    , "  emit-core FILE"
    , "      Emit validated typed Haskell 2010 Core without LLVM or native codegen."
    , "  emit-stg FILE"
    , "      Emit validated Haskell 2010 STG without LLVM or native codegen."
    , "  report FILE"
    , "      Emit a diagnostic/status report for a source file."
    , "  run FILE"
    , "      Compile a source file to a temporary native executable and run it."
    , "  compile FILE -o PROGRAM"
    , "      Build a native executable with clang."
    , "  compile FILE --emit-llvm [-o FILE.ll]"
    , "      Emit textual LLVM IR."
    , ""
    , "examples:"
    , "  cabal run hegglog -- examples/test.hg"
    , "  cabal run hegglog -- check test/e2e/programs/haskell2010/lazy-argument.hs"
    , "  cabal run hegglog -- check test/e2e/programs/haskell2010/lazy-argument.hs --dump-core --dump-stg"
    , "  cabal run hegglog -- emit-core test/e2e/programs/haskell2010/lazy-argument.hs"
    , "  cabal run hegglog -- emit-stg test/e2e/programs/haskell2010/lazy-argument.hs"
    , "  cabal run hegglog -- report examples/test.hg"
    , "  cabal run hegglog -- report test/e2e/programs/haskell2010/lazy-argument.hs"
    , "  cabal run hegglog -- run test/e2e/programs/haskell2010/lazy-argument.hs"
    , "  cabal run hegglog -- run test/e2e/programs/haskell2010/lazy-argument.hs --keep-intermediates"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic --run"
    , "  cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/hegglog.ll"
    , ""
    , "run `hegglog COMMAND --help` for command-specific options."
    ]

checkUsage :: Text
checkUsage =
  Text.unlines
    [ "HeggLog check mode"
    , ""
    , "usage:"
    , "  hegglog check FILE [--no-egglog] [-i PATH] [dump options]"
    , ""
    , "behavior:"
    , "  Parse, rename, typecheck, and validate Core/STG without emitting LLVM IR, invoking clang, or requiring a `main` binding."
    , ""
    , "options:"
    , "  --no-egglog"
    , "      Check the unoptimized Core/STG path."
    , "  --strict-egglog"
    , "      Require Egglog optimization support instead of falling back to unoptimized Core/STG."
    , "  -i, --import-path PATH"
    , "      Add a Haskell 2010 source module import search directory. May be repeated; the root module directory is searched first."
    , "  --dump-core"
    , "      Write original typed Core to stderr after successful checking."
    , "  --dump-optimized-core"
    , "      Write optimized typed Core to stderr after successful checking."
    , "  --dump-stg"
    , "      Write validated STG to stderr after successful checking."
    ]

compileUsage :: Text
compileUsage =
  Text.unlines
    [ "HeggLog compile mode"
    , ""
    , "usage:"
    , "  hegglog compile FILE --emit-llvm [-o FILE.ll] [--no-egglog] [--run-llvm] [dump options]"
    , "  hegglog compile FILE -o PROGRAM [--no-egglog] [--run] [dump options]"
    , "  hegglog FILE --emit-llvm [-o FILE.ll] [--no-egglog] [--run-llvm] [dump options]"
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
    , "  --strict-egglog"
    , "      Require Egglog optimization support instead of falling back to unoptimized output."
    , "  --keep-intermediates"
    , "      Preserve generated LLVM and native object intermediates under .context/hegglog/intermediates. Native run mode also preserves its temporary executable there."
    , "  -i, --import-path PATH"
    , "      Add a source module import search directory. May be repeated; the root module directory is searched first."
    , "  --dump-core"
    , "      Write original typed Core to stderr before emitting or building the compile output."
    , "  --dump-optimized-core"
    , "      Write optimized typed Core to stderr before emitting or building the compile output."
    , "  --dump-stg"
    , "      Write validated STG to stderr before emitting or building the compile output."
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

emitCoreUsage :: Text
emitCoreUsage =
  Text.unlines
    [ "HeggLog emit-core mode"
    , ""
    , "usage:"
    , "  hegglog emit-core FILE [--no-egglog] [--original|--optimized|--both] [-i PATH] [-o PATH]"
    , ""
    , "behavior:"
    , "  Parse, rename, typecheck, optimize when enabled, and validate Core/STG; emit typed Haskell 2010 Core without LLVM or native codegen."
    , ""
    , "options:"
    , "  --original"
    , "      Emit the typechecker Core before Core optimization."
    , "  --optimized"
    , "      Emit the checked Core after Core optimization. This is the default."
    , "  --both"
    , "      Emit original and optimized Core sections."
    , "  --no-egglog"
    , "      Disable Core optimization before validation and output."
    , "  --strict-egglog"
    , "      Require Core Egglog optimization support instead of preserving unsupported fragments."
    , "  -i, --import-path PATH"
    , "      Add a Haskell 2010 source module import search directory. May be repeated; the root module directory is searched first."
    , "  -o, --output PATH"
    , "      Write Core output to PATH instead of stdout."
    ]

emitSTGUsage :: Text
emitSTGUsage =
  Text.unlines
    [ "HeggLog emit-stg mode"
    , ""
    , "usage:"
    , "  hegglog emit-stg FILE [--no-egglog] [-i PATH] [-o PATH]"
    , ""
    , "behavior:"
    , "  Parse, rename, typecheck, optimize Core when enabled, lower to STG, validate STG, and emit Haskell 2010 STG without LLVM or native codegen."
    , ""
    , "options:"
    , "  --no-egglog"
    , "      Disable Core optimization before STG lowering and output."
    , "  --strict-egglog"
    , "      Require Core Egglog optimization support before STG lowering."
    , "  -i, --import-path PATH"
    , "      Add a Haskell 2010 source module import search directory. May be repeated; the root module directory is searched first."
    , "  -o, --output PATH"
    , "      Write STG output to PATH instead of stdout."
    ]

reportUsage :: Text
reportUsage =
  Text.unlines
    [ "HeggLog report mode"
    , ""
    , "usage:"
    , "  hegglog report FILE [--no-egglog] [--strict-egglog] [-i PATH]"
    , "  hegglog FILE"
    , ""
    , "behavior:"
    , "  Emit a diagnostic/status report for a source file."
    , "  legacy .hg reports include parsed syntax, type, interpreter result, ANF, rewrites, EGraph, Egglog, and Core."
    , "  Haskell 2010 .hs reports parse, rename, typecheck, optimize according to flags, validate Core/STG, and include typed Core/STG sections."
    , ""
    , "options:"
    , "  --no-egglog"
    , "      Report the unoptimized validation path."
    , "  --strict-egglog"
    , "      Require Egglog optimization support instead of reporting a fallback path."
    , "  -i, --import-path PATH"
    , "      Add a Haskell 2010 source module import search directory. May be repeated; the root module directory is searched first."
    ]

runUsage :: Text
runUsage =
  Text.unlines
    [ "HeggLog run mode"
    , ""
    , "usage:"
    , "  hegglog run FILE [--no-egglog] [-i PATH] [dump options] [native link options]"
    , ""
    , "behavior:"
    , "  Compile FILE to a temporary native executable, run it, forward program stdout/stderr, and exit with the program status."
    , ""
    , "options:"
    , "  --no-egglog"
    , "      Compile without Egglog optimization."
    , "  --strict-egglog"
    , "      Require Egglog optimization support instead of falling back to unoptimized output."
    , "  --keep-intermediates"
    , "      Preserve generated LLVM, object, and temporary executable intermediates under .context/hegglog/intermediates."
    , "  -i, --import-path PATH"
    , "      Add a Haskell 2010 source module import search directory. May be repeated; the root module directory is searched first."
    , "  --dump-core"
    , "      Write original typed Core to stderr before running the compiled executable."
    , "  --dump-optimized-core"
    , "      Write optimized typed Core to stderr before running the compiled executable."
    , "  --dump-stg"
    , "      Write validated STG to stderr before running the compiled executable."
    , "  --link-object PATH"
    , "      Add an object file or native archive to the clang link command. May be repeated."
    , "  --link-library NAME"
    , "      Link with -lNAME. May be repeated."
    , "  --library-path PATH"
    , "      Add -LPATH to the native link command. May be repeated."
    , "  --framework NAME"
    , "      Link with a macOS framework. May be repeated."
    ]
