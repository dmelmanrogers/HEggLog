module Optimize.EgglogBackend.Rules
  ( compilerRules
  , experimentalEqSatRules
  )
where

import Data.Text (Text)
import Egglog.Pattern
import Egglog.Rule
import Egglog.Sort
import Egglog.Value
import Optimize.EgglogBackend.Schema

compilerRules :: [Rule]
compilerRules =
  analysisRules <> integerRules <> boolRules

experimentalEqSatRules :: [Rule]
experimentalEqSatRules =
  [ rewrite (FunctionName "egglog-distribute-mul-add") (iExprSort symbols) (iMul a (iAdd b c)) (iAdd (iMul a b) (iMul a c))
  ]
 where
  a = iVar "a"
  b = iVar "b"
  c = iVar "c"

analysisRules :: [Rule]
analysisRules =
  [ Rule
      { ruleName = FunctionName "egglog-iconst-num"
      , rulePremises = [QMatch (iNum intA) outI]
      , ruleActions = [ASet (iConstFn symbols) [outI] (PKnownInt intA)]
      }
  , Rule
      { ruleName = FunctionName "egglog-bconst-bool"
      , rulePremises = [QMatch (bBool boolA) outB]
      , ruleActions = [ASet (bConstFn symbols) [outB] (PKnownBool boolA)]
      }
  , Rule
      { ruleName = FunctionName "egglog-iconst-add"
      , rulePremises =
          [ QLookup (iConstFn symbols) [a] (PKnownInt intA)
          , QLookup (iConstFn symbols) [b] (PKnownInt intB)
          , QMatch (iAdd a b) outI
          ]
      , ruleActions = [ASet (iConstFn symbols) [outI] (PKnownInt (PAddInt intA intB))]
      }
  , Rule
      { ruleName = FunctionName "egglog-iconst-mul"
      , rulePremises =
          [ QLookup (iConstFn symbols) [a] (PKnownInt intA)
          , QLookup (iConstFn symbols) [b] (PKnownInt intB)
          , QMatch (iMul a b) outI
          ]
      , ruleActions = [ASet (iConstFn symbols) [outI] (PKnownInt (PMulInt intA intB))]
      }
  , Rule
      { ruleName = FunctionName "egglog-izero-num"
      , rulePremises = [QMatch (iNum intA) outI]
      , ruleActions = [ASet (iZeroFn symbols) [outI] (PZeroInfo intA)]
      }
  , Rule
      { ruleName = FunctionName "egglog-izero-from-iconst"
      , rulePremises = [QLookup (iConstFn symbols) [outI] (PKnownInt intA)]
      , ruleActions = [ASet (iZeroFn symbols) [outI] (PZeroInfo intA)]
      }
  , Rule
      { ruleName = FunctionName "egglog-materialize-int-const"
      , rulePremises = [QLookup (iConstFn symbols) [outI] (PKnownInt intA)]
      , ruleActions = [AUnion outI (iNum intA)]
      }
  , Rule
      { ruleName = FunctionName "egglog-materialize-bool-const"
      , rulePremises = [QLookup (bConstFn symbols) [outB] (PKnownBool boolA)]
      , ruleActions = [AUnion outB (bBool boolA)]
      }
  ]
 where
  a = iVar "a"
  b = iVar "b"
  outI = iVar "out"
  outB = bVar "out"
  intA = PVar (VarName "i") SInt
  intB = PVar (VarName "j") SInt
  boolA = PVar (VarName "b") SBool

integerRules :: [Rule]
integerRules =
  [ rewrite (FunctionName "egglog-add-zero-right") (iExprSort symbols) (iAdd a (iNum (PValue (VInt 0)))) a
  , rewrite (FunctionName "egglog-add-zero-left") (iExprSort symbols) (iAdd (iNum (PValue (VInt 0))) a) a
  , rewrite (FunctionName "egglog-mul-one-right") (iExprSort symbols) (iMul a (iNum (PValue (VInt 1)))) a
  , rewrite (FunctionName "egglog-mul-one-left") (iExprSort symbols) (iMul (iNum (PValue (VInt 1))) a) a
  , rewrite (FunctionName "egglog-mul-zero-right") (iExprSort symbols) (iMul a (iNum (PValue (VInt 0)))) (iNum (PValue (VInt 0)))
  , rewrite (FunctionName "egglog-mul-zero-left") (iExprSort symbols) (iMul (iNum (PValue (VInt 0))) a) (iNum (PValue (VInt 0)))
  , Rule
      { ruleName = FunctionName "egglog-iif-known-true"
      , rulePremises =
          [ QLookup (bConstFn symbols) [c] (PKnownBool (PValue (VBool True)))
          , QMatch (PCall (iIfFn symbols) [c, a, b]) out
          ]
      , ruleActions = [AUnion out a]
      }
  , Rule
      { ruleName = FunctionName "egglog-iif-known-false"
      , rulePremises =
          [ QLookup (bConstFn symbols) [c] (PKnownBool (PValue (VBool False)))
          , QMatch (PCall (iIfFn symbols) [c, a, b]) out
          ]
      , ruleActions = [AUnion out b]
      }
  , rewrite (FunctionName "egglog-iif-same-branches") (iExprSort symbols) (PCall (iIfFn symbols) [c, a, a]) a
  ]
 where
  a = iVar "a"
  b = iVar "b"
  c = bVar "c"
  out = iVar "out"

boolRules :: [Rule]
boolRules =
  [ Rule
      { ruleName = FunctionName "egglog-bif-known-true"
      , rulePremises =
          [ QLookup (bConstFn symbols) [c] (PKnownBool (PValue (VBool True)))
          , QMatch (PCall (bIfFn symbols) [c, a, b]) out
          ]
      , ruleActions = [AUnion out a]
      }
  , Rule
      { ruleName = FunctionName "egglog-bif-known-false"
      , rulePremises =
          [ QLookup (bConstFn symbols) [c] (PKnownBool (PValue (VBool False)))
          , QMatch (PCall (bIfFn symbols) [c, a, b]) out
          ]
      , ruleActions = [AUnion out b]
      }
  , rewrite (FunctionName "egglog-bif-same-branches") (bExprSort symbols) (PCall (bIfFn symbols) [c, a, a]) a
  ]
 where
  a = bVar "a"
  b = bVar "b"
  c = bVar "c"
  out = bVar "out"

iVar :: Text -> Pattern
iVar name =
  PVar (VarName name) (iExprSort symbols)

bVar :: Text -> Pattern
bVar name =
  PVar (VarName name) (bExprSort symbols)

iNum :: Pattern -> Pattern
iNum value =
  PCall (iNumFn symbols) [value]

bBool :: Pattern -> Pattern
bBool value =
  PCall (bBoolFn symbols) [value]

iAdd :: Pattern -> Pattern -> Pattern
iAdd lhs rhs =
  PCall (iAddFn symbols) [lhs, rhs]

iMul :: Pattern -> Pattern -> Pattern
iMul lhs rhs =
  PCall (iMulFn symbols) [lhs, rhs]
