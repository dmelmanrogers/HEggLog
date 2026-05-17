module Backend.ClosureConvert
  ( ClosureConvertError (..)
  , closureConvertProgram
  , programNeedsClosureRuntime
  , renderClosureConvertError
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Backend.IR
import Backend.Validate
import Runtime.Int (IntError, mkHIntLiteral, renderIntError)
import Syntax.AST
import Syntax.Pretty (prettyBinOp, prettyName, prettyType, renderDoc)

data ClosureConvertError
  = ClosureRootFunctionType Type
  | ClosureUnsupportedTopFunctionValue Name
  | ClosureUnsupportedPartialTopCall Name Int Int
  | ClosureUnsupportedPrimitive BinOp
  | ClosureUnknownVariable Name
  | ClosureExpectedBool BackendType
  | ClosureExpectedInt BinOp BackendType
  | ClosureExpectedFunction BackendType
  | ClosureTypeMismatch BackendType BackendType
  | ClosureCannotLowerTopFunctionType Name Type
  | ClosureIntError IntError
  | ClosureBackendValidationFailed BackendValidationError
  deriving stock (Show, Eq)

data Binding
  = LocalValue BackendType
  | TopFunction [BackendType] BackendType
  deriving stock (Show, Eq)

type Env = Map.Map Name Binding

data ConvertState = ConvertState
  { nextTemp :: Int
  , nextClosure :: Int
  , nextEnv :: Int
  , usedNames :: Set.Set Name
  , generatedFunctions :: [BackendFunction]
  }
  deriving stock (Show, Eq)

type ConvertM = ExceptT ClosureConvertError (State ConvertState)

closureConvertProgram :: Type -> Program -> Either ClosureConvertError BackendProgram
closureConvertProgram rootSourceType program =
  evalState (runExceptT (convertProgram rootSourceType program)) initialState
 where
  initialState =
    ConvertState
      { nextTemp = 0
      , nextClosure = 0
      , nextEnv = 0
      , usedNames = collectProgramNames program
      , generatedFunctions = []
      }

convertProgram :: Type -> Program -> ConvertM BackendProgram
convertProgram rootSourceType program = do
  rootType <- lowerSourceType rootSourceType
  case rootSourceType of
    TFun {} -> throwError (ClosureRootFunctionType rootSourceType)
    TInt -> pure ()
    TBool -> pure ()
  (topEnv, topFunctions) <- convertTopDefs Map.empty (programDefs program)
  root <- lowerExpr topEnv (programMain program)
  assertType rootType (backendExprType root)
  generated <- getsGeneratedFunctions
  let backend =
        BackendProgram
          { backendRootType = rootType
          , backendRoot = root
          , backendFunctions = topFunctions <> generated
          , backendProvenance =
              [ "lowered from closure-converted source"
              , "closures use heap objects containing a code pointer and captured environment fields"
              ]
          }
  case validateBackendProgram backend of
    Left err -> throwError (ClosureBackendValidationFailed err)
    Right () -> pure ()
  pure backend

convertTopDefs :: Env -> [TopDef] -> ConvertM (Env, [BackendFunction])
convertTopDefs env = \case
  [] ->
    pure (env, [])
  def : rest -> do
    function <- convertTopDef env def
    (paramTypes, returnType) <- topFunctionSignature def
    let env' = Map.insert (topDefName def) (TopFunction paramTypes returnType) env
    (finalEnv, restFunctions) <- convertTopDefs env' rest
    pure (finalEnv, function : restFunctions)

convertTopDef :: Env -> TopDef -> ConvertM BackendFunction
convertTopDef env def = do
  params <- traverse lowerParam (topDefParams def)
  returnType <- lowerFirstOrderType (topDefName def) (topDefReturnType def)
  body <- lowerExpr (Map.fromList [(name, LocalValue ty) | (name, ty) <- params] <> env) (topDefBody def)
  assertType returnType (backendExprType body)
  pure
    BackendFunction
      { backendFunctionName = topDefName def
      , backendFunctionParams = params
      , backendFunctionReturnType = returnType
      , backendFunctionBody = body
      }

topFunctionSignature :: TopDef -> ConvertM ([BackendType], BackendType)
topFunctionSignature def = do
  paramTypes <- traverse (lowerFirstOrderType (topDefName def) . paramType) (topDefParams def)
  returnType <- lowerFirstOrderType (topDefName def) (topDefReturnType def)
  pure (paramTypes, returnType)

lowerParam :: Param -> ConvertM (Name, BackendType)
lowerParam param = do
  ty <- lowerFirstOrderType (paramName param) (paramType param)
  pure (paramName param, ty)

lowerExpr :: Env -> Expr -> ConvertM BackendExpr
lowerExpr env =
  lowerExprWithHint env Nothing

lowerExprWithHint :: Env -> Maybe Name -> Expr -> ConvertM BackendExpr
lowerExprWithHint env preferredName = \case
  EInt n -> do
    atom <- lowerIntAtom n
    pure (BEAtom BI64 atom)
  EBool b ->
    pure (BEAtom BI1 (BBool b))
  EVar name ->
    case Map.lookup name env of
      Just (LocalValue ty) ->
        pure (BEAtom ty (BVar name))
      Just TopFunction {} ->
        throwError (ClosureUnsupportedTopFunctionValue name)
      Nothing ->
        throwError (ClosureUnknownVariable name)
  ELet name rhs body -> do
    rhsExpr <- lowerExprWithHint env (Just name) rhs
    bodyExpr <- lowerExpr (Map.insert name (LocalValue (backendExprType rhsExpr)) env) body
    pure (BELet (backendExprType bodyExpr) name rhsExpr bodyExpr)
  EIf cond thenBranch elseBranch ->
    lowerAtom env cond $ \condAtom condType -> do
      assertType BI1 condType
      thenExpr <- lowerExpr env thenBranch
      elseExpr <- lowerExpr env elseBranch
      assertType (backendExprType thenExpr) (backendExprType elseExpr)
      pure (BEIf (backendExprType thenExpr) condAtom thenExpr elseExpr)
  EBin op lhs rhs ->
    lowerBinOp env op lhs rhs
  ELam name argType body ->
    lowerLambda env preferredName name argType body
  expression@EApp {} ->
    case directTopCall env expression of
      Just (callee, args, paramTypes, returnType) ->
        lowerCallArgs env args [] $ \argAtoms -> do
          if length argAtoms == length paramTypes
            then pure ()
            else throwError (ClosureUnsupportedPartialTopCall callee (length paramTypes) (length argAtoms))
          pure (BECall returnType callee argAtoms)
      Nothing ->
        case topCallArityMismatch env expression of
          Just (callee, expected, actual) ->
            throwError (ClosureUnsupportedPartialTopCall callee expected actual)
          Nothing ->
            lowerApp env expression

lowerBinOp :: Env -> BinOp -> Expr -> Expr -> ConvertM BackendExpr
lowerBinOp env op lhs rhs =
  case op of
    Add ->
      intPrim BPAdd
    Sub ->
      intPrim BPSub
    Mul ->
      intPrim BPMul
    Div ->
      intPrim BPDiv
    Lt ->
      intPrim BPLt
    Eq ->
      equalityPrim
 where
  intPrim prim =
    lowerAtom env lhs $ \lhsAtom lhsType ->
      lowerAtom env rhs $ \rhsAtom rhsType -> do
        requireInt lhsType
        requireInt rhsType
        pure (BEPrim (backendPrimResultType prim) prim lhsAtom rhsAtom)

  equalityPrim =
    lowerAtom env lhs $ \lhsAtom lhsType ->
      lowerAtom env rhs $ \rhsAtom rhsType -> do
        assertType lhsType rhsType
        case lhsType of
          BI64 -> pure (BEPrim BI1 (BPEq BI64) lhsAtom rhsAtom)
          BI1 -> pure (BEPrim BI1 (BPEq BI1) lhsAtom rhsAtom)
          other -> throwError (ClosureTypeMismatch BI64 other)

  requireInt ty =
    if ty == BI64 then pure () else throwError (ClosureExpectedInt op ty)

lowerApp :: Env -> Expr -> ConvertM BackendExpr
lowerApp env (EApp fn arg) =
  lowerAtom env fn $ \fnAtom fnType ->
    lowerAtom env arg $ \argAtom argType ->
      case fnType of
        BClosure expectedArg resultType -> do
          assertType expectedArg argType
          pure (BEApply resultType fnAtom argAtom)
        other ->
          throwError (ClosureExpectedFunction other)
lowerApp _ _ =
  throwError (ClosureExpectedFunction BI64)

lowerLambda :: Env -> Maybe Name -> Name -> Type -> Expr -> ConvertM BackendExpr
lowerLambda env preferredName paramName paramSourceType body = do
  argType <- lowerSourceType paramSourceType
  let captureNames = closureCaptures env paramName body
  captureTypes <- traverse requireLocalCapture captureNames
  codeName <- freshClosureName preferredName
  envName <- freshEnvName
  bodyExpr <- lowerExpr (lambdaBodyEnv envName captureTypes <> Map.insert paramName (LocalValue argType) topOnlyEnv) body
  let returnType = backendExprType bodyExpr
      envType = BEnv (map snd captureTypes)
      function =
        BackendFunction
          { backendFunctionName = codeName
          , backendFunctionParams = [(envName, envType), (paramName, argType)]
          , backendFunctionReturnType = returnType
          , backendFunctionBody = loadCaptures envName (map snd captureTypes) captureTypes bodyExpr
          }
      closureType = BClosure argType returnType
      captures = [(ty, BVar name) | (name, ty) <- captureTypes]
  appendGeneratedFunction function
  pure (BEMakeClosure closureType codeName captures)
 where
  topOnlyEnv =
    Map.filter isTopFunction env

  requireLocalCapture name =
    case Map.lookup name env of
      Just (LocalValue ty) -> pure (name, ty)
      Just TopFunction {} -> throwError (ClosureUnsupportedTopFunctionValue name)
      Nothing -> throwError (ClosureUnknownVariable name)

lambdaBodyEnv :: Name -> [(Name, BackendType)] -> Env
lambdaBodyEnv envName captures =
  Map.fromList ((envName, LocalValue (BEnv (map snd captures))) : [(name, LocalValue ty) | (name, ty) <- captures])

loadCaptures :: Name -> [BackendType] -> [(Name, BackendType)] -> BackendExpr -> BackendExpr
loadCaptures envName envFields captures body =
  foldr loadOne body (zip [0 :: Int ..] captures)
 where
  loadOne (index, (captureName, captureType)) inner =
    BELet
      (backendExprType inner)
      captureName
      (BEEnvGet captureType envFields (BVar envName) index)
      inner

closureCaptures :: Env -> Name -> Expr -> [Name]
closureCaptures env paramName body =
  [ name
  | name <- Set.toAscList (Set.delete paramName (freeVars body))
  , Just LocalValue {} <- [Map.lookup name env]
  ]

isTopFunction :: Binding -> Bool
isTopFunction = \case
  TopFunction {} -> True
  LocalValue {} -> False

lowerAtom :: Env -> Expr -> (BackendAtom -> BackendType -> ConvertM BackendExpr) -> ConvertM BackendExpr
lowerAtom env expression continuation =
  case expression of
    EInt n -> do
      atom <- lowerIntAtom n
      continuation atom BI64
    EBool b ->
      continuation (BBool b) BI1
    EVar name ->
      case Map.lookup name env of
        Just (LocalValue ty) ->
          continuation (BVar name) ty
        Just TopFunction {} ->
          throwError (ClosureUnsupportedTopFunctionValue name)
        Nothing ->
          throwError (ClosureUnknownVariable name)
    _ -> do
      lowered <- lowerExpr env expression
      temp <- freshTempName
      body <- continuation (BVar temp) (backendExprType lowered)
      pure (BELet (backendExprType body) temp lowered body)

lowerCallArgs :: Env -> [Expr] -> [BackendAtom] -> ([BackendAtom] -> ConvertM BackendExpr) -> ConvertM BackendExpr
lowerCallArgs _ [] args continuation =
  continuation (reverse args)
lowerCallArgs env (arg : rest) args continuation =
  lowerAtom env arg $ \argAtom _ ->
    lowerCallArgs env rest (argAtom : args) continuation

directTopCall :: Env -> Expr -> Maybe (Name, [Expr], [BackendType], BackendType)
directTopCall env expression =
  case unwind [] expression of
    (EVar name, args)
      | Just (TopFunction paramTypes returnType) <- Map.lookup name env
      , length args == length paramTypes ->
          Just (name, args, paramTypes, returnType)
    _ ->
      Nothing

topCallArityMismatch :: Env -> Expr -> Maybe (Name, Int, Int)
topCallArityMismatch env expression =
  case unwind [] expression of
    (EVar name, args)
      | Just (TopFunction paramTypes _) <- Map.lookup name env ->
          Just (name, length paramTypes, length args)
    _ ->
      Nothing

unwind :: [Expr] -> Expr -> (Expr, [Expr])
unwind args = \case
  EApp fn arg -> unwind (arg : args) fn
  headExpr -> (headExpr, args)

lowerIntAtom :: Integer -> ConvertM BackendAtom
lowerIntAtom n =
  case mkHIntLiteral n of
    Right value -> pure (BInt value)
    Left err -> throwError (ClosureIntError err)

lowerSourceType :: Type -> ConvertM BackendType
lowerSourceType = \case
  TInt -> pure BI64
  TBool -> pure BI1
  TFun arg result -> BClosure <$> lowerSourceType arg <*> lowerSourceType result

lowerFirstOrderType :: Name -> Type -> ConvertM BackendType
lowerFirstOrderType owner = \case
  TInt -> pure BI64
  TBool -> pure BI1
  ty@TFun {} -> throwError (ClosureCannotLowerTopFunctionType owner ty)

assertType :: BackendType -> BackendType -> ConvertM ()
assertType expected actual =
  (expected == actual) `orThrow` ClosureTypeMismatch expected actual

orThrow :: Bool -> ClosureConvertError -> ConvertM ()
orThrow condition err =
  if condition then pure () else throwError err

freshTempName :: ConvertM Name
freshTempName = freshName "_ct" nextTemp (\n st -> st {nextTemp = n})

freshClosureName :: Maybe Name -> ConvertM Name
freshClosureName preferred =
  freshName ("_closure_" <> maybe "lambda" (sanitizeStem . unName) preferred <> "_") nextClosure (\n st -> st {nextClosure = n})

freshEnvName :: ConvertM Name
freshEnvName =
  freshName "_env" nextEnv (\n st -> st {nextEnv = n})

freshName :: Text -> (ConvertState -> Int) -> (Int -> ConvertState -> ConvertState) -> ConvertM Name
freshName prefix getNext setNext = do
  state <- get
  let candidate = Name (prefix <> Text.pack (show (getNext state)))
  modify' (setNext (getNext state + 1))
  if candidate `Set.member` usedNames state
    then freshName prefix getNext setNext
    else do
      modify' (\st -> st {usedNames = Set.insert candidate (usedNames st)})
      pure candidate

appendGeneratedFunction :: BackendFunction -> ConvertM ()
appendGeneratedFunction function =
  modify' (\state -> state {generatedFunctions = generatedFunctions state <> [function]})

getsGeneratedFunctions :: ConvertM [BackendFunction]
getsGeneratedFunctions =
  generatedFunctions <$> get

freeVars :: Expr -> Set.Set Name
freeVars = \case
  EInt {} -> Set.empty
  EBool {} -> Set.empty
  EVar name -> Set.singleton name
  ELet name rhs body -> freeVars rhs <> Set.delete name (freeVars body)
  EIf cond thenBranch elseBranch -> freeVars cond <> freeVars thenBranch <> freeVars elseBranch
  EBin _ lhs rhs -> freeVars lhs <> freeVars rhs
  ELam name _ body -> Set.delete name (freeVars body)
  EApp fn arg -> freeVars fn <> freeVars arg

collectProgramNames :: Program -> Set.Set Name
collectProgramNames program =
  Set.fromList (map topDefName (programDefs program))
    <> foldMap collectTopDefNames (programDefs program)
    <> collectNames (programMain program)

collectTopDefNames :: TopDef -> Set.Set Name
collectTopDefNames def =
  Set.fromList (map paramName (topDefParams def)) <> collectNames (topDefBody def)

collectNames :: Expr -> Set.Set Name
collectNames = \case
  EInt {} -> Set.empty
  EBool {} -> Set.empty
  EVar name -> Set.singleton name
  ELet name rhs body -> Set.insert name (collectNames rhs <> collectNames body)
  EIf cond thenBranch elseBranch -> collectNames cond <> collectNames thenBranch <> collectNames elseBranch
  EBin _ lhs rhs -> collectNames lhs <> collectNames rhs
  ELam name _ body -> Set.insert name (collectNames body)
  EApp fn arg -> collectNames fn <> collectNames arg

programNeedsClosureRuntime :: Program -> Bool
programNeedsClosureRuntime program =
  any topDefNeedsClosureRuntime (programDefs program) || exprNeedsClosureRuntime Set.empty (programMain program)
 where
  topNames =
    Set.fromList (map topDefName (programDefs program))

  topDefNeedsClosureRuntime def =
    exprNeedsClosureRuntime (Set.fromList (map paramName (topDefParams def))) (topDefBody def)

  exprNeedsClosureRuntime locals = \case
    EInt {} -> False
    EBool {} -> False
    EVar {} -> False
    ELet name rhs body -> exprNeedsClosureRuntime locals rhs || exprNeedsClosureRuntime (Set.insert name locals) body
    EIf cond thenBranch elseBranch ->
      exprNeedsClosureRuntime locals cond || exprNeedsClosureRuntime locals thenBranch || exprNeedsClosureRuntime locals elseBranch
    EBin _ lhs rhs ->
      exprNeedsClosureRuntime locals lhs || exprNeedsClosureRuntime locals rhs
    ELam {} ->
      True
    expression@EApp {} ->
      case unwind [] expression of
        (EVar name, args)
          | name `Set.member` topNames
          , name `Set.notMember` locals ->
              any (exprNeedsClosureRuntime locals) args
        (fn, args) ->
          exprNeedsClosureRuntime locals fn || any (exprNeedsClosureRuntime locals) args || True

sanitizeStem :: Text -> Text
sanitizeStem text =
  let sanitized = Text.map replace text
   in if Text.null sanitized then "lambda" else sanitized
 where
  replace c
    | c >= 'a' && c <= 'z' = c
    | c >= 'A' && c <= 'Z' = c
    | c >= '0' && c <= '9' = c
    | c == '_' = c
    | otherwise = '_'

renderClosureConvertError :: ClosureConvertError -> Text
renderClosureConvertError = \case
  ClosureRootFunctionType ty ->
    "LLVM backend cannot print function-valued root expression of type " <> renderDoc (prettyType ty)
  ClosureUnsupportedTopFunctionValue name ->
    "LLVM backend does not support using top-level function " <> renderDoc (prettyName name) <> " as a closure value"
  ClosureUnsupportedPartialTopCall name expected actual ->
    "LLVM backend requires saturated direct calls to top-level function "
      <> renderDoc (prettyName name)
      <> "; expected "
      <> Text.pack (show expected)
      <> " argument(s), got "
      <> Text.pack (show actual)
  ClosureUnsupportedPrimitive op ->
    "LLVM backend does not support primitive " <> renderDoc (prettyBinOp op)
  ClosureUnknownVariable name ->
    "closure conversion found unknown variable " <> renderDoc (prettyName name)
  ClosureExpectedBool actual ->
    "closure conversion expected Bool, got " <> renderBackendType actual
  ClosureExpectedInt op actual ->
    "closure conversion expected Int operand for " <> renderDoc (prettyBinOp op) <> ", got " <> renderBackendType actual
  ClosureExpectedFunction actual ->
    "closure conversion expected function, got " <> renderBackendType actual
  ClosureTypeMismatch expected actual ->
    "closure conversion type mismatch: expected " <> renderBackendType expected <> ", got " <> renderBackendType actual
  ClosureCannotLowerTopFunctionType name ty ->
    "closure conversion cannot lower top-level function "
      <> renderDoc (prettyName name)
      <> " with function type "
      <> renderDoc (prettyType ty)
  ClosureIntError err ->
    renderIntError err
  ClosureBackendValidationFailed err ->
    renderBackendValidationError err

renderBackendType :: BackendType -> Text
renderBackendType = \case
  BI64 -> "Int"
  BI1 -> "Bool"
  BClosure arg result -> "(" <> renderBackendType arg <> " -> " <> renderBackendType result <> ")"
  BEnv fields -> "env(" <> Text.intercalate ", " (map renderBackendType fields) <> ")"
