module Main where

import Foreign.ForeignPtr (FinalizerEnvPtr, FinalizerPtr, ForeignPtr, castForeignPtr, newForeignPtr_, touchForeignPtr, unsafeForeignPtrToPtr, withForeignPtr)
import Foreign.Marshal.Error (throwIf, throwIfNull, throwIf_, void)
import Foreign.Marshal.Utils (maybeNew, maybePeek, maybeWith)
import Foreign.Ptr (FunPtr, Ptr, castFunPtrToPtr, castPtr, castPtrToFunPtr, nullFunPtr, nullPtr)
import System.IO.Error (catch, ioeGetErrorString)

foreign import ccall "&hegglog_ffi_global_i64" c_global :: Ptr Int
foreign import ccall "hegglog_ffi_read_i64_ptr" c_read :: Ptr Int -> IO Int
foreign import ccall "hegglog_ffi_write_i64_ptr" c_write :: Ptr Int -> Int -> IO ()

nullIntPtr :: Ptr Int
nullIntPtr = nullPtr

nullFunAsPtr :: Ptr Int
nullFunAsPtr = castFunPtrToPtr nullFunPtr

nullPtrFunAsPtr :: Ptr Int
nullPtrFunAsPtr = castFunPtrToPtr (castPtrToFunPtr nullIntPtr)

nothingInt :: Maybe Int
nothingInt = Nothing

keepFinalizerType :: FinalizerPtr Int -> FinalizerPtr Int
keepFinalizerType finalizer = finalizer

keepFinalizerEnvType :: FinalizerEnvPtr Int Int -> FinalizerEnvPtr Int Int
keepFinalizerEnvType finalizer = finalizer

readManaged :: ForeignPtr Int -> IO Int
readManaged managed = withForeignPtr (castForeignPtr managed) c_read

main :: IO ()
main = do
  ok <- throwIf (\x -> x < 0) (\_ -> "negative") (return 7)
  print ok
  caught <- catch (throwIf (\x -> x > 0) (\x -> "positive" ++ show x) (return 1) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn caught
  throwIf_ (\x -> x < 0) (\_ -> "negative") (return 2)
  putStrLn "unit"
  void (return 99)
  putStrLn "void"
  nullCaught <- catch (throwIfNull "null" (return nullIntPtr) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn nullCaught
  funNullCaught <- catch (throwIfNull "fun" (return nullFunAsPtr) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn funNullCaught
  ptrFunNullCaught <- catch (throwIfNull "ptrfun" (return nullPtrFunAsPtr) >> return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn ptrFunNullCaught
  c_write c_global 41
  castValue <- c_read (castPtr c_global)
  print castValue
  managed <- newForeignPtr_ c_global
  unsafeValue <- c_read (unsafeForeignPtrToPtr (castForeignPtr managed))
  print unsafeValue
  managedValue <- readManaged managed
  print managedValue
  touchForeignPtr managed
  missingNew <- catch (do
    ptr <- maybeNew (\_ -> return c_global) nothingInt
    throwIfNull "maybe-new" (return ptr)
    return "bad") (\err -> return (ioeGetErrorString err))
  putStrLn missingNew
  justNew <- maybeNew (\_ -> return c_global) (Just 0)
  justNewValue <- c_read justNew
  print justNewValue
  missingWith <- catch (maybeWith (\_ k -> k c_global) nothingInt (\ptr -> throwIfNull "maybe-with" (return ptr) >> return "bad")) (\err -> return (ioeGetErrorString err))
  putStrLn missingWith
  justWithValue <- maybeWith (\_ k -> k c_global) (Just 0) c_read
  print justWithValue
  missingPeek <- maybePeek c_read nullIntPtr
  case missingPeek of
    Nothing -> putStrLn "nothing"
    Just value -> print value
  justPeek <- maybePeek c_read c_global
  case justPeek of
    Nothing -> putStrLn "missing"
    Just value -> print value
  putStrLn "ok"
