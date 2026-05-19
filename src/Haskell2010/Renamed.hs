{-# LANGUAGE PatternSynonyms #-}

module Haskell2010.Renamed
  ( RAlt (RAlt)
  , RConDecl (RConDecl)
  , RDecl
      ( RTypeSignature
      , RFunctionBinding
      , RPatternBinding
      , RFixityDecl
      , RDataDecl
      , RNewtypeDecl
      , RTypeSynonym
      , RClassDecl
      , RInstanceDecl
      , RDefaultDecl
      , RForeignDecl
      )
  , RExpr
      ( RVar
      , RCon
      , RLit
      , RApp
      , RInfixApp
      , RLambda
      , RLet
      , RIf
      , RCase
      , RDo
      , RList
      , RTuple
      , RUnit
      , RParen
      , RLeftSection
      , RRightSection
      , RArithmeticSeq
      , RListComp
      , RExprTypeSig
      )
  , RExport (..)
  , RHsModule (..)
  , RHsType
      ( RTyVar
      , RTyCon
      , RTyApp
      , RTyFun
      , RTyContext
      , RTyTuple
      , RTyList
      , RTyParen
      )
  , RImportDecl (..)
  , RPat
      ( RPVar
      , RPCon
      , RPLit
      , RPWildcard
      , RPTuple
      , RPList
      , RPAs
      , RPIrrefutable
      , RPParen
      )
  , RRhs (RUnguarded, RGuarded)
  , RStmt (RBindStmt, RLetStmt, RExprStmt)
  , rAltSpan
  , rConDeclSpan
  , rDeclSpan
  , rExprSpan
  , rPatSpan
  , rRhsSpan
  , rStmtSpan
  , rTypeSpan
  , setRAltSpan
  , setRConDeclSpan
  , setRDeclSpan
  , setRExprSpan
  , setRPatSpan
  , setRRhsSpan
  , setRStmtSpan
  , setRTypeSpan
  )
where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Haskell2010.Names (RName)
import Haskell2010.Syntax (Fixity, ImportDecl, Literal, ModuleName)
import Syntax.Span (SourceSpan)

data RHsModule = RHsModule
  { rModuleName :: Maybe ModuleName
  , rModuleExports :: Maybe [RExport]
  , rModuleImports :: [RImportDecl]
  , rModuleFixities :: Map.Map RName Fixity
  , rModuleDecls :: [RDecl]
  }
  deriving stock (Show, Eq, Ord)

data RExport
  = RExportName RName
  | RExportThing RName [Text]
  | RExportModule ModuleName
  deriving stock (Show, Eq, Ord)

newtype RImportDecl = RImportDecl ImportDecl
  deriving stock (Show, Eq, Ord)

data RDecl = SpannedRDecl (Maybe SourceSpan) RDeclNode
  deriving stock (Show, Eq, Ord)

data RDeclNode
  = RTypeSignatureNode [RName] RHsType
  | RFunctionBindingNode RName [RPat] RRhs [RDecl]
  | RPatternBindingNode RPat RRhs [RDecl]
  | RFixityDeclNode Fixity [RName]
  | RDataDeclNode RName [RName] [RConDecl] [RName]
  | RNewtypeDeclNode RName [RName] RConDecl [RName]
  | RTypeSynonymNode RName [RName] RHsType
  | RClassDeclNode [RHsType] RName RName [RDecl]
  | RInstanceDeclNode [RHsType] RHsType [RDecl]
  | RDefaultDeclNode [RHsType]
  | RForeignDeclNode Text
  deriving stock (Show, Eq, Ord)

pattern RTypeSignature :: [RName] -> RHsType -> RDecl
pattern RTypeSignature names sourceType <- SpannedRDecl _ (RTypeSignatureNode names sourceType)
  where
    RTypeSignature names sourceType = SpannedRDecl Nothing (RTypeSignatureNode names sourceType)

pattern RFunctionBinding :: RName -> [RPat] -> RRhs -> [RDecl] -> RDecl
pattern RFunctionBinding name patterns rhs whereDecls <- SpannedRDecl _ (RFunctionBindingNode name patterns rhs whereDecls)
  where
    RFunctionBinding name patterns rhs whereDecls = SpannedRDecl Nothing (RFunctionBindingNode name patterns rhs whereDecls)

pattern RPatternBinding :: RPat -> RRhs -> [RDecl] -> RDecl
pattern RPatternBinding pat rhs whereDecls <- SpannedRDecl _ (RPatternBindingNode pat rhs whereDecls)
  where
    RPatternBinding pat rhs whereDecls = SpannedRDecl Nothing (RPatternBindingNode pat rhs whereDecls)

pattern RFixityDecl :: Fixity -> [RName] -> RDecl
pattern RFixityDecl fixity names <- SpannedRDecl _ (RFixityDeclNode fixity names)
  where
    RFixityDecl fixity names = SpannedRDecl Nothing (RFixityDeclNode fixity names)

pattern RDataDecl :: RName -> [RName] -> [RConDecl] -> [RName] -> RDecl
pattern RDataDecl name params constructors derivingNames <- SpannedRDecl _ (RDataDeclNode name params constructors derivingNames)
  where
    RDataDecl name params constructors derivingNames = SpannedRDecl Nothing (RDataDeclNode name params constructors derivingNames)

pattern RNewtypeDecl :: RName -> [RName] -> RConDecl -> [RName] -> RDecl
pattern RNewtypeDecl name params constructor derivingNames <- SpannedRDecl _ (RNewtypeDeclNode name params constructor derivingNames)
  where
    RNewtypeDecl name params constructor derivingNames = SpannedRDecl Nothing (RNewtypeDeclNode name params constructor derivingNames)

pattern RTypeSynonym :: RName -> [RName] -> RHsType -> RDecl
pattern RTypeSynonym name params sourceType <- SpannedRDecl _ (RTypeSynonymNode name params sourceType)
  where
    RTypeSynonym name params sourceType = SpannedRDecl Nothing (RTypeSynonymNode name params sourceType)

pattern RClassDecl :: [RHsType] -> RName -> RName -> [RDecl] -> RDecl
pattern RClassDecl context className typeVariable decls <- SpannedRDecl _ (RClassDeclNode context className typeVariable decls)
  where
    RClassDecl context className typeVariable decls = SpannedRDecl Nothing (RClassDeclNode context className typeVariable decls)

pattern RInstanceDecl :: [RHsType] -> RHsType -> [RDecl] -> RDecl
pattern RInstanceDecl context sourceType decls <- SpannedRDecl _ (RInstanceDeclNode context sourceType decls)
  where
    RInstanceDecl context sourceType decls = SpannedRDecl Nothing (RInstanceDeclNode context sourceType decls)

pattern RDefaultDecl :: [RHsType] -> RDecl
pattern RDefaultDecl types <- SpannedRDecl _ (RDefaultDeclNode types)
  where
    RDefaultDecl types = SpannedRDecl Nothing (RDefaultDeclNode types)

pattern RForeignDecl :: Text -> RDecl
pattern RForeignDecl text <- SpannedRDecl _ (RForeignDeclNode text)
  where
    RForeignDecl text = SpannedRDecl Nothing (RForeignDeclNode text)

{-# COMPLETE RTypeSignature, RFunctionBinding, RPatternBinding, RFixityDecl, RDataDecl, RNewtypeDecl, RTypeSynonym, RClassDecl, RInstanceDecl, RDefaultDecl, RForeignDecl #-}

rDeclSpan :: RDecl -> Maybe SourceSpan
rDeclSpan (SpannedRDecl sourceRange _) =
  sourceRange

setRDeclSpan :: SourceSpan -> RDecl -> RDecl
setRDeclSpan sourceRange (SpannedRDecl _ node) =
  SpannedRDecl (Just sourceRange) node

data RConDecl = SpannedRConDecl (Maybe SourceSpan) RName [RHsType]
  deriving stock (Show, Eq, Ord)

pattern RConDecl :: RName -> [RHsType] -> RConDecl
pattern RConDecl name fields <- SpannedRConDecl _ name fields
  where
    RConDecl name fields = SpannedRConDecl Nothing name fields

{-# COMPLETE RConDecl #-}

rConDeclSpan :: RConDecl -> Maybe SourceSpan
rConDeclSpan (SpannedRConDecl sourceRange _ _) =
  sourceRange

setRConDeclSpan :: SourceSpan -> RConDecl -> RConDecl
setRConDeclSpan sourceRange (SpannedRConDecl _ name fields) =
  SpannedRConDecl (Just sourceRange) name fields

data RRhs = SpannedRRhs (Maybe SourceSpan) RRhsNode
  deriving stock (Show, Eq, Ord)

data RRhsNode
  = RUnguardedNode RExpr
  | RGuardedNode [(RExpr, RExpr)]
  deriving stock (Show, Eq, Ord)

pattern RUnguarded :: RExpr -> RRhs
pattern RUnguarded expr <- SpannedRRhs _ (RUnguardedNode expr)
  where
    RUnguarded expr = SpannedRRhs Nothing (RUnguardedNode expr)

pattern RGuarded :: [(RExpr, RExpr)] -> RRhs
pattern RGuarded branches <- SpannedRRhs _ (RGuardedNode branches)
  where
    RGuarded branches = SpannedRRhs Nothing (RGuardedNode branches)

{-# COMPLETE RUnguarded, RGuarded #-}

rRhsSpan :: RRhs -> Maybe SourceSpan
rRhsSpan (SpannedRRhs sourceRange _) =
  sourceRange

setRRhsSpan :: SourceSpan -> RRhs -> RRhs
setRRhsSpan sourceRange (SpannedRRhs _ node) =
  SpannedRRhs (Just sourceRange) node

data RExpr = SpannedRExpr (Maybe SourceSpan) RExprNode
  deriving stock (Show, Eq, Ord)

data RExprNode
  = RVarNode RName
  | RConNode RName
  | RLitNode Literal
  | RAppNode RExpr RExpr
  | RInfixAppNode RExpr RName RExpr
  | RLambdaNode [RPat] RExpr
  | RLetNode [RDecl] RExpr
  | RIfNode RExpr RExpr RExpr
  | RCaseNode RExpr [RAlt]
  | RDoNode [RStmt]
  | RListNode [RExpr]
  | RTupleNode [RExpr]
  | RUnitNode
  | RParenNode RExpr
  | RLeftSectionNode RExpr RName
  | RRightSectionNode RName RExpr
  | RArithmeticSeqNode RExpr (Maybe RExpr) (Maybe RExpr)
  | RListCompNode RExpr [RStmt]
  | RExprTypeSigNode RExpr RHsType
  deriving stock (Show, Eq, Ord)

pattern RVar :: RName -> RExpr
pattern RVar name <- SpannedRExpr _ (RVarNode name)
  where
    RVar name = SpannedRExpr Nothing (RVarNode name)

pattern RCon :: RName -> RExpr
pattern RCon name <- SpannedRExpr _ (RConNode name)
  where
    RCon name = SpannedRExpr Nothing (RConNode name)

pattern RLit :: Literal -> RExpr
pattern RLit literal <- SpannedRExpr _ (RLitNode literal)
  where
    RLit literal = SpannedRExpr Nothing (RLitNode literal)

pattern RApp :: RExpr -> RExpr -> RExpr
pattern RApp function argument <- SpannedRExpr _ (RAppNode function argument)
  where
    RApp function argument = SpannedRExpr Nothing (RAppNode function argument)

pattern RInfixApp :: RExpr -> RName -> RExpr -> RExpr
pattern RInfixApp lhs op rhs <- SpannedRExpr _ (RInfixAppNode lhs op rhs)
  where
    RInfixApp lhs op rhs = SpannedRExpr Nothing (RInfixAppNode lhs op rhs)

pattern RLambda :: [RPat] -> RExpr -> RExpr
pattern RLambda patterns body <- SpannedRExpr _ (RLambdaNode patterns body)
  where
    RLambda patterns body = SpannedRExpr Nothing (RLambdaNode patterns body)

pattern RLet :: [RDecl] -> RExpr -> RExpr
pattern RLet decls body <- SpannedRExpr _ (RLetNode decls body)
  where
    RLet decls body = SpannedRExpr Nothing (RLetNode decls body)

pattern RIf :: RExpr -> RExpr -> RExpr -> RExpr
pattern RIf condition thenBranch elseBranch <- SpannedRExpr _ (RIfNode condition thenBranch elseBranch)
  where
    RIf condition thenBranch elseBranch = SpannedRExpr Nothing (RIfNode condition thenBranch elseBranch)

pattern RCase :: RExpr -> [RAlt] -> RExpr
pattern RCase scrutinee alternatives <- SpannedRExpr _ (RCaseNode scrutinee alternatives)
  where
    RCase scrutinee alternatives = SpannedRExpr Nothing (RCaseNode scrutinee alternatives)

pattern RDo :: [RStmt] -> RExpr
pattern RDo statements <- SpannedRExpr _ (RDoNode statements)
  where
    RDo statements = SpannedRExpr Nothing (RDoNode statements)

pattern RList :: [RExpr] -> RExpr
pattern RList expressions <- SpannedRExpr _ (RListNode expressions)
  where
    RList expressions = SpannedRExpr Nothing (RListNode expressions)

pattern RTuple :: [RExpr] -> RExpr
pattern RTuple expressions <- SpannedRExpr _ (RTupleNode expressions)
  where
    RTuple expressions = SpannedRExpr Nothing (RTupleNode expressions)

pattern RUnit :: RExpr
pattern RUnit <- SpannedRExpr _ RUnitNode
  where
    RUnit = SpannedRExpr Nothing RUnitNode

pattern RParen :: RExpr -> RExpr
pattern RParen inner <- SpannedRExpr _ (RParenNode inner)
  where
    RParen inner = SpannedRExpr Nothing (RParenNode inner)

pattern RLeftSection :: RExpr -> RName -> RExpr
pattern RLeftSection expr op <- SpannedRExpr _ (RLeftSectionNode expr op)
  where
    RLeftSection expr op = SpannedRExpr Nothing (RLeftSectionNode expr op)

pattern RRightSection :: RName -> RExpr -> RExpr
pattern RRightSection op expr <- SpannedRExpr _ (RRightSectionNode op expr)
  where
    RRightSection op expr = SpannedRExpr Nothing (RRightSectionNode op expr)

pattern RArithmeticSeq :: RExpr -> Maybe RExpr -> Maybe RExpr -> RExpr
pattern RArithmeticSeq start step end <- SpannedRExpr _ (RArithmeticSeqNode start step end)
  where
    RArithmeticSeq start step end = SpannedRExpr Nothing (RArithmeticSeqNode start step end)

pattern RListComp :: RExpr -> [RStmt] -> RExpr
pattern RListComp body statements <- SpannedRExpr _ (RListCompNode body statements)
  where
    RListComp body statements = SpannedRExpr Nothing (RListCompNode body statements)

pattern RExprTypeSig :: RExpr -> RHsType -> RExpr
pattern RExprTypeSig expr sourceType <- SpannedRExpr _ (RExprTypeSigNode expr sourceType)
  where
    RExprTypeSig expr sourceType = SpannedRExpr Nothing (RExprTypeSigNode expr sourceType)

{-# COMPLETE RVar, RCon, RLit, RApp, RInfixApp, RLambda, RLet, RIf, RCase, RDo, RList, RTuple, RUnit, RParen, RLeftSection, RRightSection, RArithmeticSeq, RListComp, RExprTypeSig #-}

rExprSpan :: RExpr -> Maybe SourceSpan
rExprSpan (SpannedRExpr sourceRange _) =
  sourceRange

setRExprSpan :: SourceSpan -> RExpr -> RExpr
setRExprSpan sourceRange (SpannedRExpr _ node) =
  SpannedRExpr (Just sourceRange) node

data RStmt = SpannedRStmt (Maybe SourceSpan) RStmtNode
  deriving stock (Show, Eq, Ord)

data RStmtNode
  = RBindStmtNode RPat RExpr
  | RLetStmtNode [RDecl]
  | RExprStmtNode RExpr
  deriving stock (Show, Eq, Ord)

pattern RBindStmt :: RPat -> RExpr -> RStmt
pattern RBindStmt pat expr <- SpannedRStmt _ (RBindStmtNode pat expr)
  where
    RBindStmt pat expr = SpannedRStmt Nothing (RBindStmtNode pat expr)

pattern RLetStmt :: [RDecl] -> RStmt
pattern RLetStmt decls <- SpannedRStmt _ (RLetStmtNode decls)
  where
    RLetStmt decls = SpannedRStmt Nothing (RLetStmtNode decls)

pattern RExprStmt :: RExpr -> RStmt
pattern RExprStmt expr <- SpannedRStmt _ (RExprStmtNode expr)
  where
    RExprStmt expr = SpannedRStmt Nothing (RExprStmtNode expr)

{-# COMPLETE RBindStmt, RLetStmt, RExprStmt #-}

rStmtSpan :: RStmt -> Maybe SourceSpan
rStmtSpan (SpannedRStmt sourceRange _) =
  sourceRange

setRStmtSpan :: SourceSpan -> RStmt -> RStmt
setRStmtSpan sourceRange (SpannedRStmt _ node) =
  SpannedRStmt (Just sourceRange) node

data RAlt = SpannedRAlt (Maybe SourceSpan) RPat RRhs [RDecl]
  deriving stock (Show, Eq, Ord)

pattern RAlt :: RPat -> RRhs -> [RDecl] -> RAlt
pattern RAlt pat rhs whereDecls <- SpannedRAlt _ pat rhs whereDecls
  where
    RAlt pat rhs whereDecls = SpannedRAlt Nothing pat rhs whereDecls

{-# COMPLETE RAlt #-}

rAltSpan :: RAlt -> Maybe SourceSpan
rAltSpan (SpannedRAlt sourceRange _ _ _) =
  sourceRange

setRAltSpan :: SourceSpan -> RAlt -> RAlt
setRAltSpan sourceRange (SpannedRAlt _ pat rhs whereDecls) =
  SpannedRAlt (Just sourceRange) pat rhs whereDecls

data RPat = SpannedRPat (Maybe SourceSpan) RPatNode
  deriving stock (Show, Eq, Ord)

data RPatNode
  = RPVarNode RName
  | RPConNode RName [RPat]
  | RPLitNode Literal
  | RPWildcardNode
  | RPTupleNode [RPat]
  | RPListNode [RPat]
  | RPAsNode RName RPat
  | RPIrrefutableNode RPat
  | RPParenNode RPat
  deriving stock (Show, Eq, Ord)

pattern RPVar :: RName -> RPat
pattern RPVar name <- SpannedRPat _ (RPVarNode name)
  where
    RPVar name = SpannedRPat Nothing (RPVarNode name)

pattern RPCon :: RName -> [RPat] -> RPat
pattern RPCon name patterns <- SpannedRPat _ (RPConNode name patterns)
  where
    RPCon name patterns = SpannedRPat Nothing (RPConNode name patterns)

pattern RPLit :: Literal -> RPat
pattern RPLit literal <- SpannedRPat _ (RPLitNode literal)
  where
    RPLit literal = SpannedRPat Nothing (RPLitNode literal)

pattern RPWildcard :: RPat
pattern RPWildcard <- SpannedRPat _ RPWildcardNode
  where
    RPWildcard = SpannedRPat Nothing RPWildcardNode

pattern RPTuple :: [RPat] -> RPat
pattern RPTuple patterns <- SpannedRPat _ (RPTupleNode patterns)
  where
    RPTuple patterns = SpannedRPat Nothing (RPTupleNode patterns)

pattern RPList :: [RPat] -> RPat
pattern RPList patterns <- SpannedRPat _ (RPListNode patterns)
  where
    RPList patterns = SpannedRPat Nothing (RPListNode patterns)

pattern RPAs :: RName -> RPat -> RPat
pattern RPAs name pat <- SpannedRPat _ (RPAsNode name pat)
  where
    RPAs name pat = SpannedRPat Nothing (RPAsNode name pat)

pattern RPIrrefutable :: RPat -> RPat
pattern RPIrrefutable pat <- SpannedRPat _ (RPIrrefutableNode pat)
  where
    RPIrrefutable pat = SpannedRPat Nothing (RPIrrefutableNode pat)

pattern RPParen :: RPat -> RPat
pattern RPParen pat <- SpannedRPat _ (RPParenNode pat)
  where
    RPParen pat = SpannedRPat Nothing (RPParenNode pat)

{-# COMPLETE RPVar, RPCon, RPLit, RPWildcard, RPTuple, RPList, RPAs, RPIrrefutable, RPParen #-}

rPatSpan :: RPat -> Maybe SourceSpan
rPatSpan (SpannedRPat sourceRange _) =
  sourceRange

setRPatSpan :: SourceSpan -> RPat -> RPat
setRPatSpan sourceRange (SpannedRPat _ node) =
  SpannedRPat (Just sourceRange) node

data RHsType = SpannedRType (Maybe SourceSpan) RTypeNode
  deriving stock (Show, Eq, Ord)

data RTypeNode
  = RTyVarNode RName
  | RTyConNode RName
  | RTyAppNode RHsType RHsType
  | RTyFunNode RHsType RHsType
  | RTyContextNode [RHsType] RHsType
  | RTyTupleNode [RHsType]
  | RTyListNode RHsType
  | RTyParenNode RHsType
  deriving stock (Show, Eq, Ord)

pattern RTyVar :: RName -> RHsType
pattern RTyVar name <- SpannedRType _ (RTyVarNode name)
  where
    RTyVar name = SpannedRType Nothing (RTyVarNode name)

pattern RTyCon :: RName -> RHsType
pattern RTyCon name <- SpannedRType _ (RTyConNode name)
  where
    RTyCon name = SpannedRType Nothing (RTyConNode name)

pattern RTyApp :: RHsType -> RHsType -> RHsType
pattern RTyApp fn arg <- SpannedRType _ (RTyAppNode fn arg)
  where
    RTyApp fn arg = SpannedRType Nothing (RTyAppNode fn arg)

pattern RTyFun :: RHsType -> RHsType -> RHsType
pattern RTyFun arg result <- SpannedRType _ (RTyFunNode arg result)
  where
    RTyFun arg result = SpannedRType Nothing (RTyFunNode arg result)

pattern RTyContext :: [RHsType] -> RHsType -> RHsType
pattern RTyContext context body <- SpannedRType _ (RTyContextNode context body)
  where
    RTyContext context body = SpannedRType Nothing (RTyContextNode context body)

pattern RTyTuple :: [RHsType] -> RHsType
pattern RTyTuple types <- SpannedRType _ (RTyTupleNode types)
  where
    RTyTuple types = SpannedRType Nothing (RTyTupleNode types)

pattern RTyList :: RHsType -> RHsType
pattern RTyList elementType <- SpannedRType _ (RTyListNode elementType)
  where
    RTyList elementType = SpannedRType Nothing (RTyListNode elementType)

pattern RTyParen :: RHsType -> RHsType
pattern RTyParen inner <- SpannedRType _ (RTyParenNode inner)
  where
    RTyParen inner = SpannedRType Nothing (RTyParenNode inner)

{-# COMPLETE RTyVar, RTyCon, RTyApp, RTyFun, RTyContext, RTyTuple, RTyList, RTyParen #-}

rTypeSpan :: RHsType -> Maybe SourceSpan
rTypeSpan (SpannedRType sourceRange _) =
  sourceRange

setRTypeSpan :: SourceSpan -> RHsType -> RHsType
setRTypeSpan sourceRange (SpannedRType _ node) =
  SpannedRType (Just sourceRange) node
