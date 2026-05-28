module Main where

data Flag = Off | On deriving (Read, Show)
data Box a = Box a deriving (Read, Show)
data Name = Name String deriving (Read, Show)
data Tree a = Leaf a | Node (Tree a) (Tree a) deriving (Read, Show)
data Person = Person { age :: Int, label :: String } deriving (Read, Show)
newtype Years = Years Int deriving (Read, Show)

parsedFlag :: Flag
parsedFlag = read "Off"

parsedBox :: Box Char
parsedBox = read "Box 'x'"

parsedName :: Name
parsedName = read "Name \"aa\""

parsedTree :: Tree Char
parsedTree = read "Node (Leaf 'a') (Leaf 'b')"

parsedYears :: Years
parsedYears = read "Years 7"

parsedPerson :: Person
parsedPerson = read "Person {age = 42, label = \"Ada\"}"

parsedBoxes :: [Box Bool]
parsedBoxes = read "[Box True,Box False]"

rejectMissingParens :: [(Box (Box Bool), String)]
rejectMissingParens = reads "Box Box True"

acceptParens :: [(Box (Box Bool), String)]
acceptParens = reads "Box (Box True)"

rejectConstructorBoundary :: [(Flag, String)]
rejectConstructorBoundary = reads "Offside"

main :: IO ()
main = do
  putStrLn (show parsedFlag)
  putStrLn (show parsedBox)
  putStrLn (show parsedName)
  putStrLn (show parsedTree)
  putStrLn (show parsedYears)
  putStrLn (show parsedPerson)
  putStrLn (show parsedBoxes)
  putStrLn (show (length rejectMissingParens))
  putStrLn (show (length acceptParens))
  putStrLn (show (length rejectConstructorBoundary))
  return ()
