module Optimize.EgglogBackend.Fragment
  ( FragmentError (..)
  , SupportedFragment
  , TypedResolvedAExpr (..)
  , TypedResolvedAtom (..)
  , classifyEgglogFragment
  , classifyResolvedANF
  , renderFragmentError
  , typedExprType
  , typedFreeVariableTypes
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import IR.ANF.Resolved
import Runtime.Int (IntError, mkHIntLiteral, renderIntError)
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

data FragmentError
  = UnsupportedLambda Binder
  | UnsupportedApplication TypedResolvedAtom TypedResolvedAtom
  | UnsupportedDirectCall Name
  | UnsupportedPrimitive BinOp
  | UnsupportedType Type
  | AmbiguousFreeVariable Name
  | UnboundResolvedBinder Binder
  | TypeMismatch Type Type
  | InvalidIntLiteral IntError
  deriving stock (Show, Eq, Ord)

data TypedResolvedAtom = TypedResolvedAtom
  { typedAtomType :: Type
  , typedAtomNode :: ResolvedAtom
  }
  deriving stock (Show, Eq, Ord)

data TypedResolvedAExpr
  = TRAtom TypedResolvedAtom
  | TRPrim Type BinOp TypedResolvedAtom TypedResolvedAtom
  | TRIf Type TypedResolvedAtom TypedResolvedAExpr TypedResolvedAExpr
  | TRLet Type Binder TypedResolvedAExpr TypedResolvedAExpr
  deriving stock (Show, Eq, Ord)

type SupportedFragment = TypedResolvedAExpr

type TypeEnv = Map.Map BinderId Type

classifyResolvedANF :: ResolvedAExpr -> Either FragmentError TypedResolvedAExpr
classifyResolvedANF expression = do
  typed <- inferExpr Map.empty Nothing expression
  _ <- typedFreeVariableTypes typed
  pure typed

classifyEgglogFragment :: ResolvedAExpr -> Either FragmentError SupportedFragment
classifyEgglogFragment =
  classifyResolvedANF

typedExprType :: TypedResolvedAExpr -> Type
typedExprType = \case
  TRAtom atom ->
    typedAtomType atom
  TRPrim ty _ _ _ ->
    ty
  TRIf ty _ _ _ ->
    ty
  TRLet ty _ _ _ ->
    ty

typedFreeVariableTypes :: TypedResolvedAExpr -> Either FragmentError (Map.Map Name Type)
typedFreeVariableTypes =
  go Map.empty
 where
  go freeTypes = \case
    TRAtom atom ->
      addAtom freeTypes atom
    TRPrim _ _ lhs rhs -> do
      withLhs <- addAtom freeTypes lhs
      addAtom withLhs rhs
    TRIf _ cond thenBranch elseBranch -> do
      withCond <- addAtom freeTypes cond
      withThen <- go withCond thenBranch
      go withThen elseBranch
    TRLet _ _ rhs body -> do
      withRhs <- go freeTypes rhs
      go withRhs body

  addAtom freeTypes atom =
    case typedAtomNode atom of
      RVar (FreeVar name) ->
        addFreeVariableType name (typedAtomType atom) freeTypes
      _ ->
        Right freeTypes

addFreeVariableType :: Name -> Type -> Map.Map Name Type -> Either FragmentError (Map.Map Name Type)
addFreeVariableType name ty freeTypes =
  case Map.lookup name freeTypes of
    Just existing
      | existing == ty -> Right freeTypes
      | otherwise -> Left (TypeMismatch existing ty)
    Nothing ->
      Right (Map.insert name ty freeTypes)

inferExpr :: TypeEnv -> Maybe Type -> ResolvedAExpr -> Either FragmentError TypedResolvedAExpr
inferExpr env expected = \case
  RAtom atom ->
    TRAtom <$> inferAtom env expected atom
  RPrim op lhs rhs ->
    inferPrim env op lhs rhs
  RIf cond thenBranch elseBranch -> do
    condTyped <- inferAtom env (Just TBool) cond
    thenTyped <- inferExpr env expected thenBranch
    elseTyped <- inferExpr env (Just (typedExprType thenTyped)) elseBranch
    assertType (typedExprType thenTyped) (typedExprType elseTyped)
    maybe (Right ()) (`assertType` typedExprType thenTyped) expected
    pure (TRIf (typedExprType thenTyped) condTyped thenTyped elseTyped)
  RLam binder _ _ ->
    Left (UnsupportedLambda binder)
  RApp fn arg -> do
    fnTyped <- inferAtom env Nothing fn
    argTyped <- inferAtom env Nothing arg
    Left (UnsupportedApplication fnTyped argTyped)
  RCall callee _ ->
    Left (UnsupportedDirectCall callee)
  RLet binder rhs body -> do
    rhsTyped <- inferExpr env Nothing rhs
    let env' = Map.insert (binderId binder) (typedExprType rhsTyped) env
    bodyTyped <- inferExpr env' expected body
    pure (TRLet (typedExprType bodyTyped) binder rhsTyped bodyTyped)

inferPrim :: TypeEnv -> BinOp -> ResolvedAtom -> ResolvedAtom -> Either FragmentError TypedResolvedAExpr
inferPrim env op lhs rhs =
  case op of
    Add -> intPrim
    Mul -> intPrim
    Sub -> intPrim
    Div -> Left (UnsupportedPrimitive Div)
    Eq -> equalityPrim
    Lt -> intComparisonPrim
 where
  intPrim = do
    lhsTyped <- inferAtom env (Just TInt) lhs
    rhsTyped <- inferAtom env (Just TInt) rhs
    pure (TRPrim TInt op lhsTyped rhsTyped)

  intComparisonPrim = do
    lhsTyped <- inferAtom env (Just TInt) lhs
    rhsTyped <- inferAtom env (Just TInt) rhs
    pure (TRPrim TBool op lhsTyped rhsTyped)

  equalityPrim = do
    lhsKnown <- inferAtomKnownType env lhs
    rhsKnown <- inferAtomKnownType env rhs
    ty <-
      case (lhsKnown, rhsKnown) of
        (Just lhsTy, Just rhsTy) -> do
          assertType lhsTy rhsTy
          pure lhsTy
        (Just lhsTy, Nothing) ->
          pure lhsTy
        (Nothing, Just rhsTy) ->
          pure rhsTy
        (Nothing, Nothing) ->
          Left (AmbiguousFreeVariable (firstFreeVariable lhs rhs))
    case ty of
      TInt -> pure ()
      TBool -> pure ()
      TFun {} -> Left (UnsupportedType ty)
    lhsTyped <- inferAtom env (Just ty) lhs
    rhsTyped <- inferAtom env (Just ty) rhs
    pure (TRPrim TBool op lhsTyped rhsTyped)

inferAtomKnownType :: TypeEnv -> ResolvedAtom -> Either FragmentError (Maybe Type)
inferAtomKnownType env = \case
  RInt n ->
    case mkHIntLiteral n of
      Right _ -> Right (Just TInt)
      Left err -> Left (InvalidIntLiteral err)
  RBool {} ->
    Right (Just TBool)
  RVar (BoundVar binder) ->
    case Map.lookup (binderId binder) env of
      Just ty -> Right (Just ty)
      Nothing -> Left (UnboundResolvedBinder binder)
  RVar (FreeVar {}) ->
    Right Nothing

firstFreeVariable :: ResolvedAtom -> ResolvedAtom -> Name
firstFreeVariable lhs rhs =
  case (lhs, rhs) of
    (RVar (FreeVar name), _) -> name
    (_, RVar (FreeVar name)) -> name
    _ -> Name "<unknown>"

inferAtom :: TypeEnv -> Maybe Type -> ResolvedAtom -> Either FragmentError TypedResolvedAtom
inferAtom env expected atom =
  case atom of
    RInt n ->
      case mkHIntLiteral n of
        Right _ -> withExpected TInt
        Left err -> Left (InvalidIntLiteral err)
    RBool {} ->
      withExpected TBool
    RVar (BoundVar binder) ->
      case Map.lookup (binderId binder) env of
        Just ty -> withExpected ty
        Nothing -> Left (UnboundResolvedBinder binder)
    RVar (FreeVar name) ->
      case expected of
        Just ty
          | supportedType ty -> Right TypedResolvedAtom {typedAtomType = ty, typedAtomNode = atom}
          | otherwise -> Left (UnsupportedType ty)
        Nothing -> Left (AmbiguousFreeVariable name)
 where
  withExpected actual = do
    unlessSupported actual
    maybe (Right ()) (`assertType` actual) expected
    pure TypedResolvedAtom {typedAtomType = actual, typedAtomNode = atom}

unlessSupported :: Type -> Either FragmentError ()
unlessSupported ty
  | supportedType ty = Right ()
  | otherwise = Left (UnsupportedType ty)

supportedType :: Type -> Bool
supportedType = \case
  TInt -> True
  TBool -> True
  TFun {} -> False

assertType :: Type -> Type -> Either FragmentError ()
assertType expected actual
  | expected == actual = Right ()
  | otherwise = Left (TypeMismatch expected actual)

renderFragmentError :: FragmentError -> Text
renderFragmentError = \case
  UnsupportedLambda binder ->
    "unsupported lambda binder " <> renderBinderKey binder
  UnsupportedApplication fn arg ->
    "unsupported application: " <> Text.pack (show fn) <> " " <> Text.pack (show arg)
  UnsupportedDirectCall name ->
    "unsupported direct function call " <> renderDoc (prettyName name)
  UnsupportedPrimitive op ->
    "unsupported primitive " <> renderDoc (prettyBinOp op)
  UnsupportedType ty ->
    "unsupported type " <> renderDoc (prettyType ty)
  AmbiguousFreeVariable name ->
    "ambiguous free variable " <> renderDoc (prettyName name)
  UnboundResolvedBinder binder ->
    "unbound resolved binder " <> renderBinderKey binder
  TypeMismatch expected actual ->
    "type mismatch: expected " <> renderDoc (prettyType expected) <> ", got " <> renderDoc (prettyType actual)
  InvalidIntLiteral err ->
    renderIntError err
