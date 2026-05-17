module Egglog.Extract
  ( ExtractedTerm (..)
  , extractCheapest
  , renderExtractedTerm
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Database
import Egglog.Function
import Egglog.Sort
import Egglog.Value

data ExtractedTerm
  = ExtractValue Value
  | ExtractCall FunctionName [ExtractedTerm]
  deriving stock (Show, Eq, Ord)

type Cost = Int

type BestMap = Map.Map (SortName, Id) (Cost, ExtractedTerm)

extractCheapest :: Database -> SortName -> Id -> Either EgglogError ExtractedTerm
extractCheapest db sortName ident =
  case Map.lookup target best of
    Just (_, term) -> Right term
    Nothing ->
      Left
        ( ExtractionError
            ( "no finite extraction for "
                <> renderValue (VId sortName (case canonicalValue db (VId sortName ident) of VId _ root -> root; _ -> ident))
            )
        )
 where
  target =
    case canonicalValue db (VId sortName ident) of
      VId canonicalSort canonicalId -> (canonicalSort, canonicalId)
      _ -> (sortName, ident)
  best = iterateBest (max 1 (length candidates + 1)) Map.empty
  candidates = extractionCandidates db

  iterateBest 0 bestMap =
    bestMap
  iterateBest remaining bestMap =
    let bestMap' = foldl relax bestMap candidates
     in if bestMap' == bestMap
          then bestMap
          else iterateBest (remaining - 1) bestMap'

  relax bestMap candidate =
    case candidateValue bestMap candidate of
      Nothing -> bestMap
      Just (key, entry) ->
        Map.insertWith chooseCheaper key entry bestMap

chooseCheaper :: (Cost, ExtractedTerm) -> (Cost, ExtractedTerm) -> (Cost, ExtractedTerm)
chooseCheaper lhs rhs =
  if lhs <= rhs then lhs else rhs

data Candidate = Candidate
  { candidateName :: FunctionName
  , candidateArgs :: [Value]
  , candidateOutput :: Value
  }
  deriving stock (Show, Eq, Ord)

extractionCandidates :: Database -> [Candidate]
extractionCandidates db =
  [ Candidate name (canonicalArgs db args) (canonicalValue db outValue)
  | (name, table) <- Map.toList (tables db)
  , decl <- maybeToList (Map.lookup name (declarations db))
  , isUserSort (functionResultSort decl)
  , (args, outValue) <- Map.toList table
  ]

candidateValue :: BestMap -> Candidate -> Maybe ((SortName, Id), (Cost, ExtractedTerm))
candidateValue bestMap candidate =
  case candidateOutput candidate of
    VId sortName ident -> do
      children <- traverse (childTerm bestMap) (candidateArgs candidate)
      let childCosts = map fst children
          childTerms = map snd children
          cost = constructorCost (candidateName candidate) childCosts
      Just ((sortName, ident), (cost, ExtractCall (candidateName candidate) childTerms))
    _ ->
      Nothing

childTerm :: BestMap -> Value -> Maybe (Cost, ExtractedTerm)
childTerm bestMap = \case
  VId sortName ident ->
    Map.lookup (sortName, ident) bestMap
  value ->
    Just (1, ExtractValue value)

constructorCost :: FunctionName -> [Cost] -> Cost
constructorCost name childCosts
  | unFunctionName name `elem` ["Num", "Var", "INum", "IVar", "BBool", "BVar"] = 1
  | otherwise = 1 + sum childCosts

isUserSort :: Sort -> Bool
isUserSort = \case
  SUser {} -> True
  _ -> False

maybeToList :: Maybe a -> [a]
maybeToList = \case
  Just value -> [value]
  Nothing -> []

renderExtractedTerm :: ExtractedTerm -> Text
renderExtractedTerm = \case
  ExtractValue value ->
    renderValue value
  ExtractCall name [] ->
    renderFunctionName name
  ExtractCall name args ->
    renderFunctionName name
      <> "("
      <> Text.intercalate ", " (map renderExtractedTerm args)
      <> ")"
