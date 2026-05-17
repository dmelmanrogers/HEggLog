module Backend.Compile
  ( CompileLLVMError (..)
  , CompileLLVMOptions (..)
  , LLVMCompileResult (..)
  , LLVMOptimizationStatus (..)
  , compileToLLVM
  , defaultCompileLLVMOptions
  , renderCompileLLVMError
  , renderLLVMOptimizationStatus
  )
where

import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Backend.IR
import Backend.LambdaLift
import Backend.LLVM.Emit
import Backend.LLVM.IR
import Backend.LLVM.Lower
import Backend.Lower
import IR.ANF
import IR.ANF.Validate
import Optimize.EgglogBackend
import qualified Egglog.Eval as Egglog
import Syntax.AST (BinOp (..), Name, Param (..), Program, Type)
import Syntax.Located
  ( LocatedExpr
  , LocatedExprNode (..)
  , LocatedParam (..)
  , LocatedProgram (..)
  , LocatedTopDef (..)
  , locatedExprNode
  , locatedExprSpan
  , stripLocatedProgram
  )
import Syntax.Parser (parseLocatedSourceProgram)
import Syntax.Pretty (prettyName, prettyType, renderDoc)
import Syntax.Span (SourceSpan, renderSourceDiagnostic)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (inferLocatedProgram)
import Typecheck.Types (LocatedTypeError, renderLocatedTypeError)

data CompileLLVMOptions = CompileLLVMOptions
  { compileUseEgglog :: Bool
  }
  deriving stock (Show, Eq, Ord)

defaultCompileLLVMOptions :: CompileLLVMOptions
defaultCompileLLVMOptions =
  CompileLLVMOptions
    { compileUseEgglog = True
    }

data LLVMOptimizationStatus
  = LLVMOptimizationDisabled
  | LLVMOptimizationApplied EgglogOptimizationResult
  | LLVMOptimizationUnsupported EgglogBackendError
  deriving stock (Show, Eq)

data LLVMCompileResult = LLVMCompileResult
  { llvmParsed :: Program
  , llvmSourceType :: Type
  , llvmOriginalANF :: AProgram
  , llvmSelectedANF :: AProgram
  , llvmOptimizationStatus :: LLVMOptimizationStatus
  , llvmBackendProgram :: BackendProgram
  , llvmModule :: LLVMModule
  , llvmText :: Text
  }
  deriving stock (Show, Eq)

data CompileLLVMError
  = LLVMCompileParseError Text
  | LLVMCompileTypeError LocatedTypeError
  | LLVMCompileUnsupportedSource SourceSpan Text
  | LLVMCompileInvalidANF ANFValidationError
  | LLVMCompileEgglogFailed EgglogBackendError
  | LLVMCompileBackendLowerError BackendLowerError
  | LLVMCompileLowerError LLVMLowerError
  deriving stock (Show, Eq)

compileToLLVM :: CompileLLVMOptions -> FilePath -> Text -> Either CompileLLVMError LLVMCompileResult
compileToLLVM options path source = do
  parsed <-
    case parseLocatedSourceProgram path source of
      Left parseError -> Left (LLVMCompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  inferredType <- mapLeft LLVMCompileTypeError (inferLocatedProgram parsed)
  lifted <-
    case lambdaLiftLocatedProgram parsed of
      Left err ->
        let (sourceRange, message) = lambdaLiftErrorDiagnostic err
         in Left (LLVMCompileUnsupportedSource sourceRange message)
      Right program -> Right program
  _ <- mapLeft LLVMCompileTypeError (inferLocatedProgram lifted)
  case findLLVMUnsupported lifted of
    Just (sourceRange, message) -> Left (LLVMCompileUnsupportedSource sourceRange message)
    Nothing -> Right ()
  let stripped = stripLocatedProgram lifted
      anf = toANFProgram stripped
  mapLeft LLVMCompileInvalidANF (validateANFProgram anf)
  (selectedANF, optimizationStatus) <- selectANFProgram options anf
  mapLeft LLVMCompileInvalidANF (validateANFProgram selectedANF)
  backend <- mapLeft LLVMCompileBackendLowerError (lowerANFProgramToBackend selectedANF)
  llvmModule0 <- mapLeft LLVMCompileLowerError (lowerBackendToLLVM backend)
  let llvmModule1 =
        llvmModule0
          { moduleComments =
              moduleComments llvmModule0
                <> [ "source type: " <> renderDoc (prettyType inferredType)
                   , renderLLVMOptimizationStatus optimizationStatus
                   ]
          }
      emitted = emitLLVMModule llvmModule1
  pure
    LLVMCompileResult
      { llvmParsed = stripped
      , llvmSourceType = inferredType
      , llvmOriginalANF = anf
      , llvmSelectedANF = selectedANF
      , llvmOptimizationStatus = optimizationStatus
      , llvmBackendProgram = backend
      , llvmModule = llvmModule1
      , llvmText = emitted
      }

selectANFProgram :: CompileLLVMOptions -> AProgram -> Either CompileLLVMError (AProgram, LLVMOptimizationStatus)
selectANFProgram options program@(AProgram defs mainExpr)
  | null defs = do
      (selectedMain, status) <- selectANF options mainExpr
      pure (AProgram [] selectedMain, status)
  | not (compileUseEgglog options) =
      Right (program, LLVMOptimizationDisabled)
  | otherwise =
      Right
        ( program
        , LLVMOptimizationUnsupported (ReconstructedTypeError "top-level or lambda-lifted definitions are outside the Egglog optimizer fragment")
        )

selectANF :: CompileLLVMOptions -> AExpr -> Either CompileLLVMError (AExpr, LLVMOptimizationStatus)
selectANF options anf
  | not (compileUseEgglog options) =
      Right (anf, LLVMOptimizationDisabled)
  | otherwise =
      case tryOptimizeWithEgglog Egglog.defaultRunConfig anf of
        EgglogOptimized result ->
          Right (optimizedANF result, LLVMOptimizationApplied result)
        EgglogUnsupported err ->
          Right (anf, LLVMOptimizationUnsupported err)
        EgglogFailed err ->
          Left (LLVMCompileEgglogFailed err)

renderCompileLLVMError :: CompileLLVMError -> Text
renderCompileLLVMError = \case
  LLVMCompileParseError parseError ->
    "parse error:\n" <> parseError
  LLVMCompileTypeError typeError ->
    renderLocatedTypeError typeError
  LLVMCompileUnsupportedSource sourceRange message ->
    renderSourceDiagnostic sourceRange "LLVM backend unsupported" message
  LLVMCompileInvalidANF err ->
    "invalid ANF before LLVM compilation: " <> renderANFValidationError err
  LLVMCompileEgglogFailed err ->
    "Egglog optimization failed before LLVM compilation: " <> renderEgglogBackendError err
  LLVMCompileBackendLowerError err ->
    renderBackendLowerError err
  LLVMCompileLowerError err ->
    renderLLVMLowerError err

renderLLVMOptimizationStatus :: LLVMOptimizationStatus -> Text
renderLLVMOptimizationStatus = \case
  LLVMOptimizationDisabled ->
    "egglog: disabled"
  LLVMOptimizationApplied result ->
    "egglog: optimized; cost " <> Text.pack (show (originalCost (extractionStats result))) <> " -> " <> Text.pack (show (optimizedCost (extractionStats result)))
  LLVMOptimizationUnsupported err ->
    "egglog: unsupported; using unoptimized ANF; reason: " <> renderEgglogBackendError err

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left value -> Left (f value)
  Right value -> Right value

findLLVMUnsupported :: LocatedProgram -> Maybe (SourceSpan, Text)
findLLVMUnsupported program =
  firstJust (map (findTopDefUnsupported arities) (locatedProgramDefs program) <> [findExprUnsupported arities Set.empty (locatedProgramMain program)])
 where
  arities =
    Map.fromList [(locatedTopDefName def, length (locatedTopDefParams def)) | def <- locatedProgramDefs program]

findTopDefUnsupported :: Map.Map Name Int -> LocatedTopDef -> Maybe (SourceSpan, Text)
findTopDefUnsupported arities def =
  findExprUnsupported arities localNames (locatedTopDefBody def)
 where
  localNames =
    Set.fromList (map locatedParamName (locatedTopDefParams def))

locatedParamName :: LocatedParam -> Name
locatedParamName (LocatedParam _ param) =
  paramName param

findExprUnsupported :: Map.Map Name Int -> Set.Set Name -> LocatedExpr -> Maybe (SourceSpan, Text)
findExprUnsupported arities localNames expr =
  case locatedExprNode expr of
    LInt _ ->
      Nothing
    LBool _ ->
      Nothing
    LVar name
      | name `Map.member` arities && name `Set.notMember` localNames ->
          Just (locatedExprSpan expr, topFunctionValueMessage name)
      | otherwise ->
          Nothing
    LLet name rhs body ->
      firstJust [findExprUnsupported arities localNames rhs, findExprUnsupported arities (Set.insert name localNames) body]
    LIf cond thenBranch elseBranch ->
      firstJust
        [ findExprUnsupported arities localNames cond
        , findExprUnsupported arities localNames thenBranch
        , findExprUnsupported arities localNames elseBranch
        ]
    LBin Div lhs rhs ->
      firstJust
        [ findExprUnsupported arities localNames lhs
        , findExprUnsupported arities localNames rhs
        , Just (locatedExprSpan expr, "LLVM backend does not support division")
        ]
    LBin _ lhs rhs ->
      firstJust [findExprUnsupported arities localNames lhs, findExprUnsupported arities localNames rhs]
    LLam {} ->
      Just (locatedExprSpan expr, "LLVM backend does not support lambda expressions")
    LApp fn arg ->
      case locatedDirectTopCall arities localNames expr of
        Just (callee, args, expectedArity)
          | length args == expectedArity ->
              firstJust (map (findExprUnsupported arities localNames) args)
          | otherwise ->
              firstJust
                ( map (findExprUnsupported arities localNames) args
                    <> [Just (locatedExprSpan expr, saturatedCallMessage callee expectedArity (length args))]
                )
        Nothing ->
          firstJust
            [ findExprUnsupported arities localNames fn
            , findExprUnsupported arities localNames arg
            , Just (locatedExprSpan expr, "LLVM backend only supports saturated direct calls to top-level functions")
            ]

locatedDirectTopCall :: Map.Map Name Int -> Set.Set Name -> LocatedExpr -> Maybe (Name, [LocatedExpr], Int)
locatedDirectTopCall arities localNames expression =
  case unwind [] expression of
    (headExpr, args) ->
      case locatedExprNode headExpr of
        LVar name
          | name `Set.notMember` localNames
          , Just arity <- Map.lookup name arities
          , not (null args) ->
              Just (name, args, arity)
        _ ->
          Nothing
 where
  unwind args current =
    case locatedExprNode current of
      LApp fn arg -> unwind (arg : args) fn
      _ -> (current, args)

saturatedCallMessage :: Name -> Int -> Int -> Text
saturatedCallMessage name expected actual =
  "LLVM backend requires saturated direct calls to top-level function "
    <> renderDoc (prettyName name)
    <> "; expected "
    <> Text.pack (show expected)
    <> " argument(s), got "
    <> Text.pack (show actual)

topFunctionValueMessage :: Name -> Text
topFunctionValueMessage name =
  "LLVM backend does not support using top-level function "
    <> renderDoc (prettyName name)
    <> " as a value"

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Nothing : rest -> firstJust rest
  Just value : _ -> Just value
