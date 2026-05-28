module Main where

data Person = Person { age :: Int, score :: Int }
data Pair = Pair { left :: Int, right :: Int }
data Box a = Box { item :: a, count :: Int }

main =
  let p = Person { score = 2, age = 40 }
      p2 = p { age = 41 }
      p3 = p2 { score = 3, age = 42 }
      lazy = right ((Pair { left = div 1 0, right = 2 }) { right = 5 })
      b = (Box { item = 7, count = 1 }) { count = 2 }
   in age p3 + score p3 + lazy + item b + count b
