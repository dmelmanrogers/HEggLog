module Main where

import MissingInstanceClass (MeasureMissing(..))
import MissingInstanceType (MissingBox(..))

main :: IO ()
main = print (measureMissing (MissingBox 41))
