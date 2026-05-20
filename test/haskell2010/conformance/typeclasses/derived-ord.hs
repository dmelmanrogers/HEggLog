module Main where

data Rank = Low | Mid | High deriving (Eq, Ord)
data Box a = Box a deriving (Eq, Ord)
data Name = Name String deriving (Eq, Ord)
data Tree a = Leaf a | Node (Tree a) (Tree a) deriving (Eq, Ord)
newtype Age = Age Int deriving (Eq, Ord)

score :: Bool -> Int
score flag =
  case flag of
    True -> 1
    False -> 0

isLT :: Ordering -> Bool
isLT ordering =
  case ordering of
    LT -> True
    EQ -> False
    GT -> False

main :: Int
main = score (Low < Mid) + score (High > Mid) + score (Mid <= Mid) + score (Box 'a' < Box 'b') + score (Box "aa" < Box "ab") + score (Name "aa" < Name "ab") + score (Node (Leaf 'a') (Leaf 'b') < Node (Leaf 'a') (Leaf 'c')) + score (Age 8 >= Age 7) + score (max Low High == High) + score (min (Box 'a') (Box 'b') == Box 'a') + score (isLT (compare Mid High))
