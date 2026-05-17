module IR.ANF
  ( AExpr (..)
  , Atom (..)
  , renderANF
  , toANF
  )
where

import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

data Atom
  = AVar Name
  | AInt Integer
  | ABool Bool
  deriving stock (Show, Eq, Ord)

data AExpr
  = AAtom Atom
  | APrim BinOp Atom Atom
  | AIf Atom AExpr AExpr
  | ALam Name Type AExpr
  | AApp Atom Atom
  | ALet Name AExpr AExpr
  deriving stock (Show, Eq, Ord)

data LowerState = LowerState
  { nextTemp :: Int
  , usedNames :: Set.Set Name
  }

-- ANF makes evaluation order explicit: primitive and application operands are
-- atoms, and complex computations are sequenced through let-bound names.
toANF :: Expr -> AExpr
toANF expression =
  evalState (lowerExpr expression) initialState
 where
  initialState =
    LowerState
      { nextTemp = 0
      , usedNames = collectNames expression
      }

lowerExpr :: Expr -> LowerM AExpr
lowerExpr = \case
  EInt n ->
    pure (AAtom (AInt n))
  EBool b ->
    pure (AAtom (ABool b))
  EVar name ->
    pure (AAtom (AVar name))
  ELet name rhs body -> do
    rhsANF <- lowerExpr rhs
    bodyANF <- lowerExpr body
    pure (ALet name rhsANF bodyANF)
  EIf cond thenBranch elseBranch ->
    lowerAtom cond $ \condAtom -> do
      thenANF <- lowerExpr thenBranch
      elseANF <- lowerExpr elseBranch
      pure (AIf condAtom thenANF elseANF)
  EBin op lhs rhs ->
    lowerAtom lhs $ \lhsAtom ->
      lowerAtom rhs $ \rhsAtom ->
        pure (APrim op lhsAtom rhsAtom)
  ELam name argType body ->
    ALam name argType <$> lowerExpr body
  EApp fn arg ->
    lowerAtom fn $ \fnAtom ->
      lowerAtom arg $ \argAtom ->
        pure (AApp fnAtom argAtom)

lowerAtom :: Expr -> (Atom -> LowerM AExpr) -> LowerM AExpr
lowerAtom expression continuation =
  case directAtom expression of
    Just atom ->
      continuation atom
    Nothing -> do
      lowered <- lowerExpr expression
      temp <- freshTemp
      ALet temp lowered <$> continuation (AVar temp)

directAtom :: Expr -> Maybe Atom
directAtom = \case
  EInt n -> Just (AInt n)
  EBool b -> Just (ABool b)
  EVar name -> Just (AVar name)
  ELet {} -> Nothing
  EIf {} -> Nothing
  EBin {} -> Nothing
  ELam {} -> Nothing
  EApp {} -> Nothing

type LowerM = State LowerState

freshTemp :: LowerM Name
freshTemp = do
  state <- get
  let candidate = Name ("_t" <> Text.pack (show (nextTemp state)))
  modify' (\st -> st {nextTemp = nextTemp st + 1})
  if candidate `Set.member` usedNames state
    then freshTemp
    else do
      modify' (\st -> st {usedNames = Set.insert candidate (usedNames st)})
      pure candidate

collectNames :: Expr -> Set.Set Name
collectNames = \case
  EInt _ ->
    Set.empty
  EBool _ ->
    Set.empty
  EVar name ->
    Set.singleton name
  ELet name rhs body ->
    Set.insert name (collectNames rhs <> collectNames body)
  EIf cond thenBranch elseBranch ->
    collectNames cond <> collectNames thenBranch <> collectNames elseBranch
  EBin _ lhs rhs ->
    collectNames lhs <> collectNames rhs
  ELam name _ body ->
    Set.insert name (collectNames body)
  EApp fn arg ->
    collectNames fn <> collectNames arg

renderANF :: AExpr -> Text
renderANF =
  renderAExpr 0

renderAExpr :: Int -> AExpr -> Text
renderAExpr outerPrec = \case
  AAtom atom ->
    renderAtom atom
  APrim op lhs rhs ->
    parenthesize (outerPrec > binPrec op) $
      Text.unwords [renderAtom lhs, renderDoc (prettyBinOp op), renderAtom rhs]
  AIf cond thenBranch elseBranch ->
    parenthesize (outerPrec > 0) $
      Text.unwords
        [ "if"
        , renderAtom cond
        , "then"
        , renderAExpr 0 thenBranch
        , "else"
        , renderAExpr 0 elseBranch
        ]
  ALam name argType body ->
    parenthesize (outerPrec > 0) $
      "\\"
        <> renderDoc (prettyName name)
        <> " : "
        <> renderDoc (prettyType argType)
        <> " -> "
        <> renderAExpr 0 body
  AApp fn arg ->
    Text.unwords [renderAtom fn, renderAtom arg]
  ALet name rhs body ->
    parenthesize (outerPrec > 0) $
      "let "
        <> renderDoc (prettyName name)
        <> " = "
        <> renderAExpr 0 rhs
        <> " in\n"
        <> renderAExpr 0 body

renderAtom :: Atom -> Text
renderAtom = \case
  AVar name -> renderDoc (prettyName name)
  AInt n -> Text.pack (show n)
  ABool True -> "true"
  ABool False -> "false"

binPrec :: BinOp -> Int
binPrec = \case
  Eq -> 3
  Lt -> 4
  Add -> 5
  Sub -> 5
  Mul -> 6
  Div -> 6

parenthesize :: Bool -> Text -> Text
parenthesize shouldWrap text
  | shouldWrap = "(" <> text <> ")"
  | otherwise = text
