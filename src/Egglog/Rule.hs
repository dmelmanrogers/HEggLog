module Egglog.Rule
  ( Action (..)
  , Program (..)
  , QueryAtom (..)
  , Rule (..)
  , relationFact
  , rewrite
  )
where

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

rewrite :: FunctionName -> Sort -> Pattern -> Pattern -> Rule
rewrite name sort lhs rhs =
  let matchVar = VarName "__rewrite_match"
   in Rule
        { ruleName = name
        , rulePremises = [QMatch lhs (PVar matchVar sort)]
        , ruleActions = [AUnion (PVar matchVar sort) rhs]
        }
