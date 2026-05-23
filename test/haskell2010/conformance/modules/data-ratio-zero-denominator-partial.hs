module Main where

import Data.Ratio ((%))

main :: IO ()
main = do
  print ((1 :: Int) % (0 :: Int))
  return ()
