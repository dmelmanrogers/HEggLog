module Egglog.Sort
  ( FunctionName (..)
  , Id (..)
  , Sort (..)
  , SortName (..)
  , VarName (..)
  , renderFunctionName
  , renderSort
  , renderSortName
  , renderVarName
  )
where

import Data.Text (Text)

newtype SortName = SortName {unSortName :: Text}
  deriving stock (Show, Eq, Ord)

newtype FunctionName = FunctionName {unFunctionName :: Text}
  deriving stock (Show, Eq, Ord)

newtype VarName = VarName {unVarName :: Text}
  deriving stock (Show, Eq, Ord)

newtype Id = Id {unId :: Int}
  deriving stock (Show, Eq, Ord)

data Sort
  = SUser SortName
  | SInt
  | SBool
  | SUnit
  | SString
  deriving stock (Show, Eq, Ord)

renderSortName :: SortName -> Text
renderSortName =
  unSortName

renderFunctionName :: FunctionName -> Text
renderFunctionName =
  unFunctionName

renderVarName :: VarName -> Text
renderVarName =
  unVarName

renderSort :: Sort -> Text
renderSort = \case
  SUser name -> renderSortName name
  SInt -> "Int"
  SBool -> "Bool"
  SUnit -> "Unit"
  SString -> "String"
