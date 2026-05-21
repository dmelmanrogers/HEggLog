module Main where

import Foreign (FunPtr)

foreign import ccall "wrapper" badWrap :: (Int -> IO Int) -> IO (FunPtr (Bool -> IO Int))

main :: IO ()
main = return ()
