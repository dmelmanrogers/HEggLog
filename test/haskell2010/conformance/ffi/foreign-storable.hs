module Main where

import Foreign.C.Types (CInt)
import Foreign.Marshal.Alloc (free, malloc)
import Foreign.Ptr (Ptr, minusPtr)
import Foreign.Storable (peek, peekByteOff, peekElemOff, poke, pokeByteOff)

main :: IO ()
main = do
  p <- malloc :: IO (Ptr Int)
  poke p (123 :: Int)
  first <- peek p
  print first
  pokeByteOff p 0 (456 :: Int)
  second <- peekElemOff p 0
  print second
  third <- peekByteOff p 0 :: IO Int
  print third

  c <- malloc :: IO (Ptr CInt)
  poke c (77 :: CInt)
  cValue <- peek c
  print cValue

  charPtr <- malloc :: IO (Ptr Char)
  poke charPtr 'Z'
  charValue <- peek charPtr
  putStrLn [charValue]

  ptrSlot <- malloc :: IO (Ptr (Ptr Int))
  poke ptrSlot p
  copied <- peek ptrSlot
  print (copied `minusPtr` p)

  free ptrSlot
  free charPtr
  free c
  free p
