module Main where

letter :: Char
letter = toEnum 65

charCode :: Int
charCode = fromEnum 'A'

stepped :: String
stepped = enumFromThenTo 'a' 'c' 'g'

boundedBools :: [Bool]
boundedBools = [minBound, maxBound]

defaulted = enumFromTo 4 6

main :: IO ()
main = do
  print (succ (41 :: Int))
  print (pred (43 :: Int))
  putStrLn (enumFromTo 'x' 'z')
  putStrLn stepped
  print charCode
  putStrLn [letter]
  print boundedBools
  print defaulted
  return ()
