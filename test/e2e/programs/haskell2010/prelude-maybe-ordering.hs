module Main where

main = case Right (Just LT) of
  Left x -> x
  Right value -> case value of
    Nothing -> 0
    Just LT -> 5
    Just EQ -> 6
    Just GT -> 7
