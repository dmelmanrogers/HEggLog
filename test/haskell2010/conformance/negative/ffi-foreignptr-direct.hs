module Main where

import Foreign (ForeignPtr)

foreign import ccall "hegglog_ffi_read_i64_ptr" badRead :: ForeignPtr Int -> IO Int

main :: IO ()
main = return ()
