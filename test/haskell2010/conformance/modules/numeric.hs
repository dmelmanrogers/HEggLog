module Main where

import Data.Ratio ((%))
import Numeric

binaryDigit :: Int -> Char
binaryDigit d = if d == 0 then '0' else '1'

showIntS :: Int -> ShowS
showIntS = showInt

main :: IO ()
main = do
  putStrLn (showInt 255 "")
  putStrLn (showHex 255 "")
  putStrLn (showOct 64 "")
  putStrLn (showSigned showIntS 7 (negate 12) "")
  putStrLn (showIntAtBase 2 binaryDigit 6 "")
  case (readDec "123x" :: [(Int, String)]) of
    (n, rest) : [] -> do
      print n
      putStrLn rest
    _ -> print 0
  case (readHex "3f!" :: [(Int, String)]) of
    (n, rest) : [] -> do
      print n
      putStrLn rest
    _ -> print 0
  case (readSigned readDec "(- 45)!" :: [(Int, String)]) of
    (n, rest) : [] -> do
      print n
      putStrLn rest
    _ -> print 0
  case (readFloat "12.5e1!" :: [(Double, String)]) of
    (x, rest) : [] -> do
      putStrLn (showFFloat (Just 1) x "")
      putStrLn rest
    _ -> print 0
  putStrLn (showFFloat (Just 2) (1.2 :: Double) "")
  putStrLn (showEFloat (Just 2) (123.4 :: Double) "")
  putStrLn (showGFloat (Just 2) (123.4 :: Double) "")
  putStrLn (showFloat (12.0 :: Double) "")
  print (fst (floatToDigits 10 (12.0 :: Double)))
  print (snd (floatToDigits 10 (12.0 :: Double)))
  putStrLn (showFFloat (Just 2) (fromRat (3 % 2) :: Double) "")
  return ()
