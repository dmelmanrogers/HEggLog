module Main where

main :: IO ()
main = do
  first <- getLine
  second <- getLine
  putStrLn ("first=" ++ first)
  putStrLn ("second=" ++ second)
  print (length first + length second)
  return ()
