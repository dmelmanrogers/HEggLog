module Egglog.Value
  ( Value (..)
  , renderValue
  , valueSort
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Sort

data Value
  = VId SortName Id
  | VInt Integer
  | VBool Bool
  | VUnit
  | VString Text
  deriving stock (Show, Eq, Ord)

valueSort :: Value -> Sort
valueSort = \case
  VId sortName _ -> SUser sortName
  VInt _ -> SInt
  VBool _ -> SBool
  VUnit -> SUnit
  VString _ -> SString

renderValue :: Value -> Text
renderValue = \case
  VId sortName ident ->
    renderSortName sortName <> "#" <> Text.pack (show (unId ident))
  VInt n ->
    Text.pack (show n)
  VBool True ->
    "true"
  VBool False ->
    "false"
  VUnit ->
    "()"
  VString text ->
    Text.pack (show text)

