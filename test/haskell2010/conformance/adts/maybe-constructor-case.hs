module Main where

data Maybe a = Nothing | Just a

main = case Just 4 of
  Nothing -> 0
  Just x -> x
