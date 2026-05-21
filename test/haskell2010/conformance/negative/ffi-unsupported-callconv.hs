module Main where

foreign import cplusplus "hegglog_ffi_add_i64" c_add :: Int -> Int -> Int

main :: Int
main = c_add 1 2
