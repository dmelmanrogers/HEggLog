module Main where

import Data.Array

main :: IO ()
main =
  print ((array (1 :: Int, 2 :: Int) [(1, 7 :: Int), (1, 9 :: Int), (2, 3 :: Int)] :: Array Int Int) ! 1)
