module Main where

(a, b) = (3, 4)
Box c = Box 5

data Box = Box Integer

main = a + b + c
