module Main where

import Control.Monad (MonadPlus (..), (=<<), guard, liftM2, mapM, sequence)

maybeDefault :: a -> Maybe a -> a
maybeDefault fallback value =
  case value of
    Just found -> found
    _ -> fallback

main :: IO ()
main = do
  print (maybeDefault [] (mapM (\x -> Just (x + 1)) [1, 2, 3]))
  print (maybeDefault [] (sequence [Just 4, Just 5]))
  print (maybeDefault 0 ((\x -> Just (x * 2)) =<< Just 6))
  print (maybeDefault 0 (liftM2 (+) (Just 7) (Just 8)))
  print (maybeDefault 0 (mplus Nothing (Just 9)))
  print (maybeDefault 99 (guard False >> Just 10))
