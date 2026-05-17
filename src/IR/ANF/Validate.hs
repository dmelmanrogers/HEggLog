module IR.ANF.Validate
  ( ANFValidationError (..)
  , renderANFValidationError
  , validateANF
  , validateANFProgram
  , validateANFWithFreeVars
  )
where

import qualified Data.Char as Char
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import IR.ANF
import Syntax.AST
import Syntax.Pretty (prettyName, renderDoc)

data ANFValidationError
  = UnboundVariable Name
  | UnboundFunction Name
  | DuplicateGeneratedTemp Name
  | GeneratedTempShadowed Name
  | DuplicateANFFunction Name
  deriving stock (Show, Eq, Ord)

-- The ANF data type enforces atomic primitive/application operands at the type
-- level. This validator checks the remaining semantic invariants: lexical
-- binding and the compiler-reserved temporary namespace used by lowering.
validateANF :: AExpr -> Either ANFValidationError ()
validateANF =
  validateANFWithFreeVars Set.empty

validateANFWithFreeVars :: Set.Set Name -> AExpr -> Either ANFValidationError ()
validateANFWithFreeVars allowedFreeVars expression = do
  validateGeneratedTemps expression
  validateExpr Set.empty allowedFreeVars expression

validateANFProgram :: AProgram -> Either ANFValidationError ()
validateANFProgram (AProgram defs mainExpr) = do
  let functionNames = map anfFunctionName defs
      functionSet = Set.fromList functionNames
  case duplicates functionNames of
    name : _ -> Left (DuplicateANFFunction name)
    [] -> Right ()
  validateFunctions Set.empty defs
  validateGeneratedTemps mainExpr
  validateExpr functionSet Set.empty mainExpr

validateFunctions :: Set.Set Name -> [AFun] -> Either ANFValidationError ()
validateFunctions _ [] =
  Right ()
validateFunctions available (function@(AFun name _ _ _) : rest) = do
  validateFunction available function
  validateFunctions (Set.insert name available) rest

validateFunction :: Set.Set Name -> AFun -> Either ANFValidationError ()
validateFunction functionSet (AFun _ params _ body) = do
  validateGeneratedTemps body
  validateExpr functionSet (Set.fromList (map paramName params)) body

anfFunctionName :: AFun -> Name
anfFunctionName (AFun name _ _ _) =
  name

validateExpr :: Set.Set Name -> Set.Set Name -> AExpr -> Either ANFValidationError ()
validateExpr functions bound = \case
  AAtom atom ->
    validateAtom bound atom
  APrim _ lhs rhs -> do
    validateAtom bound lhs
    validateAtom bound rhs
  AIf cond thenBranch elseBranch -> do
    validateAtom bound cond
    validateExpr functions bound thenBranch
    validateExpr functions bound elseBranch
  ALam name _ body ->
    validateExpr functions (Set.insert name bound) body
  AApp fn arg -> do
    validateAtom bound fn
    validateAtom bound arg
  ACall callee args -> do
    if callee `Set.member` functions
      then Right ()
      else Left (UnboundFunction callee)
    mapM_ (validateAtom bound) args
  ALet name rhs body -> do
    validateExpr functions bound rhs
    validateExpr functions (Set.insert name bound) body

validateAtom :: Set.Set Name -> Atom -> Either ANFValidationError ()
validateAtom bound = \case
  AVar name
    | name `Set.member` bound -> Right ()
    | otherwise -> Left (UnboundVariable name)
  AInt _ -> Right ()
  ABool _ -> Right ()

validateGeneratedTemps :: AExpr -> Either ANFValidationError ()
validateGeneratedTemps expression =
  case duplicates generatedTemps of
    tempName : _ -> Left (DuplicateGeneratedTemp tempName)
    [] -> checkNoGeneratedTempShadowing expression
 where
  generatedTemps =
    filter isGeneratedTempName (boundNames expression)

checkNoGeneratedTempShadowing :: AExpr -> Either ANFValidationError ()
checkNoGeneratedTempShadowing =
  go Set.empty
 where
  go inScope = \case
    AAtom {} ->
      Right ()
    APrim {} ->
      Right ()
    AIf _ thenBranch elseBranch -> do
      go inScope thenBranch
      go inScope elseBranch
    ALam name _ body -> do
      rejectShadow name inScope
      go (Set.insert name inScope) body
    AApp {} ->
      Right ()
    ACall {} ->
      Right ()
    ALet name rhs body -> do
      go inScope rhs
      rejectShadow name inScope
      go (Set.insert name inScope) body

rejectShadow :: Name -> Set.Set Name -> Either ANFValidationError ()
rejectShadow name inScope
  | isGeneratedTempName name && name `Set.member` inScope =
      Left (GeneratedTempShadowed name)
  | otherwise =
      Right ()

boundNames :: AExpr -> [Name]
boundNames = \case
  AAtom {} ->
    []
  APrim {} ->
    []
  AIf _ thenBranch elseBranch ->
    boundNames thenBranch <> boundNames elseBranch
  ALam name _ body ->
    name : boundNames body
  AApp {} ->
    []
  ACall {} ->
    []
  ALet name rhs body ->
    name : boundNames rhs <> boundNames body

duplicates :: [Name] -> [Name]
duplicates =
  Map.keys . Map.filter (> 1) . foldr count Map.empty
 where
  count name =
    Map.insertWith (+) name (1 :: Int)

isGeneratedTempName :: Name -> Bool
isGeneratedTempName (Name text) =
  case Text.stripPrefix "_t" text of
    Just suffix ->
      not (Text.null suffix) && Text.all Char.isDigit suffix
    Nothing ->
      False

renderANFValidationError :: ANFValidationError -> Text
renderANFValidationError = \case
  UnboundVariable name ->
    "unbound variable in ANF: " <> renderDoc (prettyName name)
  UnboundFunction name ->
    "unbound function in ANF: " <> renderDoc (prettyName name)
  DuplicateGeneratedTemp name ->
    "duplicate generated ANF temporary: " <> renderDoc (prettyName name)
  GeneratedTempShadowed name ->
    "generated ANF temporary was shadowed: " <> renderDoc (prettyName name)
  DuplicateANFFunction name ->
    "duplicate ANF function: " <> renderDoc (prettyName name)
