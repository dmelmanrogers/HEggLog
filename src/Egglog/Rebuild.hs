module Egglog.Rebuild
  ( RebuildStats (..)
  , emptyRebuildStats
  , rebuild
  )
where

import qualified Data.Map.Strict as Map
import Egglog.Database
import Egglog.Function
import Egglog.Sort
import Egglog.Value

data RebuildStats = RebuildStats
  { canonicalizedEntries :: Int
  , mergeConflicts :: Int
  , unionsCreated :: Int
  , rebuildIterations :: Int
  }
  deriving stock (Show, Eq, Ord)

emptyRebuildStats :: RebuildStats
emptyRebuildStats =
  RebuildStats
    { canonicalizedEntries = 0
    , mergeConflicts = 0
    , unionsCreated = 0
    , rebuildIterations = 0
    }

-- Rebuild is the key egglog phase: all tables are canonicalized after unions,
-- conflicts exposed by canonicalization are resolved with merge behavior, and
-- MergeUnion conflicts may create more unions that require another pass.
rebuild :: Database -> Either EgglogError (Database, RebuildStats, Bool)
rebuild =
  loop 0 emptyRebuildStats
 where
  loop iteration stats db
    | iteration > maxIterations =
        Left (RebuildDidNotConverge maxIterations)
    | otherwise = do
        (db', passStats, changed) <- rebuildOnce db
        let stats' = addStats stats passStats {rebuildIterations = 1}
        if changed
          then loop (iteration + 1) stats' db'
          else pure (db', stats', hasStats stats')

  maxIterations = 64

rebuildOnce :: Database -> Either EgglogError (Database, RebuildStats, Bool)
rebuildOnce db = do
  (db', stats) <- foldl rebuildFunction (Right (db {tables = Map.empty}, emptyRebuildStats)) (Map.toList (tables db))
  pure (db', stats, hasStats stats)

rebuildFunction :: Either EgglogError (Database, RebuildStats) -> (FunctionName, FunctionTable) -> Either EgglogError (Database, RebuildStats)
rebuildFunction acc (name, table) = do
  (db, stats) <- acc
  decl <- getDecl name db
  foldl (reinsertEntry decl name) (Right (db, stats)) (Map.toList table)

reinsertEntry :: FunctionDecl -> FunctionName -> Either EgglogError (Database, RebuildStats) -> ([Value], Value) -> Either EgglogError (Database, RebuildStats)
reinsertEntry decl name acc (args, value) = do
  (db, stats) <- acc
  let canonicalKey = canonicalArgs db args
      canonicalOutput = canonicalValue db value
      canonicalized =
        if canonicalKey /= args || canonicalOutput /= value
          then 1
          else 0
      table = Map.findWithDefault Map.empty name (tables db)
  case Map.lookup canonicalKey table of
    Nothing ->
      let db' = db {tables = Map.insert name (Map.insert canonicalKey canonicalOutput table) (tables db)}
       in pure (db', stats {canonicalizedEntries = canonicalizedEntries stats + canonicalized})
    Just oldValue -> do
      (dbMerged, mergedValue, _changed, unionCreated) <- mergeValues decl canonicalKey oldValue canonicalOutput db
      let table' = Map.insert canonicalKey (canonicalValue dbMerged mergedValue) table
          db' = dbMerged {tables = Map.insert name table' (tables dbMerged)}
      pure
        ( db'
        , stats
            { canonicalizedEntries = canonicalizedEntries stats + canonicalized
            , mergeConflicts = mergeConflicts stats + 1
            , unionsCreated =
                unionsCreated stats
                  + if unionCreated then 1 else 0
            }
        )

addStats :: RebuildStats -> RebuildStats -> RebuildStats
addStats lhs rhs =
  RebuildStats
    { canonicalizedEntries = canonicalizedEntries lhs + canonicalizedEntries rhs
    , mergeConflicts = mergeConflicts lhs + mergeConflicts rhs
    , unionsCreated = unionsCreated lhs + unionsCreated rhs
    , rebuildIterations = rebuildIterations lhs + rebuildIterations rhs
    }

hasStats :: RebuildStats -> Bool
hasStats stats =
  canonicalizedEntries stats > 0
    || mergeConflicts stats > 0
    || unionsCreated stats > 0
