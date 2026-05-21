module Main where

import Control.Monad (Functor (..), return)
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
  print (sumList (fmap (+ 1) [1, 2, 3]))
  print (describe (fmap (+ 1) (Just (head ([4] ++ [5])))))
  print (null emptyInts)
  fmap id (putStrLn "stdlib")
  return ()
