module InstanceClass (Measure(..)) where

class Measure a where
  measure :: a -> Int
