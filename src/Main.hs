module Main (main) where

import CLI.Report (compileReport, renderCompileError, renderFullReport)
import qualified Data.Text.IO as Text.IO
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main = do
  getArgs >>= \case
    [path] -> runFile path
    _ -> do
      Text.IO.putStrLn "usage: cabal run hegglog -- examples/test.hg"
      exitFailure

runFile :: FilePath -> IO ()
runFile path = do
  source <- Text.IO.readFile path
  case compileReport path source of
    Left err -> do
      Text.IO.putStr (renderCompileError err)
      exitFailure
    Right report ->
      Text.IO.putStr (renderFullReport report)
