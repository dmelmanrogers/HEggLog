module Main where

class Equal a where
  equal :: a -> a -> Bool

data Box a = Box a

instance Equal a => Equal (Box a) where
  equal (Box x) (Box y) = equal x y

main = 0
