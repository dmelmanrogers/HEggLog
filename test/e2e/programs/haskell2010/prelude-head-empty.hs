module Main where

emptyInts :: [Int]
emptyInts = []

main :: IO ()
main =
  print (head emptyInts)
