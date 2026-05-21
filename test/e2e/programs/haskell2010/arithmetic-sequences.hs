module Main where

ints :: [Int]
ints = [1..4]

odds :: [Int]
odds = [1, 3..8]

downs :: [Int]
downs = [6, 4..0]

chars :: String
chars = ['a'..'d']

charsDown :: String
charsDown = ['f', 'd'..'b']

openPrefix :: [Int]
openPrefix = case [7..] of
  a : b : c : _ -> [a, b, c]
  _ -> []

main :: IO ()
main = do
  print ints
  print odds
  print downs
  putStrLn chars
  putStrLn charsDown
  print openPrefix
  return ()
