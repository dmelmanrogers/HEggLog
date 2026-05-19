module Main where

data Box = Box Int

main = case Box 7 of
  Box x -> x
