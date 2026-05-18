module Typecheck.Types
  ( TypeEnv
  , LocatedTypeError (..)
  , TypeError (..)
  , emptyTypeEnv
  , renderLocatedTypeError
  , renderTypeError
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Prettyprinter ((<+>))
import qualified Runtime.Int as HInt
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)
import Syntax.Span (SourceSpan, renderSourceDiagnostic)

type TypeEnv = Map.Map Name Type

emptyTypeEnv :: TypeEnv
emptyTypeEnv = Map.empty

data TypeError
  = UnknownVariable Name
  | DuplicateTopLevelName Name
  | DuplicateParameter Name
  | TypeMismatch Type Type
  | ExpectedIntOperand BinOp Type
  | ExpectedBoolCondition Type
  | ExpectedFunction Type
  | EqualityNotSupported Type
  | AmbiguousLambdaParameter Name
  | AmbiguousExpressionType
  | AmbiguousEqualityOperand
  | RecursiveType
  | TopLevelFunctionTypeUnsupported Name Type
  | IntLiteralOutOfRange Integer
  deriving stock (Show, Eq)

data LocatedTypeError = LocatedTypeError
  { locatedTypeErrorSpan :: SourceSpan
  , locatedTypeErrorDetail :: TypeError
  }
  deriving stock (Show, Eq)

renderLocatedTypeError :: LocatedTypeError -> Text
renderLocatedTypeError err =
  renderSourceDiagnostic
    (locatedTypeErrorSpan err)
    "type error"
    (renderTypeError (locatedTypeErrorDetail err))

renderTypeError :: TypeError -> Text
renderTypeError = \case
  UnknownVariable name ->
    renderDoc ("unknown variable:" <+> prettyName name)
  DuplicateTopLevelName name ->
    renderDoc ("duplicate top-level definition:" <+> prettyName name)
  DuplicateParameter name ->
    renderDoc ("duplicate function parameter:" <+> prettyName name)
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
  AmbiguousLambdaParameter name ->
    renderDoc ("cannot infer a monomorphic type for lambda parameter:" <+> prettyName name)
  AmbiguousExpressionType ->
    "cannot infer a monomorphic type for this expression"
  AmbiguousEqualityOperand ->
    "cannot infer whether equality operands are Int or Bool"
  RecursiveType ->
    "recursive function types are not supported"
  TopLevelFunctionTypeUnsupported name ty ->
    renderDoc ("top-level first-order function" <+> prettyName name <+> "cannot use function type" <+> prettyType ty)
  IntLiteralOutOfRange value ->
    "integer literal "
      <> Text.pack (show value)
      <> " is outside HeggLog Int range ["
      <> Text.pack (show HInt.minHIntInteger)
      <> ", "
      <> Text.pack (show HInt.maxHIntInteger)
      <> "]"
