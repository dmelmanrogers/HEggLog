module Main where

import Data.Maybe

emptyInt :: Maybe Int
emptyInt = Nothing

emptyInts :: [Int]
emptyInts = []

main :: IO ()
main = do
  print (maybe 7 (+ 1) emptyInt)
  print (maybe 7 (+ 1) (Just 4))
  print (isJust (Just 'x'))
  print (isJust emptyInt)
  print (isNothing emptyInt)
  putStrLn (fromJust (Just "ok"))
  print (fromMaybe 11 emptyInt)
  print (fromMaybe 11 (Just 3))
  print (maybeToList (Just 8))
  print (maybeToList emptyInt)
  print (fromMaybe 0 (listToMaybe [1, 2, 3]))
  print (isNothing (listToMaybe emptyInts))
  print (catMaybes [Just 1, Nothing, Just 3])
  print (mapMaybe (\x -> if x > 2 then Just (x * 10) else Nothing) [1, 2, 3, 4])
