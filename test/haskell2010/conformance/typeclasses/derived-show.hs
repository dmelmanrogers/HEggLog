module Main where

data Flag = Off | On deriving (Show)
data Box a = Box a deriving (Show)
data Name = Name String deriving (Show)
data Tree a = Leaf a | Node (Tree a) (Tree a) deriving (Show)
data Person = Person { age :: Int, label :: String } deriving (Show)
newtype Years = Years Int deriving (Show)

main :: IO ()
main = do
  putStrLn (show Off)
  putStrLn (show (Box 'x'))
  putStrLn (show (Name "aa"))
  putStrLn (show (Node (Leaf 'a') (Leaf 'b')))
  putStrLn (show (Years 7))
  putStrLn (show (Person { label = "Ada", age = 42 }))
  putStrLn (show [Box True, Box False])
  return ()
