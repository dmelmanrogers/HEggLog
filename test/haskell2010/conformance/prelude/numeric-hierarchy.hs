module Main where

import Data.Ratio (denominator, numerator)

default (Integer, Int)

main :: IO ()
main = do
  print (quot 17 5)
  print (rem 17 5)
  print (div (0 - 17) 5)
  print (mod (0 - 17) 5)
  print (quot (0 - 17) 5)
  print (rem (0 - 17) 5)
  case quotRem 17 5 of
    (q, r) -> do
      print q
      print r
  case divMod (0 - 17) 5 of
    (d, m) -> do
      print d
      print m
  let r = toRational (7 :: Int)
  print (numerator r)
  print (denominator r)
  print (toInteger (7 :: Int))
  return ()
