module MissingInstanceClass (MeasureMissing(..)) where

class MeasureMissing a where
  measureMissing :: a -> Int
