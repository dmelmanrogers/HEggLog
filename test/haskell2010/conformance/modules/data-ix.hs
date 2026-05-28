module Main where

import Data.Ix

data Color = Red | Green | Blue deriving (Eq, Ord, Show, Enum, Ix)
data Point = Point Int Char deriving (Eq, Ord, Show, Ix)

main :: IO ()
main = do
  print (range (1 :: Int, 4 :: Int))
  print (index (1 :: Int, 4 :: Int) (3 :: Int))
  print (inRange ('a', 'c') 'b')
  putStrLn (range ('x', 'z'))
  print (range (False, True))
  print (range (LT, GT))
  print (length (range ((), ())))
  print (range (Red, Blue))
  print (index (Red, Blue) Green)
  print (inRange (Point 1 'a', Point 2 'b') (Point 2 'a'))
  print (index ((1 :: Int, 'a'), (2 :: Int, 'b')) (2 :: Int, 'a'))
  print (rangeSize ((1 :: Int, 'a'), (2 :: Int, 'b')))
