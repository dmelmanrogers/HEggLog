module Backend.Lower
  ( BackendLowerError (..)
  , lowerANFToBackend
  , renderBackendLowerError
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Backend.IR
import Backend.Validate
import IR.ANF
import IR.ANF.Validate
import Runtime.Int (IntError, mkHIntLiteral, renderIntError)
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

data BackendLowerError
  = BackendInvalidANF ANFValidationError
  | BackendUnsupportedLambda Name Type
  | BackendUnsupportedApplication Atom Atom
  | BackendUnsupportedPrimitive BinOp
  | BackendUnboundANFVariable Name
  | BackendTypeMismatch BackendType BackendType
  | BackendCannotLowerFunctionType Type
  | BackendIntError IntError
  | BackendValidationFailed BackendValidationError
  deriving stock (Show, Eq)

type TypeEnv = Map.Map Name BackendType

lowerANFToBackend :: AExpr -> Either BackendLowerError BackendProgram
lowerANFToBackend expression = do
  mapLeft BackendInvalidANF (validateANF expression)
  root <- lowerExpr Map.empty expression
  let program =
        BackendProgram
          { backendRootType = backendExprType root
          , backendRoot = root
          , backendProvenance = ["lowered from ANF"]
          }
  mapLeft BackendValidationFailed (validateBackendProgram program)
  pure program

lowerExpr :: TypeEnv -> AExpr -> Either BackendLowerError BackendExpr
lowerExpr env = \case
  AAtom atom -> do
    ty <- lowerAtomType env atom
    BEAtom ty <$> lowerAtom atom
  APrim op lhs rhs -> do
    lowerPrim env op lhs rhs
  AIf cond thenBranch elseBranch -> do
    condType <- lowerAtomType env cond
    assertType BI1 condType
    thenLowered <- lowerExpr env thenBranch
    elseLowered <- lowerExpr env elseBranch
    assertType (backendExprType thenLowered) (backendExprType elseLowered)
    loweredCond <- lowerAtom cond
    pure (BEIf (backendExprType thenLowered) loweredCond thenLowered elseLowered)
  ALam name ty _ ->
    Left (BackendUnsupportedLambda name ty)
  AApp fn arg ->
    Left (BackendUnsupportedApplication fn arg)
  ALet name rhs body -> do
    rhsLowered <- lowerExpr env rhs
    let env' = Map.insert name (backendExprType rhsLowered) env
    bodyLowered <- lowerExpr env' body
    pure (BELet (backendExprType bodyLowered) name rhsLowered bodyLowered)

lowerPrim :: TypeEnv -> BinOp -> Atom -> Atom -> Either BackendLowerError BackendExpr
lowerPrim env op lhs rhs =
  case op of
    Add -> intPrim BPAdd
    Sub -> intPrim BPSub
    Mul -> intPrim BPMul
    Lt -> intPrim BPLt
    Eq -> equalityPrim
    Div -> Left (BackendUnsupportedPrimitive Div)
 where
  intPrim prim = do
    assertAtomType env BI64 lhs
    assertAtomType env BI64 rhs
    loweredLhs <- lowerAtom lhs
    loweredRhs <- lowerAtom rhs
    pure (BEPrim (backendPrimResultType prim) prim loweredLhs loweredRhs)

  equalityPrim = do
    lhsType <- lowerAtomType env lhs
    rhsType <- lowerAtomType env rhs
    assertType lhsType rhsType
    loweredLhs <- lowerAtom lhs
    loweredRhs <- lowerAtom rhs
    pure (BEPrim BI1 (BPEq lhsType) loweredLhs loweredRhs)

lowerAtom :: Atom -> Either BackendLowerError BackendAtom
lowerAtom = \case
  AVar name ->
    Right (BVar name)
  AInt n ->
    case mkHIntLiteral n of
      Right value -> Right (BInt value)
      Left err -> Left (BackendIntError err)
  ABool b ->
    Right (BBool b)

lowerAtomType :: TypeEnv -> Atom -> Either BackendLowerError BackendType
lowerAtomType env = \case
  AVar name ->
    case Map.lookup name env of
      Just ty -> Right ty
      Nothing -> Left (BackendUnboundANFVariable name)
  AInt {} ->
    Right BI64
  ABool {} ->
    Right BI1

assertAtomType :: TypeEnv -> BackendType -> Atom -> Either BackendLowerError ()
assertAtomType env expected atom = do
  actual <- lowerAtomType env atom
  assertType expected actual

assertType :: BackendType -> BackendType -> Either BackendLowerError ()
assertType expected actual
  | expected == actual = Right ()
  | otherwise = Left (BackendTypeMismatch expected actual)

renderBackendLowerError :: BackendLowerError -> Text
renderBackendLowerError = \case
  BackendInvalidANF err ->
    "invalid ANF before backend lowering: " <> renderANFValidationError err
  BackendUnsupportedLambda name ty ->
    "LLVM backend does not support lambda binder " <> renderDoc (prettyName name) <> " : " <> renderDoc (prettyType ty)
  BackendUnsupportedApplication fn arg ->
    "LLVM backend does not support function application " <> Text.pack (show fn) <> " " <> Text.pack (show arg)
  BackendUnsupportedPrimitive op ->
    "LLVM backend does not support primitive " <> renderDoc (prettyBinOp op)
  BackendUnboundANFVariable name ->
    "LLVM backend cannot lower open variable " <> renderDoc (prettyName name)
  BackendTypeMismatch expected actual ->
    "backend type mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  BackendCannotLowerFunctionType ty ->
    "LLVM backend cannot lower function type " <> renderDoc (prettyType ty)
  BackendIntError err ->
    renderIntError err
  BackendValidationFailed err ->
    renderBackendValidationError err

renderBackendType :: BackendType -> Text
renderBackendType = \case
  BI64 -> "BI64"
  BI1 -> "BI1"

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value
