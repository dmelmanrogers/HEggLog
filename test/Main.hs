module Main (main) where

import Analysis.Facts
import Analysis.InferFacts (inferFacts)
import qualified Backend.Compile as BC
import qualified Backend.IR as B
import qualified Backend.LLVM.IR as LIR
import qualified Backend.LLVM.Toolchain as LLVMTools
import qualified Backend.LLVM.Validate as LV
import qualified Backend.Lower as BL
import qualified Backend.Validate as BV
import qualified CLI.Compile as CompileCLI
import CLI.Report (CompileError (..), CompileReport (..), compileReport, renderCompileError, renderGoldenReport)
import Control.Monad (unless, when)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import qualified Egglog.Database as EDB
import qualified Egglog.Eval as EEV
import qualified Egglog.Extract as EEX
import qualified Egglog.Function as EF
import qualified Egglog.Pattern as EP
import qualified Egglog.Rebuild as ERB
import qualified Egglog.Rule as ER
import qualified Egglog.Sort as ES
import qualified Egglog.Value as EV
import Eval.ANFInterpreter (ANFValue (..), evalANF)
import Eval.Interpreter (RuntimeError (..), Value (..), eval, evalProgram, renderRuntimeError, renderValue)
import qualified Haskell2010.Core.FreeVars as H2010CoreFreeVars
import qualified Haskell2010.Core.Eval as H2010CoreEval
import qualified Haskell2010.Core.Pretty as H2010CorePretty
import qualified Haskell2010.Core.Subst as H2010CoreSubst
import qualified Haskell2010.Core.Syntax as H2010Core
import qualified Haskell2010.Core.Validate as H2010CoreValidate
import qualified Haskell2010.ModuleGraph as H2010ModuleGraph
import qualified Haskell2010.Names as H2010Names
import qualified Haskell2010.Native as H2010Native
import qualified Haskell2010.Parser as H2010Parser
import qualified Haskell2010.Renamed as H2010Renamed
import qualified Haskell2010.Renamer as H2010Renamer
import qualified Haskell2010.STG.Eval as H2010STGEval
import qualified Haskell2010.STG.Lower as H2010STGLower
import qualified Haskell2010.STG.Syntax as H2010STG
import qualified Haskell2010.STG.Validate as H2010STGValidate
import qualified Haskell2010.Syntax as H2010
import qualified Haskell2010.Typecheck as H2010Typecheck
import IR.ANF
import qualified IR.ANF.Resolved as RANF
import IR.ANF.Validate
import IR.Core (CoreNode (..), CoreProgram (..), lower)
import qualified Optimize.EgglogBackend as OEB
import qualified Optimize.EgglogBackend.Rules as OER
import qualified Optimize.EgglogBackend.Schema as OES
import qualified Optimize.CoreEgglog as H2010CoreEgglog
import qualified Optimize.EGraph as EG
import Optimize.Rewrite
  ( RewriteDiagnostic (..)
  , RewriteRule (rewriteConditions)
  , checkRewriteConditions
  , divideSelfNonZero
  , matchRewriteRule
  )
import Optimize.Simplify
import Runtime.Int (HInt, IntError (IntOverflow), hintToInteger, maxHIntInteger, minHIntInteger, unsafeHIntLiteral)
import Syntax.AST
import Syntax.Parser (parseProgram, parseSourceProgram)
import Syntax.Span (SourceSpan (..))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, removePathForcibly)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import Test.QuickCheck hiding (NonZero, label)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (infer, inferProgram)
import qualified Typecheck.Principal as Principal
import Typecheck.Types (LocatedTypeError (..), TypeError (..), renderTypeError)

data TestGroup = TestGroup String [Test]

data Test = Test String (IO (Either String ()))

main :: IO ()
main = do
  results <- traverse runGroup testGroups
  let failures =
        [ (groupName, testName, message)
        | (groupName, groupResults) <- results
        , (testName, Left message) <- groupResults
        ]
  unless (null failures) $ do
    putStrLn ""
    putStrLn "Failures:"
    mapM_ printFailure failures
    exitFailure

testGroups :: [TestGroup]
testGroups =
  [ TestGroup
      "Parser"
      [ pureTest "application binds tighter than addition" testApplicationPrecedence
      , pureTest "parentheses group application arguments" testParenthesizedArgument
      , pureTest "top-level function program parses" testTopLevelFunctionParsing
      , pureTest "Haskell 2010 module header, imports, and declarations parse" testHaskell2010ModuleParsing
      , pureTest "Haskell 2010 layout blocks parse" testHaskell2010LayoutParsing
      , pureTest "Haskell 2010 expression surface forms parse" testHaskell2010ExpressionSurfaceParsing
      , pureTest "Haskell 2010 record field syntax parses" testHaskell2010RecordFieldSyntaxParsing
      , pureTest "Haskell 2010 malformed layout is rejected" testHaskell2010MalformedLayout
      , pureTest "Haskell 2010 imports after declarations are rejected" testHaskell2010ImportAfterDecl
      ]
  , TestGroup
      "Haskell 2010 Renamer"
      [ pureTest "resolves lexical shadowing to unique names" testHaskell2010RenamerShadowing
      , pureTest "rejects duplicate top-level bindings" testHaskell2010RenamerDuplicateTopLevel
      , pureTest "rejects unbound variables" testHaskell2010RenamerUnboundVariable
      , pureTest "separates term constructor type and class namespaces" testHaskell2010RenamerNamespaces
      , pureTest "scopes pattern binders over guarded RHS" testHaskell2010RenamerPatternScope
      , pureTest "resolves right-associative fixity" testHaskell2010RenamerRightAssociativeFixity
      , pureTest "resolves operator precedence" testHaskell2010RenamerFixityPrecedence
      , pureTest "rejects chained non-associative operators" testHaskell2010RenamerNonAssociativeFixity
      , pureTest "detects ambiguous explicit imports" testHaskell2010RenamerAmbiguousImport
      , pureTest "resolves qualified explicit imports" testHaskell2010RenamerQualifiedImport
      , pureTest "resolves module graph imports through exports" testHaskell2010RenamerModuleGraphExports
      , ioTest "detects module graph import cycles" testHaskell2010ModuleGraphCycle
      ]
  , TestGroup
      "Haskell 2010 Core"
      [ pureTest "validates typed identity lambda" testHaskell2010CoreValidIdentity
      , pureTest "rejects application argument mismatch" testHaskell2010CoreAppMismatch
      , pureTest "rejects unbound variables" testHaskell2010CoreUnboundVariable
      , pureTest "validates let scope and rejects duplicate binders" testHaskell2010CoreLetScopeAndDuplicates
      , pureTest "validates recursive binding scope" testHaskell2010CoreRecursiveScope
      , pureTest "checks case alternative result types" testHaskell2010CoreCaseAlternativeMismatch
      , pureTest "computes free variables through binders" testHaskell2010CoreFreeVariables
      , pureTest "substitution avoids bound variables" testHaskell2010CoreSubstitution
      , pureTest "renders stable typed Core text" testHaskell2010CorePretty
      ]
  , TestGroup
      "Haskell 2010 Core-0 Typechecker"
      [ pureTest "represents type constructor kinds" testHaskell2010KindRepresentation
      , pureTest "infers higher-kinded type constructors" testHaskell2010KindChecksHigherKindedConstructors
      , pureTest "rejects kind-mismatched source types" testHaskell2010KindRejectsMismatch
      , pureTest "expands type synonyms" testHaskell2010TypeSynonymExpansion
      , pureTest "infers higher-kinded type synonym parameters" testHaskell2010TypeSynonymKindInference
      , pureTest "rejects recursive type synonyms" testHaskell2010TypeSynonymRejectsCycles
      , pureTest "typechecks newtype constructors and patterns" testHaskell2010NewtypeTyping
      , pureTest "erases newtype constructors to Core coercions" testHaskell2010NewtypeRepresentation
      , pureTest "infers higher-kinded newtype parameters" testHaskell2010NewtypeKindInference
      , pureTest "rejects invalid newtype constructor arity" testHaskell2010NewtypeRejectsInvalidArity
      , pureTest "typechecks record field labels selectors and patterns" testHaskell2010RecordFieldLabels
      , pureTest "rejects incomplete record construction" testHaskell2010RecordRejectsIncompleteConstruction
      , pureTest "typechecks irrefutable lazy patterns" testHaskell2010IrrefutablePatterns
      , pureTest "forces irrefutable patterns only through demanded binders" testHaskell2010IrrefutablePatternDemand
      , pureTest "represents class constraints structurally" testHaskell2010ConstraintRepresentation
      , pureTest "rejects invalid class constraint arity" testHaskell2010ConstraintRejectsInvalidArity
      , pureTest "rejects unsupported class constraint contexts deliberately" testHaskell2010ClassConstraintPlaceholders
      , pureTest "typechecks explicit polymorphic identity" testHaskell2010Core0Identity
      , pureTest "typechecks explicit polymorphic const" testHaskell2010Core0Const
      , pureTest "generalizes local let polymorphism" testHaskell2010Core0PolymorphicLet
      , pureTest "desugars if to Bool case Core" testHaskell2010Core0If
      , pureTest "desugars explicit Bool case Core" testHaskell2010Core0Case
      , pureTest "typechecks user ADT constructor cases" testHaskell2010Core0ADTConstructorCase
      , pureTest "typechecks nested constructor patterns" testHaskell2010Core0NestedADTPatterns
      , pureTest "typechecks lists tuples and Prelude constructors" testHaskell2010Core0PreludeData
      , pureTest "typechecks recursive bindings" testHaskell2010Core0Recursion
      , pureTest "typechecks recursive pattern bindings" testHaskell2010RecursivePatternBindings
      , pureTest "typechecks type class dictionaries" testHaskell2010Core0TypeClassDictionaries
      , pureTest "typechecks Prelude class dictionaries" testHaskell2010Core0PreludeClassDictionaries
      , pureTest "typechecks Char runtime representation" testHaskell2010Core0CharRuntime
      , pureTest "typechecks String as Char lists" testHaskell2010Core0StringCharList
      , pureTest "typechecks fromInteger and numeric defaulting" testHaskell2010Core0NumericDefaulting
      , pureTest "documents monomorphism restriction defaulting policy" testHaskell2010MonomorphismRestrictionDefaulting
      , pureTest "typechecks multi-module imports" testHaskell2010Core0MultiModuleImports
      , pureTest "typechecks IO printing" testHaskell2010Core0IOPrinting
      , pureTest "typechecks guards and as-patterns" testHaskell2010Core0GuardsAndAsPatterns
      , pureTest "desugars operator sections to Core lambdas" testHaskell2010Core0Sections
      , pureTest "rejects invalid type class dictionaries" testHaskell2010Core0RejectsInvalidTypeClassDictionaries
      , pureTest "rejects ill-typed Core-0 source" testHaskell2010Core0TypeError
      , pureTest "renders Haskell 2010 type errors with source spans" testHaskell2010TypeErrorDiagnosticsWithSpans
      , pureTest "records Haskell 2010 exhaustiveness warning placeholders" testHaskell2010ExhaustivenessWarningPlaceholders
      , ioTest "property-checks generated Haskell 2010 inference programs" $
          checkProperty propHaskell2010InferenceValidPrograms
      , ioTest "property-checks generated Haskell 2010 dictionary inference programs" $
          checkProperty propHaskell2010DictionaryInferencePrograms
      , ioTest "property-checks generated Haskell 2010 inference failures" $
          checkProperty propHaskell2010InferenceRejectsInvalidPrograms
      , pureTest "rejects unsupported Core-0 equality" testHaskell2010Core0UnsupportedEquality
      ]
  , TestGroup
      "Haskell 2010 Core-0 Evaluator"
      [ pureTest "evaluates arithmetic Core-0 source" testHaskell2010Core0EvalArithmetic
      , pureTest "evaluates polymorphic identity instantiation" testHaskell2010Core0EvalPolymorphicIdentity
      , pureTest "evaluates Bool case" testHaskell2010Core0EvalBoolCase
      , pureTest "evaluates user ADT constructor fields" testHaskell2010Core0EvalADTField
      , pureTest "keeps unused user ADT fields lazy" testHaskell2010Core0EvalLazyADTField
      , pureTest "evaluates Prelude list functions" testHaskell2010Core0EvalPreludeLists
      , pureTest "short-circuits Bool operators" testHaskell2010Core0EvalShortCircuitBool
      , pureTest "evaluates recursive functions and list recursion" testHaskell2010Core0EvalRecursion
      , pureTest "evaluates type class dictionary calls" testHaskell2010Core0EvalTypeClassDictionaries
      , pureTest "evaluates Prelude class dictionary calls" testHaskell2010Core0EvalPreludeClassDictionaries
      , pureTest "evaluates Char equality and literal cases" testHaskell2010Core0EvalCharRuntime
      , pureTest "evaluates String as Char lists" testHaskell2010Core0EvalStringCharList
      , pureTest "evaluates fromInteger and numeric defaulting" testHaskell2010Core0EvalNumericDefaulting
      , pureTest "evaluates multi-module imports" testHaskell2010Core0EvalMultiModuleImports
      , pureTest "evaluates IO printing" testHaskell2010Core0EvalIOPrinting
      , pureTest "evaluates guards and as-patterns" testHaskell2010Core0EvalGuardsAndAsPatterns
      , pureTest "evaluates operator sections" testHaskell2010Core0EvalSections
      , pureTest "does not force unused let bindings" testHaskell2010Core0EvalLazyLet
      , pureTest "does not force unused function arguments" testHaskell2010Core0EvalLazyArgument
      , pureTest "reports forced division by zero" testHaskell2010Core0EvalDivisionByZero
      , pureTest "reports guard fallthrough as no matching alternative" testHaskell2010Core0EvalGuardFallthrough
      ]
  , TestGroup
      "Haskell 2010 STG Runtime"
      [ pureTest "validates lazy STG bindings" testHaskell2010STGValidatesLazyBindings
      , pureTest "does not force unused let thunks" testHaskell2010STGLazyLet
      , pureTest "does not force unused function arguments" testHaskell2010STGLazyFunctionArgument
      , pureTest "case forces its scrutinee" testHaskell2010STGCaseForcesScrutinee
      , pureTest "dispatches constructor cases" testHaskell2010STGConstructorCase
      , pureTest "shares updatable thunks" testHaskell2010STGUpdatableThunkSharing
      , pureTest "single-entry thunks are not shared" testHaskell2010STGSingleEntryThunk
      , pureTest "reports recursive black holes" testHaskell2010STGBlackHole
      , pureTest "rejects unbound STG variables" testHaskell2010STGRejectsUnboundVariable
      ]
  , TestGroup
      "Haskell 2010 Core-to-STG Lowering"
      [ pureTest "lowers arithmetic Core-0 to valid STG" testHaskell2010CoreToSTGArithmetic
      , pureTest "lowers polymorphic identity by erasing type applications" testHaskell2010CoreToSTGPolymorphicIdentity
      , pureTest "preserves lazy let semantics" testHaskell2010CoreToSTGLazyLet
      , pureTest "preserves lazy function argument semantics" testHaskell2010CoreToSTGLazyArgument
      , pureTest "preserves Bool case semantics" testHaskell2010CoreToSTGBoolCase
      , pureTest "preserves user ADT constructor pattern semantics" testHaskell2010CoreToSTGADTCase
      , pureTest "preserves polymorphic ADT constructor semantics" testHaskell2010CoreToSTGPolymorphicADT
      , pureTest "preserves nested constructor pattern semantics" testHaskell2010CoreToSTGNestedADTPatterns
      , pureTest "preserves list tuple and Prelude semantics" testHaskell2010CoreToSTGPreludeData
      , pureTest "preserves recursive function semantics" testHaskell2010CoreToSTGRecursion
      , pureTest "preserves type class dictionary semantics" testHaskell2010CoreToSTGTypeClassDictionaries
      , pureTest "preserves Prelude class dictionary semantics" testHaskell2010CoreToSTGPreludeClassDictionaries
      , pureTest "preserves Char runtime semantics" testHaskell2010CoreToSTGCharRuntime
      , pureTest "preserves String as Char lists" testHaskell2010CoreToSTGStringCharList
      , pureTest "preserves fromInteger and numeric defaulting" testHaskell2010CoreToSTGNumericDefaulting
      , pureTest "preserves multi-module import semantics" testHaskell2010CoreToSTGMultiModuleImports
      , pureTest "preserves IO printing semantics" testHaskell2010CoreToSTGIOPrinting
      , pureTest "preserves guard and as-pattern semantics" testHaskell2010CoreToSTGGuardsAndAsPatterns
      , pureTest "preserves operator section semantics" testHaskell2010CoreToSTGSections
      , pureTest "preserves forced division-by-zero errors" testHaskell2010CoreToSTGDivisionByZero
      , pureTest "preserves guard fallthrough errors" testHaskell2010CoreToSTGGuardFallthrough
      , pureTest "preserves curried partial application" testHaskell2010CoreToSTGPartialApplication
      , pureTest "rejects invalid Core before lowering" testHaskell2010CoreToSTGRejectsInvalidCore
      ]
  , TestGroup
      "Haskell 2010 Native Output"
      [ pureTest "emits boxed lazy STG runtime LLVM" testHaskell2010NativeLLVMShape
      , pureTest "erases newtype constructor allocation in native LLVM" testHaskell2010NativeNewtypeErasure
      , pureTest "emits Char runtime LLVM" testHaskell2010NativeCharRuntime
      , pureTest "emits String as Char lists in native LLVM" testHaskell2010NativeStringCharList
      , ioTest "LLVM execution preserves Core-0 semantics" testHaskell2010NativeLLVMExecution
      , ioTest "native executable preserves lazy Core-0 semantics" testHaskell2010NativeExecutableExecution
      , ioTest "native runtime errors fail when forced" testHaskell2010NativeRuntimeError
      ]
  , TestGroup
      "Haskell 2010 Core Egglog Optimizer"
      [ pureTest "folds safe Core-0 arithmetic with provenance" testHaskell2010CoreEgglogFoldsArithmetic
      , pureTest "folds Bool case over known constructor" testHaskell2010CoreEgglogFoldsKnownBoolCase
      , pureTest "folds case over known ADT constructor" testHaskell2010CoreEgglogFoldsKnownConstructorCase
      , pureTest "preserves lazy constructor field semantics" testHaskell2010CoreEgglogPreservesKnownConstructorLaziness
      , pureTest "preserves lazy let semantics through optimized Core and STG" testHaskell2010CoreEgglogPreservesLazyLet
      , pureTest "does not erase strict bottom dependencies" testHaskell2010CoreEgglogPreservesStrictBottom
      , ioTest "optimized and unoptimized native output agree" testHaskell2010CoreEgglogNativeAgreement
      ]
  , TestGroup
      "Typechecker"
      [ pureTest "higher-order lambda annotation parses and types" testHigherOrderType
      , pureTest "optional lambda parameter infers Int" testOptionalLambdaParameterInference
      , pureTest "optional lambda equality waits for context" testOptionalLambdaEqualityContext
      , pureTest "optional lambda parameter resolves through let use" testOptionalLambdaLetUse
      , pureTest "optional lambda let remains monomorphic" testOptionalLambdaLetMonomorphic
      , pureTest "optional lambda ambiguity is source-spanned" testOptionalLambdaAmbiguity
      , pureTest "principal type engine infers annotated identity" testPrincipalIdentityType
      , pureTest "principal type engine infers higher-order closures" testPrincipalHigherOrderType
      , pureTest "principal type engine preserves monomorphic lets" testPrincipalMonomorphicLet
      , pureTest "top-level function program types" testTopLevelFunctionTypecheck
      , pureTest "top-level duplicate function names fail" testTopLevelDuplicateFunctionName
      , pureTest "top-level duplicate parameters fail" testTopLevelDuplicateParameter
      , pureTest "top-level forward calls fail" testTopLevelForwardCall
      , pureTest "top-level function-typed parameters fail" testTopLevelFunctionParameter
      , ioTest "addition rejects Bool" $
          checkTypeError "examples/type-errors/add-bool.hg" (ExpectedIntOperand Add TBool)
      , ioTest "if condition rejects Int" $
          checkTypeError "examples/type-errors/if-non-bool.hg" (ExpectedBoolCondition TInt)
      , ioTest "if branches must match" $
          checkTypeError "examples/type-errors/if-branch-mismatch.hg" (TypeMismatch TInt TBool)
      , ioTest "applying non-function fails" $
          checkTypeError "examples/type-errors/apply-non-function.hg" (ExpectedFunction TInt)
      , ioTest "let Bool arithmetic fails" $
          checkTypeError "examples/type-errors/let-bool-arithmetic.hg" (ExpectedIntOperand Add TBool)
      , pureTest "out-of-range Int literal fails" testOutOfRangeIntLiteralTypeError
      ]
  , TestGroup
      "Diagnostics"
      [ pureTest "parser diagnostics include source location" testParserDiagnosticIncludesLocation
      , ioTest "type error diagnostic golden" $
          checkDiagnosticGolden "examples/type-errors/add-bool.hg" "test/golden/diagnostic-type-add-bool.golden"
      , ioTest "LLVM unsupported diagnostic golden" $
          checkLLVMDiagnosticGolden "\\x : Int -> x" "test/golden/diagnostic-llvm-lambda.golden"
      ]
  , TestGroup
      "CLI"
      [ pureTest "compile flags select LLVM and native output modes" testCompileFlagsOutputModes
      , pureTest "compile flags reject invalid run combinations" testCompileFlagsRejectInvalidRunModes
      ]
  , TestGroup
      "Interpreter"
      [ pureTest "inc example evaluates" (checkProgram incSource TInt (sourceInt 42))
      , pureTest "add example evaluates" (checkProgram addSource TInt (sourceInt 7))
      , pureTest "higher-order example evaluates" (checkProgram higherOrderSource TInt (sourceInt 42))
      , pureTest "top-level direct calls evaluate" testTopLevelFunctionEvaluation
      , pureTest "checked Int addition overflow fails" testInterpreterIntOverflow
      , ioTest "source and ANF evaluation agree for examples" testExampleSemanticPreservation
      ]
  , TestGroup
      "ANF"
      [ pureTest "atomizes nested arithmetic" testANFNestedArithmetic
      , pureTest "fresh names are deterministic" testDeterministicFreshNames
      , pureTest "atomizes application arguments" testApplicationAtomization
      , pureTest "lowers top-level calls as direct calls" testTopLevelDirectCallANF
      , pureTest "lambda lifting creates direct-call ANF" testLambdaLiftANF
      , pureTest "preserves lambdas" testLambdaPreservation
      , ioTest "validator accepts lowered examples" testValidateLoweredExamples
      , pureTest "validator reports unbound variables" testValidatorUnboundVariable
      , pureTest "validator reports duplicate generated temps" testValidatorDuplicateGeneratedTemp
      , pureTest "program validator reports duplicate function parameters" testValidatorDuplicateFunctionParameter
      ]
  , TestGroup
      "Facts"
      [ pureTest "constant facts are inferred" testConstantFacts
      , pureTest "nonzero facts are inferred" testNonZeroFacts
      , pureTest "purity facts are inferred" testPurityFacts
      ]
  , TestGroup
      "Optimizer"
      [ pureTest "x + 0 simplifies to x" $
          checkSimplifies "let x = 7 in x + 0" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName))) "add-right-zero"
      , pureTest "0 + x simplifies to x" $
          checkSimplifies "let x = 7 in 0 + x" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName))) "add-left-zero"
      , pureTest "x * 1 simplifies to x" $
          checkSimplifies "let x = 7 in x * 1" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName))) "mul-right-one"
      , pureTest "1 * x simplifies to x" $
          checkSimplifies "let x = 7 in 1 * x" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName))) "mul-left-one"
      , pureTest "x * 0 simplifies to 0" $
          checkSimplifies "let x = 7 in x * 0" (ALet xName (AAtom (AInt 7)) (AAtom (AInt 0))) "mul-right-zero"
      , pureTest "0 * x simplifies to 0" $
          checkSimplifies "let x = 7 in 0 * x" (ALet xName (AAtom (AInt 7)) (AAtom (AInt 0))) "mul-left-zero"
      , pureTest "constant folding simplifies integer arithmetic" $
          checkSimplifies "1 + 2" (AAtom (AInt 3)) "constant-fold-add"
      , pureTest "constant folding preserves overflowing arithmetic" testSimplifierDoesNotFoldOverflow
      , pureTest "if true selects then branch" $
          checkSimplifies "if true then 1 else 2" (AAtom (AInt 1)) "if-true"
      , pureTest "if false selects else branch" $
          checkSimplifies "if false then 1 else 2" (AAtom (AInt 2)) "if-false"
      , pureTest "fixpoint keeps simplifying rewrite results" testFixpointSimplification
      , pureTest "rewrite conditions are checked" testRewriteConditions
      , ioTest "optimized ANF validates for examples" testOptimizedANFValidates
      , ioTest "optimized ANF preserves semantics for examples" testOptimizedSemanticPreservation
      ]
  , TestGroup
      "EGraph"
      [ pureTest "inserts ANF expression" testEGraphInsertion
      , pureTest "union/find merges classes" testEGraphUnionFind
      , pureTest "extracts cheaper arithmetic representative" testEGraphExtraction
      , pureTest "x + 0 rewrite" $
          checkEGraphOptimizes "let x = 7 in x + 0" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName)))
      , pureTest "0 + x rewrite" $
          checkEGraphOptimizes "let x = 7 in 0 + x" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName)))
      , pureTest "x * 1 rewrite" $
          checkEGraphOptimizes "let x = 7 in x * 1" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName)))
      , pureTest "1 * x rewrite" $
          checkEGraphOptimizes "let x = 7 in 1 * x" (ALet xName (AAtom (AInt 7)) (AAtom (AVar xName)))
      , pureTest "x * 0 rewrite" $
          checkEGraphOptimizes "let x = 7 in x * 0" (ALet xName (AAtom (AInt 7)) (AAtom (AInt 0)))
      , pureTest "0 * x rewrite" $
          checkEGraphOptimizes "let x = 7 in 0 * x" (ALet xName (AAtom (AInt 7)) (AAtom (AInt 0)))
      , pureTest "constant folding rewrite" $
          checkEGraphOptimizes "2 * 3" (AAtom (AInt 6))
      , pureTest "if true rewrite" $
          checkEGraphOptimizes "if true then 1 else 2" (AAtom (AInt 1))
      , pureTest "if false rewrite" $
          checkEGraphOptimizes "if false then 1 else 2" (AAtom (AInt 2))
      , pureTest "unsupported lambda fails gracefully" testEGraphUnsupportedLambda
      , pureTest "unsupported application fails gracefully" testEGraphUnsupportedApplication
      , pureTest "unsupported primitive fails gracefully" testEGraphUnsupportedPrimitive
      , pureTest "agrees with reference simplifier on supported arithmetic" testEGraphAgreesWithSimplifier
      , pureTest "semantic preservation on supported fragment" testEGraphSemanticPreservation
      ]
  , TestGroup
      "Egglog"
      [ pureTest "default fresh id creation" testEgglogDefaultFreshId
      , pureTest "function lookup and set" testEgglogFunctionLookupSet
      , pureTest "functional dependency conflict" testEgglogFunctionalDependencyConflict
      , pureTest "MergeUnion unions outputs" testEgglogMergeUnion
      , pureTest "MergeMinInt keeps the shorter value" testEgglogMergeMinInt
      , pureTest "base values cannot be incorrectly unioned" testEgglogRejectsBaseUnion
      , pureTest "ids from different sorts cannot be unioned" testEgglogRejectsDifferentSortUnion
      , pureTest "rebuild canonicalizes keys" testEgglogRebuildCanonicalizesKeys
      , pureTest "rebuild resolves conflicts after union" testEgglogRebuildResolvesConflicts
      , pureTest "MergeUnion can trigger additional rebuild work" testEgglogRebuildMergeUnion
      , pureTest "single-premise rule" testEgglogSinglePremiseRule
      , pureTest "multi-premise join" testEgglogMultiPremiseJoin
      , pureTest "join planner respects computed dependencies" testEgglogJoinPlannerRespectsDependencies
      , pureTest "join planner uses stable relation-size order" testEgglogJoinPlannerUsesStableCostOrder
      , pureTest "semi-naive matches naive transitive closure" testEgglogSemiNaiveMatchesNaiveTransitiveClosure
      , pureTest "semi-naive preserves compiler backend result" testEgglogSemiNaivePreservesCompilerBackend
      , pureTest "debug log records rule action provenance" testEgglogDebugTraceRecordsRuleAction
      , pureTest "variable binding correctness" testEgglogVariableBinding
      , pureTest "typed mismatch failure" testEgglogTypedMismatchFailure
      , pureTest "action application" testEgglogActionApplication
      , pureTest "rewrite desugars into rule machinery" testEgglogRewriteDesugars
      , pureTest "rewrite is non-destructive" testEgglogRewriteNonDestructive
      , pureTest "paper reachability example" testEgglogPaperReachability
      , pureTest "paper shortest path example" testEgglogPaperShortestPath
      , pureTest "paper arithmetic EqSat example" testEgglogPaperArithmetic
      , pureTest "extracts cheapest representative" testEgglogExtractionCheapest
      , pureTest "extractor handles cycles safely" testEgglogExtractionCycle
      , pureTest "extractor fails structurally when impossible" testEgglogExtractionImpossible
      , pureTest "Egglog backend optimizes supported arithmetic" testEgglogBackendSupportedArithmetic
      , pureTest "Egglog backend rejects unsupported lambdas" testEgglogBackendUnsupportedLambda
      , pureTest "ConstInt lattice merges same constants" testEgglogConstIntMergeSame
      , pureTest "ConstInt lattice detects conflicts" testEgglogConstIntMergeConflict
      , pureTest "ZeroInfo lattice refines unknown values" testEgglogZeroInfoMergeUnknown
      , pureTest "ZeroInfo lattice detects conflicts" testEgglogZeroInfoMergeConflict
      , pureTest "resolved ANF simple let binds locally" testResolvedANFSimpleLet
      , pureTest "resolved ANF distinguishes shadowed binders" testResolvedANFShadowing
      , pureTest "resolved ANF final shadowed reference is inner" testResolvedANFInnerShadowReference
      , pureTest "resolved ANF exposes free variables" testResolvedANFFreeVariable
      , pureTest "resolved ANF dependency graph tracks let RHS references" testResolvedANFDependencyGraph
      , pureTest "resolved ANF renderer shows binder ids" testResolvedANFRenderer
      , pureTest "Egglog fragment accepts if expressions" testEgglogFragmentAcceptsIf
      , pureTest "Egglog fragment accepts comparisons" testEgglogFragmentAcceptsComparisons
      , pureTest "Egglog fragment accepts subtraction" testEgglogFragmentAcceptsSubtraction
      , pureTest "Egglog fragment accepts division" testEgglogFragmentAcceptsDivision
      , pureTest "Egglog fragment rejects mismatched if branches" testEgglogFragmentRejectsIfMismatch
      , pureTest "Egglog fragment rejects inconsistent free variable types" testEgglogFragmentRejectsInconsistentFreeVariableTypes
      , pureTest "Egglog encoding uses distinct typed sorts" testEgglogEncodingDistinctTypedSorts
      , pureTest "Egglog encoding rejects invalid cross-sort construction" testEgglogEncodingRejectsCrossSort
      , pureTest "Egglog encoding keeps shadowed BinderKeys distinct" testEgglogEncodingBinderKeys
      , pureTest "Egglog encoding keeps free variables explicit" testEgglogEncodingFreeVariable
      , pureTest "Egglog encoding asserts let equality" testEgglogEncodingLetEquality
      , pureTest "Egglog rules derive constant facts in kernel" testEgglogRulesDeriveConstFacts
      , pureTest "Egglog rules make constant fold equality" testEgglogRulesConstantFoldEquality
      , pureTest "Egglog rules handle strict-safe multiplication identities" testEgglogRulesMultiplicationIdentities
      , pureTest "Egglog rules simplify if true" testEgglogRulesIfTrue
      , pureTest "Egglog rules simplify fact-driven if" testEgglogRulesFactDrivenIf
      , pureTest "Egglog rules simplify strict-safe booleans" testEgglogRulesStrictSafeBooleans
      , pureTest "Egglog rules derive zero information" testEgglogRulesDeriveZeroInfo
      , pureTest "Egglog rules derive comparison facts" testEgglogRulesDeriveComparisonFacts
      , pureTest "Egglog rules derive subtraction facts" testEgglogRulesDeriveSubtractionFacts
      , pureTest "Egglog rules derive safe division facts" testEgglogRulesDeriveDivisionFacts
      , pureTest "Egglog rules avoid unsafe division facts" testEgglogRulesAvoidUnsafeDivisionFacts
      , pureTest "Egglog default rules exclude distributivity" testEgglogRulesExcludeDistributivity
      , pureTest "Egglog backend preserves shadowing semantics" testEgglogBackendShadowing
      , pureTest "Egglog backend preserves retained let dependencies" testEgglogBackendLetRetention
      , pureTest "Egglog backend can drop dead lets" testEgglogBackendDeadLet
      , pureTest "Egglog backend simplifies if true" testEgglogBackendIfTrue
      , pureTest "Egglog backend preserves same branches" testEgglogBackendIfSameBranches
      , pureTest "Egglog backend folds constants through Egglog facts" testEgglogBackendConstFacts
      , pureTest "Egglog backend folds comparison constants" testEgglogBackendComparisonConstFacts
      , pureTest "Egglog backend optimizes open comparisons" testEgglogBackendOpenComparisonFragment
      , pureTest "Egglog backend folds checked subtraction constants" testEgglogBackendSubtractionConstFacts
      , pureTest "Egglog backend reconstructs open subtraction" testEgglogBackendOpenSubtractionFragment
      , pureTest "Egglog backend folds checked division constants" testEgglogBackendDivisionConstFacts
      , pureTest "Egglog backend reconstructs open division" testEgglogBackendOpenDivisionFragment
      , pureTest "Egglog backend optimizes strict-safe booleans" testEgglogBackendStrictSafeBooleans
      , pureTest "Egglog backend preserves strict runtime-error dependencies" testEgglogBackendPreservesStrictRuntimeErrors
      , pureTest "Egglog Int constants do not fold overflow" testEgglogDoesNotFoldOverflowingInt
      , pureTest "Egglog backend optimizes open free-variable fragments" testEgglogBackendOpenFreeVariableFragment
      , pureTest "Egglog backend rejects applications structurally" testEgglogBackendUnsupportedApplication
      , pureTest "Egglog backend extraction is deterministic" testEgglogBackendDeterministic
      , pureTest "Egglog backend exposes extraction provenance" testEgglogBackendExtractionProvenance
      , pureTest "Egglog backend preserves boolean branches" testEgglogBackendBooleanBranchPreservation
      , pureTest "Egglog tryOptimize reports unsupported lambdas" testEgglogTryOptimizeUnsupportedLambda
      , pureTest "ordinary compiler still handles unsupported lambdas" testOrdinaryPipelineHandlesUnsupportedLambda
      , pureTest "simplifier and Egglog agree semantically on supported examples" testEgglogAgreesWithSimplifierSemantically
      ]
  , TestGroup
      "LLVM"
      [ pureTest "Backend IR validates supported arithmetic" testLLVMBackendValidArithmetic
      , pureTest "Backend IR validates Int division" testLLVMBackendValidDivision
      , pureTest "Backend IR validation rejects unbound variables" testLLVMBackendValidationRejectsUnbound
      , pureTest "Backend IR validation rejects invalid if conditions" testLLVMBackendValidationRejectsBadIf
      , pureTest "Backend IR validation rejects Bool division" testLLVMBackendValidationRejectsBoolDivision
      , pureTest "LLVM backend rejects lambdas structurally" testLLVMLowerRejectsLambda
      , pureTest "LLVM backend rejects applications structurally" testLLVMLowerRejectsApplication
      , pureTest "LLVM backend rejects open programs" testLLVMLowerRejectsOpenProgram
      , pureTest "LLVM compiler lowers checked division" testLLVMLoweringCheckedDivision
      , pureTest "LLVM lowering emits deterministic phi blocks" testLLVMLoweringNestedIf
      , pureTest "LLVM validator rejects duplicate SSA registers" testLLVMValidatorRejectsDuplicateRegisters
      , pureTest "LLVM validator rejects missing block references" testLLVMValidatorRejectsMissingBlock
      , pureTest "LLVM compiler falls back when Egglog is unsupported" testLLVMCompileEgglogFallback
      , pureTest "LLVM compiler can use Egglog optimized ANF" testLLVMCompileUsesEgglog
      , pureTest "LLVM compiler emits top-level direct calls" testLLVMCompileTopLevelFunctions
      , pureTest "LLVM compiler rejects top-level function values" testLLVMCompileRejectsTopLevelFunctionValue
      , pureTest "LLVM compiler escapes top-level names without collisions" testLLVMCompileEscapesTopLevelNames
      , pureTest "LLVM compiler lambda lifts non-capturing lets" testLLVMCompileLiftedLetLambda
      , pureTest "LLVM compiler lambda lifts immediate lambdas" testLLVMCompileImmediateLambda
      , pureTest "LLVM compiler closure-converts capturing lambdas" testLLVMCompileCapturingLambda
      , pureTest "LLVM compiler closure-converts inferred capturing lambdas" testLLVMCompileInferredCapturingLambda
      , ioTest "native build reports missing clang structurally" testNativeBuildToolchainMissing
      , ioTest "native executable output matches interpreter when clang is available" testNativeExecutionMatchesInterpreter
      , ioTest "native executable runtime errors fail when clang is available" testNativeRuntimeErrorExecutable
      , ioTest "LLVM checked Int overflow aborts when tools are available" testLLVMOverflowAborts
      , ioTest "LLVM checked division runs and aborts when tools are available" testLLVMDivisionExecution
      , ioTest "LLVM arithmetic golden" $
          checkLLVMGolden "examples/llvm/arithmetic.hg" "test/golden/llvm-arithmetic.ll"
      , ioTest "LLVM if comparison golden" $
          checkLLVMGolden "examples/llvm/if-comparison.hg" "test/golden/llvm-if-comparison.ll"
      , ioTest "LLVM bool root golden" $
          checkLLVMGolden "examples/llvm/bool-root.hg" "test/golden/llvm-bool-root.ll"
      , ioTest "LLVM execution matches interpreter when tools are available" testLLVMExecutionMatchesInterpreter
      , ioTest "LLVM differential corpus matches interpreter when tools are available" testLLVMDifferentialCorpus
      ]
  , TestGroup
      "Golden"
      [ ioTest "arithmetic output" $
          checkGolden "examples/test.hg" "test/golden/arithmetic.golden"
      , ioTest "function output" $
          checkGolden "examples/inc.hg" "test/golden/function.golden"
      , ioTest "if output" $
          checkGolden "examples/if.hg" "test/golden/if.golden"
      ]
  , TestGroup
      "Properties"
      [ ioTest "ANF validates after lowering" $
          checkProperty propANFValidationAfterLowering
      , ioTest "Egglog backend preserves generated supported programs" $
          checkProperty propEgglogSupportedSemanticPreservation
      ]
  , TestGroup
      "Core"
      [ pureTest "lowering preserves lambda and application nodes" testCoreFunctions
      ]
  ]

pureTest :: String -> Either String () -> Test
pureTest testName result =
  Test testName (pure result)

ioTest :: String -> IO (Either String ()) -> Test
ioTest =
  Test

runGroup :: TestGroup -> IO (String, [(String, Either String ())])
runGroup (TestGroup groupName tests) = do
  putStrLn ("[" <> groupName <> "]")
  results <- traverse runTest tests
  pure (groupName, results)

runTest :: Test -> IO (String, Either String ())
runTest (Test testName action) = do
  result <- action
  putStrLn $
    case result of
      Right () -> "  PASS " <> testName
      Left _ -> "  FAIL " <> testName
  pure (testName, result)

printFailure :: (String, String, String) -> IO ()
printFailure (groupName, testName, message) = do
  putStrLn ("- " <> groupName <> " / " <> testName)
  putStrLn message

testApplicationPrecedence :: Either String ()
testApplicationPrecedence = do
  parsed <- parseExpr "f x + 1"
  expectEqual
    "application precedence"
    (EBin Add (EApp (EVar (mkName "f")) (EVar (mkName "x"))) (EInt 1))
    parsed

testParenthesizedArgument :: Either String ()
testParenthesizedArgument = do
  parsed <- parseExpr "f (x + 1)"
  expectEqual
    "parenthesized application argument"
    (EApp (EVar (mkName "f")) (EBin Add (EVar (mkName "x")) (EInt 1)))
    parsed

testTopLevelFunctionParsing :: Either String ()
testTopLevelFunctionParsing = do
  parsed <- parseSource topLevelSource
  expectEqual
    "top-level program"
    ( Program
        [ TopDef
            (mkName "inc")
            [Param (mkName "x") TInt]
            TInt
            (EBin Add (EVar (mkName "x")) (EInt 1))
        , TopDef
            (mkName "double")
            [Param (mkName "x") TInt]
            TInt
            (EBin Mul (EVar (mkName "x")) (EInt 2))
        ]
        (EApp (EVar (mkName "double")) (EApp (EVar (mkName "inc")) (EInt 20)))
    )
    parsed

testHaskell2010ModuleParsing :: Either String ()
testHaskell2010ModuleParsing = do
  parsed <-
    parseHaskell2010
      "module Main (main, Maybe(..), module Data.List) where\n\
      \-- line comment\n\
      \{- nested {- block -} comment -}\n\
      \import qualified Data.List as List hiding (map)\n\
      \data Maybe a = Nothing | Just a deriving (Eq, Show)\n\
      \newtype Identity a = Identity a\n\
      \type Pair a = (a, a)\n\
      \class Eq a where\n\
      \  eq :: a -> a -> Bool\n\
      \instance Eq Int where\n\
      \  eq x y = x == y\n\
      \main :: IO Int\n\
      \main = pure 0\n"
  expectEqual "Haskell 2010 module name" (Just (H2010.ModuleName ["Main"])) (H2010.moduleName parsed)
  expectEqual
    "Haskell 2010 exports"
    ( Just
        [ H2010.ExportName "main"
        , H2010.ExportThing "Maybe" [".."]
        , H2010.ExportModule (H2010.ModuleName ["Data", "List"])
        ]
    )
    (H2010.moduleExports parsed)
  expectEqual
    "Haskell 2010 import"
    [ H2010.ImportDecl
        { H2010.importQualified = True
        , H2010.importModule = H2010.ModuleName ["Data", "List"]
        , H2010.importAs = Just (H2010.ModuleName ["List"])
        , H2010.importSpecs = Just ([H2010.ImportName "map"], True)
        }
    ]
    (H2010.moduleImports parsed)
  expectEqual "Haskell 2010 declaration count" 7 (length (H2010.moduleDecls parsed))

testHaskell2010LayoutParsing :: Either String ()
testHaskell2010LayoutParsing = do
  parsed <-
    parseHaskell2010
      "module Layout where\n\
      \main =\n\
      \  let\n\
      \    x = 1\n\
      \    y = 2\n\
      \  in case x of\n\
      \    0 -> y\n\
      \    n | n > 0 -> do\n\
      \      value <- pure n\n\
      \      let\n\
      \        z = value\n\
      \      pure z\n"
  case H2010.moduleDecls parsed of
    [H2010.FunctionBinding "main" [] (H2010.Unguarded body) []] ->
      assertBool "Haskell 2010 layout parsed let/case/do" (containsDo body)
    other -> Left ("unexpected Haskell 2010 layout declarations: " <> show other)
 where
  containsDo = \case
    H2010.Do {} -> True
    H2010.Let _ body -> containsDo body
    H2010.Case _ alts -> any altContainsDo alts
    H2010.App lhs rhs -> containsDo lhs || containsDo rhs
    H2010.InfixApp lhs _ rhs -> containsDo lhs || containsDo rhs
    H2010.If condition thenBranch elseBranch ->
      containsDo condition || containsDo thenBranch || containsDo elseBranch
    H2010.Lambda _ body -> containsDo body
    H2010.Paren body -> containsDo body
    H2010.ExprTypeSig body _ -> containsDo body
    _ -> False
  altContainsDo (H2010.Alt _ rhs _) =
    rhsContainsDo rhs
  rhsContainsDo = \case
    H2010.Unguarded body -> containsDo body
    H2010.Guarded branches -> any (containsDo . snd) branches

testHaskell2010ExpressionSurfaceParsing :: Either String ()
testHaskell2010ExpressionSurfaceParsing = do
  parsed <-
    parseHaskell2010
      "module Surface where\n\
      \infixl 6 +++\n\
      \default (Int)\n\
      \foreign import ccall \"puts\" c_puts :: CString -> IO Int\n\
      \literals = ('x', \"hello\")\n\
      \numbers = (0x10, 0o7)\n\
      \collections = ([1, 2, 3], [1, 3..9], [x | x <- xs])\n\
      \sections = ((1 +), (+ 1))\n\
      \typed = (pure 0 :: IO Int)\n\
      \branch = \\x -> if x then [] else [1]\n\
      \patterns (Just x) _ (a, b) [c] (h : t) name@value ~lazy 'x' = x\n"
  expectEqual "Haskell 2010 surface declaration count" 10 (length (H2010.moduleDecls parsed))
  assertBool
    "Haskell 2010 surface forms include foreign declarations"
    (any isForeignDecl (H2010.moduleDecls parsed))
 where
  isForeignDecl = \case
    H2010.ForeignDecl {} -> True
    _ -> False

testHaskell2010RecordFieldSyntaxParsing :: Either String ()
testHaskell2010RecordFieldSyntaxParsing = do
  parsed <-
    parseHaskell2010
      "module Records where\n\
      \data Person = Person { age, score :: Int }\n\
      \main = case Person { score = 2, age = 1 } of\n\
      \  Person { age = a } -> a\n"
  case H2010.moduleDecls parsed of
    [ H2010.DataDecl "Person" [] [H2010.RecordConDecl "Person" [H2010.ConField ["age", "score"] _]] []
      , H2010.FunctionBinding "main" [] (H2010.Unguarded (H2010.Case (H2010.RecordCon "Person" exprFields) [H2010.Alt (H2010.PRecordCon "Person" patFields) _ []])) []
      ] -> do
        expectEqual "record construction field order is parsed from source order" ["score", "age"] (map fst exprFields)
        expectEqual "record pattern fields are parsed" ["age"] (map fst patFields)
    other -> Left ("unexpected record field syntax parse: " <> show other)

testHaskell2010MalformedLayout :: Either String ()
testHaskell2010MalformedLayout =
  case
    H2010Parser.parseSourceModule
      "<haskell2010-malformed-layout>"
      "module Bad where\n\
      \main =\n\
      \  let\n\
      \    x = 1\n\
      \   y = 2\n\
      \  in x\n"
    of
      Left _ -> Right ()
      Right parsed -> Left ("malformed Haskell 2010 layout parsed unexpectedly: " <> show parsed)

testHaskell2010ImportAfterDecl :: Either String ()
testHaskell2010ImportAfterDecl =
  case
    H2010Parser.parseSourceModule
      "<haskell2010-import-after-decl>"
      "module Bad where\n\
      \main = 0\n\
      \import Data.List\n"
    of
      Left _ -> Right ()
      Right parsed -> Left ("import after declaration parsed unexpectedly: " <> show parsed)

testHaskell2010RenamerShadowing :: Either String ()
testHaskell2010RenamerShadowing = do
  renamed <-
    renameHaskell2010
      "module Scope where\n\
      \x = 1\n\
      \f x =\n\
      \  let\n\
      \    y = x\n\
      \  in y\n"
  case H2010Renamed.rModuleDecls renamed of
    [ H2010Renamed.RFunctionBinding topX [] _ []
      , H2010Renamed.RFunctionBinding _ [H2010Renamed.RPVar paramX] (H2010Renamed.RUnguarded (H2010Renamed.RLet [H2010Renamed.RFunctionBinding yBinder [] (H2010Renamed.RUnguarded (H2010Renamed.RVar rhsX)) []] (H2010Renamed.RVar bodyY))) []
      ] -> do
        assertBool "parameter shadows top-level x" (H2010Names.nameUnique topX /= H2010Names.nameUnique paramX)
        expectEqual "let rhs x resolves to parameter" paramX rhsX
        expectEqual "let body resolves to y binder" yBinder bodyY
    other -> Left ("unexpected renamed shadowing module: " <> show other)

testHaskell2010RenamerDuplicateTopLevel :: Either String ()
testHaskell2010RenamerDuplicateTopLevel =
  expectRenameError
    "duplicate top-level binding"
    (H2010Renamer.DuplicateName H2010Names.TermNamespace "x")
    "module Dup where\n\
    \x = 1\n\
    \x = 2\n"

testHaskell2010RenamerUnboundVariable :: Either String ()
testHaskell2010RenamerUnboundVariable =
  expectRenameError
    "unbound variable"
    (H2010Renamer.UnboundName H2010Names.TermNamespace "y")
    "module Unbound where\n\
    \x = y\n"

testHaskell2010RenamerNamespaces :: Either String ()
testHaskell2010RenamerNamespaces = do
  renamed <-
    renameHaskell2010
      "module Namespaces where\n\
      \data T a = T a\n\
      \class C a where\n\
      \  c :: a -> a\n\
      \instance C (T Int) where\n\
      \  c x = x\n\
      \id :: a -> a\n\
      \id x = x\n\
      \use T = c T\n"
  case H2010Renamed.rModuleDecls renamed of
    [ H2010Renamed.RDataDecl typeT [typeA] [H2010Renamed.RConDecl conT [H2010Renamed.RTyVar fieldA]] []
      , H2010Renamed.RClassDecl [] classC classA [H2010Renamed.RTypeSignature [methodC] _]
      , H2010Renamed.RInstanceDecl [] (H2010Renamed.RTyApp (H2010Renamed.RTyCon instanceClassC) _) [H2010Renamed.RFunctionBinding instanceMethodC [H2010Renamed.RPVar instanceX] (H2010Renamed.RUnguarded (H2010Renamed.RVar instanceUseX)) []]
      , H2010Renamed.RTypeSignature [idSig] _
      , H2010Renamed.RFunctionBinding idBinder [H2010Renamed.RPVar idParam] (H2010Renamed.RUnguarded (H2010Renamed.RVar idUse)) []
      , H2010Renamed.RFunctionBinding _ [H2010Renamed.RPCon useConT []] (H2010Renamed.RUnguarded (H2010Renamed.RApp (H2010Renamed.RVar useMethodC) (H2010Renamed.RCon useExprT))) []
      ] -> do
        expectEqual "type parameter scopes over constructor field" typeA fieldA
        expectEqual "class type variable namespace" H2010Names.TypeVariableNamespace (H2010Names.nameNamespace classA)
        expectEqual "instance constraint resolves class" classC instanceClassC
        expectEqual "instance method resolves class method" methodC instanceMethodC
        expectEqual "instance method body resolves parameter" instanceX instanceUseX
        expectEqual "signature resolves id binder" idBinder idSig
        expectEqual "id body resolves parameter" idParam idUse
        expectEqual "pattern constructor T resolves data constructor" conT useConT
        expectEqual "expression constructor T resolves data constructor" conT useExprT
        expectEqual "method use resolves class method" methodC useMethodC
        assertBool "type and constructor namespaces differ" (H2010Names.nameUnique typeT /= H2010Names.nameUnique conT)
        expectEqual "type namespace" H2010Names.TypeNamespace (H2010Names.nameNamespace typeT)
        expectEqual "constructor namespace" H2010Names.ConstructorNamespace (H2010Names.nameNamespace conT)
    other -> Left ("unexpected namespace renamed module: " <> show other)

testHaskell2010RenamerPatternScope :: Either String ()
testHaskell2010RenamerPatternScope = do
  renamed <-
    renameHaskell2010
      "module Patterns where\n\
      \data Maybe a = Nothing | Just a\n\
      \f (Just x) | x == x = x\n"
  case H2010Renamed.rModuleDecls renamed of
    [ H2010Renamed.RDataDecl {}
      , H2010Renamed.RFunctionBinding _ [H2010Renamed.RPParen (H2010Renamed.RPCon _ [H2010Renamed.RPVar patX])] (H2010Renamed.RGuarded [(H2010Renamed.RInfixApp (H2010Renamed.RVar guardX1) _ (H2010Renamed.RVar guardX2), H2010Renamed.RVar bodyX)]) []
      ] -> do
        expectEqual "first guard x resolves to pattern binder" patX guardX1
        expectEqual "second guard x resolves to pattern binder" patX guardX2
        expectEqual "body x resolves to pattern binder" patX bodyX
    other -> Left ("unexpected renamed pattern module: " <> show other)

testHaskell2010RenamerRightAssociativeFixity :: Either String ()
testHaskell2010RenamerRightAssociativeFixity = do
  renamed <-
    renameHaskell2010
      "module Fix where\n\
      \f a b c = a : b : c\n"
  case H2010Renamed.rModuleDecls renamed of
    [H2010Renamed.RFunctionBinding _ [H2010Renamed.RPVar argA, H2010Renamed.RPVar argB, H2010Renamed.RPVar argC] (H2010Renamed.RUnguarded expr) []] ->
      case expr of
        H2010Renamed.RInfixApp (H2010Renamed.RVar useA) colon1 (H2010Renamed.RInfixApp (H2010Renamed.RVar useB) colon2 (H2010Renamed.RVar useC)) -> do
          expectEqual "right fixity lhs" argA useA
          expectEqual "right fixity middle" argB useB
          expectEqual "right fixity rhs" argC useC
          expectEqual "same cons operator" colon1 colon2
          expectEqual "cons operator namespace" H2010Names.ConstructorNamespace (H2010Names.nameNamespace colon1)
        otherExpr -> Left ("expected right-associated cons tree, got: " <> show otherExpr)
    other -> Left ("unexpected renamed fixity module: " <> show other)

testHaskell2010RenamerFixityPrecedence :: Either String ()
testHaskell2010RenamerFixityPrecedence = do
  renamed <-
    renameHaskell2010
      "module Fix where\n\
      \f a b c = a : b + c\n"
  case H2010Renamed.rModuleDecls renamed of
    [H2010Renamed.RFunctionBinding _ [H2010Renamed.RPVar argA, H2010Renamed.RPVar argB, H2010Renamed.RPVar argC] (H2010Renamed.RUnguarded expr) []] ->
      case expr of
        H2010Renamed.RInfixApp (H2010Renamed.RVar useA) consOp (H2010Renamed.RInfixApp (H2010Renamed.RVar useB) plusOp (H2010Renamed.RVar useC)) -> do
          expectEqual "precedence lhs" argA useA
          expectEqual "precedence middle" argB useB
          expectEqual "precedence rhs" argC useC
          expectEqual "outer operator is cons" ":" (H2010Names.nameOcc consOp)
          expectEqual "inner operator is plus" "+" (H2010Names.nameOcc plusOp)
        otherExpr -> Left ("expected cons outside plus by precedence, got: " <> show otherExpr)
    other -> Left ("unexpected renamed precedence module: " <> show other)

testHaskell2010RenamerNonAssociativeFixity :: Either String ()
testHaskell2010RenamerNonAssociativeFixity =
  case renameHaskell2010Raw "module BadFix where\nf a b c = a == b == c\n" of
    Left H2010Renamer.InvalidFixityUse {} -> Right ()
    Left err -> Left ("expected non-associative fixity error, got: " <> show err)
    Right renamed -> Left ("non-associative chain renamed unexpectedly: " <> show renamed)

testHaskell2010RenamerAmbiguousImport :: Either String ()
testHaskell2010RenamerAmbiguousImport =
  case
    renameHaskell2010Raw
      "module Imports where\n\
      \import A (x)\n\
      \import B (x)\n\
      \y = x\n"
    of
      Left (H2010Renamer.AmbiguousName H2010Names.TermNamespace "x" names)
        | length names == 2 -> Right ()
      Left err -> Left ("expected ambiguous import error, got: " <> show err)
      Right renamed -> Left ("ambiguous import renamed unexpectedly: " <> show renamed)

testHaskell2010RenamerQualifiedImport :: Either String ()
testHaskell2010RenamerQualifiedImport = do
  renamed <-
    renameHaskell2010
      "module Imports where\n\
      \import qualified A as A (x)\n\
      \y = A.x\n"
  case H2010Renamed.rModuleDecls renamed of
    [H2010Renamed.RFunctionBinding _ [] (H2010Renamed.RUnguarded (H2010Renamed.RVar importedX)) []] -> do
      expectEqual "qualified import occurrence" "x" (H2010Names.nameOcc importedX)
      assertBool "qualified import is external" (H2010Names.nameExternal importedX)
    other -> Left ("unexpected qualified import module: " <> show other)

testHaskell2010RenamerModuleGraphExports :: Either String ()
testHaskell2010RenamerModuleGraphExports = do
  modules <- parseHaskell2010ModuleSources haskell2010MultiModuleSources
  renamedModules <- mapLeft (Text.unpack . H2010Renamer.renderRenameError) (H2010Renamer.renameModuleGraph modules)
  case renamedModules of
    [_, mainModule] ->
      case H2010Renamed.rModuleDecls mainModule of
        [ H2010Renamed.RFunctionBinding _ [H2010Renamed.RPParen (H2010Renamed.RPCon boxCon [H2010Renamed.RPVar field])] _ []
          , H2010Renamed.RFunctionBinding _ [] (H2010Renamed.RUnguarded (H2010Renamed.RApp (H2010Renamed.RVar qualifiedDouble) _)) []
          ] -> do
            expectEqual "imported constructor occurrence" "Box" (H2010Names.nameOcc boxCon)
            expectEqual "qualified import resolves to exported definition" "double" (H2010Names.nameOcc qualifiedDouble)
            assertBool "qualified imported definition is local to loaded graph" (not (H2010Names.nameExternal qualifiedDouble))
            assertBool "field binder is local" (not (H2010Names.nameExternal field))
        other -> Left ("unexpected renamed multi-module main: " <> show other)
    other -> Left ("unexpected renamed module graph: " <> show other)
  case renameHaskell2010ModulesRaw haskell2010HiddenImportSources of
    Left (H2010Renamer.UnboundName H2010Names.TermNamespace "hidden") -> Right ()
    Left err -> Left ("expected hidden export rejection, got " <> show err)
    Right renamed -> Left ("hidden import renamed unexpectedly: " <> show renamed)

testHaskell2010ModuleGraphCycle :: IO (Either String ())
testHaskell2010ModuleGraphCycle = do
  let directory = ".context/module-graph-cycle-test"
      aPath = directory </> "A.hs"
      bPath = directory </> "B.hs"
      moduleA = H2010.ModuleName ["A"]
      moduleB = H2010.ModuleName ["B"]
  removeDirectoryIfPresent directory
  createDirectoryIfMissing True directory
  Text.IO.writeFile aPath "module A where\nimport B (b)\na = b\n"
  Text.IO.writeFile bPath "module B where\nimport A (a)\nb = a\n"
  result <- H2010ModuleGraph.loadModuleGraph aPath
  removeDirectoryIfPresent directory
  pure $
    case result of
      Left (H2010ModuleGraph.ModuleCycle names)
        | names == [moduleA, moduleB, moduleA] -> Right ()
      Left err -> Left ("expected module cycle, got " <> show err)
      Right graph -> Left ("cyclic module graph loaded unexpectedly: " <> show graph)

removeDirectoryIfPresent :: FilePath -> IO ()
removeDirectoryIfPresent path = do
  exists <- doesDirectoryExist path
  when exists (removePathForcibly path)

testHaskell2010CoreValidIdentity :: Either String ()
testHaskell2010CoreValidIdentity = do
  let x = coreTerm "x" 100
      binder = coreBinder x H2010Core.intTy
      identity =
        H2010Core.CLam
          binder
          (H2010Core.CVar x H2010Core.intTy)
          (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
  expectEqual
    "identity Core type"
    (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
    (H2010Core.exprType identity)
  expectEqual "identity Core validates" (Right ()) (H2010CoreValidate.validateExpr identity)

testHaskell2010CoreAppMismatch :: Either String ()
testHaskell2010CoreAppMismatch = do
  let f = coreTerm "f" 101
      fTy = H2010Core.funTy H2010Core.intTy H2010Core.intTy
      fBinder = coreBinder f fTy
      expression =
        H2010Core.CLam
          fBinder
          ( H2010Core.CApp
              (H2010Core.CVar f fTy)
              (H2010Core.CCon H2010Core.trueDataConName H2010Core.boolTy)
              H2010Core.intTy
          )
          (H2010Core.funTy fTy H2010Core.intTy)
  expectCoreValidationError
    "Core application argument mismatch"
    ( \case
        H2010CoreValidate.CoreAppArgumentMismatch expected actual ->
          expected == H2010Core.intTy && actual == H2010Core.boolTy
        _ -> False
    )
    (H2010CoreValidate.validateExpr expression)

testHaskell2010CoreUnboundVariable :: Either String ()
testHaskell2010CoreUnboundVariable = do
  let x = coreTerm "x" 102
  expectCoreValidationError
    "Core unbound variable"
    ( \case
        H2010CoreValidate.CoreUnboundVariable name -> name == x
        _ -> False
    )
    (H2010CoreValidate.validateExpr (H2010Core.CVar x H2010Core.intTy))

testHaskell2010CoreLetScopeAndDuplicates :: Either String ()
testHaskell2010CoreLetScopeAndDuplicates = do
  let x = coreTerm "x" 103
      xBinder = coreBinder x H2010Core.intTy
      validLet =
        H2010Core.CLet
          (H2010Core.CoreNonRec xBinder (coreInt 41))
          ( H2010Core.CPrimOp
              H2010Core.PrimAdd
              [H2010Core.CVar x H2010Core.intTy, coreInt 1]
              H2010Core.intTy
          )
          H2010Core.intTy
      duplicateLet =
        H2010Core.CLet
          (H2010Core.CoreRec [(xBinder, coreInt 1), (xBinder, coreInt 2)])
          (H2010Core.CVar x H2010Core.intTy)
          H2010Core.intTy
  expectEqual "Core let validates" (Right ()) (H2010CoreValidate.validateExpr validLet)
  expectCoreValidationError
    "Core duplicate binder"
    ( \case
        H2010CoreValidate.CoreDuplicateBinder name -> name == x
        _ -> False
    )
    (H2010CoreValidate.validateExpr duplicateLet)

testHaskell2010CoreRecursiveScope :: Either String ()
testHaskell2010CoreRecursiveScope = do
  let f = coreTerm "f" 104
      x = coreTerm "x" 105
      fTy = H2010Core.funTy H2010Core.intTy H2010Core.intTy
      fBinder = coreBinder f fTy
      xBinder = coreBinder x H2010Core.intTy
      rhs =
        H2010Core.CLam
          xBinder
          ( H2010Core.CApp
              (H2010Core.CVar f fTy)
              (H2010Core.CVar x H2010Core.intTy)
              H2010Core.intTy
          )
          fTy
      expression =
        H2010Core.CLet
          (H2010Core.CoreRec [(fBinder, rhs)])
          (H2010Core.CVar f fTy)
          fTy
  expectEqual "Core recursive binding validates" (Right ()) (H2010CoreValidate.validateExpr expression)

testHaskell2010CoreCaseAlternativeMismatch :: Either String ()
testHaskell2010CoreCaseAlternativeMismatch = do
  let scrutinee = coreTerm "scrutinee" 106
      caseBinder = coreBinder scrutinee H2010Core.boolTy
      expression =
        H2010Core.CCase
          coreTrue
          caseBinder
          [ H2010Core.CoreAlt (H2010Core.ConstructorAlt H2010Core.trueDataConName) [] (coreInt 1)
          , H2010Core.CoreAlt (H2010Core.ConstructorAlt H2010Core.falseDataConName) [] coreTrue
          ]
          H2010Core.intTy
  expectCoreValidationError
    "Core case alternative result mismatch"
    ( \case
        H2010CoreValidate.CoreAlternativeTypeMismatch (H2010Core.ConstructorAlt name) expected actual ->
          name == H2010Core.falseDataConName
            && expected == H2010Core.intTy
            && actual == H2010Core.boolTy
        _ -> False
    )
    (H2010CoreValidate.validateExpr expression)

testHaskell2010CoreFreeVariables :: Either String ()
testHaskell2010CoreFreeVariables = do
  let x = coreTerm "x" 107
      y = coreTerm "y" 108
      z = coreTerm "z" 109
      xBinder = coreBinder x H2010Core.intTy
      yBinder = coreBinder y H2010Core.intTy
      expression =
        H2010Core.CLam
          xBinder
          ( H2010Core.CLet
              (H2010Core.CoreNonRec yBinder (H2010Core.CVar z H2010Core.intTy))
              ( H2010Core.CPrimOp
                  H2010Core.PrimAdd
                  [H2010Core.CVar x H2010Core.intTy, H2010Core.CVar y H2010Core.intTy]
                  H2010Core.intTy
              )
              H2010Core.intTy
          )
          (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
  expectEqual "Core free variables" (Set.singleton z) (H2010CoreFreeVars.freeVarsExpr expression)

testHaskell2010CoreSubstitution :: Either String ()
testHaskell2010CoreSubstitution = do
  let x = coreTerm "x" 110
      z = coreTerm "z" 111
      xBinder = coreBinder x H2010Core.intTy
      replacement = coreInt 3
      shadowed =
        H2010Core.CLam
          xBinder
          (H2010Core.CVar x H2010Core.intTy)
          (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
      letExpression =
        H2010Core.CLet
          (H2010Core.CoreNonRec xBinder (H2010Core.CVar z H2010Core.intTy))
          (H2010Core.CVar x H2010Core.intTy)
          H2010Core.intTy
      expectedLet =
        H2010Core.CLet
          (H2010Core.CoreNonRec xBinder replacement)
          (H2010Core.CVar x H2010Core.intTy)
          H2010Core.intTy
      captureRisk =
        H2010Core.CLam
          xBinder
          (H2010Core.CVar z H2010Core.intTy)
          (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
  expectEqual "Core substitution skips shadowed lambda binder" shadowed (H2010CoreSubst.substExpr x replacement shadowed)
  expectEqual "Core substitution rewrites nonrecursive let RHS" expectedLet (H2010CoreSubst.substExpr z replacement letExpression)
  case H2010CoreSubst.substExpr z (H2010Core.CVar x H2010Core.intTy) captureRisk of
    H2010Core.CLam renamedBinder (H2010Core.CVar bodyName _) _ ->
      assertBool "Core substitution alpha-renames capture-risk binder" (H2010Core.coreBinderName renamedBinder /= x)
        *> expectEqual "Core substitution keeps replacement free" x bodyName
    other -> Left ("unexpected Core substitution alpha-renamed expression: " <> show other)

testHaskell2010CorePretty :: Either String ()
testHaskell2010CorePretty = do
  let x = coreTerm "x" 100
      expression =
        H2010Core.CLam
          (coreBinder x H2010Core.intTy)
          (H2010Core.CVar x H2010Core.intTy)
          (H2010Core.funTy H2010Core.intTy H2010Core.intTy)
  expectEqualText
    "Core pretty output"
    "(\\x#100 : Int#-1 -> x#100 : Int#-1) : Int#-1 -> Int#-1"
    (H2010CorePretty.renderCoreExpr expression)

testHaskell2010Core0Identity :: Either String ()
testHaskell2010Core0Identity = do
  coreModule <-
    typecheckHaskell2010
      "module Core0 where\n\
      \id :: a -> a\n\
      \id x = x\n"
  case H2010Core.coreModuleBinds coreModule of
    [H2010Core.CoreNonRec binder (H2010Core.CTypeLam [_] (H2010Core.CLam param (H2010Core.CVar bodyName _) _) binderTy)] -> do
      expectEqual "id Core binder type" binderTy (H2010Core.coreBinderType binder)
      expectEqual "id body returns lambda parameter" (H2010Core.coreBinderName param) bodyName
      assertBool "id Core binder is polymorphic" (isForallType binderTy)
    other -> Left ("unexpected Core-0 id module: " <> show other)

testHaskell2010Core0Const :: Either String ()
testHaskell2010Core0Const = do
  coreModule <-
    typecheckHaskell2010
      "module Core0 where\n\
      \const :: a -> b -> a\n\
      \const x y = x\n"
  case H2010Core.coreModuleBinds coreModule of
    [H2010Core.CoreNonRec binder (H2010Core.CTypeLam variables (H2010Core.CLam xBinder (H2010Core.CLam _ (H2010Core.CVar bodyName _) _) _) binderTy)] -> do
      expectEqual "const quantifier count" 2 (length variables)
      expectEqual "const body returns first parameter" (H2010Core.coreBinderName xBinder) bodyName
      expectEqual "const Core binder type" binderTy (H2010Core.coreBinderType binder)
    other -> Left ("unexpected Core-0 const module: " <> show other)

testHaskell2010Core0PolymorphicLet :: Either String ()
testHaskell2010Core0PolymorphicLet = do
  coreModule <-
    typecheckHaskell2010
      "module Core0 where\n\
      \use = let\n\
      \  id x = x\n\
      \in if id True then id 1 else id 2\n"
  (binder, rhs) <- lookupCoreBindingOccurrence "use" coreModule
  expectEqual "polymorphic let result type" H2010Core.intTy (H2010Core.coreBinderType binder)
  assertBool "polymorphic let emits type applications" (countTypeApps rhs >= 3)
  assertBool "polymorphic let emits generalized local binding" (containsTypeLambda rhs)
  expectEqual
    "polymorphic let generated Core validates"
    (Right ())
    (H2010CoreValidate.validateModule (H2010CoreValidate.moduleValidationEnv coreModule) coreModule)

testHaskell2010KindRepresentation :: Either String ()
testHaskell2010KindRepresentation = do
  let star = H2010Typecheck.StarKind
      unary = H2010Typecheck.KindArrow star star
      binary = H2010Typecheck.KindArrow star unary
      higher = H2010Typecheck.KindArrow unary star
      unaryInfo = H2010Typecheck.typeConstructorInfo 1
      binaryInfo = H2010Typecheck.typeConstructorInfo 2
  expectEqual "nullary kind" star (H2010Typecheck.kindFromArity 0)
  expectEqual "unary kind" unary (H2010Typecheck.typeConstructorKind unaryInfo)
  expectEqual "binary kind" binary (H2010Typecheck.typeConstructorKind binaryInfo)
  expectEqual "binary arity" 2 (H2010Typecheck.typeConstructorArity binaryInfo)
  expectEqual "render binary kind" "* -> * -> *" (H2010Typecheck.renderKind binary)
  expectEqual "render higher-kinded argument" "(* -> *) -> *" (H2010Typecheck.renderKind higher)

testHaskell2010KindChecksHigherKindedConstructors :: Either String ()
testHaskell2010KindChecksHigherKindedConstructors =
  expectCoreEvalInt
    "higher-kinded constructor kind inference"
    1
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \data Wrap f = Wrap (f Int)\n\
      \use :: Wrap Maybe -> Int\n\
      \use _ = 1\n\
      \main = use (Wrap (Just 3))\n"

testHaskell2010KindRejectsMismatch :: Either String ()
testHaskell2010KindRejectsMismatch =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \data Box a = Box a\n\
      \bad :: Box -> Int\n\
      \bad _ = 0\n\
      \main = 0\n"
    of
      Left err
        | H2010Typecheck.KindMismatch {} <- haskell2010TypecheckErrorDetail err -> Right ()
      Left err -> Left ("expected kind mismatch, got: " <> show err)
      Right coreModule -> Left ("kind-mismatched source typechecked unexpectedly: " <> show coreModule)

testHaskell2010TypeSynonymExpansion :: Either String ()
testHaskell2010TypeSynonymExpansion =
  expectCoreEvalInt
    "type synonym expansion"
    42
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \type Age = Int\n\
      \type Pair a = (a, a)\n\
      \data Box a = Box (Pair a)\n\
      \firstAge :: Box Age -> Age\n\
      \firstAge (Box (x, _)) = x\n\
      \main = firstAge (Box (42, 0))\n"

testHaskell2010TypeSynonymKindInference :: Either String ()
testHaskell2010TypeSynonymKindInference =
  expectCoreEvalInt
    "higher-kinded type synonym kind inference"
    7
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \type Apply f = f Int\n\
      \data Wrap f = Wrap (Apply f)\n\
      \use :: Wrap Maybe -> Int\n\
      \use (Wrap (Just n)) = n\n\
      \main = use (Wrap (Just 7))\n"

testHaskell2010TypeSynonymRejectsCycles :: Either String ()
testHaskell2010TypeSynonymRejectsCycles =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \type A = B\n\
      \type B = A\n\
      \main = 0\n"
    of
      Left H2010Typecheck.RecursiveTypeSynonym {} -> Right ()
      Left err -> Left ("expected recursive type synonym rejection, got: " <> show err)
      Right coreModule -> Left ("recursive type synonyms typechecked unexpectedly: " <> show coreModule)

testHaskell2010NewtypeTyping :: Either String ()
testHaskell2010NewtypeTyping =
  expectCoreEvalInt
    "newtype constructor and pattern typing"
    42
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \newtype Age = Age Int\n\
      \unAge :: Age -> Int\n\
      \unAge (Age n) = n\n\
      \main = unAge (Age 42)\n"

testHaskell2010NewtypeRepresentation :: Either String ()
testHaskell2010NewtypeRepresentation = do
  coreModule <- typecheckHaskell2010 haskell2010NewtypeRepresentationSource
  (_, ageInfo) <- lookupUserConstructorOccurrence "Age" coreModule
  expectEqual "Age constructor representation" H2010Core.CoreNewtypeConstructor (H2010Core.constructorRepresentation ageInfo)
  (_, unAgeRhs) <- lookupCoreBindingOccurrence "unAge" coreModule
  assertBool "newtype pattern erases constructor case" (not (containsConstructorAlt "Age" unAgeRhs))
  assertBool "newtype pattern emits representation coercion" (containsCoerce unAgeRhs)
  (_, mainRhs) <- lookupCoreBindingOccurrence "main" coreModule
  assertBool "newtype construction emits representation coercion" (containsCoerce mainRhs)
  assertBool "newtype construction emits no Age constructor value" (not (containsConstructorExpr "Age" mainRhs))
  expectCoreEvalInt "newtype representation Core oracle" 42 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010NewtypeKindInference :: Either String ()
testHaskell2010NewtypeKindInference =
  expectCoreEvalInt
    "higher-kinded newtype parameter inference"
    7
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \newtype Wrap f = Wrap (f Int)\n\
      \use :: Wrap Maybe -> Int\n\
      \use (Wrap (Just n)) = n\n\
      \main = use (Wrap (Just 7))\n"

testHaskell2010NewtypeRejectsInvalidArity :: Either String ()
testHaskell2010NewtypeRejectsInvalidArity =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \newtype Bad = Bad Int Bool\n\
      \main = 0\n"
    of
      Left err
        | H2010Typecheck.InvalidNewtypeConstructorArity {} <- haskell2010TypecheckErrorDetail err -> Right ()
      Left err -> Left ("expected invalid newtype constructor arity, got: " <> show err)
      Right coreModule -> Left ("invalid newtype constructor typechecked unexpectedly: " <> show coreModule)

testHaskell2010RecordFieldLabels :: Either String ()
testHaskell2010RecordFieldLabels = do
  coreModule <- typecheckHaskell2010 haskell2010RecordFieldSource
  assertBool "record selector age is emitted" (containsBindingOccurrence "age" coreModule)
  assertBool "record selector score is emitted" (containsBindingOccurrence "score" coreModule)
  (_, ageRhs) <- lookupCoreBindingOccurrence "age" coreModule
  assertBool "data record selector lowers to Core case" (containsCase ageRhs)
  expectCoreEvalInt "record field selector/pattern Core oracle" 43 =<< evalHaskell2010CoreModuleBinding "main" coreModule
  newtypeModule <- typecheckHaskell2010 haskell2010NewtypeRecordFieldSource
  (_, unAgeRhs) <- lookupCoreBindingOccurrence "unAge" newtypeModule
  assertBool "newtype record selector lowers to coercion" (containsCoerce unAgeRhs)
  assertBool "newtype record selector avoids constructor case" (not (containsConstructorAlt "Age" unAgeRhs))
  expectCoreEvalInt "newtype record selector Core oracle" 42 =<< evalHaskell2010CoreModuleBinding "main" newtypeModule

testHaskell2010RecordRejectsIncompleteConstruction :: Either String ()
testHaskell2010RecordRejectsIncompleteConstruction =
  case
    typecheckHaskell2010Raw
      "module Main where\n\
      \data Person = Person { age :: Int, score :: Int }\n\
      \main = Person { age = 1 }\n"
    of
      Left err
        | "missing fields" `Text.isInfixOf` H2010Typecheck.renderTypecheckError err -> Right ()
      Left err -> Left ("expected incomplete record construction rejection, got: " <> show err)
      Right coreModule -> Left ("incomplete record construction typechecked unexpectedly: " <> show coreModule)

testHaskell2010IrrefutablePatterns :: Either String ()
testHaskell2010IrrefutablePatterns = do
  coreModule <- typecheckHaskell2010 haskell2010IrrefutablePatternSource
  expectEqual
    "irrefutable pattern Core validates"
    (Right ())
    (H2010CoreValidate.validateModule (H2010CoreValidate.moduleValidationEnv coreModule) coreModule)
  expectCoreEvalInt "irrefutable/lazy pattern Core oracle" 7 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010IrrefutablePatternDemand :: Either String ()
testHaskell2010IrrefutablePatternDemand =
  case evalHaskell2010BindingRaw "main" haskell2010IrrefutablePatternDemandSource of
    Left H2010CoreEval.CoreEvalNoMatchingAlternative {} -> Right ()
    Left err -> Left ("expected demanded lazy pattern mismatch, got: " <> show err)
    Right value -> Left ("demanded lazy pattern mismatch evaluated unexpectedly: " <> show value)

testHaskell2010ConstraintRepresentation :: Either String ()
testHaskell2010ConstraintRepresentation =
  expectCoreEvalInt
    "constraint representation with synonym argument"
    1
    =<< evalHaskell2010Binding
      "main"
      "module Core0 where\n\
      \type Id a = a\n\
      \same :: Eq (Id a) => Id a -> Id a -> Int\n\
      \same x y = if x == y then 1 else 0\n\
      \main = same 7 7\n"

testHaskell2010ConstraintRejectsInvalidArity :: Either String ()
testHaskell2010ConstraintRejectsInvalidArity =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \bad :: Eq Int Bool => Int\n\
      \bad = 0\n\
      \main = bad\n"
    of
      Left err
        | H2010Typecheck.InvalidClassConstraintArity {} <- haskell2010TypecheckErrorDetail err -> Right ()
      Left err -> Left ("expected invalid class constraint arity, got: " <> show err)
      Right coreModule -> Left ("invalid class constraint arity typechecked unexpectedly: " <> show coreModule)

testHaskell2010ClassConstraintPlaceholders :: Either String ()
testHaskell2010ClassConstraintPlaceholders =
  expectPlaceholder "superclass constraint context" superclassSource
    *> expectPlaceholder "method-specific constraint context" methodConstraintSource
    *> expectPlaceholder "instance constraint context" instanceContextSource
    *> expectPlaceholder "expression signature constraint context" expressionSignatureSource
 where
  expectPlaceholder label source =
    case typecheckHaskell2010Raw source of
      Left err
        | H2010Typecheck.UnsupportedClassConstraintContext _ constraints <- haskell2010TypecheckErrorDetail err
        , not (null constraints) -> Right ()
      Left err -> Left (label <> ": expected unsupported class-constraint context, got " <> show err)
      Right coreModule -> Left (label <> ": typechecked unexpectedly: " <> show coreModule)

  superclassSource =
    "module Core0 where\n\
    \class Eq a => Ordered a where\n\
    \  ordered :: a -> a -> Bool\n\
    \main = 0\n"

  methodConstraintSource =
    "module Core0 where\n\
    \class Sized a where\n\
    \  same :: Eq a => a -> a -> Bool\n\
    \main = 0\n"

  instanceContextSource =
    "module Core0 where\n\
    \class Sized a where\n\
    \  size :: a -> Int\n\
    \data Box a = Box a\n\
    \instance Eq a => Sized (Box a) where\n\
    \  size _ = 1\n\
    \main = 0\n"

  expressionSignatureSource =
    "module Core0 where\n\
    \main = (1 :: Eq Int => Int)\n"

testHaskell2010Core0If :: Either String ()
testHaskell2010Core0If = do
  coreModule <-
    typecheckHaskell2010
      "module Core0 where\n\
      \choose :: Bool -> Int\n\
      \choose b = if b then 1 else 2\n"
  (binder, rhs) <- lookupCoreBindingOccurrence "choose" coreModule
  expectEqual
    "if function type"
    (H2010Core.funTy H2010Core.boolTy H2010Core.intTy)
    (H2010Core.coreBinderType binder)
  assertBool "if desugars to Core case" (containsCase rhs)

testHaskell2010Core0Case :: Either String ()
testHaskell2010Core0Case = do
  coreModule <-
    typecheckHaskell2010
      "module Core0 where\n\
      \select :: Bool -> Int\n\
      \select b = case b of\n\
      \  True -> 1\n\
      \  False -> 0\n"
  (binder, rhs) <- lookupCoreBindingOccurrence "select" coreModule
  expectEqual
    "case function type"
    (H2010Core.funTy H2010Core.boolTy H2010Core.intTy)
    (H2010Core.coreBinderType binder)
  assertBool "explicit Bool case remains Core case" (containsCase rhs)

testHaskell2010Core0ADTConstructorCase :: Either String ()
testHaskell2010Core0ADTConstructorCase = do
  coreModule <- typecheckHaskell2010 haskell2010ADTBoxSource
  expectEqual "Box user constructor metadata count" 1 (Map.size (userConstructorMetadata coreModule))
  (binder, rhs) <- lookupCoreBindingOccurrence "main" coreModule
  expectEqual "ADT case result type" H2010Core.intTy (H2010Core.coreBinderType binder)
  assertBool "user ADT case emits Core case" (containsCase rhs)
  assertBool "user ADT case records constructor alternative" (containsConstructorAlt "Box" rhs)

testHaskell2010Core0NestedADTPatterns :: Either String ()
testHaskell2010Core0NestedADTPatterns = do
  coreModule <- typecheckHaskell2010 haskell2010NestedADTSource
  expectEqual "nested ADT user constructor metadata count" 2 (Map.size (userConstructorMetadata coreModule))
  (binder, rhs) <- lookupCoreBindingOccurrence "main" coreModule
  expectEqual "nested ADT result type" H2010Core.intTy (H2010Core.coreBinderType binder)
  assertBool "nested ADT pattern emits nested Core case" (countCases rhs >= 2)
  assertBool "nested ADT pattern records outer constructor" (containsConstructorAlt "Wrap" rhs)
  assertBool "nested ADT pattern records inner constructor" (containsConstructorAlt "Box" rhs)

userConstructorMetadata :: H2010Core.CoreModule -> Map.Map H2010Names.RName H2010Core.CoreConstructorInfo
userConstructorMetadata =
  Map.filterWithKey
    ( \name _ ->
        not (H2010Names.nameExternal name)
          && not ("$Mk" `Text.isPrefixOf` H2010Names.nameOcc name)
    )
    . H2010Core.coreModuleConstructors

lookupUserConstructorOccurrence :: Text -> H2010Core.CoreModule -> Either String (H2010Names.RName, H2010Core.CoreConstructorInfo)
lookupUserConstructorOccurrence occurrence coreModule =
  case List.find ((== occurrence) . H2010Names.nameOcc . fst) (Map.toList (userConstructorMetadata coreModule)) of
    Just pair -> Right pair
    Nothing -> Left ("missing user Core constructor `" <> Text.unpack occurrence <> "`")

testHaskell2010Core0PreludeData :: Either String ()
testHaskell2010Core0PreludeData = do
  tupleModule <- typecheckHaskell2010 haskell2010TupleCaseSource
  expectCoreEvalInt "tuple-pattern Core oracle" 3 =<< evalHaskell2010CoreModuleBinding "main" tupleModule
  listModule <- typecheckHaskell2010 haskell2010ListPreludeSource
  expectCoreEvalInt "Prelude list Core oracle" 321 =<< evalHaskell2010CoreModuleBinding "main" listModule
  maybeModule <- typecheckHaskell2010 haskell2010PreludeMaybeOrderingSource
  expectCoreEvalInt "Prelude Maybe/Ordering Core oracle" 5 =<< evalHaskell2010CoreModuleBinding "main" maybeModule

testHaskell2010Core0Recursion :: Either String ()
testHaskell2010Core0Recursion = do
  guardedModule <- typecheckHaskell2010 haskell2010GuardedSelfRecursionSource
  (binder, rhs) <- lookupCoreBindingOccurrence "main" guardedModule
  expectEqual "guarded self recursion binder" "main" (H2010Names.nameOcc (H2010Core.coreBinderName binder))
  assertBool "guarded self recursion keeps recursive occurrence" (containsVarOccurrence "main" rhs)
  expectCoreEvalInt "guarded self-recursion Core oracle" 1 =<< evalHaskell2010CoreModuleBinding "main" guardedModule
  expectCoreEvalInt "local factorial Core oracle" 120 =<< evalHaskell2010Binding "main" haskell2010LocalFactorialSource
  expectCoreEvalInt "mutual recursion Core oracle" 1 =<< evalHaskell2010Binding "main" haskell2010MutualRecursionSource
  expectCoreEvalInt "recursive list Core oracle" 10 =<< evalHaskell2010Binding "main" haskell2010RecursiveListSource

testHaskell2010RecursivePatternBindings :: Either String ()
testHaskell2010RecursivePatternBindings = do
  coreModule <- typecheckHaskell2010 haskell2010RecursivePatternBindingSource
  assertBool
    "recursive pattern selectors are emitted"
    (all (`containsBindingOccurrence` coreModule) ["ones", "x", "xs"])
  assertBool
    "recursive pattern selectors share a Core recursive group"
    (coreModuleHasRecursiveOccurrences ["x", "xs"] coreModule)
  expectCoreEvalInt "recursive pattern binding Core oracle" 2 =<< evalHaskell2010CoreModuleBinding "main" coreModule
  checkCoreToSTGInt "recursive pattern binding" 2 haskell2010RecursivePatternBindingSource

testHaskell2010Core0TypeClassDictionaries :: Either String ()
testHaskell2010Core0TypeClassDictionaries = do
  coreModule <- typecheckHaskell2010 haskell2010TypeClassDictionarySource
  assertBool "type class dictionary constructor is recorded" (containsConstructorOccurrence "$MkEqualDict" coreModule)
  assertBool "type class method selector is emitted" (containsBindingOccurrence "equal" coreModule)
  assertBool "type class instance dictionary is emitted" (containsBindingPrefix "$fEqual" coreModule)
  expectCoreEvalInt "type class dictionary Core oracle" 1 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0PreludeClassDictionaries :: Either String ()
testHaskell2010Core0PreludeClassDictionaries = do
  coreModule <- typecheckHaskell2010 haskell2010PreludeClassDictionarySource
  assertBool "Prelude Eq dictionary constructor is recorded" (containsConstructorOccurrence "$MkEqDict" coreModule)
  assertBool "Prelude Ord dictionary constructor is recorded" (containsConstructorOccurrence "$MkOrdDict" coreModule)
  assertBool "Prelude Num dictionary constructor is recorded" (containsConstructorOccurrence "$MkNumDict" coreModule)
  assertBool "Prelude Eq Int instance dictionary is emitted" (containsBindingOccurrence "$fEqInt" coreModule)
  assertBool "Prelude Ord Int instance dictionary is emitted" (containsBindingOccurrence "$fOrdInt" coreModule)
  assertBool "Prelude Num Int instance dictionary is emitted" (containsBindingOccurrence "$fNumInt" coreModule)
  expectCoreEvalInt "Prelude class dictionary Core oracle" 6 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0CharRuntime :: Either String ()
testHaskell2010Core0CharRuntime = do
  coreModule <- typecheckHaskell2010 haskell2010CharRuntimeSource
  assertBool "Prelude Eq Char instance dictionary is emitted" (containsBindingOccurrence "$fEqChar" coreModule)
  expectCoreEvalInt "Char runtime Core oracle" 1 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0StringCharList :: Either String ()
testHaskell2010Core0StringCharList = do
  coreModule <- typecheckHaskell2010 haskell2010StringCharListSource
  (binder, rhs) <- lookupCoreBindingOccurrence "main" coreModule
  expectEqual "String Char-list result type" H2010Core.intTy (H2010Core.coreBinderType binder)
  assertBool "source String literals desugar before Core" (not (coreModuleContainsStringLiteral coreModule))
  assertBool "String literal pattern emits cons alternatives" (containsConstructorAlt ":" rhs)
  assertBool "String literal pattern emits nil alternatives" (containsConstructorAlt "[]" rhs)
  assertBool "String literal expressions emit cons constructors" (containsConstructorExpr ":" rhs)
  expectCoreEvalInt "String Char-list Core oracle" 5 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0NumericDefaulting :: Either String ()
testHaskell2010Core0NumericDefaulting = do
  coreModule <- typecheckHaskell2010 haskell2010NumericDefaultingSource
  assertBool "Prelude Num dictionary constructor is recorded" (containsConstructorOccurrence "$MkNumDict" coreModule)
  assertBool "Prelude Num Int instance dictionary is emitted" (containsBindingOccurrence "$fNumInt" coreModule)
  assertBool "Prelude fromInteger selector is emitted" (containsBindingOccurrence "fromInteger" coreModule)
  assertBool "Prelude Show Int instance dictionary is emitted" (containsBindingOccurrence "$fShowInt" coreModule)
  expectCoreEvalIO "numeric defaulting Core oracle" "7\n47\n" =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010MonomorphismRestrictionDefaulting :: Either String ()
testHaskell2010MonomorphismRestrictionDefaulting = do
  coreModule <- typecheckHaskell2010 haskell2010MonomorphismRestrictionSource
  assertBool "MR defaulting emits Num Int dictionary" (containsBindingOccurrence "$fNumInt" coreModule)
  assertBool "MR defaulting emits Eq Int dictionary" (containsBindingOccurrence "$fEqInt" coreModule)
  expectCoreEvalInt "monomorphism restriction defaulting oracle" 1 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0MultiModuleImports :: Either String ()
testHaskell2010Core0MultiModuleImports = do
  coreModule <- typecheckHaskell2010Modules haskell2010MultiModuleSources
  assertBool "dependency binding is emitted" (containsBindingOccurrence "double" coreModule)
  assertBool "imported constructor metadata is emitted" (containsConstructorOccurrence "Box" coreModule)
  expectCoreEvalInt "multi-module Core oracle" 24 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0IOPrinting :: Either String ()
testHaskell2010Core0IOPrinting = do
  coreModule <- typecheckHaskell2010 haskell2010IOPrintingSource
  assertBool "Prelude Show dictionary constructor is recorded" (containsConstructorOccurrence "$MkShowDict" coreModule)
  assertBool "Prelude Show Int instance dictionary is emitted" (containsBindingOccurrence "$fShowInt" coreModule)
  assertBool "Prelude Show Bool instance dictionary is emitted" (containsBindingOccurrence "$fShowBool" coreModule)
  assertBool "Prelude putStrLn binding is emitted" (containsBindingOccurrence "putStrLn" coreModule)
  assertBool "Prelude print binding is emitted" (containsBindingOccurrence "print" coreModule)
  assertBool "Prelude return binding is emitted" (containsBindingOccurrence "return" coreModule)
  assertBool "Prelude >> binding is emitted" (containsBindingOccurrence ">>" coreModule)
  expectCoreEvalIO "IO printing Core oracle" "ok\nanswer\n42\nTrue\n" =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0GuardsAndAsPatterns :: Either String ()
testHaskell2010Core0GuardsAndAsPatterns = do
  coreModule <- typecheckHaskell2010 haskell2010GuardAsPatternSource
  assertBool "guarded RHS emits Bool case" (countCasesInModule coreModule >= 3)
  assertBool "as-pattern alias is emitted" (moduleContainsVarOccurrence "xs" coreModule || moduleContainsVarOccurrence "ys" coreModule)
  expectCoreEvalInt "guard/as-pattern Core oracle" 15 =<< evalHaskell2010CoreModuleBinding "main" coreModule

testHaskell2010Core0Sections :: Either String ()
testHaskell2010Core0Sections = do
  coreModule <- typecheckHaskell2010 haskell2010SectionsSource
  (leftBinder, leftRhs) <- lookupCoreBindingOccurrence "left" coreModule
  (rightBinder, rightRhs) <- lookupCoreBindingOccurrence "right" coreModule
  (overBinder, overRhs) <- lookupCoreBindingOccurrence "over" coreModule
  (shortBinder, shortRhs) <- lookupCoreBindingOccurrence "short" coreModule
  expectEqual "left section type" intToInt (H2010Core.coreBinderType leftBinder)
  expectEqual "right section type" intToInt (H2010Core.coreBinderType rightBinder)
  expectEqual "comparison right section type" (H2010Core.funTy H2010Core.intTy H2010Core.boolTy) (H2010Core.coreBinderType overBinder)
  expectEqual "short-circuit left section type" (H2010Core.funTy H2010Core.boolTy H2010Core.boolTy) (H2010Core.coreBinderType shortBinder)
  assertBool "left section emits Core lambda" (containsTermLambda leftRhs)
  assertBool "right section emits Core lambda" (containsTermLambda rightRhs)
  assertBool "comparison section emits Core lambda" (containsTermLambda overRhs)
  assertBool "short-circuit section emits Core lambda" (containsTermLambda shortRhs)
  assertBool "short-circuit section keeps lazy Bool case" (containsCase shortRhs)
  expectCoreEvalInt "operator section Core oracle" 6 =<< evalHaskell2010CoreModuleBinding "main" coreModule
 where
  intToInt = H2010Core.funTy H2010Core.intTy H2010Core.intTy

testHaskell2010Core0RejectsInvalidTypeClassDictionaries :: Either String ()
testHaskell2010Core0RejectsInvalidTypeClassDictionaries =
  expectTypecheckMessage "rejects duplicate concrete instances" "duplicate instance" duplicateInstanceSource
    *> expectTypecheckMessage "rejects missing instance methods" "missing instance method" missingInstanceMethodSource
    *> expectTypecheckMessage "rejects unsolved Prelude class dictionaries" "unsolved type-class constraint" unsolvedPreludeConstraintSource
 where
  expectTypecheckMessage label needle source =
    case typecheckHaskell2010Raw source of
      Left err
        | needle `Text.isInfixOf` H2010Typecheck.renderTypecheckError err -> Right ()
      Left err -> Left (label <> ": expected type class dictionary diagnostic, got " <> show err)
      Right coreModule -> Left (label <> ": typechecked unexpectedly: " <> show coreModule)

  duplicateInstanceSource =
    "module Main where\n\
    \class Equal a where\n\
    \  equal :: a -> a -> Bool\n\
    \data Box = Box Int\n\
    \instance Equal Box where\n\
    \  equal (Box x) (Box y) = x == y\n\
    \instance Equal Box where\n\
    \  equal (Box x) (Box y) = x == y\n\
    \main = 1\n"

  missingInstanceMethodSource =
    "module Main where\n\
    \class Equal a where\n\
    \  equal :: a -> a -> Bool\n\
    \data Box = Box Int\n\
    \instance Equal Box where {}\n\
    \main = 1\n"

  unsolvedPreludeConstraintSource =
    "module Main where\n\
    \data Box = Box Int\n\
    \main = if Box 1 == Box 1 then 1 else 0\n"

testHaskell2010Core0TypeError :: Either String ()
testHaskell2010Core0TypeError =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \bad :: Int\n\
      \bad = True\n"
    of
      Left err
        | H2010Typecheck.TypeMismatch {} <- haskell2010TypecheckErrorDetail err -> Right ()
      Left err -> Left ("expected Core-0 type mismatch, got: " <> show err)
      Right coreModule -> Left ("ill-typed Core-0 source typechecked unexpectedly: " <> show coreModule)

testHaskell2010TypeErrorDiagnosticsWithSpans :: Either String ()
testHaskell2010TypeErrorDiagnosticsWithSpans =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \main = 1 + True\n"
    of
      Left err@(H2010Typecheck.TypecheckErrorAt sourceRange _) -> do
        expectEqual "type error span file" "<haskell2010-renamer-test>" (spanFile sourceRange)
        expectEqual "type error span start line" 2 (spanStartLine sourceRange)
        expectEqual "type error span start column" 8 (spanStartColumn sourceRange)
        assertBool
          "rendered diagnostic includes source span and type-error severity"
          ("<haskell2010-renamer-test>:2:8-" `Text.isPrefixOf` H2010Typecheck.renderTypecheckError err)
        assertBool
          "rendered diagnostic identifies unsolved class constraint"
          ("unsolved type-class constraint" `Text.isInfixOf` H2010Typecheck.renderTypecheckError err)
      Left err -> Left ("expected source-spanned type error, got: " <> show err)
      Right coreModule -> Left ("ill-typed source typechecked unexpectedly: " <> show coreModule)

testHaskell2010ExhaustivenessWarningPlaceholders :: Either String ()
testHaskell2010ExhaustivenessWarningPlaceholders = do
  partialCase <- typecheckHaskell2010WithWarnings haskell2010PartialCaseWarningSource
  let partialCaseWarnings = H2010Typecheck.typecheckResultWarnings partialCase
  assertBool
    "partial case emits a case warning"
    (warningMentionsCase partialCaseWarnings)
  assertBool
    "partial case warning has a source span"
    (warningHasTestSourceSpan partialCaseWarnings)

  totalCase <- typecheckHaskell2010WithWarnings haskell2010TotalBoolCaseWarningSource
  expectEqual "total Bool case has no warnings" [] (H2010Typecheck.typecheckResultWarnings totalCase)

  totalADTCase <- typecheckHaskell2010WithWarnings haskell2010TotalADTCaseWarningSource
  expectEqual "total user ADT case has no warnings" [] (H2010Typecheck.typecheckResultWarnings totalADTCase)

  partialFunction <- typecheckHaskell2010WithWarnings haskell2010PartialFunctionWarningSource
  assertBool
    "partial function emits a function warning"
    (warningMentionsFunction (H2010Typecheck.typecheckResultWarnings partialFunction))

  nativeResult <- compileHaskell2010Native haskell2010PartialCaseWarningSource
  assertBool
    "native result exposes typecheck warnings"
    (warningMentionsCase (H2010Native.haskell2010Warnings nativeResult))
 where
  renderedWarnings =
    map H2010Typecheck.renderTypecheckWarning

  warningMentionsCase warnings =
    any
      ( \rendered ->
          "non-exhaustive pattern match placeholder" `Text.isInfixOf` rendered
            && "case alternatives" `Text.isInfixOf` rendered
      )
      (renderedWarnings warnings)

  warningMentionsFunction warnings =
    any
      ( \rendered ->
          "non-exhaustive pattern match placeholder" `Text.isInfixOf` rendered
            && "function `fromJust" `Text.isInfixOf` rendered
      )
      (renderedWarnings warnings)

  warningHasTestSourceSpan warnings =
    any
      ("<haskell2010-renamer-test>:" `Text.isPrefixOf`)
      (renderedWarnings warnings)

testHaskell2010Core0UnsupportedEquality :: Either String ()
testHaskell2010Core0UnsupportedEquality =
  case
    typecheckHaskell2010Raw
      "module Core0 where\n\
      \bad :: (Int -> Int) -> (Int -> Int) -> Bool\n\
      \bad f g = f == g\n"
    of
      Left err
        | "unsolved type-class constraint" `Text.isInfixOf` H2010Typecheck.renderTypecheckError err -> Right ()
      Left err -> Left ("expected unsupported Core-0 equality, got: " <> show err)
      Right coreModule -> Left ("unsupported Core-0 equality typechecked unexpectedly: " <> show coreModule)

testHaskell2010Core0EvalArithmetic :: Either String ()
testHaskell2010Core0EvalArithmetic =
  expectCoreEvalInt
    "Core-0 arithmetic evaluation"
    9
    =<< evalHaskell2010Binding
      "main"
      "module Eval where\n\
      \main = (1 + 2) * 3\n"

testHaskell2010Core0EvalPolymorphicIdentity :: Either String ()
testHaskell2010Core0EvalPolymorphicIdentity =
  expectCoreEvalInt
    "Core-0 polymorphic identity evaluation"
    42
    =<< evalHaskell2010Binding
      "main"
      "module Eval where\n\
      \id :: a -> a\n\
      \id x = x\n\
      \main = id 42\n"

testHaskell2010Core0EvalBoolCase :: Either String ()
testHaskell2010Core0EvalBoolCase =
  expectCoreEvalInt
    "Core-0 Bool case evaluation"
    7
    =<< evalHaskell2010Binding
      "main"
      "module Eval where\n\
      \main = case False of\n\
      \  True -> 0\n\
      \  False -> 7\n"

testHaskell2010Core0EvalADTField :: Either String ()
testHaskell2010Core0EvalADTField =
  expectCoreEvalInt
    "Core-0 user ADT field evaluation"
    7
    =<< evalHaskell2010Binding "main" haskell2010ADTBoxSource

testHaskell2010Core0EvalLazyADTField :: Either String ()
testHaskell2010Core0EvalLazyADTField =
  expectCoreEvalInt
    "Core-0 lazy ADT field evaluation"
    5
    =<< evalHaskell2010Binding "main" haskell2010LazyADTFieldSource

testHaskell2010Core0EvalPreludeLists :: Either String ()
testHaskell2010Core0EvalPreludeLists =
  expectCoreEvalInt
    "Core-0 Prelude list function evaluation"
    321
    =<< evalHaskell2010Binding "main" haskell2010ListPreludeSource

testHaskell2010Core0EvalShortCircuitBool :: Either String ()
testHaskell2010Core0EvalShortCircuitBool =
  expectCoreEvalInt
    "Core-0 Bool short-circuit evaluation"
    7
    =<< evalHaskell2010Binding "main" haskell2010ShortCircuitSource

testHaskell2010Core0EvalRecursion :: Either String ()
testHaskell2010Core0EvalRecursion =
  sequence_
    [ expectCoreEvalInt "Core-0 guarded self recursion" 1 =<< evalHaskell2010Binding "main" haskell2010GuardedSelfRecursionSource
    , expectCoreEvalInt "Core-0 local factorial recursion" 120 =<< evalHaskell2010Binding "main" haskell2010LocalFactorialSource
    , expectCoreEvalInt "Core-0 top-level fibonacci recursion" 21 =<< evalHaskell2010Binding "main" haskell2010FibonacciSource
    , expectCoreEvalInt "Core-0 mutual recursion" 1 =<< evalHaskell2010Binding "main" haskell2010MutualRecursionSource
    , expectCoreEvalInt "Core-0 recursive list function" 10 =<< evalHaskell2010Binding "main" haskell2010RecursiveListSource
    ]

testHaskell2010Core0EvalTypeClassDictionaries :: Either String ()
testHaskell2010Core0EvalTypeClassDictionaries =
  expectCoreEvalInt
    "Core-0 type class dictionary evaluation"
    1
    =<< evalHaskell2010Binding "main" haskell2010TypeClassDictionarySource

testHaskell2010Core0EvalPreludeClassDictionaries :: Either String ()
testHaskell2010Core0EvalPreludeClassDictionaries =
  expectCoreEvalInt
    "Core-0 Prelude class dictionary evaluation"
    6
    =<< evalHaskell2010Binding "main" haskell2010PreludeClassDictionarySource

testHaskell2010Core0EvalCharRuntime :: Either String ()
testHaskell2010Core0EvalCharRuntime =
  expectCoreEvalInt
    "Core-0 Char runtime evaluation"
    1
    =<< evalHaskell2010Binding "main" haskell2010CharRuntimeSource

testHaskell2010Core0EvalStringCharList :: Either String ()
testHaskell2010Core0EvalStringCharList =
  expectCoreEvalInt
    "Core-0 String Char-list evaluation"
    5
    =<< evalHaskell2010Binding "main" haskell2010StringCharListSource

testHaskell2010Core0EvalNumericDefaulting :: Either String ()
testHaskell2010Core0EvalNumericDefaulting =
  expectCoreEvalIO
    "Core-0 numeric defaulting evaluation"
    "7\n47\n"
    =<< evalHaskell2010Binding "main" haskell2010NumericDefaultingSource

testHaskell2010Core0EvalMultiModuleImports :: Either String ()
testHaskell2010Core0EvalMultiModuleImports =
  expectCoreEvalInt
    "Core-0 multi-module import evaluation"
    24
    =<< evalHaskell2010CoreModuleBinding "main"
    =<< typecheckHaskell2010Modules haskell2010MultiModuleSources

testHaskell2010Core0EvalIOPrinting :: Either String ()
testHaskell2010Core0EvalIOPrinting =
  expectCoreEvalIO
    "Core-0 IO printing evaluation"
    "ok\nanswer\n42\nTrue\n"
    =<< evalHaskell2010Binding "main" haskell2010IOPrintingSource

testHaskell2010Core0EvalGuardsAndAsPatterns :: Either String ()
testHaskell2010Core0EvalGuardsAndAsPatterns =
  expectCoreEvalInt
    "Core-0 guarded RHS/as-pattern evaluation"
    15
    =<< evalHaskell2010Binding "main" haskell2010GuardAsPatternSource

testHaskell2010Core0EvalSections :: Either String ()
testHaskell2010Core0EvalSections =
  expectCoreEvalInt
    "Core-0 operator section evaluation"
    6
    =<< evalHaskell2010Binding "main" haskell2010SectionsSource

testHaskell2010Core0EvalLazyLet :: Either String ()
testHaskell2010Core0EvalLazyLet =
  expectCoreEvalInt
    "Core-0 lazy let evaluation"
    5
    =<< evalHaskell2010Binding
      "main"
      "module Eval where\n\
      \main = let\n\
      \  x = 1 / 0\n\
      \in 5\n"

testHaskell2010Core0EvalLazyArgument :: Either String ()
testHaskell2010Core0EvalLazyArgument =
  expectCoreEvalInt
    "Core-0 lazy argument evaluation"
    1
    =<< evalHaskell2010Binding
      "main"
      "module Eval where\n\
      \const :: a -> b -> a\n\
      \const x y = x\n\
      \main = const 1 (1 / 0)\n"

testHaskell2010Core0EvalDivisionByZero :: Either String ()
testHaskell2010Core0EvalDivisionByZero =
  case
    evalHaskell2010BindingRaw
      "main"
      "module Eval where\n\
      \main = 1 / 0\n"
    of
      Left H2010CoreEval.CoreEvalDivisionByZero -> Right ()
      Left err -> Left ("expected Core-0 division by zero, got: " <> show err)
      Right value -> Left ("division by zero evaluated unexpectedly: " <> show value)

testHaskell2010Core0EvalGuardFallthrough :: Either String ()
testHaskell2010Core0EvalGuardFallthrough =
  case evalHaskell2010BindingRaw "main" haskell2010GuardFallthroughSource of
    Left H2010CoreEval.CoreEvalNoMatchingAlternative {} -> Right ()
    Left err -> Left ("expected Core-0 guard fallthrough, got: " <> show err)
    Right value -> Left ("guard fallthrough evaluated unexpectedly: " <> show value)

testHaskell2010STGValidatesLazyBindings :: Either String ()
testHaskell2010STGValidatesLazyBindings =
  expectEqual
    "lazy STG program validates"
    (Right ())
    (H2010STGValidate.validateProgram stgLazyFunctionArgumentProgram)

testHaskell2010STGLazyLet :: Either String ()
testHaskell2010STGLazyLet =
  expectSTGInt
    "STG lazy let evaluation"
    5
    =<< evalSTGBinding
      "main"
      ( stgMainProgram
          ( H2010STG.STGLet
              (stgThunkBinding stgUnusedBadBinder H2010STG.Updatable stgDivZeroExpr)
              (stgIntExpr 5)
              H2010Core.intTy
          )
      )

testHaskell2010STGLazyFunctionArgument :: Either String ()
testHaskell2010STGLazyFunctionArgument =
  expectSTGInt
    "STG lazy function argument evaluation"
    1
    =<< evalSTGBinding "main" stgLazyFunctionArgumentProgram

testHaskell2010STGCaseForcesScrutinee :: Either String ()
testHaskell2010STGCaseForcesScrutinee =
  case
    evalSTGBindingRaw
      "main"
      ( stgMainProgram
          ( H2010STG.STGCase
              stgDivZeroExpr
              (stgBinder "$case" 5130 H2010Core.intTy)
              [H2010STG.STGAlt H2010Core.DefaultAlt [] (stgIntExpr 0)]
              H2010Core.intTy
          )
      )
    of
      Left H2010STGEval.STGEvalDivisionByZero -> Right ()
      Left err -> Left ("expected STG division by zero, got: " <> show err)
      Right value -> Left ("STG case scrutinee evaluated unexpectedly: " <> show value)

testHaskell2010STGConstructorCase :: Either String ()
testHaskell2010STGConstructorCase =
  expectSTGInt
    "STG constructor case dispatch"
    1
    =<< evalSTGBinding
      "main"
      ( stgMainProgram
          ( H2010STG.STGCase
              (H2010STG.STGAtom (H2010STG.STGCon H2010Core.trueDataConName H2010Core.boolTy))
              (stgBinder "$case" 5140 H2010Core.boolTy)
              [ H2010STG.STGAlt (H2010Core.ConstructorAlt H2010Core.trueDataConName) [] (stgIntExpr 1)
              , H2010STG.STGAlt (H2010Core.ConstructorAlt H2010Core.falseDataConName) [] (stgIntExpr 0)
              ]
              H2010Core.intTy
          )
      )

testHaskell2010STGUpdatableThunkSharing :: Either String ()
testHaskell2010STGUpdatableThunkSharing = do
  let xBinder = stgBinder "x" 5150 H2010Core.intTy
      program = stgSharingProgram H2010STG.Updatable xBinder
  (value, stats) <- evalSTGBindingWithStats "main" program
  expectSTGInt "STG updatable thunk result" 42 value
  expectEqual
    "STG updatable thunk force count"
    (Just 1)
    (Map.lookup (H2010STG.stgBinderName xBinder) (H2010STGEval.stgThunkEvaluations stats))

testHaskell2010STGSingleEntryThunk :: Either String ()
testHaskell2010STGSingleEntryThunk = do
  let xBinder = stgBinder "x" 5160 H2010Core.intTy
      program = stgSharingProgram H2010STG.SingleEntry xBinder
  (value, stats) <- evalSTGBindingWithStats "main" program
  expectSTGInt "STG single-entry thunk result" 42 value
  expectEqual
    "STG single-entry thunk force count"
    (Just 2)
    (Map.lookup (H2010STG.stgBinderName xBinder) (H2010STGEval.stgThunkEvaluations stats))

testHaskell2010STGBlackHole :: Either String ()
testHaskell2010STGBlackHole =
  case evalSTGBindingRaw "main" stgBlackHoleProgram of
    Left (H2010STGEval.STGEvalBlackHole (Just name))
      | name == H2010STG.stgBinderName stgRecursiveBinder -> Right ()
    Left err -> Left ("expected STG black-hole error, got: " <> show err)
    Right value -> Left ("recursive STG thunk evaluated unexpectedly: " <> show value)

testHaskell2010STGRejectsUnboundVariable :: Either String ()
testHaskell2010STGRejectsUnboundVariable =
  case
    H2010STGValidate.validateExpr
      (H2010STG.STGAtom (H2010STG.STGVar (coreTerm "missing" 5190) H2010Core.intTy))
    of
      Left errors
        | any isUnbound errors -> Right ()
      Left errors -> Left ("expected unbound STG variable, got: " <> show errors)
      Right () -> Left "unbound STG variable validated unexpectedly"
 where
  isUnbound = \case
    H2010STGValidate.STGUnboundVariable {} -> True
    _ -> False

testHaskell2010CoreToSTGArithmetic :: Either String ()
testHaskell2010CoreToSTGArithmetic =
  checkCoreToSTGInt
    "Core-to-STG arithmetic"
    9
    "module Lower where\n\
    \main = (1 + 2) * 3\n"

testHaskell2010CoreToSTGPolymorphicIdentity :: Either String ()
testHaskell2010CoreToSTGPolymorphicIdentity =
  checkCoreToSTGInt
    "Core-to-STG polymorphic identity"
    42
    "module Lower where\n\
    \id :: a -> a\n\
    \id x = x\n\
    \main = id 42\n"

testHaskell2010CoreToSTGLazyLet :: Either String ()
testHaskell2010CoreToSTGLazyLet =
  checkCoreToSTGInt
    "Core-to-STG lazy let"
    5
    "module Lower where\n\
    \main = let\n\
    \  x = 1 / 0\n\
    \in 5\n"

testHaskell2010CoreToSTGLazyArgument :: Either String ()
testHaskell2010CoreToSTGLazyArgument =
  checkCoreToSTGInt
    "Core-to-STG lazy function argument"
    1
    "module Lower where\n\
    \const :: a -> b -> a\n\
    \const x y = x\n\
    \main = const 1 (1 / 0)\n"

testHaskell2010CoreToSTGBoolCase :: Either String ()
testHaskell2010CoreToSTGBoolCase =
  checkCoreToSTGInt
    "Core-to-STG Bool case"
    7
    "module Lower where\n\
    \main = case False of\n\
    \  True -> 0\n\
    \  False -> 7\n"

testHaskell2010CoreToSTGADTCase :: Either String ()
testHaskell2010CoreToSTGADTCase =
  checkCoreToSTGInt
    "Core-to-STG user ADT case"
    7
    haskell2010ADTBoxSource

testHaskell2010CoreToSTGPolymorphicADT :: Either String ()
testHaskell2010CoreToSTGPolymorphicADT =
  checkCoreToSTGInt
    "Core-to-STG polymorphic ADT case"
    4
    haskell2010PolymorphicADTSource

testHaskell2010CoreToSTGNestedADTPatterns :: Either String ()
testHaskell2010CoreToSTGNestedADTPatterns =
  checkCoreToSTGInt
    "Core-to-STG nested ADT patterns"
    3
    haskell2010NestedADTSource

testHaskell2010CoreToSTGPreludeData :: Either String ()
testHaskell2010CoreToSTGPreludeData =
  checkCoreToSTGInt
    "Core-to-STG Prelude list/tuple data"
    321
    haskell2010ListPreludeSource

testHaskell2010CoreToSTGRecursion :: Either String ()
testHaskell2010CoreToSTGRecursion = do
  checkCoreToSTGInt "Core-to-STG guarded self recursion" 1 haskell2010GuardedSelfRecursionSource
  checkCoreToSTGInt "Core-to-STG local factorial recursion" 120 haskell2010LocalFactorialSource
  checkCoreToSTGInt "Core-to-STG recursive list function" 10 haskell2010RecursiveListSource

testHaskell2010CoreToSTGTypeClassDictionaries :: Either String ()
testHaskell2010CoreToSTGTypeClassDictionaries =
  checkCoreToSTGInt "Core-to-STG type class dictionaries" 1 haskell2010TypeClassDictionarySource

testHaskell2010CoreToSTGPreludeClassDictionaries :: Either String ()
testHaskell2010CoreToSTGPreludeClassDictionaries =
  checkCoreToSTGInt "Core-to-STG Prelude class dictionaries" 6 haskell2010PreludeClassDictionarySource

testHaskell2010CoreToSTGCharRuntime :: Either String ()
testHaskell2010CoreToSTGCharRuntime =
  checkCoreToSTGInt "Core-to-STG Char runtime" 1 haskell2010CharRuntimeSource

testHaskell2010CoreToSTGStringCharList :: Either String ()
testHaskell2010CoreToSTGStringCharList =
  checkCoreToSTGInt "Core-to-STG String Char-list" 5 haskell2010StringCharListSource

testHaskell2010CoreToSTGNumericDefaulting :: Either String ()
testHaskell2010CoreToSTGNumericDefaulting =
  checkCoreToSTGIO "Core-to-STG numeric defaulting" "7\n47\n" haskell2010NumericDefaultingSource

testHaskell2010CoreToSTGMultiModuleImports :: Either String ()
testHaskell2010CoreToSTGMultiModuleImports = do
  coreModule <- typecheckHaskell2010Modules haskell2010MultiModuleSources
  stgProgram <- mapLeft (Text.unpack . H2010STGLower.renderSTGLowerError) (H2010STGLower.lowerCoreModule coreModule)
  value <- evalSTGBinding "main" stgProgram
  expectSTGInt "Core-to-STG multi-module imports" 24 value

testHaskell2010CoreToSTGIOPrinting :: Either String ()
testHaskell2010CoreToSTGIOPrinting =
  checkCoreToSTGIO "Core-to-STG IO printing" "ok\nanswer\n42\nTrue\n" haskell2010IOPrintingSource

testHaskell2010CoreToSTGGuardsAndAsPatterns :: Either String ()
testHaskell2010CoreToSTGGuardsAndAsPatterns =
  checkCoreToSTGInt "Core-to-STG guards and as-patterns" 15 haskell2010GuardAsPatternSource

testHaskell2010CoreToSTGSections :: Either String ()
testHaskell2010CoreToSTGSections =
  checkCoreToSTGInt "Core-to-STG operator sections" 6 haskell2010SectionsSource

testHaskell2010CoreToSTGDivisionByZero :: Either String ()
testHaskell2010CoreToSTGDivisionByZero =
  case
    lowerAndEvalHaskell2010BindingRaw
      "main"
      "module Lower where\n\
      \main = 1 / 0\n"
    of
      Left (Right H2010STGEval.STGEvalDivisionByZero) -> Right ()
      Left err -> Left ("expected lowered STG division by zero, got: " <> show err)
      Right value -> Left ("lowered division by zero evaluated unexpectedly: " <> show value)

testHaskell2010CoreToSTGGuardFallthrough :: Either String ()
testHaskell2010CoreToSTGGuardFallthrough =
  case lowerAndEvalHaskell2010BindingRaw "main" haskell2010GuardFallthroughSource of
    Left (Right H2010STGEval.STGEvalNoMatchingAlternative {}) -> Right ()
    Left err -> Left ("expected lowered STG guard fallthrough, got: " <> show err)
    Right value -> Left ("lowered guard fallthrough evaluated unexpectedly: " <> show value)

testHaskell2010CoreToSTGPartialApplication :: Either String ()
testHaskell2010CoreToSTGPartialApplication =
  checkCoreToSTGInt
    "Core-to-STG curried partial application"
    1
    "module Lower where\n\
    \const :: a -> b -> a\n\
    \const x y = x\n\
    \one = const 1\n\
    \main = one (1 / 0)\n"

testHaskell2010CoreToSTGRejectsInvalidCore :: Either String ()
testHaskell2010CoreToSTGRejectsInvalidCore =
  case H2010STGLower.lowerCoreExpr (H2010Core.CVar (coreTerm "missing" 5200) H2010Core.intTy) of
    Left (H2010STGLower.STGLowerInvalidCore errors)
      | any isUnbound errors -> Right ()
    Left err -> Left ("expected invalid Core before STG lowering, got: " <> show err)
    Right stgExpr -> Left ("invalid Core lowered unexpectedly: " <> show stgExpr)
 where
  isUnbound = \case
    H2010CoreValidate.CoreUnboundVariable {} -> True
    _ -> False

testHaskell2010NativeLLVMShape :: Either String ()
testHaskell2010NativeLLVMShape = do
  llvmText <- compileHaskell2010NativeText haskell2010PartialApplicationSource
  assertBool "native LLVM defines process-lifetime allocator" ("define ptr @hegglog_hs_alloc_process_lifetime(i64 %size)" `Text.isInfixOf` llvmText)
  assertBool "native LLVM object allocation uses process-lifetime allocator" ("call ptr @hegglog_hs_alloc_process_lifetime(i64 48)" `Text.isInfixOf` llvmText)
  expectEqual "native LLVM direct malloc calls stay inside allocator helper" 1 (countTextOccurrences "call ptr @malloc" llvmText)
  assertBool "native LLVM defines lazy force runtime" ("define ptr @hegglog_hs_force" `Text.isInfixOf` llvmText)
  assertBool "native LLVM allocates thunks" ("@hegglog_hs_make_thunk" `Text.isInfixOf` llvmText)
  assertBool "native LLVM boxes Int results" ("@hegglog_hs_make_int" `Text.isInfixOf` llvmText)
  assertBool "native LLVM enters closures indirectly" ("call ptr %fun_code" `Text.isInfixOf` llvmText)

testHaskell2010NativeNewtypeErasure :: Either String ()
testHaskell2010NativeNewtypeErasure = do
  llvmText <- compileHaskell2010NativeText haskell2010NewtypeRepresentationSource
  baselineText <- compileHaskell2010NativeText "module Main where\nmain = 42\n"
  expectEqual
    "native LLVM newtype data allocations match unwrapped Int baseline"
    (countTextOccurrences "call ptr @hegglog_hs_make_data" baselineText)
    (countTextOccurrences "call ptr @hegglog_hs_make_data" llvmText)

testHaskell2010NativeCharRuntime :: Either String ()
testHaskell2010NativeCharRuntime = do
  charRuntimeText <- compileHaskell2010NativeText haskell2010CharRuntimeSource
  assertBool "native LLVM boxes Char literals" ("@hegglog_hs_make_char" `Text.isInfixOf` charRuntimeText)
  assertBool "native LLVM unboxes Char values" ("@hegglog_hs_expect_char" `Text.isInfixOf` charRuntimeText)
  assertBool "native LLVM compares unboxed Char values" ("icmp eq i32" `Text.isInfixOf` charRuntimeText)
  charMainText <- compileHaskell2010NativeText haskell2010CharMainSource
  assertBool "native LLVM has a Char main format" ("@haskell2010_fmt_char" `Text.isInfixOf` charMainText)

testHaskell2010NativeStringCharList :: Either String ()
testHaskell2010NativeStringCharList = do
  llvmText <- compileHaskell2010NativeText haskell2010StringCharListSource
  assertBool "native LLVM boxes String literal chars" ("@hegglog_hs_make_char" `Text.isInfixOf` llvmText)
  assertBool "native LLVM converts show buffers to Char lists" ("@hegglog_hs_make_char_list_from_cstring" `Text.isInfixOf` llvmText)
  assertBool "native LLVM does not emit per-literal string globals" (not ("@haskell2010_str_" `Text.isInfixOf` llvmText))
  assertBool "native LLVM does not call special string payload allocator" (not ("call ptr @hegglog_hs_make_string" `Text.isInfixOf` llvmText))

testHaskell2010NativeLLVMExecution :: IO (Either String ())
testHaskell2010NativeLLVMExecution = do
  tools <- LLVMTools.findLLVMTools
  firstFailureIO (check tools) haskell2010NativeSuccessExamples
 where
  check tools (label, source, expectedStdout) =
    case compileHaskell2010Native source of
      Left err ->
        pure (Left err)
      Right result -> do
        let llvmText = H2010Native.haskell2010LLVMText result
        assemblyResult <- LLVMTools.validateLLVMText tools llvmText
        runResult <- LLVMTools.runLLVMText tools llvmText
        pure $
          checkLLVMAssemblyResult ("<haskell2010-native-" <> Text.unpack label <> ">") assemblyResult
            *> case runResult of
              LLVMTools.LLVMRunSkipped {} ->
                Right ()
              LLVMTools.LLVMRunFailed stdoutText stderrText ->
                Left
                  ( "Haskell 2010 LLVM execution failed for "
                      <> Text.unpack label
                      <> "\nstdout:\n"
                      <> stdoutText
                      <> "\nstderr:\n"
                      <> stderrText
                  )
              LLVMTools.LLVMRunSucceeded stdoutText ->
                expectEqual ("Haskell 2010 native LLVM stdout for " <> Text.unpack label) expectedStdout stdoutText

testHaskell2010NativeExecutableExecution :: IO (Either String ())
testHaskell2010NativeExecutableExecution = do
  tools <- LLVMTools.findLLVMTools
  case LLVMTools.llvmClang tools of
    Nothing ->
      pure (Right ())
    Just {} -> do
      createDirectoryIfMissing True ".context/native-tests"
      firstFailureIO (check tools) haskell2010NativeExecutableExamples
 where
  check tools (label, source, expectedStdout) =
    case compileHaskell2010Native source of
      Left err ->
        pure (Left err)
      Right result -> do
        let outputPath = ".context/native-tests/haskell2010-" <> Text.unpack label
        buildResult <- LLVMTools.buildNativeExecutable tools (H2010Native.haskell2010LLVMText result) outputPath
        runBuiltNative outputPath buildResult $ \runResult ->
          case runResult of
            LLVMTools.NativeRunSucceeded stdoutText ->
              expectEqual ("Haskell 2010 native stdout for " <> Text.unpack label) expectedStdout stdoutText
            LLVMTools.NativeRunFailed code stdoutText stderrText ->
              Left
                ( "Haskell 2010 native execution failed for "
                    <> outputPath
                    <> " with "
                    <> show code
                    <> "\nstdout:\n"
                    <> stdoutText
                    <> "\nstderr:\n"
                    <> stderrText
                )
            LLVMTools.NativeRunIOError message ->
              Left ("Haskell 2010 native execution I/O error for " <> outputPath <> ": " <> message)

testHaskell2010NativeRuntimeError :: IO (Either String ())
testHaskell2010NativeRuntimeError = do
  tools <- LLVMTools.findLLVMTools
  case compileHaskell2010Native haskell2010DivisionByZeroSource of
    Left err ->
      pure (Left err)
    Right result -> do
      assemblyResult <- LLVMTools.validateLLVMText tools (H2010Native.haskell2010LLVMText result)
      runResult <- LLVMTools.runLLVMText tools (H2010Native.haskell2010LLVMText result)
      pure $
        checkLLVMAssemblyResult "<haskell2010-native-division-by-zero>" assemblyResult
          *> case runResult of
            LLVMTools.LLVMRunSkipped {} ->
              Right ()
            LLVMTools.LLVMRunFailed {} ->
              Right ()
            LLVMTools.LLVMRunSucceeded stdoutText ->
              Left ("expected forced Haskell 2010 division by zero to fail, got stdout:\n" <> stdoutText)

testHaskell2010CoreEgglogFoldsArithmetic :: Either String ()
testHaskell2010CoreEgglogFoldsArithmetic = do
  result <- optimizeHaskell2010CoreModule haskell2010PrimitiveArithmeticCoreModule
  assertBool
    "arithmetic Core optimizer should lower expression cost"
    (H2010CoreEgglog.coreEgglogOptimizedCost result < H2010CoreEgglog.coreEgglogOriginalCost result)
  assertBool
    "arithmetic Core optimizer should record applied rules"
    (not (null (H2010CoreEgglog.coreEgglogAppliedRules result)))
  expectCoreEvalInt
    "optimized arithmetic Core oracle"
    9
    =<< evalHaskell2010CoreModuleBinding "main" (H2010CoreEgglog.coreEgglogOptimizedModule result)
  stgProgram <- lowerOptimizedCoreToSTG result
  expectSTGInt
    "optimized arithmetic STG oracle"
    9
    =<< evalSTGBinding "main" stgProgram

testHaskell2010CoreEgglogFoldsKnownBoolCase :: Either String ()
testHaskell2010CoreEgglogFoldsKnownBoolCase = do
  result <- optimizeHaskell2010CoreModule haskell2010KnownBoolCaseCoreModule
  assertBool
    "known Bool case should lower expression cost"
    (H2010CoreEgglog.coreEgglogOptimizedCost result < H2010CoreEgglog.coreEgglogOriginalCost result)
  assertBool
    "known Bool case should explain the selected rewrite"
    (any ("iif-known-false" `Text.isInfixOf`) (H2010CoreEgglog.coreEgglogAppliedRules result))
  expectCoreEvalInt
    "optimized Bool case Core oracle"
    7
    =<< evalHaskell2010CoreModuleBinding "main" (H2010CoreEgglog.coreEgglogOptimizedModule result)
  stgProgram <- lowerOptimizedCoreToSTG result
  expectSTGInt
    "optimized Bool case STG oracle"
    7
    =<< evalSTGBinding "main" stgProgram

testHaskell2010CoreEgglogFoldsKnownConstructorCase :: Either String ()
testHaskell2010CoreEgglogFoldsKnownConstructorCase = do
  result <- optimizeHaskell2010Core haskell2010KnownConstructorCaseSource
  assertBool
    "known constructor case should lower expression cost"
    (H2010CoreEgglog.coreEgglogOptimizedCost result < H2010CoreEgglog.coreEgglogOriginalCost result)
  assertBool
    "known constructor case should explain the selected rewrite"
    (any ("core-case-known-constructor" `Text.isInfixOf`) (H2010CoreEgglog.coreEgglogAppliedRules result))
  expectCoreEvalInt
    "optimized known constructor Core oracle"
    7
    =<< evalHaskell2010CoreModuleBinding "main" (H2010CoreEgglog.coreEgglogOptimizedModule result)
  stgProgram <- lowerOptimizedCoreToSTG result
  expectSTGInt
    "optimized known constructor STG oracle"
    7
    =<< evalSTGBinding "main" stgProgram

testHaskell2010CoreEgglogPreservesKnownConstructorLaziness :: Either String ()
testHaskell2010CoreEgglogPreservesKnownConstructorLaziness = do
  unusedFieldResult <- optimizeHaskell2010Core haskell2010KnownConstructorLazyFieldSource
  assertBool
    "unused lazy constructor field should still use known-constructor rewrite"
    (any ("core-case-known-constructor" `Text.isInfixOf`) (H2010CoreEgglog.coreEgglogAppliedRules unusedFieldResult))
  expectCoreEvalInt
    "optimized unused lazy constructor field Core oracle"
    5
    =<< evalHaskell2010CoreModuleBinding "main" (H2010CoreEgglog.coreEgglogOptimizedModule unusedFieldResult)
  unusedFieldSTG <- lowerOptimizedCoreToSTG unusedFieldResult
  expectSTGInt
    "optimized unused lazy constructor field STG oracle"
    5
    =<< evalSTGBinding "main" unusedFieldSTG

  forcedFieldResult <- optimizeHaskell2010Core haskell2010KnownConstructorForcedFieldSource
  case evalHaskell2010CoreModuleBindingRaw "main" (H2010CoreEgglog.coreEgglogOptimizedModule forcedFieldResult) of
    Left H2010CoreEval.CoreEvalDivisionByZero -> Right ()
    Left err ->
      Left ("expected optimized known-constructor projection to preserve forced division by zero, got: " <> show err)
    Right value ->
      Left ("optimized known-constructor projection erased forced field bottom and returned: " <> show value)

testHaskell2010CoreEgglogPreservesLazyLet :: Either String ()
testHaskell2010CoreEgglogPreservesLazyLet = do
  result <- optimizeHaskell2010Core haskell2010LazyLetSource
  expectCoreEvalInt
    "optimized lazy-let Core oracle"
    5
    =<< evalHaskell2010CoreModuleBinding "main" (H2010CoreEgglog.coreEgglogOptimizedModule result)
  stgProgram <- lowerOptimizedCoreToSTG result
  expectSTGInt
    "optimized lazy-let STG oracle"
    5
    =<< evalSTGBinding "main" stgProgram

testHaskell2010CoreEgglogPreservesStrictBottom :: Either String ()
testHaskell2010CoreEgglogPreservesStrictBottom = do
  result <-
    optimizeHaskell2010Core
      "module Optimize where\n\
      \f x = x * 0\n\
      \main = f (1 / 0)\n"
  case evalHaskell2010CoreModuleBindingRaw "main" (H2010CoreEgglog.coreEgglogOptimizedModule result) of
    Left H2010CoreEval.CoreEvalDivisionByZero -> Right ()
    Left err ->
      Left ("expected optimized Core to preserve forced division by zero, got: " <> show err)
    Right value ->
      Left ("optimized Core erased strict bottom dependency and returned: " <> show value)

data ExpectedNativeOutcome
  = ExpectedNativeStdout String
  | ExpectedNativeRuntimeError
  deriving stock (Show, Eq)

data ObservedNativeOutcome
  = ObservedNativeStdout String
  | ObservedNativeRuntimeError
  deriving stock (Show, Eq)

testHaskell2010CoreEgglogNativeAgreement :: IO (Either String ())
testHaskell2010CoreEgglogNativeAgreement = do
  tools <- LLVMTools.findLLVMTools
  firstFailureIO (check tools) haskell2010CoreEgglogNativeAgreementCases
 where
  check tools (label, source, expected) =
    case (compileHaskell2010Native source, compileHaskell2010NativeWithOptions noEgglogNativeOptions source) of
      (Left err, _) ->
        pure (Left ("optimized native compile failed for " <> Text.unpack label <> ": " <> err))
      (_, Left err) ->
        pure (Left ("unoptimized native compile failed for " <> Text.unpack label <> ": " <> err))
      (Right optimized, Right unoptimized) -> do
        optimizedOutcome <-
          runExpectedHaskell2010LLVM
            ("<haskell2010-core-egglog-optimized-" <> Text.unpack label <> ">")
            expected
            tools
            (H2010Native.haskell2010LLVMText optimized)
        unoptimizedOutcome <-
          runExpectedHaskell2010LLVM
            ("<haskell2010-core-egglog-unoptimized-" <> Text.unpack label <> ">")
            expected
            tools
            (H2010Native.haskell2010LLVMText unoptimized)
        pure $ case (optimizedOutcome, unoptimizedOutcome) of
          (Right (Just opt), Right (Just noOpt)) ->
            expectEqual ("optimized/unoptimized native outcome for " <> Text.unpack label) noOpt opt
          (Right Nothing, _) ->
            Right ()
          (_, Right Nothing) ->
            Right ()
          (Left err, _) ->
            Left err
          (_, Left err) ->
            Left err

haskell2010CoreEgglogNativeAgreementCases :: [(Text, Text, ExpectedNativeOutcome)]
haskell2010CoreEgglogNativeAgreementCases =
  [ ("arithmetic", haskell2010ArithmeticSource, ExpectedNativeStdout "9\n")
  , ("bool-case", haskell2010BoolCaseSource, ExpectedNativeStdout "7\n")
  , ("known-constructor", haskell2010KnownConstructorCaseSource, ExpectedNativeStdout "7\n")
  , ("known-constructor-lazy-field", haskell2010KnownConstructorLazyFieldSource, ExpectedNativeStdout "5\n")
  , ("lazy-let", haskell2010LazyLetSource, ExpectedNativeStdout "5\n")
  , ("known-constructor-forced-field", haskell2010KnownConstructorForcedFieldSource, ExpectedNativeRuntimeError)
  , ("division-by-zero", haskell2010DivisionByZeroSource, ExpectedNativeRuntimeError)
  ]

noEgglogNativeOptions :: H2010Native.Haskell2010NativeOptions
noEgglogNativeOptions =
  H2010Native.defaultHaskell2010NativeOptions {H2010Native.haskell2010UseEgglog = False}

runExpectedHaskell2010LLVM ::
  String ->
  ExpectedNativeOutcome ->
  LLVMTools.LLVMTools ->
  Text ->
  IO (Either String (Maybe ObservedNativeOutcome))
runExpectedHaskell2010LLVM label expected tools llvmText = do
  assemblyResult <- LLVMTools.validateLLVMText tools llvmText
  runResult <- LLVMTools.runLLVMText tools llvmText
  pure $
    checkLLVMAssemblyResult label assemblyResult
      *> observeRunResult expected label runResult

observeRunResult ::
  ExpectedNativeOutcome ->
  String ->
  LLVMTools.LLVMRunResult ->
  Either String (Maybe ObservedNativeOutcome)
observeRunResult expected label = \case
  LLVMTools.LLVMRunSkipped {} ->
    Right Nothing
  LLVMTools.LLVMRunSucceeded stdoutText ->
    case expected of
      ExpectedNativeStdout expectedStdout -> do
        expectEqual (label <> " stdout") expectedStdout stdoutText
        Right (Just (ObservedNativeStdout stdoutText))
      ExpectedNativeRuntimeError ->
        Left (label <> " should have failed at runtime, got stdout:\n" <> stdoutText)
  LLVMTools.LLVMRunFailed stdoutText stderrText ->
    case expected of
      ExpectedNativeRuntimeError ->
        Right (Just ObservedNativeRuntimeError)
      ExpectedNativeStdout {} ->
        Left
          ( label
              <> " failed unexpectedly\nstdout:\n"
              <> stdoutText
              <> "\nstderr:\n"
              <> stderrText
          )

testHigherOrderType :: Either String ()
testHigherOrderType = do
  parsed <- parseExpr "\\f : (Int -> Int) -> f 1"
  actualType <- mapLeft (showText . renderTypeError) (infer parsed)
  expectEqual "higher-order lambda type" (TFun (TFun TInt TInt) TInt) actualType

testOptionalLambdaParameterInference :: Either String ()
testOptionalLambdaParameterInference = do
  report <- mapLeft (showText . renderCompileError) (compileReport "<test>" "(\\x -> x + 1) 41")
  expectEqual "optional lambda source type" TInt (reportType report)
  expectEqual "optional lambda value" (sourceInt 42) (reportValue report)
  expectEqual
    "elaborated lambda parameter type"
    (EApp (ELam (mkName "x") TInt (EBin Add (EVar (mkName "x")) (EInt 1))) (EInt 41))
    (programMain (reportParsed report))

testOptionalLambdaEqualityContext :: Either String ()
testOptionalLambdaEqualityContext = do
  report <- mapLeft (showText . renderCompileError) (compileReport "<test>" "(\\x -> x == x) true")
  expectEqual "optional equality source type" TBool (reportType report)
  expectEqual "optional equality value" (VBool True) (reportValue report)

testOptionalLambdaLetUse :: Either String ()
testOptionalLambdaLetUse = do
  report <- mapLeft (showText . renderCompileError) (compileReport "<test>" "let id = \\x -> x in id 41")
  expectEqual "let-constrained optional lambda source type" TInt (reportType report)
  expectEqual "let-constrained optional lambda value" (sourceInt 41) (reportValue report)

testOptionalLambdaLetMonomorphic :: Either String ()
testOptionalLambdaLetMonomorphic =
  case compileReport "<test>" "let id = \\x -> x in let a = id 1 in id true" of
    Left (CompileTypeError (LocatedTypeError _ (TypeMismatch TInt TBool))) -> Right ()
    other -> Left ("expected monomorphic optional lambda let mismatch, got " <> show other)

testOptionalLambdaAmbiguity :: Either String ()
testOptionalLambdaAmbiguity =
  case compileReport "<test>" "\\x -> x" of
    Left err@(CompileTypeError (LocatedTypeError sourceRange (AmbiguousLambdaParameter name)))
      | name == mkName "x" ->
          expectEqual "ambiguity diagnostic file" "<test>" (spanFile sourceRange)
            *> expectEqual "ambiguity diagnostic line" 1 (spanStartLine sourceRange)
            *> expectEqual "ambiguity diagnostic column" 1 (spanStartColumn sourceRange)
            *> assertBool
              "ambiguity diagnostic includes parameter message"
              ("cannot infer a monomorphic type for lambda parameter: x" `Text.isInfixOf` renderCompileError err)
    other -> Left ("expected source-spanned lambda ambiguity, got " <> show other)

testPrincipalIdentityType :: Either String ()
testPrincipalIdentityType = do
  parsed <- parseExpr "\\x : Int -> x"
  actual <- mapLeft (showText . Principal.renderPrincipalTypeError) (Principal.principalType parsed)
  expectEqual
    "principal identity type"
    (Principal.TypeScheme [] (Principal.PFun Principal.PInt Principal.PInt))
    actual

testPrincipalHigherOrderType :: Either String ()
testPrincipalHigherOrderType = do
  parsed <- parseExpr "\\f : (Int -> Int) -> \\x : Int -> f (f x)"
  actual <- mapLeft (showText . Principal.renderPrincipalTypeError) (Principal.principalType parsed)
  expectEqual
    "principal higher-order type"
    ( Principal.TypeScheme
        []
        ( Principal.PFun
            (Principal.PFun Principal.PInt Principal.PInt)
            (Principal.PFun Principal.PInt Principal.PInt)
        )
    )
    actual

testPrincipalMonomorphicLet :: Either String ()
testPrincipalMonomorphicLet = do
  parsed <- parseExpr "let id = \\x : Int -> x in let a = id 1 in id true"
  case Principal.principalType parsed of
    Left (Principal.PrincipalTypeFailure (TypeMismatch TInt TBool)) -> Right ()
    other -> Left ("expected monomorphic let type mismatch, got " <> show other)

testTopLevelFunctionTypecheck :: Either String ()
testTopLevelFunctionTypecheck = do
  parsed <- parseSource topLevelSource
  actualType <- mapLeft (showText . renderTypeError) (inferProgram parsed)
  expectEqual "top-level program type" TInt actualType

testTopLevelDuplicateFunctionName :: Either String ()
testTopLevelDuplicateFunctionName = do
  parsed <- parseSource "def f(x : Int) : Int = x; def f(y : Int) : Int = y; f 1"
  case inferProgram parsed of
    Left (DuplicateTopLevelName name)
      | name == mkName "f" -> Right ()
    other -> Left ("expected duplicate top-level function name, got " <> show other)

testTopLevelDuplicateParameter :: Either String ()
testTopLevelDuplicateParameter = do
  parsed <- parseSource "def f(x : Int, x : Int) : Int = x; f 1 2"
  case inferProgram parsed of
    Left (DuplicateParameter name)
      | name == mkName "x" -> Right ()
    other -> Left ("expected duplicate top-level parameter, got " <> show other)

testTopLevelForwardCall :: Either String ()
testTopLevelForwardCall = do
  parsed <- parseSource "def f(x : Int) : Int = g x; def g(x : Int) : Int = x; f 1"
  case inferProgram parsed of
    Left (UnknownVariable name)
      | name == mkName "g" -> Right ()
    other -> Left ("expected forward call to be rejected, got " <> show other)

testTopLevelFunctionParameter :: Either String ()
testTopLevelFunctionParameter = do
  parsed <- parseSource "def apply(f : Int -> Int) : Int = 0; 0"
  case inferProgram parsed of
    Left (TopLevelFunctionTypeUnsupported name ty)
      | name == mkName "apply" && ty == TFun TInt TInt -> Right ()
    other -> Left ("expected top-level function-typed parameter rejection, got " <> show other)

testOutOfRangeIntLiteralTypeError :: Either String ()
testOutOfRangeIntLiteralTypeError = do
  let tooLarge = maxHIntInteger + 1
  parsed <- parseExpr (Text.pack (show tooLarge))
  case infer parsed of
    Left (IntLiteralOutOfRange value)
      | value == tooLarge -> Right ()
    other -> Left ("expected out-of-range Int literal type error, got " <> show other)

checkTypeError :: FilePath -> TypeError -> IO (Either String ())
checkTypeError path expectedTypeError = do
  source <- Text.IO.readFile path
  pure $ do
    parsed <- parseExprAt path source
    case infer parsed of
      Left actualTypeError ->
        expectEqual "type error" expectedTypeError actualTypeError
      Right actualType ->
        Left ("expected typechecking to fail, got " <> show actualType)

testParserDiagnosticIncludesLocation :: Either String ()
testParserDiagnosticIncludesLocation =
  case parseProgram "examples/bad.hg" "let" of
    Left parseError ->
      assertBool
        "parse diagnostic should include file, line, and column"
        ("examples/bad.hg:1:4:" `Text.isInfixOf` Text.pack (errorBundlePretty parseError))
    Right parsed ->
      Left ("expected parser to fail, got " <> show parsed)

testCompileFlagsOutputModes :: Either String ()
testCompileFlagsOutputModes = do
  expectEqual
    "emit LLVM to explicit file"
    ( Right
        ( CompileCLI.CompileCLIOptions
          { CompileCLI.cliOutputMode = CompileCLI.EmitLLVM (Just "out.ll")
          , CompileCLI.cliUseEgglog = True
          }
        )
    )
    (CompileCLI.parseCompileFlags ["--emit-llvm", "-o", "out.ll"])
  expectEqual
    "legacy run LLVM mode"
    ( Right
        ( CompileCLI.CompileCLIOptions
          { CompileCLI.cliOutputMode = CompileCLI.EmitAndRunLLVM Nothing
          , CompileCLI.cliUseEgglog = True
          }
        )
    )
    (CompileCLI.parseCompileFlags ["--run-llvm"])
  expectEqual
    "native executable output"
    ( Right
        ( CompileCLI.CompileCLIOptions
          { CompileCLI.cliOutputMode = CompileCLI.BuildExecutable "program"
          , CompileCLI.cliUseEgglog = True
          }
        )
    )
    (CompileCLI.parseCompileFlags ["-o", "program"])
  expectEqual
    "native executable run output"
    ( Right
        ( CompileCLI.CompileCLIOptions
          { CompileCLI.cliOutputMode = CompileCLI.BuildAndRunExecutable "program"
          , CompileCLI.cliUseEgglog = False
          }
        )
    )
    (CompileCLI.parseCompileFlags ["--output", "program", "--run", "--no-egglog"])

testCompileFlagsRejectInvalidRunModes :: Either String ()
testCompileFlagsRejectInvalidRunModes =
  assertLeftContains "native run needs output" "--run requires -o/--output" (CompileCLI.parseCompileFlags ["--run"])
    *> assertLeftContains "native run conflicts with emit LLVM" "--run builds and runs a native executable" (CompileCLI.parseCompileFlags ["--emit-llvm", "--run"])
    *> assertLeftContains "native and LLVM run conflict" "--run and --run-llvm cannot be combined" (CompileCLI.parseCompileFlags ["--run", "--run-llvm", "-o", "program"])
    *> assertLeftContains "duplicate output rejected" "provided more than once" (CompileCLI.parseCompileFlags ["-o", "a", "--output", "b"])
 where
  assertLeftContains label needle = \case
    Left message ->
      assertBool label (needle `Text.isInfixOf` message)
    Right value ->
      Left (label <> ": expected parse failure, got " <> show value)

testANFNestedArithmetic :: Either String ()
testANFNestedArithmetic = do
  parsed <- parseExpr "(1 + 2) * (3 + 4)"
  expectEqual
    "nested arithmetic ANF"
    ( ALet
        (mkName "_t0")
        (APrim Add (AInt 1) (AInt 2))
        ( ALet
            (mkName "_t1")
            (APrim Add (AInt 3) (AInt 4))
            (APrim Mul (AVar (mkName "_t0")) (AVar (mkName "_t1")))
        )
    )
    (toANF parsed)

testDeterministicFreshNames :: Either String ()
testDeterministicFreshNames = do
  parsed <- parseExpr "(1 + 2) * (3 + 4)"
  expectEqual
    "fresh name order"
    [mkName "_t0", mkName "_t1"]
    (letNames (toANF parsed))

testApplicationAtomization :: Either String ()
testApplicationAtomization = do
  parsed <- parseExpr "f (x + 1)"
  expectEqual
    "application atomization"
    ( ALet
        (mkName "_t0")
        (APrim Add (AVar (mkName "x")) (AInt 1))
        (AApp (AVar (mkName "f")) (AVar (mkName "_t0")))
    )
    (toANF parsed)

testTopLevelDirectCallANF :: Either String ()
testTopLevelDirectCallANF = do
  parsed <- parseSource topLevelSource
  expectEqual
    "top-level direct-call ANF"
    ( AProgram
        [ AFun
            (mkName "inc")
            [Param (mkName "x") TInt]
            TInt
            (APrim Add (AVar (mkName "x")) (AInt 1))
        , AFun
            (mkName "double")
            [Param (mkName "x") TInt]
            TInt
            (APrim Mul (AVar (mkName "x")) (AInt 2))
        ]
        ( ALet
            (mkName "_t0")
            (ACall (mkName "inc") [AInt 20])
            (ACall (mkName "double") [AVar (mkName "_t0")])
        )
    )
    (toANFProgram parsed)

testLambdaLiftANF :: Either String ()
testLambdaLiftANF = do
  result <- compileLLVMNoEgglog liftedIncSource
  expectEqual
    "lambda-lifted direct-call ANF"
    ( AProgram
        [ AFun
            (mkName "_lift_inc_0")
            [Param (mkName "x") TInt]
            TInt
            (APrim Add (AVar (mkName "x")) (AInt 1))
        ]
        (ACall (mkName "_lift_inc_0") [AInt 41])
    )
    (BC.llvmOriginalANF result)

testLambdaPreservation :: Either String ()
testLambdaPreservation = do
  parsed <- parseExpr "\\x : Int -> x + 1"
  expectEqual
    "lambda ANF"
    (ALam (mkName "x") TInt (APrim Add (AVar (mkName "x")) (AInt 1)))
    (toANF parsed)

testValidateLoweredExamples :: IO (Either String ())
testValidateLoweredExamples =
  firstFailure validateExample examplePaths

testValidatorUnboundVariable :: Either String ()
testValidatorUnboundVariable =
  expectEqual
    "unbound validation error"
    (Left (UnboundVariable (mkName "x")))
    (validateANF (AAtom (AVar (mkName "x"))))

testValidatorDuplicateGeneratedTemp :: Either String ()
testValidatorDuplicateGeneratedTemp =
  expectEqual
    "duplicate temp validation error"
    (Left (DuplicateGeneratedTemp (mkName "_t0")))
    ( validateANF
        ( ALet
            (mkName "_t0")
            (AAtom (AInt 1))
            (ALet (mkName "_t0") (AAtom (AInt 2)) (AAtom (AVar (mkName "_t0"))))
        )
    )

testValidatorDuplicateFunctionParameter :: Either String ()
testValidatorDuplicateFunctionParameter =
  expectEqual
    "duplicate ANF function parameter"
    (Left (DuplicateANFParameter xName))
    ( validateANFProgram
        ( AProgram
            [AFun (mkName "f") [Param xName TInt, Param xName TInt] TInt (AAtom (AVar xName))]
            (ACall (mkName "f") [AInt 1])
        )
    )

testConstantFacts :: Either String ()
testConstantFacts = do
  facts <- factsFor "let x = 5 in x"
  assertBool "expected IsConst x 5" (IsConst (mkName "x") (ConstInt 5) `elem` facts)

testNonZeroFacts :: Either String ()
testNonZeroFacts = do
  facts <- factsFor "let x = 5 in x"
  assertBool "expected NonZero x" (NonZero (mkName "x") `elem` facts)

testPurityFacts :: Either String ()
testPurityFacts = do
  facts <- factsFor "let x = 5 in x"
  assertBool "expected IsPure x" (IsPure (mkName "x") `elem` facts)

testCoreFunctions :: Either String ()
testCoreFunctions = do
  parsed <- parseExpr incSource
  let nodeValues = Map.elems (coreNodes (lower parsed))
  assertBool "expected a Core lambda node" (any isLam nodeValues)
  assertBool "expected a Core application node" (any isApp nodeValues)

testTopLevelFunctionEvaluation :: Either String ()
testTopLevelFunctionEvaluation = do
  parsed <- parseSource topLevelSource
  actualValue <- mapLeft (showText . renderRuntimeError) (evalProgram parsed)
  expectEqual "top-level program value" (sourceInt 42) actualValue

testExampleSemanticPreservation :: IO (Either String ())
testExampleSemanticPreservation =
  firstFailure checkExampleSemanticPreservation examplePaths

testInterpreterIntOverflow :: Either String ()
testInterpreterIntOverflow = do
  parsed <- parseExpr (Text.pack (show maxHIntInteger <> " + 1"))
  case eval parsed of
    Left err ->
      assertBool "expected checked Int overflow" ("overflowed" `Text.isInfixOf` renderRuntimeError err)
    Right value ->
      Left ("expected checked Int overflow, got " <> show value)

firstFailure :: (a -> IO (Either String ())) -> [a] -> IO (Either String ())
firstFailure action = \case
  [] ->
    pure (Right ())
  item : rest -> do
    result <- action item
    case result of
      Left message -> pure (Left message)
      Right () -> firstFailure action rest

checkExampleSemanticPreservation :: FilePath -> IO (Either String ())
checkExampleSemanticPreservation path = do
  source <- Text.IO.readFile path
  pure $ do
    parsed <- parseExprAt path source
    sourceValue <- mapLeft (showText . renderRuntimeError) (eval parsed)
    anfValue <- mapLeft (showText . renderRuntimeError) (evalANF (toANF parsed))
    sourceObserved <- observeSourceValue sourceValue
    anfObserved <- observeANFValue anfValue
    expectEqual ("semantic preservation for " <> path) sourceObserved anfObserved

testOptimizedANFValidates :: IO (Either String ())
testOptimizedANFValidates =
  firstFailure validateOptimizedExample examplePaths

validateOptimizedExample :: FilePath -> IO (Either String ())
validateOptimizedExample path = do
  source <- Text.IO.readFile path
  pure $ do
    parsed <- parseExprAt path source
    optimized <- mapLeft show (simplifyFixpoint (toANF parsed))
    mapLeft (showText . renderANFValidationError) (validateANF (simplifiedANF optimized))

testOptimizedSemanticPreservation :: IO (Either String ())
testOptimizedSemanticPreservation =
  firstFailure checkOptimizedSemanticPreservation examplePaths

checkOptimizedSemanticPreservation :: FilePath -> IO (Either String ())
checkOptimizedSemanticPreservation path = do
  source <- Text.IO.readFile path
  pure $ do
    parsed <- parseExprAt path source
    let anf = toANF parsed
    optimized <- mapLeft show (simplifyFixpoint anf)
    originalValue <- mapLeft (showText . renderRuntimeError) (evalANF anf)
    optimizedValue <- mapLeft (showText . renderRuntimeError) (evalANF (simplifiedANF optimized))
    originalObserved <- observeANFValue originalValue
    optimizedObserved <- observeANFValue optimizedValue
    expectEqual ("optimized semantic preservation for " <> path) originalObserved optimizedObserved

checkSimplifies :: Text -> AExpr -> Text -> Either String ()
checkSimplifies source expected ruleName = do
  parsed <- parseExpr source
  let original = toANF parsed
  optimized <- mapLeft show (simplifyFixpoint original)
  mapLeft (showText . renderANFValidationError) (validateANF (simplifiedANF optimized))
  originalValue <- mapLeft (showText . renderRuntimeError) (evalANF original)
  optimizedValue <- mapLeft (showText . renderRuntimeError) (evalANF (simplifiedANF optimized))
  originalObserved <- observeANFValue originalValue
  optimizedObserved <- observeANFValue optimizedValue
  expectEqual "optimized ANF" expected (simplifiedANF optimized)
  assertBool
    ("expected rewrite " <> Text.unpack ruleName)
    (any ((== ruleName) . appliedRuleName) (appliedRewrites optimized))
  expectEqual "optimization preserves ANF semantics" originalObserved optimizedObserved

testSimplifierDoesNotFoldOverflow :: Either String ()
testSimplifierDoesNotFoldOverflow = do
  let expression = APrim Add (AInt maxHIntInteger) (AInt 1)
  optimized <- mapLeft show (simplifyFixpoint expression)
  expectEqual "overflowing add is preserved" expression (simplifiedANF optimized)
  assertBool "overflowing add did not apply constant folding" (null (appliedRewrites optimized))

testFixpointSimplification :: Either String ()
testFixpointSimplification = do
  parsed <- parseExpr "if true then 1 + 2 else 0"
  onePass <- mapLeft show (simplifyOnePass (toANF parsed))
  fixpoint <- mapLeft show (simplifyFixpoint (toANF parsed))
  expectEqual "one-pass result" (APrim Add (AInt 1) (AInt 2)) (simplifiedANF onePass)
  expectEqual "fixpoint result" (AAtom (AInt 3)) (simplifiedANF fixpoint)

testRewriteConditions :: Either String ()
testRewriteConditions =
  case matchRewriteRule divideSelfNonZero (APrim Div (AVar xName) (AVar xName)) of
    Nothing ->
      Left "divide-self-nonzero did not match x / x"
    Just binding ->
      case rewriteConditions divideSelfNonZero of
        [condition] -> do
          expectEqual
            "missing NonZero condition"
            (Left (ConditionNotSatisfied condition))
            (checkRewriteConditions [] binding divideSelfNonZero)
          expectEqual
            "satisfied NonZero condition"
            (Right ())
            (checkRewriteConditions [NonZero xName] binding divideSelfNonZero)
        conditions ->
          Left ("expected exactly one rewrite condition, got " <> show conditions)

testEGraphInsertion :: Either String ()
testEGraphInsertion =
  let (rootId, graph) = EG.insertANF (APrim Add (AInt 1) (AInt 0)) EG.emptyEGraph
   in do
        assertBool "root class should exist" (Map.member (EG.findClass graph rootId) (EG.classNodes graph))
        assertBool "expected inserted e-nodes" (Map.size (EG.memo graph) >= 3)

testEGraphUnionFind :: Either String ()
testEGraphUnionFind =
  let (oneId, graph1) = EG.addENode (EG.EInt 1) EG.emptyEGraph
      (twoId, graph2) = EG.addENode (EG.EInt 2) graph1
      graph3 = EG.unionClasses oneId twoId graph2
   in expectEqual "union/find roots" (EG.findClass graph3 oneId) (EG.findClass graph3 twoId)

testEGraphExtraction :: Either String ()
testEGraphExtraction = do
  let (rootId, graph) = EG.insertANF (APrim Add (AInt 1) (AInt 0)) EG.emptyEGraph
  saturated <- mapLeft (showText . EG.renderEGraphError) (EG.saturate graph)
  extracted <- mapLeft (showText . EG.renderEGraphError) (EG.extractCheapest saturated rootId)
  expectEqual "cheapest extraction" (AAtom (AInt 1)) extracted

checkEGraphOptimizes :: Text -> AExpr -> Either String ()
checkEGraphOptimizes source expected = do
  parsed <- parseExpr source
  let original = toANF parsed
  result <- mapLeft (showText . EG.renderEGraphError) (EG.optimizeANF original)
  mapLeft (showText . renderANFValidationError) (validateANF (EG.egraphOptimizedANF result))
  originalValue <- mapLeft (showText . renderRuntimeError) (evalANF original)
  optimizedValue <- mapLeft (showText . renderRuntimeError) (evalANF (EG.egraphOptimizedANF result))
  originalObserved <- observeANFValue originalValue
  optimizedObserved <- observeANFValue optimizedValue
  expectEqual "e-graph optimized ANF" expected (EG.egraphOptimizedANF result)
  expectEqual "e-graph preserves ANF semantics" originalObserved optimizedObserved

testEGraphUnsupportedLambda :: Either String ()
testEGraphUnsupportedLambda =
  expectEqual
    "unsupported lambda"
    (Left (EG.UnsupportedLambda xName))
    (EG.optimizeANF (ALam xName TInt (AAtom (AVar xName))))

testEGraphUnsupportedApplication :: Either String ()
testEGraphUnsupportedApplication =
  expectEqual
    "unsupported application"
    (Left (EG.UnsupportedApplication (AVar (mkName "f")) (AInt 1)))
    (EG.optimizeANF (AApp (AVar (mkName "f")) (AInt 1)))

testEGraphUnsupportedPrimitive :: Either String ()
testEGraphUnsupportedPrimitive =
  expectEqual
    "unsupported primitive"
    (Left (EG.UnsupportedPrimitive Sub))
    (EG.optimizeANF (APrim Sub (AInt 4) (AInt 1)))

testEGraphAgreesWithSimplifier :: Either String ()
testEGraphAgreesWithSimplifier = do
  parsed <- parseExpr "if true then 1 + 0 else 2 * 0"
  simplified <- mapLeft show (simplifyFixpoint (toANF parsed))
  egraph <- mapLeft (showText . EG.renderEGraphError) (EG.optimizeANF (toANF parsed))
  expectEqual
    "e-graph agrees with reference simplifier"
    (simplifiedANF simplified)
    (EG.egraphOptimizedANF egraph)

testEGraphSemanticPreservation :: Either String ()
testEGraphSemanticPreservation =
  firstFailurePure checkSupportedSemanticPreservation supportedEGraphSources

checkSupportedSemanticPreservation :: Text -> Either String ()
checkSupportedSemanticPreservation source = do
  parsed <- parseExpr source
  let original = toANF parsed
  result <- mapLeft (showText . EG.renderEGraphError) (EG.optimizeANF original)
  originalValue <- mapLeft (showText . renderRuntimeError) (evalANF original)
  optimizedValue <- mapLeft (showText . renderRuntimeError) (evalANF (EG.egraphOptimizedANF result))
  originalObserved <- observeANFValue originalValue
  optimizedObserved <- observeANFValue optimizedValue
  expectEqual ("e-graph semantic preservation for " <> Text.unpack source) originalObserved optimizedObserved

testEgglogDefaultFreshId :: Either String ()
testEgglogDefaultFreshId = do
  let db0 = EDB.databaseFromDecls [numDecl]
  (db1, first, firstChanged) <- egg (EDB.callFunction numFn [EV.VInt 1] db0)
  (db2, second, secondChanged) <- egg (EDB.callFunction numFn [EV.VInt 1] db1)
  assertBool "first call should create a default id" firstChanged
  assertBool "second call should reuse the existing id" (not secondChanged)
  expectEqual "fresh id is stable" first second
  found <- egg (EDB.lookupFunction numFn [EV.VInt 1] db2)
  expectEqual "lookup after call" (Just first) found

testEgglogFunctionLookupSet :: Either String ()
testEgglogFunctionLookupSet = do
  let db0 = EDB.databaseFromDecls [edgeRelDecl]
  (db1, changed) <- egg (EDB.setFunction edgeFn [EV.VInt 1, EV.VInt 2] EV.VUnit db0)
  assertBool "set should change relation table" changed
  found <- egg (EDB.lookupFunction edgeFn [EV.VInt 1, EV.VInt 2] db1)
  expectEqual "relation fact lookup" (Just EV.VUnit) found

testEgglogFunctionalDependencyConflict :: Either String ()
testEgglogFunctionalDependencyConflict = do
  let decl = EF.FunctionDecl (fn "score") [ES.SInt] ES.SInt EF.DefaultNone EF.MergeError
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "score") [EV.VInt 1] (EV.VInt 10) db0)
  case EDB.setFunction (fn "score") [EV.VInt 1] (EV.VInt 20) db1 of
    Left (EDB.FunctionalDependencyConflict _ _ _ _ _) -> Right ()
    other -> Left ("expected functional dependency conflict, got " <> show other)

testEgglogMergeUnion :: Either String ()
testEgglogMergeUnion = do
  let decl = EF.FunctionDecl (fn "value") [ES.SInt] exprSort EF.DefaultNone EF.MergeUnion
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "value") [EV.VInt 0] (eid 0) db0)
  (db2, changed) <- egg (EDB.setFunction (fn "value") [EV.VInt 0] (eid 1) db1)
  assertBool "merge union should report a change" changed
  expectEqual "merged ids share a canonical id" (EDB.canonicalValue db2 (eid 0)) (EDB.canonicalValue db2 (eid 1))

testEgglogMergeMinInt :: Either String ()
testEgglogMergeMinInt = do
  let decl = EF.FunctionDecl (fn "path") [ES.SInt, ES.SInt] ES.SInt EF.DefaultNone EF.MergeMinInt
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "path") [EV.VInt 1, EV.VInt 3] (EV.VInt 30) db0)
  (db2, _) <- egg (EDB.setFunction (fn "path") [EV.VInt 1, EV.VInt 3] (EV.VInt 20) db1)
  found <- egg (EDB.lookupFunction (fn "path") [EV.VInt 1, EV.VInt 3] db2)
  expectEqual "min merge result" (Just (EV.VInt 20)) found

testEgglogRejectsBaseUnion :: Either String ()
testEgglogRejectsBaseUnion =
  case EDB.unionValues (EV.VInt 1) (EV.VInt 2) EDB.emptyDatabase of
    Left (EDB.CannotUnionBaseValues (EV.VInt 1) (EV.VInt 2)) -> Right ()
    other -> Left ("expected base union rejection, got " <> show other)

testEgglogRejectsDifferentSortUnion :: Either String ()
testEgglogRejectsDifferentSortUnion =
  case EDB.unionValues (EV.VId exprSortName (ES.Id 0)) (EV.VId nodeSortName (ES.Id 0)) EDB.emptyDatabase of
    Left (EDB.CannotUnionDifferentSorts _ _) -> Right ()
    other -> Left ("expected sort union rejection, got " <> show other)

testEgglogRebuildCanonicalizesKeys :: Either String ()
testEgglogRebuildCanonicalizesKeys = do
  let decl = EF.FunctionDecl (fn "mark") [exprSort] ES.SInt EF.DefaultNone EF.MergeKeepOld
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "mark") [eid 0] (EV.VInt 7) db0)
  (db2, _) <- egg (EDB.unionValues (eid 1) (eid 0) db1)
  (db3, stats, changed) <- egg (ERB.rebuild db2)
  assertBool "rebuild should canonicalize key" changed
  assertBool "canonicalized entry stat should increase" (ERB.canonicalizedEntries stats > 0)
  found <- egg (EDB.lookupFunction (fn "mark") [eid 1] db3)
  expectEqual "lookup through canonicalized key" (Just (EV.VInt 7)) found

testEgglogRebuildResolvesConflicts :: Either String ()
testEgglogRebuildResolvesConflicts = do
  let decl = EF.FunctionDecl (fn "score") [exprSort] ES.SInt EF.DefaultNone EF.MergeMinInt
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "score") [eid 0] (EV.VInt 30) db0)
  (db2, _) <- egg (EDB.setFunction (fn "score") [eid 1] (EV.VInt 20) db1)
  (db3, _) <- egg (EDB.unionValues (eid 0) (eid 1) db2)
  (db4, stats, _) <- egg (ERB.rebuild db3)
  assertBool "rebuild should expose one conflict" (ERB.mergeConflicts stats > 0)
  found <- egg (EDB.lookupFunction (fn "score") [eid 0] db4)
  expectEqual "conflict resolved by min merge" (Just (EV.VInt 20)) found

testEgglogRebuildMergeUnion :: Either String ()
testEgglogRebuildMergeUnion = do
  let decl = EF.FunctionDecl (fn "link") [exprSort] exprSort EF.DefaultNone EF.MergeUnion
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "link") [eid 0] (eid 2) db0)
  (db2, _) <- egg (EDB.setFunction (fn "link") [eid 1] (eid 3) db1)
  (db3, _) <- egg (EDB.unionValues (eid 0) (eid 1) db2)
  (db4, stats, _) <- egg (ERB.rebuild db3)
  assertBool "merge union should create union work during rebuild" (ERB.unionsCreated stats > 0)
  assertBool "rebuild should run a fixpoint after union work" (ERB.rebuildIterations stats >= 2)
  expectEqual "merged outputs share a canonical id" (EDB.canonicalValue db4 (eid 2)) (EDB.canonicalValue db4 (eid 3))

testEgglogSinglePremiseRule :: Either String ()
testEgglogSinglePremiseRule = do
  result <- eggRun [edgeToPathRule] [ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]] [edgeRelDecl, pathRelDecl]
  found <- egg (EDB.lookupFunction pathFn [EV.VInt 1, EV.VInt 2] (EEV.resultDatabase result))
  expectEqual "edge implies path" (Just EV.VUnit) found

testEgglogMultiPremiseJoin :: Either String ()
testEgglogMultiPremiseJoin = do
  result <-
    eggRun
      [edgeToPathRule, transitivePathRule]
      [ ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]
      , ER.relationFact edgeFn [EV.VInt 2, EV.VInt 3]
      ]
      [edgeRelDecl, pathRelDecl]
  found <- egg (EDB.lookupFunction pathFn [EV.VInt 1, EV.VInt 3] (EEV.resultDatabase result))
  expectEqual "join derives transitive path" (Just EV.VUnit) found

testEgglogJoinPlannerRespectsDependencies :: Either String ()
testEgglogJoinPlannerRespectsDependencies = do
  let filteredPathFn = fn "filtered-path"
      filteredPathDecl = EF.relation filteredPathFn [ES.SInt, ES.SInt]
      x = intVar "x"
      y = intVar "y"
      rule =
        ER.Rule
          { ER.ruleName = fn "computed-filter"
          , ER.rulePremises =
              [ ER.QEq (EP.PAddInt x (EP.PValue (EV.VInt 1))) (EP.PValue (EV.VInt 3))
              , ER.QLookup edgeFn [x, y] (EP.PValue EV.VUnit)
              ]
          , ER.ruleActions = [ER.AAssert filteredPathFn [x, y]]
          }
  result <-
    eggRun
      [rule]
      [ ER.relationFact edgeFn [EV.VInt 2, EV.VInt 9]
      , ER.relationFact edgeFn [EV.VInt 4, EV.VInt 9]
      ]
      [edgeRelDecl, filteredPathDecl]
  kept <- egg (EDB.lookupFunction filteredPathFn [EV.VInt 2, EV.VInt 9] (EEV.resultDatabase result))
  rejected <- egg (EDB.lookupFunction filteredPathFn [EV.VInt 4, EV.VInt 9] (EEV.resultDatabase result))
  expectEqual "computed equality filters after x is bound" (Just EV.VUnit) kept
  expectEqual "nonmatching edge is not derived" Nothing rejected

testEgglogJoinPlannerUsesStableCostOrder :: Either String ()
testEgglogJoinPlannerUsesStableCostOrder = do
  let bigFn = fn "big"
      smallFn = fn "small"
      joinedFn = fn "joined"
      bigDecl = EF.relation bigFn [ES.SInt]
      smallDecl = EF.relation smallFn [ES.SInt]
      joinedDecl = EF.relation joinedFn [ES.SInt, ES.SInt]
      x = intVar "x"
      y = intVar "y"
      rule =
        ER.Rule
          { ER.ruleName = fn "join-cost"
          , ER.rulePremises =
              [ ER.QLookup bigFn [x] (EP.PValue EV.VUnit)
              , ER.QLookup smallFn [y] (EP.PValue EV.VUnit)
              ]
          , ER.ruleActions = [ER.AAssert joinedFn [x, y]]
          }
  result <-
    egg
      ( EEV.runProgram
          EEV.defaultRunConfig
            { EEV.collectDebugLog = True
            , EEV.maxIterations = 8
            , EEV.runMode = EEV.RunNaive
            }
          ER.Program
            { ER.programDecls = [bigDecl, smallDecl, joinedDecl]
            , ER.programInitialActions =
                [ ER.relationFact bigFn [EV.VInt 1]
                , ER.relationFact bigFn [EV.VInt 2]
                , ER.relationFact bigFn [EV.VInt 3]
                , ER.relationFact smallFn [EV.VInt 10]
                , ER.relationFact smallFn [EV.VInt 20]
                ]
            , ER.programRules = [rule]
            }
      )
  let ruleTraces =
        filter ("rule join-cost" `Text.isPrefixOf`) (reverse (EDB.debugLog (EEV.resultDatabase result)))
  case ruleTraces of
    _first : second : _ -> do
      assertBool
        "second substitution should keep the smaller relation fixed before advancing it"
        ("{x=2, y=10}" `Text.isInfixOf` second)
      expectEqual "six joined facts should be derived" 6 (length ruleTraces)
    other ->
      Left ("expected join-cost rule traces, got " <> show other)

testEgglogSemiNaiveMatchesNaiveTransitiveClosure :: Either String ()
testEgglogSemiNaiveMatchesNaiveTransitiveClosure = do
  naive <- runReachability EEV.RunNaive
  semiNaive <- runReachability EEV.RunSemiNaive
  expectEqual "semi-naive final database" (EEV.resultDatabase naive) (EEV.resultDatabase semiNaive)
  assertBool "semi-naive reaches saturation" (EEV.resultSaturated semiNaive)
 where
  runReachability mode =
    egg
      ( EEV.runProgram
          EEV.defaultRunConfig {EEV.maxIterations = 24, EEV.runMode = mode}
          ER.Program
            { ER.programDecls = [edgeRelDecl, pathRelDecl]
            , ER.programInitialActions =
                [ ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]
                , ER.relationFact edgeFn [EV.VInt 2, EV.VInt 3]
                , ER.relationFact edgeFn [EV.VInt 3, EV.VInt 4]
                , ER.relationFact edgeFn [EV.VInt 4, EV.VInt 5]
                ]
            , ER.programRules = [edgeToPathRule, transitivePathRule]
            }
      )

testEgglogSemiNaivePreservesCompilerBackend :: Either String ()
testEgglogSemiNaivePreservesCompilerBackend = do
  parsed <- parseExpr "let x = 3 in let y = x + 4 in y * 2"
  let expression = toANF parsed
  naive <-
    mapLeft
      (showText . OEB.renderEgglogBackendError)
      (OEB.optimizeWithEgglog EEV.defaultRunConfig {EEV.runMode = EEV.RunNaive} expression)
  semiNaive <-
    mapLeft
      (showText . OEB.renderEgglogBackendError)
      (OEB.optimizeWithEgglog EEV.defaultRunConfig {EEV.runMode = EEV.RunSemiNaive} expression)
  expectEqual "optimized ANF" (OEB.optimizedANF naive) (OEB.optimizedANF semiNaive)
  expectEqual "optimized cost" (OEB.extractionStats naive) (OEB.extractionStats semiNaive)
  assertBool "semi-naive backend run saturates" (OEB.runSaturated (OEB.runStats semiNaive))

testEgglogDebugTraceRecordsRuleAction :: Either String ()
testEgglogDebugTraceRecordsRuleAction = do
  result <-
    egg
      ( EEV.runProgram
          EEV.defaultRunConfig {EEV.collectDebugLog = True, EEV.maxIterations = 8}
          ER.Program
            { ER.programDecls = [edgeRelDecl, pathRelDecl]
            , ER.programInitialActions = [ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]]
            , ER.programRules = [edgeToPathRule]
            }
      )
  let logs = EDB.debugLog (EEV.resultDatabase result)
  assertBool
    "debug log should include the rule action that produced path"
    (any (\line -> "rule edge-to-path substitution #0" `Text.isInfixOf` line && "assert path" `Text.isInfixOf` line) logs)
  assertBool
    "debug log should include substitution values"
    (any ("{x=1, y=2}" `Text.isInfixOf`) logs)

testEgglogVariableBinding :: Either String ()
testEgglogVariableBinding = do
  let revFn = fn "rev"
      revDecl = EF.relation revFn [ES.SInt, ES.SInt]
      x = EP.PVar (var "x") ES.SInt
      y = EP.PVar (var "y") ES.SInt
      rule =
        ER.Rule
          { ER.ruleName = fn "reverse-edge"
          , ER.rulePremises = [ER.QLookup edgeFn [x, y] (EP.PValue EV.VUnit)]
          , ER.ruleActions = [ER.AAssert revFn [y, x]]
          }
  result <-
    eggRun
      [rule]
      [ ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]
      , ER.relationFact edgeFn [EV.VInt 1, EV.VInt 3]
      ]
      [edgeRelDecl, revDecl]
  first <- egg (EDB.lookupFunction revFn [EV.VInt 2, EV.VInt 1] (EEV.resultDatabase result))
  second <- egg (EDB.lookupFunction revFn [EV.VInt 3, EV.VInt 1] (EEV.resultDatabase result))
  expectEqual "first reversed edge" (Just EV.VUnit) first
  expectEqual "second reversed edge" (Just EV.VUnit) second

testEgglogTypedMismatchFailure :: Either String ()
testEgglogTypedMismatchFailure =
  case EEV.applyAction EP.emptySubstitution db (ER.AAssert edgeFn [EP.PValue (EV.VBool True), EP.PValue (EV.VInt 2)]) of
    Left (EDB.SortMismatch _ _) -> Right ()
    other -> Left ("expected structured sort mismatch, got " <> show other)
 where
  db = EDB.databaseFromDecls [edgeRelDecl]

testEgglogActionApplication :: Either String ()
testEgglogActionApplication = do
  let answerFn = fn "answer"
      answerDecl = EF.FunctionDecl answerFn [] ES.SInt EF.DefaultNone EF.MergeKeepOld
      rule =
        ER.Rule
          { ER.ruleName = fn "answer-rule"
          , ER.rulePremises = []
          , ER.ruleActions = [ER.ASet answerFn [] (EP.PValue (EV.VInt 7))]
          }
  result <- eggRun [rule] [] [answerDecl]
  found <- egg (EDB.lookupFunction answerFn [] (EEV.resultDatabase result))
  expectEqual "empty-premise action applies" (Just (EV.VInt 7)) found

testEgglogRewriteDesugars :: Either String ()
testEgglogRewriteDesugars =
  case ER.rewrite (fn "add-comm") exprSort (EP.PCall addFn [exprVar "a", exprVar "b"]) (EP.PCall addFn [exprVar "b", exprVar "a"]) of
    ER.Rule {ER.rulePremises = [ER.QMatch _ _], ER.ruleActions = [ER.AUnion _ _]} -> Right ()
    rule -> Left ("expected rewrite to be ordinary match+union rule, got " <> show rule)

testEgglogRewriteNonDestructive :: Either String ()
testEgglogRewriteNonDestructive = do
  let original = EP.PCall addFn [numPattern 1, numPattern 2]
      rule = ER.rewrite (fn "add-comm") exprSort (EP.PCall addFn [exprVar "a", exprVar "b"]) (EP.PCall addFn [exprVar "b", exprVar "a"])
  result <- eggRun [rule] [ER.AUnion original original] arithmeticDecls
  originalValue <- topValue (EEV.resultDatabase result) addFn [numPattern 1, numPattern 2]
  replacementValue <- topValue (EEV.resultDatabase result) addFn [numPattern 2, numPattern 1]
  expectEqual "original and replacement are equivalent" (EDB.canonicalValue (EEV.resultDatabase result) originalValue) (EDB.canonicalValue (EEV.resultDatabase result) replacementValue)

testEgglogPaperReachability :: Either String ()
testEgglogPaperReachability = do
  result <-
    eggRun
      [edgeToPathRule, transitivePathRule]
      [ ER.relationFact edgeFn [EV.VInt 1, EV.VInt 2]
      , ER.relationFact edgeFn [EV.VInt 2, EV.VInt 3]
      , ER.relationFact edgeFn [EV.VInt 3, EV.VInt 4]
      ]
      [edgeRelDecl, pathRelDecl]
  found <- egg (EDB.lookupFunction pathFn [EV.VInt 1, EV.VInt 4] (EEV.resultDatabase result))
  expectEqual "path 1 4" (Just EV.VUnit) found

testEgglogPaperShortestPath :: Either String ()
testEgglogPaperShortestPath = do
  let edgeCostFn = fn "edgeCost"
      pathCostFn = fn "pathCost"
      edgeCostDecl = EF.FunctionDecl edgeCostFn [ES.SInt, ES.SInt] ES.SInt EF.DefaultNone EF.MergeKeepOld
      pathCostDecl = EF.FunctionDecl pathCostFn [ES.SInt, ES.SInt] ES.SInt EF.DefaultNone EF.MergeMinInt
      x = EP.PVar (var "x") ES.SInt
      y = EP.PVar (var "y") ES.SInt
      z = EP.PVar (var "z") ES.SInt
      len = EP.PVar (var "len") ES.SInt
      xy = EP.PVar (var "xy") ES.SInt
      yz = EP.PVar (var "yz") ES.SInt
      direct =
        ER.Rule
          { ER.ruleName = fn "direct-path-cost"
          , ER.rulePremises = [ER.QLookup edgeCostFn [x, y] len]
          , ER.ruleActions = [ER.ASet pathCostFn [x, y] len]
          }
      step =
        ER.Rule
          { ER.ruleName = fn "extend-path-cost"
          , ER.rulePremises = [ER.QLookup pathCostFn [x, y] xy, ER.QLookup edgeCostFn [y, z] yz]
          , ER.ruleActions = [ER.ASet pathCostFn [x, z] (EP.PAddInt xy yz)]
          }
  result <-
    eggRun
      [direct, step]
      [ ER.ASet edgeCostFn [EP.PValue (EV.VInt 1), EP.PValue (EV.VInt 2)] (EP.PValue (EV.VInt 10))
      , ER.ASet edgeCostFn [EP.PValue (EV.VInt 2), EP.PValue (EV.VInt 3)] (EP.PValue (EV.VInt 10))
      , ER.ASet edgeCostFn [EP.PValue (EV.VInt 1), EP.PValue (EV.VInt 3)] (EP.PValue (EV.VInt 30))
      ]
      [edgeCostDecl, pathCostDecl]
  found <- egg (EDB.lookupFunction pathCostFn [EV.VInt 1, EV.VInt 3] (EEV.resultDatabase result))
  expectEqual "shortest path merge" (Just (EV.VInt 20)) found

testEgglogPaperArithmetic :: Either String ()
testEgglogPaperArithmetic = do
  let expr1 = EP.PCall mulFn [numPattern 2, EP.PCall addFn [varPattern "x", numPattern 3]]
      expr2 = EP.PCall addFn [numPattern 6, EP.PCall mulFn [numPattern 2, varPattern "x"]]
  result <- eggRun arithmeticRules [ER.AUnion expr1 expr1, ER.AUnion expr2 expr2] arithmeticDecls
  first <- topValue (EEV.resultDatabase result) mulFn [numPattern 2, EP.PCall addFn [varPattern "x", numPattern 3]]
  second <- topValue (EEV.resultDatabase result) addFn [numPattern 6, EP.PCall mulFn [numPattern 2, varPattern "x"]]
  expectEqual "paper arithmetic terms become equivalent" (EDB.canonicalValue (EEV.resultDatabase result) first) (EDB.canonicalValue (EEV.resultDatabase result) second)

testEgglogExtractionCheapest :: Either String ()
testEgglogExtractionCheapest = do
  let original = EP.PCall addFn [numPattern 1, numPattern 0]
  result <- eggRun arithmeticRules [ER.AUnion original original] arithmeticDecls
  root <- topValue (EEV.resultDatabase result) addFn [numPattern 1, numPattern 0]
  case EDB.canonicalValue (EEV.resultDatabase result) root of
    EV.VId sortName ident -> do
      extracted <- egg (EEX.extractCheapest (EEV.resultDatabase result) sortName ident)
      expectEqual "cheapest add-zero representative" (EEX.ExtractCall numFn [EEX.ExtractValue (EV.VInt 1)]) extracted
    value -> Left ("expected expression id, got " <> show value)

testEgglogExtractionCycle :: Either String ()
testEgglogExtractionCycle = do
  let loopFn = fn "Loop"
      loopDecl = EF.FunctionDecl loopFn [exprSort] exprSort EF.DefaultFreshId EF.MergeUnion
      db0 = EDB.databaseFromDecls [loopDecl]
  (db1, value, _) <- egg (EDB.callFunction loopFn [eid 0] db0)
  case value of
    EV.VId sortName ident ->
      case EEX.extractCheapest db1 sortName ident of
        Left (EDB.ExtractionError _) -> Right ()
        other -> Left ("expected cycle-safe extraction failure, got " <> show other)
    _ ->
      Left "loop unexpectedly returned a base value"

testEgglogExtractionImpossible :: Either String ()
testEgglogExtractionImpossible =
  let (value, db) = EDB.freshId exprSortName (EDB.databaseFromDecls arithmeticDecls)
   in case value of
        EV.VId sortName ident ->
          case EEX.extractCheapest db sortName ident of
            Left (EDB.ExtractionError _) -> Right ()
            other -> Left ("expected structural extraction failure, got " <> show other)
        _ ->
          Left "fresh expression unexpectedly returned a base value"

testEgglogBackendSupportedArithmetic :: Either String ()
testEgglogBackendSupportedArithmetic = do
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeANFWithEgglog (APrim Add (AInt 7) (AInt 0)))
  expectEqual "egglog backend add-zero" (AAtom (AInt 7)) (OEB.egglogOptimizedANF result)

testEgglogBackendUnsupportedLambda :: Either String ()
testEgglogBackendUnsupportedLambda =
  case OEB.optimizeANFWithEgglog (ALam xName TInt (AAtom (AVar xName))) of
    Left (OEB.UnsupportedLambda _) -> Right ()
    other -> Left ("expected unsupported lambda error, got " <> show other)

testEgglogConstIntMergeSame :: Either String ()
testEgglogConstIntMergeSame = do
  let decl = EF.FunctionDecl (fn "const") [ES.SInt] ES.SConstInt EF.DefaultNone EF.MergeConstInt
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "const") [EV.VInt 0] (EV.VConstInt (knownInt 3)) db0)
  (db2, _) <- egg (EDB.setFunction (fn "const") [EV.VInt 0] (EV.VConstInt (knownInt 3)) db1)
  found <- egg (EDB.lookupFunction (fn "const") [EV.VInt 0] db2)
  expectEqual "same constants merge unchanged" (Just (EV.VConstInt (knownInt 3))) found

testEgglogConstIntMergeConflict :: Either String ()
testEgglogConstIntMergeConflict = do
  let decl = EF.FunctionDecl (fn "const") [ES.SInt] ES.SConstInt EF.DefaultNone EF.MergeConstInt
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "const") [EV.VInt 0] (EV.VConstInt (knownInt 3)) db0)
  (db2, _) <- egg (EDB.setFunction (fn "const") [EV.VInt 0] (EV.VConstInt (knownInt 4)) db1)
  found <- egg (EDB.lookupFunction (fn "const") [EV.VInt 0] db2)
  expectEqual "conflicting constants merge to conflict" (Just (EV.VConstInt EV.ConflictInt)) found

testEgglogZeroInfoMergeUnknown :: Either String ()
testEgglogZeroInfoMergeUnknown = do
  let decl = EF.FunctionDecl (fn "zero-info") [ES.SInt] ES.SZeroInfo EF.DefaultNone EF.MergeZeroInfo
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "zero-info") [EV.VInt 0] (EV.VZeroInfo EV.UnknownZeroInfo) db0)
  (db2, changed) <- egg (EDB.setFunction (fn "zero-info") [EV.VInt 0] (EV.VZeroInfo EV.KnownNonZero) db1)
  assertBool "unknown zero info should refine to known nonzero" changed
  found <- egg (EDB.lookupFunction (fn "zero-info") [EV.VInt 0] db2)
  expectEqual "refined zero info" (Just (EV.VZeroInfo EV.KnownNonZero)) found

testEgglogZeroInfoMergeConflict :: Either String ()
testEgglogZeroInfoMergeConflict = do
  let decl = EF.FunctionDecl (fn "zero-info") [ES.SInt] ES.SZeroInfo EF.DefaultNone EF.MergeZeroInfo
      db0 = EDB.databaseFromDecls [decl]
  (db1, _) <- egg (EDB.setFunction (fn "zero-info") [EV.VInt 0] (EV.VZeroInfo EV.KnownZero) db0)
  (db2, _) <- egg (EDB.setFunction (fn "zero-info") [EV.VInt 0] (EV.VZeroInfo EV.KnownNonZero) db1)
  found <- egg (EDB.lookupFunction (fn "zero-info") [EV.VInt 0] db2)
  expectEqual "conflicting zero info" (Just (EV.VZeroInfo EV.ConflictZeroInfo)) found

testResolvedANFSimpleLet :: Either String ()
testResolvedANFSimpleLet = do
  resolved <- resolvedFor "let x = 1 in x"
  expectEqual "one binder" 1 (Set.size (RANF.boundVarsResolved resolved))
  assertBool "no free variables" (Set.null (RANF.freeVarsResolved resolved))
  case resolved of
    RANF.RLet binder _ (RANF.RAtom (RANF.RVar (RANF.BoundVar ref))) ->
      expectEqual "body points to let binder" (RANF.binderId binder) (RANF.binderId ref)
    other ->
      Left ("unexpected resolved simple let shape: " <> show other)

testResolvedANFShadowing :: Either String ()
testResolvedANFShadowing = do
  parsed <- parseExpr "let x = 1 in let y = let x = 2 in x in x + y"
  resolved <- mapLeft show (RANF.resolveANF (toANF parsed))
  let binders = Map.elems (RANF.boundVariables resolved)
      binderIds = map RANF.binderId binders
  expectEqual "three let binders" 3 (length binders)
  expectEqual "unique binder ids" (length binderIds) (length (unique binderIds))
  assertBool "no free variables in closed shadowing program" (null (RANF.freeVariables resolved))

testResolvedANFInnerShadowReference :: Either String ()
testResolvedANFInnerShadowReference = do
  resolved <- resolvedFor "let x = 1 in let x = 2 in x"
  case resolved of
    RANF.RLet outer _ (RANF.RLet inner _ (RANF.RAtom (RANF.RVar (RANF.BoundVar ref)))) -> do
      assertBool "shadowed binders are distinct" (RANF.binderId outer /= RANF.binderId inner)
      expectEqual "final x points to inner binder" (RANF.binderId inner) (RANF.binderId ref)
    other ->
      Left ("unexpected resolved shadowing shape: " <> show other)

testResolvedANFFreeVariable :: Either String ()
testResolvedANFFreeVariable = do
  resolved <- mapLeft show (RANF.resolveANF (APrim Add (AVar xName) (AInt 1)))
  expectEqual "free variables" (Set.singleton xName) (RANF.freeVarsResolved resolved)
  expectEqual "no binders invented" Set.empty (RANF.boundVarsResolved resolved)

testResolvedANFDependencyGraph :: Either String ()
testResolvedANFDependencyGraph = do
  resolved <- resolvedFor "let x = 1 in let y = let x = 2 in x in x + y"
  case resolved of
    RANF.RLet outer _ (RANF.RLet yBinder (RANF.RLet inner _ _) _) -> do
      let graph = RANF.binderDependencyGraph resolved
      expectEqual "outer x has no RHS deps" (Just Set.empty) (Map.lookup (RANF.binderId outer) graph)
      expectEqual "inner x has no RHS deps" (Just Set.empty) (Map.lookup (RANF.binderId inner) graph)
      expectEqual "y depends on inner x RHS" (Just (Set.singleton (RANF.binderId inner))) (Map.lookup (RANF.binderId yBinder) graph)
    other ->
      Left ("unexpected resolved dependency shape: " <> show other)

testResolvedANFRenderer :: Either String ()
testResolvedANFRenderer = do
  resolved <- resolvedFor "let x = 1 in let x = 2 in x"
  let rendered = RANF.renderResolvedANF resolved
  assertBool "renderer includes x#0" ("x#0" `Text.isInfixOf` rendered)
  assertBool "renderer includes x#1" ("x#1" `Text.isInfixOf` rendered)

testEgglogFragmentAcceptsIf :: Either String ()
testEgglogFragmentAcceptsIf = do
  resolved <- resolvedFor "if true then 1 else 2"
  case OEB.classifyEgglogFragment resolved of
    Right {} -> Right ()
    Left err -> Left ("expected if expression to be accepted, got " <> Text.unpack (OEB.renderEgglogBackendError err))

testEgglogFragmentAcceptsComparisons :: Either String ()
testEgglogFragmentAcceptsComparisons = do
  ltResolved <- resolvedFor "1 < 2"
  eqResolved <- resolvedFor "true == false"
  case (OEB.classifyEgglogFragment ltResolved, OEB.classifyEgglogFragment eqResolved) of
    (Right {}, Right {}) -> Right ()
    (ltResult, eqResult) ->
      Left ("expected comparisons to be accepted, got " <> show (ltResult, eqResult))

testEgglogFragmentAcceptsSubtraction :: Either String ()
testEgglogFragmentAcceptsSubtraction = do
  resolved <- resolvedFor "5 - 2"
  case OEB.classifyEgglogFragment resolved of
    Right {} -> Right ()
    Left err -> Left ("expected subtraction to be accepted, got " <> Text.unpack (OEB.renderEgglogBackendError err))

testEgglogFragmentAcceptsDivision :: Either String ()
testEgglogFragmentAcceptsDivision = do
  resolved <- resolvedFor "8 / 2"
  case OEB.classifyEgglogFragment resolved of
    Right {} -> Right ()
    Left err -> Left ("expected division to be accepted, got " <> Text.unpack (OEB.renderEgglogBackendError err))

testEgglogFragmentRejectsIfMismatch :: Either String ()
testEgglogFragmentRejectsIfMismatch =
  let malformed =
        RANF.RIf
          (RANF.RBool True)
          (RANF.RAtom (RANF.RInt 1))
          (RANF.RAtom (RANF.RBool False))
   in case OEB.classifyEgglogFragment malformed of
        Left (OEB.FragmentTypeMismatch TInt TBool) -> Right ()
        other -> Left ("expected if branch mismatch, got " <> show other)

testEgglogFragmentRejectsInconsistentFreeVariableTypes :: Either String ()
testEgglogFragmentRejectsInconsistentFreeVariableTypes = do
  resolved <-
    mapLeft show $
      RANF.resolveANF
        (AIf (AVar xName) (AAtom (AInt 1)) (APrim Add (AVar xName) (AInt 1)))
  case OEB.classifyEgglogFragment resolved of
    Left (OEB.FragmentTypeMismatch TBool TInt) -> Right ()
    other -> Left ("expected free variable type mismatch, got " <> show other)

testEgglogEncodingDistinctTypedSorts :: Either String ()
testEgglogEncodingDistinctTypedSorts = do
  intEncoded <- encodeSource "1 + 2"
  boolEncoded <- encodeSource "if true then false else true"
  expectEqual "int root type" TInt (OEB.encodedRootType intEncoded)
  expectEqual "bool root type" TBool (OEB.encodedRootType boolEncoded)
  expectEqual "int root function" (OES.iRootFn OES.symbols) (OEB.encodedRootFunction intEncoded)
  expectEqual "bool root function" (OES.bRootFn OES.symbols) (OEB.encodedRootFunction boolEncoded)

testEgglogEncodingRejectsCrossSort :: Either String ()
testEgglogEncodingRejectsCrossSort =
  let db = EDB.databaseFromDecls OES.backendDecls
   in case EDB.callFunction (OES.iAddFn OES.symbols) [EV.VId (OES.bExprSortName OES.symbols) (ES.Id 0), EV.VId (OES.iExprSortName OES.symbols) (ES.Id 0)] db of
        Left (EDB.SortMismatch _ _) -> Right ()
        other -> Left ("expected cross-sort construction to fail, got " <> show other)

testEgglogEncodingBinderKeys :: Either String ()
testEgglogEncodingBinderKeys = do
  encoded <- encodeSource "let x = 1 in let x = 2 in x"
  let keys =
        [ key
        | EP.PCall _ [EP.PValue (EV.VString key)] <- Map.elems (OEB.encodedBinderTerms encoded)
        ]
  expectEqual "two local binder keys" 2 (length keys)
  expectEqual "keys are distinct" (length keys) (length (unique keys))
  assertBool "local binder keys are tagged" (all ("local:" `Text.isPrefixOf`) keys)

testEgglogEncodingFreeVariable :: Either String ()
testEgglogEncodingFreeVariable = do
  encoded <- encodeSourceANF (APrim Add (AVar xName) (AInt 1))
  case Map.lookup xName (OEB.encodedFreeVariables encoded) of
    Just (EP.PCall name [EP.PValue (EV.VString key)]) -> do
      expectEqual "free variable function" (OES.iVarFn OES.symbols) name
      expectEqual "free key" "free:x" key
    other ->
      Left ("expected explicit free variable term, got " <> show other)

testEgglogEncodingLetEquality :: Either String ()
testEgglogEncodingLetEquality = do
  encoded <- encodeSource "let x = 1 + 2 in x"
  binding <-
    case Map.elems (OEB.encodedBindings encoded) of
      [value] -> Right value
      other -> Left ("expected one encoded binding, got " <> show other)
  let hasUnion =
        any
          ( \case
              ER.AUnion lhs _ -> lhs == OEB.encodedBinderPattern binding
              _ -> False
          )
          (ER.programInitialActions (OEB.encodedProgram encoded))
  assertBool "let binder is equated with RHS via Egglog union" hasUnion

testEgglogRulesDeriveConstFacts :: Either String ()
testEgglogRulesDeriveConstFacts = do
  (encoded, run) <- runEncodedSource "2 + 3"
  root <- canonicalRoot encoded run
  found <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [root] (OEB.encodedRunDatabase run))
  expectEqual "IConst root" (Just (EV.VConstInt (knownInt 5))) found

testEgglogRulesConstantFoldEquality :: Either String ()
testEgglogRulesConstantFoldEquality = do
  (encoded, run) <- runEncodedSource "2 + 3"
  assertEquivalentToPattern encoded run (EP.PCall (OES.iNumFn OES.symbols) [EP.PValue (EV.VInt 5)])

testEgglogRulesMultiplicationIdentities :: Either String ()
testEgglogRulesMultiplicationIdentities = do
  checkMul (APrim Mul (AVar xName) (AInt 1)) (EP.PCall (OES.iVarFn OES.symbols) [EP.PValue (EV.VString "free:x")])
  checkMul (APrim Mul (AInt 1) (AVar xName)) (EP.PCall (OES.iVarFn OES.symbols) [EP.PValue (EV.VString "free:x")])
  checkMulNotZero (APrim Mul (AVar xName) (AInt 0))
  checkMulNotZero (APrim Mul (AInt 0) (AVar xName))
 where
  checkMul expression expectedPattern = do
    (encoded, run) <- runEncodedANF expression
    assertEquivalentToPattern encoded run expectedPattern
  checkMulNotZero expression = do
    (encoded, run) <- runEncodedANF expression
    root <- canonicalRoot encoded run
    zero <- lookupPatternValue (OEB.encodedRunDatabase run) (EP.PCall (OES.iNumFn OES.symbols) [EP.PValue (EV.VInt 0)])
    assertBool "open multiplication by zero is not folded because it may hide strict local errors" (root /= EDB.canonicalValue (OEB.encodedRunDatabase run) zero)

testEgglogRulesIfTrue :: Either String ()
testEgglogRulesIfTrue = do
  (encoded, run) <- runEncodedSource "if true then 10 else 20"
  assertEquivalentToPattern encoded run (EP.PCall (OES.iNumFn OES.symbols) [EP.PValue (EV.VInt 10)])

testEgglogRulesFactDrivenIf :: Either String ()
testEgglogRulesFactDrivenIf = do
  (encoded, run) <- runEncodedSource "let b = true in if b then 10 else 20"
  assertEquivalentToPattern encoded run (EP.PCall (OES.iNumFn OES.symbols) [EP.PValue (EV.VInt 10)])

testEgglogRulesStrictSafeBooleans :: Either String ()
testEgglogRulesStrictSafeBooleans = do
  checkBool (APrim Eq (AVar xName) (ABool True)) (EP.PCall (OES.bVarFn OES.symbols) [EP.PValue (EV.VString "free:x")])
  checkBool (APrim Eq (ABool True) (AVar xName)) (EP.PCall (OES.bVarFn OES.symbols) [EP.PValue (EV.VString "free:x")])
  checkBool (AIf (AVar xName) (AAtom (ABool True)) (AAtom (ABool False))) (EP.PCall (OES.bVarFn OES.symbols) [EP.PValue (EV.VString "free:x")])
 where
  checkBool expression expectedPattern = do
    (encoded, run) <- runEncodedANF expression
    assertEquivalentToPattern encoded run expectedPattern

testEgglogRulesDeriveZeroInfo :: Either String ()
testEgglogRulesDeriveZeroInfo = do
  (zeroEncoded, zeroRun) <- runEncodedSource "0"
  zeroRoot <- canonicalRoot zeroEncoded zeroRun
  zeroFound <- egg (EDB.lookupFunction (OES.iZeroFn OES.symbols) [zeroRoot] (OEB.encodedRunDatabase zeroRun))
  expectEqual "zero literal has KnownZero info" (Just (EV.VZeroInfo EV.KnownZero)) zeroFound
  (nonZeroEncoded, nonZeroRun) <- runEncodedSource "2 + 3"
  nonZeroRoot <- canonicalRoot nonZeroEncoded nonZeroRun
  nonZeroFound <- egg (EDB.lookupFunction (OES.iZeroFn OES.symbols) [nonZeroRoot] (OEB.encodedRunDatabase nonZeroRun))
  expectEqual "folded nonzero expression has KnownNonZero info" (Just (EV.VZeroInfo EV.KnownNonZero)) nonZeroFound

testEgglogRulesDeriveComparisonFacts :: Either String ()
testEgglogRulesDeriveComparisonFacts = do
  (ltEncoded, ltRun) <- runEncodedSource "2 < 3"
  ltRoot <- canonicalRoot ltEncoded ltRun
  ltFound <- egg (EDB.lookupFunction (OES.bConstFn OES.symbols) [ltRoot] (OEB.encodedRunDatabase ltRun))
  expectEqual "lt constant fact" (Just (EV.VConstBool (EV.KnownBool True))) ltFound
  (intEqEncoded, intEqRun) <- runEncodedSource "2 == 3"
  intEqRoot <- canonicalRoot intEqEncoded intEqRun
  intEqFound <- egg (EDB.lookupFunction (OES.bConstFn OES.symbols) [intEqRoot] (OEB.encodedRunDatabase intEqRun))
  expectEqual "int equality constant fact" (Just (EV.VConstBool (EV.KnownBool False))) intEqFound
  (boolEqEncoded, boolEqRun) <- runEncodedSource "true == false"
  boolEqRoot <- canonicalRoot boolEqEncoded boolEqRun
  boolEqFound <- egg (EDB.lookupFunction (OES.bConstFn OES.symbols) [boolEqRoot] (OEB.encodedRunDatabase boolEqRun))
  expectEqual "bool equality constant fact" (Just (EV.VConstBool (EV.KnownBool False))) boolEqFound

testEgglogRulesDeriveSubtractionFacts :: Either String ()
testEgglogRulesDeriveSubtractionFacts = do
  (encoded, run) <- runEncodedSource "7 - 2"
  root <- canonicalRoot encoded run
  found <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [root] (OEB.encodedRunDatabase run))
  expectEqual "subtraction constant fact" (Just (EV.VConstInt (knownInt 5))) found

testEgglogRulesDeriveDivisionFacts :: Either String ()
testEgglogRulesDeriveDivisionFacts = do
  (encoded, run) <- runEncodedSource "8 / 2"
  root <- canonicalRoot encoded run
  found <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [root] (OEB.encodedRunDatabase run))
  expectEqual "division constant fact" (Just (EV.VConstInt (knownInt 4))) found

testEgglogRulesAvoidUnsafeDivisionFacts :: Either String ()
testEgglogRulesAvoidUnsafeDivisionFacts = do
  assertNoKnownDivFact (APrim Div (AInt 8) (AInt 0))
  assertNoKnownDivFact (APrim Div (AInt minHIntInteger) (AInt (-1)))
 where
  assertNoKnownDivFact expression = do
    (encoded, run) <- runEncodedANF expression
    root <- canonicalRoot encoded run
    found <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [root] (OEB.encodedRunDatabase run))
    case found of
      Just (EV.VConstInt (EV.KnownInt n)) ->
        Left ("unsafe division derived false KnownInt " <> show (hintToInteger n))
      _ ->
        Right ()

testEgglogRulesExcludeDistributivity :: Either String ()
testEgglogRulesExcludeDistributivity = do
  let compilerRuleNames = map ER.ruleName OER.compilerRules
      experimentalRuleNames = map ER.ruleName OER.experimentalEqSatRules
      distribute = fn "egglog-distribute-mul-add"
  assertBool "compiler rules should not include distributivity" (distribute `notElem` compilerRuleNames)
  assertBool "experimental rules keep distributivity available" (distribute `elem` experimentalRuleNames)

testEgglogBackendShadowing :: Either String ()
testEgglogBackendShadowing =
  assertEgglogPreservesSemantics "let x = 1 in let y = let x = 2 in x in x + y" (anfInt 3) >> Right ()

testEgglogBackendLetRetention :: Either String ()
testEgglogBackendLetRetention = do
  result <- assertEgglogPreservesSemantics "let x = 1 + 2 in x * 10" (anfInt 30)
  mapLeft (showText . renderANFValidationError) (validateANF (OEB.optimizedANF result))

testEgglogBackendDeadLet :: Either String ()
testEgglogBackendDeadLet =
  assertEgglogPreservesSemantics "let x = 1 + 2 in 4" (anfInt 4) >> Right ()

testEgglogBackendIfTrue :: Either String ()
testEgglogBackendIfTrue =
  assertEgglogPreservesSemantics "if true then 10 else 20" (anfInt 10) >> Right ()

testEgglogBackendIfSameBranches :: Either String ()
testEgglogBackendIfSameBranches = do
  knownCondition <- assertEgglogPreservesSemantics "if true then 5 else 5" (anfInt 5)
  expectEqual "known same-branch if selects the branch" (AAtom (AInt 5)) (OEB.optimizedANF knownCondition)
  assertEgglogPreservesSemantics "let someBool = true in let x = 3 in if someBool then x else x" (anfInt 3) >> Right ()

testEgglogBackendConstFacts :: Either String ()
testEgglogBackendConstFacts = do
  assertEgglogPreservesSemantics "let x = 2 + 3 in x * 4" (anfInt 20) >> Right ()
  zeroRight <- assertEgglogPreservesSemantics "3 * 0" (anfInt 0)
  expectEqual "checked constant multiplication by zero folds on the right" (AAtom (AInt 0)) (OEB.optimizedANF zeroRight)
  zeroLeft <- assertEgglogPreservesSemantics "0 * 3" (anfInt 0)
  expectEqual "checked constant multiplication by zero folds on the left" (AAtom (AInt 0)) (OEB.optimizedANF zeroLeft)

testEgglogBackendComparisonConstFacts :: Either String ()
testEgglogBackendComparisonConstFacts = do
  ltResult <- assertEgglogPreservesSemantics "if 2 < 3 then 10 else 20" (anfInt 10)
  expectEqual "lt comparison folds through bool facts" (AAtom (AInt 10)) (OEB.optimizedANF ltResult)
  intEqResult <- assertEgglogPreservesSemantics "if 2 == 3 then 10 else 20" (anfInt 20)
  expectEqual "int equality folds through bool facts" (AAtom (AInt 20)) (OEB.optimizedANF intEqResult)
  boolEqResult <- assertEgglogPreservesSemantics "if true == false then 10 else 20" (anfInt 20)
  expectEqual "bool equality folds through bool facts" (AAtom (AInt 20)) (OEB.optimizedANF boolEqResult)

testEgglogBackendOpenComparisonFragment :: Either String ()
testEgglogBackendOpenComparisonFragment = do
  ltResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Lt (AVar xName) (AInt 10)))
  expectEqual "open lt expression" (APrim Lt (AVar xName) (AInt 10)) (OEB.optimizedANF ltResult)
  expectEqual "open lt type" TBool (OEB.optimizedType ltResult)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF ltResult))
  eqResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Eq (AVar xName) (AInt 10)))
  expectEqual "open int equality expression" (APrim Eq (AVar xName) (AInt 10)) (OEB.optimizedANF eqResult)
  expectEqual "open int equality type" TBool (OEB.optimizedType eqResult)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF eqResult))

testEgglogBackendSubtractionConstFacts :: Either String ()
testEgglogBackendSubtractionConstFacts = do
  result <- assertEgglogPreservesSemantics "let x = 10 - 3 in x + 1" (anfInt 8)
  expectEqual "subtraction folds through int facts" (AAtom (AInt 8)) (OEB.optimizedANF result)

testEgglogBackendOpenSubtractionFragment :: Either String ()
testEgglogBackendOpenSubtractionFragment = do
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Sub (AVar xName) (AInt 0)))
  expectEqual "open subtraction by zero expression" (AAtom (AVar xName)) (OEB.optimizedANF result)
  expectEqual "open subtraction type" TInt (OEB.optimizedType result)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF result))

testEgglogBackendDivisionConstFacts :: Either String ()
testEgglogBackendDivisionConstFacts = do
  result <- assertEgglogPreservesSemantics "let x = 8 / 2 in x + 1" (anfInt 5)
  expectEqual "division folds through int facts" (AAtom (AInt 5)) (OEB.optimizedANF result)
  zeroNumerator <- assertEgglogPreservesSemantics "let x = 10 - 7 in 0 / x" (anfInt 0)
  expectEqual "zero divided by known nonzero folds safely" (AAtom (AInt 0)) (OEB.optimizedANF zeroNumerator)

testEgglogBackendOpenDivisionFragment :: Either String ()
testEgglogBackendOpenDivisionFragment = do
  divResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Div (AVar xName) (AInt 2)))
  expectEqual "open division expression" (APrim Div (AVar xName) (AInt 2)) (OEB.optimizedANF divResult)
  expectEqual "open division type" TInt (OEB.optimizedType divResult)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF divResult))
  divOneResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Div (AVar xName) (AInt 1)))
  expectEqual "open division by one expression" (AAtom (AVar xName)) (OEB.optimizedANF divOneResult)

testEgglogBackendStrictSafeBooleans :: Either String ()
testEgglogBackendStrictSafeBooleans = do
  eqTrue <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Eq (AVar xName) (ABool True)))
  expectEqual "bool equality with true preserves the bool expression" (AAtom (AVar xName)) (OEB.optimizedANF eqTrue)
  expectEqual "bool equality with true type" TBool (OEB.optimizedType eqTrue)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF eqTrue))
  ifTrueFalse <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (AIf (AVar xName) (AAtom (ABool True)) (AAtom (ABool False))))
  expectEqual "boolean if true false preserves the condition" (AAtom (AVar xName)) (OEB.optimizedANF ifTrueFalse)
  zeroComparison <- assertEgglogPreservesSemantics "let x = 2 - 2 in if x == 0 then 10 else 20" (anfInt 10)
  expectEqual "zero-info equality feeds bool facts" (AAtom (AInt 10)) (OEB.optimizedANF zeroComparison)

testEgglogBackendPreservesStrictRuntimeErrors :: Either String ()
testEgglogBackendPreservesStrictRuntimeErrors = do
  let dName = mkName "d"
      cName = mkName "c"
      bName = mkName "b"
      erroringDiv = APrim Div (AInt 8) (AInt 0)
      overflowingAdd = APrim Add (AInt maxHIntInteger) (AInt 1)
  assertRuntimePreserved "multiplication by zero" (ALet xName (APrim Div (AInt 8) (AInt 0)) (APrim Mul (AVar xName) (AInt 0)))
  assertRuntimePreservedNotExpression "overflowing expression times zero" (AAtom (AInt 0)) (ALet xName overflowingAdd (APrim Mul (AVar xName) (AInt 0)))
  assertRuntimePreservedNotExpression "zero times division by zero" (AAtom (AInt 0)) (ALet xName (APrim Div (AInt 1) (AInt 0)) (APrim Mul (AInt 0) (AVar xName)))
  assertRuntimePreserved "integer equality with itself" (ALet xName (APrim Div (AInt 8) (AInt 0)) (APrim Eq (AVar xName) (AVar xName)))
  assertRuntimePreserved "integer less-than with itself" (ALet xName (APrim Div (AInt 8) (AInt 0)) (APrim Lt (AVar xName) (AVar xName)))
  assertRuntimePreserved "dead division-by-zero let" (ALet xName (APrim Div (AInt 5) (AInt 0)) (AAtom (ABool False)))
  assertRuntimePreservedNotExpression "same branch if with erroring condition" (AAtom (AInt 5)) (ALet dName (APrim Div (AInt 1) (AInt 0)) (ALet cName (APrim Eq (AVar dName) (AInt 0)) (AIf (AVar cName) (AAtom (AInt 5)) (AAtom (AInt 5)))))
  assertRuntimePreserved "same int if branches" (ALet dName erroringDiv (ALet cName (APrim Lt (AInt 0) (AVar dName)) (AIf (AVar cName) (AAtom (AInt 1)) (AAtom (AInt 1)))))
  assertRuntimePreserved "boolean equality with itself" (ALet dName erroringDiv (ALet bName (APrim Lt (AInt 0) (AVar dName)) (APrim Eq (AVar bName) (AVar bName))))
 where
  assertRuntimePreserved label expression = do
    result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig expression)
    expectEqual (label <> " runtime behavior") (evalANF expression) (evalANF (OEB.optimizedANF result))
  assertRuntimePreservedNotExpression label forbidden expression = do
    assertRuntimePreserved label expression
    result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig expression)
    assertBool (label <> " was not rewritten to " <> show forbidden) (OEB.optimizedANF result /= forbidden)

testEgglogDoesNotFoldOverflowingInt :: Either String ()
testEgglogDoesNotFoldOverflowingInt = do
  let expression = APrim Add (AInt maxHIntInteger) (AInt 1)
  (encoded, run) <- runEncodedANF expression
  root <- canonicalRoot encoded run
  found <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [root] (OEB.encodedRunDatabase run))
  case found of
    Just (EV.VConstInt (EV.KnownInt n)) ->
      Left ("overflowing add derived false KnownInt " <> show (hintToInteger n))
    _ ->
      Right ()
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig expression)
  expectEqual "overflowing add is not materialized as a constant" expression (OEB.optimizedANF result)
  let subExpression = APrim Sub (AInt minHIntInteger) (AInt 1)
  (subEncoded, subRun) <- runEncodedANF subExpression
  subRoot <- canonicalRoot subEncoded subRun
  subFound <- egg (EDB.lookupFunction (OES.iConstFn OES.symbols) [subRoot] (OEB.encodedRunDatabase subRun))
  case subFound of
    Just (EV.VConstInt (EV.KnownInt n)) ->
      Left ("overflowing sub derived false KnownInt " <> show (hintToInteger n))
    _ ->
      Right ()
  subResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig subExpression)
  expectEqual "overflowing sub is not materialized as a constant" subExpression (OEB.optimizedANF subResult)
  let strictSub =
        ALet
          xName
          subExpression
          (APrim Sub (AVar xName) (AInt 0))
  strictResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig strictSub)
  expectEqual "subtraction identity preserves the original runtime error" (evalANF strictSub) (evalANF (OEB.optimizedANF strictResult))
  case OEB.optimizedANF strictResult of
    ALet {} -> Right ()
    other -> Left ("subtraction identity dropped strict overflow dependency: " <> show other)
  let divByZero = APrim Div (AInt 8) (AInt 0)
  divByZeroResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig divByZero)
  expectEqual "division by zero is not materialized as a constant" divByZero (OEB.optimizedANF divByZeroResult)
  expectEqual "division by zero runtime error is preserved" (evalANF divByZero) (evalANF (OEB.optimizedANF divByZeroResult))
  let divOverflow = APrim Div (AInt minHIntInteger) (AInt (-1))
  divOverflowResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig divOverflow)
  expectEqual "overflowing division is not materialized as a constant" divOverflow (OEB.optimizedANF divOverflowResult)
  expectEqual "overflowing division runtime error is preserved" (evalANF divOverflow) (evalANF (OEB.optimizedANF divOverflowResult))
  let strictDiv =
        ALet
          xName
          divByZero
          (APrim Div (AVar xName) (AInt 1))
  strictDivResult <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig strictDiv)
  expectEqual "division identity preserves strict division-by-zero dependency" (evalANF strictDiv) (evalANF (OEB.optimizedANF strictDivResult))
  case OEB.optimizedANF strictDivResult of
    ALet {} -> Right ()
    other -> Left ("division identity dropped strict runtime-error dependency: " <> show other)

testEgglogBackendOpenFreeVariableFragment :: Either String ()
testEgglogBackendOpenFreeVariableFragment = do
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (APrim Mul (AVar xName) (AInt 1)))
  expectEqual "optimized open expression" (AAtom (AVar xName)) (OEB.optimizedANF result)
  expectEqual "open optimized type" TInt (OEB.optimizedType result)
  mapLeft (showText . renderANFValidationError) (validateANFWithFreeVars (Set.singleton xName) (OEB.optimizedANF result))

testEgglogBackendUnsupportedApplication :: Either String ()
testEgglogBackendUnsupportedApplication =
  case OEB.optimizeANFWithEgglog (AApp (AInt 1) (AInt 2)) of
    Left (OEB.UnsupportedApplication _ _) -> Right ()
    other -> Left ("expected unsupported application error, got " <> show other)

testEgglogBackendDeterministic :: Either String ()
testEgglogBackendDeterministic = do
  parsed <- parseExpr "let x = 2 + 3 in x * 4"
  first <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (toANF parsed))
  second <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (toANF parsed))
  expectEqual "deterministic optimized ANF" (OEB.optimizedANF first) (OEB.optimizedANF second)

testEgglogBackendExtractionProvenance :: Either String ()
testEgglogBackendExtractionProvenance = do
  parsed <- parseExpr "let x = 2 + 3 in x * 4"
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig (toANF parsed))
  let provenance = OEB.provenanceTrace result
  assertBool
    "backend provenance should render the extracted root term"
    (any ("extracted root:" `Text.isPrefixOf`) provenance)
  assertBool
    "backend provenance should render optimized ANF"
    (any ("optimized ANF:" `Text.isPrefixOf`) provenance)
  assertBool
    "backend provenance should include rule-action trace lines"
    (any ("debug: rule " `Text.isPrefixOf`) provenance)

testEgglogBackendBooleanBranchPreservation :: Either String ()
testEgglogBackendBooleanBranchPreservation =
  assertEgglogPreservesSemantics "let b = if true then false else true in if b then 1 else 2" (anfInt 2) >> Right ()

testEgglogTryOptimizeUnsupportedLambda :: Either String ()
testEgglogTryOptimizeUnsupportedLambda =
  case OEB.tryOptimizeWithEgglog EEV.defaultRunConfig (ALam xName TInt (AAtom (AVar xName))) of
    OEB.EgglogUnsupported OEB.UnsupportedLambda {} -> Right ()
    other -> Left ("expected unsupported lambda attempt, got " <> show other)

testOrdinaryPipelineHandlesUnsupportedLambda :: Either String ()
testOrdinaryPipelineHandlesUnsupportedLambda = do
  parsed <- parseExpr "let inc = \\x : Int -> x + 1 in inc 41"
  value <- mapLeft (showText . renderRuntimeError) (eval parsed)
  expectEqual "ordinary pipeline value" (sourceInt 42) value
  case OEB.tryOptimizeWithEgglog EEV.defaultRunConfig (toANF parsed) of
    OEB.EgglogUnsupported {} -> Right ()
    other -> Left ("expected Egglog backend to be unsupported, got " <> show other)

testEgglogAgreesWithSimplifierSemantically :: Either String ()
testEgglogAgreesWithSimplifierSemantically =
  firstFailurePure check supportedEgglogSources
 where
  check source = do
    parsed <- parseExpr source
    let original = toANF parsed
    simplified <- mapLeft show (simplifyFixpoint original)
    egglog <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig original)
    simplifiedValue <- mapLeft (showText . renderRuntimeError) (evalANF (simplifiedANF simplified))
    egglogValue <- mapLeft (showText . renderRuntimeError) (evalANF (OEB.optimizedANF egglog))
    expectEqual ("semantic agreement for " <> Text.unpack source) simplifiedValue egglogValue

testLLVMBackendValidArithmetic :: Either String ()
testLLVMBackendValidArithmetic = do
  parsed <- parseExpr "let x = 3 in let y = x + 4 in y * 2"
  backend <- mapLeft (showText . BL.renderBackendLowerError) (BL.lowerANFToBackend (toANF parsed))
  expectEqual "backend root type" B.BI64 (B.backendRootType backend)
  mapLeft (showText . BV.renderBackendValidationError) (BV.validateBackendProgram backend)

testLLVMBackendValidDivision :: Either String ()
testLLVMBackendValidDivision = do
  parsed <- parseExpr "let x = 20 in let y = 4 in x / y"
  backend <- mapLeft (showText . BL.renderBackendLowerError) (BL.lowerANFToBackend (toANF parsed))
  expectEqual "backend division root type" B.BI64 (B.backendRootType backend)
  mapLeft (showText . BV.renderBackendValidationError) (BV.validateBackendProgram backend)

testLLVMBackendValidationRejectsUnbound :: Either String ()
testLLVMBackendValidationRejectsUnbound =
  let program =
        B.BackendProgram
          { B.backendRootType = B.BI64
          , B.backendRoot = B.BEAtom B.BI64 (B.BVar xName)
          , B.backendFunctions = []
          , B.backendProvenance = []
          }
   in case BV.validateBackendProgram program of
        Left (BV.BackendUnboundVariable name)
          | name == xName -> Right ()
        other -> Left ("expected backend unbound variable validation error, got " <> show other)

testLLVMBackendValidationRejectsBadIf :: Either String ()
testLLVMBackendValidationRejectsBadIf =
  let program =
        B.BackendProgram
          { B.backendRootType = B.BI64
          , B.backendRoot =
              B.BEIf
                B.BI64
                (backendInt 1)
                (B.BEAtom B.BI64 (backendInt 10))
                (B.BEAtom B.BI64 (backendInt 20))
          , B.backendFunctions = []
          , B.backendProvenance = []
          }
   in case BV.validateBackendProgram program of
        Left (BV.BackendIfConditionTypeMismatch B.BI64) -> Right ()
        other -> Left ("expected backend if condition validation error, got " <> show other)

testLLVMBackendValidationRejectsBoolDivision :: Either String ()
testLLVMBackendValidationRejectsBoolDivision =
  let program =
        B.BackendProgram
          { B.backendRootType = B.BI64
          , B.backendRoot =
              B.BEPrim
                B.BI64
                B.BPDiv
                (B.BBool True)
                (backendInt 1)
          , B.backendFunctions = []
          , B.backendProvenance = []
          }
   in case BV.validateBackendProgram program of
        Left (BV.BackendAtomTypeMismatch B.BI64 B.BI1 (B.BBool True)) -> Right ()
        other -> Left ("expected backend Bool division validation error, got " <> show other)

testLLVMLowerRejectsLambda :: Either String ()
testLLVMLowerRejectsLambda =
  case BL.lowerANFToBackend (ALam xName TInt (AAtom (AVar xName))) of
    Left (BL.BackendUnsupportedLambda name TInt)
      | name == xName -> Right ()
    other -> Left ("expected LLVM backend to reject lambda, got " <> show other)

testLLVMLowerRejectsApplication :: Either String ()
testLLVMLowerRejectsApplication =
  case BL.lowerANFToBackend (AApp (AInt 1) (AInt 2)) of
    Left (BL.BackendUnsupportedApplication _ _) -> Right ()
    other -> Left ("expected LLVM backend to reject application, got " <> show other)

testLLVMLowerRejectsOpenProgram :: Either String ()
testLLVMLowerRejectsOpenProgram =
  case BL.lowerANFToBackend (APrim Add (AVar xName) (AInt 1)) of
    Left (BL.BackendInvalidANF (UnboundVariable name))
      | name == xName -> Right ()
    other -> Left ("expected LLVM backend to reject open ANF, got " <> show other)

testLLVMLoweringCheckedDivision :: Either String ()
testLLVMLoweringCheckedDivision = do
  result <- compileLLVMNoEgglog "let x = 20 in let y = 4 in x / y"
  let llvmText = BC.llvmText result
      beforeSdiv = fst (Text.breakOn "sdiv i64" llvmText)
  assertBool "division lowering checks zero divisor" ("icmp eq i64 4, 0" `Text.isInfixOf` llvmText)
  assertBool "division lowering checks minBound numerator" ("icmp eq i64 20, -9223372036854775808" `Text.isInfixOf` llvmText)
  assertBool "division lowering checks -1 denominator" ("icmp eq i64 4, -1" `Text.isInfixOf` llvmText)
  assertBool "division lowering emits sdiv" ("sdiv i64 20, 4" `Text.isInfixOf` llvmText)
  assertBool "division lowering calls abort for runtime errors" ("@abort()" `Text.isInfixOf` llvmText)
  assertBool "division checks precede sdiv" ("div_zero_abort" `Text.isInfixOf` beforeSdiv && "div_overflow_abort" `Text.isInfixOf` beforeSdiv)

testLLVMLoweringNestedIf :: Either String ()
testLLVMLoweringNestedIf = do
  first <- compileLLVMTextNoEgglog "let x = 10 in if x < 5 then 1 else if x < 20 then 2 else 3"
  second <- compileLLVMTextNoEgglog "let x = 10 in if x < 5 then 1 else if x < 20 then 2 else 3"
  expectEqualText "deterministic LLVM output" first second
  assertBool "nested if emits phi" ("phi i64" `Text.isInfixOf` first)
  assertBool "nested if emits branch" ("br i1" `Text.isInfixOf` first)

testLLVMValidatorRejectsDuplicateRegisters :: Either String ()
testLLVMValidatorRejectsDuplicateRegisters =
  let reg = LIR.Register "dup"
      llvmModule =
        LIR.LLVMModule
          { LIR.moduleComments = []
          , LIR.moduleGlobals = []
          , LIR.moduleDeclarations = []
          , LIR.moduleFunctions =
              [ LIR.LLVMFunction
                  { LIR.functionName = "bad"
                  , LIR.functionReturnType = LIR.LI64
                  , LIR.functionParams = []
                  , LIR.functionBlocks =
                      [ LIR.LLVMBlock
                          { LIR.blockLabel = "entry"
                          , LIR.blockInstructions =
                              [ LIR.IAdd reg LIR.LI64 (LIR.OConstInt LIR.LI64 1) (LIR.OConstInt LIR.LI64 2)
                              , LIR.IMul reg LIR.LI64 (LIR.OConstInt LIR.LI64 3) (LIR.OConstInt LIR.LI64 4)
                              ]
                          , LIR.blockTerminator = LIR.TRet LIR.LI64 (LIR.OLocal LIR.LI64 reg)
                          }
                      ]
                  }
              ]
          }
   in case LV.validateLLVMModule llvmModule of
        Left (LV.DuplicateLLVMRegister "bad" duplicate)
          | duplicate == reg -> Right ()
        other -> Left ("expected duplicate LLVM register validation error, got " <> show other)

testLLVMValidatorRejectsMissingBlock :: Either String ()
testLLVMValidatorRejectsMissingBlock =
  let llvmModule =
        LIR.LLVMModule
          { LIR.moduleComments = []
          , LIR.moduleGlobals = []
          , LIR.moduleDeclarations = []
          , LIR.moduleFunctions =
              [ LIR.LLVMFunction
                  { LIR.functionName = "bad"
                  , LIR.functionReturnType = LIR.LI64
                  , LIR.functionParams = []
                  , LIR.functionBlocks =
                      [ LIR.LLVMBlock
                          { LIR.blockLabel = "entry"
                          , LIR.blockInstructions = []
                          , LIR.blockTerminator = LIR.TBr "missing"
                          }
                      ]
                  }
              ]
          }
   in case LV.validateLLVMModule llvmModule of
        Left (LV.UnknownLLVMBlock "bad" "missing") -> Right ()
        other -> Left ("expected missing LLVM block validation error, got " <> show other)

testLLVMCompileEgglogFallback :: Either String ()
testLLVMCompileEgglogFallback = do
  result <- compileLLVMDefault "let inc = \\x : Int -> x + 1 in inc 41"
  case BC.llvmOptimizationStatus result of
    BC.LLVMOptimizationUnsupported {} -> Right ()
    other -> Left ("expected Egglog unsupported fallback, got " <> show other)
  assertBool "LLVM text reports Egglog fallback" ("egglog: unsupported; using unoptimized ANF" `Text.isInfixOf` BC.llvmText result)

testLLVMCompileUsesEgglog :: Either String ()
testLLVMCompileUsesEgglog = do
  result <- compileLLVMDefault "let x = 3 in let y = x + 4 in y * 2"
  case BC.llvmOptimizationStatus result of
    BC.LLVMOptimizationApplied {} -> Right ()
    other -> Left ("expected Egglog optimization, got " <> show other)
  assertBool "optimized LLVM returns constant" ("ret i64 14" `Text.isInfixOf` BC.llvmText result)

testLLVMCompileTopLevelFunctions :: Either String ()
testLLVMCompileTopLevelFunctions = do
  llvmText <- compileLLVMTextNoEgglog topLevelSource
  assertBool
    "LLVM defines inc with an Int parameter"
    ("define i64 @hegglog_fun_inc(i64 %arg_x)" `Text.isInfixOf` llvmText)
  assertBool
    "LLVM calls inc directly"
    ("call i64 @hegglog_fun_inc(i64 20)" `Text.isInfixOf` llvmText)
  assertBool
    "LLVM calls double directly"
    ("call i64 @hegglog_fun_double(i64 %call0)" `Text.isInfixOf` llvmText)

testLLVMCompileRejectsTopLevelFunctionValue :: Either String ()
testLLVMCompileRejectsTopLevelFunctionValue =
  case
    BC.compileToLLVM
      BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False}
      "<test>"
      "def inc(x : Int) : Int = x + 1; inc" of
    Left (BC.LLVMCompileUnsupportedSource _ message) ->
      assertBool
        "top-level function value is rejected before ANF validation"
        ("does not support using top-level function inc as a value" `Text.isInfixOf` message)
    other -> Left ("expected top-level function value rejection, got " <> show other)

testLLVMCompileEscapesTopLevelNames :: Either String ()
testLLVMCompileEscapesTopLevelNames = do
  llvmText <- compileLLVMTextNoEgglog "def f'(x : Int) : Int = x; def f_(x : Int) : Int = x + 1; f' 42"
  assertBool
    "apostrophe is escaped distinctly"
    ("define i64 @hegglog_fun_f_x27_(i64 %arg_x)" `Text.isInfixOf` llvmText)
  assertBool
    "underscore is escaped distinctly"
    ("define i64 @hegglog_fun_f_u(i64 %arg_x)" `Text.isInfixOf` llvmText)
  assertBool
    "call targets escaped apostrophe function"
    ("call i64 @hegglog_fun_f_x27_(i64 42)" `Text.isInfixOf` llvmText)

testLLVMCompileLiftedLetLambda :: Either String ()
testLLVMCompileLiftedLetLambda = do
  llvmText <- compileLLVMTextNoEgglog "let add = \\x : Int -> \\y : Int -> x + y in add 3 4"
  assertBool
    "curried lambda chain becomes one first-order LLVM function"
    ("define i64 @hegglog_fun__ulift_uadd_u0(i64 %arg_x, i64 %arg_y)" `Text.isInfixOf` llvmText)
  assertBool
    "curried lambda call lowers directly"
    ("call i64 @hegglog_fun__ulift_uadd_u0(i64 3, i64 4)" `Text.isInfixOf` llvmText)

testLLVMCompileImmediateLambda :: Either String ()
testLLVMCompileImmediateLambda = do
  llvmText <- compileLLVMTextNoEgglog "(\\x : Int -> x * 2) 21"
  assertBool
    "anonymous lambda gets deterministic lifted function"
    ("define i64 @hegglog_fun__ulift_ulambda_u0(i64 %arg_x)" `Text.isInfixOf` llvmText)
  assertBool
    "anonymous lambda call lowers directly"
    ("call i64 @hegglog_fun__ulift_ulambda_u0(i64 21)" `Text.isInfixOf` llvmText)

testLLVMCompileCapturingLambda :: Either String ()
testLLVMCompileCapturingLambda = do
  llvmText <- compileLLVMTextNoEgglog "let x = 1 in let f = \\y : Int -> x + y in f 2"
  assertBool
    "capturing lambda gets closure code function"
    ("define i64 @hegglog_fun__uclosure_uf_u0(ptr %arg__uenv0, i64 %arg_y)" `Text.isInfixOf` llvmText)
  assertBool
    "closure allocation uses process-lifetime allocator"
    ("call ptr @hegglog_alloc_process_lifetime(i64 16)" `Text.isInfixOf` llvmText)
  assertBool
    "strict LLVM defines process-lifetime allocator"
    ("define ptr @hegglog_alloc_process_lifetime(i64 %size)" `Text.isInfixOf` llvmText)
  expectEqual "strict LLVM direct malloc calls stay inside allocator helper" 1 (countTextOccurrences "call ptr @malloc" llvmText)
  assertBool
    "closure stores code pointer"
    ("store ptr @hegglog_fun__uclosure_uf_u0" `Text.isInfixOf` llvmText)
  assertBool
    "closure call dispatches through loaded code pointer"
    ("call i64 %closure_code" `Text.isInfixOf` llvmText)

testLLVMCompileInferredCapturingLambda :: Either String ()
testLLVMCompileInferredCapturingLambda = do
  llvmText <- compileLLVMTextNoEgglog "let x = 1 in let f = \\y -> x + y in f 2"
  assertBool
    "inferred capturing lambda gets typed closure code function"
    ("define i64 @hegglog_fun__uclosure_uf_u0(ptr %arg__uenv0, i64 %arg_y)" `Text.isInfixOf` llvmText)
  assertBool
    "inferred closure call dispatches through loaded code pointer"
    ("call i64 %closure_code" `Text.isInfixOf` llvmText)

testNativeBuildToolchainMissing :: IO (Either String ())
testNativeBuildToolchainMissing = do
  result <-
    LLVMTools.buildNativeExecutable
      (LLVMTools.LLVMTools Nothing Nothing Nothing)
      "define i64 @main() {\nentry:\n  ret i64 0\n}\n"
      ".context/native-tests/missing-toolchain"
  pure $
    case result of
      LLVMTools.NativeBuildToolchainMissing message ->
        assertBool "missing clang reports toolchain status" ("clang unavailable" `Text.isInfixOf` Text.pack message)
      other ->
        Left ("expected missing native toolchain, got " <> show other)

testNativeExecutionMatchesInterpreter :: IO (Either String ())
testNativeExecutionMatchesInterpreter = do
  tools <- LLVMTools.findLLVMTools
  case LLVMTools.llvmClang tools of
    Nothing ->
      pure (Right ())
    Just {} -> do
      createDirectoryIfMissing True ".context/native-tests"
      firstFailureIO (check tools) nativeExecutionExamples
 where
  check tools nativeExample = do
    source <- Text.IO.readFile (nativeExamplePath nativeExample)
    let options =
          BC.defaultCompileLLVMOptions
            { BC.compileUseEgglog = nativeExampleUseEgglog nativeExample
            }
    case BC.compileToLLVM options (nativeExamplePath nativeExample) source of
      Left err ->
        pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
      Right result -> do
        let outputPath = ".context/native-tests/" <> nativeExampleName nativeExample
        buildResult <- LLVMTools.buildNativeExecutable tools (BC.llvmText result) outputPath
        runBuiltNative outputPath buildResult $ \runResult ->
          case runResult of
            LLVMTools.NativeRunSucceeded stdoutText ->
              expectEqual ("native stdout for " <> nativeExamplePath nativeExample) (nativeExampleStdout nativeExample) stdoutText
            LLVMTools.NativeRunFailed code stdoutText stderrText ->
              Left ("native execution failed for " <> outputPath <> " with " <> show code <> "\nstdout:\n" <> stdoutText <> "\nstderr:\n" <> stderrText)
            LLVMTools.NativeRunIOError message ->
              Left ("native execution I/O error for " <> outputPath <> ": " <> message)

testNativeRuntimeErrorExecutable :: IO (Either String ())
testNativeRuntimeErrorExecutable = do
  tools <- LLVMTools.findLLVMTools
  case LLVMTools.llvmClang tools of
    Nothing ->
      pure (Right ())
    Just {} -> do
      createDirectoryIfMissing True ".context/native-tests"
      source <- Text.IO.readFile "examples/llvm/division-by-zero.hg"
      case expectedInterpreterDivisionError "native-by-zero" ExpectDivisionByZero source of
        Left err ->
          pure (Left err)
        Right () ->
          case
            BC.compileToLLVM
              BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False}
              "examples/llvm/division-by-zero.hg"
              source of
            Left err ->
              pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
            Right result -> do
              let outputPath = ".context/native-tests/division-by-zero"
              buildResult <- LLVMTools.buildNativeExecutable tools (BC.llvmText result) outputPath
              runBuiltNative outputPath buildResult $ \runResult ->
                case runResult of
                  LLVMTools.NativeRunSucceeded stdoutText ->
                    Left ("expected native division by zero to fail, got stdout:\n" <> stdoutText)
                  LLVMTools.NativeRunFailed {} ->
                    Right ()
                  LLVMTools.NativeRunIOError message ->
                    Left ("native execution I/O error for " <> outputPath <> ": " <> message)

runBuiltNative :: FilePath -> LLVMTools.NativeBuildResult -> (LLVMTools.NativeRunResult -> Either String ()) -> IO (Either String ())
runBuiltNative outputPath buildResult checkRun =
  case buildResult of
    LLVMTools.NativeBuildSucceeded ->
      checkRun <$> LLVMTools.runNativeExecutable outputPath
    LLVMTools.NativeBuildToolchainMissing {} ->
      pure (Right ())
    LLVMTools.NativeBuildFailed clangPath args code stdoutText stderrText ->
      pure $
        Left
          ( "native build failed with "
              <> show code
              <> "\ncommand: "
              <> unwords (clangPath : args)
              <> "\nstdout:\n"
              <> stdoutText
              <> "\nstderr:\n"
              <> stderrText
          )
    LLVMTools.NativeBuildIOError message ->
      pure (Left ("native build I/O error: " <> message))

testLLVMOverflowAborts :: IO (Either String ())
testLLVMOverflowAborts = do
  tools <- LLVMTools.findLLVMTools
  firstFailureIO (check tools) llvmOverflowCases
 where
  check tools overflowCase = do
    let source = overflowSource overflowCase
        path = "<llvm-overflow-" <> Text.unpack (overflowName overflowCase) <> ">"
    case expectedInterpreterOverflow path (overflowOperator overflowCase) source of
      Left err ->
        pure (Left err)
      Right () ->
        case
          BC.compileToLLVM
            BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False}
            path
            source of
          Left err ->
            pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
          Right result -> do
            let llvmText = BC.llvmText result
            runResult <- LLVMTools.runLLVMText tools llvmText
            pure $
              assertBool
                ("overflow lowering uses expected intrinsic for " <> Text.unpack (overflowName overflowCase))
                (overflowIntrinsic overflowCase `Text.isInfixOf` llvmText)
                *> assertBool
                  ("overflow lowering calls abort for " <> Text.unpack (overflowName overflowCase))
                  ("@abort()" `Text.isInfixOf` llvmText)
                *> case runResult of
                  LLVMTools.LLVMRunSkipped {} ->
                    Right ()
                  LLVMTools.LLVMRunFailed _ _ ->
                    Right ()
                  LLVMTools.LLVMRunSucceeded stdoutText ->
                    Left ("expected LLVM overflow execution to fail for " <> path <> ", got stdout:\n" <> stdoutText)

expectedInterpreterOverflow :: FilePath -> BinOp -> Text -> Either String ()
expectedInterpreterOverflow path expectedOp source = do
  parsed <- parseExprAt path source
  case eval parsed of
    Left (RuntimeIntError (IntOverflow actualOp _ _))
      | actualOp == expectedOp -> Right ()
    Left err ->
      Left ("expected interpreter checked Int overflow for " <> path <> ", got " <> Text.unpack (renderRuntimeError err))
    Right value ->
      Left ("expected interpreter checked Int overflow for " <> path <> ", got value " <> Text.unpack (renderValue value))

testLLVMDivisionExecution :: IO (Either String ())
testLLVMDivisionExecution = do
  tools <- LLVMTools.findLLVMTools
  successResult <- runDivisionSuccess tools
  case successResult of
    Left err -> pure (Left err)
    Right () -> firstFailureIO (checkError tools) llvmDivisionErrorCases
 where
  runDivisionSuccess tools = do
    source <- Text.IO.readFile "examples/llvm/division.hg"
    case BC.compileToLLVM BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False} "examples/llvm/division.hg" source of
      Left err ->
        pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
      Right result -> do
        assemblyResult <- LLVMTools.validateLLVMText tools (BC.llvmText result)
        runResult <- LLVMTools.runLLVMText tools (BC.llvmText result)
        pure $
          checkLLVMAssemblyResult "examples/llvm/division.hg" assemblyResult
            *> assertBool "division lowering emits sdiv without Egglog" ("sdiv i64" `Text.isInfixOf` BC.llvmText result)
            *> case runResult of
              LLVMTools.LLVMRunSkipped {} -> Right ()
              LLVMTools.LLVMRunFailed stdoutText stderrText ->
                Left ("LLVM division execution failed\nstdout:\n" <> stdoutText <> "\nstderr:\n" <> stderrText)
              LLVMTools.LLVMRunSucceeded stdoutText ->
                expectEqual "LLVM division stdout" "5\n" stdoutText

  checkError tools (name, source, expected) = do
    case expectedInterpreterDivisionError name expected source of
      Left err ->
        pure (Left err)
      Right () ->
        case BC.compileToLLVM BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False} ("<llvm-division-" <> Text.unpack name <> ">") source of
          Left err ->
            pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
          Right result -> do
            assemblyResult <- LLVMTools.validateLLVMText tools (BC.llvmText result)
            runResult <- LLVMTools.runLLVMText tools (BC.llvmText result)
            pure $
              checkLLVMAssemblyResult ("<llvm-division-" <> Text.unpack name <> ">") assemblyResult
                *> assertBool
                ("division error lowering emits sdiv for " <> Text.unpack name)
                ("sdiv i64" `Text.isInfixOf` BC.llvmText result)
                *> assertBool
                  ("division error lowering calls abort for " <> Text.unpack name)
                  ("@abort()" `Text.isInfixOf` BC.llvmText result)
                *> case runResult of
                  LLVMTools.LLVMRunSkipped {} -> Right ()
                  LLVMTools.LLVMRunFailed _ _ -> Right ()
                  LLVMTools.LLVMRunSucceeded stdoutText ->
                    Left ("expected LLVM division " <> Text.unpack name <> " execution to fail, got stdout:\n" <> stdoutText)

data ExpectedDivisionError
  = ExpectDivisionByZero
  | ExpectDivisionOverflow
  deriving stock (Show, Eq, Ord)

llvmDivisionErrorCases :: [(Text, Text, ExpectedDivisionError)]
llvmDivisionErrorCases =
  [ ("by-zero", "1 / 0", ExpectDivisionByZero)
  , ("overflow", divisionOverflowSource, ExpectDivisionOverflow)
  ]

expectedInterpreterDivisionError :: Text -> ExpectedDivisionError -> Text -> Either String ()
expectedInterpreterDivisionError name expected source = do
  parsed <- parseExprAt ("<llvm-division-" <> Text.unpack name <> ">") source
  case (expected, eval parsed) of
    (ExpectDivisionByZero, Left DivisionByZero) -> Right ()
    (ExpectDivisionOverflow, Left (RuntimeIntError (IntOverflow Div _ _))) -> Right ()
    (_, Left err) ->
      Left ("expected interpreter division " <> Text.unpack name <> " error, got " <> Text.unpack (renderRuntimeError err))
    (_, Right value) ->
      Left ("expected interpreter division " <> Text.unpack name <> " error, got value " <> Text.unpack (renderValue value))

checkLLVMGolden :: FilePath -> FilePath -> IO (Either String ())
checkLLVMGolden sourcePath goldenPath = do
  source <- Text.IO.readFile sourcePath
  expected <- Text.IO.readFile goldenPath
  tools <- LLVMTools.findLLVMTools
  case
    mapLeft
      (showText . BC.renderCompileLLVMError)
      ( BC.compileToLLVM
          BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False}
          sourcePath
          source
      ) of
    Left err ->
      pure (Left err)
    Right result -> do
      assemblyResult <- LLVMTools.validateLLVMText tools (BC.llvmText result)
      pure $
        expectEqualText "LLVM golden output" expected (BC.llvmText result)
          *> checkLLVMAssemblyResult sourcePath assemblyResult

checkLLVMAssemblyResult :: FilePath -> LLVMTools.LLVMAssemblyResult -> Either String ()
checkLLVMAssemblyResult _ LLVMTools.LLVMAssemblySucceeded =
  Right ()
checkLLVMAssemblyResult _ (LLVMTools.LLVMAssemblySkipped _) =
  Right ()
checkLLVMAssemblyResult sourcePath (LLVMTools.LLVMAssemblyFailed stdoutText stderrText) =
  Left ("llvm-as rejected emitted LLVM for " <> sourcePath <> "\nstdout:\n" <> stdoutText <> "\nstderr:\n" <> stderrText)

testLLVMExecutionMatchesInterpreter :: IO (Either String ())
testLLVMExecutionMatchesInterpreter = do
  tools <- LLVMTools.findLLVMTools
  firstFailureIO (check tools) llvmExecutionExamples
 where
  check tools (path, expectedStdout) = do
    source <- Text.IO.readFile path
    case BC.compileToLLVM BC.defaultCompileLLVMOptions path source of
      Left err ->
        pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
      Right result -> do
        runResult <- LLVMTools.runLLVMText tools (BC.llvmText result)
        pure $
          case runResult of
            LLVMTools.LLVMRunSkipped {} ->
              Right ()
            LLVMTools.LLVMRunFailed stdoutText stderrText ->
              Left ("LLVM execution failed for " <> path <> "\nstdout:\n" <> stdoutText <> "\nstderr:\n" <> stderrText)
            LLVMTools.LLVMRunSucceeded stdoutText ->
              expectEqual ("LLVM stdout for " <> path) expectedStdout stdoutText

testLLVMDifferentialCorpus :: IO (Either String ())
testLLVMDifferentialCorpus = do
  tools <- LLVMTools.findLLVMTools
  firstFailureIO (check tools) (zip [(1 :: Int) ..] llvmDifferentialSources)
 where
  check tools (index, source) = do
    let path = "<llvm-diff-" <> show index <> ">"
    case expectedLLVMStdout path source of
      Left err ->
        pure (Left err)
      Right expectedStdout ->
        case BC.compileToLLVM BC.defaultCompileLLVMOptions path source of
          Left err ->
            pure (Left (Text.unpack (BC.renderCompileLLVMError err)))
          Right result -> do
            runResult <- LLVMTools.runLLVMText tools (BC.llvmText result)
            pure $
              case runResult of
                LLVMTools.LLVMRunSkipped {} ->
                  Right ()
                LLVMTools.LLVMRunFailed stdoutText stderrText ->
                  Left ("LLVM execution failed for " <> path <> "\nstdout:\n" <> stdoutText <> "\nstderr:\n" <> stderrText)
                LLVMTools.LLVMRunSucceeded stdoutText ->
                  expectEqual ("LLVM stdout for " <> path) expectedStdout stdoutText

expectedLLVMStdout :: FilePath -> Text -> Either String String
expectedLLVMStdout path source = do
  parsed <- parseExprAt path source
  value <- mapLeft (showText . renderRuntimeError) (eval parsed)
  case value of
    VInt n ->
      Right (show (hintToInteger n) <> "\n")
    VBool True ->
      Right "1\n"
    VBool False ->
      Right "0\n"
    VClosure {} ->
      Left "LLVM differential corpus only supports first-order root values"

compileLLVMDefault :: Text -> Either String BC.LLVMCompileResult
compileLLVMDefault source =
  mapLeft (showText . BC.renderCompileLLVMError) (BC.compileToLLVM BC.defaultCompileLLVMOptions "<test>" source)

compileLLVMNoEgglog :: Text -> Either String BC.LLVMCompileResult
compileLLVMNoEgglog source =
  mapLeft
    (showText . BC.renderCompileLLVMError)
    ( BC.compileToLLVM
        BC.defaultCompileLLVMOptions {BC.compileUseEgglog = False}
        "<test>"
        source
    )

compileLLVMTextNoEgglog :: Text -> Either String Text
compileLLVMTextNoEgglog source =
  BC.llvmText <$> compileLLVMNoEgglog source

assertEgglogPreservesSemantics :: Text -> ANFValue -> Either String OEB.EgglogOptimizationResult
assertEgglogPreservesSemantics source expectedValue = do
  parsed <- parseExpr source
  let original = toANF parsed
  originalValue <- mapLeft (showText . renderRuntimeError) (evalANF original)
  expectEqual "original value" expectedValue originalValue
  result <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.optimizeWithEgglog EEV.defaultRunConfig original)
  mapLeft (showText . renderANFValidationError) (validateANF (OEB.optimizedANF result))
  optimizedValue <- mapLeft (showText . renderRuntimeError) (evalANF (OEB.optimizedANF result))
  expectEqual "optimized value" expectedValue optimizedValue
  expectEqual "optimized type" (OEB.originalType result) (OEB.optimizedType result)
  assertBool
    "optimized cost should not exceed original cost after saturation"
    ( not (OEB.runSaturated (OEB.runStats result))
        || OEB.optimizedCost (OEB.extractionStats result) <= OEB.originalCost (OEB.extractionStats result)
    )
  pure result

egg :: Either EDB.EgglogError a -> Either String a
egg =
  mapLeft show

resolvedFor :: Text -> Either String RANF.ResolvedAExpr
resolvedFor source = do
  parsed <- parseExpr source
  resolved <- mapLeft show (RANF.resolveANF (toANF parsed))
  mapLeft show (RANF.validateResolvedANF resolved)
  pure resolved

encodeSource :: Text -> Either String OEB.EncodedProgram
encodeSource source = do
  parsed <- parseExpr source
  encodeSourceANF (toANF parsed)

encodeSourceANF :: AExpr -> Either String OEB.EncodedProgram
encodeSourceANF expression = do
  resolved <- mapLeft show (RANF.resolveANF expression)
  fragment <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.classifyEgglogFragment resolved)
  mapLeft (showText . OEB.renderEgglogBackendError) (OEB.encodeResolvedANF fragment)

runEncodedSource :: Text -> Either String (OEB.EncodedProgram, OEB.EncodedRun)
runEncodedSource source = do
  encoded <- encodeSource source
  run <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.runEgglogCompilerRules EEV.defaultRunConfig encoded)
  pure (encoded, run)

runEncodedANF :: AExpr -> Either String (OEB.EncodedProgram, OEB.EncodedRun)
runEncodedANF expression = do
  encoded <- encodeSourceANF expression
  run <- mapLeft (showText . OEB.renderEgglogBackendError) (OEB.runEgglogCompilerRules EEV.defaultRunConfig encoded)
  pure (encoded, run)

canonicalRoot :: OEB.EncodedProgram -> OEB.EncodedRun -> Either String EV.Value
canonicalRoot _ run =
  Right (EDB.canonicalValue (OEB.encodedRunDatabase run) (OEB.encodedRunRootValue run))

assertEquivalentToPattern :: OEB.EncodedProgram -> OEB.EncodedRun -> EP.Pattern -> Either String ()
assertEquivalentToPattern encoded run pattern = do
  root <- canonicalRoot encoded run
  expected <- lookupPatternValue (OEB.encodedRunDatabase run) pattern
  expectEqual
    "root equivalence"
    root
    (EDB.canonicalValue (OEB.encodedRunDatabase run) expected)

lookupPatternValue :: EDB.Database -> EP.Pattern -> Either String EV.Value
lookupPatternValue db = \case
  EP.PCall name args -> do
    values <- traverse literalValue args
    found <- egg (EDB.lookupFunction name values db)
    case found of
      Just value -> Right value
      Nothing -> Left ("missing encoded function value for " <> show name <> " " <> show values)
  other ->
    Left ("expected first-order function pattern, got " <> show other)
 where
  literalValue = \case
    EP.PValue value -> Right value
    other -> Left ("expected literal argument pattern, got " <> show other)

eggRun :: [ER.Rule] -> [ER.Action] -> [EF.FunctionDecl] -> Either String EEV.RunResult
eggRun rules initialActions decls =
  egg
    ( EEV.runProgram
        EEV.defaultRunConfig {EEV.maxIterations = 24}
        ER.Program
          { ER.programDecls = decls
          , ER.programInitialActions = initialActions
          , ER.programRules = rules
          }
    )

topValue :: EDB.Database -> ES.FunctionName -> [EP.Pattern] -> Either String EV.Value
topValue db name argPatterns = do
  (dbWithArgs, args) <- egg (foldPatternArgs db argPatterns)
  found <- egg (EDB.lookupFunction name args dbWithArgs)
  case found of
    Just value -> Right value
    Nothing -> Left ("missing top value for " <> show name)

foldPatternArgs :: EDB.Database -> [EP.Pattern] -> Either EDB.EgglogError (EDB.Database, [EV.Value])
foldPatternArgs db patterns =
  reverseValues <$> foldl step (Right (db, [])) patterns
 where
  step acc pattern = do
    (currentDb, values) <- acc
    (nextDb, value) <- EP.evalTerm currentDb EP.emptySubstitution pattern
    Right (nextDb, value : values)
  reverseValues (finalDb, values) =
    (finalDb, reverse values)

edgeToPathRule :: ER.Rule
edgeToPathRule =
  ER.Rule
    { ER.ruleName = fn "edge-to-path"
    , ER.rulePremises = [ER.QLookup edgeFn [intVar "x", intVar "y"] (EP.PValue EV.VUnit)]
    , ER.ruleActions = [ER.AAssert pathFn [intVar "x", intVar "y"]]
    }

transitivePathRule :: ER.Rule
transitivePathRule =
  ER.Rule
    { ER.ruleName = fn "transitive-path"
    , ER.rulePremises =
        [ ER.QLookup pathFn [intVar "x", intVar "y"] (EP.PValue EV.VUnit)
        , ER.QLookup edgeFn [intVar "y", intVar "z"] (EP.PValue EV.VUnit)
        ]
    , ER.ruleActions = [ER.AAssert pathFn [intVar "x", intVar "z"]]
    }

arithmeticRules :: [ER.Rule]
arithmeticRules =
  [ ER.rewrite (fn "add-comm") exprSort (EP.PCall addFn [exprVar "a", exprVar "b"]) (EP.PCall addFn [exprVar "b", exprVar "a"])
  , ER.rewrite (fn "mul-comm") exprSort (EP.PCall mulFn [exprVar "a", exprVar "b"]) (EP.PCall mulFn [exprVar "b", exprVar "a"])
  , ER.rewrite (fn "add-zero-right") exprSort (EP.PCall addFn [exprVar "a", numPattern 0]) (exprVar "a")
  , ER.rewrite (fn "add-zero-left") exprSort (EP.PCall addFn [numPattern 0, exprVar "a"]) (exprVar "a")
  , ER.rewrite (fn "mul-one-right") exprSort (EP.PCall mulFn [exprVar "a", numPattern 1]) (exprVar "a")
  , ER.rewrite (fn "mul-one-left") exprSort (EP.PCall mulFn [numPattern 1, exprVar "a"]) (exprVar "a")
  , ER.rewrite (fn "distribute") exprSort (EP.PCall mulFn [exprVar "a", EP.PCall addFn [exprVar "b", exprVar "c"]]) (EP.PCall addFn [EP.PCall mulFn [exprVar "a", exprVar "b"], EP.PCall mulFn [exprVar "a", exprVar "c"]])
  , constantFoldRule (fn "const-add") addFn EP.PAddInt
  , constantFoldRule (fn "const-mul") mulFn EP.PMulInt
  ]

constantFoldRule :: ES.FunctionName -> ES.FunctionName -> (EP.Pattern -> EP.Pattern -> EP.Pattern) -> ER.Rule
constantFoldRule ruleName op makeInt =
  ER.Rule
    { ER.ruleName = ruleName
    , ER.rulePremises = [ER.QMatch (EP.PCall op [EP.PCall numFn [intVar "i"], EP.PCall numFn [intVar "j"]]) (exprVar "out")]
    , ER.ruleActions = [ER.AUnion (exprVar "out") (EP.PCall numFn [makeInt (intVar "i") (intVar "j")])]
    }

arithmeticDecls :: [EF.FunctionDecl]
arithmeticDecls =
  [ numDecl
  , EF.FunctionDecl varFn [ES.SString] exprSort EF.DefaultFreshId EF.MergeUnion
  , EF.FunctionDecl addFn [exprSort, exprSort] exprSort EF.DefaultFreshId EF.MergeUnion
  , EF.FunctionDecl mulFn [exprSort, exprSort] exprSort EF.DefaultFreshId EF.MergeUnion
  ]

numDecl :: EF.FunctionDecl
numDecl =
  EF.FunctionDecl numFn [ES.SInt] exprSort EF.DefaultFreshId EF.MergeUnion

edgeRelDecl :: EF.FunctionDecl
edgeRelDecl =
  EF.relation edgeFn [ES.SInt, ES.SInt]

pathRelDecl :: EF.FunctionDecl
pathRelDecl =
  EF.relation pathFn [ES.SInt, ES.SInt]

intVar :: Text -> EP.Pattern
intVar name =
  EP.PVar (var name) ES.SInt

exprVar :: Text -> EP.Pattern
exprVar name =
  EP.PVar (var name) exprSort

numPattern :: Integer -> EP.Pattern
numPattern n =
  EP.PCall numFn [EP.PValue (EV.VInt n)]

varPattern :: Text -> EP.Pattern
varPattern name =
  EP.PCall varFn [EP.PValue (EV.VString name)]

eid :: Int -> EV.Value
eid n =
  EV.VId exprSortName (ES.Id n)

fn :: Text -> ES.FunctionName
fn =
  ES.FunctionName

var :: Text -> ES.VarName
var =
  ES.VarName

exprSortName :: ES.SortName
exprSortName =
  ES.SortName "Expr"

exprSort :: ES.Sort
exprSort =
  ES.SUser exprSortName

nodeSortName :: ES.SortName
nodeSortName =
  ES.SortName "Node"

edgeFn :: ES.FunctionName
edgeFn =
  fn "edge"

pathFn :: ES.FunctionName
pathFn =
  fn "path"

numFn :: ES.FunctionName
numFn =
  fn "Num"

varFn :: ES.FunctionName
varFn =
  fn "Var"

addFn :: ES.FunctionName
addFn =
  fn "Add"

mulFn :: ES.FunctionName
mulFn =
  fn "Mul"

firstFailurePure :: (a -> Either String ()) -> [a] -> Either String ()
firstFailurePure action = \case
  [] ->
    Right ()
  item : rest ->
    case action item of
      Left message -> Left message
      Right () -> firstFailurePure action rest

firstFailureIO :: (a -> IO (Either String ())) -> [a] -> IO (Either String ())
firstFailureIO action = \case
  [] ->
    pure (Right ())
  item : rest -> do
    result <- action item
    case result of
      Left message -> pure (Left message)
      Right () -> firstFailureIO action rest

checkGolden :: FilePath -> FilePath -> IO (Either String ())
checkGolden sourcePath goldenPath = do
  source <- Text.IO.readFile sourcePath
  expected <- Text.IO.readFile goldenPath
  pure $ do
    report <- mapLeft show (compileReport sourcePath source)
    expectEqualText "golden output" expected (renderGoldenReport report)

checkDiagnosticGolden :: FilePath -> FilePath -> IO (Either String ())
checkDiagnosticGolden sourcePath goldenPath = do
  source <- Text.IO.readFile sourcePath
  expected <- Text.IO.readFile goldenPath
  pure $
    case compileReport sourcePath source of
      Left err ->
        expectEqualText "diagnostic golden output" expected (renderCompileError err)
      Right report ->
        Left ("expected diagnostic failure, got report:\n" <> Text.unpack (renderGoldenReport report))

checkLLVMDiagnosticGolden :: Text -> FilePath -> IO (Either String ())
checkLLVMDiagnosticGolden source goldenPath = do
  expected <- Text.IO.readFile goldenPath
  pure $
    case BC.compileToLLVM BC.defaultCompileLLVMOptions "<llvm-diagnostic>" source of
      Left err ->
        expectEqualText "LLVM diagnostic golden output" (Text.stripEnd expected) (BC.renderCompileLLVMError err)
      Right result ->
        Left ("expected LLVM diagnostic failure, got LLVM:\n" <> Text.unpack (BC.llvmText result))

countTextOccurrences :: Text -> Text -> Int
countTextOccurrences needle haystack
  | Text.null needle = 0
  | otherwise = go haystack
 where
  go text =
    case Text.breakOn needle text of
      (_, rest)
        | Text.null rest -> 0
        | otherwise -> 1 + go (Text.drop (Text.length needle) rest)

checkProperty :: Testable prop => prop -> IO (Either String ())
checkProperty prop = do
  result <-
    quickCheckWithResult
      stdArgs
        { maxSuccess = 100
        , chatty = False
        }
      prop
  case result of
    Success {} ->
      pure (Right ())
    failure ->
      pure (Left (output failure))

propANFValidationAfterLowering :: ClosedExpr -> Property
propANFValidationAfterLowering (ClosedExpr expression) =
  counterexample (show expression) $
    validateANF (toANF expression) === Right ()

propEgglogSupportedSemanticPreservation :: SupportedANF -> Property
propEgglogSupportedSemanticPreservation (SupportedANF expression) =
  counterexample (show expression) $
    case RANF.resolveANF expression of
      Left err ->
        counterexample (show err) False
      Right resolved ->
        case OEB.classifyEgglogFragment resolved of
          Left err ->
            counterexample (Text.unpack (OEB.renderEgglogBackendError err)) False
          Right {} ->
            case OEB.optimizeWithEgglog EEV.defaultRunConfig expression of
              Left err ->
                counterexample (Text.unpack (OEB.renderEgglogBackendError err)) False
              Right result ->
                conjoin
                  [ RANF.validateResolvedANF resolved === Right ()
                  , validateANF (OEB.optimizedANF result) === Right ()
                  , OEB.optimizedType result === OEB.originalType result
                  , evalANF (OEB.optimizedANF result) === evalANF expression
                  , OEB.optimizeWithEgglog EEV.defaultRunConfig expression === Right result
                  ]

propHaskell2010InferenceValidPrograms :: Haskell2010InferenceProgram -> Property
propHaskell2010InferenceValidPrograms (Haskell2010InferenceProgram expectedType source) =
  counterexample (Text.unpack source) $
    case typecheckHaskell2010Raw source of
      Left err ->
        counterexample (Text.unpack (H2010Typecheck.renderTypecheckError err)) False
      Right coreModule ->
        validateGeneratedHaskell2010Core expectedType coreModule

propHaskell2010DictionaryInferencePrograms :: Haskell2010DictionaryInferenceProgram -> Property
propHaskell2010DictionaryInferencePrograms (Haskell2010DictionaryInferenceProgram source) =
  counterexample (Text.unpack source) $
    case typecheckHaskell2010Raw source of
      Left err ->
        counterexample (Text.unpack (H2010Typecheck.renderTypecheckError err)) False
      Right coreModule ->
        conjoin
          [ validateGeneratedHaskell2010Core Haskell2010PropBool coreModule
          , counterexample
              "generated custom class dictionary constructor was not emitted"
              (property (containsConstructorOccurrence "$MkSameDict" coreModule))
          ]

propHaskell2010InferenceRejectsInvalidPrograms :: Haskell2010InvalidInferenceProgram -> Property
propHaskell2010InferenceRejectsInvalidPrograms (Haskell2010InvalidInferenceProgram source) =
  counterexample (Text.unpack source) $
    case typecheckHaskell2010Raw source of
      Left err ->
        counterexample (Text.unpack (H2010Typecheck.renderTypecheckError err)) $
          property (isExpectedHaskell2010InferenceFailure err)
      Right coreModule ->
        counterexample ("invalid generated program typechecked:\n" <> show coreModule) False

validateGeneratedHaskell2010Core :: Haskell2010PropType -> H2010Core.CoreModule -> Property
validateGeneratedHaskell2010Core expectedType coreModule =
  conjoin
    [ case H2010CoreValidate.validateModule (H2010CoreValidate.moduleValidationEnv coreModule) coreModule of
        Left errors ->
          counterexample ("generated Core failed validation: " <> show errors) False
        Right () ->
          property True
    , case haskell2010MainBindingType coreModule of
        Left message ->
          counterexample message False
        Right actualType ->
          actualType === haskell2010PropCoreType expectedType
    ]

haskell2010MainBindingType :: H2010Core.CoreModule -> Either String H2010Core.CoreType
haskell2010MainBindingType coreModule =
  case [H2010Core.coreBinderType binder | bind <- H2010Core.coreModuleBinds coreModule, binder <- H2010Core.bindersOf bind, H2010Names.nameOcc (H2010Core.coreBinderName binder) == "main"] of
    [] ->
      Left "generated Core is missing a main binding"
    [ty] ->
      Right ty
    types ->
      Left ("generated Core has multiple main bindings: " <> show types)

isExpectedHaskell2010InferenceFailure :: H2010Typecheck.TypecheckError -> Bool
isExpectedHaskell2010InferenceFailure err =
  case haskell2010TypecheckErrorDetail err of
    H2010Typecheck.TypeMismatch {} -> True
    H2010Typecheck.OccursCheck {} -> True
    H2010Typecheck.UnsolvedClassConstraint {} -> True
    H2010Typecheck.AmbiguousTypeVariable {} -> True
    _ -> False

newtype ClosedExpr = ClosedExpr Expr
  deriving stock (Show)

newtype SupportedANF = SupportedANF AExpr
  deriving stock (Show)

data Haskell2010PropType
  = Haskell2010PropInt
  | Haskell2010PropBool
  deriving stock (Show, Eq)

data Haskell2010GeneratedExpr = Haskell2010GeneratedExpr
  { generatedHaskell2010ExprType :: Haskell2010PropType
  , generatedHaskell2010ExprText :: Text
  }
  deriving stock (Show, Eq)

data Haskell2010InferenceProgram = Haskell2010InferenceProgram Haskell2010PropType Text
  deriving stock (Show)

newtype Haskell2010DictionaryInferenceProgram = Haskell2010DictionaryInferenceProgram Text
  deriving stock (Show)

newtype Haskell2010InvalidInferenceProgram = Haskell2010InvalidInferenceProgram Text
  deriving stock (Show)

instance Arbitrary ClosedExpr where
  arbitrary =
    sized (fmap ClosedExpr . genClosedExpr)
  shrink (ClosedExpr expression) =
    ClosedExpr <$> shrinkClosedExpr expression

instance Arbitrary SupportedANF where
  arbitrary =
    sized $ \size -> do
      ty <- elements [TInt, TBool]
      SupportedANF <$> genSupportedANF ty (min 5 size) [] 0
  shrink _ =
    []

instance Arbitrary Haskell2010InferenceProgram where
  arbitrary =
    sized $ \size -> do
      ty <- elements [Haskell2010PropInt, Haskell2010PropBool]
      expression <- genHaskell2010Expr ty (min 6 size) [] 0
      pure (Haskell2010InferenceProgram ty (haskell2010InferenceProgramSource ty expression))
  shrink _ =
    []

instance Arbitrary Haskell2010DictionaryInferenceProgram where
  arbitrary =
    sized $ \size -> do
      ty <- elements [Haskell2010PropInt, Haskell2010PropBool]
      lhs <- genHaskell2010Expr ty (min 5 size) [] 0
      rhs <- genHaskell2010Expr ty (min 5 size) [] 100
      pure (Haskell2010DictionaryInferenceProgram (haskell2010DictionaryInferenceProgramSource lhs rhs))
  shrink _ =
    []

instance Arbitrary Haskell2010InvalidInferenceProgram where
  arbitrary =
    sized $ \size -> do
      expectedType <- elements [Haskell2010PropInt, Haskell2010PropBool]
      let actualType = oppositeHaskell2010PropType expectedType
      expression <- genHaskell2010Expr actualType (min 5 size) [] 0
      pure (Haskell2010InvalidInferenceProgram (haskell2010InvalidInferenceProgramSource expectedType expression))
  shrink _ =
    []

type TypedName = (Name, Type)

type Haskell2010PropEnv = [(Text, Haskell2010PropType)]

haskell2010InferenceProgramSource :: Haskell2010PropType -> Haskell2010GeneratedExpr -> Text
haskell2010InferenceProgramSource expectedType expression =
  Text.unlines
    [ "module Main where"
    , "idp x = x"
    , "value = " <> generatedHaskell2010ExprText expression
    , "main :: " <> renderHaskell2010PropType expectedType
    , "main = idp value"
    ]

haskell2010DictionaryInferenceProgramSource :: Haskell2010GeneratedExpr -> Haskell2010GeneratedExpr -> Text
haskell2010DictionaryInferenceProgramSource lhs rhs =
  Text.unlines
    [ "module Main where"
    , "class Same a where"
    , "  same :: a -> a -> Bool"
    , "instance Same Int where"
    , "  same x y = x == y"
    , "instance Same Bool where"
    , "  same x y = x == y"
    , "left = " <> generatedHaskell2010ExprText lhs
    , "right = " <> generatedHaskell2010ExprText rhs
    , "main :: Bool"
    , "main = same left right"
    ]

haskell2010InvalidInferenceProgramSource :: Haskell2010PropType -> Haskell2010GeneratedExpr -> Text
haskell2010InvalidInferenceProgramSource expectedType expression =
  Text.unlines
    [ "module Main where"
    , "bad = " <> generatedHaskell2010ExprText expression
    , "main :: " <> renderHaskell2010PropType expectedType
    , "main = bad"
    ]

genHaskell2010Expr :: Haskell2010PropType -> Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010Expr ty size env next
  | size <= 0 = genHaskell2010AtomExpr ty env
  | otherwise =
      frequency
        [ (4, genHaskell2010AtomExpr ty env)
        , (3, genHaskell2010LetExpr ty size env next)
        , (3, genHaskell2010IfExpr ty size env next)
        , (2, genHaskell2010LambdaAppExpr ty size env next)
        , (if ty == Haskell2010PropInt then 4 else 0, genHaskell2010IntOpExpr size env next)
        , (if ty == Haskell2010PropBool then 4 else 0, genHaskell2010BoolOpExpr size env next)
        ]

genHaskell2010AtomExpr :: Haskell2010PropType -> Haskell2010PropEnv -> Gen Haskell2010GeneratedExpr
genHaskell2010AtomExpr ty env =
  Haskell2010GeneratedExpr ty
    <$> frequency
      (literalChoices <> variableChoices)
 where
  literalChoices =
    case ty of
      Haskell2010PropInt ->
        [(4, Text.pack . show <$> chooseInt (0, 30))]
      Haskell2010PropBool ->
        [(2, pure "True"), (2, pure "False")]
  variableChoices =
    [(2, pure name) | (name, nameType) <- env, nameType == ty]

genHaskell2010LetExpr :: Haskell2010PropType -> Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010LetExpr ty size env next = do
  rhsType <- elements [Haskell2010PropInt, Haskell2010PropBool]
  rhs <- genHaskell2010Expr rhsType (size `div` 2) env (next + 1)
  let name = "p" <> Text.pack (show next)
  body <- genHaskell2010Expr ty (size `div` 2) ((name, rhsType) : env) (next + 2)
  pure $
    Haskell2010GeneratedExpr ty $
      "(let " <> name <> " = " <> generatedHaskell2010ExprText rhs <> " in " <> generatedHaskell2010ExprText body <> ")"

genHaskell2010IfExpr :: Haskell2010PropType -> Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010IfExpr ty size env next = do
  condition <- genHaskell2010Expr Haskell2010PropBool (size `div` 2) env (next + 1)
  thenBranch <- genHaskell2010Expr ty (size `div` 2) env (next + 2)
  elseBranch <- genHaskell2010Expr ty (size `div` 2) env (next + 3)
  pure $
    Haskell2010GeneratedExpr ty $
      "(if "
        <> generatedHaskell2010ExprText condition
        <> " then "
        <> generatedHaskell2010ExprText thenBranch
        <> " else "
        <> generatedHaskell2010ExprText elseBranch
        <> ")"

genHaskell2010LambdaAppExpr :: Haskell2010PropType -> Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010LambdaAppExpr ty size env next =
  case ty of
    Haskell2010PropInt -> do
      argument <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 1)
      let param = "n" <> Text.pack (show next)
      pure $
        Haskell2010GeneratedExpr Haskell2010PropInt $
          "((\\" <> param <> " -> " <> param <> " + 1) " <> generatedHaskell2010ExprText argument <> ")"
    Haskell2010PropBool ->
      oneof
        [ do
            argument <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 1)
            let param = "n" <> Text.pack (show next)
            pure $
              Haskell2010GeneratedExpr Haskell2010PropBool $
                "((\\" <> param <> " -> " <> param <> " == " <> param <> ") " <> generatedHaskell2010ExprText argument <> ")"
        , do
            argument <- genHaskell2010Expr Haskell2010PropBool (size `div` 2) env (next + 1)
            let param = "b" <> Text.pack (show next)
            pure $
              Haskell2010GeneratedExpr Haskell2010PropBool $
                "((\\" <> param <> " -> if " <> param <> " then True else False) " <> generatedHaskell2010ExprText argument <> ")"
        ]

genHaskell2010IntOpExpr :: Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010IntOpExpr size env next = do
  op <- elements [" + ", " - ", " * "]
  lhs <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 1)
  rhs <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 2)
  pure $
    Haskell2010GeneratedExpr Haskell2010PropInt $
      "(" <> generatedHaskell2010ExprText lhs <> op <> generatedHaskell2010ExprText rhs <> ")"

genHaskell2010BoolOpExpr :: Int -> Haskell2010PropEnv -> Int -> Gen Haskell2010GeneratedExpr
genHaskell2010BoolOpExpr size env next =
  oneof
    [ do
        lhs <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 1)
        rhs <- genHaskell2010Expr Haskell2010PropInt (size `div` 2) env (next + 2)
        op <- elements [" == ", " < "]
        pure $
          Haskell2010GeneratedExpr Haskell2010PropBool $
            "(" <> generatedHaskell2010ExprText lhs <> op <> generatedHaskell2010ExprText rhs <> ")"
    , do
        lhs <- genHaskell2010Expr Haskell2010PropBool (size `div` 2) env (next + 1)
        rhs <- genHaskell2010Expr Haskell2010PropBool (size `div` 2) env (next + 2)
        pure $
          Haskell2010GeneratedExpr Haskell2010PropBool $
            "(" <> generatedHaskell2010ExprText lhs <> " == " <> generatedHaskell2010ExprText rhs <> ")"
    ]

renderHaskell2010PropType :: Haskell2010PropType -> Text
renderHaskell2010PropType = \case
  Haskell2010PropInt -> "Int"
  Haskell2010PropBool -> "Bool"

haskell2010PropCoreType :: Haskell2010PropType -> H2010Core.CoreType
haskell2010PropCoreType = \case
  Haskell2010PropInt -> H2010Core.intTy
  Haskell2010PropBool -> H2010Core.boolTy

oppositeHaskell2010PropType :: Haskell2010PropType -> Haskell2010PropType
oppositeHaskell2010PropType = \case
  Haskell2010PropInt -> Haskell2010PropBool
  Haskell2010PropBool -> Haskell2010PropInt

genSupportedANF :: Type -> Int -> [TypedName] -> Int -> Gen AExpr
genSupportedANF ty size env next
  | size <= 0 = AAtom <$> genSupportedAtom ty env
  | otherwise =
      frequency
        [ (4, AAtom <$> genSupportedAtom ty env)
        , (3, genLet ty size env next)
        , (2, genSupportedIf ty size env next)
        , (if ty == TInt then 4 else 0, genIntPrim size env)
        ]

genSupportedAtom :: Type -> [TypedName] -> Gen Atom
genSupportedAtom ty env =
  frequency $
    literal ++ vars
 where
  literal =
    case ty of
      TInt -> [(4, AInt <$> chooseInteger (0, 20))]
      TBool -> [(4, ABool <$> arbitrary)]
      TFun {} -> []
  vars =
    [(2, pure (AVar name)) | (name, nameType) <- env, nameType == ty]

genLet :: Type -> Int -> [TypedName] -> Int -> Gen AExpr
genLet bodyType size env next = do
  rhsType <- elements [TInt, TBool]
  let name = Name ("p" <> Text.pack (show next))
  rhs <- genSupportedANF rhsType (size `div` 2) env (next + 1)
  body <- genSupportedANF bodyType (size `div` 2) ((name, rhsType) : env) (next + 2)
  pure (ALet name rhs body)

genSupportedIf :: Type -> Int -> [TypedName] -> Int -> Gen AExpr
genSupportedIf ty size env next = do
  cond <- genSupportedAtom TBool env
  thenBranch <- genSupportedANF ty (size `div` 2) env (next + 1)
  elseBranch <- genSupportedANF ty (size `div` 2) env (next + 2)
  pure (AIf cond thenBranch elseBranch)

genIntPrim :: Int -> [TypedName] -> Gen AExpr
genIntPrim _ env = do
  op <- elements [Add, Sub, Mul, Div]
  lhs <- genSupportedAtom TInt env
  rhs <- genSupportedAtom TInt env
  pure (APrim op lhs rhs)

genClosedExpr :: Int -> Gen Expr
genClosedExpr size
  | size <= 0 =
      oneof [EInt <$> arbitrarySizedNatural, EBool <$> arbitrary]
  | otherwise =
      frequency
        [ (3, EInt <$> arbitrarySizedNatural)
        , (2, EBool <$> arbitrary)
        , (3, genArithmetic size)
        , (2, genIf size)
        , (1, pure (ELam (mkName "x") TInt (EBin Add (EVar (mkName "x")) (EInt 1))))
        , (1, pure (EApp (ELam (mkName "x") TInt (EBin Add (EVar (mkName "x")) (EInt 1))) (EInt 1)))
        ]

genArithmetic :: Int -> Gen Expr
genArithmetic size = do
  op <- elements [Add, Sub, Mul]
  lhs <- genIntExpr (size `div` 2)
  rhs <- genIntExpr (size `div` 2)
  pure (EBin op lhs rhs)

genIf :: Int -> Gen Expr
genIf size = do
  thenBranch <- genClosedExpr (size `div` 2)
  elseBranch <- genClosedExpr (size `div` 2)
  pure (EIf (EBool True) thenBranch elseBranch)

genIntExpr :: Int -> Gen Expr
genIntExpr size
  | size <= 0 = EInt <$> arbitrarySizedNatural
  | otherwise =
      frequency
        [ (4, EInt <$> arbitrarySizedNatural)
        , (1, genArithmetic (size `div` 2))
        ]

shrinkClosedExpr :: Expr -> [Expr]
shrinkClosedExpr = \case
  EBin _ lhs rhs ->
    [lhs, rhs]
  EIf _ thenBranch elseBranch ->
    [thenBranch, elseBranch]
  EApp _ arg ->
    [arg]
  ELet _ rhs body ->
    [rhs, body]
  ELam _ _ body ->
    [body]
  EInt n ->
    EInt <$> shrink n
  EBool b ->
    EBool <$> shrink b
  EVar _ ->
    []

validateExample :: FilePath -> IO (Either String ())
validateExample path = do
  source <- Text.IO.readFile path
  pure $ do
    parsed <- parseExprAt path source
    mapLeft (showText . renderANFValidationError) (validateANF (toANF parsed))

checkProgram :: Text -> Type -> Value -> Either String ()
checkProgram source expectedType expectedValue = do
  parsed <- parseExpr source
  actualType <- mapLeft (showText . renderTypeError) (infer parsed)
  actualValue <- mapLeft (showText . renderRuntimeError) (eval parsed)
  expectEqual "inferred type" expectedType actualType
  expectEqual "evaluation result" expectedValue actualValue

parseExpr :: Text -> Either String Expr
parseExpr =
  parseExprAt "<test>"

parseExprAt :: FilePath -> Text -> Either String Expr
parseExprAt path source =
  mapLeft errorBundlePretty (parseProgram path source)

parseSource :: Text -> Either String Program
parseSource =
  parseSourceAt "<test>"

parseSourceAt :: FilePath -> Text -> Either String Program
parseSourceAt path source =
  mapLeft errorBundlePretty (parseSourceProgram path source)

parseHaskell2010 :: Text -> Either String H2010.HsModule
parseHaskell2010 =
  parseHaskell2010At "<haskell2010-test>"

parseHaskell2010At :: FilePath -> Text -> Either String H2010.HsModule
parseHaskell2010At path source =
  mapLeft errorBundlePretty (H2010Parser.parseSourceModule path source)

renameHaskell2010 :: Text -> Either String H2010Renamed.RHsModule
renameHaskell2010 source =
  mapLeft (Text.unpack . H2010Renamer.renderRenameError) (renameHaskell2010Raw source)

renameHaskell2010Raw :: Text -> Either H2010Renamer.RenameError H2010Renamed.RHsModule
renameHaskell2010Raw source = do
  parsed <- mapLeft (error . errorBundlePretty) (H2010Parser.parseSourceModule "<haskell2010-renamer-test>" source)
  H2010Renamer.renameModule parsed

parseHaskell2010ModuleSources :: [(FilePath, Text)] -> Either String [H2010.HsModule]
parseHaskell2010ModuleSources =
  traverse (\(path, source) -> parseHaskell2010At path source)

renameHaskell2010ModulesRaw :: [(FilePath, Text)] -> Either H2010Renamer.RenameError [H2010Renamed.RHsModule]
renameHaskell2010ModulesRaw sources = do
  modules <- mapLeft (error . id) (parseHaskell2010ModuleSources sources)
  H2010Renamer.renameModuleGraph modules

expectRenameError :: String -> H2010Renamer.RenameError -> Text -> Either String ()
expectRenameError label expected source =
  case renameHaskell2010Raw source of
    Left actual -> expectEqual label expected actual
    Right renamed -> Left (label <> "\nexpected rename error, got module:\n" <> show renamed)

typecheckHaskell2010 :: Text -> Either String H2010Core.CoreModule
typecheckHaskell2010 source =
  mapLeft (Text.unpack . H2010Typecheck.renderTypecheckError) (typecheckHaskell2010Raw source)

typecheckHaskell2010Raw :: Text -> Either H2010Typecheck.TypecheckError H2010Core.CoreModule
typecheckHaskell2010Raw source = do
  renamed <- mapLeft (error . Text.unpack . H2010Renamer.renderRenameError) (renameHaskell2010Raw source)
  H2010Typecheck.typecheckModuleToCore renamed

typecheckHaskell2010WithWarnings :: Text -> Either String H2010Typecheck.TypecheckResult
typecheckHaskell2010WithWarnings source = do
  renamed <- mapLeft (Text.unpack . H2010Renamer.renderRenameError) (renameHaskell2010Raw source)
  mapLeft
    (Text.unpack . H2010Typecheck.renderTypecheckError)
    (H2010Typecheck.typecheckModuleToCoreWithWarnings renamed)

haskell2010TypecheckErrorDetail :: H2010Typecheck.TypecheckError -> H2010Typecheck.TypecheckError
haskell2010TypecheckErrorDetail = \case
  H2010Typecheck.TypecheckErrorAt _ err ->
    haskell2010TypecheckErrorDetail err
  err ->
    err

typecheckHaskell2010Modules :: [(FilePath, Text)] -> Either String H2010Core.CoreModule
typecheckHaskell2010Modules sources = do
  renamed <- mapLeft (Text.unpack . H2010Renamer.renderRenameError) (renameHaskell2010ModulesRaw sources)
  mapLeft
    (Text.unpack . H2010Typecheck.renderTypecheckError)
    (H2010Typecheck.typecheckModuleToCore (H2010ModuleGraph.wholeProgramModule renamed))

optimizeHaskell2010Core :: Text -> Either String H2010CoreEgglog.CoreEgglogResult
optimizeHaskell2010Core source = do
  coreModule <- typecheckHaskell2010 source
  optimizeHaskell2010CoreModule coreModule

optimizeHaskell2010CoreModule :: H2010Core.CoreModule -> Either String H2010CoreEgglog.CoreEgglogResult
optimizeHaskell2010CoreModule coreModule =
  mapLeft
    (Text.unpack . H2010CoreEgglog.renderCoreEgglogError)
    (H2010CoreEgglog.optimizeCoreModuleWithEgglog EEV.defaultRunConfig coreModule)

evalHaskell2010Binding :: Text -> Text -> Either String H2010CoreEval.CoreValue
evalHaskell2010Binding binding source =
  mapLeft (Text.unpack . H2010CoreEval.renderCoreEvalError) (evalHaskell2010BindingRaw binding source)

evalHaskell2010BindingRaw :: Text -> Text -> Either H2010CoreEval.CoreEvalError H2010CoreEval.CoreValue
evalHaskell2010BindingRaw binding source = do
  coreModule <- mapLeft (error . Text.unpack . H2010Typecheck.renderTypecheckError) (typecheckHaskell2010Raw source)
  H2010CoreEval.evalCoreModuleBindingByOccurrence binding coreModule

evalHaskell2010CoreModuleBinding ::
  Text ->
  H2010Core.CoreModule ->
  Either String H2010CoreEval.CoreValue
evalHaskell2010CoreModuleBinding binding =
  mapLeft (Text.unpack . H2010CoreEval.renderCoreEvalError)
    . evalHaskell2010CoreModuleBindingRaw binding

evalHaskell2010CoreModuleBindingRaw ::
  Text ->
  H2010Core.CoreModule ->
  Either H2010CoreEval.CoreEvalError H2010CoreEval.CoreValue
evalHaskell2010CoreModuleBindingRaw =
  H2010CoreEval.evalCoreModuleBindingByOccurrence

expectCoreEvalInt :: String -> Integer -> H2010CoreEval.CoreValue -> Either String ()
expectCoreEvalInt label expected = \case
  H2010CoreEval.CoreInt actual ->
    expectEqual label expected (hintToInteger actual)
  actual ->
    Left
      ( label
          <> ": expected Core Int "
          <> show expected
          <> ", got "
          <> Text.unpack (H2010CoreEval.renderCoreValue actual)
      )

expectCoreEvalIO :: String -> Text -> H2010CoreEval.CoreValue -> Either String ()
expectCoreEvalIO label expected = \case
  H2010CoreEval.CoreIO chunks ->
    expectEqual label expected (Text.concat chunks)
  actual ->
    Left
      ( label
          <> ": expected Core IO output "
          <> show expected
          <> ", got "
          <> Text.unpack (H2010CoreEval.renderCoreValue actual)
      )

evalSTGBinding :: Text -> H2010STG.STGProgram -> Either String H2010STGEval.STGValue
evalSTGBinding binding program =
  mapLeft (Text.unpack . H2010STGEval.renderSTGEvalError) (evalSTGBindingRaw binding program)

evalSTGBindingRaw :: Text -> H2010STG.STGProgram -> Either H2010STGEval.STGEvalError H2010STGEval.STGValue
evalSTGBindingRaw binding =
  H2010STGEval.evalSTGProgramBindingByOccurrence binding

evalSTGBindingWithStats ::
  Text ->
  H2010STG.STGProgram ->
  Either String (H2010STGEval.STGValue, H2010STGEval.STGEvalStats)
evalSTGBindingWithStats binding program =
  mapLeft
    (Text.unpack . H2010STGEval.renderSTGEvalError)
    (H2010STGEval.evalSTGProgramBindingByOccurrenceWithStats binding program)

lowerHaskell2010ToSTG :: Text -> Either String H2010STG.STGProgram
lowerHaskell2010ToSTG source = do
  coreModule <-
    mapLeft
      (Text.unpack . H2010Typecheck.renderTypecheckError)
      (typecheckHaskell2010Raw source)
  mapLeft (Text.unpack . H2010STGLower.renderSTGLowerError) (H2010STGLower.lowerCoreModule coreModule)

lowerOptimizedCoreToSTG :: H2010CoreEgglog.CoreEgglogResult -> Either String H2010STG.STGProgram
lowerOptimizedCoreToSTG result =
  mapLeft
    (Text.unpack . H2010STGLower.renderSTGLowerError)
    (H2010STGLower.lowerCoreModule (H2010CoreEgglog.coreEgglogOptimizedModule result))

lowerAndEvalHaskell2010Binding :: Text -> Text -> Either String H2010STGEval.STGValue
lowerAndEvalHaskell2010Binding binding source = do
  stgProgram <- lowerHaskell2010ToSTG source
  evalSTGBinding binding stgProgram

lowerAndEvalHaskell2010BindingRaw ::
  Text ->
  Text ->
  Either (Either String H2010STGEval.STGEvalError) H2010STGEval.STGValue
lowerAndEvalHaskell2010BindingRaw binding source = do
  stgProgram <- mapLeft Left (lowerHaskell2010ToSTG source)
  mapLeft Right (H2010STGEval.evalSTGProgramBindingByOccurrence binding stgProgram)

checkCoreToSTGInt :: String -> Integer -> Text -> Either String ()
checkCoreToSTGInt label expected source = do
  coreValue <- evalHaskell2010Binding "main" source
  stgValue <- lowerAndEvalHaskell2010Binding "main" source
  expectCoreEvalInt (label <> " Core oracle") expected coreValue
  expectSTGInt (label <> " STG value") expected stgValue

checkCoreToSTGIO :: String -> Text -> Text -> Either String ()
checkCoreToSTGIO label expected source = do
  coreValue <- evalHaskell2010Binding "main" source
  stgValue <- lowerAndEvalHaskell2010Binding "main" source
  expectCoreEvalIO (label <> " Core oracle") expected coreValue
  expectSTGIO (label <> " STG value") expected stgValue

compileHaskell2010Native :: Text -> Either String H2010Native.Haskell2010LLVMResult
compileHaskell2010Native source =
  compileHaskell2010NativeWithOptions H2010Native.defaultHaskell2010NativeOptions source

compileHaskell2010NativeWithOptions ::
  H2010Native.Haskell2010NativeOptions ->
  Text ->
  Either String H2010Native.Haskell2010LLVMResult
compileHaskell2010NativeWithOptions options source =
  mapLeft
    (Text.unpack . H2010Native.renderHaskell2010LLVMError)
    (H2010Native.compileHaskell2010ToLLVMWithOptions options "<haskell2010-native-test>" source)

compileHaskell2010NativeText :: Text -> Either String Text
compileHaskell2010NativeText source =
  H2010Native.haskell2010LLVMText <$> compileHaskell2010Native source

haskell2010NativeSuccessExamples :: [(Text, Text, String)]
haskell2010NativeSuccessExamples =
  [ ("arithmetic", haskell2010ArithmeticSource, "9\n")
  , ("polymorphic-id", haskell2010PolymorphicIdentitySource, "42\n")
  , ("lazy-let", haskell2010LazyLetSource, "5\n")
  , ("lazy-argument", haskell2010LazyArgumentSource, "1\n")
  , ("bool-case", haskell2010BoolCaseSource, "7\n")
  , ("tuple-case", haskell2010TupleCaseSource, "3\n")
  , ("prelude-lists", haskell2010ListPreludeSource, "321\n")
  , ("prelude-maybe-ordering", haskell2010PreludeMaybeOrderingSource, "5\n")
  , ("short-circuit", haskell2010ShortCircuitSource, "7\n")
  , ("guarded-self-recursion", haskell2010GuardedSelfRecursionSource, "1\n")
  , ("local-factorial", haskell2010LocalFactorialSource, "120\n")
  , ("fibonacci", haskell2010FibonacciSource, "21\n")
  , ("mutual-recursion", haskell2010MutualRecursionSource, "1\n")
  , ("recursive-list", haskell2010RecursiveListSource, "10\n")
  , ("recursive-pattern-binding", haskell2010RecursivePatternBindingSource, "2\n")
  , ("typeclass-dictionary", haskell2010TypeClassDictionarySource, "1\n")
  , ("prelude-classes", haskell2010PreludeClassDictionarySource, "6\n")
  , ("char-runtime", haskell2010CharRuntimeSource, "1\n")
  , ("char-main", haskell2010CharMainSource, "Z\n")
  , ("string-char-list", haskell2010StringCharListSource, "5\n")
  , ("numeric-defaulting", haskell2010NumericDefaultingSource, "7\n47\n")
  , ("io-printing", haskell2010IOPrintingSource, "ok\nanswer\n42\nTrue\n")
  , ("guards-as-patterns", haskell2010GuardAsPatternSource, "15\n")
  , ("irrefutable-patterns", haskell2010IrrefutablePatternSource, "7\n")
  , ("sections", haskell2010SectionsSource, "6\n")
  , ("adt-box", haskell2010ADTBoxSource, "7\n")
  , ("adt-record-fields", haskell2010RecordFieldSource, "43\n")
  , ("adt-maybe", haskell2010PolymorphicADTSource, "4\n")
  , ("adt-nested", haskell2010NestedADTSource, "3\n")
  , ("adt-lazy-field", haskell2010LazyADTFieldSource, "5\n")
  , ("partial-application", haskell2010PartialApplicationSource, "1\n")
  ]

haskell2010NativeExecutableExamples :: [(Text, Text, String)]
haskell2010NativeExecutableExamples =
  [ ("lazy-argument", haskell2010LazyArgumentSource, "1\n")
  , ("partial-application", haskell2010PartialApplicationSource, "1\n")
  , ("prelude-lists", haskell2010ListPreludeSource, "321\n")
  , ("recursive-list", haskell2010RecursiveListSource, "10\n")
  , ("recursive-pattern-binding", haskell2010RecursivePatternBindingSource, "2\n")
  , ("typeclass-dictionary", haskell2010TypeClassDictionarySource, "1\n")
  , ("prelude-classes", haskell2010PreludeClassDictionarySource, "6\n")
  , ("char-runtime", haskell2010CharRuntimeSource, "1\n")
  , ("char-main", haskell2010CharMainSource, "Z\n")
  , ("string-char-list", haskell2010StringCharListSource, "5\n")
  , ("numeric-defaulting", haskell2010NumericDefaultingSource, "7\n47\n")
  , ("io-printing", haskell2010IOPrintingSource, "ok\nanswer\n42\nTrue\n")
  , ("guards-as-patterns", haskell2010GuardAsPatternSource, "15\n")
  , ("irrefutable-patterns", haskell2010IrrefutablePatternSource, "7\n")
  , ("sections", haskell2010SectionsSource, "6\n")
  ]

haskell2010ArithmeticSource :: Text
haskell2010ArithmeticSource =
  "module Main where\n\
  \main = (1 + 2) * 3\n"

haskell2010PrimitiveArithmeticCoreModule :: H2010Core.CoreModule
haskell2010PrimitiveArithmeticCoreModule =
  H2010Core.CoreModule
    { H2010Core.coreModuleName = Nothing
    , H2010Core.coreModuleConstructors = Map.empty
    , H2010Core.coreModuleBinds =
        [ H2010Core.CoreNonRec
            (coreBinder (coreTerm "main" 6200) H2010Core.intTy)
            ( H2010Core.CPrimOp
                H2010Core.PrimMul
                [ H2010Core.CPrimOp H2010Core.PrimAdd [coreInt 1, coreInt 2] H2010Core.intTy
                , coreInt 3
                ]
                H2010Core.intTy
            )
        ]
    }

haskell2010KnownBoolCaseCoreModule :: H2010Core.CoreModule
haskell2010KnownBoolCaseCoreModule =
  H2010Core.CoreModule
    { H2010Core.coreModuleName = Nothing
    , H2010Core.coreModuleConstructors = Map.empty
    , H2010Core.coreModuleBinds =
        [ H2010Core.CoreNonRec
            (coreBinder (coreTerm "main" 6201) H2010Core.intTy)
            ( H2010Core.CCase
                (H2010Core.CCon H2010Core.falseDataConName H2010Core.boolTy)
                (coreBinder (coreTerm "$case" 6202) H2010Core.boolTy)
                [ H2010Core.CoreAlt (H2010Core.ConstructorAlt H2010Core.trueDataConName) [] (coreInt 0)
                , H2010Core.CoreAlt (H2010Core.ConstructorAlt H2010Core.falseDataConName) [] (coreInt 7)
                ]
                H2010Core.intTy
            )
        ]
    }

haskell2010PolymorphicIdentitySource :: Text
haskell2010PolymorphicIdentitySource =
  "module Main where\n\
  \id :: a -> a\n\
  \id x = x\n\
  \main = id 42\n"

haskell2010LazyLetSource :: Text
haskell2010LazyLetSource =
  "module Main where\n\
  \main = let\n\
  \  x = 1 / 0\n\
  \in 5\n"

haskell2010LazyArgumentSource :: Text
haskell2010LazyArgumentSource =
  "module Main where\n\
  \const :: a -> b -> a\n\
  \const x y = x\n\
  \main = const 1 (1 / 0)\n"

haskell2010BoolCaseSource :: Text
haskell2010BoolCaseSource =
  "module Main where\n\
  \main = case False of\n\
  \  True -> 0\n\
  \  False -> 7\n"

haskell2010PartialCaseWarningSource :: Text
haskell2010PartialCaseWarningSource =
  "module Main where\n\
  \main = case True of\n\
  \  True -> 1\n"

haskell2010TotalBoolCaseWarningSource :: Text
haskell2010TotalBoolCaseWarningSource =
  "module Main where\n\
  \main = case True of\n\
  \  True -> 1\n\
  \  False -> 0\n"

haskell2010TotalADTCaseWarningSource :: Text
haskell2010TotalADTCaseWarningSource =
  "module Main where\n\
  \data Choice = One | Two Int\n\
  \main = case Two 4 of\n\
  \  One -> 1\n\
  \  Two _ -> 2\n"

haskell2010PartialFunctionWarningSource :: Text
haskell2010PartialFunctionWarningSource =
  "module Main where\n\
  \fromJust :: Maybe Int -> Int\n\
  \fromJust (Just x) = x\n\
  \main = fromJust (Just 1)\n"

haskell2010KnownConstructorCaseSource :: Text
haskell2010KnownConstructorCaseSource =
  "module Main where\n\
  \data Box = Box Int\n\
  \main = case Box (1 + 2) of\n\
  \  Box x -> x + 4\n"

haskell2010KnownConstructorLazyFieldSource :: Text
haskell2010KnownConstructorLazyFieldSource =
  "module Main where\n\
  \data Pair = Pair Int Int\n\
  \main = case Pair (1 / 0) 5 of\n\
  \  Pair _ y -> y\n"

haskell2010KnownConstructorForcedFieldSource :: Text
haskell2010KnownConstructorForcedFieldSource =
  "module Main where\n\
  \data Box = Box Int\n\
  \main = case Box (1 / 0) of\n\
  \  Box x -> x\n"

haskell2010TupleCaseSource :: Text
haskell2010TupleCaseSource =
  "module Main where\n\
  \unit x = case () of\n\
  \  () -> x\n\
  \main = case (unit 1, 2) of\n\
  \  (x, y) -> x + y\n"

haskell2010ListPreludeSource :: Text
haskell2010ListPreludeSource =
  "module Main where\n\
  \inc x = x + 0\n\
  \keep x = x < 4\n\
  \add x acc = x + acc\n\
  \main = case reverse (filter keep (map inc [1, 2, 3])) of\n\
  \  [a, b, c] -> foldr add 0 [a * 100, b * 10, c] + length [a, b, c] - 3\n\
  \  _ -> 0\n"

haskell2010PreludeMaybeOrderingSource :: Text
haskell2010PreludeMaybeOrderingSource =
  "module Main where\n\
  \main = case Right (Just LT) of\n\
  \  Left x -> x\n\
  \  Right value -> case value of\n\
  \    Nothing -> 0\n\
  \    Just LT -> 5\n\
  \    Just EQ -> 6\n\
  \    Just GT -> 7\n"

haskell2010ShortCircuitSource :: Text
haskell2010ShortCircuitSource =
  "module Main where\n\
  \main = if (False && ((1 / 0) == 0)) || True then 7 else 1\n"

haskell2010SectionsSource :: Text
haskell2010SectionsSource =
  "module Main where\n\
  \left :: Int -> Int\n\
  \left = (1 +)\n\
  \right :: Int -> Int\n\
  \right = (+ 1)\n\
  \over :: Int -> Bool\n\
  \over = (> 3)\n\
  \short :: Bool -> Bool\n\
  \short = (False &&)\n\
  \main = if short ((1 / 0) == 0) then 0 else if over (right 3) then left (right 4) else 0\n"

haskell2010GuardedSelfRecursionSource :: Text
haskell2010GuardedSelfRecursionSource =
  "module Main where\n\
  \main = if True then 1 else main\n"

haskell2010LocalFactorialSource :: Text
haskell2010LocalFactorialSource =
  "module Main where\n\
  \main = let\n\
  \  fact n = if n == 0 then 1 else n * fact (n - 1)\n\
  \in fact 5\n"

haskell2010FibonacciSource :: Text
haskell2010FibonacciSource =
  "module Main where\n\
  \fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)\n\
  \main = fib 8\n"

haskell2010MutualRecursionSource :: Text
haskell2010MutualRecursionSource =
  "module Main where\n\
  \evenN n = if n == 0 then True else oddN (n - 1)\n\
  \oddN n = if n == 0 then False else evenN (n - 1)\n\
  \main = if evenN 6 then 1 else 0\n"

haskell2010RecursiveListSource :: Text
haskell2010RecursiveListSource =
  "module Main where\n\
  \sumList xs = case xs of\n\
  \  [] -> 0\n\
  \  y : ys -> y + sumList ys\n\
  \main = sumList [1, 2, 3, 4]\n"

haskell2010RecursivePatternBindingSource :: Text
haskell2010RecursivePatternBindingSource =
  "module Main where\n\
  \ones@(x : xs) = 1 : ones\n\
  \main = case xs of\n\
  \  y : _ -> x + y\n\
  \  _ -> 0\n"

haskell2010TypeClassDictionarySource :: Text
haskell2010TypeClassDictionarySource =
  "module Main where\n\
  \class Equal a where\n\
  \  equal :: a -> a -> Bool\n\
  \data Box = Box Int\n\
  \instance Equal Box where\n\
  \  equal (Box x) (Box y) = x == y\n\
  \same :: Equal a => a -> a -> Bool\n\
  \same x y = equal x y\n\
  \main = if same (Box 7) (Box 7) && not (same (Box 7) (Box 8)) then 1 else 0\n"

haskell2010PreludeClassDictionarySource :: Text
haskell2010PreludeClassDictionarySource =
  "module Main where\n\
  \same :: Eq a => a -> a -> Bool\n\
  \same x y = x == y\n\
  \ordered :: Ord a => a -> a -> Bool\n\
  \ordered x y = x <= y && y > x\n\
  \distancePlusSign :: Num a => a -> a -> a\n\
  \distancePlusSign x y = abs (x + negate y) + signum (x - y)\n\
  \compareFlag = case compare 5 4 of\n\
  \  GT -> True\n\
  \  _ -> False\n\
  \main = if same 7 7 && not (same 7 8) && ordered 3 4 && compareFlag && max False True && not (min False True) then distancePlusSign 9 4 else 0\n"

haskell2010CharRuntimeSource :: Text
haskell2010CharRuntimeSource =
  "module Main where\n\
  \same :: Char -> Char -> Bool\n\
  \same x y = x == y\n\
  \different :: Char -> Char -> Bool\n\
  \different x y = x /= y\n\
  \main = case 'h' of\n\
  \  'h' -> if same 'a' 'a' && different 'a' 'b' then 1 else 0\n\
  \  _ -> 0\n"

haskell2010CharMainSource :: Text
haskell2010CharMainSource =
  "module Main where\n\
  \main = 'Z'\n"

haskell2010StringCharListSource :: Text
haskell2010StringCharListSource =
  "module Main where\n\
  \stringLength :: String -> Int\n\
  \stringLength xs = length xs\n\
  \shownLength :: Int\n\
  \shownLength = length (show 42)\n\
  \main = case \"hi\" of\n\
  \  \"hi\" -> stringLength \"abc\" + shownLength\n\
  \  _ -> 0\n"

haskell2010NumericDefaultingSource :: Text
haskell2010NumericDefaultingSource =
  "module Main where\n\
  \twice x = x + x\n\
  \defaulted = 6\n\
  \viaFromInteger :: Int\n\
  \viaFromInteger = fromInteger 35\n\
  \main :: IO ()\n\
  \main = do\n\
  \  print (1 + 2 * 3)\n\
  \  print (twice defaulted + viaFromInteger)\n\
  \  return ()\n"

haskell2010MonomorphismRestrictionSource :: Text
haskell2010MonomorphismRestrictionSource =
  "module Main where\n\
  \defaulted = 7\n\
  \main = if defaulted == 7 then 1 else 0\n"

haskell2010MultiModuleSources :: [(FilePath, Text)]
haskell2010MultiModuleSources =
  [ ( "Lib.hs"
    , "module Lib (Box(..), double) where\n\
      \data Box = Box Int\n\
      \double x = x + x\n\
      \hidden = 99\n"
    )
  , ( "Main.hs"
    , "module Main where\n\
      \import qualified Lib as Lib (Box(..), double)\n\
      \unbox (Lib.Box x) = x\n\
      \main = Lib.double (unbox (Lib.Box 12))\n"
    )
  ]

haskell2010HiddenImportSources :: [(FilePath, Text)]
haskell2010HiddenImportSources =
  [ ( "Lib.hs"
    , "module Lib (public) where\n\
      \public = 1\n\
      \hidden = 2\n"
    )
  , ( "Main.hs"
    , "module Main where\n\
      \import Lib (hidden)\n\
      \main = hidden\n"
    )
  ]

haskell2010IOPrintingSource :: Text
haskell2010IOPrintingSource =
  "module Main where\n\
  \prefix :: IO ()\n\
  \prefix = putStrLn ['o', 'k'] >> putStrLn \"answer\" >> print (abs (negate 42))\n\
  \main :: IO ()\n\
  \main = do\n\
  \  prefix\n\
  \  print (not False)\n\
  \  return ()\n"

haskell2010GuardAsPatternSource :: Text
haskell2010GuardAsPatternSource =
  "module Main where\n\
  \score n\n\
  \  | n == 0 = 1\n\
  \  | n < 3 = n + 10\n\
  \  | otherwise = n + 2\n\
  \listScore xs@(x : rest) = case xs of\n\
  \  ys@(y : tail) | length ys == 3 -> score y + length tail + length xs + x\n\
  \  _ -> 0\n\
  \main = listScore [4, 5, 6]\n"

haskell2010GuardFallthroughSource :: Text
haskell2010GuardFallthroughSource =
  "module Main where\n\
  \main | False = 1\n"

haskell2010IrrefutablePatternSource :: Text
haskell2010IrrefutablePatternSource =
  "module Main where\n\
  \ignore :: Maybe Int -> Int\n\
  \ignore ~(Just x) = 5\n\
  \pick :: (Int, Int) -> Int\n\
  \pick ~(x, _) = x\n\
  \main = case (1 / 0) of\n\
  \  z@(~x) -> ignore Nothing + pick (2, 1 / 0)\n"

haskell2010IrrefutablePatternDemandSource :: Text
haskell2010IrrefutablePatternDemandSource =
  "module Main where\n\
  \force :: Maybe Int -> Int\n\
  \force ~(Just x) = x\n\
  \main = force Nothing\n"

haskell2010ADTBoxSource :: Text
haskell2010ADTBoxSource =
  "module Main where\n\
  \data Box = Box Int\n\
  \main = case Box 7 of\n\
  \  Box x -> x\n"

haskell2010NewtypeRepresentationSource :: Text
haskell2010NewtypeRepresentationSource =
  "module Main where\n\
  \newtype Age = Age Int\n\
  \unAge :: Age -> Int\n\
  \unAge (Age n) = n\n\
  \main = unAge (Age 42)\n"

haskell2010RecordFieldSource :: Text
haskell2010RecordFieldSource =
  "module Main where\n\
  \data Person = Person { age :: Int, score :: Int }\n\
  \bump :: Person -> Int\n\
  \bump (Person { score = s, age = a }) = a + s\n\
  \main = bump (Person { score = 2, age = 40 }) + age (Person { age = 1, score = 0 })\n"

haskell2010NewtypeRecordFieldSource :: Text
haskell2010NewtypeRecordFieldSource =
  "module Main where\n\
  \newtype Age = Age { unAge :: Int }\n\
  \main = unAge (Age { unAge = 42 })\n"

haskell2010PolymorphicADTSource :: Text
haskell2010PolymorphicADTSource =
  "module Main where\n\
  \data Maybe a = Nothing | Just a\n\
  \main = case Just 4 of\n\
  \  Nothing -> 0\n\
  \  Just x -> x\n"

haskell2010NestedADTSource :: Text
haskell2010NestedADTSource =
  "module Main where\n\
  \data Box = Box Int\n\
  \data Wrap = Wrap Box\n\
  \main = case Wrap (Box 3) of\n\
  \  Wrap (Box x) -> x\n"

haskell2010LazyADTFieldSource :: Text
haskell2010LazyADTFieldSource =
  "module Main where\n\
  \data Box = Box Int\n\
  \main = case Box (1 / 0) of\n\
  \  Box _ -> 5\n"

haskell2010PartialApplicationSource :: Text
haskell2010PartialApplicationSource =
  "module Main where\n\
  \const :: a -> b -> a\n\
  \const x y = x\n\
  \one = const 1\n\
  \main = one (1 / 0)\n"

haskell2010DivisionByZeroSource :: Text
haskell2010DivisionByZeroSource =
  "module Main where\n\
  \main = 1 / 0\n"

expectSTGInt :: String -> Integer -> H2010STGEval.STGValue -> Either String ()
expectSTGInt label expected = \case
  H2010STGEval.STGInt actual ->
    expectEqual label expected (hintToInteger actual)
  actual ->
    Left
      ( label
          <> ": expected STG Int "
          <> show expected
          <> ", got "
          <> Text.unpack (H2010STGEval.renderSTGValue actual)
      )

expectSTGIO :: String -> Text -> H2010STGEval.STGValue -> Either String ()
expectSTGIO label expected = \case
  H2010STGEval.STGIO chunks ->
    expectEqual label expected (Text.concat chunks)
  actual ->
    Left
      ( label
          <> ": expected STG IO output "
          <> show expected
          <> ", got "
          <> Text.unpack (H2010STGEval.renderSTGValue actual)
      )

coreTerm :: Text -> Int -> H2010Names.RName
coreTerm occurrence uniqueId =
  H2010Names.RName H2010Names.TermNamespace occurrence uniqueId False

coreBinder :: H2010Names.RName -> H2010Core.CoreType -> H2010Core.CoreBinder
coreBinder =
  H2010Core.CoreBinder

coreInt :: Integer -> H2010Core.CoreExpr
coreInt value =
  H2010Core.CLit (H2010.LInt value) H2010Core.intTy

coreTrue :: H2010Core.CoreExpr
coreTrue =
  H2010Core.CCon H2010Core.trueDataConName H2010Core.boolTy

stgBinder :: Text -> Int -> H2010Core.CoreType -> H2010STG.STGBinder
stgBinder occurrence uniqueId ty =
  H2010STG.STGBinder (coreTerm occurrence uniqueId) ty

stgVar :: H2010STG.STGBinder -> H2010STG.STGAtom
stgVar binder =
  H2010STG.STGVar (H2010STG.stgBinderName binder) (H2010STG.stgBinderType binder)

stgIntAtom :: Integer -> H2010STG.STGAtom
stgIntAtom value =
  H2010STG.STGLit (H2010.LInt value) H2010Core.intTy

stgIntExpr :: Integer -> H2010STG.STGExpr
stgIntExpr =
  H2010STG.STGAtom . stgIntAtom

stgDivZeroExpr :: H2010STG.STGExpr
stgDivZeroExpr =
  H2010STG.STGPrim H2010Core.PrimDiv [stgIntAtom 1, stgIntAtom 0] H2010Core.intTy

stgThunkBinding :: H2010STG.STGBinder -> H2010STG.STGUpdateFlag -> H2010STG.STGExpr -> H2010STG.STGBind
stgThunkBinding binder updateFlag expression =
  H2010STG.STGNonRec binder (H2010STG.STGThunk updateFlag expression)

stgMainProgram :: H2010STG.STGExpr -> H2010STG.STGProgram
stgMainProgram expression =
  H2010STG.STGProgram Map.empty [stgThunkBinding stgMainBinder H2010STG.Updatable expression]

stgMainBinder :: H2010STG.STGBinder
stgMainBinder =
  stgBinder "main" 5100 H2010Core.intTy

stgUnusedBadBinder :: H2010STG.STGBinder
stgUnusedBadBinder =
  stgBinder "bad" 5101 H2010Core.intTy

stgLazyFunctionArgumentProgram :: H2010STG.STGProgram
stgLazyFunctionArgumentProgram =
  H2010STG.STGProgram
    Map.empty
    [ H2010STG.STGNonRec constBinder constRhs
    , stgThunkBinding stgMainBinder H2010STG.Updatable mainBody
    ]
 where
  constBinder =
    stgBinder
      "const"
      5110
      (H2010Core.funTy H2010Core.intTy (H2010Core.funTy H2010Core.intTy H2010Core.intTy))
  xBinder =
    stgBinder "x" 5111 H2010Core.intTy
  yBinder =
    stgBinder "y" 5112 H2010Core.intTy
  badBinder =
    stgBinder "bad" 5113 H2010Core.intTy
  constRhs =
    H2010STG.STGFunction [xBinder, yBinder] (H2010STG.STGAtom (stgVar xBinder))
  mainBody =
    H2010STG.STGLet
      (stgThunkBinding badBinder H2010STG.Updatable stgDivZeroExpr)
      ( H2010STG.STGApp
          (H2010STG.stgBinderName constBinder)
          [stgIntAtom 1, stgVar badBinder]
          H2010Core.intTy
      )
      H2010Core.intTy

stgSharingProgram :: H2010STG.STGUpdateFlag -> H2010STG.STGBinder -> H2010STG.STGProgram
stgSharingProgram updateFlag xBinder =
  stgMainProgram
    ( H2010STG.STGLet
        ( stgThunkBinding
            xBinder
            updateFlag
            (H2010STG.STGPrim H2010Core.PrimAdd [stgIntAtom 20, stgIntAtom 1] H2010Core.intTy)
        )
        (H2010STG.STGPrim H2010Core.PrimAdd [stgVar xBinder, stgVar xBinder] H2010Core.intTy)
        H2010Core.intTy
    )

stgRecursiveBinder :: H2010STG.STGBinder
stgRecursiveBinder =
  stgBinder "x" 5180 H2010Core.intTy

stgBlackHoleProgram :: H2010STG.STGProgram
stgBlackHoleProgram =
  H2010STG.STGProgram
    Map.empty
    [ H2010STG.STGRec
        [ ( stgRecursiveBinder
          , H2010STG.STGThunk H2010STG.Updatable (H2010STG.STGAtom (stgVar stgRecursiveBinder))
          )
        ]
    , stgThunkBinding stgMainBinder H2010STG.Updatable (H2010STG.STGAtom (stgVar stgRecursiveBinder))
    ]

expectCoreValidationError ::
  String ->
  (H2010CoreValidate.CoreValidationError -> Bool) ->
  Either [H2010CoreValidate.CoreValidationError] () ->
  Either String ()
expectCoreValidationError label predicate validation =
  case validation of
    Left errors
      | any predicate errors -> Right ()
      | otherwise -> Left (label <> "\nunexpected Core validation errors: " <> show errors)
    Right () -> Left (label <> "\nexpected Core validation failure")

isForallType :: H2010Core.CoreType -> Bool
isForallType = \case
  H2010Core.CTyForall {} -> True
  _ -> False

containsTypeLambda :: H2010Core.CoreExpr -> Bool
containsTypeLambda = \case
  H2010Core.CTypeLam {} -> True
  H2010Core.CLam _ body _ -> containsTypeLambda body
  H2010Core.CApp callee arg _ -> containsTypeLambda callee || containsTypeLambda arg
  H2010Core.CTypeApp callee _ _ -> containsTypeLambda callee
  H2010Core.CLet bind body _ -> bindContainsTypeLambda bind || containsTypeLambda body
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsTypeLambda scrutinee || any altContainsTypeLambda alternatives
  H2010Core.CCoerce expression _ -> containsTypeLambda expression
  H2010Core.CPrimOp _ arguments _ -> any containsTypeLambda arguments
  _ -> False

containsTermLambda :: H2010Core.CoreExpr -> Bool
containsTermLambda = \case
  H2010Core.CLam {} -> True
  H2010Core.CApp callee arg _ -> containsTermLambda callee || containsTermLambda arg
  H2010Core.CTypeLam _ body _ -> containsTermLambda body
  H2010Core.CTypeApp callee _ _ -> containsTermLambda callee
  H2010Core.CLet bind body _ -> bindContainsTermLambda bind || containsTermLambda body
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsTermLambda scrutinee || any altContainsTermLambda alternatives
  H2010Core.CCoerce expression _ -> containsTermLambda expression
  H2010Core.CPrimOp _ arguments _ -> any containsTermLambda arguments
  _ -> False

bindContainsTypeLambda :: H2010Core.CoreBind -> Bool
bindContainsTypeLambda = \case
  H2010Core.CoreNonRec _ rhs -> containsTypeLambda rhs
  H2010Core.CoreRec pairs -> any (containsTypeLambda . snd) pairs

bindContainsTermLambda :: H2010Core.CoreBind -> Bool
bindContainsTermLambda = \case
  H2010Core.CoreNonRec _ rhs -> containsTermLambda rhs
  H2010Core.CoreRec pairs -> any (containsTermLambda . snd) pairs

altContainsTypeLambda :: H2010Core.CoreAlt -> Bool
altContainsTypeLambda (H2010Core.CoreAlt _ _ body) =
  containsTypeLambda body

altContainsTermLambda :: H2010Core.CoreAlt -> Bool
altContainsTermLambda (H2010Core.CoreAlt _ _ body) =
  containsTermLambda body

containsCase :: H2010Core.CoreExpr -> Bool
containsCase = \case
  H2010Core.CCase {} -> True
  H2010Core.CLam _ body _ -> containsCase body
  H2010Core.CApp callee arg _ -> containsCase callee || containsCase arg
  H2010Core.CTypeLam _ body _ -> containsCase body
  H2010Core.CTypeApp callee _ _ -> containsCase callee
  H2010Core.CLet bind body _ -> bindContainsCase bind || containsCase body
  H2010Core.CCoerce expression _ -> containsCase expression
  H2010Core.CPrimOp _ arguments _ -> any containsCase arguments
  _ -> False

bindContainsCase :: H2010Core.CoreBind -> Bool
bindContainsCase = \case
  H2010Core.CoreNonRec _ rhs -> containsCase rhs
  H2010Core.CoreRec pairs -> any (containsCase . snd) pairs

countCases :: H2010Core.CoreExpr -> Int
countCases = \case
  H2010Core.CCase scrutinee _ alternatives _ ->
    1 + countCases scrutinee + sum (map altCountCases alternatives)
  H2010Core.CLam _ body _ -> countCases body
  H2010Core.CApp callee arg _ -> countCases callee + countCases arg
  H2010Core.CTypeLam _ body _ -> countCases body
  H2010Core.CTypeApp callee _ _ -> countCases callee
  H2010Core.CLet bind body _ -> bindCountCases bind + countCases body
  H2010Core.CCoerce expression _ -> countCases expression
  H2010Core.CPrimOp _ arguments _ -> sum (map countCases arguments)
  _ -> 0

bindCountCases :: H2010Core.CoreBind -> Int
bindCountCases = \case
  H2010Core.CoreNonRec _ rhs -> countCases rhs
  H2010Core.CoreRec pairs -> sum (map (countCases . snd) pairs)

countCasesInModule :: H2010Core.CoreModule -> Int
countCasesInModule =
  sum . map bindCountCases . H2010Core.coreModuleBinds

altCountCases :: H2010Core.CoreAlt -> Int
altCountCases (H2010Core.CoreAlt _ _ body) =
  countCases body

containsConstructorAlt :: Text -> H2010Core.CoreExpr -> Bool
containsConstructorAlt occurrence = \case
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsConstructorAlt occurrence scrutinee
      || any (altContainsConstructorAlt occurrence) alternatives
  H2010Core.CLam _ body _ -> containsConstructorAlt occurrence body
  H2010Core.CApp callee arg _ -> containsConstructorAlt occurrence callee || containsConstructorAlt occurrence arg
  H2010Core.CTypeLam _ body _ -> containsConstructorAlt occurrence body
  H2010Core.CTypeApp callee _ _ -> containsConstructorAlt occurrence callee
  H2010Core.CLet bind body _ -> bindContainsConstructorAlt occurrence bind || containsConstructorAlt occurrence body
  H2010Core.CCoerce expression _ -> containsConstructorAlt occurrence expression
  H2010Core.CPrimOp _ arguments _ -> any (containsConstructorAlt occurrence) arguments
  _ -> False

containsConstructorExpr :: Text -> H2010Core.CoreExpr -> Bool
containsConstructorExpr occurrence = \case
  H2010Core.CCon name _ ->
    H2010Names.nameOcc name == occurrence
  H2010Core.CLam _ body _ -> containsConstructorExpr occurrence body
  H2010Core.CApp callee arg _ -> containsConstructorExpr occurrence callee || containsConstructorExpr occurrence arg
  H2010Core.CTypeLam _ body _ -> containsConstructorExpr occurrence body
  H2010Core.CTypeApp callee _ _ -> containsConstructorExpr occurrence callee
  H2010Core.CLet bind body _ -> bindContainsConstructorExpr occurrence bind || containsConstructorExpr occurrence body
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsConstructorExpr occurrence scrutinee || any (altContainsConstructorExpr occurrence) alternatives
  H2010Core.CCoerce expression _ -> containsConstructorExpr occurrence expression
  H2010Core.CPrimOp _ arguments _ -> any (containsConstructorExpr occurrence) arguments
  _ -> False

bindContainsConstructorExpr :: Text -> H2010Core.CoreBind -> Bool
bindContainsConstructorExpr occurrence = \case
  H2010Core.CoreNonRec _ rhs -> containsConstructorExpr occurrence rhs
  H2010Core.CoreRec pairs -> any (containsConstructorExpr occurrence . snd) pairs

altContainsConstructorExpr :: Text -> H2010Core.CoreAlt -> Bool
altContainsConstructorExpr occurrence (H2010Core.CoreAlt _ _ body) =
  containsConstructorExpr occurrence body

coreModuleContainsStringLiteral :: H2010Core.CoreModule -> Bool
coreModuleContainsStringLiteral =
  any bindContainsStringLiteral . H2010Core.coreModuleBinds

bindContainsStringLiteral :: H2010Core.CoreBind -> Bool
bindContainsStringLiteral = \case
  H2010Core.CoreNonRec _ rhs -> containsStringLiteral rhs
  H2010Core.CoreRec pairs -> any (containsStringLiteral . snd) pairs

containsStringLiteral :: H2010Core.CoreExpr -> Bool
containsStringLiteral = \case
  H2010Core.CLit (H2010.LString {}) _ ->
    True
  H2010Core.CLam _ body _ ->
    containsStringLiteral body
  H2010Core.CApp callee arg _ ->
    containsStringLiteral callee || containsStringLiteral arg
  H2010Core.CTypeLam _ body _ ->
    containsStringLiteral body
  H2010Core.CTypeApp callee _ _ ->
    containsStringLiteral callee
  H2010Core.CLet bind body _ ->
    bindContainsStringLiteral bind || containsStringLiteral body
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsStringLiteral scrutinee || any altContainsStringLiteral alternatives
  H2010Core.CCoerce expression _ ->
    containsStringLiteral expression
  H2010Core.CPrimOp _ arguments _ ->
    any containsStringLiteral arguments
  _ ->
    False

altContainsStringLiteral :: H2010Core.CoreAlt -> Bool
altContainsStringLiteral (H2010Core.CoreAlt _ _ body) =
  containsStringLiteral body

containsCoerce :: H2010Core.CoreExpr -> Bool
containsCoerce = \case
  H2010Core.CCoerce _ _ -> True
  H2010Core.CLam _ body _ -> containsCoerce body
  H2010Core.CApp callee arg _ -> containsCoerce callee || containsCoerce arg
  H2010Core.CTypeLam _ body _ -> containsCoerce body
  H2010Core.CTypeApp callee _ _ -> containsCoerce callee
  H2010Core.CLet bind body _ -> bindContainsCoerce bind || containsCoerce body
  H2010Core.CCase scrutinee _ alternatives _ ->
    containsCoerce scrutinee || any altContainsCoerce alternatives
  H2010Core.CPrimOp _ arguments _ -> any containsCoerce arguments
  _ -> False

bindContainsCoerce :: H2010Core.CoreBind -> Bool
bindContainsCoerce = \case
  H2010Core.CoreNonRec _ rhs -> containsCoerce rhs
  H2010Core.CoreRec pairs -> any (containsCoerce . snd) pairs

altContainsCoerce :: H2010Core.CoreAlt -> Bool
altContainsCoerce (H2010Core.CoreAlt _ _ body) =
  containsCoerce body

bindContainsConstructorAlt :: Text -> H2010Core.CoreBind -> Bool
bindContainsConstructorAlt occurrence = \case
  H2010Core.CoreNonRec _ rhs -> containsConstructorAlt occurrence rhs
  H2010Core.CoreRec pairs -> any (containsConstructorAlt occurrence . snd) pairs

altContainsConstructorAlt :: Text -> H2010Core.CoreAlt -> Bool
altContainsConstructorAlt occurrence (H2010Core.CoreAlt altCon _ body) =
  case altCon of
    H2010Core.ConstructorAlt name ->
      H2010Names.nameOcc name == occurrence || containsConstructorAlt occurrence body
    _ ->
      containsConstructorAlt occurrence body

containsConstructorOccurrence :: Text -> H2010Core.CoreModule -> Bool
containsConstructorOccurrence occurrence coreModule =
  any ((== occurrence) . H2010Names.nameOcc) (Map.keys (H2010Core.coreModuleConstructors coreModule))

containsBindingOccurrence :: Text -> H2010Core.CoreModule -> Bool
containsBindingOccurrence occurrence coreModule =
  any ((== occurrence) . H2010Names.nameOcc . H2010Core.coreBinderName) (concatMap H2010Core.bindersOf (H2010Core.coreModuleBinds coreModule))

lookupCoreBindingOccurrence :: Text -> H2010Core.CoreModule -> Either String (H2010Core.CoreBinder, H2010Core.CoreExpr)
lookupCoreBindingOccurrence occurrence coreModule =
  case List.find ((== occurrence) . H2010Names.nameOcc . H2010Core.coreBinderName . fst) (concatMap coreBindPairs (H2010Core.coreModuleBinds coreModule)) of
    Just pair -> Right pair
    Nothing -> Left ("missing Core binding `" <> Text.unpack occurrence <> "`")

coreBindPairs :: H2010Core.CoreBind -> [(H2010Core.CoreBinder, H2010Core.CoreExpr)]
coreBindPairs = \case
  H2010Core.CoreNonRec binder rhs -> [(binder, rhs)]
  H2010Core.CoreRec pairs -> pairs

coreModuleHasRecursiveOccurrences :: [Text] -> H2010Core.CoreModule -> Bool
coreModuleHasRecursiveOccurrences occurrences coreModule =
  any recContainsAll (H2010Core.coreModuleBinds coreModule)
 where
  wanted = Set.fromList occurrences

  recContainsAll = \case
    H2010Core.CoreRec pairs ->
      wanted `Set.isSubsetOf` Set.fromList [H2010Names.nameOcc (H2010Core.coreBinderName binder) | (binder, _) <- pairs]
    H2010Core.CoreNonRec {} ->
      False

containsBindingPrefix :: Text -> H2010Core.CoreModule -> Bool
containsBindingPrefix prefix coreModule =
  any (Text.isPrefixOf prefix . H2010Names.nameOcc . H2010Core.coreBinderName) (concatMap H2010Core.bindersOf (H2010Core.coreModuleBinds coreModule))

containsVarOccurrence :: Text -> H2010Core.CoreExpr -> Bool
containsVarOccurrence occurrence = \case
  H2010Core.CVar name _ ->
    H2010Names.nameOcc name == occurrence
  H2010Core.CLam binder body _ ->
    H2010Names.nameOcc (H2010Core.coreBinderName binder) /= occurrence
      && containsVarOccurrence occurrence body
  H2010Core.CApp callee arg _ ->
    containsVarOccurrence occurrence callee || containsVarOccurrence occurrence arg
  H2010Core.CTypeLam _ body _ ->
    containsVarOccurrence occurrence body
  H2010Core.CTypeApp callee _ _ ->
    containsVarOccurrence occurrence callee
  H2010Core.CLet bind body _ ->
    bindContainsVarOccurrence occurrence bind || containsVarOccurrence occurrence body
  H2010Core.CCase scrutinee binder alternatives _ ->
    containsVarOccurrence occurrence scrutinee
      || ( H2010Names.nameOcc (H2010Core.coreBinderName binder) /= occurrence
             && any (altContainsVarOccurrence occurrence) alternatives
         )
  H2010Core.CCoerce expression _ ->
    containsVarOccurrence occurrence expression
  H2010Core.CPrimOp _ arguments _ ->
    any (containsVarOccurrence occurrence) arguments
  _ ->
    False

bindContainsVarOccurrence :: Text -> H2010Core.CoreBind -> Bool
bindContainsVarOccurrence occurrence = \case
  H2010Core.CoreNonRec _ rhs ->
    containsVarOccurrence occurrence rhs
  H2010Core.CoreRec pairs ->
    any (containsVarOccurrence occurrence . snd) pairs

moduleContainsVarOccurrence :: Text -> H2010Core.CoreModule -> Bool
moduleContainsVarOccurrence occurrence =
  any (bindContainsVarOccurrence occurrence) . H2010Core.coreModuleBinds

altContainsVarOccurrence :: Text -> H2010Core.CoreAlt -> Bool
altContainsVarOccurrence occurrence (H2010Core.CoreAlt _ binders body) =
  all ((/= occurrence) . H2010Names.nameOcc . H2010Core.coreBinderName) binders
    && containsVarOccurrence occurrence body

countTypeApps :: H2010Core.CoreExpr -> Int
countTypeApps = \case
  H2010Core.CTypeApp callee _ _ -> 1 + countTypeApps callee
  H2010Core.CLam _ body _ -> countTypeApps body
  H2010Core.CApp callee arg _ -> countTypeApps callee + countTypeApps arg
  H2010Core.CTypeLam _ body _ -> countTypeApps body
  H2010Core.CLet bind body _ -> bindCountTypeApps bind + countTypeApps body
  H2010Core.CCase scrutinee _ alternatives _ ->
    countTypeApps scrutinee + sum (map altCountTypeApps alternatives)
  H2010Core.CCoerce expression _ -> countTypeApps expression
  H2010Core.CPrimOp _ arguments _ -> sum (map countTypeApps arguments)
  _ -> 0

bindCountTypeApps :: H2010Core.CoreBind -> Int
bindCountTypeApps = \case
  H2010Core.CoreNonRec _ rhs -> countTypeApps rhs
  H2010Core.CoreRec pairs -> sum (map (countTypeApps . snd) pairs)

altCountTypeApps :: H2010Core.CoreAlt -> Int
altCountTypeApps (H2010Core.CoreAlt _ _ body) =
  countTypeApps body

factsFor :: Text -> Either String [Fact]
factsFor source =
  inferFacts . toANF <$> parseExpr source

letNames :: AExpr -> [Name]
letNames = \case
  AAtom {} -> []
  APrim {} -> []
  AIf _ thenBranch elseBranch -> letNames thenBranch <> letNames elseBranch
  ALam _ _ body -> letNames body
  AApp {} -> []
  ACall {} -> []
  ALet letName rhs body -> letName : letNames rhs <> letNames body

observeSourceValue :: Value -> Either String ObservedValue
observeSourceValue = \case
  VInt n -> Right (ObservedInt (hintToInteger n))
  VBool b -> Right (ObservedBool b)
  VClosure {} -> Left "semantic preservation test cannot compare function results"

observeANFValue :: ANFValue -> Either String ObservedValue
observeANFValue = \case
  ANFVInt n -> Right (ObservedInt (hintToInteger n))
  ANFVBool b -> Right (ObservedBool b)
  ANFVClosure {} -> Left "semantic preservation test cannot compare function results"

data ObservedValue
  = ObservedInt Integer
  | ObservedBool Bool
  deriving stock (Show, Eq)

expectEqual :: (Eq a, Show a) => String -> a -> a -> Either String ()
expectEqual label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left $
        label
          <> "\nexpected: "
          <> show expected
          <> "\nactual:   "
          <> show actual

expectEqualText :: String -> Text -> Text -> Either String ()
expectEqualText label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left $
        label
          <> "\nexpected:\n"
          <> Text.unpack expected
          <> "\nactual:\n"
          <> Text.unpack actual

assertBool :: String -> Bool -> Either String ()
assertBool label condition =
  if condition
    then Right ()
    else Left label

unique :: Ord a => [a] -> [a]
unique =
  Map.keys . foldr (`Map.insert` ()) Map.empty

isLam :: CoreNode -> Bool
isLam = \case
  CLam {} -> True
  _ -> False

isApp :: CoreNode -> Bool
isApp = \case
  CApp {} -> True
  _ -> False

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f = \case
  Left err -> Left (f err)
  Right value -> Right value

showText :: Text -> String
showText =
  Text.unpack

hint :: Integer -> HInt
hint =
  unsafeHIntLiteral

sourceInt :: Integer -> Value
sourceInt =
  VInt . hint

anfInt :: Integer -> ANFValue
anfInt =
  ANFVInt . hint

knownInt :: Integer -> EV.ConstInt
knownInt =
  EV.KnownInt . hint

backendInt :: Integer -> B.BackendAtom
backendInt =
  B.BInt . hint

mkName :: Text -> Name
mkName =
  Name

xName :: Name
xName =
  mkName "x"

examplePaths :: [FilePath]
examplePaths =
  [ "examples/test.hg"
  , "examples/if.hg"
  , "examples/let-bool.hg"
  , "examples/inc.hg"
  , "examples/add.hg"
  , "examples/higher-order.hg"
  ]

supportedEGraphSources :: [Text]
supportedEGraphSources =
  [ "1 + 0"
  , "0 + 4"
  , "3 * 1"
  , "0 * 99"
  , "if true then 1 + 0 else 2 * 0"
  , "let x = 7 in x * 1"
  ]

supportedEgglogSources :: [Text]
supportedEgglogSources =
  [ "1 + 0"
  , "0 + 4"
  , "3 * 1"
  , "0 * 99"
  , "if true then 1 + 0 else 2 * 0"
  , "let x = 2 + 3 in x * 4"
  , "let x = 10 - 3 in x + 1"
  , "let x = 8 / 2 in x + 1"
  , "let b = true in if b then 10 else 20"
  ]

llvmExecutionExamples :: [(FilePath, String)]
llvmExecutionExamples =
  [ ("examples/llvm/arithmetic.hg", "14\n")
  , ("examples/llvm/if-true.hg", "10\n")
  , ("examples/llvm/if-comparison.hg", "6\n")
  , ("examples/llvm/nested-if.hg", "2\n")
  , ("examples/llvm/let-chain.hg", "21\n")
  , ("examples/llvm/bool-root.hg", "1\n")
  , ("examples/llvm/top-level.hg", "42\n")
  , ("examples/llvm/division.hg", "5\n")
  ]

data NativeExample = NativeExample
  { nativeExampleName :: FilePath
  , nativeExamplePath :: FilePath
  , nativeExampleStdout :: String
  , nativeExampleUseEgglog :: Bool
  }
  deriving stock (Show, Eq)

nativeExecutionExamples :: [NativeExample]
nativeExecutionExamples =
  [ NativeExample "arithmetic" "examples/llvm/arithmetic.hg" "14\n" True
  , NativeExample "if-comparison" "examples/llvm/if-comparison.hg" "6\n" True
  , NativeExample "division" "examples/llvm/division.hg" "5\n" True
  , NativeExample "bool-root" "examples/llvm/bool-root.hg" "1\n" True
  , NativeExample "division-no-egglog" "examples/llvm/division.hg" "5\n" False
  ]

llvmDifferentialSources :: [Text]
llvmDifferentialSources =
  [ "0"
  , "true"
  , "false"
  , liftedIncSource
  , "let add = \\x : Int -> \\y : Int -> x + y in add 3 4"
  , "(\\x : Int -> x * 2) 21"
  , "let x = 1 in let f = \\y : Int -> x + y in f 2"
  , "let makeAdder = \\x : Int -> \\y : Int -> x + y in let add10 = makeAdder 10 in add10 32"
  , higherOrderSource
  , "1 + 2 * 3"
  , "let x = 10 in let y = x - 4 in y * 3"
  , "if 3 < 4 then 11 else 22"
  , "if 4 < 3 then 11 else 22"
  , "let b = 1 == 1 in if b then 41 + 1 else 0"
  , "let b = false == (1 < 0) in if b then 7 else 9"
  , "let x = 5 in if x == 5 then if x < 10 then x * x else 0 else 1"
  , "let x = 9223372036854775807 in x - 7"
  , "(0 - 3) / 2"
  , "let x = 20 in let y = 4 in x / y"
  , "let x = 20 in let f = \\y : Int -> x / y in f 4"
  ]

data LLVMOverflowCase = LLVMOverflowCase
  { overflowName :: Text
  , overflowSource :: Text
  , overflowOperator :: BinOp
  , overflowIntrinsic :: Text
  }

llvmOverflowCases :: [LLVMOverflowCase]
llvmOverflowCases =
  [ LLVMOverflowCase
      { overflowName = "add"
      , overflowSource = Text.pack (show maxHIntInteger <> " + 1")
      , overflowOperator = Add
      , overflowIntrinsic = "@llvm.sadd.with.overflow.i64"
      }
  , LLVMOverflowCase
      { overflowName = "sub"
      , overflowSource = "let minish = 0 - 9223372036854775807 in minish - 2"
      , overflowOperator = Sub
      , overflowIntrinsic = "@llvm.ssub.with.overflow.i64"
      }
  , LLVMOverflowCase
      { overflowName = "mul"
      , overflowSource = "3037000500 * 3037000500"
      , overflowOperator = Mul
      , overflowIntrinsic = "@llvm.smul.with.overflow.i64"
      }
  ]

incSource :: Text
incSource =
  "let inc = \\x : Int -> x + 1 in\ninc 41"

addSource :: Text
addSource =
  "let add = \\x : Int -> \\y : Int -> x + y in\nadd 3 4"

higherOrderSource :: Text
higherOrderSource =
  "let applyTwice = \\f : (Int -> Int) -> \\x : Int -> f (f x) in\n\
  \let inc = \\n : Int -> n + 1 in\n\
  \applyTwice inc 40"

liftedIncSource :: Text
liftedIncSource =
  "let inc = \\x : Int -> x + 1 in inc 41"

topLevelSource :: Text
topLevelSource =
  "def inc(x : Int) : Int = x + 1;\n\
  \def double(x : Int) : Int = x * 2;\n\
  \double (inc 20)"

divisionOverflowSource :: Text
divisionOverflowSource =
  "let min_int = (0 - 9223372036854775807) - 1 in\n\
  \let neg_one = 0 - 1 in\n\
  \min_int / neg_one"
