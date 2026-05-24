module Main where

import Foreign.Marshal.Alloc (free)
import Foreign.Marshal.Array (advancePtr, copyArray, lengthArray0, mallocArray, moveArray, newArray, newArray0, peekArray, peekArray0, pokeArray)
import Foreign.Ptr (Ptr)

main :: IO ()
main = do
  p <- newArray [3, 4, 5] :: IO (Ptr Int)
  initial <- peekArray 3 p
  print initial

  pokeArray p [9, 8, 7]
  rewritten <- peekArray 3 p
  print rewritten

  q <- mallocArray 4 :: IO (Ptr Int)
  copyArray q p 3
  copied <- peekArray 3 q
  print copied

  moveArray (advancePtr q 1) q 3
  moved <- peekArray 4 q
  print moved

  z <- newArray0 0 [1, 2, 3] :: IO (Ptr Int)
  len <- lengthArray0 0 z
  print len
  sentinel <- peekArray0 0 z
  print sentinel

  free z
  free q
  free p
