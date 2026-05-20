module Haskell2010.ModuleGraph
  ( LoadedModule (..)
  , LoadedModuleGraph (..)
  , ModuleGraphError (..)
  , loadModuleGraph
  , renderModuleGraphError
  , sourceModuleName
  , wholeProgramModule
  )
where

import Control.Exception (IOException, try)
import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Haskell2010.Parser (parseSourceModule)
import Haskell2010.Pretty (renderModuleName)
import Haskell2010.Renamed
import Haskell2010.Syntax
import System.FilePath ((<.>), (</>), joinPath, normalise, takeDirectory)
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
  deriving stock (Show, Eq, Ord)

data LoadState = LoadState
  { loadedByName :: Map.Map ModuleName LoadedModule
  , loadedOrder :: [LoadedModule]
  }
  deriving stock (Show, Eq, Ord)

loadModuleGraph :: FilePath -> IO (Either ModuleGraphError LoadedModuleGraph)
loadModuleGraph rootPath = do
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
    loadModule (takeDirectory path) [] emptyLoadState (normalise path) Nothing

emptyLoadState :: LoadState
emptyLoadState =
  LoadState
    { loadedByName = Map.empty
    , loadedOrder = []
    }

loadModule ::
  FilePath ->
  [ModuleName] ->
  LoadState ->
  FilePath ->
  Maybe ModuleName ->
  IO (Either ModuleGraphError LoadState)
loadModule rootDirectory active state path expectedName =
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
              pureOrContinue rootDirectory active state path source parsed actualName expectedName

pureOrContinue ::
  FilePath ->
  [ModuleName] ->
  LoadState ->
  FilePath ->
  Text ->
  HsModule ->
  ModuleName ->
  Maybe ModuleName ->
  IO (Either ModuleGraphError LoadState)
pureOrContinue rootDirectory active state path source parsed actualName expectedName = do
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
              dependencies <- foldM (loadImport rootDirectory (actualName : active)) (Right state) (moduleImports parsed)
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

loadImport :: FilePath -> [ModuleName] -> Either ModuleGraphError LoadState -> ImportDecl -> IO (Either ModuleGraphError LoadState)
loadImport rootDirectory active stateResult importDecl =
  case stateResult of
    Left err ->
      pure (Left err)
    Right state
      | isBuiltinModule (importModule importDecl) ->
          pure (Right state)
      | Map.member (importModule importDecl) (loadedByName state) ->
          pure (Right state)
      | otherwise ->
          loadModule rootDirectory active state (moduleNamePath rootDirectory (importModule importDecl)) (Just (importModule importDecl))

readModuleSource :: FilePath -> IO (Either ModuleGraphError Text)
readModuleSource path = do
  result <- try (Text.IO.readFile path) :: IO (Either IOException Text)
  pure $
    case result of
      Left err ->
        Left (ModuleReadError path (Text.pack (show err)))
      Right source ->
        Right source

sourceModuleName :: HsModule -> ModuleName
sourceModuleName sourceModule =
  case moduleName sourceModule of
    Just name -> name
    Nothing -> ModuleName ["Main"]

moduleNamePath :: FilePath -> ModuleName -> FilePath
moduleNamePath rootDirectory (ModuleName parts) =
  rootDirectory </> joinPath (map Text.unpack parts) <.> "hs"

isBuiltinModule :: ModuleName -> Bool
isBuiltinModule (ModuleName parts) =
  parts == ["Prelude"]

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

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
