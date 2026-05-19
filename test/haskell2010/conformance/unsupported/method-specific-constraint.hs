module Main where

class Sized a where
  same :: Eq a => a -> a -> Bool

main :: Int
main = 0
