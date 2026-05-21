module Main where

data Person = Person { age :: Int, score :: Int }

main = (Person { age = 1, score = 2 }) { age = 3, age = 4 }
