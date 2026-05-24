module Main where

import System.Exit (ExitCode (..), exitWith)
import System.IO (IO, putStrLn)

main :: IO ()
main = do
  putStrLn "before"
  exitWith (ExitFailure 7)
  putStrLn "after"
