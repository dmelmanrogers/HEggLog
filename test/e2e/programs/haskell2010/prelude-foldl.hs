module Main where

twist :: Int -> Int -> Int
twist acc x = acc * 10 + x

minus :: Int -> Int -> Int
minus acc x = acc - x

snoc :: String -> Char -> String
snoc acc x = acc ++ [x]

count :: Int -> Bool -> Int
count acc flag = if flag then acc + 1 else acc

explode :: Int -> Bool -> Int
explode _ _ = div 1 0

ignoreLeft :: Int -> Int -> Int
ignoreLeft _ x = x

main :: IO ()
main = do
  print (foldl twist 0 [1, 2, 3, 4])
  print (foldl minus 0 [1, 2, 3])
  putStrLn (foldl snoc "" ['a', 'b', 'c', 'd'])
  print (foldl count 0 [True, False, True])
  print (foldl explode 7 [])
  print (foldl ignoreLeft (div 1 0) [5])
  return ()
