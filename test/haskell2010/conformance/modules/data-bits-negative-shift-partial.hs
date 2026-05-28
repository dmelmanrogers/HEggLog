module Main where

import Data.Bits

main :: IO ()
main =
  print (shiftL (1 :: Int) (negate (1 :: Int)))
