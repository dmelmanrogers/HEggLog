module Main where

keep :: () -> Int -> Int
keep () _ = 8

main = keep () (1 / 0)
