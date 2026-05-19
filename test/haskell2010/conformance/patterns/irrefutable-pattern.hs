module Main where

ignore :: Maybe Int -> Int
ignore ~(Just x) = 5

pick :: (Int, Int) -> Int
pick ~(x, _) = x

main = case (1 / 0) of
  z@(~x) -> ignore Nothing + pick (2, 1 / 0)
