module Main where

import Data.Ratio (Ratio, Rational, (%), approxRational, denominator, numerator)

typedRatio :: Ratio Int
typedRatio = (9 :: Int) % (6 :: Int)

typedRational :: Rational
typedRational = toRational (7 :: Int)

readRatio :: Rational
readRatio = read "3 % 2"

readParenRatio :: [(Rational, String)]
readParenRatio = readsPrec 8 "(3 % 2)!"

readRatioList :: [Rational]
readRatioList = read "[3 % 2,-3 % 2]"

main :: IO ()
main = do
  let positive = (12 :: Int) % (8 :: Int)
  let negative = (12 :: Int) % (negate (8 :: Int))
  let quarter = (1 :: Int) % (4 :: Int)
  let zero = (0 :: Int) % (5 :: Int)
  print (numerator positive)
  print (denominator positive)
  print (numerator negative)
  print (denominator negative)
  print (numerator zero)
  print (denominator zero)
  print positive
  print (positive == ((3 :: Int) % (2 :: Int)))
  print (positive < ((2 :: Int) % (1 :: Int)))
  print (positive + quarter)
  print (positive - quarter)
  print (positive * quarter)
  print (negate positive)
  print (abs negative)
  print (signum positive)
  print typedRatio
  print (numerator typedRational)
  print (denominator typedRational)
  print [positive, negative]
  print (approxRational ((1 :: Int) % (10 :: Int)) ((1 :: Int) % (5 :: Int)))
  print (approxRational ((3 :: Int) % (10 :: Int)) ((1 :: Int) % (100 :: Int)))
  print readRatio
  print (fst (head readParenRatio))
  putStrLn (snd (head readParenRatio))
  print readRatioList
  return ()
