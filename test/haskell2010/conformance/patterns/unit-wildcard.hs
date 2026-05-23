module Main where

keep :: () -> Int -> Int
keep () _ = 8

main = keep () (div 1 0)
