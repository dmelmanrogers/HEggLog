module Main where

inc x = x + 0

keep x = x < 4

add x acc = x + acc

main = case reverse (filter keep (map inc [1, 2, 3])) of
  [a, b, c] -> foldr add 0 [a * 100, b * 10, c] + length [a, b, c] - 3
  _ -> 0
