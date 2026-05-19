{-# LANGUAGE PatternSynonyms #-}

module Haskell2010.Syntax
  ( Alt (Alt)
  , Assoc (..)
  , ConDecl (ConDecl)
  , Decl
      ( TypeSignature
      , FunctionBinding
      , PatternBinding
      , FixityDecl
      , DataDecl
      , NewtypeDecl
      , TypeSynonym
      , ClassDecl
      , InstanceDecl
      , DefaultDecl
      , ForeignDecl
      )
  , Export (..)
  , Expr
      ( Var
      , Con
      , Lit
      , App
      , InfixApp
      , Lambda
      , Let
      , If
      , Case
      , Do
      , List
      , Tuple
      , Unit
      , Paren
      , LeftSection
      , RightSection
      , ArithmeticSeq
      , ListComp
      , ExprTypeSig
      )
  , Fixity (..)
  , HsModule (..)
  , HsType
      ( TyVar
      , TyCon
      , TyApp
      , TyFun
      , TyContext
      , TyTuple
      , TyList
      , TyParen
      )
  , ImportDecl (..)
  , ImportSpec (..)
  , Literal (..)
  , ModuleName (..)
  , Pat
      ( PVar
      , PCon
      , PLit
      , PWildcard
      , PTuple
      , PList
      , PAs
      , PIrrefutable
      , PParen
      )
  , Rhs (Unguarded, Guarded)
  , Stmt (BindStmt, LetStmt, ExprStmt)
  , altSpan
  , conDeclSpan
  , declSpan
  , exprSpan
  , hsTypeSpan
  , patSpan
  , rhsSpan
  , setAltSpan
  , setConDeclSpan
  , setDeclSpan
  , setExprSpan
  , setHsTypeSpan
  , setPatSpan
  , setRhsSpan
  , setStmtSpan
  , stmtSpan
  )
where

import Data.Text (Text)
import Syntax.Span (SourceSpan)

newtype ModuleName = ModuleName [Text]
  deriving stock (Show, Eq, Ord)

data HsModule = HsModule
  { moduleName :: Maybe ModuleName
  , moduleExports :: Maybe [Export]
  , moduleImports :: [ImportDecl]
  , moduleDecls :: [Decl]
  }
  deriving stock (Show, Eq, Ord)

data Export
  = ExportName Text
  | ExportThing Text [Text]
  | ExportModule ModuleName
  deriving stock (Show, Eq, Ord)

data ImportDecl = ImportDecl
  { importQualified :: Bool
  , importModule :: ModuleName
  , importAs :: Maybe ModuleName
  , importSpecs :: Maybe ([ImportSpec], Bool)
  }
  deriving stock (Show, Eq, Ord)

data ImportSpec
  = ImportName Text
  | ImportThing Text [Text]
  deriving stock (Show, Eq, Ord)

data Decl = SpannedDecl (Maybe SourceSpan) DeclNode
  deriving stock (Show, Eq, Ord)

data DeclNode
  = TypeSignatureNode [Text] HsType
  | FunctionBindingNode Text [Pat] Rhs [Decl]
  | PatternBindingNode Pat Rhs [Decl]
  | FixityDeclNode Fixity [Text]
  | DataDeclNode Text [Text] [ConDecl] [Text]
  | NewtypeDeclNode Text [Text] ConDecl [Text]
  | TypeSynonymNode Text [Text] HsType
  | ClassDeclNode [HsType] Text Text [Decl]
  | InstanceDeclNode [HsType] HsType [Decl]
  | DefaultDeclNode [HsType]
  | ForeignDeclNode Text
  deriving stock (Show, Eq, Ord)

pattern TypeSignature :: [Text] -> HsType -> Decl
pattern TypeSignature names sourceType <- SpannedDecl _ (TypeSignatureNode names sourceType)
  where
    TypeSignature names sourceType = SpannedDecl Nothing (TypeSignatureNode names sourceType)

pattern FunctionBinding :: Text -> [Pat] -> Rhs -> [Decl] -> Decl
pattern FunctionBinding name patterns rhs whereDecls <- SpannedDecl _ (FunctionBindingNode name patterns rhs whereDecls)
  where
    FunctionBinding name patterns rhs whereDecls = SpannedDecl Nothing (FunctionBindingNode name patterns rhs whereDecls)

pattern PatternBinding :: Pat -> Rhs -> [Decl] -> Decl
pattern PatternBinding pat rhs whereDecls <- SpannedDecl _ (PatternBindingNode pat rhs whereDecls)
  where
    PatternBinding pat rhs whereDecls = SpannedDecl Nothing (PatternBindingNode pat rhs whereDecls)

pattern FixityDecl :: Fixity -> [Text] -> Decl
pattern FixityDecl fixity names <- SpannedDecl _ (FixityDeclNode fixity names)
  where
    FixityDecl fixity names = SpannedDecl Nothing (FixityDeclNode fixity names)

pattern DataDecl :: Text -> [Text] -> [ConDecl] -> [Text] -> Decl
pattern DataDecl name params constructors derivingNames <- SpannedDecl _ (DataDeclNode name params constructors derivingNames)
  where
    DataDecl name params constructors derivingNames = SpannedDecl Nothing (DataDeclNode name params constructors derivingNames)

pattern NewtypeDecl :: Text -> [Text] -> ConDecl -> [Text] -> Decl
pattern NewtypeDecl name params constructor derivingNames <- SpannedDecl _ (NewtypeDeclNode name params constructor derivingNames)
  where
    NewtypeDecl name params constructor derivingNames = SpannedDecl Nothing (NewtypeDeclNode name params constructor derivingNames)

pattern TypeSynonym :: Text -> [Text] -> HsType -> Decl
pattern TypeSynonym name params sourceType <- SpannedDecl _ (TypeSynonymNode name params sourceType)
  where
    TypeSynonym name params sourceType = SpannedDecl Nothing (TypeSynonymNode name params sourceType)

pattern ClassDecl :: [HsType] -> Text -> Text -> [Decl] -> Decl
pattern ClassDecl context className typeVariable decls <- SpannedDecl _ (ClassDeclNode context className typeVariable decls)
  where
    ClassDecl context className typeVariable decls = SpannedDecl Nothing (ClassDeclNode context className typeVariable decls)

pattern InstanceDecl :: [HsType] -> HsType -> [Decl] -> Decl
pattern InstanceDecl context sourceType decls <- SpannedDecl _ (InstanceDeclNode context sourceType decls)
  where
    InstanceDecl context sourceType decls = SpannedDecl Nothing (InstanceDeclNode context sourceType decls)

pattern DefaultDecl :: [HsType] -> Decl
pattern DefaultDecl types <- SpannedDecl _ (DefaultDeclNode types)
  where
    DefaultDecl types = SpannedDecl Nothing (DefaultDeclNode types)

pattern ForeignDecl :: Text -> Decl
pattern ForeignDecl text <- SpannedDecl _ (ForeignDeclNode text)
  where
    ForeignDecl text = SpannedDecl Nothing (ForeignDeclNode text)

{-# COMPLETE TypeSignature, FunctionBinding, PatternBinding, FixityDecl, DataDecl, NewtypeDecl, TypeSynonym, ClassDecl, InstanceDecl, DefaultDecl, ForeignDecl #-}

declSpan :: Decl -> Maybe SourceSpan
declSpan (SpannedDecl sourceRange _) =
  sourceRange

setDeclSpan :: SourceSpan -> Decl -> Decl
setDeclSpan sourceRange (SpannedDecl _ node) =
  SpannedDecl (Just sourceRange) node

data Fixity = Fixity Assoc Int
  deriving stock (Show, Eq, Ord)

data Assoc
  = InfixL
  | InfixR
  | InfixN
  deriving stock (Show, Eq, Ord)

data ConDecl = SpannedConDecl (Maybe SourceSpan) Text [HsType]
  deriving stock (Show, Eq, Ord)

pattern ConDecl :: Text -> [HsType] -> ConDecl
pattern ConDecl name fields <- SpannedConDecl _ name fields
  where
    ConDecl name fields = SpannedConDecl Nothing name fields

{-# COMPLETE ConDecl #-}

conDeclSpan :: ConDecl -> Maybe SourceSpan
conDeclSpan (SpannedConDecl sourceRange _ _) =
  sourceRange

setConDeclSpan :: SourceSpan -> ConDecl -> ConDecl
setConDeclSpan sourceRange (SpannedConDecl _ name fields) =
  SpannedConDecl (Just sourceRange) name fields

data Rhs = SpannedRhs (Maybe SourceSpan) RhsNode
  deriving stock (Show, Eq, Ord)

data RhsNode
  = UnguardedNode Expr
  | GuardedNode [(Expr, Expr)]
  deriving stock (Show, Eq, Ord)

pattern Unguarded :: Expr -> Rhs
pattern Unguarded expr <- SpannedRhs _ (UnguardedNode expr)
  where
    Unguarded expr = SpannedRhs Nothing (UnguardedNode expr)

pattern Guarded :: [(Expr, Expr)] -> Rhs
pattern Guarded branches <- SpannedRhs _ (GuardedNode branches)
  where
    Guarded branches = SpannedRhs Nothing (GuardedNode branches)

{-# COMPLETE Unguarded, Guarded #-}

rhsSpan :: Rhs -> Maybe SourceSpan
rhsSpan (SpannedRhs sourceRange _) =
  sourceRange

setRhsSpan :: SourceSpan -> Rhs -> Rhs
setRhsSpan sourceRange (SpannedRhs _ node) =
  SpannedRhs (Just sourceRange) node

data Expr = SpannedExpr (Maybe SourceSpan) ExprNode
  deriving stock (Show, Eq, Ord)

data ExprNode
  = VarNode Text
  | ConNode Text
  | LitNode Literal
  | AppNode Expr Expr
  | InfixAppNode Expr Text Expr
  | LambdaNode [Pat] Expr
  | LetNode [Decl] Expr
  | IfNode Expr Expr Expr
  | CaseNode Expr [Alt]
  | DoNode [Stmt]
  | ListNode [Expr]
  | TupleNode [Expr]
  | UnitNode
  | ParenNode Expr
  | LeftSectionNode Expr Text
  | RightSectionNode Text Expr
  | ArithmeticSeqNode Expr (Maybe Expr) (Maybe Expr)
  | ListCompNode Expr [Stmt]
  | ExprTypeSigNode Expr HsType
  deriving stock (Show, Eq, Ord)

pattern Var :: Text -> Expr
pattern Var name <- SpannedExpr _ (VarNode name)
  where
    Var name = SpannedExpr Nothing (VarNode name)

pattern Con :: Text -> Expr
pattern Con name <- SpannedExpr _ (ConNode name)
  where
    Con name = SpannedExpr Nothing (ConNode name)

pattern Lit :: Literal -> Expr
pattern Lit literal <- SpannedExpr _ (LitNode literal)
  where
    Lit literal = SpannedExpr Nothing (LitNode literal)

pattern App :: Expr -> Expr -> Expr
pattern App function argument <- SpannedExpr _ (AppNode function argument)
  where
    App function argument = SpannedExpr Nothing (AppNode function argument)

pattern InfixApp :: Expr -> Text -> Expr -> Expr
pattern InfixApp lhs op rhs <- SpannedExpr _ (InfixAppNode lhs op rhs)
  where
    InfixApp lhs op rhs = SpannedExpr Nothing (InfixAppNode lhs op rhs)

pattern Lambda :: [Pat] -> Expr -> Expr
pattern Lambda patterns body <- SpannedExpr _ (LambdaNode patterns body)
  where
    Lambda patterns body = SpannedExpr Nothing (LambdaNode patterns body)

pattern Let :: [Decl] -> Expr -> Expr
pattern Let decls body <- SpannedExpr _ (LetNode decls body)
  where
    Let decls body = SpannedExpr Nothing (LetNode decls body)

pattern If :: Expr -> Expr -> Expr -> Expr
pattern If condition thenBranch elseBranch <- SpannedExpr _ (IfNode condition thenBranch elseBranch)
  where
    If condition thenBranch elseBranch = SpannedExpr Nothing (IfNode condition thenBranch elseBranch)

pattern Case :: Expr -> [Alt] -> Expr
pattern Case scrutinee alternatives <- SpannedExpr _ (CaseNode scrutinee alternatives)
  where
    Case scrutinee alternatives = SpannedExpr Nothing (CaseNode scrutinee alternatives)

pattern Do :: [Stmt] -> Expr
pattern Do statements <- SpannedExpr _ (DoNode statements)
  where
    Do statements = SpannedExpr Nothing (DoNode statements)

pattern List :: [Expr] -> Expr
pattern List expressions <- SpannedExpr _ (ListNode expressions)
  where
    List expressions = SpannedExpr Nothing (ListNode expressions)

pattern Tuple :: [Expr] -> Expr
pattern Tuple expressions <- SpannedExpr _ (TupleNode expressions)
  where
    Tuple expressions = SpannedExpr Nothing (TupleNode expressions)

pattern Unit :: Expr
pattern Unit <- SpannedExpr _ UnitNode
  where
    Unit = SpannedExpr Nothing UnitNode

pattern Paren :: Expr -> Expr
pattern Paren inner <- SpannedExpr _ (ParenNode inner)
  where
    Paren inner = SpannedExpr Nothing (ParenNode inner)

pattern LeftSection :: Expr -> Text -> Expr
pattern LeftSection expr op <- SpannedExpr _ (LeftSectionNode expr op)
  where
    LeftSection expr op = SpannedExpr Nothing (LeftSectionNode expr op)

pattern RightSection :: Text -> Expr -> Expr
pattern RightSection op expr <- SpannedExpr _ (RightSectionNode op expr)
  where
    RightSection op expr = SpannedExpr Nothing (RightSectionNode op expr)

pattern ArithmeticSeq :: Expr -> Maybe Expr -> Maybe Expr -> Expr
pattern ArithmeticSeq start step end <- SpannedExpr _ (ArithmeticSeqNode start step end)
  where
    ArithmeticSeq start step end = SpannedExpr Nothing (ArithmeticSeqNode start step end)

pattern ListComp :: Expr -> [Stmt] -> Expr
pattern ListComp body statements <- SpannedExpr _ (ListCompNode body statements)
  where
    ListComp body statements = SpannedExpr Nothing (ListCompNode body statements)

pattern ExprTypeSig :: Expr -> HsType -> Expr
pattern ExprTypeSig expr sourceType <- SpannedExpr _ (ExprTypeSigNode expr sourceType)
  where
    ExprTypeSig expr sourceType = SpannedExpr Nothing (ExprTypeSigNode expr sourceType)

{-# COMPLETE Var, Con, Lit, App, InfixApp, Lambda, Let, If, Case, Do, List, Tuple, Unit, Paren, LeftSection, RightSection, ArithmeticSeq, ListComp, ExprTypeSig #-}

exprSpan :: Expr -> Maybe SourceSpan
exprSpan (SpannedExpr sourceRange _) =
  sourceRange

setExprSpan :: SourceSpan -> Expr -> Expr
setExprSpan sourceRange (SpannedExpr _ node) =
  SpannedExpr (Just sourceRange) node

data Stmt = SpannedStmt (Maybe SourceSpan) StmtNode
  deriving stock (Show, Eq, Ord)

data StmtNode
  = BindStmtNode Pat Expr
  | LetStmtNode [Decl]
  | ExprStmtNode Expr
  deriving stock (Show, Eq, Ord)

pattern BindStmt :: Pat -> Expr -> Stmt
pattern BindStmt pat expr <- SpannedStmt _ (BindStmtNode pat expr)
  where
    BindStmt pat expr = SpannedStmt Nothing (BindStmtNode pat expr)

pattern LetStmt :: [Decl] -> Stmt
pattern LetStmt decls <- SpannedStmt _ (LetStmtNode decls)
  where
    LetStmt decls = SpannedStmt Nothing (LetStmtNode decls)

pattern ExprStmt :: Expr -> Stmt
pattern ExprStmt expr <- SpannedStmt _ (ExprStmtNode expr)
  where
    ExprStmt expr = SpannedStmt Nothing (ExprStmtNode expr)

{-# COMPLETE BindStmt, LetStmt, ExprStmt #-}

stmtSpan :: Stmt -> Maybe SourceSpan
stmtSpan (SpannedStmt sourceRange _) =
  sourceRange

setStmtSpan :: SourceSpan -> Stmt -> Stmt
setStmtSpan sourceRange (SpannedStmt _ node) =
  SpannedStmt (Just sourceRange) node

data Alt = SpannedAlt (Maybe SourceSpan) Pat Rhs [Decl]
  deriving stock (Show, Eq, Ord)

pattern Alt :: Pat -> Rhs -> [Decl] -> Alt
pattern Alt pat rhs whereDecls <- SpannedAlt _ pat rhs whereDecls
  where
    Alt pat rhs whereDecls = SpannedAlt Nothing pat rhs whereDecls

{-# COMPLETE Alt #-}

altSpan :: Alt -> Maybe SourceSpan
altSpan (SpannedAlt sourceRange _ _ _) =
  sourceRange

setAltSpan :: SourceSpan -> Alt -> Alt
setAltSpan sourceRange (SpannedAlt _ pat rhs whereDecls) =
  SpannedAlt (Just sourceRange) pat rhs whereDecls

data Pat = SpannedPat (Maybe SourceSpan) PatNode
  deriving stock (Show, Eq, Ord)

data PatNode
  = PVarNode Text
  | PConNode Text [Pat]
  | PLitNode Literal
  | PWildcardNode
  | PTupleNode [Pat]
  | PListNode [Pat]
  | PAsNode Text Pat
  | PIrrefutableNode Pat
  | PParenNode Pat
  deriving stock (Show, Eq, Ord)

pattern PVar :: Text -> Pat
pattern PVar name <- SpannedPat _ (PVarNode name)
  where
    PVar name = SpannedPat Nothing (PVarNode name)

pattern PCon :: Text -> [Pat] -> Pat
pattern PCon name patterns <- SpannedPat _ (PConNode name patterns)
  where
    PCon name patterns = SpannedPat Nothing (PConNode name patterns)

pattern PLit :: Literal -> Pat
pattern PLit literal <- SpannedPat _ (PLitNode literal)
  where
    PLit literal = SpannedPat Nothing (PLitNode literal)

pattern PWildcard :: Pat
pattern PWildcard <- SpannedPat _ PWildcardNode
  where
    PWildcard = SpannedPat Nothing PWildcardNode

pattern PTuple :: [Pat] -> Pat
pattern PTuple patterns <- SpannedPat _ (PTupleNode patterns)
  where
    PTuple patterns = SpannedPat Nothing (PTupleNode patterns)

pattern PList :: [Pat] -> Pat
pattern PList patterns <- SpannedPat _ (PListNode patterns)
  where
    PList patterns = SpannedPat Nothing (PListNode patterns)

pattern PAs :: Text -> Pat -> Pat
pattern PAs name pat <- SpannedPat _ (PAsNode name pat)
  where
    PAs name pat = SpannedPat Nothing (PAsNode name pat)

pattern PIrrefutable :: Pat -> Pat
pattern PIrrefutable pat <- SpannedPat _ (PIrrefutableNode pat)
  where
    PIrrefutable pat = SpannedPat Nothing (PIrrefutableNode pat)

pattern PParen :: Pat -> Pat
pattern PParen pat <- SpannedPat _ (PParenNode pat)
  where
    PParen pat = SpannedPat Nothing (PParenNode pat)

{-# COMPLETE PVar, PCon, PLit, PWildcard, PTuple, PList, PAs, PIrrefutable, PParen #-}

patSpan :: Pat -> Maybe SourceSpan
patSpan (SpannedPat sourceRange _) =
  sourceRange

setPatSpan :: SourceSpan -> Pat -> Pat
setPatSpan sourceRange (SpannedPat _ node) =
  SpannedPat (Just sourceRange) node

data Literal
  = LInt Integer
  | LChar Char
  | LString Text
  deriving stock (Show, Eq, Ord)

data HsType = SpannedHsType (Maybe SourceSpan) HsTypeNode
  deriving stock (Show, Eq, Ord)

data HsTypeNode
  = TyVarNode Text
  | TyConNode Text
  | TyAppNode HsType HsType
  | TyFunNode HsType HsType
  | TyContextNode [HsType] HsType
  | TyTupleNode [HsType]
  | TyListNode HsType
  | TyParenNode HsType
  deriving stock (Show, Eq, Ord)

pattern TyVar :: Text -> HsType
pattern TyVar name <- SpannedHsType _ (TyVarNode name)
  where
    TyVar name = SpannedHsType Nothing (TyVarNode name)

pattern TyCon :: Text -> HsType
pattern TyCon name <- SpannedHsType _ (TyConNode name)
  where
    TyCon name = SpannedHsType Nothing (TyConNode name)

pattern TyApp :: HsType -> HsType -> HsType
pattern TyApp fn arg <- SpannedHsType _ (TyAppNode fn arg)
  where
    TyApp fn arg = SpannedHsType Nothing (TyAppNode fn arg)

pattern TyFun :: HsType -> HsType -> HsType
pattern TyFun arg result <- SpannedHsType _ (TyFunNode arg result)
  where
    TyFun arg result = SpannedHsType Nothing (TyFunNode arg result)

pattern TyContext :: [HsType] -> HsType -> HsType
pattern TyContext context body <- SpannedHsType _ (TyContextNode context body)
  where
    TyContext context body = SpannedHsType Nothing (TyContextNode context body)

pattern TyTuple :: [HsType] -> HsType
pattern TyTuple types <- SpannedHsType _ (TyTupleNode types)
  where
    TyTuple types = SpannedHsType Nothing (TyTupleNode types)

pattern TyList :: HsType -> HsType
pattern TyList elementType <- SpannedHsType _ (TyListNode elementType)
  where
    TyList elementType = SpannedHsType Nothing (TyListNode elementType)

pattern TyParen :: HsType -> HsType
pattern TyParen inner <- SpannedHsType _ (TyParenNode inner)
  where
    TyParen inner = SpannedHsType Nothing (TyParenNode inner)

{-# COMPLETE TyVar, TyCon, TyApp, TyFun, TyContext, TyTuple, TyList, TyParen #-}

hsTypeSpan :: HsType -> Maybe SourceSpan
hsTypeSpan (SpannedHsType sourceRange _) =
  sourceRange

setHsTypeSpan :: SourceSpan -> HsType -> HsType
setHsTypeSpan sourceRange (SpannedHsType _ node) =
  SpannedHsType (Just sourceRange) node
