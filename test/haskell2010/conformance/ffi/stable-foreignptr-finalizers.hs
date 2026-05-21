module Main where

import Foreign (ForeignPtr, FunPtr, Ptr, StablePtr, addForeignPtrFinalizer, castPtrToStablePtr, castStablePtrToPtr, deRefStablePtr, finalizeForeignPtr, freeStablePtr, newForeignPtr, newStablePtr, touchForeignPtr, withForeignPtr)

foreign import ccall "&hegglog_ffi_global_i64" c_global :: Ptr Int
foreign import ccall "&hegglog_ffi_count_i64_finalizer" c_finalizer :: FunPtr (Ptr Int -> IO ())
foreign import ccall "hegglog_ffi_reset_finalizers" c_reset_finalizers :: IO ()
foreign import ccall "hegglog_ffi_finalizer_total_value" c_finalizer_total :: IO Int
foreign import ccall "hegglog_ffi_expect_i64" c_expect :: Int -> Int -> IO ()
foreign import ccall "hegglog_ffi_read_i64_ptr" c_read :: Ptr Int -> IO Int
foreign import ccall "hegglog_ffi_write_i64_ptr" c_write :: Ptr Int -> Int -> IO ()

stableRoundTrip :: Int -> IO Int
stableRoundTrip value = do
  stable <- newStablePtr value
  first <- deRefStablePtr stable
  let raw = castStablePtrToPtr stable
  second <- deRefStablePtr (castPtrToStablePtr raw)
  freeStablePtr stable
  return (first + second)

foreignRoundTrip :: IO Int
foreignRoundTrip = do
  c_reset_finalizers
  c_write c_global 5
  managed <- newForeignPtr c_finalizer c_global
  first <- withForeignPtr managed c_read
  c_write c_global 7
  addForeignPtrFinalizer c_finalizer managed
  touchForeignPtr managed
  finalizeForeignPtr managed
  finalizeForeignPtr managed
  total <- c_finalizer_total
  return (first + total)

main :: IO ()
main = do
  stable <- stableRoundTrip 21
  c_expect stable 42
  foreignValue <- foreignRoundTrip
  c_expect foreignValue 19
  putStrLn "ok"
