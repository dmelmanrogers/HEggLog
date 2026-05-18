module Main where

score n
  | n == 0 = 1
  | n < 3 = n + 10
  | otherwise = n + 2

listScore xs@(x : rest) = case xs of
  ys@(y : tail) | length ys == 3 -> score y + length tail + length xs + x
  _ -> 0

main = listScore [4, 5, 6]
