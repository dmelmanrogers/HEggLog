module Main where

const :: a -> b -> a
const x y = x

main = const 1 (1 / 0)
