module Main where

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
  case toRational (7 :: Int) of
    (n, d) -> do
      print n
      print d
  print (toInteger (7 :: Int))
  return ()
