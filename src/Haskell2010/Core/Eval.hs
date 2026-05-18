module Haskell2010.Core.Eval
  ( CoreEvalError (..)
  , CoreValue (..)
  , evalCoreExpr
  , evalCoreModuleBinding
  , evalCoreModuleBindingByOccurrence
  , renderCoreEvalError
  , renderCoreValue
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import qualified Haskell2010.Core.Validate as CoreValidate
import Haskell2010.Names (RName, nameOcc, renderRName)
import Haskell2010.Syntax (Literal (..))
import Runtime.Int
  ( HInt
  , IntError
  , addHInt
  , divHInt
  , eqHInt
  , hintToInteger
  , ltHInt
  , mkHIntLiteral
  , mulHInt
  , renderHInt
  , renderIntError
  , subHInt
  )

data CoreValue
  = CoreInt HInt
  | CoreBool Bool
  | CoreChar Char
  | CoreString Text
  | CoreClosure Env CoreBinder CoreExpr
  | CoreTypeClosure Env [RName] CoreExpr
  deriving stock (Show)

data CoreEvalError
  = CoreEvalInvalid [CoreValidate.CoreValidationError]
  | CoreEvalUnknownVariable RName
  | CoreEvalUnknownBinding RName
  | CoreEvalUnknownBindingOccurrence Text
  | CoreEvalAmbiguousBindingOccurrence Text [RName]
  | CoreEvalTypeError Text
  | CoreEvalDivisionByZero
  | CoreEvalIntError IntError
  | CoreEvalNoMatchingAlternative CoreValue
  deriving stock (Show)

type Env = Map.Map RName CoreThunk

data CoreThunk
  = Evaluated CoreValue
  | Unevaluated Env CoreExpr
  deriving stock (Show)

evalCoreExpr :: CoreExpr -> Either CoreEvalError CoreValue
evalCoreExpr expression =
  case CoreValidate.validateExpr expression of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () -> evalExpr Map.empty expression

evalCoreModuleBinding :: RName -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBinding name coreModule =
  case CoreValidate.validateModule CoreValidate.defaultValidationEnv coreModule of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () -> evalCoreModuleBindingUnchecked name coreModule

evalCoreModuleBindingUnchecked :: RName -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBindingUnchecked name coreModule =
  case Map.lookup name env of
    Nothing -> Left (CoreEvalUnknownBinding name)
    Just thunk -> force thunk
 where
  env =
    moduleEnv coreModule

evalCoreModuleBindingByOccurrence :: Text -> CoreModule -> Either CoreEvalError CoreValue
evalCoreModuleBindingByOccurrence occurrence coreModule =
  case CoreValidate.validateModule CoreValidate.defaultValidationEnv coreModule of
    Left errors -> Left (CoreEvalInvalid errors)
    Right () ->
      case matchingNames of
        [] ->
          Left (CoreEvalUnknownBindingOccurrence occurrence)
        [name] ->
          evalCoreModuleBindingUnchecked name coreModule
        names ->
          Left (CoreEvalAmbiguousBindingOccurrence occurrence names)
 where
  matchingNames =
    [ coreBinderName binder
    | bind <- coreModuleBinds coreModule
    , binder <- bindersOf bind
    , nameOcc (coreBinderName binder) == occurrence
    ]

evalExpr :: Env -> CoreExpr -> Either CoreEvalError CoreValue
evalExpr env = \case
  CVar name _ ->
    case Map.lookup name env of
      Nothing -> Left (CoreEvalUnknownVariable name)
      Just thunk -> force thunk
  CLit literal _ ->
    evalLiteral literal
  CCon name _
    | name == trueDataConName ->
        Right (CoreBool True)
    | name == falseDataConName ->
        Right (CoreBool False)
    | otherwise ->
        Left
          (CoreEvalTypeError ("unsupported Core-0 constructor value `" <> renderRName name <> "`"))
  CLam binder body _ ->
    Right (CoreClosure env binder body)
  CApp function argument _ -> do
    functionValue <- evalExpr env function
    case functionValue of
      CoreClosure closureEnv binder body ->
        evalExpr (Map.insert (coreBinderName binder) (Unevaluated env argument) closureEnv) body
      other ->
        Left (CoreEvalTypeError ("expected Core function, got " <> renderCoreValue other))
  CTypeLam variables body _ ->
    Right (CoreTypeClosure env variables body)
  CTypeApp function _ _ -> do
    functionValue <- evalExpr env function
    case functionValue of
      CoreTypeClosure closureEnv _ body ->
        evalExpr closureEnv body
      other ->
        Left (CoreEvalTypeError ("expected Core type function, got " <> renderCoreValue other))
  CLet bind body _ ->
    evalExpr (extendEnv bind env) body
  CCase scrutinee binder alternatives _ -> do
    scrutineeValue <- evalExpr env scrutinee
    evalCaseAlternative env binder alternatives scrutineeValue
  CPrimOp op arguments _ ->
    traverse (evalExpr env) arguments >>= evalPrimitive op

evalLiteral :: Literal -> Either CoreEvalError CoreValue
evalLiteral = \case
  LInt value ->
    case mkHIntLiteral value of
      Right intValue -> Right (CoreInt intValue)
      Left err -> Left (CoreEvalIntError err)
  LChar value ->
    Right (CoreChar value)
  LString value ->
    Right (CoreString value)

force :: CoreThunk -> Either CoreEvalError CoreValue
force = \case
  Evaluated value ->
    Right value
  Unevaluated env expression ->
    evalExpr env expression

moduleEnv :: CoreModule -> Env
moduleEnv coreModule =
  env
 where
  env =
    Map.fromList
      [ (coreBinderName binder, Unevaluated env rhs)
      | (binder, rhs) <- concatMap bindPairs (coreModuleBinds coreModule)
      ]

extendEnv :: CoreBind -> Env -> Env
extendEnv bind env =
  case bind of
    CoreNonRec binder rhs ->
      Map.insert (coreBinderName binder) (Unevaluated env rhs) env
    CoreRec pairs ->
      recEnv
     where
      recEnv =
        Map.union
          ( Map.fromList
              [ (coreBinderName binder, Unevaluated recEnv rhs)
              | (binder, rhs) <- pairs
              ]
          )
          env

bindPairs :: CoreBind -> [(CoreBinder, CoreExpr)]
bindPairs = \case
  CoreNonRec binder rhs -> [(binder, rhs)]
  CoreRec pairs -> pairs

evalCaseAlternative :: Env -> CoreBinder -> [CoreAlt] -> CoreValue -> Either CoreEvalError CoreValue
evalCaseAlternative env binder alternatives scrutineeValue =
  case firstMatching alternatives of
    Nothing ->
      Left (CoreEvalNoMatchingAlternative scrutineeValue)
    Just (CoreAlt _ altBinders body) ->
      evalExpr (extendCaseEnv binder scrutineeValue altBinders env) body
 where
  firstMatching [] =
    Nothing
  firstMatching (alternative@(CoreAlt altCon _ _) : rest)
    | alternativeMatches altCon scrutineeValue = Just alternative
    | otherwise = firstMatching rest

extendCaseEnv :: CoreBinder -> CoreValue -> [CoreBinder] -> Env -> Env
extendCaseEnv binder scrutineeValue altBinders env =
  foldr
    (\altBinder -> Map.insert (coreBinderName altBinder) (Evaluated scrutineeValue))
    (Map.insert (coreBinderName binder) (Evaluated scrutineeValue) env)
    altBinders

alternativeMatches :: CoreAltCon -> CoreValue -> Bool
alternativeMatches altCon value =
  case (altCon, value) of
    (DefaultAlt, _) ->
      True
    (LiteralAlt (LInt expected), CoreInt actual) ->
      hintToInteger actual == expected
    (LiteralAlt (LChar expected), CoreChar actual) ->
      actual == expected
    (LiteralAlt (LString expected), CoreString actual) ->
      actual == expected
    (ConstructorAlt name, CoreBool True) ->
      name == trueDataConName
    (ConstructorAlt name, CoreBool False) ->
      name == falseDataConName
    _ ->
      False

evalPrimitive :: CorePrimOp -> [CoreValue] -> Either CoreEvalError CoreValue
evalPrimitive op values =
  case (op, values) of
    (PrimAdd, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (addHInt lhs rhs)
    (PrimSub, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (subHInt lhs rhs)
    (PrimMul, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (mulHInt lhs rhs)
    (PrimDiv, [CoreInt _, CoreInt rhs])
      | hintToInteger rhs == 0 ->
          Left CoreEvalDivisionByZero
    (PrimDiv, [CoreInt lhs, CoreInt rhs]) ->
      checkedIntValue (divHInt lhs rhs)
    (PrimEq, [lhs, rhs]) ->
      CoreBool <$> valueEquals lhs rhs
    (PrimLt, [CoreInt lhs, CoreInt rhs]) ->
      Right (CoreBool (ltHInt lhs rhs))
    (PrimNegate, [CoreInt value]) ->
      checkedIntValue (subHInt zero value)
    _ ->
      Left (CoreEvalTypeError ("invalid Core primitive operands for " <> renderCorePrimOpName op))
 where
  checkedIntValue =
    \case
      Right value -> Right (CoreInt value)
      Left err -> Left (CoreEvalIntError err)
  zero =
    case mkHIntLiteral 0 of
      Right value -> value
      Left err -> error (Text.unpack (renderIntError err))

valueEquals :: CoreValue -> CoreValue -> Either CoreEvalError Bool
valueEquals lhs rhs =
  case (lhs, rhs) of
    (CoreInt lhsInt, CoreInt rhsInt) ->
      Right (eqHInt lhsInt rhsInt)
    (CoreBool lhsBool, CoreBool rhsBool) ->
      Right (lhsBool == rhsBool)
    (CoreChar lhsChar, CoreChar rhsChar) ->
      Right (lhsChar == rhsChar)
    (CoreString lhsText, CoreString rhsText) ->
      Right (lhsText == rhsText)
    _ ->
      Left
        ( CoreEvalTypeError
            ("cannot compare Core values " <> renderCoreValue lhs <> " and " <> renderCoreValue rhs)
        )

renderCoreValue :: CoreValue -> Text
renderCoreValue = \case
  CoreInt value ->
    renderHInt value
  CoreBool True ->
    "True"
  CoreBool False ->
    "False"
  CoreChar value ->
    Text.pack (show value)
  CoreString value ->
    Text.pack (show (Text.unpack value))
  CoreClosure {} ->
    "<Core function>"
  CoreTypeClosure {} ->
    "<Core type function>"

renderCoreEvalError :: CoreEvalError -> Text
renderCoreEvalError = \case
  CoreEvalInvalid errors ->
    "invalid Core before evaluation: "
      <> Text.intercalate "; " (map CoreValidate.renderValidationError errors)
  CoreEvalUnknownVariable name ->
    "unknown Core variable `" <> renderRName name <> "`"
  CoreEvalUnknownBinding name ->
    "unknown Core module binding `" <> renderRName name <> "`"
  CoreEvalUnknownBindingOccurrence occurrence ->
    "unknown Core module binding occurrence `" <> occurrence <> "`"
  CoreEvalAmbiguousBindingOccurrence occurrence names ->
    "ambiguous Core module binding occurrence `"
      <> occurrence
      <> "`: "
      <> Text.intercalate ", " (map renderRName names)
  CoreEvalTypeError message ->
    message
  CoreEvalDivisionByZero ->
    "division by zero"
  CoreEvalIntError err ->
    renderIntError err
  CoreEvalNoMatchingAlternative value ->
    "no Core case alternative matched " <> renderCoreValue value

renderCorePrimOpName :: CorePrimOp -> Text
renderCorePrimOpName = \case
  PrimAdd -> "+"
  PrimSub -> "-"
  PrimMul -> "*"
  PrimDiv -> "/"
  PrimEq -> "=="
  PrimLt -> "<"
  PrimNegate -> "negate#"
