module Haskell2010.Native
  ( Haskell2010LLVMError (..)
  , Haskell2010NativeOptions (..)
  , Haskell2010LLVMResult (..)
  , Haskell2010OptimizationStatus (..)
  , compileHaskell2010ToLLVM
  , compileHaskell2010ToLLVMWithOptions
  , defaultHaskell2010NativeOptions
  , renderHaskell2010LLVMError
  , renderHaskell2010OptimizationStatus
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Egglog.Eval as Egglog
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
import qualified Optimize.CoreEgglog as CoreEgglog
import Text.Megaparsec (errorBundlePretty)

data Haskell2010NativeOptions = Haskell2010NativeOptions
  { haskell2010UseEgglog :: Bool
  , haskell2010EgglogRunConfig :: Egglog.RunConfig
  }
  deriving stock (Show, Eq)

defaultHaskell2010NativeOptions :: Haskell2010NativeOptions
defaultHaskell2010NativeOptions =
  Haskell2010NativeOptions
    { haskell2010UseEgglog = True
    , haskell2010EgglogRunConfig = Egglog.defaultRunConfig
    }

data Haskell2010LLVMResult = Haskell2010LLVMResult
  { haskell2010Parsed :: HsModule
  , haskell2010Renamed :: RHsModule
  , haskell2010OriginalCore :: CoreModule
  , haskell2010Core :: CoreModule
  , haskell2010OptimizationStatus :: Haskell2010OptimizationStatus
  , haskell2010STG :: STGProgram
  , haskell2010LLVMModule :: LLVMModule
  , haskell2010LLVMText :: Text
  }
  deriving stock (Show, Eq)

data Haskell2010OptimizationStatus
  = Haskell2010OptimizationDisabled
  | Haskell2010OptimizationApplied CoreEgglog.CoreEgglogResult
  deriving stock (Show, Eq)

data Haskell2010LLVMError
  = Haskell2010LLVMParseError Text
  | Haskell2010LLVMRenameError RenameError
  | Haskell2010LLVMTypecheckError TypecheckError
  | Haskell2010LLVMCoreEgglogError CoreEgglog.CoreEgglogError
  | Haskell2010LLVMLowerError STGLowerError
  | Haskell2010LLVMSTGError STGLLVMError
  deriving stock (Show, Eq)

compileHaskell2010ToLLVM :: FilePath -> Text -> Either Haskell2010LLVMError Haskell2010LLVMResult
compileHaskell2010ToLLVM =
  compileHaskell2010ToLLVMWithOptions defaultHaskell2010NativeOptions

compileHaskell2010ToLLVMWithOptions ::
  Haskell2010NativeOptions ->
  FilePath ->
  Text ->
  Either Haskell2010LLVMError Haskell2010LLVMResult
compileHaskell2010ToLLVMWithOptions options path source = do
  parsed <-
    mapLeft
      (Haskell2010LLVMParseError . Text.pack . errorBundlePretty)
      (parseSourceModule path source)
  renamed <- mapLeft Haskell2010LLVMRenameError (renameModule parsed)
  originalCore <- mapLeft Haskell2010LLVMTypecheckError (typecheckModuleToCore renamed)
  (core, optimizationStatus) <-
    optimizeCoreIfEnabled options originalCore
  stg <- mapLeft Haskell2010LLVMLowerError (lowerCoreModule core)
  llvmModule <- mapLeft Haskell2010LLVMSTGError (lowerSTGProgramToLLVM "main" stg)
  pure
    Haskell2010LLVMResult
      { haskell2010Parsed = parsed
      , haskell2010Renamed = renamed
      , haskell2010OriginalCore = originalCore
      , haskell2010Core = core
      , haskell2010OptimizationStatus = optimizationStatus
      , haskell2010STG = stg
      , haskell2010LLVMModule = llvmModule
      , haskell2010LLVMText = emitLLVMModule llvmModule
      }

optimizeCoreIfEnabled ::
  Haskell2010NativeOptions ->
  CoreModule ->
  Either Haskell2010LLVMError (CoreModule, Haskell2010OptimizationStatus)
optimizeCoreIfEnabled options core
  | not (haskell2010UseEgglog options) =
      Right (core, Haskell2010OptimizationDisabled)
  | otherwise = do
      result <-
        mapLeft
          Haskell2010LLVMCoreEgglogError
          (CoreEgglog.optimizeCoreModuleWithEgglog (haskell2010EgglogRunConfig options) core)
      Right (CoreEgglog.coreEgglogOptimizedModule result, Haskell2010OptimizationApplied result)

renderHaskell2010LLVMError :: Haskell2010LLVMError -> Text
renderHaskell2010LLVMError = \case
  Haskell2010LLVMParseError parseError ->
    "Haskell 2010 parse error:\n" <> parseError
  Haskell2010LLVMRenameError err ->
    renderRenameError err
  Haskell2010LLVMTypecheckError err ->
    renderTypecheckError err
  Haskell2010LLVMCoreEgglogError err ->
    CoreEgglog.renderCoreEgglogError err
  Haskell2010LLVMLowerError err ->
    renderSTGLowerError err
  Haskell2010LLVMSTGError err ->
    renderSTGLLVMError err

renderHaskell2010OptimizationStatus :: Haskell2010OptimizationStatus -> Text
renderHaskell2010OptimizationStatus = \case
  Haskell2010OptimizationDisabled ->
    "haskell2010: Core-0 STG native path; egglog-core: disabled"
  Haskell2010OptimizationApplied result ->
    "haskell2010: Core-0 STG native path; " <> CoreEgglog.renderCoreEgglogStatus result

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
