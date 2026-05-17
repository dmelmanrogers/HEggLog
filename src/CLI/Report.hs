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
import Eval.Interpreter (RuntimeError, Value, eval, renderRuntimeError, renderValue)
import IR.ANF (AExpr, renderANF, toANF)
import IR.Core (CoreProgram, lower, renderCore)
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
import Syntax.Parser (parseProgram)
import Syntax.Pretty (prettyExpr, prettyType, renderDoc)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (infer)
import Typecheck.Types (TypeError, renderTypeError)

data CompileReport = CompileReport
  { reportParsed :: Expr
  , reportType :: Type
  , reportValue :: Value
  , reportANF :: AExpr
  , reportFacts :: [Fact]
  , reportOptimizedANF :: AExpr
  , reportAppliedRewrites :: [AppliedRewrite]
  , reportCore :: CoreProgram
  }
  deriving stock (Show, Eq)

data CompileError
  = CompileParseError Text
  | CompileTypeError TypeError
  | CompileRuntimeError RuntimeError
  | CompileSimplifyError SimplifyError
  deriving stock (Show, Eq)

compileReport :: FilePath -> Text -> Either CompileError CompileReport
compileReport path source = do
  parsed <-
    case parseProgram path source of
      Left parseError -> Left (CompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  inferredType <-
    case infer parsed of
      Left typeError -> Left (CompileTypeError typeError)
      Right ty -> Right ty
  value <-
    case eval parsed of
      Left runtimeError -> Left (CompileRuntimeError runtimeError)
      Right result -> Right result
  let anf = toANF parsed
  simplified <-
    case simplifyFixpoint anf of
      Left simplifyError -> Left (CompileSimplifyError simplifyError)
      Right result -> Right result
  pure
    CompileReport
      { reportParsed = parsed
      , reportType = inferredType
      , reportValue = value
      , reportANF = anf
      , reportFacts = inferFacts anf
      , reportOptimizedANF = simplifiedANF simplified
      , reportAppliedRewrites = appliedRewrites simplified
      , reportCore = optimize (lower parsed)
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
    ]

renderCompileError :: CompileError -> Text
renderCompileError = \case
  CompileParseError parseError ->
    section "Parse error" parseError
  CompileTypeError typeError ->
    section "Type error" (renderTypeError typeError)
  CompileRuntimeError runtimeError ->
    section "Runtime error" (renderRuntimeError runtimeError)
  CompileSimplifyError simplifyError ->
    section "Simplify error" (renderSimplifyError simplifyError)

section :: Text -> Text -> Text
section title body =
  "== " <> title <> " ==\n" <> Text.stripEnd body <> "\n"
