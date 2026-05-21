module Main where

foreign import ccall "hegglog_ffi_add_i64" c_add :: Int -> Int -> Int
foreign import ccall "hegglog_ffi_reset" c_reset :: IO ()
foreign import ccall "hegglog_ffi_accum" c_accum :: Int -> IO Int
foreign import ccall "hegglog_ffi_current" c_current :: IO Int
foreign import ccall "hegglog_ffi_bool_to_i64" c_bool_to_i64 :: Bool -> Int
foreign import ccall "hegglog_ffi_next_char" c_next_char :: Char -> Char

main :: IO ()
main = do
  print (c_add 7 5)
  c_reset
  first <- c_accum 10
  second <- c_accum 32
  current <- c_current
  print first
  print second
  print current
  print (c_bool_to_i64 True)
  putStrLn [c_next_char 'A']
