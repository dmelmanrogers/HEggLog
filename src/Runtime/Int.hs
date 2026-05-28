module Runtime.Int
  ( HInt
  , IntError (..)
  , addHInt
  , andHInt
  , bitHInt
  , complementHInt
  , divHInt
  , eqHInt
  , hintToInt64
  , hintToInteger
  , ltHInt
  , maxHIntInteger
  , minHIntInteger
  , mkHIntLiteral
  , mulHInt
  , orHInt
  , rotateHInt
  , rotateLHInt
  , rotateRHInt
  , remHInt
  , renderHInt
  , renderIntError
  , shiftHInt
  , shiftLHInt
  , shiftRHInt
  , subHInt
  , testBitHInt
  , unsafeHIntLiteral
  , xorHInt
  )
where

import qualified Data.Bits as Bits
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
  | IntInvalidBitIndex Text HInt
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

andHInt :: HInt -> HInt -> Either IntError HInt
andHInt lhs rhs =
  Right (HInt ((Bits..&.) (hintToInt64 lhs) (hintToInt64 rhs)))

orHInt :: HInt -> HInt -> Either IntError HInt
orHInt lhs rhs =
  Right (HInt ((Bits..|.) (hintToInt64 lhs) (hintToInt64 rhs)))

xorHInt :: HInt -> HInt -> Either IntError HInt
xorHInt lhs rhs =
  Right (HInt (Bits.xor (hintToInt64 lhs) (hintToInt64 rhs)))

complementHInt :: HInt -> Either IntError HInt
complementHInt value =
  Right (HInt (Bits.complement (hintToInt64 value)))

shiftHInt :: HInt -> HInt -> Either IntError HInt
shiftHInt value amount
  | hintToInteger amount < 0 =
      Right (shiftRightByInteger value (negate (hintToInteger amount)))
  | otherwise =
      Right (shiftLeftByInteger value (hintToInteger amount))

shiftLHInt :: HInt -> HInt -> Either IntError HInt
shiftLHInt value amount = do
  index <- nonNegativeBitCount "shiftL" amount
  Right (shiftLeftByInteger value index)

shiftRHInt :: HInt -> HInt -> Either IntError HInt
shiftRHInt value amount = do
  index <- nonNegativeBitCount "shiftR" amount
  Right (shiftRightByInteger value index)

rotateHInt :: HInt -> HInt -> Either IntError HInt
rotateHInt =
  rotateLHInt

rotateLHInt :: HInt -> HInt -> Either IntError HInt
rotateLHInt value amount =
  Right (HInt (Bits.rotateL (hintToInt64 value) (normalizedRotateAmount amount)))

rotateRHInt :: HInt -> HInt -> Either IntError HInt
rotateRHInt value amount = do
  index <- nonNegativeBitCount "rotateR" amount
  Right (HInt (Bits.rotateR (hintToInt64 value) (fromInteger (index `mod` intBitSize))))

bitHInt :: HInt -> Either IntError HInt
bitHInt amount = do
  index <- nonNegativeBitCount "bit" amount
  Right $
    if index >= intBitSize
      then HInt 0
      else HInt (Bits.bit (fromInteger index))

testBitHInt :: HInt -> HInt -> Either IntError Bool
testBitHInt value amount = do
  index <- nonNegativeBitCount "testBit" amount
  Right $
    index < intBitSize
      && Bits.testBit (hintToInt64 value) (fromInteger index)

checkedBinOp :: BinOp -> (Integer -> Integer -> Integer) -> HInt -> HInt -> Either IntError HInt
checkedBinOp op operation lhs rhs =
  case mkHIntLiteral (operation (hintToInteger lhs) (hintToInteger rhs)) of
    Right result -> Right result
    Left _ -> Left (IntOverflow op lhs rhs)

intBitSize :: Integer
intBitSize =
  64

nonNegativeBitCount :: Text -> HInt -> Either IntError Integer
nonNegativeBitCount operation amount
  | hintToInteger amount < 0 = Left (IntInvalidBitIndex operation amount)
  | otherwise = Right (hintToInteger amount)

normalizedRotateAmount :: HInt -> Int
normalizedRotateAmount amount =
  fromInteger (hintToInteger amount `mod` intBitSize)

shiftLeftByInteger :: HInt -> Integer -> HInt
shiftLeftByInteger value amount
  | amount >= intBitSize = HInt 0
  | otherwise = HInt (Bits.shiftL (hintToInt64 value) (fromInteger amount))

shiftRightByInteger :: HInt -> Integer -> HInt
shiftRightByInteger value amount
  | amount >= intBitSize && hintToInteger value < 0 = HInt (-1)
  | amount >= intBitSize = HInt 0
  | otherwise = HInt (Bits.shiftR (hintToInt64 value) (fromInteger amount))

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
  IntInvalidBitIndex operation amount ->
    "Data.Bits."
      <> operation
      <> " received negative bit index "
      <> renderHInt amount
