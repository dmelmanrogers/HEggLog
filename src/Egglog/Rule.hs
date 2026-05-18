module Egglog.Rule
  ( Action (..)
  , Program (..)
  , QueryAtom (..)
  , Rule (..)
  , relationFact
  , renderAction
  , rewrite
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Egglog.Function
import Egglog.Pattern
import Egglog.Sort
import Egglog.Value

data QueryAtom
  = QLookup FunctionName [Pattern] Pattern
  | QMatch Pattern Pattern
  | QEq Pattern Pattern
  deriving stock (Show, Eq, Ord)

data Action
  = ASet FunctionName [Pattern] Pattern
  | AUnion Pattern Pattern
  | AAssert FunctionName [Pattern]
  deriving stock (Show, Eq, Ord)

data Rule = Rule
  { ruleName :: FunctionName
  , rulePremises :: [QueryAtom]
  , ruleActions :: [Action]
  }
  deriving stock (Show, Eq, Ord)

data Program = Program
  { programDecls :: [FunctionDecl]
  , programInitialActions :: [Action]
  , programRules :: [Rule]
  }
  deriving stock (Show, Eq, Ord)

relationFact :: FunctionName -> [Value] -> Action
relationFact name args =
  ASet name (map PValue args) (PValue VUnit)

renderAction :: Action -> Text
renderAction = \case
  ASet name args out ->
    "set " <> renderFunctionName name <> renderArgs args <> " = " <> renderPattern out
  AUnion lhs rhs ->
    "union " <> renderPattern lhs <> " = " <> renderPattern rhs
  AAssert name args ->
    "assert " <> renderFunctionName name <> renderArgs args

renderArgs :: [Pattern] -> Text
renderArgs args =
  "(" <> Text.intercalate ", " (map renderPattern args) <> ")"

rewrite :: FunctionName -> Sort -> Pattern -> Pattern -> Rule
rewrite name sort lhs rhs =
  let matchVar = VarName "__rewrite_match"
   in Rule
        { ruleName = name
        , rulePremises = [QMatch lhs (PVar matchVar sort)]
        , ruleActions = [AUnion (PVar matchVar sort) rhs]
        }
