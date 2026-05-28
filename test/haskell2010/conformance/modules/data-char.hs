module Main where

import Data.Char

combiningAcute :: Char
combiningAcute = chr 769

greekPi :: Char
greekPi = chr 960

latinSmallYDiaeresis :: Char
latinSmallYDiaeresis = chr 255

main :: IO ()
main = do
  print (isControl '\n')
  print (isSpace '\t')
  print (isLower 'a')
  print (isUpper 'A')
  print (isAlpha 'Z')
  print (isAlphaNum '7')
  print (isPrint 'x')
  print (isDigit '9')
  print (isOctDigit '8')
  print (isHexDigit 'F')
  print (isLetter greekPi)
  print (isMark combiningAcute)
  print (isNumber (chr 178))
  print (isPunctuation '!')
  print (isSymbol '$')
  print (isSeparator ' ')
  print (isAscii '\DEL')
  print (isLatin1 latinSmallYDiaeresis)
  print (isAsciiUpper 'Q')
  print (isAsciiLower 'q')
  print (generalCategory 'A')
  print (generalCategory combiningAcute)
  putStrLn [toUpper 'a', toLower 'Z', toTitle 'q']
  print (digitToInt 'f')
  putStrLn [intToDigit 15]
  print (ord 'A')
  putStrLn [chr 65]
  putStrLn (showLitChar '\n' "!")
  putStrLn (showLitChar '\SO' "H")
  putStrLn (fst (head (lexLitChar "\\nHello")))
  putStrLn (snd (head (lexLitChar "\\nHello")))
  print (fst (head (readLitChar "\\65!")))
  print (ord (fst (head (readLitChar "\\BEL!"))))
  putStrLn (snd (head (readLitChar "\\x41!")))
