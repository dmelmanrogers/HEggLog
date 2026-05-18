module Main where

same :: Eq a => a -> a -> Bool
same x y = x == y

ordered :: Ord a => a -> a -> Bool
ordered x y = x <= y && y > x

distancePlusSign :: Num a => a -> a -> a
distancePlusSign x y = abs (x + negate y) + signum (x - y)

compareFlag = case compare 5 4 of
  GT -> True
  _ -> False

main = if same 7 7 && not (same 7 8) && ordered 3 4 && compareFlag && max False True && not (min False True) then distancePlusSign 9 4 else 0
