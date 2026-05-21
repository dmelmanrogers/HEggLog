module Main where

main :: IO ()
main = do
  putStrLn "before fail"
  fail "io fail"
  putStrLn "after fail"
