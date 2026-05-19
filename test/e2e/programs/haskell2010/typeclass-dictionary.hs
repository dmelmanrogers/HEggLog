module Main where

class Equal a where
  equal :: a -> a -> Bool

data Box = Box Int

instance Equal Box where
  equal (Box x) (Box y) = x == y

same :: Equal a => a -> a -> Bool
same x y = equal x y

main = if same (Box 7) (Box 7) && not (same (Box 7) (Box 8)) then 1 else 0
