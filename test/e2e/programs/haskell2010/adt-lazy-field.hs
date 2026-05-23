module Main where

data Box = Box Int

main = case Box (div 1 0) of
  Box _ -> 5
