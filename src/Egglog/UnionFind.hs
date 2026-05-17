module Egglog.UnionFind
  ( UnionFind (..)
  , emptyUnionFind
  , findId
  , insertId
  , unionIds
  )
where

import qualified Data.Map.Strict as Map
import Egglog.Sort

newtype UnionFind = UnionFind
  { parents :: Map.Map Id Id
  }
  deriving stock (Show, Eq, Ord)

emptyUnionFind :: UnionFind
emptyUnionFind =
  UnionFind Map.empty

insertId :: Id -> UnionFind -> UnionFind
insertId ident uf =
  uf {parents = Map.insertWith (\_ old -> old) ident ident (parents uf)}

findId :: UnionFind -> Id -> Id
findId uf ident =
  case Map.lookup ident (parents uf) of
    Just parent
      | parent /= ident -> findId uf parent
    _ -> ident

unionIds :: Id -> Id -> UnionFind -> (UnionFind, Bool)
unionIds lhs rhs uf
  | lhsRoot == rhsRoot = (uf', False)
  | otherwise =
      (uf' {parents = Map.insert rhsRoot lhsRoot (parents uf')}, True)
 where
  uf' = insertId lhs (insertId rhs uf)
  lhsRoot = findId uf' lhs
  rhsRoot = findId uf' rhs
