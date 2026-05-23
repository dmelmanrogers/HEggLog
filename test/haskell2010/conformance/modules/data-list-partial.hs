module Main where

import Data.List (last)

emptyInts :: [Int]
emptyInts = []

main :: IO ()
main =
  print (last emptyInts)
