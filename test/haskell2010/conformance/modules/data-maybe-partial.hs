module Main where

import Data.Maybe (fromJust)

emptyInt :: Maybe Int
emptyInt = Nothing

main :: IO ()
main =
  print (fromJust emptyInt)
