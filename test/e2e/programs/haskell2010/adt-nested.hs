module Main where

data Box = Box Int
data Wrap = Wrap Box

main = case Wrap (Box 3) of
  Wrap (Box x) -> x
