module Backend.Validate
  ( BackendValidationError (..)
  , inferBackendExprType
  , renderBackendValidationError
  , validateBackendProgram
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Backend.IR
import Syntax.AST (Name)
import Syntax.Pretty (prettyName, renderDoc)

data BackendValidationError
  = BackendUnboundVariable Name
  | BackendRootTypeMismatch BackendType BackendType
  | BackendAtomTypeMismatch BackendType BackendType BackendAtom
  | BackendPrimitiveResultMismatch BackendPrim BackendType BackendType
  | BackendIfConditionTypeMismatch BackendType
  | BackendIfBranchTypeMismatch BackendType BackendType
  | BackendLetTypeMismatch Name BackendType BackendType
  deriving stock (Show, Eq, Ord)

type TypeEnv = Map.Map Name BackendType

validateBackendProgram :: BackendProgram -> Either BackendValidationError ()
validateBackendProgram program = do
  actual <- inferBackendExprType Map.empty (backendRoot program)
  if actual == backendRootType program
    then Right ()
    else Left (BackendRootTypeMismatch (backendRootType program) actual)

inferBackendExprType :: TypeEnv -> BackendExpr -> Either BackendValidationError BackendType
inferBackendExprType env = \case
  BEAtom expected atom -> do
    actual <- inferBackendAtomType env atom
    if actual == expected
      then Right expected
      else Left (BackendAtomTypeMismatch expected actual atom)
  BEPrim expected prim lhs rhs -> do
    let operandType = backendPrimOperandType prim
        resultType = backendPrimResultType prim
    assertAtomType env operandType lhs
    assertAtomType env operandType rhs
    if expected == resultType
      then Right expected
      else Left (BackendPrimitiveResultMismatch prim resultType expected)
  BEIf expected cond thenBranch elseBranch -> do
    condType <- inferBackendAtomType env cond
    if condType == BI1
      then Right ()
      else Left (BackendIfConditionTypeMismatch condType)
    thenType <- inferBackendExprType env thenBranch
    elseType <- inferBackendExprType env elseBranch
    if thenType == elseType
      then Right ()
      else Left (BackendIfBranchTypeMismatch thenType elseType)
    if expected == thenType
      then Right expected
      else Left (BackendRootTypeMismatch expected thenType)
  BELet expected name rhs body -> do
    rhsType <- inferBackendExprType env rhs
    bodyType <- inferBackendExprType (Map.insert name rhsType env) body
    if expected == bodyType
      then Right expected
      else Left (BackendLetTypeMismatch name expected bodyType)

inferBackendAtomType :: TypeEnv -> BackendAtom -> Either BackendValidationError BackendType
inferBackendAtomType env = \case
  BVar name ->
    case Map.lookup name env of
      Just ty -> Right ty
      Nothing -> Left (BackendUnboundVariable name)
  BInt {} ->
    Right BI64
  BBool {} ->
    Right BI1

assertAtomType :: TypeEnv -> BackendType -> BackendAtom -> Either BackendValidationError ()
assertAtomType env expected atom = do
  actual <- inferBackendAtomType env atom
  if actual == expected
    then Right ()
    else Left (BackendAtomTypeMismatch expected actual atom)

renderBackendValidationError :: BackendValidationError -> Text
renderBackendValidationError = \case
  BackendUnboundVariable name ->
    "unbound backend variable " <> renderDoc (prettyName name)
  BackendRootTypeMismatch expected actual ->
    "backend root type mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendAtomTypeMismatch expected actual atom ->
    "backend atom type mismatch for " <> Text.pack (show atom) <> ": expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendPrimitiveResultMismatch prim expected actual ->
    "backend primitive " <> Text.pack (show prim) <> " result mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendIfConditionTypeMismatch actual ->
    "backend if condition must be BI1, got " <> renderBackendType actual
  BackendIfBranchTypeMismatch thenType elseType ->
    "backend if branches must match, got " <> renderBackendType thenType <> " and " <> renderBackendType elseType
  BackendLetTypeMismatch name expected actual ->
    "backend let body type mismatch for " <> renderDoc (prettyName name) <> ": expected " <> renderBackendType expected <> ", got " <> renderBackendType actual

renderBackendType :: BackendType -> Text
renderBackendType = \case
  BI64 -> "BI64"
  BI1 -> "BI1"
