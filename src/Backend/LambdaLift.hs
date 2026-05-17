module Backend.LambdaLift
  ( LambdaLiftError (..)
  , lambdaLiftLocatedProgram
  , lambdaLiftErrorDiagnostic
  )
where

import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.State.Strict (State, evalState, get, modify')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Syntax.AST
import Syntax.Located
import Syntax.Pretty (prettyName, prettyType, renderDoc)
import Syntax.Span (SourceSpan)
import Typecheck.Infer (inferLocatedWithEnv)
import Typecheck.Types (TypeEnv, locatedTypeErrorDetail, renderTypeError)

data LambdaLiftError
  = CapturingLambda SourceSpan [Name]
  | UnsupportedLambdaType SourceSpan Type
  | LiftedLambdaTypeError SourceSpan Text
  deriving stock (Show, Eq)

data LiftContext = LiftContext
  { contextTopTypes :: TypeEnv
  , contextAliases :: Map.Map Name Name
  }
  deriving stock (Show, Eq)

data LiftState = LiftState
  { nextLiftId :: Int
  , usedNames :: Set.Set Name
  }
  deriving stock (Show, Eq)

type LiftM = ExceptT LambdaLiftError (State LiftState)

lambdaLiftLocatedProgram :: LocatedProgram -> Either LambdaLiftError LocatedProgram
lambdaLiftLocatedProgram program =
  evalState (runExceptT (liftProgram program)) initialState
 where
  initialState =
    LiftState
      { nextLiftId = 0
      , usedNames = collectProgramNames program
      }

liftProgram :: LocatedProgram -> LiftM LocatedProgram
liftProgram program = do
  (topTypes, defs) <- liftTopDefs Map.empty (locatedProgramDefs program)
  (mainLiftedDefs, mainExpr) <- liftExpr LiftContext {contextTopTypes = topTypes, contextAliases = Map.empty} (locatedProgramMain program)
  pure
    LocatedProgram
      { locatedProgramDefs = defs <> mainLiftedDefs
      , locatedProgramMain = mainExpr
      }

liftTopDefs :: TypeEnv -> [LocatedTopDef] -> LiftM (TypeEnv, [LocatedTopDef])
liftTopDefs topTypes = \case
  [] ->
    pure (topTypes, [])
  def : rest -> do
    let context =
          LiftContext
            { contextTopTypes = topTypes
            , contextAliases = Map.empty
            }
    (liftedDefs, body) <- liftExpr context (locatedTopDefBody def)
    let transformedDef =
          def {locatedTopDefBody = body}
        topTypes' =
          topTypes
            <> locatedTopDefTypes liftedDefs
            <> Map.singleton (locatedTopDefName transformedDef) (locatedTopDefType transformedDef)
    (finalTopTypes, restDefs) <- liftTopDefs topTypes' rest
    pure (finalTopTypes, liftedDefs <> [transformedDef] <> restDefs)

liftExpr :: LiftContext -> LocatedExpr -> LiftM ([LocatedTopDef], LocatedExpr)
liftExpr context expr@(LocatedExpr sourceRange node) =
  case node of
    LInt {} ->
      pure ([], expr)
    LBool {} ->
      pure ([], expr)
    LVar name ->
      pure ([], LocatedExpr sourceRange (LVar (Map.findWithDefault name name (contextAliases context))))
    LLet name rhs body ->
      case lambdaChain rhs of
        Just chain -> do
          (liftedDefs, liftedName) <- liftLambdaChain context (Just name) (locatedExprSpan rhs) chain
          let bodyContext =
                context
                  { contextTopTypes = contextTopTypes context <> locatedTopDefTypes liftedDefs
                  , contextAliases = Map.insert name liftedName (contextAliases context)
                  }
          (bodyDefs, bodyExpr) <- liftExpr bodyContext body
          pure (liftedDefs <> bodyDefs, bodyExpr)
        Nothing -> do
          (rhsDefs, rhsExpr) <- liftExpr context rhs
          let bodyContext =
                context
                  { contextTopTypes = contextTopTypes context <> locatedTopDefTypes rhsDefs
                  , contextAliases = Map.delete name (contextAliases context)
                  }
          (bodyDefs, bodyExpr) <- liftExpr bodyContext body
          pure (rhsDefs <> bodyDefs, LocatedExpr sourceRange (LLet name rhsExpr bodyExpr))
    LIf cond thenBranch elseBranch -> do
      (condDefs, condExpr) <- liftExpr context cond
      (thenDefs, thenExpr) <- liftExpr (extendTopTypes condDefs context) thenBranch
      (elseDefs, elseExpr) <- liftExpr (extendTopTypes (condDefs <> thenDefs) context) elseBranch
      pure (condDefs <> thenDefs <> elseDefs, LocatedExpr sourceRange (LIf condExpr thenExpr elseExpr))
    LBin op lhs rhs -> do
      (lhsDefs, lhsExpr) <- liftExpr context lhs
      (rhsDefs, rhsExpr) <- liftExpr (extendTopTypes lhsDefs context) rhs
      pure (lhsDefs <> rhsDefs, LocatedExpr sourceRange (LBin op lhsExpr rhsExpr))
    LLam {} ->
      pure ([], expr)
    LApp fn arg -> do
      (fnDefs, fnExpr) <-
        case lambdaChain fn of
          Just chain -> do
            (liftedDefs, liftedName) <- liftLambdaChain context Nothing (locatedExprSpan fn) chain
            pure (liftedDefs, LocatedExpr (locatedExprSpan fn) (LVar liftedName))
          Nothing ->
            liftExpr context fn
      (argDefs, argExpr) <- liftExpr (extendTopTypes fnDefs context) arg
      pure (fnDefs <> argDefs, LocatedExpr sourceRange (LApp fnExpr argExpr))

extendTopTypes :: [LocatedTopDef] -> LiftContext -> LiftContext
extendTopTypes defs context =
  context {contextTopTypes = contextTopTypes context <> locatedTopDefTypes defs}

data LambdaChain = LambdaChain
  { chainParams :: [LocatedParam]
  , chainBody :: LocatedExpr
  }
  deriving stock (Show, Eq)

lambdaChain :: LocatedExpr -> Maybe LambdaChain
lambdaChain =
  go []
 where
  go params (LocatedExpr sourceRange node) =
    case node of
      LLam name ty body ->
        go (params <> [LocatedParam sourceRange (Param name ty)]) body
      _ | null params -> Nothing
      _ -> Just LambdaChain {chainParams = params, chainBody = LocatedExpr sourceRange node}

liftLambdaChain :: LiftContext -> Maybe Name -> SourceSpan -> LambdaChain -> LiftM ([LocatedTopDef], Name)
liftLambdaChain context preferredName sourceRange chain = do
  mapM_ rejectFunctionParam params
  let paramNames = map paramName params
      lambdaContext =
        context
          { contextAliases = foldr Map.delete (contextAliases context) paramNames
          }
  (bodyDefs, liftedBody) <- liftExpr lambdaContext (chainBody chain)
  let topTypes = contextTopTypes context <> locatedTopDefTypes bodyDefs
      paramTypes = Map.fromList [(paramName param, paramType param) | param <- params]
      inferEnv = paramTypes <> topTypes
      captured =
        Set.toAscList (freeVars liftedBody `Set.difference` (Set.fromList paramNames <> Map.keysSet topTypes))
  case captured of
    [] -> pure ()
    _ -> throwError (CapturingLambda sourceRange captured)
  returnType <-
    case inferLocatedWithEnv inferEnv liftedBody of
      Left err ->
        throwError (LiftedLambdaTypeError sourceRange (renderTypeError (locatedTypeErrorDetail err)))
      Right ty ->
        pure ty
  rejectFunctionType sourceRange returnType
  liftName <- freshLiftName preferredName
  let def =
        LocatedTopDef
          { locatedTopDefSpan = sourceRange
          , locatedTopDefName = liftName
          , locatedTopDefParams = chainParams chain
          , locatedTopDefReturnType = returnType
          , locatedTopDefBody = liftedBody
          }
  pure (bodyDefs <> [def], liftName)
 where
  params =
    [param | LocatedParam _ param <- chainParams chain]
  rejectFunctionParam (Param _ ty) =
    rejectFunctionType sourceRange ty

rejectFunctionType :: SourceSpan -> Type -> LiftM ()
rejectFunctionType sourceRange = \case
  ty@TFun {} ->
    throwError (UnsupportedLambdaType sourceRange ty)
  TInt ->
    pure ()
  TBool ->
    pure ()

freshLiftName :: Maybe Name -> LiftM Name
freshLiftName preferredName = do
  state <- get
  let stem = maybe "lambda" (sanitizeStem . unName) preferredName
      candidate = Name ("_lift_" <> stem <> "_" <> Text.pack (show (nextLiftId state)))
  modify' (\st -> st {nextLiftId = nextLiftId st + 1})
  if candidate `Set.member` usedNames state
    then freshLiftName preferredName
    else do
      modify' (\st -> st {usedNames = Set.insert candidate (usedNames st)})
      pure candidate

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

freeVars :: LocatedExpr -> Set.Set Name
freeVars (LocatedExpr _ node) =
  case node of
    LInt {} ->
      Set.empty
    LBool {} ->
      Set.empty
    LVar name ->
      Set.singleton name
    LLet name rhs body ->
      freeVars rhs <> Set.delete name (freeVars body)
    LIf cond thenBranch elseBranch ->
      freeVars cond <> freeVars thenBranch <> freeVars elseBranch
    LBin _ lhs rhs ->
      freeVars lhs <> freeVars rhs
    LLam name _ body ->
      Set.delete name (freeVars body)
    LApp fn arg ->
      freeVars fn <> freeVars arg

locatedTopDefTypes :: [LocatedTopDef] -> TypeEnv
locatedTopDefTypes =
  Map.fromList . map (\def -> (locatedTopDefName def, locatedTopDefType def))

locatedTopDefType :: LocatedTopDef -> Type
locatedTopDefType def =
  foldr TFun (locatedTopDefReturnType def) [paramType param | LocatedParam _ param <- locatedTopDefParams def]

collectProgramNames :: LocatedProgram -> Set.Set Name
collectProgramNames program =
  foldMap collectTopDefNames (locatedProgramDefs program) <> collectNames (locatedProgramMain program)

collectTopDefNames :: LocatedTopDef -> Set.Set Name
collectTopDefNames def =
  Set.singleton (locatedTopDefName def)
    <> Set.fromList [paramName param | LocatedParam _ param <- locatedTopDefParams def]
    <> collectNames (locatedTopDefBody def)

collectNames :: LocatedExpr -> Set.Set Name
collectNames (LocatedExpr _ node) =
  case node of
    LInt {} ->
      Set.empty
    LBool {} ->
      Set.empty
    LVar name ->
      Set.singleton name
    LLet name rhs body ->
      Set.insert name (collectNames rhs <> collectNames body)
    LIf cond thenBranch elseBranch ->
      collectNames cond <> collectNames thenBranch <> collectNames elseBranch
    LBin _ lhs rhs ->
      collectNames lhs <> collectNames rhs
    LLam name _ body ->
      Set.insert name (collectNames body)
    LApp fn arg ->
      collectNames fn <> collectNames arg

lambdaLiftErrorDiagnostic :: LambdaLiftError -> (SourceSpan, Text)
lambdaLiftErrorDiagnostic = \case
  CapturingLambda sourceRange captured ->
    ( sourceRange
    , "LLVM backend cannot lambda lift capturing lambda; captured variables: "
        <> Text.intercalate ", " (map (renderDoc . prettyName) captured)
    )
  UnsupportedLambdaType sourceRange ty ->
    ( sourceRange
    , "LLVM backend lambda lifting only supports first-order Int/Bool parameters and results, got "
        <> renderDoc (prettyType ty)
    )
  LiftedLambdaTypeError sourceRange message ->
    (sourceRange, "LLVM backend could not typecheck lifted lambda: " <> message)
