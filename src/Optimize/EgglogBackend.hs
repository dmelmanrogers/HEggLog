module Optimize.EgglogBackend
  ( EgglogBackendError (..)
  , EgglogBackendResult (..)
  , optimizeANFWithEgglog
  , renderEgglogBackendError
  )
where

import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Database
import Egglog.Eval
import Egglog.Extract
import Egglog.Function
import Egglog.Pattern
import Egglog.Rule
import Egglog.Sort
import Egglog.Value
import IR.ANF
import Syntax.AST (BinOp (..), Name (..))

data EgglogBackendError
  = EgglogKernelError EgglogError
  | UnsupportedFeature Text
  | CannotConvertExtracted ExtractedTerm
  | MissingRootValue
  deriving stock (Show, Eq)

data EgglogBackendResult = EgglogBackendResult
  { egglogOptimizedANF :: AExpr
  , egglogIterations :: Int
  , egglogSaturated :: Bool
  }
  deriving stock (Show, Eq, Ord)

optimizeANFWithEgglog :: AExpr -> Either EgglogBackendError EgglogBackendResult
optimizeANFWithEgglog expression = do
  pattern <- anfToPattern Map.empty expression
  runResult <-
    mapLeft EgglogKernelError $
      runProgram
        defaultRunConfig {maxIterations = 16}
        Program
          { programDecls = arithmeticDecls
          , programInitialActions = [ASet rootFn [] pattern]
          , programRules = arithmeticRules
          }
  rootValue <-
    mapLeft EgglogKernelError $
      lookupFunction rootFn [] (resultDatabase runResult)
  case rootValue of
    Just (VId sortName ident) -> do
      extracted <- mapLeft EgglogKernelError (extractCheapest (resultDatabase runResult) sortName ident)
      optimized <- extractedToANF extracted
      pure
        EgglogBackendResult
          { egglogOptimizedANF = optimized
          , egglogIterations = resultIterations runResult
          , egglogSaturated = resultSaturated runResult
          }
    _ ->
      Left MissingRootValue

anfToPattern :: Map.Map Name Pattern -> AExpr -> Either EgglogBackendError Pattern
anfToPattern env = \case
  AAtom atom ->
    atomToPattern env atom
  APrim Add lhs rhs ->
    PCall addFn <$> traverse (atomToPattern env) [lhs, rhs]
  APrim Mul lhs rhs ->
    PCall mulFn <$> traverse (atomToPattern env) [lhs, rhs]
  APrim op _ _ ->
    Left (UnsupportedFeature ("egglog backend does not support primitive " <> Text.pack (show op)))
  AIf {} ->
    Left (UnsupportedFeature "egglog backend does not support if expressions yet")
  ALam {} ->
    Left (UnsupportedFeature "egglog backend does not support lambdas")
  AApp {} ->
    Left (UnsupportedFeature "egglog backend does not support applications")
  ALet name rhs body -> do
    rhsPattern <- anfToPattern env rhs
    anfToPattern (Map.insert name rhsPattern env) body

atomToPattern :: Map.Map Name Pattern -> Atom -> Either EgglogBackendError Pattern
atomToPattern env = \case
  AInt n ->
    Right (PCall numFn [PValue (VInt n)])
  ABool {} ->
    Left (UnsupportedFeature "egglog backend does not support Bool atoms")
  AVar name ->
    Right (Map.findWithDefault (PCall varFn [PValue (VString (unName name))]) name env)

extractedToANF :: ExtractedTerm -> Either EgglogBackendError AExpr
extractedToANF term =
  evalState (lowerExpr term) 0

lowerExpr :: ExtractedTerm -> State Int (Either EgglogBackendError AExpr)
lowerExpr term =
  case termToAtom term of
    Just atom ->
      pure (Right (AAtom atom))
    Nothing ->
      case term of
        ExtractCall name [lhs, rhs]
          | name == addFn -> lowerBinary Add lhs rhs
          | name == mulFn -> lowerBinary Mul lhs rhs
        _ ->
          pure (Left (CannotConvertExtracted term))

lowerBinary :: BinOp -> ExtractedTerm -> ExtractedTerm -> State Int (Either EgglogBackendError AExpr)
lowerBinary op lhs rhs = do
  lhsResult <- lowerAtom lhs
  rhsResult <- lowerAtom rhs
  case (lhsResult, rhsResult) of
    (Right (lhsAtom, wrapLhs), Right (rhsAtom, wrapRhs)) ->
      pure (Right (wrapLhs (wrapRhs (APrim op lhsAtom rhsAtom))))
    (Left err, _) -> pure (Left err)
    (_, Left err) -> pure (Left err)

lowerAtom :: ExtractedTerm -> State Int (Either EgglogBackendError (Atom, AExpr -> AExpr))
lowerAtom term =
  case termToAtom term of
    Just atom ->
      pure (Right (atom, id))
    Nothing -> do
      exprResult <- lowerExpr term
      case exprResult of
        Left err -> pure (Left err)
        Right expr -> do
          temp <- freshTemp
          pure (Right (AVar temp, ALet temp expr))

freshTemp :: State Int Name
freshTemp = do
  next <- get
  modify' (+ 1)
  pure (Name ("_egg" <> Text.pack (show next)))

termToAtom :: ExtractedTerm -> Maybe Atom
termToAtom = \case
  ExtractCall name [ExtractValue (VInt n)]
    | name == numFn -> Just (AInt n)
  ExtractCall name [ExtractValue (VString text)]
    | name == varFn -> Just (AVar (Name text))
  _ ->
    Nothing

arithmeticDecls :: [FunctionDecl]
arithmeticDecls =
  [ FunctionDecl numFn [SInt] exprSort DefaultFreshId MergeUnion
  , FunctionDecl varFn [SString] exprSort DefaultFreshId MergeUnion
  , FunctionDecl addFn [exprSort, exprSort] exprSort DefaultFreshId MergeUnion
  , FunctionDecl mulFn [exprSort, exprSort] exprSort DefaultFreshId MergeUnion
  , FunctionDecl rootFn [] exprSort DefaultNone MergeKeepOld
  ]

arithmeticRules :: [Rule]
arithmeticRules =
  [ rewrite (FunctionName "add-comm") exprSort (call addFn [a, b]) (call addFn [b, a])
  , rewrite (FunctionName "mul-comm") exprSort (call mulFn [a, b]) (call mulFn [b, a])
  , rewrite (FunctionName "add-zero-right") exprSort (call addFn [a, num 0]) a
  , rewrite (FunctionName "add-zero-left") exprSort (call addFn [num 0, a]) a
  , rewrite (FunctionName "mul-one-right") exprSort (call mulFn [a, num 1]) a
  , rewrite (FunctionName "mul-one-left") exprSort (call mulFn [num 1, a]) a
  , rewrite (FunctionName "mul-zero-right") exprSort (call mulFn [a, num 0]) (num 0)
  , rewrite (FunctionName "mul-zero-left") exprSort (call mulFn [num 0, a]) (num 0)
  , rewrite (FunctionName "distribute-right") exprSort (call mulFn [a, call addFn [b, c]]) (call addFn [call mulFn [a, b], call mulFn [a, c]])
  , constantFold (FunctionName "const-add") addFn PAddInt
  , constantFold (FunctionName "const-mul") mulFn PMulInt
  ]
 where
  a = PVar (VarName "a") exprSort
  b = PVar (VarName "b") exprSort
  c = PVar (VarName "c") exprSort
  call = PCall
  num n = PCall numFn [PValue (VInt n)]

constantFold :: FunctionName -> FunctionName -> (Pattern -> Pattern -> Pattern) -> Rule
constantFold ruleName' op makeInt =
  Rule
    { ruleName = ruleName'
    , rulePremises = [QMatch (PCall op [numA, numB]) out]
    , ruleActions = [AUnion out (PCall numFn [makeInt intA intB])]
    }
 where
  intA = PVar (VarName "i") SInt
  intB = PVar (VarName "j") SInt
  numA = PCall numFn [intA]
  numB = PCall numFn [intB]
  out = PVar (VarName "out") exprSort

exprSortName :: SortName
exprSortName =
  SortName "Expr"

exprSort :: Sort
exprSort =
  SUser exprSortName

numFn :: FunctionName
numFn =
  FunctionName "Num"

varFn :: FunctionName
varFn =
  FunctionName "Var"

addFn :: FunctionName
addFn =
  FunctionName "Add"

mulFn :: FunctionName
mulFn =
  FunctionName "Mul"

rootFn :: FunctionName
rootFn =
  FunctionName "__root"

renderEgglogBackendError :: EgglogBackendError -> Text
renderEgglogBackendError = \case
  EgglogKernelError err ->
    Text.pack (show err)
  UnsupportedFeature message ->
    message
  CannotConvertExtracted term ->
    "cannot convert extracted egglog term to ANF: " <> renderExtractedTerm term
  MissingRootValue ->
    "egglog backend did not produce a root value"

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left err -> Left (f err)
  Right value -> Right value
