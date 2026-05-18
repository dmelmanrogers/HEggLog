module Haskell2010.Syntax
  ( Alt (..)
  , Assoc (..)
  , ConDecl (..)
  , Decl (..)
  , Export (..)
  , Expr (..)
  , Fixity (..)
  , HsModule (..)
  , HsType (..)
  , ImportDecl (..)
  , ImportSpec (..)
  , Literal (..)
  , ModuleName (..)
  , Pat (..)
  , Rhs (..)
  , Stmt (..)
  )
where

import Data.Text (Text)

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

data Decl
  = TypeSignature [Text] HsType
  | FunctionBinding Text [Pat] Rhs [Decl]
  | PatternBinding Pat Rhs [Decl]
  | FixityDecl Fixity [Text]
  | DataDecl Text [Text] [ConDecl] [Text]
  | NewtypeDecl Text [Text] ConDecl [Text]
  | TypeSynonym Text [Text] HsType
  | ClassDecl [HsType] Text Text [Decl]
  | InstanceDecl [HsType] HsType [Decl]
  | DefaultDecl [HsType]
  | ForeignDecl Text
  deriving stock (Show, Eq, Ord)

data Fixity = Fixity Assoc Int
  deriving stock (Show, Eq, Ord)

data Assoc
  = InfixL
  | InfixR
  | InfixN
  deriving stock (Show, Eq, Ord)

data ConDecl = ConDecl Text [HsType]
  deriving stock (Show, Eq, Ord)

data Rhs
  = Unguarded Expr
  | Guarded [(Expr, Expr)]
  deriving stock (Show, Eq, Ord)

data Expr
  = Var Text
  | Con Text
  | Lit Literal
  | App Expr Expr
  | InfixApp Expr Text Expr
  | Lambda [Pat] Expr
  | Let [Decl] Expr
  | If Expr Expr Expr
  | Case Expr [Alt]
  | Do [Stmt]
  | List [Expr]
  | Tuple [Expr]
  | Unit
  | Paren Expr
  | LeftSection Expr Text
  | RightSection Text Expr
  | ArithmeticSeq Expr (Maybe Expr) (Maybe Expr)
  | ListComp Expr [Stmt]
  | ExprTypeSig Expr HsType
  deriving stock (Show, Eq, Ord)

data Stmt
  = BindStmt Pat Expr
  | LetStmt [Decl]
  | ExprStmt Expr
  deriving stock (Show, Eq, Ord)

data Alt = Alt Pat Rhs [Decl]
  deriving stock (Show, Eq, Ord)

data Pat
  = PVar Text
  | PCon Text [Pat]
  | PLit Literal
  | PWildcard
  | PTuple [Pat]
  | PList [Pat]
  | PAs Text Pat
  | PIrrefutable Pat
  | PParen Pat
  deriving stock (Show, Eq, Ord)

data Literal
  = LInt Integer
  | LChar Char
  | LString Text
  deriving stock (Show, Eq, Ord)

data HsType
  = TyVar Text
  | TyCon Text
  | TyApp HsType HsType
  | TyFun HsType HsType
  | TyContext [HsType] HsType
  | TyTuple [HsType]
  | TyList HsType
  | TyParen HsType
  deriving stock (Show, Eq, Ord)
