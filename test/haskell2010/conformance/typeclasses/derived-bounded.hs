module Main where

data Direction = North | East | South | West deriving (Bounded, Enum, Eq, Show)

data Pair a b = Pair a b deriving (Bounded, Eq, Show)

data Record = Record { low :: Bool, high :: Direction } deriving (Bounded, Eq, Show)

newtype Flag = Flag Bool deriving (Bounded, Eq, Show)

main :: IO ()
main = do
  print (fromEnum (minBound :: Direction))
  print (fromEnum (maxBound :: Direction))
  print (minBound :: Pair Bool Direction)
  print (maxBound :: Pair Bool Direction)
  print (minBound :: Record)
  print (maxBound :: Record)
  print (minBound :: Flag)
  print (maxBound :: Flag)
  return ()
