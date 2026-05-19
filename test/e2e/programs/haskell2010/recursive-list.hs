module Main where

sumList xs = case xs of
  [] -> 0
  y : ys -> y + sumList ys

main = sumList [1, 2, 3, 4]
