module Main where

foreign export ccall "hegglog_missing_export" missing :: Int -> Int

main :: Int
main = 0
