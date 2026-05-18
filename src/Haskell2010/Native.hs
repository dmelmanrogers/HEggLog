module Haskell2010.Native
  ( Haskell2010LLVMError (..)
  , Haskell2010LLVMResult (..)
  , compileHaskell2010ToLLVM
  , renderHaskell2010LLVMError
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax (CoreModule)
import Haskell2010.Parser (parseSourceModule)
import Haskell2010.Renamed (RHsModule)
import Haskell2010.Renamer (RenameError, renameModule, renderRenameError)
import Haskell2010.STG.LLVM (STGLLVMError, lowerSTGProgramToLLVM, renderSTGLLVMError)
import Haskell2010.STG.Lower (STGLowerError, lowerCoreModule, renderSTGLowerError)
import Haskell2010.STG.Syntax (STGProgram)
import Haskell2010.Syntax (HsModule)
import Haskell2010.Typecheck (TypecheckError, renderTypecheckError, typecheckModuleToCore)
import Backend.LLVM.Emit (emitLLVMModule)
import Backend.LLVM.IR (LLVMModule)
import Text.Megaparsec (errorBundlePretty)

data Haskell2010LLVMResult = Haskell2010LLVMResult
  { haskell2010Parsed :: HsModule
  , haskell2010Renamed :: RHsModule
  , haskell2010Core :: CoreModule
  , haskell2010STG :: STGProgram
  , haskell2010LLVMModule :: LLVMModule
  , haskell2010LLVMText :: Text
  }
  deriving stock (Show, Eq)

data Haskell2010LLVMError
  = Haskell2010LLVMParseError Text
  | Haskell2010LLVMRenameError RenameError
  | Haskell2010LLVMTypecheckError TypecheckError
  | Haskell2010LLVMLowerError STGLowerError
  | Haskell2010LLVMSTGError STGLLVMError
  deriving stock (Show, Eq)

compileHaskell2010ToLLVM :: FilePath -> Text -> Either Haskell2010LLVMError Haskell2010LLVMResult
compileHaskell2010ToLLVM path source = do
  parsed <-
    mapLeft
      (Haskell2010LLVMParseError . Text.pack . errorBundlePretty)
      (parseSourceModule path source)
  renamed <- mapLeft Haskell2010LLVMRenameError (renameModule parsed)
  core <- mapLeft Haskell2010LLVMTypecheckError (typecheckModuleToCore renamed)
  stg <- mapLeft Haskell2010LLVMLowerError (lowerCoreModule core)
  llvmModule <- mapLeft Haskell2010LLVMSTGError (lowerSTGProgramToLLVM "main" stg)
  pure
    Haskell2010LLVMResult
      { haskell2010Parsed = parsed
      , haskell2010Renamed = renamed
      , haskell2010Core = core
      , haskell2010STG = stg
      , haskell2010LLVMModule = llvmModule
      , haskell2010LLVMText = emitLLVMModule llvmModule
      }

renderHaskell2010LLVMError :: Haskell2010LLVMError -> Text
renderHaskell2010LLVMError = \case
  Haskell2010LLVMParseError parseError ->
    "Haskell 2010 parse error:\n" <> parseError
  Haskell2010LLVMRenameError err ->
    renderRenameError err
  Haskell2010LLVMTypecheckError err ->
    renderTypecheckError err
  Haskell2010LLVMLowerError err ->
    renderSTGLowerError err
  Haskell2010LLVMSTGError err ->
    renderSTGLLVMError err

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
