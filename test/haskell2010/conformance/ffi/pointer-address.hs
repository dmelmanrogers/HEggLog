module Main where

import Foreign (FunPtr, Ptr)

foreign import ccall "&hegglog_ffi_global_i64" c_global :: Ptr Int
foreign import ccall "&hegglog_ffi_inc_i64" c_inc_ptr :: FunPtr (Int -> IO Int)
foreign import ccall "hegglog_ffi_read_i64_ptr" c_read :: Ptr Int -> IO Int
foreign import ccall "hegglog_ffi_write_i64_ptr" c_write :: Ptr Int -> Int -> IO ()
foreign import ccall "hegglog_ffi_select_i64_ptr" c_select :: Bool -> IO (Ptr Int)
foreign import ccall "hegglog_ffi_apply_i64" c_apply :: FunPtr (Int -> IO Int) -> Int -> IO Int

main :: IO ()
main = do
  before <- c_read c_global
  print before
  c_write c_global 123
  after <- c_read c_global
  print after
  selected <- c_select True
  selectedValue <- c_read selected
  print selectedValue
  applied <- c_apply c_inc_ptr 41
  print applied
