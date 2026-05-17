module Egglog.Pattern
  ( Pattern (..)
  , Substitution
  , bindVar
  , emptySubstitution
  , evalExistingPattern
  , evalTerm
  , matchPatternValue
  )
where

import qualified Data.Map.Strict as Map
import Egglog.Database
import Egglog.Sort
import Egglog.Value

data Pattern
  = PVar VarName Sort
  | PValue Value
  | PCall FunctionName [Pattern]
  | PAddInt Pattern Pattern
  | PMulInt Pattern Pattern
  | PKnownInt Pattern
  | PKnownBool Pattern
  deriving stock (Show, Eq, Ord)

type Substitution = Map.Map VarName Value

emptySubstitution :: Substitution
emptySubstitution =
  Map.empty

bindVar :: VarName -> Sort -> Value -> Database -> Substitution -> Either EgglogError Substitution
bindVar name expectedSort value db subst = do
  let canonical = canonicalValue db value
  if valueSort canonical /= expectedSort
    then Left (PatternSortMismatch name expectedSort canonical)
    else case Map.lookup name subst of
      Nothing ->
        Right (Map.insert name canonical subst)
      Just existing ->
        if canonicalValue db existing == canonical
          then Right subst
          else Left (PatternSortMismatch name expectedSort canonical)

matchPatternValue :: Database -> Pattern -> Value -> Substitution -> Either EgglogError Substitution
matchPatternValue db pattern value subst =
  case pattern of
    PVar name sort ->
      bindVar name sort value db subst
    PValue expected ->
      if canonicalValue db expected == canonicalValue db value
        then Right subst
        else Left (QueryTypeError "literal pattern did not match value")
    PCall {} ->
      case evalExistingPattern db subst pattern of
        Right (Just existing)
          | canonicalValue db existing == canonicalValue db value -> Right subst
        Right _ -> Left (QueryTypeError "function pattern did not match value")
        Left err -> Left err
    PAddInt {} ->
      matchComputed
    PMulInt {} ->
      matchComputed
    PKnownInt inner ->
      case canonicalValue db value of
        VConstInt (KnownInt n) -> matchPatternValue db inner (VInt n) subst
        _ -> Left (QueryTypeError "KnownInt pattern did not match value")
    PKnownBool inner ->
      case canonicalValue db value of
        VConstBool (KnownBool b) -> matchPatternValue db inner (VBool b) subst
        _ -> Left (QueryTypeError "KnownBool pattern did not match value")
 where
  matchComputed =
    case evalExistingPattern db subst pattern of
      Right (Just existing)
        | existing == canonicalValue db value -> Right subst
      Right _ -> Left (QueryTypeError "computed pattern did not match value")
      Left err -> Left err

evalExistingPattern :: Database -> Substitution -> Pattern -> Either EgglogError (Maybe Value)
evalExistingPattern db subst = \case
  PVar name _ ->
    pure (Map.lookup name subst)
  PValue value ->
    pure (Just (canonicalValue db value))
  PCall name args -> do
    maybeArgs <- mapM (evalExistingPattern db subst) args
    case sequence maybeArgs of
      Nothing -> pure Nothing
      Just values -> lookupFunction name values db
  PAddInt lhs rhs -> do
    lhsValue <- evalExistingPattern db subst lhs
    rhsValue <- evalExistingPattern db subst rhs
    case (lhsValue, rhsValue) of
      (Just (VInt a), Just (VInt b)) -> pure (Just (VInt (a + b)))
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for addition")
      _ -> pure Nothing
  PMulInt lhs rhs -> do
    lhsValue <- evalExistingPattern db subst lhs
    rhsValue <- evalExistingPattern db subst rhs
    case (lhsValue, rhsValue) of
      (Just (VInt a), Just (VInt b)) -> pure (Just (VInt (a * b)))
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for multiplication")
      _ -> pure Nothing
  PKnownInt inner -> do
    innerValue <- evalExistingPattern db subst inner
    case innerValue of
      Just (VInt n) -> pure (Just (VConstInt (KnownInt n)))
      Just _ -> Left (QueryTypeError "expected Int operand for KnownInt")
      Nothing -> pure Nothing
  PKnownBool inner -> do
    innerValue <- evalExistingPattern db subst inner
    case innerValue of
      Just (VBool b) -> pure (Just (VConstBool (KnownBool b)))
      Just _ -> Left (QueryTypeError "expected Bool operand for KnownBool")
      Nothing -> pure Nothing

evalTerm :: Database -> Substitution -> Pattern -> Either EgglogError (Database, Value)
evalTerm db subst = \case
  PVar name _ ->
    case Map.lookup name subst of
      Just value -> Right (db, canonicalValue db value)
      Nothing -> Left (UnboundVariable name)
  PValue value ->
    Right (db, canonicalValue db value)
  PCall name args -> do
    (dbWithArgs, values) <- evalTerms db subst args
    (dbResult, value, _) <- callFunction name values dbWithArgs
    Right (dbResult, value)
  PAddInt lhs rhs -> do
    (db1, lhsValue) <- evalTerm db subst lhs
    (db2, rhsValue) <- evalTerm db1 subst rhs
    case (lhsValue, rhsValue) of
      (VInt a, VInt b) -> Right (db2, VInt (a + b))
      _ -> Left (QueryTypeError "expected Int operands for addition")
  PMulInt lhs rhs -> do
    (db1, lhsValue) <- evalTerm db subst lhs
    (db2, rhsValue) <- evalTerm db1 subst rhs
    case (lhsValue, rhsValue) of
      (VInt a, VInt b) -> Right (db2, VInt (a * b))
      _ -> Left (QueryTypeError "expected Int operands for multiplication")
  PKnownInt inner -> do
    (db1, value) <- evalTerm db subst inner
    case value of
      VInt n -> Right (db1, VConstInt (KnownInt n))
      _ -> Left (QueryTypeError "expected Int operand for KnownInt")
  PKnownBool inner -> do
    (db1, value) <- evalTerm db subst inner
    case value of
      VBool b -> Right (db1, VConstBool (KnownBool b))
      _ -> Left (QueryTypeError "expected Bool operand for KnownBool")

evalTerms :: Database -> Substitution -> [Pattern] -> Either EgglogError (Database, [Value])
evalTerms db subst = \case
  [] ->
    Right (db, [])
  pattern : rest -> do
    (db1, value) <- evalTerm db subst pattern
    (db2, values) <- evalTerms db1 subst rest
    Right (db2, value : values)
