module Main where

import qualified Lib as L (Box(..), double, exported)

unbox (L.Box x) = x

main = L.double (unbox (L.Box L.exported))
