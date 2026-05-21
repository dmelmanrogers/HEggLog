module Main where

foreign import ccall "hegglog_ffi_call_export_add" c_call_add :: Int -> Int -> IO Int
foreign import ccall "hegglog_ffi_call_export_io" c_call_io :: Int -> IO Int

exportedAdd :: Int -> Int -> Int
exportedAdd lhs rhs = lhs + rhs

exportedIO :: Int -> IO Int
exportedIO value = do
  print value
  return (value + 7)

foreign export ccall "hegglog_hs_export_add" exportedAdd :: Int -> Int -> Int
foreign export ccall "hegglog_hs_export_io" exportedIO :: Int -> IO Int

main :: IO ()
main = do
  add <- c_call_add 10 32
  print add
  io <- c_call_io 5
  print io
