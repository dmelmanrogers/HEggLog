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
  , extraCompileArgs :: [String]
  , stdinText :: Text
  , expectedCompileWarnings :: [Text]
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
        args = ["compile", sourcePath e2eCase, "-o", outputPath] <> extraCompileArgs e2eCase <> modeArgs mode
    compileResult <- runCommand hegglog args
    case expected e2eCase of
      ExpectSuccess expectedStdout -> do
        assertExitSuccess ("native compile " <> showCommand hegglog args) compileResult
        assertCompileWarnings e2eCase compileResult
        assertExecutableExists outputPath
        runResult <- runCommandWithInput outputPath [] (stdinText e2eCase)
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
        args = ["compile", sourcePath e2eCase, "--emit-llvm", "-o", llvmPath] <> extraCompileArgs e2eCase
    emitResult <- runCommand hegglog args
    assertExitSuccess ("emit LLVM " <> showCommand hegglog args) emitResult
    assertCompileWarnings e2eCase emitResult
    llvmExists <- doesFileExist llvmPath
    assertBool ("LLVM output should exist: " <> llvmPath) llvmExists
    llvmText <- Text.IO.readFile llvmPath
    assertBool "LLVM output should be nonempty" (not (Text.null llvmText))
    assertBool "LLVM output should contain define" ("define" `Text.isInfixOf` llvmText)
    assertBool "LLVM output should contain @main" ("@main" `Text.isInfixOf` llvmText)
    clangResult <- runCommand clang [llvmPath, "-o", exePath]
    assertExitSuccess ("clang emitted LLVM " <> showCommand clang [llvmPath, "-o", exePath]) clangResult
    assertExecutableExists exePath
    runResult <- runCommandWithInput exePath [] (stdinText e2eCase)
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
runCommand command args =
  runCommandWithInput command args ""

runCommandWithInput :: FilePath -> [String] -> Text -> IO CommandResult
runCommandWithInput command args stdinText' = do
  (code, stdoutText, stderrText) <- readProcessWithExitCode command args (Text.unpack stdinText')
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

assertCompileWarnings :: E2ECase -> CommandResult -> Assertion
assertCompileWarnings e2eCase result =
  mapM_ assertWarning (expectedCompileWarnings e2eCase)
 where
  assertWarning warning =
    assertBool
      ( "compile warning should contain "
          <> show warning
          <> "\nstderr:\n"
          <> resultStderr result
      )
      (Text.unpack warning `isInfixOf` resultStderr result)

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
    , extraCompileArgs = []
    , stdinText = ""
    , expectedCompileWarnings = []
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
    , extraCompileArgs = []
    , stdinText = ""
    , expectedCompileWarnings = []
    }

nativeOnlySuccessCaseWithCompileArgs :: Text -> FilePath -> Text -> [EgglogMode] -> Bool -> [String] -> E2ECase
nativeOnlySuccessCaseWithCompileArgs name path expectedStdout modes emitLLVM compileArgs =
  (nativeOnlySuccessCase name path expectedStdout modes emitLLVM) {extraCompileArgs = compileArgs}

nativeOnlySuccessCaseWithInput :: Text -> FilePath -> Text -> Text -> [EgglogMode] -> Bool -> E2ECase
nativeOnlySuccessCaseWithInput name path input expectedStdout modes emitLLVM =
  (nativeOnlySuccessCase name path expectedStdout modes emitLLVM) {stdinText = input}

nativeOnlySuccessCaseWithCompileWarnings :: Text -> FilePath -> Text -> [EgglogMode] -> Bool -> [Text] -> E2ECase
nativeOnlySuccessCaseWithCompileWarnings name path expectedStdout modes emitLLVM warnings =
  (nativeOnlySuccessCase name path expectedStdout modes emitLLVM) {expectedCompileWarnings = warnings}

runtimeErrorCase :: Text -> FilePath -> [EgglogMode] -> E2ECase
runtimeErrorCase name path modes =
  E2ECase
    { caseName = name
    , sourcePath = path
    , expected = ExpectRuntimeError
    , egglogModes = modes
    , alsoEmitLLVM = False
    , includeReport = False
    , extraCompileArgs = []
    , stdinText = ""
    , expectedCompileWarnings = []
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
    , extraCompileArgs = []
    , stdinText = ""
    , expectedCompileWarnings = []
    }

dataListExpectedStdout :: Text
dataListExpectedStdout =
  Text.intercalate
    "\n"
    [ "3"
    , "[1,2]"
    , "a-b-c"
    , "ab,cd,ef"
    , "[[1,4,7],[2,5,8],[3,6]]"
    , "[\"\",\"a\",\"b\",\"ab\"]"
    , "[\"abc\",\"bac\",\"cba\",\"bca\",\"cab\",\"acb\"]"
    , "6"
    , "True"
    , "15"
    , "5"
    , "haskell"
    , "[1,2,3]"
    , "[1,11,2,12]"
    , "False"
    , "True"
    , "True"
    , "True"
    , "6"
    , "24"
    , "4"
    , "1"
    , "[0,1,3,6]"
    , "[1,3,6]"
    , "[[1,2,3],[2,3],[3],[]]"
    , "[6,5,3]"
    , "6"
    , "[1,3,6]"
    , "6"
    , "[6,5,3]"
    , "[1,3,5,7,9]"
    , "[7,7,7,7]"
    , "[1,2,1,2,1]"
    , "[4,3,2,1]"
    , "[1,2]"
    , "[3,4]"
    , "[1,2]"
    , "[3,4]"
    , "[1,2]"
    , "[3,1]"
    , "[1,2]"
    , "[3,1]"
    , "[1,2]"
    , "[3,1]"
    , "fix"
    , "[\"m\",\"i\",\"ss\"]"
    , "[\"\",\"a\",\"ab\",\"abc\"]"
    , "[\"abc\",\"bc\",\"c\",\"\"]"
    , "True"
    , "True"
    , "True"
    , "True"
    , "2"
    , "3"
    , "[1,3]"
    , "[2,4]"
    , "8"
    , "1"
    , "[1,3,5]"
    , "2"
    , "[0,2]"
    , "[11,22]"
    , "[6]"
    , "[10]"
    , "[15]"
    , "[21]"
    , "[28]"
    , "2"
    , "1"
    , "1"
    , "1"
    , "1"
    , "1"
    , "[1,2]"
    , "ab"
    , "3"
    , "4"
    , "5"
    , "6"
    , "7"
    , "[\"a\",\"b\"]"
    , "[\"a\",\"b\",\"c\"]"
    , "a"
    , "b"
    , ""
    , "a b c"
    , "ban"
    , "bnana"
    , "bana"
    , "dogcw"
    , "ississippi"
    , "[1,2,3]"
    , "[1,2,3,4]"
    , "ab"
    , "bnana"
    , "bana"
    , "dogcw"
    , "ississippi"
    , "[\"aa\",\"bb\"]"
    , "[3,2,1]"
    , "[1,2,3,4]"
    , "4"
    , "1"
    , "3"
    , "[1,2]"
    , "[2,3]"
    , "[1,2]"
    , "[3]"
    , "6"
    , "[8,8,8]"
    ]

dataBitsExpectedStdout :: Text
dataBitsExpectedStdout =
  Text.intercalate
    "\n"
    [ "2"
    , "7"
    , "5"
    , "-1"
    , "4"
    , "12"
    , "-9223372036854775808"
    , "0"
    , "-1"
    , "-9223372036854775808"
    , "2"
    , "1"
    , "32"
    , "0"
    , "8"
    , "-2"
    , "2"
    , "True"
    , "False"
    , "64"
    , "True"
    , "8"
    ]

dataRatioExpectedStdout :: Text
dataRatioExpectedStdout =
  Text.intercalate
    "\n"
    [ "3"
    , "2"
    , "-3"
    , "2"
    , "0"
    , "1"
    , "3 % 2"
    , "True"
    , "True"
    , "7 % 4"
    , "5 % 4"
    , "3 % 8"
    , "-3 % 2"
    , "3 % 2"
    , "1 % 1"
    , "3 % 2"
    , "7"
    , "1"
    , "[3 % 2,-3 % 2]"
    , "0 % 1"
    , "3 % 10"
    , "3 % 2"
    , "3 % 2"
    , "!"
    , "[3 % 2,-3 % 2]"
    ]

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
  , nativeOnlySuccessCase "haskell2010-prelude-append" "test/e2e/programs/haskell2010/prelude-append.hs" "[1,2,3,4]\nhegglog\n[1,2,3]\n[True,False]\nhey\nheglog" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-maybe-ordering" "test/e2e/programs/haskell2010/prelude-maybe-ordering.hs" "5" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-short-circuit" "test/e2e/programs/haskell2010/short-circuit.hs" "7" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-guarded-self-recursion" "test/e2e/programs/haskell2010/guarded-self-recursion.hs" "1" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-local-factorial" "test/e2e/programs/haskell2010/local-factorial.hs" "120" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-fibonacci" "test/e2e/programs/haskell2010/fibonacci.hs" "21" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-mutual-recursion" "test/e2e/programs/haskell2010/mutual-recursion.hs" "1" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-recursive-list" "test/e2e/programs/haskell2010/recursive-list.hs" "10" [DefaultEgglog, NoEgglog] False
  , nativeOnlySuccessCase "haskell2010-typeclass-dictionary" "test/e2e/programs/haskell2010/typeclass-dictionary.hs" "1" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-classes" "test/e2e/programs/haskell2010/prelude-classes.hs" "6" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-char-runtime" "test/e2e/programs/haskell2010/char-runtime.hs" "1" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-char-main" "test/e2e/programs/haskell2010/char-main.hs" "Z" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-string-char-list" "test/e2e/programs/haskell2010/string-char-list.hs" "5" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-string-output" "test/e2e/programs/haskell2010/string-output.hs" "native\nok\n7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-string-show-output" "test/e2e/programs/haskell2010/string-show-output.hs" "42\nFalse" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-string-char-patterns" "test/e2e/programs/haskell2010/string-char-patterns.hs" "6" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-broad-show" "test/e2e/programs/haskell2010/broad-show.hs" "'Z'\n\"hi\"\n[1,2,3]\n[True,False]\n[\"a\",\"b\"]\n'Z'!\n\"hi\"!\n\"ab\"!\n[1,2]!\n'\\NUL'\n\"\\n\\\"\\\\\"\n\"\\SO\\&H\"\n'Q'\n\"ok\"" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-numeric-defaulting" "test/e2e/programs/haskell2010/numeric-defaulting.hs" "7\n47" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-numeric-hierarchy" "test/e2e/programs/haskell2010/numeric-hierarchy.hs" "3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-foldl" "test/e2e/programs/haskell2010/prelude-foldl.hs" "1234\n-6\nabcd\n2\n7\n5" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-prelude-functions" "test/e2e/programs/haskell2010/prelude-functions.hs" "5\n21\n7\n1\n[2,3]\nTrue\nFalse\n42\nok" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-standard-library-modules" "test/e2e/programs/haskell2010/standard-library-modules.hs" "9\n9\n5\nTrue\nstdlib" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-list" "test/haskell2010/conformance/modules/data-list.hs" dataListExpectedStdout [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-maybe" "test/haskell2010/conformance/modules/data-maybe.hs" "7\n5\nTrue\nFalse\nTrue\nok\n11\n3\n[8]\n[]\n1\nTrue\n[1,3]\n[30,40]" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-char" "test/haskell2010/conformance/modules/data-char.hs" "True\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nFalse\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nUppercaseLetter\nNonSpacingMark\nAzQ\n15\nf\n65\nA\n\\n!\n\\SO\\&H\n\\n\nHello\n'A'\n7\n!" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-ix" "test/haskell2010/conformance/modules/data-ix.hs" "[1,2,3,4]\n2\nTrue\nxyz\n[False,True]\n[LT,EQ,GT]\n1\n[Red,Green,Blue]\n1\nTrue\n2\n4" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-array" "test/haskell2010/conformance/modules/data-array.hs" "abc\nbc\n1\n3\n[1,2,3]\naZc\n2\n3\n1\n0\n10\nbc\nAbc\nTrue\nGT\narray (1,3) [(1,'a'),(2,'b'),(3,'c')]\n(array (1,3) [(1,'a'),(2,'b'),(3,'c')])!\nabc\nxy" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-bits" "test/haskell2010/conformance/modules/data-bits.hs" dataBitsExpectedStdout [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-data-ratio" "test/haskell2010/conformance/modules/data-ratio.hs" dataRatioExpectedStdout [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-modules" "test/e2e/programs/haskell2010/modules/Main.hs" "20" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCaseWithCompileArgs "haskell2010-import-search-path" "test/e2e/programs/haskell2010/search-path/Main.hs" "42" [DefaultEgglog, NoEgglog] True ["-i", "test/e2e/programs/haskell2010/search-path-lib"]
  , nativeOnlySuccessCase "haskell2010-io-printing" "test/e2e/programs/haskell2010/io-printing.hs" "ok\nanswer\n42\nTrue" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-io-normal-examples" "test/e2e/programs/haskell2010/io-normal-examples.hs" "hello\nbound\n\"quoted\"\n'X'\n\"plain\"\n[1,2,3]\n[True,False]" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCaseWithInput "haskell2010-io-getline" "test/e2e/programs/haskell2010/io-getline.hs" "hegg\nlog\nunused\n" "first=hegg\nsecond=log\n7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-monad" "test/e2e/programs/haskell2010/monad.hs" "monad\n[11,21,12,22]\n[1,3]\n7\nmaybe fail" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-monad-explicit-fail" "test/e2e/programs/haskell2010/monad-explicit-fail.hs" "[]\nmaybe explicit fail\n7" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-control-monad" "test/e2e/programs/haskell2010/control-monad.hs" "[2,3,4]\n4\n5\n[2,4]\n6\n[1,2]\n7\n8\n7\n9\n9\n10\n11\n[1,2,3]\n[3,4]\n[1,2]\n[11,12]\n[11,22]\n21\n32\n6\n13\n[2,2,2]\n14\n15\n99\n[16,17]\n[]\nwhen\nunless\n16\n33\n6\n10\n15\n34\n35" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-guards-as-patterns" "test/e2e/programs/haskell2010/guards-as-patterns.hs" "15" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-sections" "test/e2e/programs/haskell2010/sections.hs" "6" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-user-defined-operators" "test/e2e/programs/haskell2010/user-defined-operators.hs" "537" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-where-layout" "test/e2e/programs/haskell2010/where-layout.hs" "14" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-arithmetic-sequences" "test/e2e/programs/haskell2010/arithmetic-sequences.hs" "[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-derived-enum" "test/e2e/programs/haskell2010/derived-enum.hs" "0\n2\n2\n1\nWest\n[1,2,3]\n[3,2,1,0]\n[1,2,3]\n[0,2]\n[3,2,1,0]\n[1,2,3]\n[3,2,1,0]\n0" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-derived-bounded" "test/e2e/programs/haskell2010/derived-bounded.hs" "0\n3\nPair False North\nPair True West\nRecord {low = False, high = North}\nRecord {low = True, high = West}\nFlag False\nFlag True" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCase "haskell2010-list-comprehensions" "test/e2e/programs/haskell2010/list-comprehensions.hs" "[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]" [DefaultEgglog, NoEgglog] True
  , nativeOnlySuccessCaseWithCompileWarnings "haskell2010-pattern-diagnostics" "test/e2e/programs/haskell2010/pattern-diagnostics.hs" "7" [DefaultEgglog, NoEgglog] True ["non-exhaustive pattern match", "case alternatives", "False"]
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
  , runtimeErrorCase "haskell2010-derived-enum-runtime-error" "test/e2e/programs/haskell2010/derived-enum-runtime-error.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-prelude-head-empty" "test/e2e/programs/haskell2010/prelude-head-empty.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-list-partial" "test/haskell2010/conformance/modules/data-list-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-maybe-partial" "test/haskell2010/conformance/modules/data-maybe-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-char-partial" "test/haskell2010/conformance/modules/data-char-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-array-partial" "test/haskell2010/conformance/modules/data-array-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-array-duplicate-partial" "test/haskell2010/conformance/modules/data-array-duplicate-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-bits-negative-shift-partial" "test/haskell2010/conformance/modules/data-bits-negative-shift-partial.hs" [DefaultEgglog, NoEgglog]
  , runtimeErrorCase "haskell2010-data-ratio-zero-denominator-partial" "test/haskell2010/conformance/modules/data-ratio-zero-denominator-partial.hs" [DefaultEgglog, NoEgglog]
  , compileErrorCase "open-free-variable" "test/e2e/programs/compile-errors/open-free-variable.hg" ["free", "unbound", "unknown", "backend"]
  , compileErrorCase "type-error" "test/e2e/programs/compile-errors/type-error.hg" ["type"]
  , compileErrorCase "unsupported-recursion" "test/e2e/programs/unsupported/unsupported-recursion.hg" ["recursive", "recursion", "unbound", "unknown"]
  ]
