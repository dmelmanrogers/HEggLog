module Main where

ignore :: Maybe Int -> Int
ignore ~(Just x) = 5

pick :: (Int, Int) -> Int
pick ~(x, _) = x

main = case (div (1 :: Int) 0) of
  z@(~x) -> ignore Nothing + pick (2, div (1 :: Int) 0)
