module Main where

import System.IO
import System.IO.Error

main :: IO ()
main = do
  let path = ".context/haskell2010-system-io-files.txt"
  let newPath = ".context/haskell2010-system-io-readwrite-new.txt"
  writeFile path "abc\ndef"
  appendFile path "\nxyz"
  withFile path ReadMode (\h -> do
    a <- hGetChar h
    b <- hLookAhead h
    p1 <- hTell h
    line <- hGetLine h
    p2 <- hTell h
    hSeek h AbsoluteSeek 4
    rest <- hGetContents h
    semiOpen <- hIsOpen h
    semiReadable <- hIsReadable h
    repeatedContents <- try (hGetContents h)
    putStrLn [a, b]
    print p1
    print p2
    putStrLn line
    print semiOpen
    print semiReadable
    print (case repeatedContents of Left _ -> True; Right _ -> False)
    putStrLn rest)
  h <- openFile path ReadWriteMode
  size <- hFileSize h
  hSeek h AbsoluteSeek 1
  saved <- hGetPosn h
  hSeek h SeekFromEnd (0 - 3)
  pos <- hTell h
  hSetPosn saved
  savedPos <- hTell h
  hSetFileSize h 7
  size2 <- hFileSize h
  badSeek <- try (hSeek h AbsoluteSeek 100)
  open <- hIsOpen h
  readable <- hIsReadable h
  writable <- hIsWritable h
  seekable <- hIsSeekable h
  hSetBuffering h NoBuffering
  buffering <- hGetBuffering h
  hSetEcho h True
  echo <- hGetEcho h
  terminal <- hIsTerminalDevice h
  ready <- hReady h
  hClose h
  closed <- hIsClosed h
  print size
  print pos
  print savedPos
  print size2
  print (case badSeek of Left _ -> True; Right _ -> False)
  print open
  print readable
  print writable
  print seekable
  print (case buffering of NoBuffering -> True; _ -> False)
  print echo
  print terminal
  print ready
  print closed
  created <- openFile newPath ReadWriteMode
  hPutStr created "rw"
  hSeek created AbsoluteSeek 0
  createdContents <- hGetContents created
  putStrLn createdContents
  xs <- fixIO (\ys -> return ('Q' : ys))
  putChar (head xs)
  putChar '\n'
