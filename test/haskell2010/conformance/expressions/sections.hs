module Main where

left :: Int -> Int
left = (1 +)

right :: Int -> Int
right = (+ 1)

over :: Int -> Bool
over = (> 3)

short :: Bool -> Bool
short = (False &&)

main = if short ((div 1 0) == 0) then 0 else if over (right 3) then left (right 4) else 0
