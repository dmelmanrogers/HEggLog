module Main where

twice x = x + x

defaulted = 6

viaFromInteger :: Int
viaFromInteger = fromInteger 35

main :: IO ()
main = do
  print (1 + 2 * 3)
  print (twice defaulted + viaFromInteger)
  return ()
