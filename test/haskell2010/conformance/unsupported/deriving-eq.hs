module Main where

data Flag = Off | On deriving (Eq)

main = if On == On then 1 else 0
