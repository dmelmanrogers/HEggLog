module Main where

import Foreign (FunPtr)

foreign import ccall "dynamic" mkIntFun :: FunPtr (Int -> IO Int) -> Int -> IO Int
foreign import ccall "dynamic" mkPureFun :: FunPtr (Int -> Int) -> Int -> Int
foreign import ccall "wrapper" wrapIntFun :: (Int -> IO Int) -> IO (FunPtr (Int -> IO Int))
foreign import ccall "wrapper" wrapPureFun :: (Int -> Int) -> IO (FunPtr (Int -> Int))
foreign import ccall "&hegglog_ffi_inc_i64" c_inc_ptr :: FunPtr (Int -> IO Int)
foreign import ccall "&hegglog_ffi_inc_i64" c_inc_pure_ptr :: FunPtr (Int -> Int)
foreign import ccall "hegglog_ffi_apply_i64" c_apply :: FunPtr (Int -> IO Int) -> Int -> IO Int
foreign import ccall "hegglog_ffi_apply_i64" c_apply_pure :: FunPtr (Int -> Int) -> Int -> IO Int
foreign import ccall "hegglog_ffi_apply_twice_i64" c_apply_twice :: FunPtr (Int -> IO Int) -> Int -> IO Int

callback :: Int -> IO Int
callback value = do
  print value
  return (value + 2)

callback2 :: Int -> IO Int
callback2 value = return (value + 10)

pureCallback :: Int -> Int
pureCallback value = value + 20

main :: IO ()
main = do
  direct <- mkIntFun c_inc_ptr 10
  print direct
  print (mkPureFun c_inc_pure_ptr 20)
  callbackPtr <- wrapIntFun callback
  callbackPtr2 <- wrapIntFun callback2
  pureCallbackPtr <- wrapPureFun pureCallback
  once <- c_apply callbackPtr 40
  print once
  other <- c_apply callbackPtr2 5
  print other
  pureApplied <- c_apply_pure pureCallbackPtr 2
  print pureApplied
  twice <- c_apply_twice callbackPtr 3
  print twice
