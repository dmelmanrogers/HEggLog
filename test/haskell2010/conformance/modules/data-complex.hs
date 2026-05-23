module Main where

import Data.Complex

main :: IO ()
main = do
  let z = (3.0 :: Double) :+ (4.0 :: Double)
  let w = mkPolar (magnitude z) (phase z)
  print (realPart z)
  print (imagPart z)
  print (conjugate z)
  print (magnitude z)
  print (if realPart w > 2.99 && realPart w < 3.01 then 1 else 0)
  print (imagPart (cis (0.0 :: Double)))
  print (sqrt ((negate 4.0 :: Double) :+ 0.0))
  print (sin ((0.0 :: Double) :+ 0.0))
  putStrLn (show z)
  putStrLn (show [z, conjugate z])
  return ()
