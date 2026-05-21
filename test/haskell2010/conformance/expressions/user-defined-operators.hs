module Main where

infixr 5 <+>
infixl 6 `combine`
infixl 7 ++

(<->) :: Int -> Int -> Int
(<->) x y = x - y

(<+>) :: Int -> Int -> Int
x <+> y = x * 10 + y

combine :: Int -> Int -> Int
x `combine` y = x * 10 + y

(++) :: Int -> Int -> Int
x ++ y = x * y

main = (1 <+> 2 <+> 3) + (4 `combine` 5 `combine` 6) + (6 ++ 7) + (10 <-> 4)
