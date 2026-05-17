module Analysis.Facts
  ( ConstValue (..)
  , Fact (..)
  , renderConstValue
  , renderFact
  , renderFacts
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST
import Syntax.Pretty (prettyName, prettyType, renderDoc)

data ConstValue
  = ConstInt Integer
  | ConstBool Bool
  deriving stock (Show, Eq, Ord)

data Fact
  = HasType Name Type
  | IsPure Name
  | IsConst Name ConstValue
  | NonZero Name
  deriving stock (Show, Eq, Ord)

renderFacts :: [Fact] -> Text
renderFacts [] =
  "<none>"
renderFacts facts =
  Text.unlines (map renderFact facts)

renderFact :: Fact -> Text
renderFact = \case
  HasType name ty ->
    "HasType " <> renderDoc (prettyName name) <> " " <> renderDoc (prettyType ty)
  IsPure name ->
    "IsPure " <> renderDoc (prettyName name)
  IsConst name value ->
    "IsConst " <> renderDoc (prettyName name) <> " " <> renderConstValue value
  NonZero name ->
    "NonZero " <> renderDoc (prettyName name)

renderConstValue :: ConstValue -> Text
renderConstValue = \case
  ConstInt n -> Text.pack (show n)
  ConstBool True -> "true"
  ConstBool False -> "false"
