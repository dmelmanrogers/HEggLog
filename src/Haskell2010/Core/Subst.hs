module Haskell2010.Core.Subst
  ( substExpr
  )
where

import qualified Data.Set as Set
import Haskell2010.Core.FreeVars (freeVarsExpr)
import Haskell2010.Core.Syntax
import Haskell2010.Names (RName (..))

substExpr :: RName -> CoreExpr -> CoreExpr -> CoreExpr
substExpr target replacement expression =
  fst (go initialSupply expression)
 where
  replacementFreeVars =
    freeVarsExpr replacement

  initialSupply =
    1
      + maximum
        ( 0
            : map
              nameUnique
              (Set.toList (Set.insert target (allNamesExpr replacement <> allNamesExpr expression)))
        )

  go supply = \case
    CVar name _
      | name == target -> (replacement, supply)
    expression'@CVar {} ->
      (expression', supply)
    expression'@CLit {} ->
      (expression', supply)
    expression'@CCon {} ->
      (expression', supply)
    CLam binder body ty
      | coreBinderName binder == target ->
          (CLam binder body ty, supply)
      | coreBinderName binder `Set.member` replacementFreeVars ->
          let (freshBinder, supplyAfterFreshen) = freshenBinder supply binder
              renamedBody = renameBound (coreBinderName binder) (coreBinderName freshBinder) body
              (body', supplyAfterBody) = go supplyAfterFreshen renamedBody
           in (CLam freshBinder body' ty, supplyAfterBody)
      | otherwise ->
          let (body', supplyAfterBody) = go supply body
           in (CLam binder body' ty, supplyAfterBody)
    CApp fn arg ty ->
      let (fn', supplyAfterFn) = go supply fn
          (arg', supplyAfterArg) = go supplyAfterFn arg
       in (CApp fn' arg' ty, supplyAfterArg)
    CLet bind body ty ->
      let (bind', bodyForSubstitution, substituteBody, supplyAfterBind) = substBind supply bind body
          (body', supplyAfterBody) =
            if substituteBody
              then go supplyAfterBind bodyForSubstitution
              else (bodyForSubstitution, supplyAfterBind)
       in (CLet bind' body' ty, supplyAfterBody)
    CCase scrutinee binder alternatives ty ->
      let (scrutinee', supplyAfterScrutinee) = go supply scrutinee
       in if coreBinderName binder == target
            then (CCase scrutinee' binder alternatives ty, supplyAfterScrutinee)
            else
              let (binder', alternativesForSubstitution, supplyAfterBinder) =
                    freshenCaseBinderIfNeeded supplyAfterScrutinee binder alternatives
                  (alternatives', supplyAfterAlternatives) =
                    substAlts supplyAfterBinder alternativesForSubstitution
               in (CCase scrutinee' binder' alternatives' ty, supplyAfterAlternatives)
    CPrimOp op arguments ty ->
      let (arguments', supplyAfterArguments) = substExprs supply arguments
       in (CPrimOp op arguments' ty, supplyAfterArguments)

  substBind supply bind body =
    case bind of
      CoreNonRec binder rhs ->
        let (rhs', supplyAfterRhs) = go supply rhs
         in if coreBinderName binder == target
              then (CoreNonRec binder rhs', body, False, supplyAfterRhs)
              else
                let (binder', body', supplyAfterBinder) =
                      freshenBodyBinderIfNeeded supplyAfterRhs binder body
                 in (CoreNonRec binder' rhs', body', True, supplyAfterBinder)
      CoreRec pairs ->
        let binders = map fst pairs
            binderNames = Set.fromList (map coreBinderName binders)
         in if target `Set.member` binderNames
              then (bind, body, False, supply)
              else
                let (freshenedPairs, body', supplyAfterFreshen) =
                      freshenRecursiveBinders supply pairs body
                    (pairs', supplyAfterPairs) = substRecPairs supplyAfterFreshen freshenedPairs
                 in (CoreRec pairs', body', True, supplyAfterPairs)

  substRecPairs supply [] =
    ([], supply)
  substRecPairs supply ((binder, rhs) : pairs) =
    let (rhs', supplyAfterRhs) = go supply rhs
        (pairs', supplyAfterPairs) = substRecPairs supplyAfterRhs pairs
     in ((binder, rhs') : pairs', supplyAfterPairs)

  substAlts supply [] =
    ([], supply)
  substAlts supply (alt : alternatives) =
    let (alt', supplyAfterAlt) = substAlt supply alt
        (alternatives', supplyAfterAlternatives) = substAlts supplyAfterAlt alternatives
     in (alt' : alternatives', supplyAfterAlternatives)

  substAlt supply (CoreAlt altCon binders body) =
    let binderNames = Set.fromList (map coreBinderName binders)
     in if target `Set.member` binderNames
          then (CoreAlt altCon binders body, supply)
          else
            let (binders', body', supplyAfterFreshen) = freshenBindersIfNeeded supply binders body
                (body'', supplyAfterBody) = go supplyAfterFreshen body'
             in (CoreAlt altCon binders' body'', supplyAfterBody)

  substExprs supply [] =
    ([], supply)
  substExprs supply (argument : arguments) =
    let (argument', supplyAfterArgument) = go supply argument
        (arguments', supplyAfterArguments) = substExprs supplyAfterArgument arguments
     in (argument' : arguments', supplyAfterArguments)

  freshenCaseBinderIfNeeded supply binder alternatives
    | coreBinderName binder `Set.member` replacementFreeVars =
        let (freshBinder, supplyAfterFreshen) = freshenBinder supply binder
         in ( freshBinder
            , map (renameAltBound (coreBinderName binder) (coreBinderName freshBinder)) alternatives
            , supplyAfterFreshen
            )
    | otherwise =
        (binder, alternatives, supply)

  freshenBodyBinderIfNeeded supply binder body
    | coreBinderName binder `Set.member` replacementFreeVars =
        let (freshBinder, supplyAfterFreshen) = freshenBinder supply binder
         in ( freshBinder
            , renameBound (coreBinderName binder) (coreBinderName freshBinder) body
            , supplyAfterFreshen
            )
    | otherwise =
        (binder, body, supply)

  freshenRecursiveBinders supply pairs body =
    let binders = map fst pairs
        (binders', renames, supplyAfterFreshen) = freshenBinderGroup supply binders
        pairsWithFreshBinders = zip binders' (map snd pairs)
     in ( map (renamePair renames) pairsWithFreshBinders
        , applyRenames renames body
        , supplyAfterFreshen
        )

  freshenBindersIfNeeded supply binders body =
    let (binders', renames, supplyAfterFreshen) = freshenBinderGroup supply binders
     in (binders', applyRenames renames body, supplyAfterFreshen)

  freshenBinderGroup supply binders =
    foldr freshenOne ([], [], supply) binders
   where
    freshenOne binder (bindersAcc, renamesAcc, supplyAcc)
      | coreBinderName binder `Set.member` replacementFreeVars =
          let (freshBinder, supplyNext) = freshenBinder supplyAcc binder
           in (freshBinder : bindersAcc, (coreBinderName binder, coreBinderName freshBinder) : renamesAcc, supplyNext)
      | otherwise =
          (binder : bindersAcc, renamesAcc, supplyAcc)

freshenBinder :: Int -> CoreBinder -> (CoreBinder, Int)
freshenBinder supply binder =
  let oldName = coreBinderName binder
      freshName = oldName {nameUnique = supply, nameExternal = False}
   in (binder {coreBinderName = freshName}, supply + 1)

renamePair :: [(RName, RName)] -> (CoreBinder, CoreExpr) -> (CoreBinder, CoreExpr)
renamePair renames (binder, rhs) =
  (binder, applyRenames renames rhs)

applyRenames :: [(RName, RName)] -> CoreExpr -> CoreExpr
applyRenames renames expression =
  foldr (uncurry renameBound) expression renames

renameAltBound :: RName -> RName -> CoreAlt -> CoreAlt
renameAltBound old new (CoreAlt altCon binders body) =
  CoreAlt altCon (map (renameBinder old new) binders) (renameBound old new body)

renameBound :: RName -> RName -> CoreExpr -> CoreExpr
renameBound old new = \case
  CVar name ty
    | name == old -> CVar new ty
  expression@CVar {} ->
    expression
  expression@CLit {} ->
    expression
  expression@CCon {} ->
    expression
  CLam binder body ty ->
    CLam (renameBinder old new binder) (renameBound old new body) ty
  CApp fn arg ty ->
    CApp (renameBound old new fn) (renameBound old new arg) ty
  CLet bind body ty ->
    CLet (renameBind old new bind) (renameBound old new body) ty
  CCase scrutinee binder alternatives ty ->
    CCase
      (renameBound old new scrutinee)
      (renameBinder old new binder)
      (map (renameAltBound old new) alternatives)
      ty
  CPrimOp op arguments ty ->
    CPrimOp op (map (renameBound old new) arguments) ty

renameBind :: RName -> RName -> CoreBind -> CoreBind
renameBind old new = \case
  CoreNonRec binder rhs ->
    CoreNonRec (renameBinder old new binder) (renameBound old new rhs)
  CoreRec pairs ->
    CoreRec [(renameBinder old new binder, renameBound old new rhs) | (binder, rhs) <- pairs]

renameBinder :: RName -> RName -> CoreBinder -> CoreBinder
renameBinder old new binder
  | coreBinderName binder == old = binder {coreBinderName = new}
  | otherwise = binder

allNamesExpr :: CoreExpr -> Set.Set RName
allNamesExpr = \case
  CVar name ty ->
    Set.insert name (allNamesType ty)
  CLit _ ty ->
    allNamesType ty
  CCon name ty ->
    Set.insert name (allNamesType ty)
  CLam binder body ty ->
    allNamesBinder binder <> allNamesExpr body <> allNamesType ty
  CApp fn arg ty ->
    allNamesExpr fn <> allNamesExpr arg <> allNamesType ty
  CLet bind body ty ->
    allNamesBind bind <> allNamesExpr body <> allNamesType ty
  CCase scrutinee binder alternatives ty ->
    allNamesExpr scrutinee
      <> allNamesBinder binder
      <> Set.unions (map allNamesAlt alternatives)
      <> allNamesType ty
  CPrimOp _ arguments ty ->
    Set.unions (map allNamesExpr arguments) <> allNamesType ty

allNamesBind :: CoreBind -> Set.Set RName
allNamesBind = \case
  CoreNonRec binder rhs ->
    allNamesBinder binder <> allNamesExpr rhs
  CoreRec pairs ->
    Set.unions [allNamesBinder binder <> allNamesExpr rhs | (binder, rhs) <- pairs]

allNamesAlt :: CoreAlt -> Set.Set RName
allNamesAlt (CoreAlt altCon binders body) =
  allNamesAltCon altCon <> Set.unions (map allNamesBinder binders) <> allNamesExpr body

allNamesAltCon :: CoreAltCon -> Set.Set RName
allNamesAltCon = \case
  DefaultAlt -> Set.empty
  LiteralAlt {} -> Set.empty
  ConstructorAlt name -> Set.singleton name

allNamesBinder :: CoreBinder -> Set.Set RName
allNamesBinder binder =
  Set.insert (coreBinderName binder) (allNamesType (coreBinderType binder))

allNamesType :: CoreType -> Set.Set RName
allNamesType = \case
  CTyVar name -> Set.singleton name
  CTyCon name -> Set.singleton name
  CTyApp fn arg -> allNamesType fn <> allNamesType arg
  CTyFun arg result -> allNamesType arg <> allNamesType result
  CTyTuple fields -> Set.unions (map allNamesType fields)
  CTyList elementTy -> allNamesType elementTy
