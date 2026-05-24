module Main where

import System.Exit (ExitCode (..), exitWith)
import System.IO (IO, putStrLn)
import System.IO.Error (catch, isIllegalOperation)

zeroExitAction :: IO ()
zeroExitAction = do
  exitWith (ExitFailure 0)

main :: IO ()
main = catch zeroExitAction (\err -> if isIllegalOperation err then putStrLn "caught" else putStrLn "wrong error")
