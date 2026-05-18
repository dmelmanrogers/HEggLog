module Main where

data Box a = Box a

bad :: Box -> Int
bad x = 0

main = bad (Box 1)
