module Egglog.Pretty
  ( renderEgglogError
  , renderRebuildStats
  , renderRunResult
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Database
import Egglog.Eval
import Egglog.Rebuild
import Egglog.Sort
import Egglog.Value

renderEgglogError :: EgglogError -> Text
renderEgglogError = \case
  UnknownFunction name ->
    "unknown function: " <> renderFunctionName name
  ArityMismatch name expected actual ->
    "arity mismatch for " <> renderFunctionName name <> ": expected " <> showText expected <> ", got " <> showText actual
  SortMismatch expected actual ->
    "sort mismatch: expected " <> renderSort expected <> ", got " <> renderValue actual
  InvalidDefault name behavior sort ->
    "invalid default for " <> renderFunctionName name <> ": " <> showText behavior <> " cannot produce " <> renderSort sort
  MissingDefault name ->
    "missing default for " <> renderFunctionName name
  FunctionalDependencyConflict name args oldValue newValue merge ->
    "functional dependency conflict for "
      <> renderFunctionName name
      <> "("
      <> Text.intercalate ", " (map renderValue args)
      <> "): "
      <> renderValue oldValue
      <> " vs "
      <> renderValue newValue
      <> " under "
      <> showText merge
  CannotUnionBaseValues lhs rhs ->
    "cannot union base values " <> renderValue lhs <> " and " <> renderValue rhs
  CannotUnionDifferentSorts lhs rhs ->
    "cannot union values from different sorts " <> renderValue lhs <> " and " <> renderValue rhs
  InvalidMerge name merge lhs rhs ->
    "invalid merge for " <> renderFunctionName name <> " using " <> showText merge <> ": " <> renderValue lhs <> " vs " <> renderValue rhs
  UnboundVariable name ->
    "unbound variable: " <> renderVarName name
  PatternSortMismatch name expected actual ->
    "pattern variable " <> renderVarName name <> " expected " <> renderSort expected <> ", got " <> renderValue actual
  QueryTypeError message ->
    "query type error: " <> message
  RebuildDidNotConverge iterations ->
    "rebuild did not converge within " <> showText iterations <> " iterations"
  RunDidNotConverge iterations ->
    "run did not converge within " <> showText iterations <> " iterations"
  ExtractionError message ->
    "extraction failed: " <> message

renderRebuildStats :: RebuildStats -> Text
renderRebuildStats stats =
  Text.intercalate
    ", "
    [ "canonicalized=" <> showText (canonicalizedEntries stats)
    , "conflicts=" <> showText (mergeConflicts stats)
    , "unions=" <> showText (unionsCreated stats)
    , "iterations=" <> showText (rebuildIterations stats)
    ]

renderRunResult :: RunResult -> Text
renderRunResult result =
  "iterations="
    <> showText (resultIterations result)
    <> ", saturated="
    <> showText (resultSaturated result)
    <> ", "
    <> renderRebuildStats (resultRebuildStats result)

showText :: Show a => a -> Text
showText =
  Text.pack . show
