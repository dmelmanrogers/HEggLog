module Main where

import Foreign (FunPtr, freeHaskellFunPtr)

foreign import ccall "wrapper" wrapIntFun :: (Int -> IO Int) -> IO (FunPtr (Int -> IO Int))
foreign import ccall "hegglog_ffi_apply_i64" c_apply :: FunPtr (Int -> IO Int) -> Int -> IO Int

callback :: Int -> IO Int
callback value = return (value + 1)

callback2 :: Int -> IO Int
callback2 value = return (value + 20)

main :: IO ()
main = do
  first <- wrapIntFun callback
  slot01 <- wrapIntFun callback
  slot02 <- wrapIntFun callback
  slot03 <- wrapIntFun callback
  slot04 <- wrapIntFun callback
  slot05 <- wrapIntFun callback
  slot06 <- wrapIntFun callback
  slot07 <- wrapIntFun callback
  slot08 <- wrapIntFun callback
  slot09 <- wrapIntFun callback
  slot10 <- wrapIntFun callback
  slot11 <- wrapIntFun callback
  slot12 <- wrapIntFun callback
  slot13 <- wrapIntFun callback
  slot14 <- wrapIntFun callback
  slot15 <- wrapIntFun callback
  slot16 <- wrapIntFun callback
  slot17 <- wrapIntFun callback
  slot18 <- wrapIntFun callback
  slot19 <- wrapIntFun callback
  slot20 <- wrapIntFun callback
  slot21 <- wrapIntFun callback
  slot22 <- wrapIntFun callback
  slot23 <- wrapIntFun callback
  slot24 <- wrapIntFun callback
  slot25 <- wrapIntFun callback
  slot26 <- wrapIntFun callback
  slot27 <- wrapIntFun callback
  slot28 <- wrapIntFun callback
  slot29 <- wrapIntFun callback
  slot30 <- wrapIntFun callback
  slot31 <- wrapIntFun callback
  slot32 <- wrapIntFun callback
  slot33 <- wrapIntFun callback
  slot34 <- wrapIntFun callback
  slot35 <- wrapIntFun callback
  slot36 <- wrapIntFun callback
  slot37 <- wrapIntFun callback
  slot38 <- wrapIntFun callback
  slot39 <- wrapIntFun callback
  slot40 <- wrapIntFun callback
  slot41 <- wrapIntFun callback
  slot42 <- wrapIntFun callback
  slot43 <- wrapIntFun callback
  slot44 <- wrapIntFun callback
  slot45 <- wrapIntFun callback
  slot46 <- wrapIntFun callback
  slot47 <- wrapIntFun callback
  slot48 <- wrapIntFun callback
  slot49 <- wrapIntFun callback
  slot50 <- wrapIntFun callback
  slot51 <- wrapIntFun callback
  slot52 <- wrapIntFun callback
  slot53 <- wrapIntFun callback
  slot54 <- wrapIntFun callback
  slot55 <- wrapIntFun callback
  slot56 <- wrapIntFun callback
  slot57 <- wrapIntFun callback
  slot58 <- wrapIntFun callback
  slot59 <- wrapIntFun callback
  slot60 <- wrapIntFun callback
  slot61 <- wrapIntFun callback
  slot62 <- wrapIntFun callback
  slot63 <- wrapIntFun callback
  freeHaskellFunPtr first
  freeHaskellFunPtr first
  reused <- wrapIntFun callback2
  value <- c_apply reused 10
  print value
