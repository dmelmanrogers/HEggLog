module Haskell2010.ModuleGraph
  ( LoadedModule (..)
  , LoadedModuleGraph (..)
  , InterfaceFilePolicy (..)
  , ModuleCompilationBoundary (..)
  , ModuleCompilationMode (..)
  , ModuleGraphError (..)
  , ModuleSearchPolicy (..)
  , currentModuleCompilationBoundary
  , loadModuleGraph
  , loadModuleGraphWithPolicy
  , loadVirtualStandardModuleClosure
  , renderModuleGraphError
  , resolveModuleImportPath
  , resolveModuleImportPaths
  , sourceModuleName
  , wholeProgramModule
  )
where

import Control.Exception (IOException, try)
import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Haskell2010.Parser (parseSourceModule)
import Haskell2010.Pretty (renderModuleName)
import Haskell2010.Renamed
import qualified Haskell2010.StandardLibrary as StandardLibrary
import Haskell2010.Syntax
import System.FilePath ((<.>), (</>), joinPath, normalise, takeDirectory)
import System.IO.Error (isDoesNotExistError)
import Text.Megaparsec (errorBundlePretty)

data LoadedModule = LoadedModule
  { loadedModulePath :: FilePath
  , loadedModuleName :: ModuleName
  , loadedModuleSource :: Text
  , loadedModuleParsed :: HsModule
  }
  deriving stock (Show, Eq, Ord)

data LoadedModuleGraph = LoadedModuleGraph
  { loadedRoot :: LoadedModule
  , loadedModules :: [LoadedModule]
  }
  deriving stock (Show, Eq, Ord)

data ModuleGraphError
  = ModuleReadError FilePath Text
  | ModuleParseError FilePath Text
  | ModuleNameMismatch FilePath ModuleName ModuleName
  | DuplicateModule ModuleName FilePath FilePath
  | ModuleCycle [ModuleName]
  | ModuleNotFound ModuleName [FilePath]
  deriving stock (Show, Eq, Ord)

data ModuleSearchPolicy
  = RootDirectoryAndImportPathSourceSearch [FilePath]
  deriving stock (Show, Eq, Ord)

data ModuleCompilationMode
  = WholeProgramSourceCompilation
  deriving stock (Show, Eq, Ord)

data InterfaceFilePolicy
  = InterfaceFilesDeferredUntilStableSearchPaths
  deriving stock (Show, Eq, Ord)

data ModuleCompilationBoundary = ModuleCompilationBoundary
  { moduleBoundarySearchPolicy :: ModuleSearchPolicy
  , moduleBoundaryCompilationMode :: ModuleCompilationMode
  , moduleBoundaryInterfaceFilePolicy :: InterfaceFilePolicy
  }
  deriving stock (Show, Eq, Ord)

currentModuleCompilationBoundary :: ModuleCompilationBoundary
currentModuleCompilationBoundary =
  ModuleCompilationBoundary
    { moduleBoundarySearchPolicy = RootDirectoryAndImportPathSourceSearch []
    , moduleBoundaryCompilationMode = WholeProgramSourceCompilation
    , moduleBoundaryInterfaceFilePolicy = InterfaceFilesDeferredUntilStableSearchPaths
    }

data LoadState = LoadState
  { loadedByName :: Map.Map ModuleName LoadedModule
  , loadedOrder :: [LoadedModule]
  }
  deriving stock (Show, Eq, Ord)

loadModuleGraph :: FilePath -> IO (Either ModuleGraphError LoadedModuleGraph)
loadModuleGraph =
  loadModuleGraphWithPolicy (moduleBoundarySearchPolicy currentModuleCompilationBoundary)

loadModuleGraphWithPolicy :: ModuleSearchPolicy -> FilePath -> IO (Either ModuleGraphError LoadedModuleGraph)
loadModuleGraphWithPolicy searchPolicy rootPath = do
  result <- runLoad rootPath
  pure $ do
    finalState <- result
    rootModule <-
      case List.find ((== normalise rootPath) . loadedModulePath) (loadedOrder finalState) of
        Just loaded -> Right loaded
        Nothing -> Left (ModuleReadError rootPath "root module did not load")
    pure
      LoadedModuleGraph
        { loadedRoot = rootModule
        , loadedModules = loadedOrder finalState
        }
 where
  runLoad path =
    loadModule searchPolicy (takeDirectory path) [] emptyLoadState (normalise path) Nothing

emptyLoadState :: LoadState
emptyLoadState =
  LoadState
    { loadedByName = Map.empty
    , loadedOrder = []
    }

loadVirtualStandardModuleClosure :: HsModule -> Either ModuleGraphError [LoadedModule]
loadVirtualStandardModuleClosure rootModule =
  snd <$> collectImports Set.empty (moduleImports rootModule)

collectImports :: Set.Set ModuleName -> [ImportDecl] -> Either ModuleGraphError (Set.Set ModuleName, [LoadedModule])
collectImports seen imports =
  foldM collectImport (seen, []) imports

collectImport :: (Set.Set ModuleName, [LoadedModule]) -> ImportDecl -> Either ModuleGraphError (Set.Set ModuleName, [LoadedModule])
collectImport (seen, loaded) importDecl = do
  (seen', dependencies) <- collectVirtualStandardModule seen (importModule importDecl)
  pure (seen', loaded <> dependencies)

collectVirtualStandardModule :: Set.Set ModuleName -> ModuleName -> Either ModuleGraphError (Set.Set ModuleName, [LoadedModule])
collectVirtualStandardModule seen moduleName
  | moduleName `Set.member` seen = Right (seen, [])
  | Just source <- StandardLibrary.standardLibrarySourceModule moduleName = do
      let virtualPath = standardModuleVirtualPath moduleName
      parsed <-
        mapLeft
          (ModuleParseError virtualPath . Text.pack . errorBundlePretty)
          (parseSourceModule virtualPath source)
      let actualName = sourceModuleName parsed
      if actualName /= moduleName
        then Left (ModuleNameMismatch virtualPath moduleName actualName)
        else do
          (seenWithDependencies, dependencies) <-
            collectImports (Set.insert moduleName seen) (moduleImports parsed)
          let loaded =
                LoadedModule
                  { loadedModulePath = normalise virtualPath
                  , loadedModuleName = moduleName
                  , loadedModuleSource = source
                  , loadedModuleParsed = parsed
                  }
          pure (seenWithDependencies, dependencies <> [loaded])
  | otherwise = Right (seen, [])

loadModule ::
  ModuleSearchPolicy ->
  FilePath ->
  [ModuleName] ->
  LoadState ->
  FilePath ->
  Maybe ModuleName ->
  IO (Either ModuleGraphError LoadState)
loadModule searchPolicy rootDirectory active state path expectedName =
  case expectedName >>= (`Map.lookup` loadedByName state) of
    Just {} ->
      pure (Right state)
    Nothing -> do
      sourceResult <- readModuleSource path
      case sourceResult of
        Left err ->
          pure (Left err)
        Right source -> do
          let parsedResult =
                mapLeft
                  (ModuleParseError path . Text.pack . errorBundlePretty)
                  (parseSourceModule path source)
          case parsedResult of
            Left err ->
              pure (Left err)
            Right parsed -> do
              let actualName = sourceModuleName parsed
              pureOrContinue searchPolicy rootDirectory active state path source parsed actualName expectedName

pureOrContinue ::
  ModuleSearchPolicy ->
  FilePath ->
  [ModuleName] ->
  LoadState ->
  FilePath ->
  Text ->
  HsModule ->
  ModuleName ->
  Maybe ModuleName ->
  IO (Either ModuleGraphError LoadState)
pureOrContinue searchPolicy rootDirectory active state path source parsed actualName expectedName = do
  let normalizedPath = normalise path
  case expectedName of
    Just expected | expected /= actualName ->
      pure (Left (ModuleNameMismatch normalizedPath expected actualName))
    _ ->
      case Map.lookup actualName (loadedByName state) of
        Just previous
          | loadedModulePath previous == normalizedPath ->
              pure (Right state)
          | otherwise ->
              pure (Left (DuplicateModule actualName (loadedModulePath previous) normalizedPath))
        Nothing
          | actualName `elem` active ->
              pure (Left (ModuleCycle (cyclePath actualName active)))
          | otherwise -> do
              dependencies <-
                foldM
                  (loadImport searchPolicy rootDirectory (actualName : active))
                  (Right state)
                  (moduleImports parsed)
              pure $ do
                stateWithDependencies <- dependencies
                let loaded =
                      LoadedModule
                        { loadedModulePath = normalizedPath
                        , loadedModuleName = actualName
                        , loadedModuleSource = source
                        , loadedModuleParsed = parsed
                        }
                pure
                  stateWithDependencies
                    { loadedByName = Map.insert actualName loaded (loadedByName stateWithDependencies)
                    , loadedOrder = loadedOrder stateWithDependencies <> [loaded]
                    }

loadImport ::
  ModuleSearchPolicy ->
  FilePath ->
  [ModuleName] ->
  Either ModuleGraphError LoadState ->
  ImportDecl ->
  IO (Either ModuleGraphError LoadState)
loadImport searchPolicy rootDirectory active stateResult importDecl =
  case stateResult of
    Left err ->
      pure (Left err)
    Right state
      | Map.member (importModule importDecl) (loadedByName state) ->
          pure (Right state)
      | Just source <- StandardLibrary.standardLibrarySourceModule (importModule importDecl) ->
          loadVirtualStandardModule
            searchPolicy
            rootDirectory
            active
            state
            (importModule importDecl)
            source
      | isBuiltinModule (importModule importDecl) ->
          pure (Right state)
      | otherwise ->
          loadModuleBySearchPath
            searchPolicy
            rootDirectory
            active
            state
            (importModule importDecl)

loadModuleBySearchPath ::
  ModuleSearchPolicy ->
  FilePath ->
  [ModuleName] ->
  LoadState ->
  ModuleName ->
  IO (Either ModuleGraphError LoadState)
loadModuleBySearchPath searchPolicy rootDirectory active state expectedName =
  go candidates
 where
  candidates =
    resolveModuleImportPaths searchPolicy rootDirectory expectedName
  go [] =
    pure (Left (ModuleNotFound expectedName candidates))
  go (path : rest) = do
    sourceResult <- readModuleSourceCandidate path
    case sourceResult of
      ModuleSourceMissing ->
        go rest
      ModuleSourceReadError message ->
        pure (Left (ModuleReadError path message))
      ModuleSourceFound source -> do
        let parsedResult =
              mapLeft
                (ModuleParseError path . Text.pack . errorBundlePretty)
                (parseSourceModule path source)
        case parsedResult of
          Left err ->
            pure (Left err)
          Right parsed ->
            pureOrContinue searchPolicy rootDirectory active state path source parsed (sourceModuleName parsed) (Just expectedName)

loadVirtualStandardModule ::
  ModuleSearchPolicy ->
  FilePath ->
  [ModuleName] ->
  LoadState ->
  ModuleName ->
  Text ->
  IO (Either ModuleGraphError LoadState)
loadVirtualStandardModule searchPolicy rootDirectory active state moduleName source =
  case parseResult of
    Left err ->
      pure (Left err)
    Right parsed ->
      pureOrContinue searchPolicy rootDirectory active state virtualPath source parsed (sourceModuleName parsed) (Just moduleName)
 where
  virtualPath =
    standardModuleVirtualPath moduleName
  parseResult =
    mapLeft
      (ModuleParseError virtualPath . Text.pack . errorBundlePretty)
      (parseSourceModule virtualPath source)

standardModuleVirtualPath :: ModuleName -> FilePath
standardModuleVirtualPath moduleName =
  "<standard-library>" </> moduleNamePath moduleName <.> "hs"

moduleNamePath :: ModuleName -> FilePath
moduleNamePath (ModuleName parts) =
  joinPath (map Text.unpack parts)

readModuleSource :: FilePath -> IO (Either ModuleGraphError Text)
readModuleSource path = do
  result <- try (Text.IO.readFile path) :: IO (Either IOException Text)
  pure $
    case result of
      Left err ->
        Left (ModuleReadError path (Text.pack (show err)))
      Right source ->
        Right source

data ModuleSourceCandidate
  = ModuleSourceFound Text
  | ModuleSourceMissing
  | ModuleSourceReadError Text
  deriving stock (Show, Eq, Ord)

readModuleSourceCandidate :: FilePath -> IO ModuleSourceCandidate
readModuleSourceCandidate path = do
  result <- try (Text.IO.readFile path) :: IO (Either IOException Text)
  pure $
    case result of
      Left err
        | isDoesNotExistError err -> ModuleSourceMissing
        | otherwise -> ModuleSourceReadError (Text.pack (show err))
      Right source ->
        ModuleSourceFound source

sourceModuleName :: HsModule -> ModuleName
sourceModuleName sourceModule =
  case moduleName sourceModule of
    Just name -> name
    Nothing -> ModuleName ["Main"]

resolveModuleImportPath :: ModuleSearchPolicy -> FilePath -> ModuleName -> FilePath
resolveModuleImportPath searchPolicy rootDirectory moduleName =
  case resolveModuleImportPaths searchPolicy rootDirectory moduleName of
    path : _ -> path
    [] -> rootDirectory </> moduleNamePath moduleName <.> "hs"

resolveModuleImportPaths :: ModuleSearchPolicy -> FilePath -> ModuleName -> [FilePath]
resolveModuleImportPaths (RootDirectoryAndImportPathSourceSearch importPaths) rootDirectory moduleName =
  [ directory </> moduleNamePath moduleName <.> "hs"
  | directory <- uniqueNormalisedPaths (rootDirectory : importPaths)
  ]

uniqueNormalisedPaths :: [FilePath] -> [FilePath]
uniqueNormalisedPaths =
  go Set.empty []
 where
  go _ acc [] =
    reverse acc
  go seen acc (path : rest) =
    let normalized = normalise path
     in if normalized `Set.member` seen
          then go seen acc rest
          else go (Set.insert normalized seen) (normalized : acc) rest

isBuiltinModule :: ModuleName -> Bool
isBuiltinModule moduleName =
  Map.member moduleName StandardLibrary.standardLibraryModuleInterfaces

cyclePath :: ModuleName -> [ModuleName] -> [ModuleName]
cyclePath repeated active =
  repeated : (takeWhile (/= repeated) active <> [repeated])

wholeProgramModule :: [RHsModule] -> RHsModule
wholeProgramModule modules =
  case modules of
    [] ->
      RHsModule
        { rModuleName = Nothing
        , rModuleExports = Nothing
        , rModuleImports = []
        , rModuleFixities = Map.empty
        , rModuleDecls = []
        }
    root : rest ->
      let finalRoot = lastModule root rest
       in RHsModule
            { rModuleName = rModuleName finalRoot
            , rModuleExports = rModuleExports finalRoot
            , rModuleImports = concatMap rModuleImports modules
            , rModuleFixities = Map.unions (map rModuleFixities modules)
            -- Haskell 2010 imports all instances along the transitive import
            -- chain. Keeping every dependency declaration in the flattened
            -- module makes instance dictionaries available to typechecking and
            -- later lowering even when the declaring module exports no names.
            , rModuleDecls = concatMap rModuleDecls modules
            }
 where
  lastModule latest [] =
    latest
  lastModule _ (next : rest) =
    lastModule next rest

renderModuleGraphError :: ModuleGraphError -> Text
renderModuleGraphError = \case
  ModuleReadError path message ->
    "could not read Haskell 2010 module " <> Text.pack path <> ": " <> message
  ModuleParseError path message ->
    "Haskell 2010 parse error in " <> Text.pack path <> ":\n" <> message
  ModuleNameMismatch path expected actual ->
    "module name mismatch in "
      <> Text.pack path
      <> ": expected `"
      <> renderModuleName expected
      <> "`, got `"
      <> renderModuleName actual
      <> "`"
  DuplicateModule name firstPath secondPath ->
    "duplicate Haskell 2010 module `"
      <> renderModuleName name
      <> "` loaded from "
      <> Text.pack firstPath
      <> " and "
      <> Text.pack secondPath
  ModuleCycle names ->
    "cyclic Haskell 2010 module imports: "
      <> Text.intercalate " -> " (map renderModuleName names)
  ModuleNotFound name paths ->
    "could not read Haskell 2010 module `"
      <> renderModuleName name
      <> "`: no source file found; searched: "
      <> Text.intercalate ", " (map Text.pack paths)

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
