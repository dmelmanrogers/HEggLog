module Main where

import Control.Monad

maybeDefault :: a -> Maybe a -> a
maybeDefault fallback value =
  case value of
    Just found -> found
    _ -> fallback

main :: IO ()
main = do
  print (maybeDefault [] (mapM (\x -> Just (x + 1)) [1, 2, 3]))
  mapM_ print [4, 5]
  print (maybeDefault [] (forM [1, 2] (\x -> Just (x * 2))))
  forM_ [6] print
  print (maybeDefault [] (sequence [Just 1, Just 2]))
  sequence_ [print 7, print 8]
  print (maybeDefault 0 ((\x -> Just (x + 3)) =<< Just 4))
  print (maybeDefault 0 (((\x -> Just (x + 1)) >=> (\x -> Just (x * 3))) 2))
  print (maybeDefault 0 (((\x -> Just (x * 3)) <=< (\x -> Just (x + 1))) 2))
  print (maybeDefault 0 (join (Just (Just 10))))
  print (maybeDefault 0 (msum [Nothing, Just 11, Just 12]))
  print (msum [[1], [2, 3]])
  print (maybeDefault [] (filterM (\x -> Just (x > 2)) [1, 2, 3, 4]))
  let unzipped = maybeDefault ([], []) (mapAndUnzipM (\x -> Just (x, x + 10)) [1, 2])
  print (fst unzipped)
  print (snd unzipped)
  print (maybeDefault [] (zipWithM (\x y -> Just (x + y)) [1, 2] [10, 20, 30]))
  zipWithM_ (\x y -> print (x + y)) [1, 2] [20, 30]
  print (maybeDefault 0 (foldM (\acc x -> Just (acc + x)) 0 [1, 2, 3]))
  print (maybeDefault 0 (foldM_ (\acc x -> Just (acc + x)) 0 [1, 2, 3] >> Just 13))
  print (maybeDefault [] (replicateM 3 (Just 2)))
  print (maybeDefault 0 (replicateM_ 2 (Just 1) >> Just 14))
  print (maybeDefault 0 (guard True >> Just 15))
  print (maybeDefault 99 (guard False >> Just 15))
  print (guard True >> [16, 17])
  print (guard False >> [18])
  when True (putStrLn "when")
  when False (putStrLn "not printed")
  unless False (putStrLn "unless")
  unless True (putStrLn "not printed")
  print (maybeDefault 0 (liftM (+ 1) (Just 15)))
  print (maybeDefault 0 (liftM2 (+) (Just 16) (Just 17)))
  print (maybeDefault 0 (liftM3 (\x y z -> x + y + z) (Just 1) (Just 2) (Just 3)))
  print (maybeDefault 0 (liftM4 (\w x y z -> w + x + y + z) (Just 1) (Just 2) (Just 3) (Just 4)))
  print (maybeDefault 0 (liftM5 (\v w x y z -> v + w + x + y + z) (Just 1) (Just 2) (Just 3) (Just 4) (Just 5)))
  print (maybeDefault 0 (ap (Just (+ 4)) (Just 30)))
  print (maybeDefault 0 (void (Just 1) >> Just 35))
