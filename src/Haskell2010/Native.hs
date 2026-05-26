module Haskell2010.Native
  ( ForeignLinkMetadata (..)
  , Haskell2010LLVMError (..)
  , Haskell2010NativeOptions (..)
  , Haskell2010LLVMResult (..)
  , Haskell2010OptimizationStatus (..)
  , compileHaskell2010FileToLLVM
  , compileHaskell2010FileToLLVMWithOptions
  , compileHaskell2010ToLLVM
  , compileHaskell2010ToLLVMWithOptions
  , defaultHaskell2010NativeOptions
  , renderHaskell2010LLVMError
  , renderHaskell2010OptimizationStatus
  )
where

import qualified Data.List as List
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Egglog.Eval as Egglog
import Haskell2010.Core.Syntax (CoreForeignImport, CoreModule)
import Haskell2010.Diagnostics (renderParseDiagnostic)
import Haskell2010.FFI.LinkMetadata (ForeignLinkMetadata (..), foreignLinkMetadataForImportsExports)
import Haskell2010.ModuleGraph
  ( LoadedModule (..)
  , LoadedModuleGraph (..)
  , ModuleGraphError
  , ModuleSearchPolicy (..)
  , loadVirtualStandardModuleClosure
  , loadModuleGraphWithPolicy
  , renderModuleGraphError
  , sourceModuleName
  , wholeProgramModule
  )
import Haskell2010.Names (RName, nameOcc)
import Haskell2010.Parser (parseSourceModule)
import Haskell2010.Pretty (renderModuleName)
import Haskell2010.Renamed (RDecl (..), RHsModule (..), RPat (..))
import Haskell2010.Renamer (RenameError, renameModule, renameModuleGraph, renderRenameError)
import Haskell2010.STG.LLVM (STGLLVMError, lowerSTGProgramToLLVMByName, renderSTGLLVMError)
import Haskell2010.STG.Lower (STGLowerError, lowerCoreModule, renderSTGLowerError)
import Haskell2010.STG.Syntax (STGAlt (..), STGBind (..), STGExpr (..), STGProgram (..), STGRhs (..))
import Haskell2010.Syntax (HsModule, ModuleName (..))
import Haskell2010.Typecheck
  ( TypecheckError
  , TypecheckResult (..)
  , TypecheckWarning
  , renderTypecheckError
  , typecheckModuleToCoreWithWarnings
  )
import Backend.LLVM.Emit (emitLLVMModule)
import Backend.LLVM.IR (LLVMModule)
import qualified Optimize.CoreEgglog as CoreEgglog

data Haskell2010NativeOptions = Haskell2010NativeOptions
  { haskell2010UseEgglog :: Bool
  , haskell2010EgglogRunConfig :: Egglog.RunConfig
  , haskell2010ImportPaths :: [FilePath]
  }
  deriving stock (Show, Eq)

defaultHaskell2010NativeOptions :: Haskell2010NativeOptions
defaultHaskell2010NativeOptions =
  Haskell2010NativeOptions
    { haskell2010UseEgglog = True
    , haskell2010EgglogRunConfig = Egglog.defaultRunConfig
    , haskell2010ImportPaths = []
    }

data Haskell2010LLVMResult = Haskell2010LLVMResult
  { haskell2010Parsed :: HsModule
  , haskell2010Renamed :: RHsModule
  , haskell2010OriginalCore :: CoreModule
  , haskell2010Warnings :: [TypecheckWarning]
  , haskell2010Core :: CoreModule
  , haskell2010OptimizationStatus :: Haskell2010OptimizationStatus
  , haskell2010STG :: STGProgram
  , haskell2010LinkMetadata :: ForeignLinkMetadata
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
  | Haskell2010LLVMModuleGraphError ModuleGraphError
  | Haskell2010LLVMRenameError RenameError
  | Haskell2010LLVMTypecheckError TypecheckError
  | Haskell2010LLVMMissingMain Text
  | Haskell2010LLVMCoreEgglogError CoreEgglog.CoreEgglogError
  | Haskell2010LLVMLowerError STGLowerError
  | Haskell2010LLVMSTGError STGLLVMError
  deriving stock (Show, Eq)

compileHaskell2010FileToLLVM :: FilePath -> IO (Either Haskell2010LLVMError Haskell2010LLVMResult)
compileHaskell2010FileToLLVM =
  compileHaskell2010FileToLLVMWithOptions defaultHaskell2010NativeOptions

compileHaskell2010FileToLLVMWithOptions ::
  Haskell2010NativeOptions ->
  FilePath ->
  IO (Either Haskell2010LLVMError Haskell2010LLVMResult)
compileHaskell2010FileToLLVMWithOptions options path = do
  graphResult <-
    loadModuleGraphWithPolicy
      (RootDirectoryAndImportPathSourceSearch (haskell2010ImportPaths options))
      path
  pure $ do
    graph <- mapLeft Haskell2010LLVMModuleGraphError graphResult
    compileHaskell2010LoadedModulesToLLVMWithOptions options graph

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
      (Haskell2010LLVMParseError . renderParseDiagnostic)
      (parseSourceModule path source)
  virtualModules <-
    mapLeft
      Haskell2010LLVMModuleGraphError
      (loadVirtualStandardModuleClosure parsed)
  case virtualModules of
    [] -> do
      renamed <- mapLeft Haskell2010LLVMRenameError (renameModule parsed)
      mainName <- mapLeft Haskell2010LLVMMissingMain (rootMainName renamed)
      compileHaskell2010RenamedToLLVMWithOptions options parsed renamed mainName
    _ -> do
      renamedModules <-
        mapLeft
          Haskell2010LLVMRenameError
          (renameModuleGraph (map loadedModuleParsed virtualModules <> [parsed]))
      let renamed = wholeProgramModule renamedModules
          rootName = sourceModuleName parsed
      rootRenamed <-
        case List.find ((== rootName) . renamedModuleSourceName) renamedModules of
          Just root -> Right root
          Nothing ->
            Left
              ( Haskell2010LLVMMissingMain
                  ("renamed Haskell 2010 virtual module graph is missing root module `" <> renderModuleName rootName <> "`")
              )
      mainName <- mapLeft Haskell2010LLVMMissingMain (rootMainName rootRenamed)
      compileHaskell2010RenamedToLLVMWithOptions options parsed renamed mainName

compileHaskell2010LoadedModulesToLLVMWithOptions ::
  Haskell2010NativeOptions ->
  LoadedModuleGraph ->
  Either Haskell2010LLVMError Haskell2010LLVMResult
compileHaskell2010LoadedModulesToLLVMWithOptions options graph = do
  renamedModules <-
    mapLeft
      Haskell2010LLVMRenameError
      (renameModuleGraph (map loadedModuleParsed (loadedModules graph)))
  let renamed = wholeProgramModule renamedModules
      parsed = loadedModuleParsed (loadedRoot graph)
      rootName = loadedModuleName (loadedRoot graph)
  rootRenamed <-
    case List.find ((== rootName) . renamedModuleSourceName) renamedModules of
      Just root -> Right root
      Nothing ->
        Left
          ( Haskell2010LLVMMissingMain
              ("renamed Haskell 2010 module graph is missing root module `" <> renderModuleName rootName <> "`")
          )
  mainName <- mapLeft Haskell2010LLVMMissingMain (rootMainName rootRenamed)
  compileHaskell2010RenamedToLLVMWithOptions options parsed renamed mainName

renamedModuleSourceName :: RHsModule -> ModuleName
renamedModuleSourceName renamedModule =
  case rModuleName renamedModule of
    Just name -> name
    Nothing -> ModuleName ["Main"]

compileHaskell2010RenamedToLLVMWithOptions ::
  Haskell2010NativeOptions ->
  HsModule ->
  RHsModule ->
  RName ->
  Either Haskell2010LLVMError Haskell2010LLVMResult
compileHaskell2010RenamedToLLVMWithOptions options parsed renamed mainName = do
  typecheckResult <- mapLeft Haskell2010LLVMTypecheckError (typecheckModuleToCoreWithWarnings renamed)
  let originalCore = typecheckResultCore typecheckResult
  (core, optimizationStatus) <-
    optimizeCoreIfEnabled options originalCore
  stg <- mapLeft Haskell2010LLVMLowerError (lowerCoreModule core)
  llvmModule <- mapLeft Haskell2010LLVMSTGError (lowerSTGProgramToLLVMByName mainName stg)
  let linkMetadata =
        foreignLinkMetadataForImportsExports
          (foreignImportsInProgram stg)
          (stgProgramForeignExports stg)
  pure
    Haskell2010LLVMResult
      { haskell2010Parsed = parsed
      , haskell2010Renamed = renamed
      , haskell2010OriginalCore = originalCore
      , haskell2010Warnings = typecheckResultWarnings typecheckResult
      , haskell2010Core = core
      , haskell2010OptimizationStatus = optimizationStatus
      , haskell2010STG = stg
      , haskell2010LinkMetadata = linkMetadata
      , haskell2010LLVMModule = llvmModule
      , haskell2010LLVMText = emitLLVMModule llvmModule
      }

foreignImportsInProgram :: STGProgram -> [CoreForeignImport]
foreignImportsInProgram (STGProgram _ binds _foreignExports) =
  concatMap foreignImportsInBind binds

foreignImportsInBind :: STGBind -> [CoreForeignImport]
foreignImportsInBind = \case
  STGNonRec _ rhs ->
    foreignImportsInRhs rhs
  STGRec pairs ->
    concatMap (foreignImportsInRhs . snd) pairs

foreignImportsInRhs :: STGRhs -> [CoreForeignImport]
foreignImportsInRhs = \case
  STGFunction _ body ->
    foreignImportsInExpr body
  STGThunk _ body ->
    foreignImportsInExpr body
  STGConstructor {} ->
    []

foreignImportsInExpr :: STGExpr -> [CoreForeignImport]
foreignImportsInExpr = \case
  STGAtom {} ->
    []
  STGApp {} ->
    []
  STGLet bind body _ ->
    foreignImportsInBind bind <> foreignImportsInExpr body
  STGCase scrutinee _ alternatives _ ->
    foreignImportsInExpr scrutinee <> concatMap foreignImportsInAlt alternatives
  STGPrim {} ->
    []
  STGForeignCall foreignImport _ _ ->
    [foreignImport]
  STGForeignImportValue foreignImport _ ->
    [foreignImport]

foreignImportsInAlt :: STGAlt -> [CoreForeignImport]
foreignImportsInAlt (STGAlt _ _ body) =
  foreignImportsInExpr body

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
    parseError
  Haskell2010LLVMModuleGraphError err ->
    renderModuleGraphError err
  Haskell2010LLVMRenameError err ->
    renderRenameError err
  Haskell2010LLVMTypecheckError err ->
    renderTypecheckError err
  Haskell2010LLVMMissingMain message ->
    message
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

rootMainName :: RHsModule -> Either Text RName
rootMainName renamed =
  case [name | name <- concatMap declTopLevelTerms (rModuleDecls renamed), nameOcc name == "main"] of
    [name] -> Right name
    [] -> Left "Haskell 2010 module does not define `main`"
    names -> Left ("Haskell 2010 module defines multiple `main` bindings: " <> Text.pack (show names))

declTopLevelTerms :: RDecl -> [RName]
declTopLevelTerms = \case
  RTypeSignature {} -> []
  RFunctionBinding name _ _ _ -> [name]
  RPatternBinding pat _ _ -> patternTopLevelTerms pat
  RFixityDecl {} -> []
  RDataDecl {} -> []
  RNewtypeDecl {} -> []
  RTypeSynonym {} -> []
  RClassDecl {} -> []
  RInstanceDecl {} -> []
  RDefaultDecl {} -> []
  RForeignDecl {} -> []

patternTopLevelTerms :: RPat -> [RName]
patternTopLevelTerms = \case
  RPVar name -> [name]
  RPCon _ patterns -> concatMap patternTopLevelTerms patterns
  RPRecordCon _ fields -> concatMap (patternTopLevelTerms . snd) fields
  RPLit {} -> []
  RPWildcard -> []
  RPTuple patterns -> concatMap patternTopLevelTerms patterns
  RPList patterns -> concatMap patternTopLevelTerms patterns
  RPAs name pat -> name : patternTopLevelTerms pat
  RPIrrefutable pat -> patternTopLevelTerms pat
  RPParen pat -> patternTopLevelTerms pat
