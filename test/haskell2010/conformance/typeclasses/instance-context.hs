module Main where

class Equal a where
  equal :: a -> a -> Bool

data Box a = Box a

instance Equal Int where
  equal x y = x == y

instance Equal a => Equal (Box a) where
  equal (Box x) (Box y) = equal x y

main :: IO ()
main = print (equal (Box (4 :: Int)) (Box (4 :: Int)))
