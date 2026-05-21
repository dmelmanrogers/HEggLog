module Main where

inc :: Int -> Int
inc x = x + 1

double :: Int -> Int
double x = x * 2

minus :: Int -> Int -> Int
minus x y = x - y

choose :: Bool -> [Int]
choose flag = if flag then [1, 2, 3] else []

emptyInts :: [Int]
emptyInts = []

pair :: (Int, String)
pair = (42, "ok")

main :: IO ()
main = do
  print $ inc 4
  print ((inc . double) 10)
  print (flip minus 3 10)
  print (head (choose True))
  print (tail [1, 2, 3])
  print (null emptyInts)
  print (null [False])
  print (fst pair)
  putStrLn (snd pair)
  return ()
