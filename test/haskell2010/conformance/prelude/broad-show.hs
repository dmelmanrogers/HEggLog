module Main where

main :: IO ()
main = do
  putStrLn (show 'Z')
  putStrLn (show "hi")
  putStrLn (show [1, 2, 3])
  putStrLn (show [True, False])
  putStrLn (show ["a", "b"])
  putStrLn (shows 'Z' "!")
  putStrLn (showsPrec 0 "hi" "!")
  putStrLn (showList ['a', 'b'] "!")
  putStrLn (showList [1, 2] "!")
  putStrLn (show '\NUL')
  putStrLn (show "\n\"\\")
  putStrLn (show ['\SO', 'H'])
  print 'Q'
  print "ok"
  return ()
