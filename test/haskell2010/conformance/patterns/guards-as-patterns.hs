module Main where

data Box = Box Int

score original@(Box x)
  | x == 0 = 0
  | otherwise = case original of
      Box y -> y + 10

main = score (Box 5)
