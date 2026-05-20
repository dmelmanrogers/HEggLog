module Main where

main :: IO ()
main = do
  putStrLn "native"
  putStrLn (reverse "ko")
  print (length "abc" + length (show True))
  return ()
