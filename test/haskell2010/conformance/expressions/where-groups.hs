module Main where

f :: Int -> Int
f x = y + z where
  y = x + 1
  z = 2

g :: Maybe Int -> Int
g value = case value of
  Just n -> a + b where
    a = n
    b = 1
  Nothing -> 0

main = f 4 + g (Just 6)
