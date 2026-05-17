module Optimize.EGraph
  ( EClassId (..)
  , EGraph (..)
  , EGraphError (..)
  , EGraphResult (..)
  , ENode (..)
  , addENode
  , emptyEGraph
  , extractCheapest
  , findClass
  , insertANF
  , optimizeANF
  , rebuild
  , renderEGraphError
  , saturate
  , unionClasses
  )
where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import IR.ANF
import IR.ANF.Validate
import Runtime.Int (HInt, addHInt, hintToInteger, mkHIntLiteral, mulHInt)
import Syntax.AST (BinOp (..), Name (..))
import Syntax.Pretty (prettyName, renderDoc)

newtype EClassId = EClassId {unEClassId :: Int}
  deriving stock (Show, Eq, Ord)

data ENode
  = EInt Integer
  | EBool Bool
  | EVar Name
  | EAdd EClassId EClassId
  | EMul EClassId EClassId
  | EIf EClassId EClassId EClassId
  deriving stock (Show, Eq, Ord)

data EGraph = EGraph
  { nextClassId :: Int
  , parents :: Map.Map EClassId EClassId
  , classNodes :: Map.Map EClassId (Set.Set ENode)
  , memo :: Map.Map ENode EClassId
  }
  deriving stock (Show, Eq)

data EGraphError
  = UnsupportedLambda Name
  | UnsupportedApplication Atom Atom
  | UnsupportedDirectCall Name
  | UnsupportedPrimitive BinOp
  | UnsupportedLetBinding Name
  | MissingEClass EClassId
  | ExtractionFailed EClassId
  | ExtractedInvalidANF ANFValidationError
  | SaturationDidNotConverge Int
  deriving stock (Show, Eq, Ord)

data EGraphResult = EGraphResult
  { egraphOptimizedANF :: AExpr
  , egraphRewriteCount :: Int
  , egraphClassCount :: Int
  }
  deriving stock (Show, Eq, Ord)

data BuiltExpr
  = BuiltAtom Atom
  | BuiltExpr AExpr
  deriving stock (Show, Eq, Ord)

data RewriteTarget
  = ExistingClass EClassId
  | NewNode ENode
  deriving stock (Show, Eq, Ord)

type Cost = Int

emptyEGraph :: EGraph
emptyEGraph =
  EGraph
    { nextClassId = 0
    , parents = Map.empty
    , classNodes = Map.empty
    , memo = Map.empty
    }

-- Report-only prototype: lambdas and applications stay outside this isolated
-- e-graph backend until binder-aware equality saturation is designed.
optimizeANF :: AExpr -> Either EGraphError EGraphResult
optimizeANF expression = do
  result <- optimizeExpr expression
  mapValidationError (validateANF (egraphOptimizedANF result))
  pure result

optimizeExpr :: AExpr -> Either EGraphError EGraphResult
optimizeExpr = \case
  ALet name rhs body -> do
    rhsResult <- optimizeExpr rhs
    bodyResult <- optimizeExpr body
    pure
      EGraphResult
        { egraphOptimizedANF =
            ALet name (egraphOptimizedANF rhsResult) (egraphOptimizedANF bodyResult)
        , egraphRewriteCount = egraphRewriteCount rhsResult + egraphRewriteCount bodyResult
        , egraphClassCount = egraphClassCount rhsResult + egraphClassCount bodyResult
        }
  ALam name _ _ ->
    Left (UnsupportedLambda name)
  AApp fn arg ->
    Left (UnsupportedApplication fn arg)
  ACall callee _ ->
    Left (UnsupportedDirectCall callee)
  expression -> do
    ensureSupported expression
    optimizeFirstOrder expression

optimizeFirstOrder :: AExpr -> Either EGraphError EGraphResult
optimizeFirstOrder expression = do
  let (rootId, graph) = insertANF expression emptyEGraph
  saturated <- saturate graph
  optimized <- extractCheapest saturated rootId
  pure
    EGraphResult
      { egraphOptimizedANF = optimized
      , egraphRewriteCount = rewriteCount graph saturated
      , egraphClassCount = Map.size (rootClasses saturated)
      }

insertANF :: AExpr -> EGraph -> (EClassId, EGraph)
insertANF expression graph =
  case expression of
    AAtom atom ->
      insertAtom atom graph
    APrim Add lhs rhs ->
      insertBinary EAdd lhs rhs graph
    APrim Mul lhs rhs ->
      insertBinary EMul lhs rhs graph
    APrim op lhs rhs ->
      insertUnsupportedPrimitiveAsVar op lhs rhs graph
    AIf cond thenBranch elseBranch ->
      let (condId, graph1) = insertAtom cond graph
          (thenId, graph2) = insertANF thenBranch graph1
          (elseId, graph3) = insertANF elseBranch graph2
       in addENode (EIf condId thenId elseId) graph3
    ALet name _ _ ->
      addENode (EVar name) graph
    ALam name _ _ ->
      addENode (EVar name) graph
    AApp fn _ ->
      case fn of
        AVar name -> addENode (EVar name) graph
        AInt n -> addENode (EInt n) graph
        ABool b -> addENode (EBool b) graph
    ACall callee _ ->
      addENode (EVar callee) graph

insertAtom :: Atom -> EGraph -> (EClassId, EGraph)
insertAtom atom =
  addENode $
    case atom of
      AVar name -> EVar name
      AInt n -> EInt n
      ABool b -> EBool b

insertBinary :: (EClassId -> EClassId -> ENode) -> Atom -> Atom -> EGraph -> (EClassId, EGraph)
insertBinary node lhs rhs graph =
  let (lhsId, graph1) = insertAtom lhs graph
      (rhsId, graph2) = insertAtom rhs graph1
   in addENode (node lhsId rhsId) graph2

insertUnsupportedPrimitiveAsVar :: BinOp -> Atom -> Atom -> EGraph -> (EClassId, EGraph)
insertUnsupportedPrimitiveAsVar op lhs rhs =
  addENode (EVar (Name ("unsupported_" <> Text.pack (show (op, lhs, rhs)))))

addENode :: ENode -> EGraph -> (EClassId, EGraph)
addENode node graph =
  let canonicalNode = canonicalizeNode graph node
   in case Map.lookup canonicalNode (memo graph) of
        Just existing ->
          (findClass graph existing, graph)
        Nothing ->
          let classId = EClassId (nextClassId graph)
              graph' =
                graph
                  { nextClassId = nextClassId graph + 1
                  , parents = Map.insert classId classId (parents graph)
                  , classNodes = Map.insert classId (Set.singleton canonicalNode) (classNodes graph)
                  , memo = Map.insert canonicalNode classId (memo graph)
                  }
           in (classId, graph')

findClass :: EGraph -> EClassId -> EClassId
findClass graph classId =
  case Map.lookup classId (parents graph) of
    Just parent
      | parent /= classId -> findClass graph parent
    _ -> classId

unionClasses :: EClassId -> EClassId -> EGraph -> EGraph
unionClasses lhs rhs graph
  | lhsRoot == rhsRoot = graph
  | otherwise =
      rebuild
        graph
          { parents = Map.insert rhsRoot lhsRoot (parents graph)
          , classNodes =
              Map.insert lhsRoot mergedNodes $
                Map.delete rhsRoot (classNodes graph)
          }
 where
  lhsRoot = findClass graph lhs
  rhsRoot = findClass graph rhs
  mergedNodes =
    Map.findWithDefault Set.empty lhsRoot (classNodes graph)
      <> Map.findWithDefault Set.empty rhsRoot (classNodes graph)

rebuild :: EGraph -> EGraph
rebuild graph =
  rebuildCongruence rebuiltMemoGraph
 where
  rootNodePairs =
    [ (findClass graph classId, canonicalizeNode graph node)
    | (classId, nodes) <- Map.toList (classNodes graph)
    , node <- Set.toList nodes
    ]
  rebuiltClasses =
    Map.fromListWith (<>) [(root, Set.singleton node) | (root, node) <- rootNodePairs]
  rebuiltMemo =
    Map.fromListWith chooseRoot [(node, root) | (root, node) <- rootNodePairs]
  rebuiltMemoGraph =
    graph
      { classNodes = rebuiltClasses
      , memo = rebuiltMemo
      }
  chooseRoot lhs rhs =
    min (findClass graph lhs) (findClass graph rhs)

rebuildCongruence :: EGraph -> EGraph
rebuildCongruence graph =
  case duplicateCongruence graph of
    Nothing -> graph
    Just (lhs, rhs) -> rebuild (unionClasses lhs rhs graph)

duplicateCongruence :: EGraph -> Maybe (EClassId, EClassId)
duplicateCongruence graph =
  findDuplicate Map.empty $
    [ (node, classId)
    | (classId, nodes) <- Map.toList (classNodes graph)
    , node <- Set.toList nodes
    ]
 where
  findDuplicate _ [] =
    Nothing
  findDuplicate seen ((node, classId) : rest) =
    case Map.lookup node seen of
      Just previous
        | previous /= classId -> Just (previous, classId)
      _ -> findDuplicate (Map.insert node classId seen) rest

canonicalizeNode :: EGraph -> ENode -> ENode
canonicalizeNode graph = \case
  EInt n -> EInt n
  EBool b -> EBool b
  EVar name -> EVar name
  EAdd lhs rhs -> EAdd (findClass graph lhs) (findClass graph rhs)
  EMul lhs rhs -> EMul (findClass graph lhs) (findClass graph rhs)
  EIf cond thenBranch elseBranch ->
    EIf (findClass graph cond) (findClass graph thenBranch) (findClass graph elseBranch)

saturate :: EGraph -> Either EGraphError EGraph
saturate =
  loop 0
 where
  loop iteration graph
    | iteration > maxIterations =
        Left (SaturationDidNotConverge maxIterations)
    | otherwise =
        let (changed, graph') = rewriteOnce graph
            rebuilt = rebuild graph'
         in if changed
              then loop (iteration + 1) rebuilt
              else Right rebuilt

  maxIterations = 32

rewriteOnce :: EGraph -> (Bool, EGraph)
rewriteOnce graph =
  foldl applyNode (False, graph) nodePairs
 where
  nodePairs =
    [ (classId, node)
    | (classId, nodes) <- Map.toList (rootClasses graph)
    , node <- Set.toList nodes
    ]

  applyNode (changed, currentGraph) (classId, node) =
    let (nodeChanged, graph') = rewriteNode classId node currentGraph
     in (changed || nodeChanged, graph')

rewriteNode :: EClassId -> ENode -> EGraph -> (Bool, EGraph)
rewriteNode classId node graph =
  foldl applyRewrite (False, graph) (rewriteTargets node graph)
 where
  applyRewrite (changed, currentGraph) target =
    let (targetRoot, graphWithTarget) =
          case target of
            ExistingClass targetId ->
              (findClass currentGraph targetId, currentGraph)
            NewNode targetNode ->
              let (targetId, graph') = addENode targetNode currentGraph
               in (findClass graph' targetId, graph')
        beforeRoot = findClass graphWithTarget classId
        unioned = unionClasses beforeRoot targetRoot graphWithTarget
     in (changed || beforeRoot /= targetRoot, unioned)

rewriteTargets :: ENode -> EGraph -> [RewriteTarget]
rewriteTargets node graph =
  case node of
    EAdd lhs rhs ->
      addTargets lhs rhs graph
    EMul lhs rhs ->
      mulTargets lhs rhs graph
    EIf cond thenBranch elseBranch ->
      ifTargets cond thenBranch elseBranch graph
    EInt {} ->
      []
    EBool {} ->
      []
    EVar {} ->
      []

addTargets :: EClassId -> EClassId -> EGraph -> [RewriteTarget]
addTargets lhs rhs graph =
  concat
    [ [ExistingClass lhs | classContains (EInt 0) rhs graph]
    , [ExistingClass rhs | classContains (EInt 0) lhs graph]
    , [NewNode node | a <- intValues lhs graph, b <- intValues rhs graph, Just node <- [checkedIntNode addHInt a b]]
    ]

mulTargets :: EClassId -> EClassId -> EGraph -> [RewriteTarget]
mulTargets lhs rhs graph =
  concat
    [ [ExistingClass lhs | classContains (EInt 1) rhs graph]
    , [ExistingClass rhs | classContains (EInt 1) lhs graph]
    , [NewNode (EInt 0) | classContains (EInt 0) lhs graph || classContains (EInt 0) rhs graph]
    , [NewNode node | a <- intValues lhs graph, b <- intValues rhs graph, Just node <- [checkedIntNode mulHInt a b]]
    ]

checkedIntNode :: (HInt -> HInt -> Either err HInt) -> Integer -> Integer -> Maybe ENode
checkedIntNode op lhs rhs = do
  lhsInt <- either (const Nothing) Just (mkHIntLiteral lhs)
  rhsInt <- either (const Nothing) Just (mkHIntLiteral rhs)
  result <- either (const Nothing) Just (op lhsInt rhsInt)
  pure (EInt (hintToInteger result))

ifTargets :: EClassId -> EClassId -> EClassId -> EGraph -> [RewriteTarget]
ifTargets cond thenBranch elseBranch graph =
  concat
    [ [ExistingClass thenBranch | classContains (EBool True) cond graph]
    , [ExistingClass elseBranch | classContains (EBool False) cond graph]
    ]

classContains :: ENode -> EClassId -> EGraph -> Bool
classContains node classId graph =
  Set.member node $
    Map.findWithDefault Set.empty (findClass graph classId) (classNodes graph)

intValues :: EClassId -> EGraph -> [Integer]
intValues classId graph =
  [ n
  | EInt n <- Set.toList (Map.findWithDefault Set.empty (findClass graph classId) (classNodes graph))
  ]

extractCheapest :: EGraph -> EClassId -> Either EGraphError AExpr
extractCheapest graph root =
  case Map.lookup (findClass graph root) bestByClass of
    Just (_, built) ->
      pure (builtToExpr built)
    Nothing ->
      Left (ExtractionFailed root)
 where
  bestByClass = computeBest graph

computeBest :: EGraph -> Map.Map EClassId (Cost, BuiltExpr)
computeBest graph =
  iterateBest 0 Map.empty
 where
  classes = rootClasses graph
  iterateBest :: Int -> Map.Map EClassId (Cost, BuiltExpr) -> Map.Map EClassId (Cost, BuiltExpr)
  iterateBest iteration best
    | iteration > maxIterations = best
    | otherwise =
        let best' = foldl improveClass best (Map.toList classes)
         in if best' == best
              then best'
              else iterateBest (iteration + 1) best'
  maxIterations :: Int
  maxIterations = 64

  improveClass :: Map.Map EClassId (Cost, BuiltExpr) -> (EClassId, Set.Set ENode) -> Map.Map EClassId (Cost, BuiltExpr)
  improveClass best (classId, nodes) =
    case minimumCandidate [candidate best node | node <- Set.toList nodes] of
      Nothing ->
        best
      Just candidateResult ->
        Map.insertWith chooseCheaper classId candidateResult best

candidate :: Map.Map EClassId (Cost, BuiltExpr) -> ENode -> Maybe (Cost, BuiltExpr)
candidate best = \case
  EInt n ->
    Just (1, BuiltAtom (AInt n))
  EBool b ->
    Just (1, BuiltAtom (ABool b))
  EVar name
    -> Just (1, BuiltAtom (AVar name))
  EAdd lhs rhs -> do
    (lhsCost, lhsBuilt) <- Map.lookup lhs best
    (rhsCost, rhsBuilt) <- Map.lookup rhs best
    lhsAtom <- builtToAtom lhsBuilt
    rhsAtom <- builtToAtom rhsBuilt
    Just (1 + lhsCost + rhsCost, BuiltExpr (APrim Add lhsAtom rhsAtom))
  EMul lhs rhs -> do
    (lhsCost, lhsBuilt) <- Map.lookup lhs best
    (rhsCost, rhsBuilt) <- Map.lookup rhs best
    lhsAtom <- builtToAtom lhsBuilt
    rhsAtom <- builtToAtom rhsBuilt
    Just (2 + lhsCost + rhsCost, BuiltExpr (APrim Mul lhsAtom rhsAtom))
  EIf cond thenBranch elseBranch -> do
    (condCost, condBuilt) <- Map.lookup cond best
    (thenCost, thenBuilt) <- Map.lookup thenBranch best
    (elseCost, elseBuilt) <- Map.lookup elseBranch best
    condAtom <- builtToAtom condBuilt
    Just
      ( 1 + condCost + thenCost + elseCost
      , BuiltExpr (AIf condAtom (builtToExpr thenBuilt) (builtToExpr elseBuilt))
      )

builtToAtom :: BuiltExpr -> Maybe Atom
builtToAtom = \case
  BuiltAtom atom -> Just atom
  BuiltExpr (AAtom atom) -> Just atom
  BuiltExpr {} -> Nothing

builtToExpr :: BuiltExpr -> AExpr
builtToExpr = \case
  BuiltAtom atom -> AAtom atom
  BuiltExpr expression -> expression

minimumCandidate :: [Maybe (Cost, BuiltExpr)] -> Maybe (Cost, BuiltExpr)
minimumCandidate =
  foldr choose Nothing
 where
  choose Nothing best = best
  choose (Just candidateResult) Nothing = Just candidateResult
  choose (Just candidateResult) (Just best) = Just (chooseCheaper candidateResult best)

chooseCheaper :: (Cost, BuiltExpr) -> (Cost, BuiltExpr) -> (Cost, BuiltExpr)
chooseCheaper lhs rhs
  | fst lhs <= fst rhs = lhs
  | otherwise = rhs

rootClasses :: EGraph -> Map.Map EClassId (Set.Set ENode)
rootClasses graph =
  Map.fromListWith (<>) $
    [ (findClass graph classId, nodes)
    | (classId, nodes) <- Map.toList (classNodes graph)
    ]

rewriteCount :: EGraph -> EGraph -> Int
rewriteCount before after =
  Map.size (memo after) - Map.size (memo before)

mapValidationError :: Either ANFValidationError () -> Either EGraphError ()
mapValidationError = \case
  Left err -> Left (ExtractedInvalidANF err)
  Right () -> Right ()

renderEGraphError :: EGraphError -> Text
renderEGraphError = \case
  UnsupportedLambda name ->
    "unsupported e-graph fragment: lambda binding " <> renderDoc (prettyName name)
  UnsupportedApplication fn arg ->
    "unsupported e-graph fragment: application " <> Text.pack (show (fn, arg))
  UnsupportedDirectCall name ->
    "unsupported e-graph fragment: direct function call " <> renderDoc (prettyName name)
  UnsupportedPrimitive op ->
    "unsupported e-graph primitive: " <> Text.pack (show op)
  UnsupportedLetBinding name ->
    "unsupported e-graph fragment: let binding " <> renderDoc (prettyName name)
  MissingEClass classId ->
    "missing e-class: " <> Text.pack (show classId)
  ExtractionFailed classId ->
    "failed to extract e-class: " <> Text.pack (show classId)
  ExtractedInvalidANF err ->
    "e-graph extraction produced invalid ANF: " <> renderANFValidationError err
  SaturationDidNotConverge iterationLimit ->
    "e-graph saturation did not converge within " <> Text.pack (show iterationLimit) <> " iterations"

ensureSupported :: AExpr -> Either EGraphError ()
ensureSupported = \case
  AAtom {} ->
    Right ()
  APrim Add _ _ ->
    Right ()
  APrim Mul _ _ ->
    Right ()
  APrim op _ _ ->
    Left (UnsupportedPrimitive op)
  AIf _ thenBranch elseBranch -> do
    ensureSupported thenBranch
    ensureSupported elseBranch
  ALet name _ _ ->
    Left (UnsupportedLetBinding name)
  ALam name _ _ ->
    Left (UnsupportedLambda name)
  AApp fn arg ->
    Left (UnsupportedApplication fn arg)
  ACall callee _ ->
    Left (UnsupportedDirectCall callee)
