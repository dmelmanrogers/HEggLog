module Main where

import Data.Array

main :: IO ()
main =
  print ((array (1 :: Int, 2 :: Int) [(3, 9 :: Int)] :: Array Int Int) ! 1)
