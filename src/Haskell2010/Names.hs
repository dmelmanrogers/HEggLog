module Haskell2010.Names
  ( Namespace (..)
  , RName (..)
  , renderNamespace
  , renderRName
  )
where

import Data.Text (Text)
import qualified Data.Text as Text

data Namespace
  = TermNamespace
  | ConstructorNamespace
  | TypeNamespace
  | TypeVariableNamespace
  | ClassNamespace
  | ModuleNamespace
  deriving stock (Show, Eq, Ord)

data RName = RName
  { nameNamespace :: Namespace
  , nameOcc :: Text
  , nameUnique :: Int
  , nameExternal :: Bool
  }
  deriving stock (Show, Eq, Ord)

renderNamespace :: Namespace -> Text
renderNamespace = \case
  TermNamespace -> "term"
  ConstructorNamespace -> "constructor"
  TypeNamespace -> "type"
  TypeVariableNamespace -> "type variable"
  ClassNamespace -> "class"
  ModuleNamespace -> "module"

renderRName :: RName -> Text
renderRName name =
  nameOcc name <> "#" <> Text.pack (show (nameUnique name))
