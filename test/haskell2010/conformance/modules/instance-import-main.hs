module Main where

import InstanceBridge ()
import InstanceClass (Measure(..))
import InstanceType (Box(..))

main :: IO ()
main = print (measure (Box 41))
