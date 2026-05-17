module IR.Core
  ( CoreBinOp (..)
  , CoreId (..)
  , CoreNode (..)
  , CoreProgram (..)
  , lower
  , renderCore
  )
where

import Control.Monad.State.Strict (State, get, modify', runState)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST
import Syntax.Pretty (prettyName, prettyType, renderDoc)

newtype CoreId = CoreId {unCoreId :: Int}
  deriving stock (Show, Eq, Ord)

data CoreBinOp
  = CAdd
  | CSub
  | CMul
  | CDiv
  | CEq
  | CLt
  deriving stock (Show, Eq, Ord)

data CoreNode
  = CInt Integer
  | CBool Bool
  | CVar Name
  | CLet Name CoreId CoreId
  | CIf CoreId CoreId CoreId
  | CBin CoreBinOp CoreId CoreId
  | CLam Name Type CoreId
  | CApp CoreId CoreId
  deriving stock (Show, Eq, Ord)

data CoreProgram = CoreProgram
  { coreRoot :: CoreId
  , coreNodes :: Map.Map CoreId CoreNode
  }
  deriving stock (Show, Eq)

-- TODO: Future EqSat integration should translate CoreNode values into egglog
-- relations, run rewrite rules in Optimize.*, and extract a replacement root.
-- Binder-aware rewrites need explicit treatment of alpha equivalence, beta
-- reduction, capture avoidance, and extraction cost models before lambdas can
-- safely participate in unrestricted equality saturation.

data LowerState = LowerState
  { nextId :: Int
  , nodes :: Map.Map CoreId CoreNode
  }

lower :: Expr -> CoreProgram
lower expression =
  let (root, finalState) = runLower (lowerExpr expression)
   in CoreProgram
        { coreRoot = root
        , coreNodes = nodes finalState
        }

lowerExpr :: Expr -> LowerM CoreId
lowerExpr = \case
  EInt n ->
    emit (CInt n)
  EBool b ->
    emit (CBool b)
  EVar name ->
    emit (CVar name)
  ELet name rhs body -> do
    rhsId <- lowerExpr rhs
    bodyId <- lowerExpr body
    emit (CLet name rhsId bodyId)
  EIf cond thenBranch elseBranch -> do
    condId <- lowerExpr cond
    thenId <- lowerExpr thenBranch
    elseId <- lowerExpr elseBranch
    emit (CIf condId thenId elseId)
  EBin op lhs rhs -> do
    lhsId <- lowerExpr lhs
    rhsId <- lowerExpr rhs
    let (normalizedLhs, normalizedRhs) = normalizeOperands op lhsId rhsId
    emit (CBin (lowerBinOp op) normalizedLhs normalizedRhs)
  ELam name argType body -> do
    bodyId <- lowerExpr body
    emit (CLam name argType bodyId)
  EApp fn arg -> do
    fnId <- lowerExpr fn
    argId <- lowerExpr arg
    emit (CApp fnId argId)

type LowerM = State LowerState

runLower :: LowerM a -> (a, LowerState)
runLower action =
  let initialState = LowerState {nextId = 0, nodes = Map.empty}
   in runStateStrict action initialState

runStateStrict :: State s a -> s -> (a, s)
runStateStrict action initial =
  runState action initial

emit :: CoreNode -> LowerM CoreId
emit node = do
  current <- get
  let ident = CoreId (nextId current)
  modify' $
    \st ->
      st
        { nextId = nextId st + 1
        , nodes = Map.insert ident node (nodes st)
        }
  pure ident

lowerBinOp :: BinOp -> CoreBinOp
lowerBinOp = \case
  Add -> CAdd
  Sub -> CSub
  Mul -> CMul
  Div -> CDiv
  Eq -> CEq
  Lt -> CLt

normalizeOperands :: BinOp -> CoreId -> CoreId -> (CoreId, CoreId)
normalizeOperands op lhs rhs
  | op `elem` [Add, Mul, Eq] && rhs < lhs = (rhs, lhs)
  | otherwise = (lhs, rhs)

renderCore :: CoreProgram -> Text
renderCore program =
  Text.unlines $
    ("root = " <> renderId (coreRoot program))
      : map renderBinding (Map.toAscList (coreNodes program))

renderBinding :: (CoreId, CoreNode) -> Text
renderBinding (ident, node) =
  renderId ident <> " = " <> renderNode node

renderNode :: CoreNode -> Text
renderNode = \case
  CInt n ->
    "int " <> Text.pack (show n)
  CBool True ->
    "bool true"
  CBool False ->
    "bool false"
  CVar name ->
    "var " <> renderDoc (prettyName name)
  CLet name rhs body ->
    "let " <> renderDoc (prettyName name) <> " " <> renderId rhs <> " " <> renderId body
  CIf cond thenBranch elseBranch ->
    "if " <> Text.unwords (map renderId [cond, thenBranch, elseBranch])
  CBin op lhs rhs ->
    Text.unwords [renderCoreBinOp op, renderId lhs, renderId rhs]
  CLam name argType body ->
    "lam " <> renderDoc (prettyName name) <> " : " <> renderDoc (prettyType argType) <> " " <> renderId body
  CApp fn arg ->
    "app " <> renderId fn <> " " <> renderId arg

renderCoreBinOp :: CoreBinOp -> Text
renderCoreBinOp = \case
  CAdd -> "add"
  CSub -> "sub"
  CMul -> "mul"
  CDiv -> "div"
  CEq -> "eq"
  CLt -> "lt"

renderId :: CoreId -> Text
renderId (CoreId ident) =
  "%" <> Text.pack (show ident)
