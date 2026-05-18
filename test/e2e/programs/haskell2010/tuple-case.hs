module Main where

unit x = case () of
  () -> x

main = case (unit 1, 2) of
  (x, y) -> x + y
