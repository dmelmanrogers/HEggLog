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
  | BackendUnknownFunction Name
  | BackendDuplicateFunction Name
  | BackendDuplicateParameter Name
  | BackendRootTypeMismatch BackendType BackendType
  | BackendFunctionReturnTypeMismatch Name BackendType BackendType
  | BackendAtomTypeMismatch BackendType BackendType BackendAtom
  | BackendPrimitiveResultMismatch BackendPrim BackendType BackendType
  | BackendCallArityMismatch Name Int Int
  | BackendCallArgumentTypeMismatch Name BackendType BackendType BackendAtom
  | BackendIfConditionTypeMismatch BackendType
  | BackendIfBranchTypeMismatch BackendType BackendType
  | BackendLetTypeMismatch Name BackendType BackendType
  deriving stock (Show, Eq, Ord)

type TypeEnv = Map.Map Name BackendType

type FunctionEnv = Map.Map Name ([BackendType], BackendType)

validateBackendProgram :: BackendProgram -> Either BackendValidationError ()
validateBackendProgram program = do
  fullFunctionEnv <- buildFunctionEnv (backendFunctions program)
  validateBackendFunctions Map.empty (backendFunctions program)
  actual <- inferBackendExprType fullFunctionEnv Map.empty (backendRoot program)
  if actual == backendRootType program
    then Right ()
    else Left (BackendRootTypeMismatch (backendRootType program) actual)

buildFunctionEnv :: [BackendFunction] -> Either BackendValidationError FunctionEnv
buildFunctionEnv =
  go Map.empty
 where
  go env = \case
    [] ->
      Right env
    function : rest
      | backendFunctionName function `Map.member` env ->
          Left (BackendDuplicateFunction (backendFunctionName function))
      | otherwise ->
          go
            ( Map.insert
                (backendFunctionName function)
                (map snd (backendFunctionParams function), backendFunctionReturnType function)
                env
            )
            rest

validateBackendFunction :: FunctionEnv -> BackendFunction -> Either BackendValidationError ()
validateBackendFunction functionEnv function = do
  checkDuplicateParams (map fst (backendFunctionParams function))
  actual <- inferBackendExprType functionEnv (Map.fromList (backendFunctionParams function)) (backendFunctionBody function)
  if actual == backendFunctionReturnType function
    then Right ()
    else Left (BackendFunctionReturnTypeMismatch (backendFunctionName function) (backendFunctionReturnType function) actual)

validateBackendFunctions :: FunctionEnv -> [BackendFunction] -> Either BackendValidationError ()
validateBackendFunctions _ [] =
  Right ()
validateBackendFunctions functionEnv (function : rest) = do
  validateBackendFunction functionEnv function
  validateBackendFunctions
    ( Map.insert
        (backendFunctionName function)
        (map snd (backendFunctionParams function), backendFunctionReturnType function)
        functionEnv
    )
    rest

checkDuplicateParams :: [Name] -> Either BackendValidationError ()
checkDuplicateParams =
  go Map.empty
 where
  go _ [] =
    Right ()
  go seen (name : rest)
    | name `Map.member` seen = Left (BackendDuplicateParameter name)
    | otherwise = go (Map.insert name () seen) rest

inferBackendExprType :: FunctionEnv -> TypeEnv -> BackendExpr -> Either BackendValidationError BackendType
inferBackendExprType functionEnv env = \case
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
    thenType <- inferBackendExprType functionEnv env thenBranch
    elseType <- inferBackendExprType functionEnv env elseBranch
    if thenType == elseType
      then Right ()
      else Left (BackendIfBranchTypeMismatch thenType elseType)
    if expected == thenType
      then Right expected
      else Left (BackendRootTypeMismatch expected thenType)
  BECall expected callee args -> do
    case Map.lookup callee functionEnv of
      Nothing ->
        Left (BackendUnknownFunction callee)
      Just (paramTypes, returnType) -> do
        if length paramTypes == length args
          then Right ()
          else Left (BackendCallArityMismatch callee (length paramTypes) (length args))
        mapM_ (uncurry (assertCallAtomType callee env)) (zip paramTypes args)
        if expected == returnType
          then Right expected
          else Left (BackendRootTypeMismatch expected returnType)
  BELet expected name rhs body -> do
    rhsType <- inferBackendExprType functionEnv env rhs
    bodyType <- inferBackendExprType functionEnv (Map.insert name rhsType env) body
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

assertCallAtomType :: Name -> TypeEnv -> BackendType -> BackendAtom -> Either BackendValidationError ()
assertCallAtomType callee env expected atom = do
  actual <- inferBackendAtomType env atom
  if actual == expected
    then Right ()
    else Left (BackendCallArgumentTypeMismatch callee expected actual atom)

renderBackendValidationError :: BackendValidationError -> Text
renderBackendValidationError = \case
  BackendUnboundVariable name ->
    "unbound backend variable " <> renderDoc (prettyName name)
  BackendUnknownFunction name ->
    "unknown backend function " <> renderDoc (prettyName name)
  BackendDuplicateFunction name ->
    "duplicate backend function " <> renderDoc (prettyName name)
  BackendDuplicateParameter name ->
    "duplicate backend function parameter " <> renderDoc (prettyName name)
  BackendRootTypeMismatch expected actual ->
    "backend root type mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendFunctionReturnTypeMismatch name expected actual ->
    "backend function " <> renderDoc (prettyName name) <> " return type mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendAtomTypeMismatch expected actual atom ->
    "backend atom type mismatch for " <> Text.pack (show atom) <> ": expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendPrimitiveResultMismatch prim expected actual ->
    "backend primitive " <> Text.pack (show prim) <> " result mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendCallArityMismatch name expected actual ->
    "backend call to " <> renderDoc (prettyName name) <> " has " <> Text.pack (show actual) <> " arguments, expected " <> Text.pack (show expected)
  BackendCallArgumentTypeMismatch name expected actual atom ->
    "backend call argument for " <> renderDoc (prettyName name) <> " has wrong type for " <> Text.pack (show atom) <> ": expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
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
