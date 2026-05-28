module Main where

import System.IO

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hPutStr stdout "alpha"
  hPutChar stdout '-'
  hPutStrLn stdout "beta"
  hPrint stdout True
  putStr "plain"
  putChar '-'
  putStrLn "stdout"
  first <- getLine
  hPutStrLn stdout first
  rest <- getContents
  putStr rest
  eof <- hIsEOF stdin
  print eof
  shown <- hShow stdout
  putStrLn shown
