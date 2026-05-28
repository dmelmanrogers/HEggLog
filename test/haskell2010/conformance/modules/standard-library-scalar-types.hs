module Main where

import Data.Int (Int16, Int32, Int64, Int8)
import Data.Word (Word, Word16, Word32, Word64, Word8)
import Foreign.C.String (CString, CWString)
import Foreign.C.Types (CChar, CDouble, CInt, CLong, CWchar)
import Foreign.Ptr (Ptr, nullPtr)

useInt8 :: Int8 -> Int
useInt8 _ = 1

useInt16 :: Int16 -> Int
useInt16 _ = 1

useInt32 :: Int32 -> Int
useInt32 _ = 1

useInt64 :: Int64 -> Int
useInt64 _ = 1

useWord8 :: Word8 -> Int
useWord8 _ = 1

useWord16 :: Word16 -> Int
useWord16 _ = 1

useWord32 :: Word32 -> Int
useWord32 _ = 1

useWord64 :: Word64 -> Int
useWord64 _ = 1

useWord :: Word -> Int
useWord _ = 1

useCChar :: CChar -> Int
useCChar _ = 1

useCInt :: CInt -> Int
useCInt _ = 1

useCLong :: CLong -> Int
useCLong _ = 1

useCDouble :: CDouble -> Int
useCDouble _ = 1

cStringNull :: CString
cStringNull = nullPtr

cWStringNull :: CWString
cWStringNull = nullPtr

asCCharPtr :: CString -> Ptr CChar
asCCharPtr value = value

asCWcharPtr :: CWString -> Ptr CWchar
asCWcharPtr value = value

main = 0
