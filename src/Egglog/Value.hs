module Egglog.Value
  ( ConstBool (..)
  , ConstInt (..)
  , Value (..)
  , ZeroInfo (..)
  , joinConstBool
  , joinConstInt
  , joinZeroInfo
  , renderValue
  , valueSort
  , zeroInfoFromInteger
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

data ZeroInfo
  = UnknownZeroInfo
  | KnownZero
  | KnownNonZero
  | ConflictZeroInfo
  deriving stock (Show, Eq, Ord)

data Value
  = VId SortName Id
  | VInt Integer
  | VBool Bool
  | VConstInt ConstInt
  | VConstBool ConstBool
  | VZeroInfo ZeroInfo
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
  VZeroInfo _ -> SZeroInfo
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

joinZeroInfo :: ZeroInfo -> ZeroInfo -> ZeroInfo
joinZeroInfo lhs rhs =
  case (lhs, rhs) of
    (ConflictZeroInfo, _) -> ConflictZeroInfo
    (_, ConflictZeroInfo) -> ConflictZeroInfo
    (UnknownZeroInfo, value) -> value
    (value, UnknownZeroInfo) -> value
    (KnownZero, KnownZero) -> KnownZero
    (KnownNonZero, KnownNonZero) -> KnownNonZero
    (KnownZero, KnownNonZero) -> ConflictZeroInfo
    (KnownNonZero, KnownZero) -> ConflictZeroInfo

zeroInfoFromInteger :: Integer -> ZeroInfo
zeroInfoFromInteger 0 =
  KnownZero
zeroInfoFromInteger _ =
  KnownNonZero

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
  VZeroInfo UnknownZeroInfo ->
    "UnknownZeroInfo"
  VZeroInfo KnownZero ->
    "KnownZero"
  VZeroInfo KnownNonZero ->
    "KnownNonZero"
  VZeroInfo ConflictZeroInfo ->
    "ConflictZeroInfo"
  VUnit ->
    "()"
  VString text ->
    Text.pack (show text)
