module Egglog.Eval
  ( DeltaDatabase (..)
  , RunConfig (..)
  , RunResult (..)
  , applyAction
  , defaultRunConfig
  , evalRule
  , runProgram
  )
where

import Control.Monad (foldM)
import qualified Data.Map.Strict as Map
import Egglog.Database
import Egglog.Function
import Egglog.Pattern
import Egglog.Rebuild
import Egglog.Rule
import Egglog.Sort
import Egglog.Value

data DeltaDatabase = DeltaDatabase
  deriving stock (Show, Eq, Ord)

-- TODO: carry per-function deltas here and evaluate rules incrementally once
-- the kernel grows a real semi-naive planner. The evaluator below is deliberately
-- naive and bounded; it does not pretend to be incremental.
data RunConfig = RunConfig
  { maxIterations :: Int
  , collectDebugLog :: Bool
  , stopOnSaturation :: Bool
  }
  deriving stock (Show, Eq, Ord)

data RunResult = RunResult
  { resultDatabase :: Database
  , resultIterations :: Int
  , resultSaturated :: Bool
  , resultRebuildStats :: RebuildStats
  }
  deriving stock (Show, Eq)

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { maxIterations = 32
    , collectDebugLog = False
    , stopOnSaturation = True
    }

runProgram :: RunConfig -> Program -> Either EgglogError RunResult
runProgram config program = do
  let db0 = databaseFromDecls (programDecls program)
  (db1, _) <- applyActions emptySubstitution db0 (programInitialActions program)
  (db2, initialStats, _) <- rebuild db1
  loop 0 initialStats (clearDebugIfNeeded db2)
 where
  loop iteration stats db
    | iteration >= maxIterations config =
        if stopOnSaturation config
          then Left (RunDidNotConverge (maxIterations config))
          else
            Right
              RunResult
                { resultDatabase = db
                , resultIterations = iteration
                , resultSaturated = False
                , resultRebuildStats = stats
                }
    | otherwise = do
        (dbAfterRules, ruleChanged) <- applyRules db (programRules program)
        (dbAfterRebuild, passStats, rebuildChanged) <- rebuild dbAfterRules
        let stats' = addRebuildStats stats passStats
            changed = ruleChanged || rebuildChanged
            db' = clearDebugIfNeeded dbAfterRebuild
        if stopOnSaturation config && not changed
          then
            Right
              RunResult
                { resultDatabase = db'
                , resultIterations = iteration + 1
                , resultSaturated = True
                , resultRebuildStats = stats'
                }
          else loop (iteration + 1) stats' db'

  clearDebugIfNeeded db
    | collectDebugLog config = db
    | otherwise = db {debugLog = []}

applyRules :: Database -> [Rule] -> Either EgglogError (Database, Bool)
applyRules startDb =
  foldM applyRule (startDb, False)
 where
  applyRule (currentDb, alreadyChanged) rule = do
    substitutions <- evalRule currentDb rule
    (nextDb, ruleChanged) <- foldM applySubstitution (currentDb, False) substitutions
    pure (nextDb, alreadyChanged || ruleChanged)
   where
    applySubstitution (actionDb, substitutionChanged) subst = do
      (nextDb, actionChanged) <- applyActions subst actionDb (ruleActions rule)
      pure (nextDb, substitutionChanged || actionChanged)

evalRule :: Database -> Rule -> Either EgglogError [Substitution]
evalRule db rule =
  foldM extend [emptySubstitution] (rulePremises rule)
 where
  extend substitutions atom =
    concat <$> traverse (evalQueryAtom db atom) substitutions

evalQueryAtom :: Database -> QueryAtom -> Substitution -> Either EgglogError [Substitution]
evalQueryAtom db = \case
  QLookup name args outPattern ->
    evalLookupAtom db name args outPattern
  QMatch pattern outPattern ->
    evalMatchAtom db pattern outPattern
  QEq lhs rhs ->
    evalEqualityAtom db lhs rhs

evalLookupAtom :: Database -> FunctionName -> [Pattern] -> Pattern -> Substitution -> Either EgglogError [Substitution]
evalLookupAtom db name argPatterns outPattern subst = do
  decl <- getDecl name db
  if length (functionArgSorts decl) /= length argPatterns
    then Left (ArityMismatch name (length (functionArgSorts decl)) (length argPatterns))
    else foldM collect [] (Map.toList table)
 where
  table = Map.findWithDefault Map.empty name (tables db)

  collect matches (args, outValue) = do
    argSubsts <- matchPatterns db argPatterns (canonicalArgs db args) subst
    outSubsts <- concat <$> traverse (\s -> matchPattern db outPattern (canonicalValue db outValue) s) argSubsts
    pure (matches <> outSubsts)

evalMatchAtom :: Database -> Pattern -> Pattern -> Substitution -> Either EgglogError [Substitution]
evalMatchAtom db pattern outPattern subst =
  case pattern of
    PCall name argPatterns ->
      evalLookupAtom db name argPatterns outPattern subst
    _ -> do
      maybeValue <- evalExistingPattern db subst pattern
      case maybeValue of
        Nothing -> pure []
        Just value -> matchPattern db outPattern value subst

evalEqualityAtom :: Database -> Pattern -> Pattern -> Substitution -> Either EgglogError [Substitution]
evalEqualityAtom db lhs rhs subst = do
  lhsValue <- evalExistingPattern db subst lhs
  rhsValue <- evalExistingPattern db subst rhs
  case (lhsValue, rhsValue) of
    (Just lhsKnown, Just rhsKnown)
      | canonicalValue db lhsKnown == canonicalValue db rhsKnown -> pure [subst]
      | otherwise -> pure []
    (Just lhsKnown, Nothing) ->
      matchPattern db rhs lhsKnown subst
    (Nothing, Just rhsKnown) ->
      matchPattern db lhs rhsKnown subst
    (Nothing, Nothing) ->
      pure []

matchPatterns :: Database -> [Pattern] -> [Value] -> Substitution -> Either EgglogError [Substitution]
matchPatterns db patterns values subst =
  foldM extend [subst] (zip patterns values)
 where
  extend substitutions (pattern, value) =
    concat <$> traverse (matchPattern db pattern value) substitutions

matchPattern :: Database -> Pattern -> Value -> Substitution -> Either EgglogError [Substitution]
matchPattern db pattern value subst =
  case pattern of
    PVar name sort ->
      matchVar name sort
    PValue expected
      | canonicalValue db expected == canonicalValue db value -> pure [subst]
      | otherwise -> pure []
    PCall name argPatterns -> do
      decl <- getDecl name db
      if length (functionArgSorts decl) /= length argPatterns
        then Left (ArityMismatch name (length (functionArgSorts decl)) (length argPatterns))
        else pure ()
      let wanted = canonicalValue db value
          table = Map.findWithDefault Map.empty name (tables db)
          collect matches (args, outValue)
            | canonicalValue db outValue /= wanted = pure matches
            | otherwise = do
                substs <- matchPatterns db argPatterns (canonicalArgs db args) subst
                pure (matches <> substs)
      foldM collect [] (Map.toList table)
    PAddInt {} ->
      matchComputed
    PMulInt {} ->
      matchComputed
 where
  canonical = canonicalValue db value

  matchVar name sort
    | valueSort canonical /= sort =
        Left (PatternSortMismatch name sort canonical)
    | otherwise =
        case Map.lookup name subst of
          Nothing -> pure [Map.insert name canonical subst]
          Just existing
            | canonicalValue db existing == canonical -> pure [subst]
            | otherwise -> pure []

  matchComputed = do
    maybeValue <- evalExistingPattern db subst pattern
    case maybeValue of
      Just computed
        | computed == canonical -> pure [subst]
        | otherwise -> pure []
      Nothing -> pure []

applyActions :: Substitution -> Database -> [Action] -> Either EgglogError (Database, Bool)
applyActions subst startDb =
  foldM applyOne (startDb, False)
 where
  applyOne (currentDb, alreadyChanged) action = do
    (nextDb, actionChanged) <- applyAction subst currentDb action
    pure (nextDb, alreadyChanged || actionChanged)

applyAction :: Substitution -> Database -> Action -> Either EgglogError (Database, Bool)
applyAction subst db = \case
  ASet name argPatterns outPattern -> do
    (dbWithArgs, args) <- evalTerms db subst argPatterns
    (dbWithOut, outValue) <- evalTerm dbWithArgs subst outPattern
    (dbSet, setChanged) <- setFunction name args outValue dbWithOut
    pure (dbSet, dbSet /= db || setChanged)
  AUnion lhs rhs -> do
    (dbWithLhs, lhsValue) <- evalTerm db subst lhs
    (dbWithRhs, rhsValue) <- evalTerm dbWithLhs subst rhs
    (dbUnioned, unionChanged) <- unionValues lhsValue rhsValue dbWithRhs
    pure (dbUnioned, dbUnioned /= db || unionChanged)
  AAssert name argPatterns -> do
    (dbWithArgs, args) <- evalTerms db subst argPatterns
    (dbSet, setChanged) <- setFunction name args VUnit dbWithArgs
    pure (dbSet, dbSet /= db || setChanged)

evalTerms :: Database -> Substitution -> [Pattern] -> Either EgglogError (Database, [Value])
evalTerms db subst = \case
  [] ->
    Right (db, [])
  pattern : rest -> do
    (db1, value) <- evalTerm db subst pattern
    (db2, values) <- evalTerms db1 subst rest
    Right (db2, value : values)

addRebuildStats :: RebuildStats -> RebuildStats -> RebuildStats
addRebuildStats lhs rhs =
  RebuildStats
    { canonicalizedEntries = canonicalizedEntries lhs + canonicalizedEntries rhs
    , mergeConflicts = mergeConflicts lhs + mergeConflicts rhs
    , unionsCreated = unionsCreated lhs + unionsCreated rhs
    , rebuildIterations = rebuildIterations lhs + rebuildIterations rhs
    }
