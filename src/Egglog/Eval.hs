module Egglog.Eval
  ( DeltaDatabase (..)
  , RunMode (..)
  , RunConfig (..)
  , RunResult (..)
  , applyAction
  , defaultRunConfig
  , evalRule
  , evalRuleSemiNaive
  , runProgram
  )
where

import Control.Monad (foldM)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Database
import Egglog.Function
import Egglog.Pattern
import Egglog.Rebuild
import Egglog.Rule
import Egglog.Sort
import Egglog.Value
import Runtime.Int (hintToInteger)

newtype DeltaDatabase = DeltaDatabase
  { deltaTables :: Map.Map FunctionName FunctionTable
  }
  deriving stock (Show, Eq, Ord)

data RunMode
  = RunNaive
  | RunSemiNaive
  deriving stock (Show, Eq, Ord)

data RunConfig = RunConfig
  { maxIterations :: Int
  , collectDebugLog :: Bool
  , stopOnSaturation :: Bool
  , runMode :: RunMode
  }
  deriving stock (Show, Eq, Ord)

data RunResult = RunResult
  { resultDatabase :: Database
  , resultIterations :: Int
  , resultSaturated :: Bool
  , resultRebuildStats :: RebuildStats
  , resultAppliedRules :: [FunctionName]
  }
  deriving stock (Show, Eq)

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { maxIterations = 32
    , collectDebugLog = False
    , stopOnSaturation = True
    , runMode = RunSemiNaive
    }

runProgram :: RunConfig -> Program -> Either EgglogError RunResult
runProgram config program = do
  let db0 = databaseFromDecls (programDecls program)
  (db1, _) <- applyActionsWithTrace InitialActionTrace emptySubstitution db0 (programInitialActions program)
  (db2, initialStats, _) <- rebuild db1
  let db = clearDebugIfNeeded db2
      initialDelta = databaseDelta db0 db
  case runMode config of
    RunNaive ->
      loopNaive 0 initialStats [] db
    RunSemiNaive ->
      loopSemiNaive 0 initialStats [] initialDelta db
 where
  loopNaive iteration stats applied db
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
                , resultAppliedRules = reverse applied
                }
    | otherwise = do
        (dbAfterRules, ruleChanged, appliedThisIteration) <- applyRules db (programRules program)
        (dbAfterRebuild, passStats, rebuildChanged) <- rebuild dbAfterRules
        let stats' = addRebuildStats stats passStats
            changed = ruleChanged || rebuildChanged
            db' = clearDebugIfNeeded dbAfterRebuild
            applied' = reverse appliedThisIteration <> applied
        if stopOnSaturation config && not changed
          then
            Right
              RunResult
                { resultDatabase = db'
                , resultIterations = iteration + 1
                , resultSaturated = True
                , resultRebuildStats = stats'
                , resultAppliedRules = reverse applied'
                }
          else loopNaive (iteration + 1) stats' applied' db'

  loopSemiNaive iteration stats applied delta db
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
                , resultAppliedRules = reverse applied
                }
    | otherwise = do
        (dbAfterRules, ruleChanged, appliedThisIteration) <- applyRulesSemiNaive delta db (programRules program)
        (dbAfterRebuild, passStats, rebuildChanged) <- rebuild dbAfterRules
        let stats' = addRebuildStats stats passStats
            changed = ruleChanged || rebuildChanged
            db' = clearDebugIfNeeded dbAfterRebuild
            delta' = databaseDelta db db'
            applied' = reverse appliedThisIteration <> applied
        if stopOnSaturation config && not changed
          then
            Right
              RunResult
                { resultDatabase = db'
                , resultIterations = iteration + 1
                , resultSaturated = True
                , resultRebuildStats = stats'
                , resultAppliedRules = reverse applied'
                }
          else loopSemiNaive (iteration + 1) stats' applied' delta' db'

  clearDebugIfNeeded db
    | collectDebugLog config = db
    | otherwise = db {debugLog = []}

applyRules :: Database -> [Rule] -> Either EgglogError (Database, Bool, [FunctionName])
applyRules startDb =
  foldM applyRule (startDb, False, [])
 where
  applyRule (currentDb, alreadyChanged, applied) rule = do
    substitutions <- evalRule currentDb rule
    (nextDb, ruleChanged) <- foldM applySubstitution (currentDb, False) (zip [(0 :: Int) ..] substitutions)
    pure
      ( nextDb
      , alreadyChanged || ruleChanged
      , if ruleChanged then ruleName rule : applied else applied
      )
   where
    applySubstitution (actionDb, substitutionChanged) (substIndex, subst) = do
      (nextDb, actionChanged) <-
        applyActionsWithTrace
          (RuleActionTrace (ruleName rule) substIndex subst)
          subst
          actionDb
          (ruleActions rule)
      pure (nextDb, substitutionChanged || actionChanged)

applyRulesSemiNaive :: DeltaDatabase -> Database -> [Rule] -> Either EgglogError (Database, Bool, [FunctionName])
applyRulesSemiNaive delta startDb =
  foldM applyRule (startDb, False, [])
 where
  applyRule (currentDb, alreadyChanged, applied) rule = do
    substitutions <- evalRuleSemiNaive delta currentDb rule
    (nextDb, ruleChanged) <- foldM applySubstitution (currentDb, False) (zip [(0 :: Int) ..] substitutions)
    pure
      ( nextDb
      , alreadyChanged || ruleChanged
      , if ruleChanged then ruleName rule : applied else applied
      )
   where
    applySubstitution (actionDb, substitutionChanged) (substIndex, subst) = do
      (nextDb, actionChanged) <-
        applyActionsWithTrace
          (RuleActionTrace (ruleName rule) substIndex subst)
          subst
          actionDb
          (ruleActions rule)
      pure (nextDb, substitutionChanged || actionChanged)

evalRule :: Database -> Rule -> Either EgglogError [Substitution]
evalRule db rule =
  evalPlannedRule Nothing db (planRulePremises Nothing db Nothing rule)

evalRuleSemiNaive :: DeltaDatabase -> Database -> Rule -> Either EgglogError [Substitution]
evalRuleSemiNaive delta db rule =
  case semiNaivePlans delta rule of
    RunRuleNaively ->
      evalRule db rule
    SkipRuleUntilDelta ->
      pure []
    RunRuleWithDeltaPremises premiseIndexes -> do
      substitutions <- concat <$> traverse (evalRuleWithDeltaPremise delta db rule) premiseIndexes
      pure (dedupeSubstitutions substitutions)

data RuleSchedule
  = RunRuleNaively
  | SkipRuleUntilDelta
  | RunRuleWithDeltaPremises [Int]
  deriving stock (Show, Eq, Ord)

dedupeSubstitutions :: [Substitution] -> [Substitution]
dedupeSubstitutions =
  reverse . snd . foldl step (Set.empty, [])
 where
  step (seen, acc) subst
    | subst `Set.member` seen = (seen, acc)
    | otherwise = (Set.insert subst seen, subst : acc)

semiNaivePlans :: DeltaDatabase -> Rule -> RuleSchedule
semiNaivePlans delta rule
  | null (rulePremises rule) = RunRuleNaively
  | null deltaEligibleIndexes = RunRuleNaively
  | null changedIndexes = SkipRuleUntilDelta
  | otherwise = RunRuleWithDeltaPremises changedIndexes
 where
  indexedPremises =
    zip [0 ..] (rulePremises rule)
  deltaEligibleIndexes =
    [index | (index, atom) <- indexedPremises, isDeltaEligible atom]
  changedIndexes =
    [index | (index, atom) <- indexedPremises, atomHasDelta delta atom]

evalRuleWithDeltaPremise :: DeltaDatabase -> Database -> Rule -> Int -> Either EgglogError [Substitution]
evalRuleWithDeltaPremise delta db rule deltaIndex =
  evalPlannedRule (Just delta) db (planRulePremises (Just delta) db (Just deltaIndex) rule)

data PlannedQueryAtom = PlannedQueryAtom
  { plannedAtomIndex :: Int
  , plannedAtom :: QueryAtom
  , plannedUsesDelta :: Bool
  }
  deriving stock (Show, Eq, Ord)

planRulePremises :: Maybe DeltaDatabase -> Database -> Maybe Int -> Rule -> [PlannedQueryAtom]
planRulePremises maybeDelta db deltaIndex rule =
  stableSortPlannedAtoms $
    [ PlannedQueryAtom
        { plannedAtomIndex = index
        , plannedAtom = atom
        , plannedUsesDelta = Just index == deltaIndex
        }
    | (index, atom) <- zip [0 ..] (rulePremises rule)
    ]
 where
  stableSortPlannedAtoms =
    sortOn (staticJoinCost maybeDelta db)

evalPlannedRule :: Maybe DeltaDatabase -> Database -> [PlannedQueryAtom] -> Either EgglogError [Substitution]
evalPlannedRule maybeDelta db atoms =
  evalRemaining atoms emptySubstitution
 where
  evalRemaining remaining subst =
    case remaining of
      [] ->
        Right [subst]
      _ ->
        case chooseNextAtom maybeDelta db subst remaining of
          Nothing ->
            Right []
          Just (atom, rest) -> do
            substitutions <- evalPlannedAtom maybeDelta db atom subst
            concat <$> traverse (evalRemaining rest) substitutions

evalPlannedAtom :: Maybe DeltaDatabase -> Database -> PlannedQueryAtom -> Substitution -> Either EgglogError [Substitution]
evalPlannedAtom maybeDelta db planned subst
  | plannedUsesDelta planned
  , Just delta <- maybeDelta =
      evalQueryAtomDelta delta db (plannedAtom planned) subst
  | otherwise =
      evalQueryAtom db (plannedAtom planned) subst

chooseNextAtom :: Maybe DeltaDatabase -> Database -> Substitution -> [PlannedQueryAtom] -> Maybe (PlannedQueryAtom, [PlannedQueryAtom])
chooseNextAtom maybeDelta db subst atoms =
  case selectBestOn (dynamicJoinCost maybeDelta db subst) (filter (premiseReady subst . plannedAtom) atoms) of
    Nothing ->
      Nothing
    Just best ->
      Just (best, filter ((/= plannedAtomIndex best) . plannedAtomIndex) atoms)
 where
  selectBestOn _ [] =
    Nothing
  selectBestOn score (first : rest) =
    Just $
      foldl
        ( \currentBest candidate ->
            if score candidate < score currentBest
              then candidate
              else currentBest
        )
        first
        rest

data JoinCost = JoinCost
  { joinEstimatedRows :: Int
  , joinUnboundVariables :: Int
  , joinOriginalIndex :: Int
  }
  deriving stock (Show, Eq, Ord)

staticJoinCost :: Maybe DeltaDatabase -> Database -> PlannedQueryAtom -> JoinCost
staticJoinCost maybeDelta db planned =
  JoinCost
    { joinEstimatedRows = estimatedRows maybeDelta db planned
    , joinUnboundVariables = Set.size (queryAtomVariables (plannedAtom planned))
    , joinOriginalIndex = plannedAtomIndex planned
    }

dynamicJoinCost :: Maybe DeltaDatabase -> Database -> Substitution -> PlannedQueryAtom -> JoinCost
dynamicJoinCost maybeDelta db subst planned =
  JoinCost
    { joinEstimatedRows = adjustedRows
    , joinUnboundVariables = Set.size (queryAtomVariables atom `Set.difference` boundVars)
    , joinOriginalIndex = plannedAtomIndex planned
    }
 where
  atom = plannedAtom planned
  boundVars = Map.keysSet subst
  boundInputs = Set.size (queryAtomVariables atom `Set.intersection` boundVars)
  baseRows = estimatedRows maybeDelta db planned
  adjustedRows = baseRows `div` (boundInputs + 1)

estimatedRows :: Maybe DeltaDatabase -> Database -> PlannedQueryAtom -> Int
estimatedRows maybeDelta db planned =
  case queryAtomFunction (plannedAtom planned) of
    Just name
      | plannedUsesDelta planned
      , Just delta <- maybeDelta ->
          Map.size (deltaTable name delta)
      | otherwise ->
          Map.size (Map.findWithDefault Map.empty name (tables db))
    Nothing ->
      1

premiseReady :: Substitution -> QueryAtom -> Bool
premiseReady subst atom =
  case atom of
    QLookup _ args outPattern ->
      varsReady (foldMap patternMatchRequiredVars (outPattern : args))
    QMatch (PCall _ args) outPattern ->
      varsReady (foldMap patternMatchRequiredVars (outPattern : args))
    QMatch pattern outPattern ->
      varsReady (patternTermRequiredVars pattern <> patternMatchRequiredVars outPattern)
    QEq lhs rhs ->
      (varsReady (patternTermRequiredVars lhs) && varsReady (patternMatchRequiredVars rhs))
        || (varsReady (patternTermRequiredVars rhs) && varsReady (patternMatchRequiredVars lhs))
 where
  boundVars = Map.keysSet subst
  varsReady required =
    required `Set.isSubsetOf` boundVars

queryAtomVariables :: QueryAtom -> Set.Set VarName
queryAtomVariables = \case
  QLookup _ args outPattern ->
    foldMap patternVariables (outPattern : args)
  QMatch pattern outPattern ->
    patternVariables pattern <> patternVariables outPattern
  QEq lhs rhs ->
    patternVariables lhs <> patternVariables rhs

patternVariables :: Pattern -> Set.Set VarName
patternVariables = \case
  PVar name _ ->
    Set.singleton name
  PValue {} ->
    Set.empty
  PCall _ args ->
    foldMap patternVariables args
  PAddInt lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PSubInt lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PMulInt lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PIntLt lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PIntEq lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PBoolEq lhs rhs ->
    patternVariables lhs <> patternVariables rhs
  PKnownInt inner ->
    patternVariables inner
  PKnownBool inner ->
    patternVariables inner
  PZeroInfo inner ->
    patternVariables inner

patternTermRequiredVars :: Pattern -> Set.Set VarName
patternTermRequiredVars = \case
  PVar name _ ->
    Set.singleton name
  PValue {} ->
    Set.empty
  PCall _ args ->
    foldMap patternTermRequiredVars args
  PAddInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PSubInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PMulInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PIntLt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PIntEq lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PBoolEq lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PKnownInt inner ->
    patternTermRequiredVars inner
  PKnownBool inner ->
    patternTermRequiredVars inner
  PZeroInfo inner ->
    patternTermRequiredVars inner

patternMatchRequiredVars :: Pattern -> Set.Set VarName
patternMatchRequiredVars = \case
  PVar {} ->
    Set.empty
  PValue {} ->
    Set.empty
  PCall _ args ->
    foldMap patternMatchRequiredVars args
  PAddInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PSubInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PMulInt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PIntLt lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PIntEq lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PBoolEq lhs rhs ->
    patternTermRequiredVars lhs <> patternTermRequiredVars rhs
  PKnownInt inner ->
    patternMatchRequiredVars inner
  PKnownBool inner ->
    patternMatchRequiredVars inner
  PZeroInfo inner ->
    patternMatchRequiredVars inner

isDeltaEligible :: QueryAtom -> Bool
isDeltaEligible atom =
  case queryAtomFunction atom of
    Just {} -> True
    Nothing -> False

atomHasDelta :: DeltaDatabase -> QueryAtom -> Bool
atomHasDelta delta atom =
  case queryAtomFunction atom of
    Just name -> not (Map.null (deltaTable name delta))
    Nothing -> False

queryAtomFunction :: QueryAtom -> Maybe FunctionName
queryAtomFunction = \case
  QLookup name _ _ ->
    Just name
  QMatch (PCall name _) _ ->
    Just name
  QMatch {} ->
    Nothing
  QEq {} ->
    Nothing

evalQueryAtom :: Database -> QueryAtom -> Substitution -> Either EgglogError [Substitution]
evalQueryAtom db = \case
  QLookup name args outPattern ->
    evalLookupAtom db name args outPattern
  QMatch pattern outPattern ->
    evalMatchAtom db pattern outPattern
  QEq lhs rhs ->
    evalEqualityAtom db lhs rhs

evalQueryAtomDelta :: DeltaDatabase -> Database -> QueryAtom -> Substitution -> Either EgglogError [Substitution]
evalQueryAtomDelta delta db = \case
  QLookup name args outPattern ->
    evalLookupAtomInTable db (deltaTable name delta) name args outPattern
  QMatch (PCall name argPatterns) outPattern ->
    evalLookupAtomInTable db (deltaTable name delta) name argPatterns outPattern
  atom ->
    evalQueryAtom db atom

evalLookupAtom :: Database -> FunctionName -> [Pattern] -> Pattern -> Substitution -> Either EgglogError [Substitution]
evalLookupAtom db name argPatterns outPattern subst = do
  evalLookupAtomInTable db (Map.findWithDefault Map.empty name (tables db)) name argPatterns outPattern subst

evalLookupAtomInTable :: Database -> FunctionTable -> FunctionName -> [Pattern] -> Pattern -> Substitution -> Either EgglogError [Substitution]
evalLookupAtomInTable db table name argPatterns outPattern subst = do
  decl <- getDecl name db
  if length (functionArgSorts decl) /= length argPatterns
    then Left (ArityMismatch name (length (functionArgSorts decl)) (length argPatterns))
    else foldM collect [] (Map.toList table)
 where
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
    PSubInt {} ->
      matchComputed
    PMulInt {} ->
      matchComputed
    PIntLt {} ->
      matchComputed
    PIntEq {} ->
      matchComputed
    PBoolEq {} ->
      matchComputed
    PKnownInt inner ->
      case canonical of
        VConstInt (KnownInt n) -> matchPattern db inner (VInt (hintToInteger n)) subst
        _ -> pure []
    PKnownBool inner ->
      case canonical of
        VConstBool (KnownBool b) -> matchPattern db inner (VBool b) subst
        _ -> pure []
    PZeroInfo inner ->
      case canonical of
        VZeroInfo info -> matchZeroInfo inner info
        _ -> pure []
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

  matchZeroInfo inner info = do
    maybeValue <- evalExistingPattern db subst inner
    case maybeValue of
      Just (VInt n)
        | zeroInfoFromInteger n == info -> pure [subst]
        | otherwise -> pure []
      Just _ -> Left (QueryTypeError "expected Int operand for ZeroInfo")
      Nothing -> pure []

data ActionTraceContext
  = InitialActionTrace
  | RuleActionTrace FunctionName Int Substitution
  deriving stock (Show, Eq, Ord)

applyActionsWithTrace :: ActionTraceContext -> Substitution -> Database -> [Action] -> Either EgglogError (Database, Bool)
applyActionsWithTrace traceContext subst startDb =
  foldM applyOne (startDb, False)
 where
  applyOne (currentDb, alreadyChanged) action = do
    (nextDb, actionChanged) <- applyAction subst currentDb action
    pure (annotateActionTrace traceContext action actionChanged nextDb, alreadyChanged || actionChanged)

annotateActionTrace :: ActionTraceContext -> Action -> Bool -> Database -> Database
annotateActionTrace _ _ False db =
  db
annotateActionTrace traceContext action True db =
  db {debugLog = renderActionTrace traceContext action : debugLog db}

renderActionTrace :: ActionTraceContext -> Action -> Text
renderActionTrace InitialActionTrace action =
  "initial action: " <> renderAction action
renderActionTrace (RuleActionTrace name substIndex subst) action =
  "rule "
    <> renderFunctionName name
    <> " substitution #"
    <> Text.pack (show substIndex)
    <> " "
    <> renderSubstitution subst
    <> ": "
    <> renderAction action

renderSubstitution :: Substitution -> Text
renderSubstitution subst
  | Map.null subst = "{}"
  | otherwise =
      "{"
        <> Text.intercalate
          ", "
          [renderVarName name <> "=" <> renderValue value | (name, value) <- Map.toAscList subst]
        <> "}"

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

databaseDelta :: Database -> Database -> DeltaDatabase
databaseDelta before after =
  DeltaDatabase
    { deltaTables =
        Map.mapMaybeWithKey changedTableAfter (normalizeTables after after)
    }
 where
  beforeTables =
    normalizeTables before before

  changedTableAfter name afterTable =
    let beforeTable = Map.findWithDefault Map.empty name beforeTables
        entries =
          Map.filterWithKey
            ( \args outValue ->
                Map.lookup args beforeTable /= Just outValue
            )
            afterTable
     in if Map.null entries then Nothing else Just entries

deltaTable :: FunctionName -> DeltaDatabase -> FunctionTable
deltaTable name delta =
  Map.findWithDefault Map.empty name (deltaTables delta)

normalizeTables :: Database -> Database -> Map.Map FunctionName FunctionTable
normalizeTables canonicalDb sourceDb =
  Map.map (normalizeFunctionTable canonicalDb) (tables sourceDb)

normalizeFunctionTable :: Database -> FunctionTable -> FunctionTable
normalizeFunctionTable db =
  Map.fromList . map normalizeEntry . Map.toList
 where
  normalizeEntry (args, outValue) =
    (canonicalArgs db args, canonicalValue db outValue)
