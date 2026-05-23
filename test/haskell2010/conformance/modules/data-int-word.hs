module Main where

import Data.Bits
import Data.Int
import Data.Ix
import Data.Word

main :: IO ()
main = do
  print (minBound :: Int8)
  print (maxBound :: Int8)
  print ((127 + 1) :: Int8)
  print ((minBound - 1) :: Int8)
  print ((0 - 1) :: Word8)
  print ((maxBound + 1) :: Word8)
  print (maxBound :: Word64)
  print ((255 :: Word8) `quot` (2 :: Word8))
  print ((255 :: Word8) `rem` (2 :: Word8))
  print ((negate 7 :: Int8) `div` (2 :: Int8))
  print ((6 :: Word8) .&. (3 :: Word8))
  print (complement (0 :: Word8))
  print (shift (1 :: Word8) (8 :: Int))
  print (shift (negate (1 :: Int8)) (8 :: Int))
  print (shiftL (negate (1 :: Int8)) (8 :: Int))
  print (shiftR (negate (1 :: Int8)) (8 :: Int))
  print (rotateL (1 :: Word8) (9 :: Int))
  print (rotateR (2 :: Word8) (1 :: Int))
  print (testBit (negate (1 :: Int8)) (7 :: Int))
  print (testBit (negate (1 :: Int8)) (8 :: Int))
  print (bitSize (0 :: Word16))
  print (isSigned (0 :: Int16))
  print (isSigned (0 :: Word16))
  print ([(126 :: Int8) .. (maxBound :: Int8)])
  print ([(254 :: Word8) .. (maxBound :: Word8)])
  print (range (250 :: Word8, 252 :: Word8))
  print (index (250 :: Word8, 252 :: Word8) (251 :: Word8))
  print (inRange ((negate (2) :: Int8), (2 :: Int8)) (negate (1) :: Int8))
  print (read "255" :: Word8)
  print (read "-128" :: Int8)
  print (fromEnum (255 :: Word8))
  print (toEnum (negate (1) :: Int) :: Word8)
