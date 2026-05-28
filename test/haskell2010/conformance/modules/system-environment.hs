module Main where

import System.Environment (getArgs, getEnv, getProgName)
import System.IO (IO, print, putStrLn)
import System.IO.Error (isDoesNotExistError, try)

main :: IO ()
main = do
  args <- getArgs
  progName <- getProgName
  value <- getEnv "HEGGLOG_LIB011_ENV"
  missing <- try (getEnv "HEGGLOG_LIB011_MISSING")
  print args
  putStrLn (if null progName then "empty" else "prog")
  putStrLn value
  case missing of
    Left ioError -> print (isDoesNotExistError ioError)
    Right _ -> putStrLn "unexpected"
