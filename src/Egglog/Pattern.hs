module Egglog.Pattern
  ( Pattern (..)
  , Substitution
  , bindVar
  , emptySubstitution
  , evalExistingPattern
  , evalTerm
  , matchPatternValue
  , renderPattern
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Egglog.Database
import Egglog.Sort
import Egglog.Value
import Runtime.Int (HInt, addHInt, divHInt, hintToInteger, mkHIntLiteral, mulHInt, subHInt)

data Pattern
  = PVar VarName Sort
  | PValue Value
  | PCall FunctionName [Pattern]
  | PAddInt Pattern Pattern
  | PSubInt Pattern Pattern
  | PMulInt Pattern Pattern
  | PDivInt Pattern Pattern
  | PIntLt Pattern Pattern
  | PIntEq Pattern Pattern
  | PBoolEq Pattern Pattern
  | PKnownInt Pattern
  | PKnownBool Pattern
  | PZeroInfo Pattern
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
    PSubInt {} ->
      matchComputed
    PMulInt {} ->
      matchComputed
    PDivInt {} ->
      matchComputed
    PIntLt {} ->
      matchComputed
    PIntEq {} ->
      matchComputed
    PBoolEq {} ->
      matchComputed
    PKnownInt inner ->
      case canonicalValue db value of
        VConstInt (KnownInt n) -> matchPatternValue db inner (VInt (hintToInteger n)) subst
        _ -> Left (QueryTypeError "KnownInt pattern did not match value")
    PKnownBool inner ->
      case canonicalValue db value of
        VConstBool (KnownBool b) -> matchPatternValue db inner (VBool b) subst
        _ -> Left (QueryTypeError "KnownBool pattern did not match value")
    PZeroInfo inner ->
      case canonicalValue db value of
        VZeroInfo info -> matchZeroInfo inner info
        _ -> Left (QueryTypeError "ZeroInfo pattern did not match value")
 where
  matchComputed =
    case evalExistingPattern db subst pattern of
      Right (Just existing)
        | existing == canonicalValue db value -> Right subst
      Right _ -> Left (QueryTypeError "computed pattern did not match value")
      Left err -> Left err

  matchZeroInfo inner info =
    case evalExistingPattern db subst inner of
      Right (Just (VInt n))
        | zeroInfoFromInteger n == info -> Right subst
        | otherwise -> Left (QueryTypeError "ZeroInfo pattern did not match value")
      Right (Just _) -> Left (QueryTypeError "expected Int operand for ZeroInfo")
      Right Nothing -> Left (QueryTypeError "ZeroInfo pattern could not be computed")
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
      (Just (VInt a), Just (VInt b)) -> pure (VInt <$> checkedInteger addHInt a b)
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for addition")
      _ -> pure Nothing
  PSubInt lhs rhs -> do
    lhsValue <- evalExistingPattern db subst lhs
    rhsValue <- evalExistingPattern db subst rhs
    case (lhsValue, rhsValue) of
      (Just (VInt a), Just (VInt b)) -> pure (VInt <$> checkedInteger subHInt a b)
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for subtraction")
      _ -> pure Nothing
  PMulInt lhs rhs -> do
    lhsValue <- evalExistingPattern db subst lhs
    rhsValue <- evalExistingPattern db subst rhs
    case (lhsValue, rhsValue) of
      (Just (VInt a), Just (VInt b)) -> pure (VInt <$> checkedInteger mulHInt a b)
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for multiplication")
      _ -> pure Nothing
  PDivInt lhs rhs -> do
    lhsValue <- evalExistingPattern db subst lhs
    rhsValue <- evalExistingPattern db subst rhs
    case (lhsValue, rhsValue) of
      (Just (VInt a), Just (VInt b)) -> pure (VInt <$> checkedDivInteger a b)
      (Just _, Just _) -> Left (QueryTypeError "expected Int operands for division")
      _ -> pure Nothing
  PIntLt lhs rhs ->
    evalExistingIntComparison db subst (<) lhs rhs
  PIntEq lhs rhs ->
    evalExistingIntComparison db subst (==) lhs rhs
  PBoolEq lhs rhs ->
    evalExistingBoolComparison db subst (==) lhs rhs
  PKnownInt inner -> do
    maybeKnown <- evalExistingKnownInt db subst inner
    pure (VConstInt . KnownInt <$> maybeKnown)
  PKnownBool inner -> do
    innerValue <- evalExistingPattern db subst inner
    case innerValue of
      Just (VBool b) -> pure (Just (VConstBool (KnownBool b)))
      Just _ -> Left (QueryTypeError "expected Bool operand for KnownBool")
      Nothing -> pure Nothing
  PZeroInfo inner -> do
    innerValue <- evalExistingPattern db subst inner
    case innerValue of
      Just (VInt n) -> pure (Just (VZeroInfo (zeroInfoFromInteger n)))
      Just _ -> Left (QueryTypeError "expected Int operand for ZeroInfo")
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
      (VInt a, VInt b) ->
        case checkedInteger addHInt a b of
          Just result -> Right (db2, VInt result)
          Nothing -> Left (QueryTypeError "Int addition overflow")
      _ -> Left (QueryTypeError "expected Int operands for addition")
  PSubInt lhs rhs -> do
    (db1, lhsValue) <- evalTerm db subst lhs
    (db2, rhsValue) <- evalTerm db1 subst rhs
    case (lhsValue, rhsValue) of
      (VInt a, VInt b) ->
        case checkedInteger subHInt a b of
          Just result -> Right (db2, VInt result)
          Nothing -> Left (QueryTypeError "Int subtraction overflow")
      _ -> Left (QueryTypeError "expected Int operands for subtraction")
  PMulInt lhs rhs -> do
    (db1, lhsValue) <- evalTerm db subst lhs
    (db2, rhsValue) <- evalTerm db1 subst rhs
    case (lhsValue, rhsValue) of
      (VInt a, VInt b) ->
        case checkedInteger mulHInt a b of
          Just result -> Right (db2, VInt result)
          Nothing -> Left (QueryTypeError "Int multiplication overflow")
      _ -> Left (QueryTypeError "expected Int operands for multiplication")
  PDivInt lhs rhs -> do
    (db1, lhsValue) <- evalTerm db subst lhs
    (db2, rhsValue) <- evalTerm db1 subst rhs
    case (lhsValue, rhsValue) of
      (VInt a, VInt b) ->
        case checkedDivInteger a b of
          Just result -> Right (db2, VInt result)
          Nothing -> Left (QueryTypeError "Int division failed")
      _ -> Left (QueryTypeError "expected Int operands for division")
  PIntLt lhs rhs ->
    evalTermIntComparison db subst (<) lhs rhs
  PIntEq lhs rhs ->
    evalTermIntComparison db subst (==) lhs rhs
  PBoolEq lhs rhs ->
    evalTermBoolComparison db subst (==) lhs rhs
  PKnownInt inner -> do
    (db1, maybeKnown) <- evalTermKnownInt db subst inner
    Right (db1, VConstInt (maybe UnknownInt KnownInt maybeKnown))
  PKnownBool inner -> do
    (db1, value) <- evalTerm db subst inner
    case value of
      VBool b -> Right (db1, VConstBool (KnownBool b))
      _ -> Left (QueryTypeError "expected Bool operand for KnownBool")
  PZeroInfo inner -> do
    (db1, value) <- evalTerm db subst inner
    case value of
      VInt n -> Right (db1, VZeroInfo (zeroInfoFromInteger n))
      _ -> Left (QueryTypeError "expected Int operand for ZeroInfo")

evalTerms :: Database -> Substitution -> [Pattern] -> Either EgglogError (Database, [Value])
evalTerms db subst = \case
  [] ->
    Right (db, [])
  pattern : rest -> do
    (db1, value) <- evalTerm db subst pattern
    (db2, values) <- evalTerms db1 subst rest
    Right (db2, value : values)

evalExistingIntComparison :: Database -> Substitution -> (Integer -> Integer -> Bool) -> Pattern -> Pattern -> Either EgglogError (Maybe Value)
evalExistingIntComparison db subst op lhs rhs = do
  lhsValue <- evalExistingPattern db subst lhs
  rhsValue <- evalExistingPattern db subst rhs
  case (lhsValue, rhsValue) of
    (Just (VInt a), Just (VInt b)) -> pure (Just (VBool (op a b)))
    (Just _, Just _) -> Left (QueryTypeError "expected Int operands for comparison")
    _ -> pure Nothing

evalExistingBoolComparison :: Database -> Substitution -> (Bool -> Bool -> Bool) -> Pattern -> Pattern -> Either EgglogError (Maybe Value)
evalExistingBoolComparison db subst op lhs rhs = do
  lhsValue <- evalExistingPattern db subst lhs
  rhsValue <- evalExistingPattern db subst rhs
  case (lhsValue, rhsValue) of
    (Just (VBool a), Just (VBool b)) -> pure (Just (VBool (op a b)))
    (Just _, Just _) -> Left (QueryTypeError "expected Bool operands for comparison")
    _ -> pure Nothing

evalTermIntComparison :: Database -> Substitution -> (Integer -> Integer -> Bool) -> Pattern -> Pattern -> Either EgglogError (Database, Value)
evalTermIntComparison db subst op lhs rhs = do
  (db1, lhsValue) <- evalTerm db subst lhs
  (db2, rhsValue) <- evalTerm db1 subst rhs
  case (lhsValue, rhsValue) of
    (VInt a, VInt b) -> Right (db2, VBool (op a b))
    _ -> Left (QueryTypeError "expected Int operands for comparison")

evalTermBoolComparison :: Database -> Substitution -> (Bool -> Bool -> Bool) -> Pattern -> Pattern -> Either EgglogError (Database, Value)
evalTermBoolComparison db subst op lhs rhs = do
  (db1, lhsValue) <- evalTerm db subst lhs
  (db2, rhsValue) <- evalTerm db1 subst rhs
  case (lhsValue, rhsValue) of
    (VBool a, VBool b) -> Right (db2, VBool (op a b))
    _ -> Left (QueryTypeError "expected Bool operands for comparison")

evalExistingKnownInt :: Database -> Substitution -> Pattern -> Either EgglogError (Maybe HInt)
evalExistingKnownInt db subst = \case
  PAddInt lhs rhs ->
    evalExistingCheckedKnownInt db subst addHInt lhs rhs
  PSubInt lhs rhs ->
    evalExistingCheckedKnownInt db subst subHInt lhs rhs
  PMulInt lhs rhs ->
    evalExistingCheckedKnownInt db subst mulHInt lhs rhs
  PDivInt lhs rhs ->
    evalExistingCheckedKnownInt db subst checkedDivHInt lhs rhs
  pattern -> do
    innerValue <- evalExistingPattern db subst pattern
    case innerValue of
      Just (VInt n) -> pure (either (const Nothing) Just (mkHIntLiteral n))
      Just _ -> Left (QueryTypeError "expected Int operand for KnownInt")
      Nothing -> pure Nothing

evalExistingCheckedKnownInt ::
  Database ->
  Substitution ->
  (HInt -> HInt -> Either err HInt) ->
  Pattern ->
  Pattern ->
  Either EgglogError (Maybe HInt)
evalExistingCheckedKnownInt db subst op lhs rhs = do
  lhsValue <- evalExistingKnownInt db subst lhs
  rhsValue <- evalExistingKnownInt db subst rhs
  case (lhsValue, rhsValue) of
    (Just a, Just b) -> pure (either (const Nothing) Just (op a b))
    _ -> pure Nothing

evalTermKnownInt :: Database -> Substitution -> Pattern -> Either EgglogError (Database, Maybe HInt)
evalTermKnownInt db subst = \case
  PAddInt lhs rhs ->
    evalTermCheckedKnownInt db subst addHInt lhs rhs
  PSubInt lhs rhs ->
    evalTermCheckedKnownInt db subst subHInt lhs rhs
  PMulInt lhs rhs ->
    evalTermCheckedKnownInt db subst mulHInt lhs rhs
  PDivInt lhs rhs ->
    evalTermCheckedKnownInt db subst checkedDivHInt lhs rhs
  pattern -> do
    (db1, value) <- evalTerm db subst pattern
    case value of
      VInt n -> Right (db1, either (const Nothing) Just (mkHIntLiteral n))
      _ -> Left (QueryTypeError "expected Int operand for KnownInt")

evalTermCheckedKnownInt ::
  Database ->
  Substitution ->
  (HInt -> HInt -> Either err HInt) ->
  Pattern ->
  Pattern ->
  Either EgglogError (Database, Maybe HInt)
evalTermCheckedKnownInt db subst op lhs rhs = do
  (db1, lhsValue) <- evalTermKnownInt db subst lhs
  (db2, rhsValue) <- evalTermKnownInt db1 subst rhs
  case (lhsValue, rhsValue) of
    (Just a, Just b) -> Right (db2, either (const Nothing) Just (op a b))
    _ -> Right (db2, Nothing)

checkedInteger :: (HInt -> HInt -> Either err HInt) -> Integer -> Integer -> Maybe Integer
checkedInteger op lhs rhs = do
  lhsInt <- either (const Nothing) Just (mkHIntLiteral lhs)
  rhsInt <- either (const Nothing) Just (mkHIntLiteral rhs)
  result <- either (const Nothing) Just (op lhsInt rhsInt)
  pure (hintToInteger result)

checkedDivInteger :: Integer -> Integer -> Maybe Integer
checkedDivInteger lhs rhs = do
  lhsInt <- either (const Nothing) Just (mkHIntLiteral lhs)
  rhsInt <- either (const Nothing) Just (mkHIntLiteral rhs)
  result <- either (const Nothing) Just (checkedDivHInt lhsInt rhsInt)
  pure (hintToInteger result)

checkedDivHInt :: HInt -> HInt -> Either () HInt
checkedDivHInt lhs rhs
  | hintToInteger rhs == 0 = Left ()
  | otherwise = either (const (Left ())) Right (divHInt lhs rhs)

renderPattern :: Pattern -> Text
renderPattern = \case
  PVar name sort ->
    "?" <> renderVarName name <> ":" <> renderSort sort
  PValue value ->
    renderValue value
  PCall name args ->
    renderFunctionName name <> renderArgs args
  PAddInt lhs rhs ->
    "(" <> renderPattern lhs <> " + " <> renderPattern rhs <> ")"
  PSubInt lhs rhs ->
    "(" <> renderPattern lhs <> " - " <> renderPattern rhs <> ")"
  PMulInt lhs rhs ->
    "(" <> renderPattern lhs <> " * " <> renderPattern rhs <> ")"
  PDivInt lhs rhs ->
    "(" <> renderPattern lhs <> " / " <> renderPattern rhs <> ")"
  PIntLt lhs rhs ->
    "(" <> renderPattern lhs <> " < " <> renderPattern rhs <> ")"
  PIntEq lhs rhs ->
    "(" <> renderPattern lhs <> " == " <> renderPattern rhs <> ")"
  PBoolEq lhs rhs ->
    "(" <> renderPattern lhs <> " == " <> renderPattern rhs <> ")"
  PKnownInt inner ->
    "KnownInt(" <> renderPattern inner <> ")"
  PKnownBool inner ->
    "KnownBool(" <> renderPattern inner <> ")"
  PZeroInfo inner ->
    "ZeroInfo(" <> renderPattern inner <> ")"

renderArgs :: [Pattern] -> Text
renderArgs args =
  "(" <> Text.intercalate ", " (map renderPattern args) <> ")"
