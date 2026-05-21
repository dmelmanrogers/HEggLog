module Haskell2010.ModuleInterface
  ( InterfaceInstance (..)
  , ModuleInterface (..)
  )
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Haskell2010.Names (RName)
import Haskell2010.Renamed (RHsType)
import Haskell2010.Syntax (Fixity, ModuleName)

data InterfaceInstance = InterfaceInstance
  { interfaceInstanceContext :: [RHsType]
  , interfaceInstanceHead :: RHsType
  , interfaceInstanceDictionary :: Maybe RName
  }
  deriving stock (Show, Eq, Ord)

data ModuleInterface = ModuleInterface
  { interfaceModuleName :: ModuleName
  , interfaceExports :: [RName]
  , interfaceChildren :: Map RName [RName]
  , interfaceFixities :: Map Text Fixity
  , interfaceInstances :: [InterfaceInstance]
  }
  deriving stock (Show, Eq)
