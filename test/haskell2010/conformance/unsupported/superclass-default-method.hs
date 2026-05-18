module Main where

class Eq a => Ordered a where
  lessOrEqual :: a -> a -> Bool
  lessOrEqual x y = True

main = 0
