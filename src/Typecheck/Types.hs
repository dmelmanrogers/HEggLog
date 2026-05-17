module Typecheck.Types
  ( TypeEnv
  , TypeError (..)
  , emptyTypeEnv
  , renderTypeError
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Prettyprinter ((<+>))
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

type TypeEnv = Map.Map Name Type

emptyTypeEnv :: TypeEnv
emptyTypeEnv = Map.empty

data TypeError
  = UnknownVariable Name
  | TypeMismatch Type Type
  | ExpectedIntOperand BinOp Type
  | ExpectedBoolCondition Type
  | ExpectedFunction Type
  | EqualityNotSupported Type
  deriving stock (Show, Eq)

renderTypeError :: TypeError -> Text
renderTypeError = \case
  UnknownVariable name ->
    renderDoc ("unknown variable:" <+> prettyName name)
  TypeMismatch expected actual ->
    renderDoc ("type mismatch: expected" <+> prettyType expected <> ", got" <+> prettyType actual)
  ExpectedIntOperand op actual ->
    renderDoc ("operator" <+> prettyBinOp op <+> "expects Int operands, got" <+> prettyType actual)
  ExpectedBoolCondition actual ->
    renderDoc ("if condition must be Bool, got" <+> prettyType actual)
  ExpectedFunction actual ->
    renderDoc ("expected a function, got" <+> prettyType actual)
  EqualityNotSupported actual ->
    renderDoc ("equality is only supported for Int and Bool, got" <+> prettyType actual)
