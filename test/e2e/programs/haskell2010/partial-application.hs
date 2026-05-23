module Main where

const :: a -> b -> a
const x y = x

one = const 1

main = one (div 1 0)
