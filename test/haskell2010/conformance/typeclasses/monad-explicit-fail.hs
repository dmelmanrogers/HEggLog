module Main where

listFailExplicit :: [Int]
listFailExplicit = do
  value <- [1, 2, 3]
  fail "drop list branch"
  return value

maybeFailExplicit :: Maybe Int
maybeFailExplicit = fail "missing maybe value"

maybeReturnBind :: Maybe Int
maybeReturnBind = do
  value <- return 4
  return (value + 3)

main :: IO ()
main = do
  print listFailExplicit
  case maybeFailExplicit of
    Nothing -> putStrLn "maybe explicit fail"
    Just value -> print value
  case maybeReturnBind of
    Nothing -> putStrLn "missing"
    Just value -> print value
  return ()
