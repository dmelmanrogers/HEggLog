module Main where

import qualified ConformanceLib as C (Box(..), triple, value)

unbox (C.Box x) = x

main = C.triple (unbox (C.Box C.value))
