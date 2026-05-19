module Main where

data Person = Person { age :: Int, score :: Int }

total :: Person -> Int
total (Person { score = s, age = a }) = a + s

main = total (Person { score = 2, age = 40 }) + age (Person { age = 1, score = 0 })
