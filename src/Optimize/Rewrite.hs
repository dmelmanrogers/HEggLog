module Optimize.Rewrite
  ( PatternAtom (..)
  , RewriteCondition (..)
  , RewritePattern (..)
  , RewriteRule (..)
  , RewriteVar (..)
  , divideSelfNonZero
  )
where

import Analysis.Facts (ConstValue)
import Data.Text (Text)
import Syntax.AST

newtype RewriteVar = RewriteVar {unRewriteVar :: Text}
  deriving stock (Show, Eq, Ord)

data PatternAtom
  = PBind RewriteVar
  | PName Name
  | PInt Integer
  | PBool Bool
  deriving stock (Show, Eq, Ord)

data RewritePattern
  = MatchAtom PatternAtom
  | MatchPrim BinOp PatternAtom PatternAtom
  | MatchApp PatternAtom PatternAtom
  deriving stock (Show, Eq, Ord)

data RewriteCondition
  = RequiresType PatternAtom Type
  | RequiresPure PatternAtom
  | RequiresConst PatternAtom ConstValue
  | RequiresNonZero PatternAtom
  deriving stock (Show, Eq, Ord)

data RewriteRule = RewriteRule
  { rewriteName :: Text
  , rewriteLhs :: RewritePattern
  , rewriteRhs :: RewritePattern
  , rewriteConditions :: [RewriteCondition]
  }
  deriving stock (Show, Eq, Ord)

-- EqSat rewrites need a semantic contract. Conditional rewrites let future
-- optimization use relational facts instead of installing globally unsound
-- rules. This only describes the rule surface; no EqSat engine exists yet.
divideSelfNonZero :: RewriteRule
divideSelfNonZero =
  let x = PBind (RewriteVar "x")
   in RewriteRule
        { rewriteName = "divide-self-nonzero"
        , rewriteLhs = MatchPrim Div x x
        , rewriteRhs = MatchAtom (PInt 1)
        , rewriteConditions = [RequiresNonZero x]
        }
