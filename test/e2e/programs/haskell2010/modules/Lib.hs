module Lib (Box(..), double, exported) where

data Box = Box Int

double x = x + x

exported :: Int
exported = double 5

hidden = 999
