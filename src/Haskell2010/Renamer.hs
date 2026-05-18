module Haskell2010.Renamer
  ( RenameError (..)
  , renameModule
  , renderRenameError
  )
where

import Control.Monad (foldM, when)
import Control.Monad.State.Strict (StateT (..), evalStateT, get, lift, modify, put, runStateT)
import Data.Char (isUpper)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Names
import Haskell2010.Pretty (renderModuleName)
import Haskell2010.Renamed
import qualified Haskell2010.Syntax as S

data RenameError
  = DuplicateName Namespace Text
  | DuplicatePatternName Text
  | UnboundName Namespace Text
  | AmbiguousName Namespace Text [RName]
  | ConflictingFixity Text S.Fixity S.Fixity
  | InvalidFixityUse Text
  deriving stock (Show, Eq)

type Scope = Map.Map Namespace (Map.Map Text [RName])

data RenameState = RenameState
  { nextUnique :: Int
  , scopes :: [Scope]
  , fixities :: Map.Map Text S.Fixity
  }
  deriving stock (Show, Eq)

type RenameM = StateT RenameState (Either RenameError)

renameModule :: S.HsModule -> Either RenameError RHsModule
renameModule sourceModule =
  evalStateT go initialState
 where
  initialState =
    RenameState
      { nextUnique = 1
      , scopes = []
      , fixities = preludeFixities
      }
  go = do
    preludeScope <- externalScope preludeNames
    importScope <- importsScope (S.moduleImports sourceModule)
    topScope <- collectDeclBinders TopLevelContext (S.moduleDecls sourceModule)
    moduleFixities <- collectFixityDecls (S.moduleDecls sourceModule)
    modify $ \state ->
      state
        { scopes = [topScope, importScope, preludeScope]
        , fixities = Map.union moduleFixities preludeFixities
        }
    renamedExports <- traverse renameExportList (S.moduleExports sourceModule)
    renamedDecls <- traverse renameDecl (S.moduleDecls sourceModule)
    resolvedFixities <- resolveFixityDecls (S.moduleDecls sourceModule)
    pure
      RHsModule
        { rModuleName = S.moduleName sourceModule
        , rModuleExports = renamedExports
        , rModuleImports = RImportDecl <$> S.moduleImports sourceModule
        , rModuleFixities = Map.fromList resolvedFixities
        , rModuleDecls = renamedDecls
        }

renderRenameError :: RenameError -> Text
renderRenameError = \case
  DuplicateName namespace occ ->
    "duplicate " <> renderNamespace namespace <> " binding `" <> occ <> "`"
  DuplicatePatternName occ ->
    "duplicate pattern binding `" <> occ <> "`"
  UnboundName namespace occ ->
    "unbound " <> renderNamespace namespace <> " name `" <> occ <> "`"
  AmbiguousName namespace occ names ->
    "ambiguous "
      <> renderNamespace namespace
      <> " name `"
      <> occ
      <> "`: "
      <> Text.intercalate ", " (renderRName <$> names)
  ConflictingFixity occ oldFixity newFixity ->
    "conflicting fixity declarations for `"
      <> occ
      <> "`: "
      <> Text.pack (show oldFixity)
      <> " and "
      <> Text.pack (show newFixity)
  InvalidFixityUse message ->
    message

data DeclContext
  = TopLevelContext
  | ClassContext
  | InstanceContext
  deriving stock (Show, Eq)

freshName :: Namespace -> Text -> Bool -> RenameM RName
freshName namespace occ external = do
  state <- get
  let unique = nextUnique state
  put state {nextUnique = unique + 1}
  pure
    RName
      { nameNamespace = namespace
      , nameOcc = occ
      , nameUnique = unique
      , nameExternal = external
      }

externalScope :: [(Namespace, Text)] -> RenameM Scope
externalScope =
  foldM addExternal emptyScope
 where
  addExternal scope (namespace, occ) = do
    name <- freshName namespace occ True
    pure (insertScopeName namespace occ name scope)

importsScope :: [S.ImportDecl] -> RenameM Scope
importsScope =
  foldM addImport emptyScope
 where
  addImport scope importDecl = do
    let moduleText = renderModuleName (S.importModule importDecl)
        qualifierTexts = List.nub (moduleText : maybe [] ((: []) . renderModuleName) (S.importAs importDecl))
        moduleNames = (,moduleText) <$> qualifierTexts
    scopeWithModules <- foldM addModuleAlias scope moduleNames
    case S.importSpecs importDecl of
      Nothing -> pure scopeWithModules
      Just (specs, _) -> foldM (addImportSpec importDecl qualifierTexts) scopeWithModules specs

  addModuleAlias scope (alias, originalModule) = do
    name <- freshName ModuleNamespace originalModule True
    pure (insertScopeName ModuleNamespace alias name scope)

addImportSpec :: S.ImportDecl -> [Text] -> Scope -> S.ImportSpec -> RenameM Scope
addImportSpec importDecl qualifiers scope importSpec =
  foldM addImportedOccurrence scope (importSpecOccurrences importSpec)
 where
  addImportedOccurrence currentScope (namespace, occ) = do
    let qualifiedOccurrences = [(namespace, qualifier <> "." <> occ) | qualifier <- qualifiers]
        unqualifiedOccurrences =
          if S.importQualified importDecl
            then []
            else [(namespace, occ)]
    foldM addOne currentScope (unqualifiedOccurrences <> qualifiedOccurrences)

  addOne currentScope (namespace, occ) = do
    name <- freshName namespace occ True
    pure (insertScopeName namespace occ name currentScope)

importSpecOccurrences :: S.ImportSpec -> [(Namespace, Text)]
importSpecOccurrences = \case
  S.ImportName occ -> classifiedImportedName occ
  S.ImportThing occ children ->
    classifiedImportedParent occ <> concatMap classifiedImportedChild children

classifiedImportedName :: Text -> [(Namespace, Text)]
classifiedImportedName occ
  | isConstructorOperator occ =
      [(ConstructorNamespace, occ)]
  | isConstructorLike occ =
      [(TypeNamespace, occ), (ClassNamespace, occ), (ConstructorNamespace, occ)]
  | otherwise =
      [(TermNamespace, occ)]

classifiedImportedParent :: Text -> [(Namespace, Text)]
classifiedImportedParent occ
  | isConstructorLike occ =
      [(TypeNamespace, occ), (ClassNamespace, occ)]
  | otherwise =
      [(TermNamespace, occ)]

classifiedImportedChild :: Text -> [(Namespace, Text)]
classifiedImportedChild ".." =
  []
classifiedImportedChild occ
  | isConstructorOperator occ =
      [(ConstructorNamespace, occ)]
  | isConstructorLike occ =
      [(ConstructorNamespace, occ)]
  | otherwise =
      [(TermNamespace, occ)]

collectDeclBinders :: DeclContext -> [S.Decl] -> RenameM Scope
collectDeclBinders context =
  foldM collect emptyScope
 where
  collect scope = \case
    S.TypeSignature names _
      | context == ClassContext ->
          defineMany TermNamespace names scope
      | otherwise ->
          pure scope
    S.FunctionBinding name _ _ _
      | context == InstanceContext ->
          pure scope
      | context == ClassContext ->
          defineIfMissing TermNamespace name scope
      | otherwise ->
          defineOne TermNamespace name scope
    S.PatternBinding pat _ _ -> do
      names <- patternBinderOccurrences pat
      defineMany TermNamespace names scope
    S.FixityDecl {} ->
      pure scope
    S.DataDecl name _ constructors _ -> do
      withType <- defineOne TypeNamespace name scope
      foldM defineConstructor withType constructors
    S.NewtypeDecl name _ constructor _ -> do
      withType <- defineOne TypeNamespace name scope
      defineConstructor withType constructor
    S.TypeSynonym name _ _ ->
      defineOne TypeNamespace name scope
    S.ClassDecl _ className _ decls -> do
      withClass <- defineOne ClassNamespace className scope
      collectClassMethods withClass decls
    S.InstanceDecl {} ->
      pure scope
    S.DefaultDecl {} ->
      pure scope
    S.ForeignDecl {} ->
      pure scope

  defineConstructor scope (S.ConDecl constructorName _) =
    defineOne ConstructorNamespace constructorName scope

collectClassMethods :: Scope -> [S.Decl] -> RenameM Scope
collectClassMethods initialScope decls =
  fst <$> foldM collect (initialScope, Set.empty) decls
 where
  collect (scope, defaults) = \case
    S.TypeSignature names _ ->
      (,defaults) <$> defineMany TermNamespace names scope
    S.FunctionBinding name _ _ _
      | name `Set.member` defaults ->
          throwRename (DuplicateName TermNamespace name)
      | otherwise ->
          (,Set.insert name defaults) <$> defineIfMissing TermNamespace name scope
    _ ->
      pure (scope, defaults)

defineOne :: Namespace -> Text -> Scope -> RenameM Scope
defineOne namespace occ scope = do
  when (scopeHasName namespace occ scope) $
    throwRename (DuplicateName namespace occ)
  name <- freshName namespace occ False
  pure (insertScopeName namespace occ name scope)

defineIfMissing :: Namespace -> Text -> Scope -> RenameM Scope
defineIfMissing namespace occ scope =
  if scopeHasName namespace occ scope
    then pure scope
    else defineOne namespace occ scope

defineMany :: Namespace -> [Text] -> Scope -> RenameM Scope
defineMany namespace names scope =
  foldM (\acc name -> defineOne namespace name acc) scope names

scopeHasName :: Namespace -> Text -> Scope -> Bool
scopeHasName namespace occ scope =
  case Map.lookup namespace scope >>= Map.lookup occ of
    Just (_ : _) -> True
    _ -> False

insertScopeName :: Namespace -> Text -> RName -> Scope -> Scope
insertScopeName namespace occ name =
  Map.insertWith
    (Map.unionWith (<>))
    namespace
    (Map.singleton occ [name])

emptyScope :: Scope
emptyScope =
  Map.empty

lookupName :: Namespace -> Text -> RenameM RName
lookupName namespace occ = do
  scopeStack <- scopes <$> get
  case firstVisible scopeStack of
    Nothing ->
      throwRename (UnboundName namespace occ)
    Just [name] ->
      pure name
    Just names ->
      throwRename (AmbiguousName namespace occ names)
 where
  firstVisible [] =
    Nothing
  firstVisible (scope : rest) =
    case Map.lookup namespace scope >>= Map.lookup occ of
      Just names | not (null names) -> Just names
      _ -> firstVisible rest

lookupTypeConstructor :: Text -> RenameM RName
lookupTypeConstructor occ =
  lookupName TypeNamespace occ `orElseRename` lookupName ClassNamespace occ

orElseRename :: RenameM a -> RenameM a -> RenameM a
orElseRename first second =
  StateT $ \state ->
    case runStateT first state of
      Right result -> Right result
      Left UnboundName {} -> runStateT second state
      Left err -> Left err

withScope :: Scope -> RenameM a -> RenameM a
withScope scope action = do
  state <- get
  put state {scopes = scope : scopes state}
  result <- action
  modify $ \current -> current {scopes = scopes state}
  pure result

withDeclGroupScope :: DeclContext -> [S.Decl] -> ([RDecl] -> RenameM a) -> RenameM a
withDeclGroupScope _ [] continuation =
  continuation []
withDeclGroupScope context decls continuation = do
  groupScope <- collectDeclBinders context decls
  withScope groupScope $ do
    renamedDecls <- traverse renameDecl decls
    continuation renamedDecls

withPatternScope :: [S.Pat] -> ([RPat] -> RenameM a) -> RenameM a
withPatternScope patterns continuation = do
  patternScope <- patternScopeFor patterns
  withScope patternScope $ do
    renamedPatterns <- traverse renamePat patterns
    continuation renamedPatterns

withTypeVariableScope :: [Text] -> ([RName] -> RenameM a) -> RenameM a
withTypeVariableScope names continuation = do
  ensureNoDuplicates (DuplicateName TypeVariableNamespace) names
  (scope, renamedNames) <- foldM add (emptyScope, []) names
  withScope scope (continuation (reverse renamedNames))
 where
  add (scope, renamedNames) occ = do
    newScope <- defineOne TypeVariableNamespace occ scope
    name <- lookupNameInScope TypeVariableNamespace occ newScope
    pure (newScope, name : renamedNames)

lookupNameInScope :: Namespace -> Text -> Scope -> RenameM RName
lookupNameInScope namespace occ scope =
  case Map.lookup namespace scope >>= Map.lookup occ of
    Just [name] -> pure name
    Just names -> throwRename (AmbiguousName namespace occ names)
    Nothing -> throwRename (UnboundName namespace occ)

renameDecl :: S.Decl -> RenameM RDecl
renameDecl = \case
  S.TypeSignature names sourceType -> do
    renamedNames <- traverse (lookupName TermNamespace) names
    renamedType <- renameImplicitForallType sourceType
    pure (RTypeSignature renamedNames renamedType)
  S.FunctionBinding name patterns rhs whereDecls -> do
    renamedName <- lookupName TermNamespace name
    withPatternScope patterns $ \renamedPatterns ->
      withDeclGroupScope TopLevelContext whereDecls $ \renamedWhereDecls -> do
        renamedRhs <- renameRhs rhs
        pure (RFunctionBinding renamedName renamedPatterns renamedRhs renamedWhereDecls)
  S.PatternBinding pat rhs whereDecls -> do
    renamedPat <- renamePat pat
    withDeclGroupScope TopLevelContext whereDecls $ \renamedWhereDecls -> do
      renamedRhs <- renameRhs rhs
      pure (RPatternBinding renamedPat renamedRhs renamedWhereDecls)
  S.FixityDecl fixity names -> do
    renamedNames <- traverse lookupOperatorName names
    pure (RFixityDecl fixity renamedNames)
  S.DataDecl name params constructors derivingNames -> do
    renamedName <- lookupName TypeNamespace name
    withTypeVariableScope params $ \renamedParams -> do
      renamedConstructors <- traverse renameConDecl constructors
      renamedDeriving <- traverse (lookupName ClassNamespace) derivingNames
      pure (RDataDecl renamedName renamedParams renamedConstructors renamedDeriving)
  S.NewtypeDecl name params constructor derivingNames -> do
    renamedName <- lookupName TypeNamespace name
    withTypeVariableScope params $ \renamedParams -> do
      renamedConstructor <- renameConDecl constructor
      renamedDeriving <- traverse (lookupName ClassNamespace) derivingNames
      pure (RNewtypeDecl renamedName renamedParams renamedConstructor renamedDeriving)
  S.TypeSynonym name params sourceType -> do
    renamedName <- lookupName TypeNamespace name
    withTypeVariableScope params $ \renamedParams -> do
      renamedType <- renameType sourceType
      pure (RTypeSynonym renamedName renamedParams renamedType)
  S.ClassDecl context className typeVariable decls -> do
    renamedClassName <- lookupName ClassNamespace className
    withTypeVariableScope [typeVariable] $ \case
      [renamedTypeVariable] -> do
        renamedContext <- traverse renameType context
        renamedDecls <- traverse renameDecl decls
        pure (RClassDecl renamedContext renamedClassName renamedTypeVariable renamedDecls)
      _ -> error "withTypeVariableScope returned impossible arity"
  S.InstanceDecl context sourceType decls -> do
    let typeVariables = typeVarsInTypes (sourceType : context)
    withTypeVariableScope typeVariables $ \_ -> do
      renamedContext <- traverse renameType context
      renamedType <- renameType sourceType
      renamedDecls <- traverse renameDecl decls
      pure (RInstanceDecl renamedContext renamedType renamedDecls)
  S.DefaultDecl types ->
    RDefaultDecl <$> traverse renameImplicitForallType types
  S.ForeignDecl text ->
    pure (RForeignDecl text)

renameConDecl :: S.ConDecl -> RenameM RConDecl
renameConDecl (S.ConDecl constructorName fields) =
  RConDecl <$> lookupName ConstructorNamespace constructorName <*> traverse renameType fields

renameRhs :: S.Rhs -> RenameM RRhs
renameRhs = \case
  S.Unguarded expr ->
    RUnguarded <$> renameExpr expr
  S.Guarded branches ->
    RGuarded <$> traverse renameGuardedBranch branches
 where
  renameGuardedBranch (guardExpr, bodyExpr) =
    (,) <$> renameExpr guardExpr <*> renameExpr bodyExpr

renameExpr :: S.Expr -> RenameM RExpr
renameExpr expr =
  renameExprRaw expr >>= resolveExprFixities

renameExprRaw :: S.Expr -> RenameM RExpr
renameExprRaw = \case
  S.Var occ ->
    RVar <$> lookupName TermNamespace occ
  S.Con occ ->
    RCon <$> lookupName ConstructorNamespace occ
  S.Lit literal ->
    pure (RLit literal)
  S.App function argument ->
    RApp <$> renameExpr function <*> renameExpr argument
  S.InfixApp lhs op rhs ->
    RInfixApp <$> renameExprRaw lhs <*> lookupOperatorName op <*> renameExprRaw rhs
  S.Lambda patterns body ->
    withPatternScope patterns $ \renamedPatterns ->
      RLambda renamedPatterns <$> renameExpr body
  S.Let decls body ->
    withDeclGroupScope TopLevelContext decls $ \renamedDecls ->
      RLet renamedDecls <$> renameExpr body
  S.If condition thenBranch elseBranch ->
    RIf <$> renameExpr condition <*> renameExpr thenBranch <*> renameExpr elseBranch
  S.Case scrutinee alternatives ->
    RCase <$> renameExpr scrutinee <*> traverse renameAlt alternatives
  S.Do statements ->
    RDo <$> renameStmtList statements
  S.List expressions ->
    RList <$> traverse renameExpr expressions
  S.Tuple expressions ->
    RTuple <$> traverse renameExpr expressions
  S.Unit ->
    pure RUnit
  S.Paren inner ->
    RParen <$> renameExpr inner
  S.LeftSection sectionExpr op ->
    RLeftSection <$> renameExpr sectionExpr <*> lookupOperatorName op
  S.RightSection op sectionExpr ->
    RRightSection <$> lookupOperatorName op <*> renameExpr sectionExpr
  S.ArithmeticSeq start step end ->
    RArithmeticSeq <$> renameExpr start <*> traverse renameExpr step <*> traverse renameExpr end
  S.ListComp body statements ->
    RListComp <$> renameExpr body <*> renameStmtList statements
  S.ExprTypeSig inner sourceType ->
    RExprTypeSig <$> renameExpr inner <*> renameImplicitForallType sourceType

renameStmtList :: [S.Stmt] -> RenameM [RStmt]
renameStmtList [] =
  pure []
renameStmtList (statement : rest) =
  case statement of
    S.ExprStmt expr ->
      (:) <$> (RExprStmt <$> renameExpr expr) <*> renameStmtList rest
    S.BindStmt pat expr -> do
      renamedExpr <- renameExpr expr
      patternScope <- patternScopeFor [pat]
      withScope patternScope $ do
        renamedPat <- renamePat pat
        renamedRest <- renameStmtList rest
        pure (RBindStmt renamedPat renamedExpr : renamedRest)
    S.LetStmt decls -> do
      groupScope <- collectDeclBinders TopLevelContext decls
      withScope groupScope $ do
        renamedDecls <- traverse renameDecl decls
        renamedRest <- renameStmtList rest
        pure (RLetStmt renamedDecls : renamedRest)

renameAlt :: S.Alt -> RenameM RAlt
renameAlt (S.Alt pat rhs whereDecls) = do
  patternScope <- patternScopeFor [pat]
  withScope patternScope $ do
    renamedPat <- renamePat pat
    withDeclGroupScope TopLevelContext whereDecls $ \renamedWhereDecls -> do
      renamedRhs <- renameRhs rhs
      pure (RAlt renamedPat renamedRhs renamedWhereDecls)

renamePat :: S.Pat -> RenameM RPat
renamePat = \case
  S.PVar occ ->
    RPVar <$> lookupName TermNamespace occ
  S.PCon occ args ->
    RPCon <$> lookupName ConstructorNamespace occ <*> traverse renamePat args
  S.PLit literal ->
    pure (RPLit literal)
  S.PWildcard ->
    pure RPWildcard
  S.PTuple patterns ->
    RPTuple <$> traverse renamePat patterns
  S.PList patterns ->
    RPList <$> traverse renamePat patterns
  S.PAs occ pat ->
    RPAs <$> lookupName TermNamespace occ <*> renamePat pat
  S.PIrrefutable pat ->
    RPIrrefutable <$> renamePat pat
  S.PParen pat ->
    RPParen <$> renamePat pat

renameImplicitForallType :: S.HsType -> RenameM RHsType
renameImplicitForallType sourceType =
  withTypeVariableScope (typeVarsInType sourceType) $ \_ ->
    renameType sourceType

renameType :: S.HsType -> RenameM RHsType
renameType = \case
  S.TyVar occ ->
    RTyVar <$> lookupName TypeVariableNamespace occ
  S.TyCon occ ->
    RTyCon <$> lookupTypeConstructor occ
  S.TyApp lhs rhs ->
    RTyApp <$> renameType lhs <*> renameType rhs
  S.TyFun fromType toType ->
    RTyFun <$> renameType fromType <*> renameType toType
  S.TyContext context body ->
    RTyContext <$> traverse renameType context <*> renameType body
  S.TyTuple types ->
    RTyTuple <$> traverse renameType types
  S.TyList elementType ->
    RTyList <$> renameType elementType
  S.TyParen inner ->
    RTyParen <$> renameType inner

patternScopeFor :: [S.Pat] -> RenameM Scope
patternScopeFor patterns = do
  names <- concat <$> traverse patternBinderOccurrences patterns
  ensureNoDuplicates DuplicatePatternName names
  defineMany TermNamespace names emptyScope

patternBinderOccurrences :: S.Pat -> RenameM [Text]
patternBinderOccurrences pat = do
  let names = collect pat
  ensureNoDuplicates DuplicatePatternName names
  pure names
 where
  collect = \case
    S.PVar occ -> [occ]
    S.PCon _ args -> concatMap collect args
    S.PLit {} -> []
    S.PWildcard -> []
    S.PTuple patterns -> concatMap collect patterns
    S.PList patterns -> concatMap collect patterns
    S.PAs occ inner -> occ : collect inner
    S.PIrrefutable inner -> collect inner
    S.PParen inner -> collect inner

ensureNoDuplicates :: (Text -> RenameError) -> [Text] -> RenameM ()
ensureNoDuplicates toError values =
  go Set.empty values
 where
  go _ [] =
    pure ()
  go seen (value : rest)
    | value `Set.member` seen =
        throwRename (toError value)
    | otherwise =
        go (Set.insert value seen) rest

renameExportList :: [S.Export] -> RenameM [RExport]
renameExportList =
  traverse renameExport

renameExport :: S.Export -> RenameM RExport
renameExport = \case
  S.ExportName occ ->
    RExportName <$> lookupExportName occ
  S.ExportThing occ children ->
    RExportThing <$> lookupExportName occ <*> pure children
  S.ExportModule moduleName ->
    pure (RExportModule moduleName)

lookupExportName :: Text -> RenameM RName
lookupExportName occ
  | isConstructorLike occ =
      lookupTypeConstructor occ `orElseRename` lookupName ConstructorNamespace occ
  | otherwise =
      lookupName TermNamespace occ

collectFixityDecls :: [S.Decl] -> RenameM (Map.Map Text S.Fixity)
collectFixityDecls =
  foldM collect Map.empty
 where
  collect acc = \case
    S.FixityDecl fixity names ->
      foldM (insertFixity fixity) acc names
    _ ->
      pure acc

  insertFixity fixity acc occ =
    case Map.lookup occ acc of
      Just oldFixity -> throwRename (ConflictingFixity occ oldFixity fixity)
      Nothing -> pure (Map.insert occ fixity acc)

resolveFixityDecls :: [S.Decl] -> RenameM [(RName, S.Fixity)]
resolveFixityDecls decls =
  concat <$> traverse resolve decls
 where
  resolve = \case
    S.FixityDecl fixity names ->
      traverse (\occ -> (,fixity) <$> lookupOperatorName occ) names
    _ ->
      pure []

resolveExprFixities :: RExpr -> RenameM RExpr
resolveExprFixities expr =
  case expr of
    RInfixApp {} -> do
      let (firstOperand, rest) = flattenInfix expr
      resolvedFirst <- resolveExprFixities firstOperand
      resolvedRest <- traverse resolveRest rest
      resolveInfixChain resolvedFirst resolvedRest
    RApp function argument ->
      RApp <$> resolveExprFixities function <*> resolveExprFixities argument
    RLambda patterns body ->
      RLambda patterns <$> resolveExprFixities body
    RLet decls body ->
      RLet decls <$> resolveExprFixities body
    RIf condition thenBranch elseBranch ->
      RIf <$> resolveExprFixities condition <*> resolveExprFixities thenBranch <*> resolveExprFixities elseBranch
    RCase scrutinee alternatives ->
      RCase <$> resolveExprFixities scrutinee <*> traverse resolveAlt alternatives
    RDo statements ->
      RDo <$> traverse resolveStmt statements
    RList expressions ->
      RList <$> traverse resolveExprFixities expressions
    RTuple expressions ->
      RTuple <$> traverse resolveExprFixities expressions
    RParen inner ->
      RParen <$> resolveExprFixities inner
    RLeftSection sectionExpr op ->
      RLeftSection <$> resolveExprFixities sectionExpr <*> pure op
    RRightSection op sectionExpr ->
      RRightSection op <$> resolveExprFixities sectionExpr
    RArithmeticSeq start step end ->
      RArithmeticSeq <$> resolveExprFixities start <*> traverse resolveExprFixities step <*> traverse resolveExprFixities end
    RListComp body statements ->
      RListComp <$> resolveExprFixities body <*> traverse resolveStmt statements
    RExprTypeSig inner sourceType ->
      RExprTypeSig <$> resolveExprFixities inner <*> pure sourceType
    _ ->
      pure expr

resolveRest :: (RName, RExpr) -> RenameM (RName, RExpr)
resolveRest (op, operand) =
  (op,) <$> resolveExprFixities operand

resolveAlt :: RAlt -> RenameM RAlt
resolveAlt (RAlt pat rhs whereDecls) =
  RAlt pat <$> resolveRhs rhs <*> pure whereDecls

resolveRhs :: RRhs -> RenameM RRhs
resolveRhs = \case
  RUnguarded expr ->
    RUnguarded <$> resolveExprFixities expr
  RGuarded branches ->
    RGuarded <$> traverse (\(guardExpr, bodyExpr) -> (,) <$> resolveExprFixities guardExpr <*> resolveExprFixities bodyExpr) branches

resolveStmt :: RStmt -> RenameM RStmt
resolveStmt = \case
  RBindStmt pat expr ->
    RBindStmt pat <$> resolveExprFixities expr
  RLetStmt decls ->
    pure (RLetStmt decls)
  RExprStmt expr ->
    RExprStmt <$> resolveExprFixities expr

flattenInfix :: RExpr -> (RExpr, [(RName, RExpr)])
flattenInfix = \case
  RInfixApp lhs op rhs ->
    let (firstOperand, rest) = flattenInfix lhs
     in (firstOperand, rest <> [(op, rhs)])
  other ->
    (other, [])

resolveInfixChain :: RExpr -> [(RName, RExpr)] -> RenameM RExpr
resolveInfixChain firstOperand rest = do
  ensureCompatibleFixities (fst <$> rest)
  fst <$> climb 0 firstOperand rest
 where
  climb _ lhs [] =
    pure (lhs, [])
  climb minPrecedence lhs allRest@((op, rhs) : more) = do
    S.Fixity assoc precedence <- fixityForCurrentName op
    if precedence < minPrecedence
      then pure (lhs, allRest)
      else do
        let nextMinPrecedence =
              case assoc of
                S.InfixL -> precedence + 1
                S.InfixR -> precedence
                S.InfixN -> precedence + 1
        (newRhs, remaining) <- climb nextMinPrecedence rhs more
        climb minPrecedence (RInfixApp lhs op newRhs) remaining

ensureCompatibleFixities :: [RName] -> RenameM ()
ensureCompatibleFixities operators =
  mapM_ checkPair (zip operators (drop 1 operators))
 where
  checkPair (lhs, rhs) = do
    lhsFixity@(S.Fixity lhsAssoc lhsPrecedence) <- fixityForCurrentName lhs
    rhsFixity@(S.Fixity rhsAssoc rhsPrecedence) <- fixityForCurrentName rhs
    when
      ( lhsPrecedence == rhsPrecedence
          && (lhsAssoc == S.InfixN || rhsAssoc == S.InfixN || lhsAssoc /= rhsAssoc)
      )
      . throwRename
      $ InvalidFixityUse
        ( "cannot mix `"
            <> nameOcc lhs
            <> "` ("
            <> Text.pack (show lhsFixity)
            <> ") and `"
            <> nameOcc rhs
            <> "` ("
            <> Text.pack (show rhsFixity)
            <> ") at the same precedence without parentheses"
        )

typeVarsInTypes :: [S.HsType] -> [Text]
typeVarsInTypes =
  List.nub . concatMap typeVarsInType

typeVarsInType :: S.HsType -> [Text]
typeVarsInType =
  List.nub . collect
 where
  collect = \case
    S.TyVar occ -> [occ]
    S.TyCon {} -> []
    S.TyApp lhs rhs -> collect lhs <> collect rhs
    S.TyFun lhs rhs -> collect lhs <> collect rhs
    S.TyContext context body -> concatMap collect context <> collect body
    S.TyTuple types -> concatMap collect types
    S.TyList elementType -> collect elementType
    S.TyParen inner -> collect inner

fixityForCurrentName :: RName -> RenameM S.Fixity
fixityForCurrentName name =
  Map.findWithDefault defaultFixity (nameOcc name) . fixities <$> get

defaultFixity :: S.Fixity
defaultFixity =
  S.Fixity S.InfixL 9

preludeFixities :: Map.Map Text S.Fixity
preludeFixities =
  Map.fromList
    [ (":", S.Fixity S.InfixR 5)
    , ("++", S.Fixity S.InfixR 5)
    , ("+", S.Fixity S.InfixL 6)
    , ("-", S.Fixity S.InfixL 6)
    , ("*", S.Fixity S.InfixL 7)
    , ("/", S.Fixity S.InfixL 7)
    , ("==", S.Fixity S.InfixN 4)
    , ("/=", S.Fixity S.InfixN 4)
    , ("<", S.Fixity S.InfixN 4)
    , ("<=", S.Fixity S.InfixN 4)
    , (">", S.Fixity S.InfixN 4)
    , (">=", S.Fixity S.InfixN 4)
    , ("&&", S.Fixity S.InfixR 3)
    , ("||", S.Fixity S.InfixR 2)
    , (">>=", S.Fixity S.InfixL 1)
    , (">>", S.Fixity S.InfixL 1)
    , ("$", S.Fixity S.InfixR 0)
    , (".", S.Fixity S.InfixR 9)
    ]

preludeNames :: [(Namespace, Text)]
preludeNames =
  fmap (TermNamespace,)
    [ "+"
    , "-"
    , "*"
    , "/"
    , "=="
    , "/="
    , "<"
    , "<="
    , ">"
    , ">="
    , "&&"
    , "||"
    , "++"
    , ">>="
    , ">>"
    , "$"
    , "."
    , "pure"
    , "return"
    , "fmap"
    , "map"
    , "id"
    , "const"
    , "otherwise"
    ]
    <> fmap (ConstructorNamespace,) ["True", "False", "Nothing", "Just", "Left", "Right", "LT", "EQ", "GT", ":"]
    <> fmap (TypeNamespace,) ["Int", "Integer", "Bool", "Char", "String", "IO", "CString", "Maybe", "Either", "Ordering", "()"]
    <> fmap (ClassNamespace,) ["Eq", "Ord", "Show", "Num", "Enum", "Bounded", "Functor", "Monad"]

isConstructorLike :: Text -> Bool
isConstructorLike text =
  case Text.uncons text of
    Just (char, _) -> isUpper char
    Nothing -> False

isConstructorOperator :: Text -> Bool
isConstructorOperator =
  Text.isPrefixOf ":"

lookupOperatorName :: Text -> RenameM RName
lookupOperatorName occ
  | isConstructorOperator occ =
      lookupName ConstructorNamespace occ
  | otherwise =
      lookupName TermNamespace occ `orElseRename` lookupName ConstructorNamespace occ

throwRename :: RenameError -> RenameM a
throwRename =
  lift . Left
