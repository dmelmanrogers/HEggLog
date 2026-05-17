module CLI.Report
  ( CompileError (..)
  , CompileReport (..)
  , compileReport
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
import Eval.Interpreter (RuntimeError, Value, eval, renderRuntimeError, renderValue)
import IR.ANF (AExpr, renderANF, toANF)
import IR.Core (CoreProgram, lower, renderCore)
import Optimize.EgglogBackend
  ( AppliedRuleSummary (..)
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
import Optimize.Placeholder (optimize)
import Optimize.Simplify
  ( AppliedRewrite
  , SimplifyError
  , appliedRewrites
  , renderAppliedRewrites
  , renderSimplifyError
  , simplifiedANF
  , simplifyFixpoint
  )
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST (Expr, Type)
import Syntax.Located (locatedExprSpan, stripLocatedExpr)
import Syntax.Parser (parseLocatedProgram)
import Syntax.Pretty (prettyExpr, prettyType, renderDoc)
import Syntax.Span (SourceSpan, renderSourceDiagnostic)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (inferLocated)
import Typecheck.Types (LocatedTypeError, renderLocatedTypeError)

data CompileReport = CompileReport
  { reportParsed :: Expr
  , reportType :: Type
  , reportValue :: Value
  , reportANF :: AExpr
  , reportFacts :: [Fact]
  , reportOptimizedANF :: AExpr
  , reportAppliedRewrites :: [AppliedRewrite]
  , reportEGraph :: Either EGraphError EGraphResult
  , reportEgglog :: EgglogOptimizationAttempt
  , reportCore :: CoreProgram
  }
  deriving stock (Show, Eq)

data CompileError
  = CompileParseError Text
  | CompileTypeError LocatedTypeError
  | CompileRuntimeError SourceSpan RuntimeError
  | CompileSimplifyError SimplifyError
  deriving stock (Show, Eq)

compileReport :: FilePath -> Text -> Either CompileError CompileReport
compileReport path source = do
  parsed <-
    case parseLocatedProgram path source of
      Left parseError -> Left (CompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  let stripped = stripLocatedExpr parsed
  inferredType <-
    case inferLocated parsed of
      Left typeError -> Left (CompileTypeError typeError)
      Right ty -> Right ty
  value <-
    case eval stripped of
      Left runtimeError -> Left (CompileRuntimeError (locatedExprSpan parsed) runtimeError)
      Right result -> Right result
  let anf = toANF stripped
  simplified <-
    case simplifyFixpoint anf of
      Left simplifyError -> Left (CompileSimplifyError simplifyError)
      Right result -> Right result
  pure
    CompileReport
      { reportParsed = stripped
      , reportType = inferredType
      , reportValue = value
      , reportANF = anf
      , reportFacts = inferFacts anf
      , reportOptimizedANF = simplifiedANF simplified
      , reportAppliedRewrites = appliedRewrites simplified
      , reportEGraph = optimizeANF anf
      , reportEgglog = tryOptimizeWithEgglog defaultRunConfig anf
      , reportCore = optimize (lower stripped)
      }

renderFullReport :: CompileReport -> Text
renderFullReport report =
  Text.concat
    [ section "Parsed AST" (renderDoc (prettyExpr (reportParsed report)))
    , section "Type" (renderDoc (prettyType (reportType report)))
    , section "Result" (renderValue (reportValue report))
    , section "ANF IR" (renderANF (reportANF report))
    , section "Inferred Facts" (renderFacts (reportFacts report))
    , section "Optimized ANF IR" (renderANF (reportOptimizedANF report))
    , section "Applied Rewrites" (renderAppliedRewrites (reportAppliedRewrites report))
    , section "EGraph Optimized ANF IR" (renderEGraphReport (reportEGraph report))
    , section "Egglog Optimizer" (renderEgglogReport (reportEgglog report))
    , section "Core IR" (renderCore (reportCore report))
    ]

renderGoldenReport :: CompileReport -> Text
renderGoldenReport report =
  Text.concat
    [ section "Type" (renderDoc (prettyType (reportType report)))
    , section "Result" (renderValue (reportValue report))
    , section "ANF IR" (renderANF (reportANF report))
    , section "Inferred Facts" (renderFacts (reportFacts report))
    , section "Optimized ANF IR" (renderANF (reportOptimizedANF report))
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

renderEgglogReport :: EgglogOptimizationAttempt -> Text
renderEgglogReport = \case
  EgglogOptimized result ->
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
  EgglogUnsupported err ->
    Text.unlines
      [ "status: unsupported"
      , "reason: " <> renderEgglogBackendError err
      ]
  EgglogFailed err ->
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
