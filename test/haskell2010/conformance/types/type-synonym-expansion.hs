module Main where

type Age = Int
type Pair a = (a, a)

data Box a = Box (Pair a)

firstAge :: Box Age -> Age
firstAge (Box (x, _)) = x

main :: Int
main = firstAge (Box (42, 0))
