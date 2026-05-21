module Main where

data Shape = Point { x :: Int } | Rect { x :: Int, y :: Int }

main = x ((Point { x = 1 }) { y = 2 })
