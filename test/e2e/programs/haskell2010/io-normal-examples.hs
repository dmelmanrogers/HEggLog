module Main where

greeting :: String
greeting = "hello"

announce :: String -> IO ()
announce label = putStrLn label

main :: IO ()
main = do
  word <- return greeting
  announce word
  return "bound" >>= putStrLn
  let values = [1, 2, 3]
  putStrLn (show "quoted")
  print 'X'
  print "plain"
  print values
  print [True, False]
  return ()
