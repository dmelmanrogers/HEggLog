module Main where

import Control.Monad (return)
import Data.List ((++), foldl, head, map, null)
import Data.Maybe (Maybe (..))
import System.IO (IO, print, putStrLn)

emptyInts :: [Int]
emptyInts = []

sumList :: [Int] -> Int
sumList xs = foldl (+) 0 xs

describe :: Maybe Int -> Int
describe value =
  case value of
    Just found -> found
    Nothing -> 0

main :: IO ()
main = do
  print (sumList (map (+ 1) [1, 2, 3]))
  print (describe (Just (head ([4] ++ [5]))))
  print (null emptyInts)
  putStrLn "stdlib"
  return ()
