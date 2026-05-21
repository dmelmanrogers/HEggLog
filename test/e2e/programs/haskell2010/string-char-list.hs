module Main where

stringLength :: String -> Int
stringLength xs = length xs

shownLength :: Int
shownLength = length (show 42)

main = case "hi" of
  "hi" -> stringLength "abc" + shownLength
  _ -> 0
