module Egglog.Value
  ( ConstBool (..)
  , ConstInt (..)
  , Value (..)
  , joinConstBool
  , joinConstInt
  , renderValue
  , valueSort
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Sort
import Runtime.Int (HInt, renderHInt)

data ConstInt
  = UnknownInt
  | KnownInt HInt
  | ConflictInt
  deriving stock (Show, Eq, Ord)

data ConstBool
  = UnknownBool
  | KnownBool Bool
  | ConflictBool
  deriving stock (Show, Eq, Ord)

data Value
  = VId SortName Id
  | VInt Integer
  | VBool Bool
  | VConstInt ConstInt
  | VConstBool ConstBool
  | VUnit
  | VString Text
  deriving stock (Show, Eq, Ord)

valueSort :: Value -> Sort
valueSort = \case
  VId sortName _ -> SUser sortName
  VInt _ -> SInt
  VBool _ -> SBool
  VConstInt _ -> SConstInt
  VConstBool _ -> SConstBool
  VUnit -> SUnit
  VString _ -> SString

joinConstInt :: ConstInt -> ConstInt -> ConstInt
joinConstInt lhs rhs =
  case (lhs, rhs) of
    (ConflictInt, _) -> ConflictInt
    (_, ConflictInt) -> ConflictInt
    (UnknownInt, value) -> value
    (value, UnknownInt) -> value
    (KnownInt a, KnownInt b)
      | a == b -> KnownInt a
      | otherwise -> ConflictInt

joinConstBool :: ConstBool -> ConstBool -> ConstBool
joinConstBool lhs rhs =
  case (lhs, rhs) of
    (ConflictBool, _) -> ConflictBool
    (_, ConflictBool) -> ConflictBool
    (UnknownBool, value) -> value
    (value, UnknownBool) -> value
    (KnownBool a, KnownBool b)
      | a == b -> KnownBool a
      | otherwise -> ConflictBool

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
  VConstInt UnknownInt ->
    "UnknownInt"
  VConstInt (KnownInt n) ->
    "KnownInt(" <> renderHInt n <> ")"
  VConstInt ConflictInt ->
    "ConflictInt"
  VConstBool UnknownBool ->
    "UnknownBool"
  VConstBool (KnownBool True) ->
    "KnownBool(true)"
  VConstBool (KnownBool False) ->
    "KnownBool(false)"
  VConstBool ConflictBool ->
    "ConflictBool"
  VUnit ->
    "()"
  VString text ->
    Text.pack (show text)
