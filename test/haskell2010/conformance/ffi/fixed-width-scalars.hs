module Main where

import Data.Int
import Data.Word

foreign import ccall "static ffi_helpers.h hegglog_ffi_inc_u8" c_inc_u8 :: Word8 -> Word8
foreign import ccall "static ffi_helpers.h hegglog_ffi_neg_i8" c_neg_i8 :: Int8 -> Int8
foreign import ccall "static ffi_helpers.h hegglog_ffi_id_u64" c_id_u64 :: Word64 -> Word64

main :: IO ()
main = do
  print (c_inc_u8 255)
  print (c_neg_i8 120)
  print (c_id_u64 (maxBound :: Word64))
