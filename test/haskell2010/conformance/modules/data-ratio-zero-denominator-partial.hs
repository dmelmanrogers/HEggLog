module Main where

import Data.Ratio ((%))

main :: IO ()
main = do
  print ((1 :: Integer) % (0 :: Integer))
  return ()
