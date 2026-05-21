module Main where

data Flag = Off | On deriving (Eq)
data Box a = Box a deriving (Eq)
data Name = Name String deriving (Eq)
data Tree a = Leaf a | Node (Tree a) (Tree a) deriving (Eq)
newtype Age = Age Int deriving (Eq)

score :: Bool -> Int
score flag =
  case flag of
    True -> 1
    False -> 0

main :: Int
main = score (On == On) + score (Off /= On) + score (Box 'x' == Box 'x') + score (Box 'x' /= Box 'y') + score (Name "aa" == Name "aa") + score (Name "aa" /= Name "ab") + score (Node (Leaf 'a') (Leaf 'b') == Node (Leaf 'a') (Leaf 'b')) + score (Node (Leaf 'a') (Leaf 'b') /= Node (Leaf 'a') (Leaf 'c')) + score (Age 7 == Age 7) + score (Box "hi" == Box "hi")
