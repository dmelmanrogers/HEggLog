module Haskell2010.STG.Eval
  ( STGEvalError (..)
  , STGEvalStats (..)
  , STGHeapAddress (..)
  , STGValue (..)
  , evalSTGExpr
  , evalSTGExprWithStats
  , evalSTGProgramBinding
  , evalSTGProgramBindingByOccurrence
  , evalSTGProgramBindingByOccurrenceWithStats
  , evalSTGProgramBindingWithStats
  , renderSTGEvalError
  , renderSTGValue
  )
where

import Control.Monad (foldM, zipWithM_)
import Control.Monad.State.Strict (StateT, get, lift, modify, runStateT)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax
import Haskell2010.Names (RName, nameOcc, renderRName)
import Haskell2010.STG.Syntax
import qualified Haskell2010.STG.Validate as STGValidate
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

newtype STGHeapAddress = STGHeapAddress Int
  deriving stock (Show, Eq, Ord)

data STGValue
  = STGInt HInt
  | STGBool Bool
  | STGChar Char
  | STGString Text
  | STGIO [Text]
  | STGData RName [STGHeapAddress]
  | STGFunctionValue STGHeapAddress
  deriving stock (Show, Eq, Ord)

data STGEvalStats = STGEvalStats
  { stgThunkEvaluations :: Map.Map RName Int
  }
  deriving stock (Show, Eq, Ord)

data STGEvalError
  = STGEvalInvalid [STGValidate.STGValidationError]
  | STGEvalUnknownVariable RName
  | STGEvalUnknownBinding RName
  | STGEvalUnknownBindingOccurrence Text
  | STGEvalAmbiguousBindingOccurrence Text [RName]
  | STGEvalUnknownHeapAddress STGHeapAddress
  | STGEvalBlackHole (Maybe RName)
  | STGEvalTypeError Text
  | STGEvalArityMismatch RName Int Int
  | STGEvalDivisionByZero
  | STGEvalIntError IntError
  | STGEvalNoMatchingAlternative STGValue
  deriving stock (Show, Eq)

type RuntimeEnv = Map.Map RName STGHeapAddress

data RuntimeClosure
  = ValueClosure STGValue
  | FunctionClosure RuntimeEnv [STGBinder] STGExpr
  | ThunkClosure (Maybe RName) STGUpdateFlag RuntimeEnv STGExpr
  | BlackHole (Maybe RName)
  deriving stock (Show, Eq)

data EvalState = EvalState
  { evalNextAddress :: Int
  , evalHeap :: Map.Map STGHeapAddress RuntimeClosure
  , evalStats :: STGEvalStats
  }
  deriving stock (Show, Eq)

type EvalM = StateT EvalState (Either STGEvalError)

evalSTGExpr :: STGExpr -> Either STGEvalError STGValue
evalSTGExpr expression =
  fst <$> evalSTGExprWithStats expression

evalSTGExprWithStats :: STGExpr -> Either STGEvalError (STGValue, STGEvalStats)
evalSTGExprWithStats expression =
  case STGValidate.validateExpr expression of
    Left errors -> Left (STGEvalInvalid errors)
    Right () -> runEval (evalExpr Map.empty expression)

evalSTGProgramBinding :: RName -> STGProgram -> Either STGEvalError STGValue
evalSTGProgramBinding name program =
  fst <$> evalSTGProgramBindingWithStats name program

evalSTGProgramBindingWithStats ::
  RName ->
  STGProgram ->
  Either STGEvalError (STGValue, STGEvalStats)
evalSTGProgramBindingWithStats name program =
  case STGValidate.validateProgram program of
    Left errors -> Left (STGEvalInvalid errors)
    Right () -> evalSTGProgramBindingUnchecked name program

evalSTGProgramBindingByOccurrence :: Text -> STGProgram -> Either STGEvalError STGValue
evalSTGProgramBindingByOccurrence occurrence program =
  fst <$> evalSTGProgramBindingByOccurrenceWithStats occurrence program

evalSTGProgramBindingByOccurrenceWithStats ::
  Text ->
  STGProgram ->
  Either STGEvalError (STGValue, STGEvalStats)
evalSTGProgramBindingByOccurrenceWithStats occurrence program =
  case STGValidate.validateProgram program of
    Left errors -> Left (STGEvalInvalid errors)
    Right () ->
      case matchingNames of
        [] ->
          Left (STGEvalUnknownBindingOccurrence occurrence)
        [name] ->
          evalSTGProgramBindingUnchecked name program
        names ->
          Left (STGEvalAmbiguousBindingOccurrence occurrence names)
 where
  matchingNames =
    [ stgBinderName binder
    | bind <- stgProgramBinds program
    , binder <- stgBindersOf bind
    , nameOcc (stgBinderName binder) == occurrence
    ]

evalSTGProgramBindingUnchecked ::
  RName ->
  STGProgram ->
  Either STGEvalError (STGValue, STGEvalStats)
evalSTGProgramBindingUnchecked name program =
  runEval $ do
    env <- allocateProgramEnv program
    address <- lookupBinding name env
    forceAddress address

runEval :: EvalM STGValue -> Either STGEvalError (STGValue, STGEvalStats)
runEval action = do
  (value, finalState) <- runStateT action initialState
  Right (value, evalStats finalState)

initialState :: EvalState
initialState =
  EvalState
    { evalNextAddress = 0
    , evalHeap = Map.empty
    , evalStats = STGEvalStats {stgThunkEvaluations = Map.empty}
    }

evalExpr :: RuntimeEnv -> STGExpr -> EvalM STGValue
evalExpr env = \case
  STGAtom atom ->
    evalAtom env atom
  STGApp callee arguments _ ->
    enterNamedFunction env callee arguments
  STGLet bind body _ -> do
    env' <- allocateBind env bind
    evalExpr env' body
  STGCase scrutinee binder alternatives _ -> do
    scrutineeValue <- evalExpr env scrutinee
    evalCaseAlternative env binder alternatives scrutineeValue
  STGPrim op arguments _ ->
    traverse (evalAtom env) arguments >>= evalPrimitive op

evalAtom :: RuntimeEnv -> STGAtom -> EvalM STGValue
evalAtom env = \case
  STGVar name _ ->
    lookupEnv name env >>= forceAddress
  STGLit literal _ ->
    liftEither (evalLiteral literal)
  STGCon name _ ->
    pure (constructorValue name [])

evalLiteral :: Literal -> Either STGEvalError STGValue
evalLiteral = \case
  LInt value ->
    case mkHIntLiteral value of
      Right intValue -> Right (STGInt intValue)
      Left err -> Left (STGEvalIntError err)
  LChar value ->
    Right (STGChar value)
  LString value ->
    Right (STGString value)

allocateProgramEnv :: STGProgram -> EvalM RuntimeEnv
allocateProgramEnv (STGProgram _ binds) =
  foldM allocateBind Map.empty binds

allocateBind :: RuntimeEnv -> STGBind -> EvalM RuntimeEnv
allocateBind env = \case
  STGNonRec binder rhs -> do
    closure <- rhsToClosure (Just (stgBinderName binder)) env rhs
    address <- allocateClosure closure
    pure (Map.insert (stgBinderName binder) address env)
  STGRec pairs -> do
    addresses <-
      traverse
        (\(binder, _) -> allocateClosure (BlackHole (Just (stgBinderName binder))))
        pairs
    let binderAddresses = zip (map (stgBinderName . fst) pairs) addresses
        recEnv = Map.union (Map.fromList binderAddresses) env
    zipWithM_ (writeRecClosure recEnv) pairs addresses
    pure recEnv
 where
  writeRecClosure recEnv (binder, rhs) address = do
    closure <- rhsToClosure (Just (stgBinderName binder)) recEnv rhs
    writeClosure address closure

rhsToClosure :: Maybe RName -> RuntimeEnv -> STGRhs -> EvalM RuntimeClosure
rhsToClosure origin env = \case
  STGFunction binders body ->
    pure (FunctionClosure env binders body)
  STGThunk updateFlag body ->
    pure (ThunkClosure origin updateFlag env body)
  STGConstructor name fields _ -> do
    fieldAddresses <- traverse (atomAddress env) fields
    pure (ValueClosure (constructorValue name fieldAddresses))

atomAddress :: RuntimeEnv -> STGAtom -> EvalM STGHeapAddress
atomAddress env = \case
  STGVar name _ ->
    lookupEnv name env
  STGLit literal _ -> do
    value <- liftEither (evalLiteral literal)
    allocateClosure (ValueClosure value)
  STGCon name _ ->
    allocateClosure (ValueClosure (constructorValue name []))

enterNamedFunction :: RuntimeEnv -> RName -> [STGAtom] -> EvalM STGValue
enterNamedFunction callerEnv callee arguments =
  lookupEnv callee callerEnv >>= \address -> enterFunctionAddress callerEnv callee address arguments

enterFunctionAddress :: RuntimeEnv -> RName -> STGHeapAddress -> [STGAtom] -> EvalM STGValue
enterFunctionAddress callerEnv callee address arguments =
  lookupClosure address >>= \case
    FunctionClosure closureEnv binders body ->
      applyFunction callerEnv callee closureEnv binders body arguments
    ThunkClosure {} -> do
      value <- forceAddress address
      case value of
        STGFunctionValue functionAddress ->
          enterFunctionAddress callerEnv callee functionAddress arguments
        other ->
          typeError ("expected STG function, got " <> renderSTGValue other)
    ValueClosure (STGFunctionValue functionAddress) ->
      enterFunctionAddress callerEnv callee functionAddress arguments
    ValueClosure other ->
      typeError ("expected STG function, got " <> renderSTGValue other)
    BlackHole origin ->
      throwEval (STGEvalBlackHole origin)

applyFunction ::
  RuntimeEnv ->
  RName ->
  RuntimeEnv ->
  [STGBinder] ->
  STGExpr ->
  [STGAtom] ->
  EvalM STGValue
applyFunction callerEnv callee closureEnv binders body arguments
  | expectedArity /= actualArity =
      throwEval (STGEvalArityMismatch callee expectedArity actualArity)
  | otherwise = do
      argumentAddresses <- traverse (atomAddress callerEnv) arguments
      let parameterEnv =
            Map.fromList (zip (map stgBinderName binders) argumentAddresses)
      evalExpr (Map.union parameterEnv closureEnv) body
 where
  expectedArity =
    length binders
  actualArity =
    length arguments

forceAddress :: STGHeapAddress -> EvalM STGValue
forceAddress address =
  lookupClosure address >>= \case
    ValueClosure value ->
      pure value
    FunctionClosure {} ->
      pure (STGFunctionValue address)
    ThunkClosure origin updateFlag closureEnv body -> do
      bumpThunkEvaluation origin
      writeClosure address (BlackHole origin)
      value <- evalExpr closureEnv body
      case updateFlag of
        Updatable ->
          writeClosure address (ValueClosure value)
        SingleEntry ->
          writeClosure address (ThunkClosure origin updateFlag closureEnv body)
      pure value
    BlackHole origin ->
      throwEval (STGEvalBlackHole origin)

evalCaseAlternative ::
  RuntimeEnv ->
  STGBinder ->
  [STGAlt] ->
  STGValue ->
  EvalM STGValue
evalCaseAlternative env binder alternatives scrutineeValue =
  case firstMatching alternatives of
    Nothing ->
      throwEval (STGEvalNoMatchingAlternative scrutineeValue)
    Just (STGAlt _ altBinders body, fieldAddresses) -> do
      caseAddress <- allocateClosure (ValueClosure scrutineeValue)
      let caseEnv = Map.insert (stgBinderName binder) caseAddress env
      fieldEnv <- bindAlternativeFields altBinders fieldAddresses
      evalExpr (Map.union fieldEnv caseEnv) body
 where
  firstMatching [] =
    Nothing
  firstMatching (alternative@(STGAlt altCon _ _) : rest) =
    case alternativeFields altCon scrutineeValue of
      Just fieldAddresses -> Just (alternative, fieldAddresses)
      Nothing -> firstMatching rest

bindAlternativeFields :: [STGBinder] -> [STGHeapAddress] -> EvalM RuntimeEnv
bindAlternativeFields binders fieldAddresses
  | length binders == length fieldAddresses =
      pure (Map.fromList (zip (map stgBinderName binders) fieldAddresses))
  | otherwise =
      typeError "STG constructor alternative field arity mismatch"

alternativeFields :: CoreAltCon -> STGValue -> Maybe [STGHeapAddress]
alternativeFields altCon value =
  case (altCon, value) of
    (DefaultAlt, _) ->
      Just []
    (LiteralAlt (LInt expected), STGInt actual)
      | hintToInteger actual == expected -> Just []
    (LiteralAlt (LChar expected), STGChar actual)
      | actual == expected -> Just []
    (LiteralAlt (LString expected), STGString actual)
      | actual == expected -> Just []
    (ConstructorAlt name, STGBool True)
      | name == trueDataConName -> Just []
    (ConstructorAlt name, STGBool False)
      | name == falseDataConName -> Just []
    (ConstructorAlt expectedName, STGData actualName fields)
      | expectedName == actualName -> Just fields
    _ ->
      Nothing

evalPrimitive :: CorePrimOp -> [STGValue] -> EvalM STGValue
evalPrimitive op values =
  case (op, values) of
    (PrimAdd, [STGInt lhs, STGInt rhs]) ->
      liftEither (checkedIntValue (addHInt lhs rhs))
    (PrimSub, [STGInt lhs, STGInt rhs]) ->
      liftEither (checkedIntValue (subHInt lhs rhs))
    (PrimMul, [STGInt lhs, STGInt rhs]) ->
      liftEither (checkedIntValue (mulHInt lhs rhs))
    (PrimDiv, [STGInt _, STGInt rhs])
      | hintToInteger rhs == 0 ->
          throwEval STGEvalDivisionByZero
    (PrimDiv, [STGInt lhs, STGInt rhs]) ->
      liftEither (checkedIntValue (divHInt lhs rhs))
    (PrimEq, [lhs, rhs]) ->
      liftEither (STGBool <$> valueEquals lhs rhs)
    (PrimLt, [STGInt lhs, STGInt rhs]) ->
      pure (STGBool (ltHInt lhs rhs))
    (PrimNegate, [STGInt value]) ->
      liftEither (checkedIntValue (subHInt zero value))
    (PrimShowInt, [STGInt value]) ->
      pure (STGString (renderHInt value))
    (PrimShowBool, [STGBool True]) ->
      pure (STGString "True")
    (PrimShowBool, [STGBool False]) ->
      pure (STGString "False")
    (PrimPutStrLn, [value]) ->
      STGIO . (: []) . (<> "\n") <$> stgStringText value
    (PrimIOThen, [STGIO first, STGIO second]) ->
      pure (STGIO (first <> second))
    (PrimIOReturn, [_]) ->
      pure (STGIO [])
    _ ->
      throwEval (STGEvalTypeError ("invalid STG primitive operands for " <> renderCorePrimOpName op))
 where
  checkedIntValue =
    \case
      Right value -> Right (STGInt value)
      Left err -> Left (STGEvalIntError err)
  zero =
    case mkHIntLiteral 0 of
      Right value -> value
      Left err -> error (Text.unpack (renderIntError err))

stgStringText :: STGValue -> EvalM Text
stgStringText = \case
  STGString value ->
    pure value
  STGData name []
    | name == listNilDataConName ->
        pure ""
  STGData name [headAddress, tailAddress]
    | name == listConsDataConName -> do
        headValue <- forceAddress headAddress
        tailValue <- forceAddress tailAddress
        case headValue of
          STGChar char -> Text.cons char <$> stgStringText tailValue
          other -> typeError ("expected Char in String list, got " <> renderSTGValue other)
  other ->
    typeError ("expected String, got " <> renderSTGValue other)

valueEquals :: STGValue -> STGValue -> Either STGEvalError Bool
valueEquals lhs rhs =
  case (lhs, rhs) of
    (STGInt lhsInt, STGInt rhsInt) ->
      Right (eqHInt lhsInt rhsInt)
    (STGBool lhsBool, STGBool rhsBool) ->
      Right (lhsBool == rhsBool)
    (STGChar lhsChar, STGChar rhsChar) ->
      Right (lhsChar == rhsChar)
    (STGString lhsText, STGString rhsText) ->
      Right (lhsText == rhsText)
    _ ->
      Left
        ( STGEvalTypeError
            ("cannot compare STG values " <> renderSTGValue lhs <> " and " <> renderSTGValue rhs)
        )

constructorValue :: RName -> [STGHeapAddress] -> STGValue
constructorValue name fields
  | name == trueDataConName && null fields = STGBool True
  | name == falseDataConName && null fields = STGBool False
  | otherwise = STGData name fields

allocateClosure :: RuntimeClosure -> EvalM STGHeapAddress
allocateClosure closure = do
  state <- get
  let address = STGHeapAddress (evalNextAddress state)
  modify $ \current ->
    current
      { evalNextAddress = evalNextAddress current + 1
      , evalHeap = Map.insert address closure (evalHeap current)
      }
  pure address

writeClosure :: STGHeapAddress -> RuntimeClosure -> EvalM ()
writeClosure address closure =
  modify $ \state -> state {evalHeap = Map.insert address closure (evalHeap state)}

lookupEnv :: RName -> RuntimeEnv -> EvalM STGHeapAddress
lookupEnv name env =
  case Map.lookup name env of
    Nothing -> throwEval (STGEvalUnknownVariable name)
    Just address -> pure address

lookupBinding :: RName -> RuntimeEnv -> EvalM STGHeapAddress
lookupBinding name env =
  case Map.lookup name env of
    Nothing -> throwEval (STGEvalUnknownBinding name)
    Just address -> pure address

lookupClosure :: STGHeapAddress -> EvalM RuntimeClosure
lookupClosure address = do
  state <- get
  case Map.lookup address (evalHeap state) of
    Nothing -> throwEval (STGEvalUnknownHeapAddress address)
    Just closure -> pure closure

bumpThunkEvaluation :: Maybe RName -> EvalM ()
bumpThunkEvaluation Nothing =
  pure ()
bumpThunkEvaluation (Just name) =
  modify $ \state ->
    let stats = evalStats state
     in state
          { evalStats =
              stats
                { stgThunkEvaluations =
                    Map.insertWith (+) name 1 (stgThunkEvaluations stats)
                }
          }

throwEval :: STGEvalError -> EvalM a
throwEval =
  lift . Left

typeError :: Text -> EvalM a
typeError =
  throwEval . STGEvalTypeError

liftEither :: Either STGEvalError a -> EvalM a
liftEither =
  lift

renderSTGValue :: STGValue -> Text
renderSTGValue = \case
  STGInt value ->
    renderHInt value
  STGBool True ->
    "True"
  STGBool False ->
    "False"
  STGChar value ->
    Text.pack (show value)
  STGString value ->
    Text.pack (show (Text.unpack value))
  STGIO chunks ->
    "<STG IO " <> Text.pack (show (Text.unpack (Text.concat chunks))) <> ">"
  STGData name fields ->
    renderRName name <> "/" <> Text.pack (show (length fields))
  STGFunctionValue address ->
    "<STG function " <> Text.pack (show address) <> ">"

renderSTGEvalError :: STGEvalError -> Text
renderSTGEvalError = \case
  STGEvalInvalid errors ->
    "invalid STG before evaluation: "
      <> Text.intercalate "; " (map STGValidate.renderSTGValidationError errors)
  STGEvalUnknownVariable name ->
    "unknown STG variable `" <> renderRName name <> "`"
  STGEvalUnknownBinding name ->
    "unknown STG program binding `" <> renderRName name <> "`"
  STGEvalUnknownBindingOccurrence occurrence ->
    "unknown STG program binding occurrence `" <> occurrence <> "`"
  STGEvalAmbiguousBindingOccurrence occurrence names ->
    "ambiguous STG program binding occurrence `"
      <> occurrence
      <> "`: "
      <> Text.intercalate ", " (map renderRName names)
  STGEvalUnknownHeapAddress address ->
    "unknown STG heap address " <> Text.pack (show address)
  STGEvalBlackHole Nothing ->
    "entered an evaluating STG thunk"
  STGEvalBlackHole (Just name) ->
    "entered an evaluating STG thunk for `" <> renderRName name <> "`"
  STGEvalTypeError message ->
    message
  STGEvalArityMismatch callee expected actual ->
    "STG function `"
      <> renderRName callee
      <> "` arity mismatch: expected "
      <> Text.pack (show expected)
      <> ", got "
      <> Text.pack (show actual)
  STGEvalDivisionByZero ->
    "division by zero"
  STGEvalIntError err ->
    renderIntError err
  STGEvalNoMatchingAlternative value ->
    "no STG case alternative matched " <> renderSTGValue value

renderCorePrimOpName :: CorePrimOp -> Text
renderCorePrimOpName = \case
  PrimAdd -> "+"
  PrimSub -> "-"
  PrimMul -> "*"
  PrimDiv -> "/"
  PrimEq -> "=="
  PrimLt -> "<"
  PrimNegate -> "negate#"
  PrimShowInt -> "showInt#"
  PrimShowBool -> "showBool#"
  PrimPutStrLn -> "putStrLn#"
  PrimIOThen -> "thenIO#"
  PrimIOReturn -> "returnIO#"
