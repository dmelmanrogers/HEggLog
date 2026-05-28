module Main where

import Data.List

showPairLists :: ([Int], [Char]) -> IO ()
showPairLists pair =
  case pair of
    (ints, chars) -> do
      print ints
      putStrLn chars

showPartition :: ([Int], [Int]) -> IO ()
showPartition pair =
  case pair of
    (yes, no) -> do
      print yes
      print no

showAccum :: (Int, [Int]) -> IO ()
showAccum pair =
  case pair of
    (acc, values) -> do
      print acc
      print values

showMaybeString :: Maybe String -> IO ()
showMaybeString value =
  case value of
    Just text -> putStrLn text
    Nothing -> putStrLn "Nothing"

showMaybeInt :: Maybe Int -> IO ()
showMaybeInt value =
  case value of
    Just n -> print n
    Nothing -> putStrLn "Nothing"

main :: IO ()
main = do
  print (last [1, 2, 3])
  print (init [1, 2, 3])
  putStrLn (intersperse '-' "abc")
  putStrLn (intercalate "," ["ab", "cd", "ef"])
  print (transpose [[1, 2, 3], [4, 5, 6], [7, 8]])
  print (subsequences "ab")
  print (permutations "abc")
  print (length (permutations "abc"))
  print (elem "cab" (permutations "abc"))
  print (foldl' (+) 0 [1, 2, 3, 4, 5])
  print (foldl1 (-) [10, 3, 2])
  putStrLn (foldr1 (++) ["ha", "sk", "ell"])
  print (concat [[1, 2], [3], []])
  print (concatMap (\x -> [x, x + 10]) [1, 2])
  print (and [True, True, False])
  print (or [False, True])
  print (any (> 3) [1, 4])
  print (all (< 5) [1, 4])
  print (sum [1, 2, 3])
  print (product [2, 3, 4])
  print (maximum [3, 1, 4, 2])
  print (minimum [3, 1, 4, 2])
  print (scanl (+) 0 [1, 2, 3])
  print (scanl1 (+) [1, 2, 3])
  print (scanr (\x xs -> x : xs) [] [1, 2, 3])
  print (scanr1 (+) [1, 2, 3])
  showAccum (mapAccumL (\acc x -> (acc + x, acc + x)) 0 [1, 2, 3])
  showAccum (mapAccumR (\acc x -> (acc + x, acc + x)) 0 [1, 2, 3])
  print (take 5 (iterate (+ 2) 1))
  print (take 4 (repeat 7))
  print (take 5 (cycle [1, 2]))
  print (unfoldr (\n -> if n == 0 then Nothing else Just (n, n - 1)) 4)
  print (take 3 [1, 2])
  print (drop 2 [1, 2, 3, 4])
  showPartition (splitAt 2 [1, 2, 3, 4])
  print (takeWhile (< 3) [1, 2, 3, 1])
  print (dropWhile (< 3) [1, 2, 3, 1])
  showPartition (span (< 3) [1, 2, 3, 1])
  showPartition (break (> 2) [1, 2, 3, 1])
  showMaybeString (stripPrefix "pre" "prefix")
  print (group "miss")
  print (inits "abc")
  print (tails "abc")
  print (isPrefixOf "pre" "prefix")
  print (isSuffixOf "fix" "prefix")
  print (isInfixOf "efi" "prefix")
  print (notElem 5 [1, 2, 3])
  showMaybeInt (lookup 'b' [('a', 1), ('b', 2)])
  showMaybeInt (find (> 2) [1, 3, 2])
  showPartition (partition (\x -> rem x 2 == 1) [1, 2, 3, 4])
  print ([9, 8, 7] !! 1)
  showMaybeInt (elemIndex 'b' "abc")
  print (elemIndices 'a' "banana")
  showMaybeInt (findIndex (> 2) [1, 2, 3])
  print (findIndices (\x -> rem x 2 == 1) [1, 2, 3, 4])
  print (zipWith (+) [1, 2] [10, 20])
  print (zipWith3 (\a b c -> a + b + c) [1] [2] [3])
  print (zipWith4 (\a b c d -> a + b + c + d) [1] [2] [3] [4])
  print (zipWith5 (\a b c d e -> a + b + c + d + e) [1] [2] [3] [4] [5])
  print (zipWith6 (\a b c d e f -> a + b + c + d + e + f) [1] [2] [3] [4] [5] [6])
  print (zipWith7 (\a b c d e f g -> a + b + c + d + e + f + g) [1] [2] [3] [4] [5] [6] [7])
  print (length (zip [1, 2] "ab"))
  print (length (zip3 [1] [2] [3]))
  print (length (zip4 [1] [2] [3] [4]))
  print (length (zip5 [1] [2] [3] [4] [5]))
  print (length (zip6 [1] [2] [3] [4] [5] [6]))
  print (length (zip7 [1] [2] [3] [4] [5] [6] [7]))
  showPairLists (unzip [(1, 'a'), (2, 'b')])
  print (length (case unzip3 [(1, 2, 3)] of (as, bs, cs) -> as ++ bs ++ cs))
  print (length (case unzip4 [(1, 2, 3, 4)] of (a, b, c, d) -> a ++ b ++ c ++ d))
  print (length (case unzip5 [(1, 2, 3, 4, 5)] of (a, b, c, d, e) -> a ++ b ++ c ++ d ++ e))
  print (length (case unzip6 [(1, 2, 3, 4, 5, 6)] of (a, b, c, d, e, f) -> a ++ b ++ c ++ d ++ e ++ f))
  print (length (case unzip7 [(1, 2, 3, 4, 5, 6, 7)] of (a, b, c, d, e, f, g) -> a ++ b ++ c ++ d ++ e ++ f ++ g))
  print (lines "a\nb\n")
  print (words " a\tb\nc ")
  putStrLn (unlines ["a", "b"])
  putStrLn (unwords ["a", "b", "c"])
  putStrLn (nub "banana")
  putStrLn (delete 'a' "banana")
  putStrLn ("banana" \\ "an")
  putStrLn (union "dog" "cow")
  putStrLn (intersect "mississippi" "sip")
  print (sort [3, 1, 2])
  print (insert 2 [1, 3, 4])
  putStrLn (nubBy (\x y -> x == y) "aabb")
  putStrLn (deleteBy (\x y -> x == y) 'a' "banana")
  putStrLn (deleteFirstsBy (\x y -> x == y) "banana" "an")
  putStrLn (unionBy (\x y -> x == y) "dog" "cow")
  putStrLn (intersectBy (\x y -> x == y) "mississippi" "sip")
  print (groupBy (\x y -> x == y) "aabb")
  print (sortBy (flip compare) [1, 3, 2])
  print (insertBy compare 2 [1, 3, 4])
  print (maximumBy compare [3, 1, 4, 2])
  print (minimumBy compare [3, 1, 4, 2])
  print (genericLength [1, 2, 3] :: Int)
  print (genericTake (2 :: Int) [1, 2, 3])
  print (genericDrop (1 :: Int) [1, 2, 3])
  showPartition (genericSplitAt (2 :: Int) [1, 2, 3])
  print (genericIndex [5, 6, 7] (1 :: Int))
  print (genericReplicate (3 :: Int) 8)
  return ()
