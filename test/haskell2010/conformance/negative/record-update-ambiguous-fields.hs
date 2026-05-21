module Main where

data Person = Person { age :: Int }
data Score = Score { points :: Int }

main = (Person { age = 1 }) { age = 2, points = 3 }
