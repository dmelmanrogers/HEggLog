module IR.ANF.Resolved
  ( Binder (..)
  , BinderId (..)
  , FreeVar
  , ResolveError (..)
  , ResolveValidationError (..)
  , ResolvedAExpr (..)
  , ResolvedAtom (..)
  , VarRef (..)
  , binderDependencyGraph
  , boundVariables
  , boundVarsResolved
  , freeVarsResolved
  , freeVariables
  , renderResolvedANF
  , renderBinderKey
  , resolveANF
  , validateUniqueBinders
  , validateResolvedANF
  )
where

import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import IR.ANF
import Syntax.AST
import Syntax.Pretty (prettyName, renderDoc)

newtype BinderId = BinderId {unBinderId :: Int}
  deriving stock (Show, Eq, Ord)

data Binder = Binder
  { binderId :: BinderId
  , binderName :: Name
  }
  deriving stock (Show, Eq, Ord)

data VarRef
  = BoundVar Binder
  | FreeVar Name
  deriving stock (Show, Eq, Ord)

type FreeVar = Name

data ResolvedAtom
  = RVar VarRef
  | RInt Integer
  | RBool Bool
  deriving stock (Show, Eq, Ord)

data ResolvedAExpr
  = RAtom ResolvedAtom
  | RPrim BinOp ResolvedAtom ResolvedAtom
  | RIf ResolvedAtom ResolvedAExpr ResolvedAExpr
  | RLam Binder Type ResolvedAExpr
  | RApp ResolvedAtom ResolvedAtom
  | RLet Binder ResolvedAExpr ResolvedAExpr
  deriving stock (Show, Eq, Ord)

data ResolveError
  = DuplicateBinderId BinderId
  | ResolveValidationFailed ResolveValidationError
  deriving stock (Show, Eq, Ord)

data ResolveValidationError
  = ResolvedDuplicateBinderId BinderId
  | ResolvedOutOfScopeBinder Binder
  | ResolvedBinderCollision Binder
  deriving stock (Show, Eq, Ord)

type ResolveEnv = Map.Map Name Binder

data ResolveState = ResolveState
  { nextBinderId :: Int
  }
  deriving stock (Show, Eq)

resolveANF :: AExpr -> Either ResolveError ResolvedAExpr
resolveANF expression =
  let resolved =
        evalState
          (resolveExpr Map.empty expression)
          ResolveState {nextBinderId = 0}
   in case validateResolvedANF resolved of
        Left err -> Left (ResolveValidationFailed err)
        Right () -> Right resolved

resolveExpr :: ResolveEnv -> AExpr -> State ResolveState ResolvedAExpr
resolveExpr env = \case
  AAtom atom ->
    RAtom <$> resolveAtom env atom
  APrim op lhs rhs ->
    RPrim op <$> resolveAtom env lhs <*> resolveAtom env rhs
  AIf cond thenBranch elseBranch ->
    RIf <$> resolveAtom env cond <*> resolveExpr env thenBranch <*> resolveExpr env elseBranch
  ALam name argType body -> do
    binder <- freshBinder name
    RLam binder argType <$> resolveExpr (Map.insert name binder env) body
  AApp fn arg ->
    RApp <$> resolveAtom env fn <*> resolveAtom env arg
  ALet name rhs body -> do
    rhsResolved <- resolveExpr env rhs
    binder <- freshBinder name
    bodyResolved <- resolveExpr (Map.insert name binder env) body
    pure (RLet binder rhsResolved bodyResolved)

resolveAtom :: ResolveEnv -> Atom -> State ResolveState ResolvedAtom
resolveAtom env = \case
  AVar name ->
    pure $
      RVar $
        case Map.lookup name env of
          Just binder -> BoundVar binder
          Nothing -> FreeVar name
  AInt n ->
    pure (RInt n)
  ABool b ->
    pure (RBool b)

freshBinder :: Name -> State ResolveState Binder
freshBinder name = do
  state <- get
  let ident = BinderId (nextBinderId state)
  modify' (\st -> st {nextBinderId = nextBinderId st + 1})
  pure Binder {binderId = ident, binderName = name}

freeVariables :: ResolvedAExpr -> Set.Set Name
freeVariables = \case
  RAtom atom ->
    freeAtom atom
  RPrim _ lhs rhs ->
    freeAtom lhs <> freeAtom rhs
  RIf cond thenBranch elseBranch ->
    freeAtom cond <> freeVariables thenBranch <> freeVariables elseBranch
  RLam _ _ body ->
    freeVariables body
  RApp fn arg ->
    freeAtom fn <> freeAtom arg
  RLet _ rhs body ->
    freeVariables rhs <> freeVariables body

freeAtom :: ResolvedAtom -> Set.Set Name
freeAtom = \case
  RVar (FreeVar name) -> Set.singleton name
  RVar (BoundVar _) -> Set.empty
  RInt _ -> Set.empty
  RBool _ -> Set.empty

freeVarsResolved :: ResolvedAExpr -> Set.Set FreeVar
freeVarsResolved =
  freeVariables

boundVariables :: ResolvedAExpr -> Map.Map BinderId Binder
boundVariables =
  go Map.empty
 where
  go acc = \case
    RAtom {} ->
      acc
    RPrim {} ->
      acc
    RIf _ thenBranch elseBranch ->
      go (go acc thenBranch) elseBranch
    RLam binder _ body ->
      go (Map.insert (binderId binder) binder acc) body
    RApp {} ->
      acc
    RLet binder rhs body ->
      go (go (Map.insert (binderId binder) binder acc) rhs) body

boundVarsResolved :: ResolvedAExpr -> Set.Set BinderId
boundVarsResolved =
  Map.keysSet . boundVariables

binderDependencyGraph :: ResolvedAExpr -> Map.Map BinderId (Set.Set BinderId)
binderDependencyGraph =
  go Map.empty
 where
  go graph = \case
    RAtom {} ->
      graph
    RPrim {} ->
      graph
    RIf _ thenBranch elseBranch ->
      go (go graph thenBranch) elseBranch
    RLam binder _ body ->
      Map.insert (binderId binder) (boundRefs body) (go graph body)
    RApp {} ->
      graph
    RLet binder rhs body ->
      go (Map.insert (binderId binder) (boundRefs rhs) (go graph rhs)) body

boundRefs :: ResolvedAExpr -> Set.Set BinderId
boundRefs = \case
  RAtom atom ->
    boundRefsAtom atom
  RPrim _ lhs rhs ->
    boundRefsAtom lhs <> boundRefsAtom rhs
  RIf cond thenBranch elseBranch ->
    boundRefsAtom cond <> boundRefs thenBranch <> boundRefs elseBranch
  RLam binder _ body ->
    Set.delete (binderId binder) (boundRefs body)
  RApp fn arg ->
    boundRefsAtom fn <> boundRefsAtom arg
  RLet _ rhs body ->
    boundRefs rhs <> boundRefs body

boundRefsAtom :: ResolvedAtom -> Set.Set BinderId
boundRefsAtom = \case
  RVar (BoundVar binder) -> Set.singleton (binderId binder)
  RVar (FreeVar _) -> Set.empty
  RInt _ -> Set.empty
  RBool _ -> Set.empty

validateUniqueBinders :: ResolvedAExpr -> Either ResolveError ()
validateUniqueBinders expression =
  go Set.empty expression *> Right ()
 where
  go seen = \case
    RAtom {} ->
      Right seen
    RPrim {} ->
      Right seen
    RIf _ thenBranch elseBranch ->
      go seen thenBranch >>= \seen' -> go seen' elseBranch
    RLam binder _ body ->
      insertBinder seen binder >>= \seen' -> go seen' body
    RApp {} ->
      Right seen
    RLet binder rhs body ->
      insertBinder seen binder >>= \seen' -> go seen' rhs >>= \seen'' -> go seen'' body

  insertBinder seen binder
    | binderId binder `Set.member` seen = Left (DuplicateBinderId (binderId binder))
    | otherwise = Right (Set.insert (binderId binder) seen)

validateResolvedANF :: ResolvedAExpr -> Either ResolveValidationError ()
validateResolvedANF expression =
  go Set.empty Set.empty expression *> Right ()
 where
  go :: Set.Set BinderId -> Set.Set BinderId -> ResolvedAExpr -> Either ResolveValidationError (Set.Set BinderId)
  go seen scope = \case
    RAtom atom ->
      validateAtom scope atom >> Right seen
    RPrim _ lhs rhs -> do
      validateAtom scope lhs
      validateAtom scope rhs
      Right seen
    RIf cond thenBranch elseBranch -> do
      validateAtom scope cond
      seen' <- go seen scope thenBranch
      go seen' scope elseBranch
    RLam binder _ body -> do
      seen' <- insertBinder seen binder
      go seen' (Set.insert (binderId binder) scope) body
    RApp fn arg -> do
      validateAtom scope fn
      validateAtom scope arg
      Right seen
    RLet binder rhs body -> do
      seenAfterRhs <- go seen scope rhs
      seen' <- insertBinder seenAfterRhs binder
      go seen' (Set.insert (binderId binder) scope) body

  validateAtom scope = \case
    RVar (BoundVar binder)
      | binderId binder `Set.member` scope -> Right ()
      | otherwise -> Left (ResolvedOutOfScopeBinder binder)
    RVar (FreeVar _) -> Right ()
    RInt _ -> Right ()
    RBool _ -> Right ()

  insertBinder seen binder
    | binderId binder `Set.member` seen = Left (ResolvedDuplicateBinderId (binderId binder))
    | otherwise = Right (Set.insert (binderId binder) seen)

renderBinderKey :: Binder -> Text
renderBinderKey binder =
  renderDoc (prettyName (binderName binder))
    <> "#"
    <> Text.pack (show (unBinderId (binderId binder)))

renderResolvedANF :: ResolvedAExpr -> Text
renderResolvedANF =
  renderExpr 0
 where
  renderExpr :: Int -> ResolvedAExpr -> Text
  renderExpr outerPrec = \case
    RAtom atom ->
      renderAtom atom
    RPrim op lhs rhs ->
      parenthesize (outerPrec > 0) $
        Text.unwords [renderAtom lhs, Text.pack (show op), renderAtom rhs]
    RIf cond thenBranch elseBranch ->
      parenthesize (outerPrec > 0) $
        Text.unwords
          [ "if"
          , renderAtom cond
          , "then"
          , renderExpr 0 thenBranch
          , "else"
          , renderExpr 0 elseBranch
          ]
    RLam binder _ body ->
      parenthesize (outerPrec > 0) $
        "\\" <> renderBinderKey binder <> " -> " <> renderExpr 0 body
    RApp fn arg ->
      Text.unwords [renderAtom fn, renderAtom arg]
    RLet binder rhs body ->
      parenthesize (outerPrec > 0) $
        "let "
          <> renderBinderKey binder
          <> " = "
          <> renderExpr 0 rhs
          <> " in\n"
          <> renderExpr 0 body

  renderAtom = \case
    RVar (BoundVar binder) -> renderBinderKey binder
    RVar (FreeVar name) -> renderDoc (prettyName name)
    RInt n -> Text.pack (show n)
    RBool True -> "true"
    RBool False -> "false"

  parenthesize shouldWrap text
    | shouldWrap = "(" <> text <> ")"
    | otherwise = text
