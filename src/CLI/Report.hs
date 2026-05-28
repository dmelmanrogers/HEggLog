module CLI.Report
  ( CompileError (..)
  , CompileReport (..)
  , LegacyReportEgglog (..)
  , LegacyReportOptions (..)
  , compileLegacyCore
  , compileReport
  , compileReportWithOptions
  , defaultLegacyReportOptions
  , renderCompileError
  , renderFullReport
  , renderGoldenReport
  )
where

import Analysis.Facts (Fact, renderFacts)
import Analysis.InferFacts (inferFacts)
import Egglog.Eval (defaultRunConfig)
import Egglog.Rebuild (canonicalizedEntries, mergeConflicts, rebuildIterations, unionsCreated)
import Egglog.Sort (renderFunctionName)
import Eval.Interpreter (RuntimeError, Value (..), evalProgram, renderRuntimeError, renderValue)
import IR.ANF (AExpr, AProgram (..), renderANF, renderANFProgram, toANFProgram)
import IR.Core (CoreProgram, lower, renderCore)
import Optimize.EgglogBackend
  ( AppliedRuleSummary (..)
  , EgglogBackendError
  , EgglogOptimizationAttempt (..)
  , EgglogOptimizationResult (..)
  , ExtractionStats (..)
  , RunStats (..)
  , renderEgglogBackendError
  , tryOptimizeWithEgglog
  )
import Optimize.EGraph
  ( EGraphError
  , EGraphResult (..)
  , optimizeANF
  , renderEGraphError
  )
import Optimize.Simplify
  ( AppliedRewrite
  , SimplifyError
  , SimplifyResult (..)
  , appliedRewrites
  , renderAppliedRewrites
  , renderSimplifyError
  , simplifiedANF
  , simplifyFixpoint
  )
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST (Program (..), Type)
import Syntax.Located (locatedExprSpan, locatedProgramMain, stripLocatedProgram)
import Syntax.Parser (parseLocatedSourceProgram)
import Syntax.Pretty (prettyProgram, prettyType, renderDoc)
import Syntax.Span (SourceSpan, renderSourceDiagnostic)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (elaborateLocatedProgram)
import Typecheck.Types (LocatedTypeError, renderLocatedTypeError)

data CompileReport = CompileReport
  { reportParsed :: Program
  , reportType :: Type
  , reportValue :: Value
  , reportANF :: AProgram
  , reportFacts :: [Fact]
  , reportOptimizedANF :: AProgram
  , reportAppliedRewrites :: [AppliedRewrite]
  , reportEGraph :: Either EGraphError EGraphResult
  , reportEgglog :: LegacyReportEgglog
  , reportCore :: CoreProgram
  }
  deriving stock (Show, Eq)

data LegacyReportOptions = LegacyReportOptions
  { legacyReportUseEgglog :: Bool
  , legacyReportStrictEgglog :: Bool
  }
  deriving stock (Show, Eq)

data LegacyReportEgglog
  = LegacyReportEgglogDisabled
  | LegacyReportEgglogAttempt EgglogOptimizationAttempt
  deriving stock (Show, Eq)

defaultLegacyReportOptions :: LegacyReportOptions
defaultLegacyReportOptions =
  LegacyReportOptions
    { legacyReportUseEgglog = True
    , legacyReportStrictEgglog = False
    }

data CompileError
  = CompileParseError Text
  | CompileTypeError LocatedTypeError
  | CompileRuntimeError SourceSpan RuntimeError
  | CompileSimplifyError SimplifyError
  | CompileEgglogError EgglogBackendError
  deriving stock (Show, Eq)

compileReport :: FilePath -> Text -> Either CompileError CompileReport
compileReport =
  compileReportWithOptions defaultLegacyReportOptions

compileReportWithOptions :: LegacyReportOptions -> FilePath -> Text -> Either CompileError CompileReport
compileReportWithOptions options path source = do
  parsed <-
    case parseLocatedSourceProgram path source of
      Left parseError -> Left (CompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  (inferredType, typedParsed) <-
    case elaborateLocatedProgram parsed of
      Left typeError -> Left (CompileTypeError typeError)
      Right result -> Right result
  let stripped = stripLocatedProgram typedParsed
  value <-
    case evalProgram stripped of
      Left runtimeError -> Left (CompileRuntimeError (locatedExprSpan (locatedProgramMain typedParsed)) runtimeError)
      Right result -> Right result
  let anf = toANFProgram stripped
      mainANF = programMainANF anf
  simplified <-
    case simplifyTopLevelAware anf of
      Left simplifyError -> Left (CompileSimplifyError simplifyError)
      Right result -> Right result
  egglogReport <- selectLegacyEgglogReport options mainANF
  pure
    CompileReport
      { reportParsed = stripped
      , reportType = inferredType
      , reportValue = value
      , reportANF = anf
      , reportFacts = inferFacts mainANF
      , reportOptimizedANF = replaceProgramMain anf (simplifiedANF simplified)
      , reportAppliedRewrites = appliedRewrites simplified
      , reportEGraph = optimizeANF mainANF
      , reportEgglog = egglogReport
      , reportCore = lower (programMain stripped)
      }

selectLegacyEgglogReport :: LegacyReportOptions -> AExpr -> Either CompileError LegacyReportEgglog
selectLegacyEgglogReport options mainANF
  | not (legacyReportUseEgglog options) =
      Right LegacyReportEgglogDisabled
  | otherwise =
      case tryOptimizeWithEgglog defaultRunConfig mainANF of
        attempt@(EgglogOptimized {}) ->
          Right (LegacyReportEgglogAttempt attempt)
        EgglogUnsupported err
          | legacyReportStrictEgglog options ->
              Left (CompileEgglogError err)
        attempt@(EgglogUnsupported {}) ->
          Right (LegacyReportEgglogAttempt attempt)
        EgglogFailed err
          | legacyReportStrictEgglog options ->
              Left (CompileEgglogError err)
        attempt@(EgglogFailed {}) ->
          Right (LegacyReportEgglogAttempt attempt)

compileLegacyCore :: FilePath -> Text -> Either CompileError CoreProgram
compileLegacyCore path source = do
  parsed <-
    case parseLocatedSourceProgram path source of
      Left parseError -> Left (CompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  typedParsed <-
    case elaborateLocatedProgram parsed of
      Left typeError -> Left (CompileTypeError typeError)
      Right (_, result) -> Right result
  pure (lower (programMain (stripLocatedProgram typedParsed)))

programMainANF :: AProgram -> AExpr
programMainANF (AProgram _ mainExpr) =
  mainExpr

replaceProgramMain :: AProgram -> AExpr -> AProgram
replaceProgramMain (AProgram defs _) mainExpr =
  AProgram defs mainExpr

simplifyTopLevelAware :: AProgram -> Either SimplifyError SimplifyResult
simplifyTopLevelAware (AProgram [] mainExpr) =
  simplifyFixpoint mainExpr
simplifyTopLevelAware (AProgram _ mainExpr) =
  Right SimplifyResult {simplifiedANF = mainExpr, appliedRewrites = []}

renderFullReport :: CompileReport -> Text
renderFullReport report =
  Text.concat
    [ "Result: " <> renderMachineResult (reportValue report) <> "\n"
    , section "Parsed AST" (renderDoc (prettyProgram (reportParsed report)))
    , section "Type" (renderDoc (prettyType (reportType report)))
    , section "Result" (renderValue (reportValue report))
    , section "ANF IR" (renderANFProgram (reportANF report))
    , section "Inferred Facts" (renderFacts (reportFacts report))
    , section "Optimized ANF IR" (renderANFProgram (reportOptimizedANF report))
    , section "Applied Rewrites" (renderAppliedRewrites (reportAppliedRewrites report))
    , section "EGraph Optimized ANF IR" (renderEGraphReport (reportEGraph report))
    , section "Egglog Optimizer" (renderEgglogReport (reportEgglog report))
    , section "Core IR" (renderCore (reportCore report))
    ]

renderMachineResult :: Value -> Text
renderMachineResult = \case
  VInt n -> renderValue (VInt n)
  VBool True -> "1"
  VBool False -> "0"
  VClosure {} -> "<function>"

renderGoldenReport :: CompileReport -> Text
renderGoldenReport report =
  Text.concat
    [ section "Type" (renderDoc (prettyType (reportType report)))
    , section "Result" (renderValue (reportValue report))
    , section "ANF IR" (renderANFProgram (reportANF report))
    , section "Inferred Facts" (renderFacts (reportFacts report))
    , section "Optimized ANF IR" (renderANFProgram (reportOptimizedANF report))
    , section "Applied Rewrites" (renderAppliedRewrites (reportAppliedRewrites report))
    , section "EGraph Optimized ANF IR" (renderEGraphReport (reportEGraph report))
    ]

renderCompileError :: CompileError -> Text
renderCompileError = \case
  CompileParseError parseError ->
    section "Parse error" parseError
  CompileTypeError typeError ->
    section "Type error" (renderLocatedTypeError typeError)
  CompileRuntimeError sourceRange runtimeError ->
    section "Runtime error" (renderSourceDiagnostic sourceRange "runtime error" (renderRuntimeError runtimeError))
  CompileSimplifyError simplifyError ->
    section "Simplify error" (renderSimplifyError simplifyError)
  CompileEgglogError egglogError ->
    section
      "Egglog error"
      ("Egglog optimization is required by --strict-egglog but unsupported in report mode: " <> renderEgglogBackendError egglogError)

section :: Text -> Text -> Text
section title body =
  "== " <> title <> " ==\n" <> Text.stripEnd body <> "\n"

renderEGraphReport :: Either EGraphError EGraphResult -> Text
renderEGraphReport = \case
  Right result ->
    Text.unlines
      [ renderANF (egraphOptimizedANF result)
      , "classes: " <> Text.pack (show (egraphClassCount result))
      , "rewrites: " <> Text.pack (show (egraphRewriteCount result))
      ]
  Left err ->
    renderEGraphError err

renderEgglogReport :: LegacyReportEgglog -> Text
renderEgglogReport = \case
  LegacyReportEgglogDisabled ->
    "status: disabled\n"
  LegacyReportEgglogAttempt (EgglogOptimized result) ->
    Text.unlines
      [ "status: optimized"
      , "optimized ANF:"
      , renderANF (optimizedANF result)
      , "original cost: " <> Text.pack (show (originalCost (extractionStats result)))
      , "optimized cost: " <> Text.pack (show (optimizedCost (extractionStats result)))
      , "run iterations: " <> Text.pack (show (runIterations (runStats result)))
      , "rebuild iterations: " <> Text.pack (show (rebuildIterations (rebuildStats result)))
      , "unions: " <> Text.pack (show (unionsCreated (rebuildStats result)))
      , "function entries: " <> Text.pack (show (functionEntries result))
      , "saturation: " <> yesNo (runSaturated (runStats result))
      , "canonicalized entries: " <> Text.pack (show (canonicalizedEntries (rebuildStats result)))
      , "merge conflicts: " <> Text.pack (show (mergeConflicts (rebuildStats result)))
      , "rules: " <> renderAppliedRuleSummary (appliedRules result)
      ]
  LegacyReportEgglogAttempt (EgglogUnsupported err) ->
    Text.unlines
      [ "status: unsupported"
      , "reason: " <> renderEgglogBackendError err
      ]
  LegacyReportEgglogAttempt (EgglogFailed err) ->
    Text.unlines
      [ "status: failed"
      , "reason: " <> renderEgglogBackendError err
      ]

renderAppliedRuleSummary :: [AppliedRuleSummary] -> Text
renderAppliedRuleSummary rules =
  case map (renderFunctionName . appliedRuleName) rules of
    [] -> "none"
    names -> Text.intercalate ", " names

yesNo :: Bool -> Text
yesNo True = "yes"
yesNo False = "no"
