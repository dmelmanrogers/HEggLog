module Main where

data Box = Box Int

main = case Box (1 + 2) of
  Box x -> x + 4
