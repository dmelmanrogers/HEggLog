module Main where

import Foreign.C.String (CStringLen, newCString, newCStringLen, newCWString, peekCString, peekCStringLen, peekCWString, withCString, withCStringLen)
import Foreign.Marshal.Alloc (free)

main :: IO ()
main = do
  c <- newCString "abc"
  peekCString c >>= putStrLn
  peekCStringLen (c, 2) >>= putStrLn

  withCString "xy" (\p -> do
    value <- peekCString p
    putStrLn value)

  pair <- newCStringLen "hi"
  printCStringLen pair

  withCStringLen "lmno" (\p -> do
    value <- peekCStringLen p
    putStrLn value)

  cw <- newCWString "AZ"
  wide <- peekCWString cw
  putStrLn wide

  free c
  freeCStringLen pair
  free cw

printCStringLen :: CStringLen -> IO ()
printCStringLen pair =
  do
    value <- peekCStringLen pair
    putStrLn value

freeCStringLen :: CStringLen -> IO ()
freeCStringLen pair =
  free (fst pair)
