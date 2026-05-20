module Main where

pairs :: [Int]
pairs = [x * y | x <- [1..3], y <- [2..4], x < y]

chars :: String
chars = [c | c <- ['a'..'f'], c /= 'c', c < 'f']

justs :: [Int]
justs = [x | Just x <- [Nothing, Just 3, Just 4]]

tuples :: [Int]
tuples = [a + b | (a, b) <- [(1, 2), (3, 4)]]

nested :: [Int]
nested = [x | Just (Just x) <- [Just Nothing, Just (Just 9), Nothing]]

locals :: [Int]
locals = [y | x <- [1..3], let y = x + 10, y > 11]

main :: IO ()
main = do
  print pairs
  putStrLn chars
  print justs
  print tuples
  print nested
  print locals
  return ()
