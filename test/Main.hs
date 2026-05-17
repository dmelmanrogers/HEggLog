module Main (main) where

import Analysis.Facts
import Analysis.InferFacts (inferFacts)
import CLI.Report (compileReport, renderGoldenReport)
import Control.Monad (unless)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Eval.ANFInterpreter (ANFValue (..), evalANF)
import Eval.Interpreter (Value (..), eval, renderRuntimeError)
import IR.ANF
import IR.ANF.Validate
import IR.Core (CoreNode (..), CoreProgram (..), lower)
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
