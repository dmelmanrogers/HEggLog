module Main where

import System.Exit (ExitCode (..), exitWith)
import System.IO (IO, putStrLn)
import System.IO.Error (catch)

main :: IO ()
main =
  catch (exitWith (ExitFailure 9)) (\_ -> putStrLn "caught")
