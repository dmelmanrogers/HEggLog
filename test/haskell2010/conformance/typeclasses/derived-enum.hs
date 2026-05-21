module Main where

data Direction = North | East | South | West deriving (Enum, Eq, Show)
data Singleton = Only deriving (Enum, Eq, Show)

main :: IO ()
main = do
  print (fromEnum North)
  print (fromEnum South)
  print (fromEnum (succ East))
  print (fromEnum (pred South))
  putStrLn (show (toEnum 3 :: Direction))
  print (map fromEnum (enumFrom East))
  print (map fromEnum (enumFromThen West South))
  print (map fromEnum (enumFromTo East West))
  print (map fromEnum (enumFromThenTo North South West))
  print (map fromEnum (enumFromThenTo West South North))
  print (map fromEnum [East .. West])
  print (map fromEnum [West, South .. North])
  print (fromEnum Only)
