module Main where

newtype Age = Age Int

unAge :: Age -> Int
unAge (Age n) = n

main :: Int
main = unAge (Age 42)
