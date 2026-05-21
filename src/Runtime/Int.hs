module Runtime.Int
  ( HInt
  , IntError (..)
  , addHInt
  , divHInt
  , eqHInt
  , hintToInt64
  , hintToInteger
  , ltHInt
  , maxHIntInteger
  , minHIntInteger
  , mkHIntLiteral
  , mulHInt
  , remHInt
  , renderHInt
  , renderIntError
  , subHInt
  , unsafeHIntLiteral
  )
where

import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST (BinOp (..))
import Syntax.Pretty (prettyBinOp, renderDoc)

newtype HInt = HInt {hintToInt64 :: Int64}
  deriving stock (Show, Eq, Ord)

data IntError
  = IntLiteralOutOfRange Integer
  | IntOverflow BinOp HInt HInt
  deriving stock (Show, Eq, Ord)

minHIntInteger :: Integer
minHIntInteger =
  toInteger (minBound :: Int64)

maxHIntInteger :: Integer
maxHIntInteger =
  toInteger (maxBound :: Int64)

mkHIntLiteral :: Integer -> Either IntError HInt
mkHIntLiteral value
  | value < minHIntInteger || value > maxHIntInteger = Left (IntLiteralOutOfRange value)
  | otherwise = Right (HInt (fromInteger value))

unsafeHIntLiteral :: Integer -> HInt
unsafeHIntLiteral value =
  case mkHIntLiteral value of
    Right hint -> hint
    Left err -> error (Text.unpack (renderIntError err))

hintToInteger :: HInt -> Integer
hintToInteger =
  toInteger . hintToInt64

renderHInt :: HInt -> Text
renderHInt =
  Text.pack . show . hintToInteger

addHInt :: HInt -> HInt -> Either IntError HInt
addHInt =
  checkedBinOp Add (+)

subHInt :: HInt -> HInt -> Either IntError HInt
subHInt =
  checkedBinOp Sub (-)

mulHInt :: HInt -> HInt -> Either IntError HInt
mulHInt =
  checkedBinOp Mul (*)

divHInt :: HInt -> HInt -> Either IntError HInt
divHInt lhs rhs =
  checkedBinOp Div quot lhs rhs

remHInt :: HInt -> HInt -> Either IntError HInt
remHInt lhs rhs
  | hintToInteger lhs == minHIntInteger && hintToInteger rhs == (-1) = Left (IntOverflow Div lhs rhs)
  | otherwise = checkedBinOp Div rem lhs rhs

ltHInt :: HInt -> HInt -> Bool
ltHInt lhs rhs =
  hintToInt64 lhs < hintToInt64 rhs

eqHInt :: HInt -> HInt -> Bool
eqHInt =
  (==)

checkedBinOp :: BinOp -> (Integer -> Integer -> Integer) -> HInt -> HInt -> Either IntError HInt
checkedBinOp op operation lhs rhs =
  case mkHIntLiteral (operation (hintToInteger lhs) (hintToInteger rhs)) of
    Right result -> Right result
    Left _ -> Left (IntOverflow op lhs rhs)

renderIntError :: IntError -> Text
renderIntError = \case
  IntLiteralOutOfRange value ->
    "integer literal "
      <> Text.pack (show value)
      <> " is outside HeggLog Int range ["
      <> Text.pack (show minHIntInteger)
      <> ", "
      <> Text.pack (show maxHIntInteger)
      <> "]"
  IntOverflow op lhs rhs ->
    "checked Int "
      <> renderDoc (prettyBinOp op)
      <> " overflowed for operands "
      <> renderHInt lhs
      <> " and "
      <> renderHInt rhs
