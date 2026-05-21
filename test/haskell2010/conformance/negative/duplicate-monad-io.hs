module Main where

instance Monad IO where
  (>>=) action continuation = action >>= continuation
  (>>) first second = first >> second
  return value = return value
  fail message = fail message

main :: Int
main = 1
