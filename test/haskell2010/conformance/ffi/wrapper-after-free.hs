module Main where

import Foreign (FunPtr, freeHaskellFunPtr)

foreign import ccall "wrapper" wrapIntFun :: (Int -> IO Int) -> IO (FunPtr (Int -> IO Int))
foreign import ccall "hegglog_ffi_apply_i64" c_apply :: FunPtr (Int -> IO Int) -> Int -> IO Int

callback :: Int -> IO Int
callback value = return (value + 1)

main :: IO ()
main = do
  callbackPtr <- wrapIntFun callback
  freeHaskellFunPtr callbackPtr
  value <- c_apply callbackPtr 10
  print value
