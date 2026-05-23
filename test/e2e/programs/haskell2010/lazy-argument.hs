module Main where

const :: a -> b -> a
const x y = x

main = const 1 (div 1 0)
