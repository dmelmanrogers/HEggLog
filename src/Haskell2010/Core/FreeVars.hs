module Haskell2010.Core.FreeVars
  ( freeVarsBind
  , freeVarsExpr
  , freeVarsModule
  )
where

import qualified Data.Set as Set
import Haskell2010.Core.Syntax
import Haskell2010.Names (RName)

freeVarsModule :: CoreModule -> Set.Set RName
freeVarsModule (CoreModule _ _ binds _foreignExports _) =
  Set.unions (map freeVarsBind binds) `Set.difference` boundNames binds

freeVarsBind :: CoreBind -> Set.Set RName
freeVarsBind = \case
  CoreNonRec _ rhs ->
    freeVarsExpr rhs
  CoreRec pairs ->
    Set.unions (map (freeVarsExpr . snd) pairs) `Set.difference` binderNameSet (map fst pairs)

freeVarsExpr :: CoreExpr -> Set.Set RName
freeVarsExpr = \case
  CVar name _ ->
    Set.singleton name
  CLit {} ->
    Set.empty
  CCon {} ->
    Set.empty
  CSpanned _ expression ->
    freeVarsExpr expression
  CLam binder body _ ->
    Set.delete (coreBinderName binder) (freeVarsExpr body)
  CApp fn arg _ ->
    freeVarsExpr fn <> freeVarsExpr arg
  CTypeLam _ body _ ->
    freeVarsExpr body
  CTypeApp fn _ _ ->
    freeVarsExpr fn
  CLet bind body _ ->
    freeVarsBind bind <> (freeVarsExpr body `Set.difference` binderNameSet (bindersOf bind))
  CCase scrutinee binder alternatives _ ->
    freeVarsExpr scrutinee
      <> ( Set.unions (map (freeVarsAlt binder) alternatives)
             `Set.difference` Set.singleton (coreBinderName binder)
         )
  CCoerce expression _ ->
    freeVarsExpr expression
  CPrimOp _ arguments _ ->
    Set.unions (map freeVarsExpr arguments)
  CForeignCall _ arguments _ ->
    Set.unions (map freeVarsExpr arguments)
  CForeignImportValue {} ->
    Set.empty

freeVarsAlt :: CoreBinder -> CoreAlt -> Set.Set RName
freeVarsAlt caseBinder (CoreAlt _ binders body) =
  freeVarsExpr body
    `Set.difference` Set.insert (coreBinderName caseBinder) (binderNameSet binders)

boundNames :: [CoreBind] -> Set.Set RName
boundNames =
  binderNameSet . concatMap bindersOf

binderNameSet :: [CoreBinder] -> Set.Set RName
binderNameSet =
  Set.fromList . map coreBinderName
