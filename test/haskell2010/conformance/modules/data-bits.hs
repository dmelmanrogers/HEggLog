module Main where

import Data.Bits

main :: IO ()
main = do
  print ((6 :: Int) .&. (3 :: Int))
  print ((6 :: Int) .|. (3 :: Int))
  print (xor (6 :: Int) (3 :: Int))
  print (complement (0 :: Int))
  print (shift (8 :: Int) (negate (1 :: Int)))
  print (shift (3 :: Int) (2 :: Int))
  print (shiftL (1 :: Int) (63 :: Int))
  print (shiftL (1 :: Int) (64 :: Int))
  print (shiftR (negate (1 :: Int)) (64 :: Int))
  print (rotate (1 :: Int) (negate (1 :: Int)))
  print (rotateL (1 :: Int) (65 :: Int))
  print (rotateR (2 :: Int) (1 :: Int))
  print (bit (5 :: Int) :: Int)
  print (bit (64 :: Int) :: Int)
  print (setBit (0 :: Int) (3 :: Int))
  print (clearBit (negate (1 :: Int)) (0 :: Int))
  print (complementBit (0 :: Int) (1 :: Int))
  print (testBit (8 :: Int) (3 :: Int))
  print (testBit (8 :: Int) (2 :: Int))
  print (bitSize (0 :: Int))
  print (isSigned (0 :: Int))
  print ((1 :: Int) `shiftL` (3 :: Int))
