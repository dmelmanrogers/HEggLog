module Main where

class Equal a where
  equal :: a -> a -> Bool

class Equal a => Ordered a where
  same :: a -> a -> Bool
  same x y = equal x y

data Box = Box Int

instance Equal Box where
  equal (Box x) (Box y) = x == y

instance Ordered Box where {}

sameOrdered :: Ordered a => a -> a -> Bool
sameOrdered x y = equal x y

main = if same (Box 1) (Box 1) && sameOrdered (Box 2) (Box 2) then 1 else 0
