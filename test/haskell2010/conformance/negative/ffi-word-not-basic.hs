module Main where

import Data.Word (Word)

foreign import ccall "hegglog_ffi_word" c_word :: Word -> IO Word

main = 0
