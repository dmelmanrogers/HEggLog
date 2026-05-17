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
import qualified Data.Text as Text
import Backend.IR
import Backend.LLVM.Emit
import Backend.LLVM.IR
import Backend.LLVM.Lower
import Backend.Lower
import IR.ANF
import IR.ANF.Validate
import Optimize.EgglogBackend
import qualified Egglog.Eval as Egglog
import Syntax.AST (BinOp (..), Expr, Type)
import Syntax.Located
  ( LocatedExpr
  , LocatedExprNode (..)
  , locatedExprNode
  , locatedExprSpan
  , stripLocatedExpr
  )
import Syntax.Parser (parseLocatedProgram)
import Syntax.Pretty (prettyType, renderDoc)
import Syntax.Span (SourceSpan, renderSourceDiagnostic)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (inferLocated)
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
  { llvmParsed :: Expr
  , llvmSourceType :: Type
  , llvmOriginalANF :: AExpr
  , llvmSelectedANF :: AExpr
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
    case parseLocatedProgram path source of
      Left parseError -> Left (LLVMCompileParseError (Text.pack (errorBundlePretty parseError)))
      Right expr -> Right expr
  inferredType <- mapLeft LLVMCompileTypeError (inferLocated parsed)
  case findLLVMUnsupported parsed of
    Just (sourceRange, message) -> Left (LLVMCompileUnsupportedSource sourceRange message)
    Nothing -> Right ()
  let stripped = stripLocatedExpr parsed
      anf = toANF stripped
  mapLeft LLVMCompileInvalidANF (validateANF anf)
  (selectedANF, optimizationStatus) <- selectANF options anf
  mapLeft LLVMCompileInvalidANF (validateANF selectedANF)
  backend <- mapLeft LLVMCompileBackendLowerError (lowerANFToBackend selectedANF)
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

findLLVMUnsupported :: LocatedExpr -> Maybe (SourceSpan, Text)
findLLVMUnsupported expr =
  case locatedExprNode expr of
    LInt _ ->
      Nothing
    LBool _ ->
      Nothing
    LVar _ ->
      Nothing
    LLet _ rhs body ->
      firstJust [findLLVMUnsupported rhs, findLLVMUnsupported body]
    LIf cond thenBranch elseBranch ->
      firstJust [findLLVMUnsupported cond, findLLVMUnsupported thenBranch, findLLVMUnsupported elseBranch]
    LBin Div lhs rhs ->
      firstJust
        [ findLLVMUnsupported lhs
        , findLLVMUnsupported rhs
        , Just (locatedExprSpan expr, "LLVM backend does not support division")
        ]
    LBin _ lhs rhs ->
      firstJust [findLLVMUnsupported lhs, findLLVMUnsupported rhs]
    LLam {} ->
      Just (locatedExprSpan expr, "LLVM backend does not support lambda expressions")
    LApp fn arg ->
      firstJust
        [ findLLVMUnsupported fn
        , findLLVMUnsupported arg
        , Just (locatedExprSpan expr, "LLVM backend does not support function application")
        ]

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Nothing : rest -> firstJust rest
  Just value : _ -> Just value
