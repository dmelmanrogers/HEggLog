module Main where

evenN n = if n == 0 then True else oddN (n - 1)

oddN n = if n == 0 then False else evenN (n - 1)

main = if evenN 6 then 1 else 0
