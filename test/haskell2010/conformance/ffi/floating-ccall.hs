module Main where

import Foreign (FunPtr)
import Foreign.C.Types (CDouble, CFloat)

foreign import ccall "hegglog_ffi_double_const" c_double_const :: IO CDouble
foreign import ccall "hegglog_ffi_float_const" c_float_const :: IO CFloat
foreign import ccall "hegglog_ffi_double_const" c_double_const_hs :: IO Double
foreign import ccall "hegglog_ffi_float_const" c_float_const_hs :: IO Float
foreign import ccall "hegglog_ffi_identity_double" c_identity_double :: CDouble -> CDouble
foreign import ccall "hegglog_ffi_identity_float" c_identity_float :: CFloat -> CFloat
foreign import ccall "hegglog_ffi_score_double" c_score_double :: CDouble -> IO Int
foreign import ccall "hegglog_ffi_score_float" c_score_float :: CFloat -> IO Int
foreign import ccall "hegglog_ffi_score_double" c_score_double_hs :: Double -> IO Int
foreign import ccall "hegglog_ffi_score_float" c_score_float_hs :: Float -> IO Int
foreign import ccall "hegglog_ffi_mix_float_double" c_mix_float_double :: CFloat -> CDouble -> IO Int
foreign import ccall "&hegglog_ffi_double_plus_one" c_double_plus_one_ptr :: FunPtr (CDouble -> IO CDouble)
foreign import ccall "dynamic" mkDoubleFun :: FunPtr (CDouble -> IO CDouble) -> CDouble -> IO CDouble
foreign import ccall "wrapper" wrapDoubleFun :: (CDouble -> IO CDouble) -> IO (FunPtr (CDouble -> IO CDouble))
foreign import ccall "hegglog_ffi_apply_double" c_apply_double :: FunPtr (CDouble -> IO CDouble) -> CDouble -> IO Int
foreign import ccall "hegglog_ffi_score_export_double" c_call_export_double :: CDouble -> IO Int
foreign import ccall "hegglog_ffi_score_export_float" c_call_export_float :: CFloat -> IO Int

callbackDouble :: CDouble -> IO CDouble
callbackDouble value = return (c_identity_double value)

exportedDouble :: CDouble -> CDouble
exportedDouble value = c_identity_double value

exportedFloat :: CFloat -> IO CFloat
exportedFloat value = return (c_identity_float value)

foreign export ccall "hegglog_hs_export_double" exportedDouble :: CDouble -> CDouble
foreign export ccall "hegglog_hs_export_float" exportedFloat :: CFloat -> IO CFloat

main :: IO ()
main = do
  doubleValue <- c_double_const
  floatValue <- c_float_const
  haskellDoubleValue <- c_double_const_hs
  haskellFloatValue <- c_float_const_hs
  doubleScore <- c_score_double (c_identity_double doubleValue)
  print doubleScore
  floatScore <- c_score_float (c_identity_float floatValue)
  print floatScore
  haskellDoubleScore <- c_score_double_hs haskellDoubleValue
  print haskellDoubleScore
  haskellFloatScore <- c_score_float_hs haskellFloatValue
  print haskellFloatScore
  mixed <- c_mix_float_double floatValue doubleValue
  print mixed
  dynamicValue <- mkDoubleFun c_double_plus_one_ptr doubleValue
  dynamicScore <- c_score_double dynamicValue
  print dynamicScore
  callbackPtr <- wrapDoubleFun callbackDouble
  callbackScore <- c_apply_double callbackPtr doubleValue
  print callbackScore
  exportDoubleScore <- c_call_export_double doubleValue
  print exportDoubleScore
  exportFloatScore <- c_call_export_float floatValue
  print exportFloatScore
