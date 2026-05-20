module Main where

main :: IO ()
main = do
  putStrLn (show 'Z')
  putStrLn (show "hi")
  putStrLn (show [1, 2, 3])
  putStrLn (show [True, False])
  putStrLn (show ["a", "b"])
  print 'Q'
  print "ok"
  return ()
