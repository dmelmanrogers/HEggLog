module Main where

import Data.Array

data Color = Red | Green | Blue deriving (Eq, Ord, Show, Enum, Ix)

main :: IO ()
main = do
  let chars = array (1 :: Int, 3 :: Int) [(1, 'a'), (2, 'b'), (3, 'c')] :: Array Int Char
  putStrLn (elems chars)
  putStrLn [chars ! 2, chars ! 3]
  print (fst (bounds chars))
  print (snd (bounds chars))
  print (indices chars)
  let updated = chars // [(2, 'Z')]
  putStrLn (elems updated)
  let listed = listArray ('a', 'c') [1 :: Int, 2 :: Int, 3 :: Int] :: Array Char Int
  print (listed ! 'b')
  print (length (assocs listed))
  let counted = accumArray (+) 0 (Red, Blue) [(Red, 1 :: Int), (Blue, 4 :: Int), (Blue, 6 :: Int)] :: Array Color Int
  print (counted ! Red)
  print (counted ! Green)
  print (counted ! Blue)
  let shifted = ixmap (1 :: Int, 2 :: Int) (\i -> i + 1) chars
  putStrLn (elems shifted)
  putStrLn (elems (fmap (\c -> if c == 'a' then 'A' else c) chars))
  print (chars == array (1 :: Int, 3 :: Int) [(1, 'a'), (2, 'b'), (3, 'c')])
  print (compare chars updated)
  putStrLn (show chars)
  putStrLn (showsPrec 11 chars "!")
  let readChars = read "array (1,3) [(1,'a'),(2,'b'),(3,'c')]" :: Array Int Char
  putStrLn (elems readChars)
  let readCharArrays = read "[array (1,2) [(1,'x'),(2,'y')]]" :: [Array Int Char]
  putStrLn (elems (head readCharArrays))
