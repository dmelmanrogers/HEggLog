module Egglog.Function
  ( DefaultBehavior (..)
  , FunctionDecl (..)
  , MergeBehavior (..)
  , relation
  )
where

import Egglog.Sort

data DefaultBehavior
  = DefaultFreshId
  | DefaultNone
  | DefaultUnit
  deriving stock (Show, Eq, Ord)

data MergeBehavior
  = MergeUnion
  | MergeKeepOld
  | MergeMinInt
  | MergeMaxInt
  | MergeError
  deriving stock (Show, Eq, Ord)

data FunctionDecl = FunctionDecl
  { functionName :: FunctionName
  , functionArgSorts :: [Sort]
  , functionResultSort :: Sort
  , functionDefault :: DefaultBehavior
  , functionMerge :: MergeBehavior
  }
  deriving stock (Show, Eq, Ord)

relation :: FunctionName -> [Sort] -> FunctionDecl
relation name argSorts =
  FunctionDecl
    { functionName = name
    , functionArgSorts = argSorts
    , functionResultSort = SUnit
    , functionDefault = DefaultNone
    , functionMerge = MergeKeepOld
    }

