module Main (main) where

import Control.Monad (unless)
import qualified Data.Aeson as Aeson
import Data.Aeson ((.!=), (.:), (.:?), FromJSON (..), withObject, withText)
import qualified Data.ByteString.Lazy as BL
import Data.Char (isAlphaNum, toLower)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import System.Directory
  ( doesFileExist
  , executable
  , findExecutable
  , getPermissions
  )
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.HUnit

manifestPath :: FilePath
manifestPath = "test/haskell2010/conformance/manifest.json"

data Manifest = Manifest
  { manifestSchemaVersion :: Int
  , manifestCases :: [ConformanceCase]
  }
  deriving stock (Show, Eq)

instance FromJSON Manifest where
  parseJSON =
    withObject "Manifest" $ \object ->
      Manifest
        <$> object .: "schemaVersion"
        <*> object .: "cases"

data ConformanceCase = ConformanceCase
  { caseName :: Text
  , caseSourceFile :: FilePath
  , caseCategory :: Text
  , caseExpectedStatus :: ExpectedStatus
  , caseExpectedStdout :: Maybe Text
  , caseExpectedDiagnosticCategory :: Maybe Text
  , caseRequiredStage :: Text
  , caseNotes :: Text
  , caseCompilerModes :: [CompilerMode]
  }
  deriving stock (Show, Eq)

instance FromJSON ConformanceCase where
  parseJSON =
    withObject "ConformanceCase" $ \object ->
      ConformanceCase
        <$> object .: "name"
        <*> object .: "sourceFile"
        <*> object .: "category"
        <*> object .: "expectedStatus"
        <*> object .:? "expectedStdout"
        <*> object .:? "expectedDiagnosticCategory"
        <*> object .: "requiredStage"
        <*> object .: "notes"
        <*> ((object .:? "compilerModes") .!= [DefaultCompilerMode])

data ExpectedStatus
  = ParsePass
  | RenamePass
  | TypecheckPass
  | CorePass
  | NativeSuccess
  | NativeRuntimeError
  | CompileError
  | UnsupportedDocumented
  deriving stock (Show, Eq, Ord)

instance FromJSON ExpectedStatus where
  parseJSON =
    withText "ExpectedStatus" $ \text ->
      case text of
        "parse-pass" -> pure ParsePass
        "rename-pass" -> pure RenamePass
        "typecheck-pass" -> pure TypecheckPass
        "core-pass" -> pure CorePass
        "native-success" -> pure NativeSuccess
        "native-runtime-error" -> pure NativeRuntimeError
        "compile-error" -> pure CompileError
        "unsupported-documented" -> pure UnsupportedDocumented
        _ -> fail ("unknown expected status: " <> Text.unpack text)

data CompilerMode
  = DefaultCompilerMode
  | NoEgglogCompilerMode
  deriving stock (Show, Eq, Ord)

instance FromJSON CompilerMode where
  parseJSON =
    withText "CompilerMode" $ \text ->
      case text of
        "default" -> pure DefaultCompilerMode
        "no-egglog" -> pure NoEgglogCompilerMode
        _ -> fail ("unknown compiler mode: " <> Text.unpack text)

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
  manifest <- readManifest manifestPath
  unless (manifestSchemaVersion manifest == 1) $
    fail ("unsupported Haskell 2010 conformance manifest schema: " <> show (manifestSchemaVersion manifest))
  putStrLn ("hegglog: " <> hegglog)
  putStrLn ("clang: " <> clang)
  putManifestSummary (manifestCases manifest)
  testResult <- runTestTT (TestList (tests hegglog (manifestCases manifest)))
  unless (errors testResult == 0 && failures testResult == 0) exitFailure

readManifest :: FilePath -> IO Manifest
readManifest path = do
  bytes <- BL.readFile path
  case Aeson.eitherDecode bytes of
    Left message ->
      fail ("could not decode " <> path <> ": " <> message)
    Right manifest ->
      pure manifest

tests :: FilePath -> [ConformanceCase] -> [Test]
tests hegglog =
  concatMap (caseTests hegglog)

caseTests :: FilePath -> ConformanceCase -> [Test]
caseTests hegglog conformanceCase =
  case caseExpectedStatus conformanceCase of
    NativeSuccess ->
      [modeTest mode (runNativeSuccessCase hegglog conformanceCase mode) | mode <- caseCompilerModes conformanceCase]
    NativeRuntimeError ->
      [modeTest mode (runNativeRuntimeErrorCase hegglog conformanceCase mode) | mode <- caseCompilerModes conformanceCase]
    CompileError ->
      [modeTest DefaultCompilerMode (runCompileErrorCase hegglog conformanceCase)]
    UnsupportedDocumented ->
      [modeTest DefaultCompilerMode (runUnsupportedDocumentedCase hegglog conformanceCase)]
    ParsePass ->
      [modeTest DefaultCompilerMode (runCompileToLLVMPassCase hegglog conformanceCase)]
    RenamePass ->
      [modeTest DefaultCompilerMode (runCompileToLLVMPassCase hegglog conformanceCase)]
    TypecheckPass ->
      [modeTest DefaultCompilerMode (runCompileToLLVMPassCase hegglog conformanceCase)]
    CorePass ->
      [modeTest DefaultCompilerMode (runCompileToLLVMPassCase hegglog conformanceCase)]
 where
  modeTest mode assertion =
    TestLabel (Text.unpack (caseName conformanceCase) <> " " <> modeLabel mode) (TestCase assertion)

runNativeSuccessCase :: FilePath -> ConformanceCase -> CompilerMode -> Assertion
runNativeSuccessCase hegglog conformanceCase mode =
  withSystemTempDirectory "hegglog-haskell2010-conformance" $ \tmpDir -> do
    expectedStdout <- requiredExpectedStdout conformanceCase
    let outputPath = tmpDir </> safeCaseFileName conformanceCase <> "-" <> modeLabel mode
        args = compileExecutableArgs conformanceCase outputPath mode
    compileResult <- runCommand hegglog args
    assertExitSuccess ("native compile " <> showCommand hegglog args) compileResult
    assertExecutableExists outputPath
    runResult <- runCommand outputPath []
    assertExitSuccess ("native run " <> outputPath) runResult
    assertEqual "native stdout" (Text.unpack expectedStdout) (resultStdout runResult)
    assertEqual "native stderr" "" (resultStderr runResult)

runNativeRuntimeErrorCase :: FilePath -> ConformanceCase -> CompilerMode -> Assertion
runNativeRuntimeErrorCase hegglog conformanceCase mode =
  withSystemTempDirectory "hegglog-haskell2010-conformance-runtime-error" $ \tmpDir -> do
    let outputPath = tmpDir </> safeCaseFileName conformanceCase <> "-" <> modeLabel mode
        args = compileExecutableArgs conformanceCase outputPath mode
    compileResult <- runCommand hegglog args
    assertExitSuccess ("runtime-error compile " <> showCommand hegglog args) compileResult
    assertExecutableExists outputPath
    runResult <- runCommand outputPath []
    assertNonZeroExit ("runtime-error run " <> outputPath) runResult

runCompileErrorCase :: FilePath -> ConformanceCase -> Assertion
runCompileErrorCase =
  runExpectedFailingCompile "compile-error"

runUnsupportedDocumentedCase :: FilePath -> ConformanceCase -> Assertion
runUnsupportedDocumentedCase hegglog conformanceCase = do
  assertBool
    ("unsupported-documented case must include notes/deviation: " <> Text.unpack (caseName conformanceCase))
    (not (Text.null (Text.strip (caseNotes conformanceCase))))
  runExpectedFailingCompile "unsupported-documented" hegglog conformanceCase

runExpectedFailingCompile :: String -> FilePath -> ConformanceCase -> Assertion
runExpectedFailingCompile label hegglog conformanceCase =
  withSystemTempDirectory ("hegglog-haskell2010-conformance-" <> label) $ \tmpDir -> do
    let outputPath = tmpDir </> safeCaseFileName conformanceCase
        args = compileExecutableArgs conformanceCase outputPath DefaultCompilerMode
    compileResult <- runCommand hegglog args
    assertNonZeroExit (label <> " compile " <> showCommand hegglog args) compileResult
    outputExists <- doesFileExist outputPath
    assertBool (label <> " should not produce executable " <> outputPath) (not outputExists)
    let combinedOutput = resultStdout compileResult <> resultStderr compileResult
    assertBool (label <> " diagnostic output should be nonempty") (not (null combinedOutput))
    case caseExpectedDiagnosticCategory conformanceCase of
      Nothing -> pure ()
      Just category -> assertDiagnosticCategory category combinedOutput

runCompileToLLVMPassCase :: FilePath -> ConformanceCase -> Assertion
runCompileToLLVMPassCase hegglog conformanceCase =
  withSystemTempDirectory "hegglog-haskell2010-conformance-stage-pass" $ \tmpDir -> do
    let outputPath = tmpDir </> safeCaseFileName conformanceCase <> ".ll"
        args = ["compile", caseSourceFile conformanceCase, "--emit-llvm", "-o", outputPath]
    result <- runCommand hegglog args
    assertExitSuccess ("compile-to-llvm pass " <> showCommand hegglog args) result
    outputExists <- doesFileExist outputPath
    assertBool ("LLVM output should exist for stage-pass case " <> outputPath) outputExists

runCommand :: FilePath -> [String] -> IO CommandResult
runCommand command args = do
  (code, stdoutText, stderrText) <- readProcessWithExitCode command args ""
  pure
    CommandResult
      { resultExitCode = code
      , resultStdout = stdoutText
      , resultStderr = stderrText
      }

compileExecutableArgs :: ConformanceCase -> FilePath -> CompilerMode -> [String]
compileExecutableArgs conformanceCase outputPath mode =
  ["compile", caseSourceFile conformanceCase, "-o", outputPath] <> modeArgs mode

requiredExpectedStdout :: ConformanceCase -> IO Text
requiredExpectedStdout conformanceCase =
  case caseExpectedStdout conformanceCase of
    Just stdoutText -> pure stdoutText
    Nothing -> assertFailure ("native-success case lacks expectedStdout: " <> Text.unpack (caseName conformanceCase))

requireExecutable :: String -> String -> IO FilePath
requireExecutable envName executableName = do
  override <- lookupEnv envName
  case override of
    Just path -> pure path
    Nothing -> do
      found <- findExecutable executableName
      case found of
        Just path -> pure path
        Nothing -> do
          putStrLn ("required executable unavailable on PATH: " <> executableName)
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

assertDiagnosticCategory :: Text -> String -> Assertion
assertDiagnosticCategory category output =
  assertBool
    ("diagnostic should contain category " <> show category <> "\noutput:\n" <> output)
    (Text.unpack (Text.toLower category) `isSubstringOf` lowerOutput)
 where
  lowerOutput = toLower <$> output

isSubstringOf :: String -> String -> Bool
isSubstringOf needle haystack =
  any (needle `prefixOf`) (suffixes haystack)

prefixOf :: String -> String -> Bool
prefixOf prefix text =
  take (length prefix) text == prefix

suffixes :: String -> [String]
suffixes [] = [""]
suffixes text@(_ : rest) = text : suffixes rest

renderCapturedOutput :: CommandResult -> String
renderCapturedOutput result =
  "\nstdout:\n"
    <> resultStdout result
    <> "\nstderr:\n"
    <> resultStderr result

showCommand :: FilePath -> [String] -> String
showCommand command args =
  unwords (command : args)

modeArgs :: CompilerMode -> [String]
modeArgs = \case
  DefaultCompilerMode -> []
  NoEgglogCompilerMode -> ["--no-egglog"]

modeLabel :: CompilerMode -> String
modeLabel = \case
  DefaultCompilerMode -> "default"
  NoEgglogCompilerMode -> "no-egglog"

safeCaseFileName :: ConformanceCase -> FilePath
safeCaseFileName conformanceCase =
  [ if isAlphaNum char then char else '-'
  | char <- Text.unpack (caseName conformanceCase)
  ]

putManifestSummary :: [ConformanceCase] -> IO ()
putManifestSummary conformanceCases = do
  putStrLn ("conformance fixtures: " <> show (length conformanceCases))
  putStrLn ("native-success fixtures: " <> showStatusCount NativeSuccess)
  putStrLn ("native-runtime-error fixtures: " <> showStatusCount NativeRuntimeError)
  putStrLn ("compile-error fixtures: " <> showStatusCount CompileError)
  putStrLn ("unsupported-documented fixtures: " <> showStatusCount UnsupportedDocumented)
  putStrLn ("subprocess native runs: " <> show nativeRunCount)
  putStrLn "category summary:"
  mapM_ putCategoryCount (Map.toAscList categoryCounts)
 where
  statusCounts =
    Map.fromListWith (+) [(caseExpectedStatus conformanceCase, 1 :: Int) | conformanceCase <- conformanceCases]
  categoryCounts =
    Map.fromListWith (+) [(caseCategory conformanceCase, 1 :: Int) | conformanceCase <- conformanceCases]
  nativeRunCount =
    sum
      [ length (caseCompilerModes conformanceCase)
      | conformanceCase <- conformanceCases
      , caseExpectedStatus conformanceCase `elem` [NativeSuccess, NativeRuntimeError]
      ]
  showStatusCount status =
    show (Map.findWithDefault 0 status statusCounts)
  putCategoryCount (category, count) =
    putStrLn ("  " <> Text.unpack category <> ": " <> show count)
