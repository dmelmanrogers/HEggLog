module Main (main) where

import Analysis.Facts
import Analysis.InferFacts (inferFacts)
import CLI.Report (compileReport, renderGoldenReport)
import Control.Monad (unless)
import qualified Data.Map.Strict as Map
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
import Eval.Interpreter (Value (..), eval, renderRuntimeError)
import IR.ANF
import IR.ANF.Validate
import IR.Core (CoreNode (..), CoreProgram (..), lower)
import qualified Optimize.EgglogBackend as OEB
import qualified Optimize.EGraph as EG
import Optimize.Rewrite
  ( RewriteDiagnostic (..)
  , RewriteRule (rewriteConditions)
  , checkRewriteConditions
  , divideSelfNonZero
  , matchRewriteRule
  )
import Optimize.Simplify
import Syntax.AST
import Syntax.Parser (parseProgram)
import System.Exit (exitFailure)
import Test.QuickCheck hiding (NonZero, label)
import Text.Megaparsec (errorBundlePretty)
import Typecheck.Infer (infer)
import Typecheck.Types (TypeError (..), renderTypeError)

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
      ]
  , TestGroup
      "Typechecker"
      [ pureTest "higher-order lambda annotation parses and types" testHigherOrderType
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
      ]
  , TestGroup
      "Interpreter"
      [ pureTest "inc example evaluates" (checkProgram incSource TInt (VInt 42))
      , pureTest "add example evaluates" (checkProgram addSource TInt (VInt 7))
      , pureTest "higher-order example evaluates" (checkProgram higherOrderSource TInt (VInt 42))
      , ioTest "source and ANF evaluation agree for examples" testExampleSemanticPreservation
      ]
  , TestGroup
      "ANF"
      [ pureTest "atomizes nested arithmetic" testANFNestedArithmetic
      , pureTest "fresh names are deterministic" testDeterministicFreshNames
      , pureTest "atomizes application arguments" testApplicationAtomization
      , pureTest "preserves lambdas" testLambdaPreservation
      , ioTest "validator accepts lowered examples" testValidateLoweredExamples
      , pureTest "validator reports unbound variables" testValidatorUnboundVariable
      , pureTest "validator reports duplicate generated temps" testValidatorDuplicateGeneratedTemp
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

testHigherOrderType :: Either String ()
testHigherOrderType = do
  parsed <- parseExpr "\\f : (Int -> Int) -> f 1"
  actualType <- mapLeft (showText . renderTypeError) (infer parsed)
  expectEqual "higher-order lambda type" (TFun (TFun TInt TInt) TInt) actualType

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

testExampleSemanticPreservation :: IO (Either String ())
testExampleSemanticPreservation =
  firstFailure checkExampleSemanticPreservation examplePaths

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
    Left (OEB.UnsupportedFeature _) -> Right ()
    other -> Left ("expected unsupported lambda error, got " <> show other)

egg :: Either EDB.EgglogError a -> Either String a
egg =
  mapLeft show

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

checkGolden :: FilePath -> FilePath -> IO (Either String ())
checkGolden sourcePath goldenPath = do
  source <- Text.IO.readFile sourcePath
  expected <- Text.IO.readFile goldenPath
  pure $ do
    report <- mapLeft show (compileReport sourcePath source)
    expectEqualText "golden output" expected (renderGoldenReport report)

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

newtype ClosedExpr = ClosedExpr Expr
  deriving stock (Show)

instance Arbitrary ClosedExpr where
  arbitrary =
    sized (fmap ClosedExpr . genClosedExpr)
  shrink (ClosedExpr expression) =
    ClosedExpr <$> shrinkClosedExpr expression

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
  ALet letName rhs body -> letName : letNames rhs <> letNames body

observeSourceValue :: Value -> Either String ObservedValue
observeSourceValue = \case
  VInt n -> Right (ObservedInt n)
  VBool b -> Right (ObservedBool b)
  VClosure {} -> Left "semantic preservation test cannot compare function results"

observeANFValue :: ANFValue -> Either String ObservedValue
observeANFValue = \case
  ANFVInt n -> Right (ObservedInt n)
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
