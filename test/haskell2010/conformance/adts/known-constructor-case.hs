module Main where

data Box = Box Int

main = case Box (2 + 3) of
  Box x -> x
