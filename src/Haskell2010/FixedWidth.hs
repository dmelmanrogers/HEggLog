module Haskell2010.FixedWidth
  ( FixedIntegral (..)
  , FixedIntegralOp (..)
  , FixedSignedness (..)
  , fixedIntegralAll
  , fixedIntegralBitMask
  , fixedIntegralBitSize
  , fixedIntegralFromBits
  , fixedIntegralIsSigned
  , fixedIntegralMaxValue
  , fixedIntegralMinValue
  , fixedIntegralModulus
  , fixedIntegralNormalize
  , fixedIntegralOccurrence
  , fixedIntegralRender
  , fixedIntegralShift
  , fixedIntegralToBits
  , fixedIntegralTypeByOccurrence
  , fixedIntegralTypeName
  )
where

import qualified Data.Bits as Bits
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Names (Namespace (..), RName (..))

data FixedSignedness
  = FixedSigned
  | FixedUnsigned
  deriving stock (Show, Eq, Ord)

data FixedIntegral
  = FixedInt8
  | FixedInt16
  | FixedInt32
  | FixedInt64
  | FixedWord
  | FixedWord8
  | FixedWord16
  | FixedWord32
  | FixedWord64
  deriving stock (Show, Eq, Ord, Enum, Bounded)

data FixedIntegralOp
  = FixedAdd
  | FixedSub
  | FixedMul
  | FixedQuot
  | FixedRem
  | FixedEq
  | FixedLt
  | FixedNegate
  | FixedAbs
  | FixedSignum
  | FixedFromInteger
  | FixedToInteger
  | FixedShow
  | FixedBitAnd
  | FixedBitOr
  | FixedBitXor
  | FixedBitComplement
  | FixedShift
  | FixedShiftL
  | FixedShiftR
  | FixedRotate
  | FixedRotateL
  | FixedRotateR
  | FixedBit
  | FixedTestBit
  | FixedMinBound
  | FixedMaxBound
  deriving stock (Show, Eq, Ord)

fixedIntegralAll :: [FixedIntegral]
fixedIntegralAll =
  [minBound .. maxBound]

fixedIntegralOccurrence :: FixedIntegral -> Text
fixedIntegralOccurrence = \case
  FixedInt8 -> "Int8"
  FixedInt16 -> "Int16"
  FixedInt32 -> "Int32"
  FixedInt64 -> "Int64"
  FixedWord -> "Word"
  FixedWord8 -> "Word8"
  FixedWord16 -> "Word16"
  FixedWord32 -> "Word32"
  FixedWord64 -> "Word64"

fixedIntegralTypeName :: FixedIntegral -> RName
fixedIntegralTypeName fixed =
  RName TypeNamespace (fixedIntegralOccurrence fixed) (fixedIntegralUnique fixed) True

fixedIntegralTypeByOccurrence :: Text -> Maybe FixedIntegral
fixedIntegralTypeByOccurrence occurrence =
  lookup occurrence [(fixedIntegralOccurrence fixed, fixed) | fixed <- fixedIntegralAll]

fixedIntegralUnique :: FixedIntegral -> Int
fixedIntegralUnique = \case
  FixedInt8 -> -121005
  FixedInt16 -> -121006
  FixedInt32 -> -121007
  FixedInt64 -> -121008
  FixedWord -> -121500
  FixedWord8 -> -121009
  FixedWord16 -> -121010
  FixedWord32 -> -121011
  FixedWord64 -> -121012

fixedIntegralSignedness :: FixedIntegral -> FixedSignedness
fixedIntegralSignedness = \case
  FixedInt8 -> FixedSigned
  FixedInt16 -> FixedSigned
  FixedInt32 -> FixedSigned
  FixedInt64 -> FixedSigned
  FixedWord -> FixedUnsigned
  FixedWord8 -> FixedUnsigned
  FixedWord16 -> FixedUnsigned
  FixedWord32 -> FixedUnsigned
  FixedWord64 -> FixedUnsigned

fixedIntegralIsSigned :: FixedIntegral -> Bool
fixedIntegralIsSigned fixed =
  fixedIntegralSignedness fixed == FixedSigned

fixedIntegralBitSize :: FixedIntegral -> Integer
fixedIntegralBitSize = \case
  FixedInt8 -> 8
  FixedInt16 -> 16
  FixedInt32 -> 32
  FixedInt64 -> 64
  FixedWord -> 64
  FixedWord8 -> 8
  FixedWord16 -> 16
  FixedWord32 -> 32
  FixedWord64 -> 64

fixedIntegralModulus :: FixedIntegral -> Integer
fixedIntegralModulus fixed =
  2 ^ fixedIntegralBitSize fixed

fixedIntegralBitMask :: FixedIntegral -> Integer
fixedIntegralBitMask fixed =
  fixedIntegralModulus fixed - 1

fixedIntegralMinValue :: FixedIntegral -> Integer
fixedIntegralMinValue fixed =
  case fixedIntegralSignedness fixed of
    FixedSigned -> negate (2 ^ (fixedIntegralBitSize fixed - 1))
    FixedUnsigned -> 0

fixedIntegralMaxValue :: FixedIntegral -> Integer
fixedIntegralMaxValue fixed =
  case fixedIntegralSignedness fixed of
    FixedSigned -> 2 ^ (fixedIntegralBitSize fixed - 1) - 1
    FixedUnsigned -> fixedIntegralBitMask fixed

fixedIntegralNormalize :: FixedIntegral -> Integer -> Integer
fixedIntegralNormalize fixed value =
  fixedIntegralFromBits fixed (fixedIntegralToBits fixed value)

fixedIntegralToBits :: FixedIntegral -> Integer -> Integer
fixedIntegralToBits fixed value =
  value `mod` fixedIntegralModulus fixed

fixedIntegralFromBits :: FixedIntegral -> Integer -> Integer
fixedIntegralFromBits fixed bits =
  case fixedIntegralSignedness fixed of
    FixedUnsigned ->
      normalizedBits
    FixedSigned
      | normalizedBits >= 2 ^ (fixedIntegralBitSize fixed - 1) ->
          normalizedBits - fixedIntegralModulus fixed
      | otherwise ->
          normalizedBits
 where
  normalizedBits = bits `mod` fixedIntegralModulus fixed

fixedIntegralRender :: FixedIntegral -> Integer -> Text
fixedIntegralRender fixed value =
  Text.pack (show rendered)
 where
  rendered =
    case fixedIntegralSignedness fixed of
      FixedSigned -> fixedIntegralNormalize fixed value
      FixedUnsigned -> fixedIntegralToBits fixed value

fixedIntegralShift :: FixedIntegral -> FixedIntegralOp -> Integer -> Integer -> Either Text Integer
fixedIntegralShift fixed op value amount =
  case op of
    FixedShift
      | amount < 0 -> pure (shiftRight (negate amount))
      | otherwise -> pure (shiftLeft amount)
    FixedShiftL
      | amount < 0 -> Left "negative shiftL count"
      | otherwise -> pure (shiftLeft amount)
    FixedShiftR
      | amount < 0 -> Left "negative shiftR count"
      | otherwise -> pure (shiftRight amount)
    FixedRotate ->
      pure (rotate amount)
    FixedRotateL
      | amount < 0 -> Left "negative rotateL count"
      | otherwise -> pure (rotate amount)
    FixedRotateR
      | amount < 0 -> Left "negative rotateR count"
      | otherwise -> pure (rotate (negate amount))
    _ ->
      Left ("not a fixed-width shift operation: " <> Text.pack (show op))
 where
  width = fixedIntegralBitSize fixed
  bits = fixedIntegralToBits fixed value
  mask = fixedIntegralBitMask fixed
  signedValue = fixedIntegralNormalize fixed value
  shiftLeft n
    | n >= width =
        case fixedIntegralSignedness fixed of
          FixedUnsigned -> 0
          FixedSigned -> if signedValue < 0 then -1 else 0
    | otherwise =
        fixedIntegralNormalize fixed (bits * (2 ^ n))
  shiftRight n
    | n >= width =
        case fixedIntegralSignedness fixed of
          FixedUnsigned -> 0
          FixedSigned -> if signedValue < 0 then -1 else 0
    | fixedIntegralSignedness fixed == FixedSigned =
        fixedIntegralNormalize fixed (signedValue `Bits.shiftR` fromInteger n)
    | otherwise =
        fixedIntegralNormalize fixed (bits `Bits.shiftR` fromInteger n)
  rotate n =
    let count = n `mod` width
        left = (bits `Bits.shiftL` fromInteger count) Bits..&. mask
        right = bits `Bits.shiftR` fromInteger (width - count)
     in fixedIntegralNormalize fixed (left Bits..|. right)
