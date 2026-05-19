module Main where

type Id a = a

same :: Eq (Id a) => Id a -> Id a -> Int
same x y = if x == y then 1 else 0

main :: Int
main = same 7 7
