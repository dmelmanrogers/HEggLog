module Main (main) where

import Control.Monad (unless)
import Data.Char (isAlphaNum, toLower)
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.IO as Text.IO
import System.Directory
  ( doesFileExist
  , executable
  , findExecutable
  , getPermissions
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath ((<.>), (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.HUnit

data Expected
  = ExpectSuccess Text
  | ExpectRuntimeError
  | ExpectCompileError [Text]
  deriving stock (Show, Eq)

data EgglogMode
  = DefaultEgglog
  | NoEgglog
  deriving stock (Show, Eq, Ord)

data E2ECase = E2ECase
  { caseName :: Text
  , sourcePath :: FilePath
  , expected :: Expected
  , egglogModes :: [EgglogMode]
  , alsoEmitLLVM :: Bool
  , includeReport :: Bool
  }
  deriving stock (Show, Eq)

data CommandResult = CommandResult
  { resultExitCode :: ExitCode
  , resultStdout :: String
  , resultStderr :: String
  }
  deriving stock (Show, Eq)

main :: IO ()
main = do
  hegglog <- requireExecutable "HEGGLOG_EXE" "hegglog"
  clang <- requireExecutable "CLANG" "clang"
  putStrLn ("hegglog: " <> hegglog)
  putStrLn ("clang: " <> clang)
  counts <- pure manifestCounts
  putStrLn ("native runs: " <> show (nativeRunCount counts))
  putStrLn ("--no-egglog runs: " <> show (noEgglogRunCount counts))
  putStrLn ("emit-LLVM runs: " <> show (emitLLVMRunCount counts))
  testResult <- runTestTT (TestList (tests hegglog clang))
  unless (errors testResult == 0 && failures testResult == 0) exitFailure

data ManifestCounts = ManifestCounts
  { nativeRunCount :: Int
  , noEgglogRunCount :: Int
  , emitLLVMRunCount :: Int
  }
  deriving stock (Show, Eq)

manifestCounts :: ManifestCounts
manifestCounts =
  ManifestCounts
    { nativeRunCount = sum (length . egglogModes <$> e2eCases)
    , noEgglogRunCount = length [() | e2eCase <- e2eCases, NoEgglog <- egglogModes e2eCase]
    , emitLLVMRunCount = length (filter alsoEmitLLVM e2eCases)
    }

tests :: FilePath -> FilePath -> [Test]
tests hegglog clang =
  concatMap (caseTests hegglog clang) e2eCases

caseTests :: FilePath -> FilePath -> E2ECase -> [Test]
caseTests hegglog clang e2eCase =
  nativeTests <> emitTests <> reportTests
 where
  nativeTests =
    [ TestLabel (Text.unpack (caseName e2eCase) <> " native " <> modeLabel mode) $
        TestCase (runNativeCase hegglog e2eCase mode)
    | mode <- egglogModes e2eCase
    ]
  emitTests =
    case expected e2eCase of
      ExpectSuccess {} | alsoEmitLLVM e2eCase ->
        [ TestLabel (Text.unpack (caseName e2eCase) <> " emit-llvm") $
            TestCase (runEmitLLVMCase hegglog clang e2eCase)
        ]
      _ -> []
  reportTests =
    case expected e2eCase of
      ExpectSuccess {} | includeReport e2eCase ->
        [ TestLabel (Text.unpack (caseName e2eCase) <> " report") $
            TestCase (runReportCase hegglog e2eCase)
        ]
      _ -> []

runNativeCase :: FilePath -> E2ECase -> EgglogMode -> Assertion
runNativeCase hegglog e2eCase mode =
  withSystemTempDirectory "hegglog-e2e-native" $ \tmpDir -> do
    let outputPath = tmpDir </> executableName e2eCase mode
        args = ["compile", sourcePath e2eCase, "-o", outputPath] <> modeArgs mode
    compileResult <- runCommand hegglog args
    case expected e2eCase of
      ExpectSuccess expectedStdout -> do
        assertExitSuccess ("native compile " <> showCommand hegglog args) compileResult
        assertExecutableExists outputPath
        runResult <- runCommand outputPath []
        assertExitSuccess ("native run " <> outputPath) runResult
        assertEqual "native stdout" (Text.unpack expectedStdout <> "\n") (resultStdout runResult)
        assertEqual "native stderr" "" (resultStderr runResult)
      ExpectRuntimeError -> do
        assertExitSuccess ("runtime-error compile " <> showCommand hegglog args) compileResult
        assertExecutableExists outputPath
        runResult <- runCommand outputPath []
        assertNonZeroExit ("runtime-error run " <> outputPath) runResult
        assertEqual "runtime-error stdout" "" (resultStdout runResult)
        assertEqual "runtime-error stderr" "" (resultStderr runResult)
      ExpectCompileError categories -> do
        assertNonZeroExit ("compile-error compile " <> showCommand hegglog args) compileResult
        outputExists <- doesFileExist outputPath
        assertBool ("compile-error should not produce executable " <> outputPath) (not outputExists)
        let combinedOutput = resultStdout compileResult <> resultStderr compileResult
        assertBool "compile-error output should be nonempty" (not (null combinedOutput))
        assertAnyCategory categories combinedOutput

runEmitLLVMCase :: FilePath -> FilePath -> E2ECase -> Assertion
runEmitLLVMCase hegglog clang e2eCase =
  withSystemTempDirectory "hegglog-e2e-llvm" $ \tmpDir -> do
    let llvmPath = tmpDir </> safeCaseName e2eCase <.> "ll"
        exePath = tmpDir </> safeCaseName e2eCase <> "-from-llvm"
        args = ["compile", sourcePath e2eCase, "--emit-llvm", "-o", llvmPath]
    emitResult <- runCommand hegglog args
    assertExitSuccess ("emit LLVM " <> showCommand hegglog args) emitResult
    llvmExists <- doesFileExist llvmPath
    assertBool ("LLVM output should exist: " <> llvmPath) llvmExists
    llvmText <- Text.IO.readFile llvmPath
    assertBool "LLVM output should be nonempty" (not (Text.null llvmText))
    assertBool "LLVM output should contain define" ("define" `Text.isInfixOf` llvmText)
    assertBool "LLVM output should contain @main" ("@main" `Text.isInfixOf` llvmText)
    clangResult <- runCommand clang [llvmPath, "-o", exePath]
    assertExitSuccess ("clang emitted LLVM " <> showCommand clang [llvmPath, "-o", exePath]) clangResult
    assertExecutableExists exePath
    runResult <- runCommand exePath []
    case expected e2eCase of
      ExpectSuccess expectedStdout -> do
        assertExitSuccess ("run emitted LLVM artifact " <> exePath) runResult
        assertEqual "emit LLVM artifact stdout" (Text.unpack expectedStdout <> "\n") (resultStdout runResult)
        assertEqual "emit LLVM artifact stderr" "" (resultStderr runResult)
      _ ->
        assertFailure "emit-LLVM cases should be successful programs"

runReportCase :: FilePath -> E2ECase -> Assertion
runReportCase hegglog e2eCase =
  case expected e2eCase of
    ExpectSuccess expectedStdout -> do
      result <- runCommand hegglog [sourcePath e2eCase]
      assertExitSuccess ("report mode " <> showCommand hegglog [sourcePath e2eCase]) result
      assertEqual "report stderr" "" (resultStderr result)
      actual <- assertReportResult (resultStdout result)
      assertEqual "report Result line" (Text.unpack expectedStdout) actual
    _ ->
      assertFailure "report cases should be successful programs"

runCommand :: FilePath -> [String] -> IO CommandResult
runCommand command args = do
  (code, stdoutText, stderrText) <- readProcessWithExitCode command args ""
  pure
    CommandResult
      { resultExitCode = code
      , resultStdout = stdoutText
      , resultStderr = stderrText
      }

requireExecutable :: String -> String -> IO FilePath
requireExecutable envName executableName' = do
  override <- lookupEnv envName
  case override of
    Just path -> pure path
    Nothing -> do
      found <- findExecutable executableName'
      case found of
        Just path -> pure path
        Nothing -> do
          putStrLn ("required executable unavailable on PATH: " <> executableName')
          exitFailure

assertExitSuccess :: String -> CommandResult -> Assertion
assertExitSuccess label result =
  case resultExitCode result of
    ExitSuccess -> pure ()
    ExitFailure code ->
      assertFailure (label <> " failed with exit " <> show code <> renderCapturedOutput result)

assertNonZeroExit :: String -> CommandResult -> Assertion
assertNonZeroExit label result =
  case resultExitCode result of
    ExitSuccess ->
      assertFailure (label <> " unexpectedly succeeded" <> renderCapturedOutput result)
    ExitFailure {} -> pure ()

assertExecutableExists :: FilePath -> Assertion
assertExecutableExists path = do
  exists <- doesFileExist path
  assertBool ("executable should exist: " <> path) exists
  permissions <- getPermissions path
  assertBool ("file should have executable permissions: " <> path) (executable permissions)

assertAnyCategory :: [Text] -> String -> Assertion
assertAnyCategory categories output =
  assertBool
    ("diagnostic should contain one of " <> show categories <> "\noutput:\n" <> output)
    (any (`isInfixOf` lowerOutput) lowerCategories)
 where
  lowerOutput = toLower <$> output
  lowerCategories = Text.unpack . Text.toLower <$> categories

assertReportResult :: String -> IO String
assertReportResult output =
  case [drop (length resultPrefix) line | line <- lines output, resultPrefix `isPrefixOf` line] of
    result : _ -> pure result
    [] -> assertFailure ("report output did not contain stable Result line\noutput:\n" <> output)
 where
  resultPrefix = "Result: "

renderCapturedOutput :: CommandResult -> String
renderCapturedOutput result =
  "\nstdout:\n"
    <> resultStdout result
    <> "\nstderr:\n"
    <> resultStderr result

showCommand :: FilePath -> [String] -> String
showCommand command args =
  unwords (command : args)

modeArgs :: EgglogMode -> [String]
modeArgs = \case
  DefaultEgglog -> []
  NoEgglog -> ["--no-egglog"]

modeLabel :: EgglogMode -> String
modeLabel = \case
  DefaultEgglog -> "default"
  NoEgglog -> "no-egglog"

executableName :: E2ECase -> EgglogMode -> FilePath
executableName e2eCase mode =
  safeCaseName e2eCase <> "-" <> modeLabel mode

safeCaseName :: E2ECase -> FilePath
safeCaseName e2eCase =
  [ if isAlphaNum char then char else '-'
  | char <- Text.unpack (caseName e2eCase)
  ]

successCase :: Text -> FilePath -> Text -> [EgglogMode] -> Bool -> E2ECase
successCase name path expectedStdout modes emitLLVM =
  E2ECase
    { caseName = name
    , sourcePath = path
    , expected = ExpectSuccess expectedStdout
    , egglogModes = modes
    , alsoEmitLLVM = emitLLVM
    , includeReport = True
    }

nativeOnlySuccessCase :: Text -> FilePath -> Text -> [EgglogMode] -> Bool -> E2ECase
nativeOnlySuccessCase name path expectedStdout modes emitLLVM =
  E2ECase
    { caseName = name
    , sourcePath = path
    , expected = ExpectSuccess expectedStdout
    , egglogModes = modes
    , alsoEmitLLVM = emitLLVM
    , includeReport = False
    }

runtimeErrorCase :: Text -> FilePath -> [EgglogMode] -> E2ECase
runtimeErrorCase name path modes =
  E2ECase
    { caseName = name
    , sourcePath = path
    , expected = ExpectRuntimeError
    , egglogModes = modes
    , alsoEmitLLVM = False
    , includeReport = False
    }

compileErrorCase :: Text -> FilePath -> [Text] -> E2ECase
compileErrorCase name path categories =
  E2ECase
    { caseName = name
    , sourcePath = path
    , expected = ExpectCompileError categories
    , egglogModes = [DefaultEgglog]
    , alsoEmitLLVM = False
    , includeReport = False
    }

e2eCases :: [E2ECase]
e2eCases =
  [ successCase "arithmetic" "test/e2e/programs/arithmetic.hg" "14" [DefaultEgglog, NoEgglog] True
  , successCase "subtraction" "test/e2e/programs/subtraction.hg" "7" [DefaultEgglog, NoEgglog] False
  , successCase "division" "test/e2e/programs/division.hg" "5" [DefaultEgglog, NoEgglog] True
  , successCase "negative-quotient" "test/e2e/programs/negative-quotient.hg" "-2" [DefaultEgglog, NoEgglog] False
  , successCase "if-comparison" "test/e2e/programs/if-comparison.hg" "6" [DefaultEgglog] True
  , successCase "bool-root" "test/e2e/programs/bool-root.hg" "1" [DefaultEgglog, NoEgglog] True
  , successCase "top-level-function" "test/e2e/programs/top-level-function.hg" "7" [DefaultEgglog] False
  , successCase "noncapturing-lambda" "test/e2e/programs/noncapturing-lambda.hg" "42" [DefaultEgglog] False
  , successCase "capturing-closure" "test/e2e/programs/capturing-closure.hg" "42" [DefaultEgglog] True
  , successCase "higher-order" "test/e2e/programs/higher-order.hg" "42" [DefaultEgglog] False
  , successCase "egglog-beneficial" "test/e2e/programs/egglog-beneficial.hg" "14" [DefaultEgglog, NoEgglog] False
  , successCase "boolean-reasoning" "test/e2e/programs/boolean-reasoning.hg" "1" [DefaultEgglog] False
  , nativeOnlySuccessCase "haskell2010-arithmetic" "test/e2e/programs/haskell2010/arithmetic.hs" "9" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-lazy-let" "test/e2e/programs/haskell2010/lazy-let.hs" "5" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-lazy-argument" "test/e2e/programs/haskell2010/lazy-argument.hs" "1" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-partial-application" "test/e2e/programs/haskell2010/partial-application.hs" "1" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-bool-case" "test/e2e/programs/haskell2010/bool-case.hs" "7" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-egglog-known-constructor" "test/e2e/programs/haskell2010/egglog-known-constructor.hs" "7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-tuple-case" "test/e2e/programs/haskell2010/tuple-case.hs" "3" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-prelude-lists" "test/e2e/programs/haskell2010/prelude-lists.hs" "321" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-maybe-ordering" "test/e2e/programs/haskell2010/prelude-maybe-ordering.hs" "5" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-short-circuit" "test/e2e/programs/haskell2010/short-circuit.hs" "7" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-guarded-self-recursion" "test/e2e/programs/haskell2010/guarded-self-recursion.hs" "1" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-local-factorial" "test/e2e/programs/haskell2010/local-factorial.hs" "120" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-fibonacci" "test/e2e/programs/haskell2010/fibonacci.hs" "21" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-mutual-recursion" "test/e2e/programs/haskell2010/mutual-recursion.hs" "1" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-recursive-list" "test/e2e/programs/haskell2010/recursive-list.hs" "10" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-typeclass-dictionary" "test/e2e/programs/haskell2010/typeclass-dictionary.hs" "1" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-classes" "test/e2e/programs/haskell2010/prelude-classes.hs" "6" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-numeric-defaulting" "test/e2e/programs/haskell2010/numeric-defaulting.hs" "7\n47" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-modules" "test/e2e/programs/haskell2010/modules/Main.hs" "20" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-io-printing" "test/e2e/programs/haskell2010/io-printing.hs" "ok\nanswer\n42\nTrue" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-guards-as-patterns" "test/e2e/programs/haskell2010/guards-as-patterns.hs" "15" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-sections" "test/e2e/programs/haskell2010/sections.hs" "6" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-adt-box" "test/e2e/programs/haskell2010/adt-box.hs" "7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-adt-maybe" "test/e2e/programs/haskell2010/adt-maybe.hs" "4" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-adt-nested" "test/e2e/programs/haskell2010/adt-nested.hs" "3" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-adt-lazy-field" "test/e2e/programs/haskell2010/adt-lazy-field.hs" "5" [DefaultEgglog, NoEgglog] False
  , runtimeErrorCase "addition-overflow" "test/e2e/programs/runtime-errors/addition-overflow.hg" [DefaultEgglog]
  , runtimeErrorCase "subtraction-overflow" "test/e2e/programs/runtime-errors/subtraction-overflow.hg" [DefaultEgglog]
  , runtimeErrorCase "multiplication-overflow" "test/e2e/programs/runtime-errors/multiplication-overflow.hg" [DefaultEgglog]
  , runtimeErrorCase "division-by-zero" "test/e2e/programs/runtime-errors/division-by-zero.hg" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "division-overflow" "test/e2e/programs/runtime-errors/division-overflow.hg" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-division-by-zero" "test/e2e/programs/haskell2010/division-by-zero.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-guard-fallthrough" "test/e2e/programs/haskell2010/guard-fallthrough.hs" [DefaultEgglog, NoEgglog]
  , compileErrorCase "open-free-variable" "test/e2e/programs/compile-errors/open-free-variable.hg" ["free", "unbound", "unknown", "backend"]
  , compileErrorCase "type-error" "test/e2e/programs/compile-errors/type-error.hg" ["type"]
  , compileErrorCase "unsupported-recursion" "test/e2e/programs/unsupported/unsupported-recursion.hg" ["recursive", "recursion", "unbound", "unknown"]
  ]
