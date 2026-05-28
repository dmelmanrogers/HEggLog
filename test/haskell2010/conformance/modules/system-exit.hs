module Main where

import System.Exit (ExitCode (..), exitSuccess)
import System.IO (IO, print, putStrLn)

main :: IO ()
main = do
  print (show ExitSuccess == "ExitSuccess")
  print (show (ExitFailure 7) == "ExitFailure 7")
  print ((read "ExitSuccess" :: ExitCode) == ExitSuccess)
  print ((read "ExitFailure 7" :: ExitCode) == ExitFailure 7)
  print (ExitSuccess < ExitFailure 1)
  putStrLn "before"
  exitSuccess
  putStrLn "after"
