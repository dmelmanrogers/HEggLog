module Main where

usesRead :: Read a => a -> Int
usesRead _ = 0

main = usesRead 1
