module IR.ANF
  ( AFun (..)
  , AProgram (..)
  , AExpr (..)
  , Atom (..)
  , renderANF
  , renderANFProgram
  , toANF
  , toANFProgram
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
  | ACall Name [Atom]
  | ALet Name AExpr AExpr
  deriving stock (Show, Eq, Ord)

data AFun = AFun Name [Param] Type AExpr
  deriving stock (Show, Eq, Ord)

data AProgram = AProgram [AFun] AExpr
  deriving stock (Show, Eq, Ord)

data LowerState = LowerState
  { nextTemp :: Int
  , usedNames :: Set.Set Name
  }

-- ANF makes evaluation order explicit: primitive and application operands are
-- atoms, and complex computations are sequenced through let-bound names.
toANF :: Expr -> AExpr
toANF expression =
  evalState (lowerExpr Set.empty Set.empty expression) initialState
 where
  initialState =
    LowerState
      { nextTemp = 0
      , usedNames = collectNames expression
      }

toANFProgram :: Program -> AProgram
toANFProgram program =
  evalState lowerProgram initialState
 where
  topNames =
    Set.fromList (map topDefName (programDefs program))
  initialState =
    LowerState
      { nextTemp = 0
      , usedNames = collectProgramNames program
      }
  lowerProgram = do
    defs <- traverse (lowerTopDef topNames) (programDefs program)
    mainExpr <- lowerExpr topNames Set.empty (programMain program)
    pure (AProgram defs mainExpr)

lowerTopDef :: Set.Set Name -> TopDef -> LowerM AFun
lowerTopDef topNames def = do
  body <- lowerExpr topNames (Set.fromList (map paramName (topDefParams def))) (topDefBody def)
  pure (AFun (topDefName def) (topDefParams def) (topDefReturnType def) body)

lowerExpr :: Set.Set Name -> Set.Set Name -> Expr -> LowerM AExpr
lowerExpr topNames localNames = \case
  EInt n ->
    pure (AAtom (AInt n))
  EBool b ->
    pure (AAtom (ABool b))
  EVar name ->
    pure (AAtom (AVar name))
  ELet name rhs body -> do
    rhsANF <- lowerExpr topNames localNames rhs
    bodyANF <- lowerExpr topNames (Set.insert name localNames) body
    pure (ALet name rhsANF bodyANF)
  EIf cond thenBranch elseBranch ->
    lowerAtom topNames localNames cond $ \condAtom -> do
      thenANF <- lowerExpr topNames localNames thenBranch
      elseANF <- lowerExpr topNames localNames elseBranch
      pure (AIf condAtom thenANF elseANF)
  EBin op lhs rhs ->
    lowerAtom topNames localNames lhs $ \lhsAtom ->
      lowerAtom topNames localNames rhs $ \rhsAtom ->
        pure (APrim op lhsAtom rhsAtom)
  ELam name argType body ->
    ALam name argType <$> lowerExpr topNames (Set.insert name localNames) body
  expression@(EApp fn arg) ->
    case directTopCall topNames localNames expression of
      Just (callee, args) ->
        lowerCallArgs topNames localNames args [] $ \argAtoms ->
          pure (ACall callee argAtoms)
      Nothing ->
        lowerAtom topNames localNames fn $ \fnAtom ->
          lowerAtom topNames localNames arg $ \argAtom ->
            pure (AApp fnAtom argAtom)

lowerCallArgs :: Set.Set Name -> Set.Set Name -> [Expr] -> [Atom] -> ([Atom] -> LowerM AExpr) -> LowerM AExpr
lowerCallArgs _ _ [] args continuation =
  continuation (reverse args)
lowerCallArgs topNames localNames (arg : rest) args continuation =
  lowerAtom topNames localNames arg $ \argAtom ->
    lowerCallArgs topNames localNames rest (argAtom : args) continuation

directTopCall :: Set.Set Name -> Set.Set Name -> Expr -> Maybe (Name, [Expr])
directTopCall topNames localNames expression =
  case unwind [] expression of
    (EVar name, args)
      | name `Set.member` topNames && name `Set.notMember` localNames && not (null args) ->
          Just (name, args)
    _ ->
      Nothing
 where
  unwind args = \case
    EApp fn arg -> unwind (arg : args) fn
    headExpr -> (headExpr, args)

lowerAtom :: Set.Set Name -> Set.Set Name -> Expr -> (Atom -> LowerM AExpr) -> LowerM AExpr
lowerAtom topNames localNames expression continuation =
  case directAtom expression of
    Just atom ->
      continuation atom
    Nothing -> do
      lowered <- lowerExpr topNames localNames expression
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

collectProgramNames :: Program -> Set.Set Name
collectProgramNames program =
  Set.fromList (map topDefName (programDefs program))
    <> foldMap collectTopDefNames (programDefs program)
    <> collectNames (programMain program)

collectTopDefNames :: TopDef -> Set.Set Name
collectTopDefNames def =
  Set.fromList (map paramName (topDefParams def)) <> collectNames (topDefBody def)

renderANF :: AExpr -> Text
renderANF =
  renderAExpr 0

renderANFProgram :: AProgram -> Text
renderANFProgram (AProgram defs mainExpr) =
  Text.intercalate "\n" (map renderAFun defs <> [renderAExpr 0 mainExpr])

renderAFun :: AFun -> Text
renderAFun (AFun name params returnType body) =
  "def "
    <> renderDoc (prettyName name)
    <> "("
    <> Text.intercalate ", " [renderDoc (prettyName (paramName param)) <> " : " <> renderDoc (prettyType (paramType param)) | param <- params]
    <> ") : "
    <> renderDoc (prettyType returnType)
    <> " = "
    <> renderAExpr 0 body
    <> ";"

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
  ACall callee args ->
    Text.unwords (renderDoc (prettyName callee) : map renderAtom args)
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
