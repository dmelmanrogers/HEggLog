module Main where

prefixScore :: String -> Int
prefixScore xs = case xs of
  'h' : 'i' : rest -> length rest
  _ -> 100

literalScore :: String -> Int
literalScore xs = case xs of
  "ok" -> 1
  _ -> 0

main = prefixScore "hithere" + literalScore "ok"
