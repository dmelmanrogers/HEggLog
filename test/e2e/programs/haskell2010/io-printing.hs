module Main where

prefix :: IO ()
prefix = putStrLn ['o', 'k'] >> putStrLn "answer" >> print (abs (negate 42))

main :: IO ()
main = do
  prefix
  print (not False)
  return ()
