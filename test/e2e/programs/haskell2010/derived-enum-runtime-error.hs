module Main where

data Direction = North | East | South | West deriving (Enum)

main = fromEnum (succ West)
