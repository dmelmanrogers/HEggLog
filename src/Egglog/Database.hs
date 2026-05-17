module Egglog.Database
  ( Database (..)
  , EgglogError (..)
  , FunctionTable
  , canonicalArgs
  , canonicalValue
  , callFunction
  , databaseFromDecls
  , emptyDatabase
  , freshId
  , getDecl
  , lookupFunction
  , mergeValues
  , setFunction
  , unionValues
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Function
import Egglog.Sort
import Egglog.UnionFind
import Egglog.Value

type FunctionTable = Map.Map [Value] Value

data Database = Database
  { declarations :: Map.Map FunctionName FunctionDecl
  , tables :: Map.Map FunctionName FunctionTable
  , unionFinds :: Map.Map SortName UnionFind
  , nextIds :: Map.Map SortName Int
  , debugLog :: [Text]
  }
  deriving stock (Show, Eq)

data EgglogError
  = UnknownFunction FunctionName
  | ArityMismatch FunctionName Int Int
  | SortMismatch Sort Value
  | InvalidDefault FunctionName DefaultBehavior Sort
  | MissingDefault FunctionName
  | FunctionalDependencyConflict FunctionName [Value] Value Value MergeBehavior
  | CannotUnionBaseValues Value Value
  | CannotUnionDifferentSorts Value Value
  | InvalidMerge FunctionName MergeBehavior Value Value
  | UnboundVariable VarName
  | PatternSortMismatch VarName Sort Value
  | QueryTypeError Text
  | RebuildDidNotConverge Int
  | RunDidNotConverge Int
  | ExtractionError Text
  deriving stock (Show, Eq, Ord)

emptyDatabase :: Database
emptyDatabase =
  Database
    { declarations = Map.empty
    , tables = Map.empty
    , unionFinds = Map.empty
    , nextIds = Map.empty
    , debugLog = []
    }

databaseFromDecls :: [FunctionDecl] -> Database
databaseFromDecls decls =
  foldr addDecl emptyDatabase decls
 where
  addDecl decl db =
    db
      { declarations = Map.insert (functionName decl) decl (declarations db)
      , tables = Map.insert (functionName decl) Map.empty (tables db)
      , unionFinds = foldr ensureUserSort (unionFinds db) (functionResultSort decl : functionArgSorts decl)
      , nextIds = foldr ensureNextId (nextIds db) (functionResultSort decl : functionArgSorts decl)
      }
  ensureUserSort sortNameOrBase acc =
    case sortNameOrBase of
      SUser sortName -> Map.insertWith (\_ old -> old) sortName emptyUnionFind acc
      _ -> acc
  ensureNextId sortNameOrBase acc =
    case sortNameOrBase of
      SUser sortName -> Map.insertWith (\_ old -> old) sortName 0 acc
      _ -> acc

getDecl :: FunctionName -> Database -> Either EgglogError FunctionDecl
getDecl name db =
  case Map.lookup name (declarations db) of
    Just decl -> Right decl
    Nothing -> Left (UnknownFunction name)

freshId :: SortName -> Database -> (Value, Database)
freshId sortName db =
  let next = Map.findWithDefault 0 sortName (nextIds db)
      ident = Id next
      uf = Map.findWithDefault emptyUnionFind sortName (unionFinds db)
      db' =
        db
          { nextIds = Map.insert sortName (next + 1) (nextIds db)
          , unionFinds = Map.insert sortName (insertId ident uf) (unionFinds db)
          , debugLog = ("fresh " <> renderSortName sortName <> "#" <> Text.pack (show next)) : debugLog db
          }
   in (VId sortName ident, db')

canonicalValue :: Database -> Value -> Value
canonicalValue db = \case
  VId sortName ident ->
    let uf = Map.findWithDefault emptyUnionFind sortName (unionFinds db)
     in VId sortName (findId uf ident)
  value ->
    value

canonicalArgs :: Database -> [Value] -> [Value]
canonicalArgs db =
  map (canonicalValue db)

lookupFunction :: FunctionName -> [Value] -> Database -> Either EgglogError (Maybe Value)
lookupFunction name args db = do
  decl <- getDecl name db
  checkArgs decl args
  let key = canonicalArgs db args
  pure (canonicalValue db <$> Map.lookup key (Map.findWithDefault Map.empty name (tables db)))

callFunction :: FunctionName -> [Value] -> Database -> Either EgglogError (Database, Value, Bool)
callFunction name args db = do
  decl <- getDecl name db
  checkArgs decl args
  let key = canonicalArgs db args
      table = Map.findWithDefault Map.empty name (tables db)
  case Map.lookup key table of
    Just value ->
      pure (db, canonicalValue db value, False)
    Nothing -> do
      (value, dbWithDefault) <- defaultValue decl db
      let canonicalOutput = canonicalValue dbWithDefault value
          table' = Map.insert key canonicalOutput table
          db' =
            dbWithDefault
              { tables = Map.insert name table' (tables dbWithDefault)
              , debugLog = ("default " <> renderFunctionName name) : debugLog dbWithDefault
              }
      pure (db', canonicalOutput, True)

setFunction :: FunctionName -> [Value] -> Value -> Database -> Either EgglogError (Database, Bool)
setFunction name args value db = do
  decl <- getDecl name db
  checkArgs decl args
  checkSort (functionResultSort decl) value
  let key = canonicalArgs db args
      newValue = canonicalValue db value
      table = Map.findWithDefault Map.empty name (tables db)
  case Map.lookup key table of
    Nothing ->
      let db' =
            db
              { tables = Map.insert name (Map.insert key newValue table) (tables db)
              , debugLog = ("set " <> renderFunctionName name) : debugLog db
              }
       in pure (db', True)
    Just oldValue -> do
      (dbMerged, mergedValue, changed, _) <- mergeValues decl key (canonicalValue db oldValue) newValue db
      let table' = Map.insert key (canonicalValue dbMerged mergedValue) table
      pure
        ( dbMerged
            { tables = Map.insert name table' (tables dbMerged)
            , debugLog =
                if changed
                  then ("merge " <> renderFunctionName name) : debugLog dbMerged
                  else debugLog dbMerged
            }
        , changed
        )

unionValues :: Value -> Value -> Database -> Either EgglogError (Database, Bool)
unionValues lhs rhs db =
  case (canonicalValue db lhs, canonicalValue db rhs) of
    (VId lhsSort lhsId, VId rhsSort rhsId)
      | lhsSort == rhsSort ->
          let uf = Map.findWithDefault emptyUnionFind lhsSort (unionFinds db)
              (uf', changed) = unionIds lhsId rhsId uf
              db' =
                db
                  { unionFinds = Map.insert lhsSort uf' (unionFinds db)
                  , debugLog =
                      if changed
                        then ("union " <> renderSortName lhsSort) : debugLog db
                        else debugLog db
                  }
           in pure (db', changed)
      | otherwise ->
          Left (CannotUnionDifferentSorts lhs rhs)
    (baseLhs, baseRhs)
      | baseLhs == baseRhs -> pure (db, False)
      | otherwise -> Left (CannotUnionBaseValues baseLhs baseRhs)

mergeValues :: FunctionDecl -> [Value] -> Value -> Value -> Database -> Either EgglogError (Database, Value, Bool, Bool)
mergeValues decl key oldValue newValue db
  | canonicalValue db oldValue == canonicalValue db newValue =
      pure (db, canonicalValue db oldValue, False, False)
  | otherwise =
      case functionMerge decl of
        MergeUnion -> do
          case functionResultSort decl of
            SUser _ -> do
              (db', unionChanged) <- unionValues oldValue newValue db
              pure (db', canonicalValue db' oldValue, unionChanged, unionChanged)
            _ ->
              Left (InvalidMerge (functionName decl) MergeUnion oldValue newValue)
        MergeKeepOld ->
          pure (db, oldValue, False, False)
        MergeMinInt ->
          case (oldValue, newValue) of
            (VInt lhs, VInt rhs) ->
              let merged = VInt (min lhs rhs)
               in pure (db, merged, merged /= oldValue, False)
            _ ->
              Left (InvalidMerge (functionName decl) MergeMinInt oldValue newValue)
        MergeMaxInt ->
          case (oldValue, newValue) of
            (VInt lhs, VInt rhs) ->
              let merged = VInt (max lhs rhs)
               in pure (db, merged, merged /= oldValue, False)
            _ ->
              Left (InvalidMerge (functionName decl) MergeMaxInt oldValue newValue)
        MergeConstInt ->
          case (oldValue, newValue) of
            (VConstInt lhs, VConstInt rhs) ->
              let merged = VConstInt (joinConstInt lhs rhs)
               in pure (db, merged, merged /= oldValue, False)
            _ ->
              Left (InvalidMerge (functionName decl) MergeConstInt oldValue newValue)
        MergeConstBool ->
          case (oldValue, newValue) of
            (VConstBool lhs, VConstBool rhs) ->
              let merged = VConstBool (joinConstBool lhs rhs)
               in pure (db, merged, merged /= oldValue, False)
            _ ->
              Left (InvalidMerge (functionName decl) MergeConstBool oldValue newValue)
        MergeError ->
          Left (FunctionalDependencyConflict (functionName decl) key oldValue newValue MergeError)

defaultValue :: FunctionDecl -> Database -> Either EgglogError (Value, Database)
defaultValue decl db =
  case functionDefault decl of
    DefaultFreshId ->
      case functionResultSort decl of
        SUser sortName -> Right (freshId sortName db)
        sort -> Left (InvalidDefault (functionName decl) DefaultFreshId sort)
    DefaultUnit ->
      case functionResultSort decl of
        SUnit -> Right (VUnit, db)
        sort -> Left (InvalidDefault (functionName decl) DefaultUnit sort)
    DefaultNone ->
      Left (MissingDefault (functionName decl))

checkArgs :: FunctionDecl -> [Value] -> Either EgglogError ()
checkArgs decl args = do
  let expected = functionArgSorts decl
  if length expected == length args
    then mapM_ (uncurry checkSort) (zip expected args)
    else Left (ArityMismatch (functionName decl) (length expected) (length args))

checkSort :: Sort -> Value -> Either EgglogError ()
checkSort expected value
  | valueSort value == expected = Right ()
  | otherwise = Left (SortMismatch expected value)
