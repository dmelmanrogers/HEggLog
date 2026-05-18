module Haskell2010.Pretty
  ( renderModuleName
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Syntax (ModuleName (..))

renderModuleName :: ModuleName -> Text
renderModuleName (ModuleName parts) =
  Text.intercalate "." parts
