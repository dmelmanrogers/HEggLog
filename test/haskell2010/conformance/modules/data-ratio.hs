module Main where

import Data.Ratio (Ratio, Rational, (%), approxRational, denominator, numerator)

typedRatio :: Ratio Integer
typedRatio = (9 :: Integer) % (6 :: Integer)

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
  let positive = (12 :: Integer) % (8 :: Integer)
  let negative = (12 :: Integer) % (negate (8 :: Integer))
  let quarter = (1 :: Integer) % (4 :: Integer)
  let zero = (0 :: Integer) % (5 :: Integer)
  print (numerator positive)
  print (denominator positive)
  print (numerator negative)
  print (denominator negative)
  print (numerator zero)
  print (denominator zero)
  print positive
  print (positive == ((3 :: Integer) % (2 :: Integer)))
  print (positive < ((2 :: Integer) % (1 :: Integer)))
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
  print (approxRational ((1 :: Integer) % (10 :: Integer)) ((1 :: Integer) % (5 :: Integer)))
  print (approxRational ((3 :: Integer) % (10 :: Integer)) ((1 :: Integer) % (100 :: Integer)))
  print readRatio
  print (fst (head readParenRatio))
  putStrLn (snd (head readParenRatio))
  print readRatioList
  return ()
