module Main where

import System.IO.Error (annotateIOError, doesNotExistErrorType, ioeGetErrorString, ioeGetFileName, isDoesNotExistError, isUserError, mkIOError, try, userErrorType)

missingAction :: IO Int
missingAction = ioError (mkIOError doesNotExistErrorType "missing" Nothing (Just "path.txt"))

okAction :: IO Int
okAction = return 7

failAction :: IO Int
failAction = fail "failed"

main :: IO ()
main = do
  catch (ioError (userError "boom")) (\err -> putStrLn ("caught:" ++ ioeGetErrorString err))
  missingResult <- try missingAction
  case missingResult of
    Left err -> do
      print (isDoesNotExistError err)
      putStrLn (ioeGetErrorString err)
      case ioeGetFileName err of
        Just path -> putStrLn path
        Nothing -> putStrLn "missing file"
    Right value -> print value
  okResult <- try okAction
  case okResult of
    Left err -> putStrLn (ioeGetErrorString err)
    Right value -> print value
  failResult <- try failAction
  case failResult of
    Left err -> do
      print (isUserError err)
      putStrLn (ioeGetErrorString err)
    Right value -> print value
  let annotated = annotateIOError (userError "old") "new" Nothing (Just "ann.txt")
  print (isUserError annotated)
  putStrLn (ioeGetErrorString annotated)
  case ioeGetFileName annotated of
    Just path -> putStrLn path
    Nothing -> putStrLn "missing file"
  putStrLn (show userErrorType)
  putStrLn (show doesNotExistErrorType)
  print (userErrorType == userErrorType)
  print (userErrorType /= doesNotExistErrorType)
  return ()
