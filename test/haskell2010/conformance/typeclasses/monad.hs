module Main where

listPairs :: [Int]
listPairs = do
  x <- [1, 2]
  y <- [10, 20]
  return (x + y)

listFail :: [Int]
listFail = do
  Just x <- [Just 1, Nothing, Just 3]
  return x

maybeValue :: Maybe Int
maybeValue = do
  x <- Just 5
  y <- return 2
  return (x + y)

maybeFail :: Maybe Int
maybeFail = do
  Just x <- Just Nothing
  return x

main :: IO ()
main = do
  putStrLn "monad"
  print listPairs
  print listFail
  case maybeValue of
    Just value -> print value
    Nothing -> putStrLn "missing"
  case maybeFail of
    Just value -> print value
    Nothing -> putStrLn "maybe fail"
  return ()
