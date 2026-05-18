module Haskell2010.Parser
  ( declParser
  , exprParser
  , moduleParser
  , parseModule
  , parseSourceModule
  , typeParser
  )
where

import Control.Applicative (many, optional, some, (<|>))
import Control.Monad (void)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void (Void)
import Haskell2010.Layout (layoutBlock)
import Haskell2010.Lexer
  ( Parser
  , charLiteral
  , conid
  , eof
  , integer
  , operator
  , reserved
  , scn
  , stringLiteral
  , symbol
  , varid
  )
import qualified Haskell2010.Lexer as Lex
import Haskell2010.Syntax
import Text.Megaparsec
  ( MonadParsec (lookAhead, try)
  , ParseErrorBundle
  , anySingle
  , choice
  , manyTill
  , option
  , parse
  , sepBy
  , sepBy1
  , sepEndBy
  )
import qualified Text.Megaparsec.Char as C

data ModuleItem
  = ModuleImport ImportDecl
  | ModuleDecl Decl

parseModule :: FilePath -> Text -> Either (ParseErrorBundle Text Void) HsModule
parseModule =
  parse moduleParser

parseSourceModule :: FilePath -> Text -> Either (ParseErrorBundle Text Void) HsModule
parseSourceModule =
  parseModule

moduleParser :: Parser HsModule
moduleParser = do
  scn
  parsed <- try explicitModule <|> bareModule
  scn
  eof
  pure parsed

explicitModule :: Parser HsModule
explicitModule = do
  reserved "module"
  name <- Lex.moduleName
  exports <- optional exportList
  reserved "where"
  items <- moduleBody
  (imports, decls) <- partitionModuleItems items
  pure
    HsModule
      { moduleName = Just name
      , moduleExports = exports
      , moduleImports = imports
      , moduleDecls = decls
      }

bareModule :: Parser HsModule
bareModule = do
  items <- moduleBody
  (imports, decls) <- partitionModuleItems items
  pure
    HsModule
      { moduleName = Nothing
      , moduleExports = Nothing
      , moduleImports = imports
      , moduleDecls = decls
      }

moduleBody :: Parser [ModuleItem]
moduleBody =
  scn *> (emptyBody <|> layoutBlock moduleItem)
 where
  emptyBody =
    [] <$ lookAhead eof

moduleItem :: Parser ModuleItem
moduleItem =
  try (ModuleImport <$> importDecl) <|> (ModuleDecl <$> declParser)

partitionModuleItems :: [ModuleItem] -> Parser ([ImportDecl], [Decl])
partitionModuleItems =
  go False [] []
 where
  go _ imports decls [] =
    pure (reverse imports, reverse decls)
  go False imports decls (ModuleImport importDecl' : rest) =
    go False (importDecl' : imports) decls rest
  go _ _ _ (ModuleImport {} : _) =
    fail "import declarations must precede top-level declarations"
  go _ imports decls (ModuleDecl decl : rest) =
    go True imports (decl : decls) rest

exportList :: Parser [Export]
exportList =
  parensComma exportSpec

exportSpec :: Parser Export
exportSpec =
  try (ExportModule <$> (reserved "module" *> Lex.moduleName))
    <|> try exportThing
    <|> (ExportName <$> importedName)
 where
  exportThing = do
    name <- importedName
    children <- allChildren <|> parensComma importedName
    pure (ExportThing name children)

importDecl :: Parser ImportDecl
importDecl = do
  reserved "import"
  qualifiedImport <- option False (True <$ reserved "qualified")
  importedModule <- Lex.moduleName
  alias <- optional (reserved "as" *> Lex.moduleName)
  specs <- optional . try $ do
    hidingImport <- option False (True <$ reserved "hiding")
    names <- parensComma importSpec
    pure (names, hidingImport)
  pure
    ImportDecl
      { importQualified = qualifiedImport
      , importModule = importedModule
      , importAs = alias
      , importSpecs = specs
      }

importSpec :: Parser ImportSpec
importSpec =
  try importThing <|> (ImportName <$> importedName)
 where
  importThing = do
    name <- importedName
    children <- allChildren <|> parensComma importedName
    pure (ImportThing name children)

declParser :: Parser Decl
declParser =
  choice
    [ try typeSignatureDecl
    , try fixityDecl
    , try dataDecl
    , try newtypeDecl
    , try typeSynonymDecl
    , try classDecl
    , try instanceDecl
    , try defaultDecl
    , try foreignDecl
    , try functionBinding
    , patternBinding
    ]

typeSignatureDecl :: Parser Decl
typeSignatureDecl = do
  names <- bindingName `sepBy1` comma
  void (symbol "::")
  TypeSignature names <$> typeParser

fixityDecl :: Parser Decl
fixityDecl = do
  assoc <-
    choice
      [ InfixL <$ reserved "infixl"
      , InfixR <$ reserved "infixr"
      , InfixN <$ reserved "infix"
      ]
  precedence <- fromInteger <$> option 9 integer
  if precedence < 0 || precedence > 9
    then fail "fixity precedence must be between 0 and 9"
    else FixityDecl (Fixity assoc precedence) <$> qop `sepBy1` comma

dataDecl :: Parser Decl
dataDecl = do
  reserved "data"
  (typeName, params) <- typeHead
  void (symbol "=")
  constructors <- constructorDecl `sepBy1` symbol "|"
  derived <- derivingDecl
  pure (DataDecl typeName params constructors derived)

newtypeDecl :: Parser Decl
newtypeDecl = do
  reserved "newtype"
  (typeName, params) <- typeHead
  void (symbol "=")
  constructorDecl' <- constructorDecl
  derived <- derivingDecl
  pure (NewtypeDecl typeName params constructorDecl' derived)

typeSynonymDecl :: Parser Decl
typeSynonymDecl = do
  reserved "type"
  (typeName, params) <- typeHead
  void (symbol "=")
  TypeSynonym typeName params <$> typeParser

classDecl :: Parser Decl
classDecl = do
  reserved "class"
  context <- optional (try (contextParser <* symbol "=>"))
  className <- qconid
  typeVariable <- varid
  decls <- optionalWhereDecls
  pure (ClassDecl (fromMaybe [] context) className typeVariable decls)

instanceDecl :: Parser Decl
instanceDecl = do
  reserved "instance"
  context <- optional (try (contextParser <* symbol "=>"))
  instanceType <- typeParser
  decls <- optionalWhereDecls
  pure (InstanceDecl (fromMaybe [] context) instanceType decls)

defaultDecl :: Parser Decl
defaultDecl = do
  reserved "default"
  DefaultDecl <$> parensComma typeParser

foreignDecl :: Parser Decl
foreignDecl = do
  reserved "foreign"
  rest <- Text.strip . Text.pack <$> manyTill anySingle (lookAhead endOfForeignDecl)
  pure (ForeignDecl ("foreign " <> rest))
 where
  endOfForeignDecl =
    void C.eol <|> eof

functionBinding :: Parser Decl
functionBinding = do
  name <- functionName
  patterns <- many patParser
  rhs <- rhsParser
  whereDecls <- optionalWhereDecls
  pure (FunctionBinding name patterns rhs whereDecls)

patternBinding :: Parser Decl
patternBinding = do
  pat <- patParser
  rhs <- rhsParser
  whereDecls <- optionalWhereDecls
  pure (PatternBinding pat rhs whereDecls)

rhsParser :: Parser Rhs
rhsParser =
  guardedRhs <|> unguardedRhs
 where
  guardedRhs = Guarded <$> some guardedBranch
  guardedBranch = do
    void (symbol "|")
    guardExpr <- exprParser
    void (symbol "=")
    scn
    bodyExpr <- exprParser
    pure (guardExpr, bodyExpr)
  unguardedRhs =
    Unguarded <$> (symbol "=" *> scn *> exprParser)

exprParser :: Parser Expr
exprParser = do
  expr <- choice [lambdaExpr, letExpr, ifExpr, caseExpr, doExpr, infixExpr]
  option expr (ExprTypeSig expr <$> (symbol "::" *> typeParser))

lambdaExpr :: Parser Expr
lambdaExpr = do
  void (symbol "\\")
  patterns <- some patParser
  void (symbol "->")
  scn
  Lambda patterns <$> exprParser

letExpr :: Parser Expr
letExpr = do
  reserved "let"
  decls <- layoutBlock declParser
  scn
  reserved "in"
  Let decls <$> exprParser

ifExpr :: Parser Expr
ifExpr = do
  reserved "if"
  condition <- exprParser
  reserved "then"
  thenExpr <- exprParser
  reserved "else"
  If condition thenExpr <$> exprParser

caseExpr :: Parser Expr
caseExpr = do
  reserved "case"
  scrutinee <- exprParser
  reserved "of"
  Case scrutinee <$> layoutBlock altParser

doExpr :: Parser Expr
doExpr = do
  reserved "do"
  Do <$> layoutBlock stmtParser

infixExpr :: Parser Expr
infixExpr = do
  firstExpr <- appExpr
  rest <- many (try ((,) <$> qop <*> appExpr))
  pure (foldl applyInfix firstExpr rest)
 where
  applyInfix lhs (op, rhs) =
    InfixApp lhs op rhs

appExpr :: Parser Expr
appExpr = do
  atoms <- some atomExpr
  pure (foldl1 App atoms)

atomExpr :: Parser Expr
atomExpr =
  choice
    [ try parenExpr
    , try listExpr
    , literalExpr
    , Con <$> qconid
    , Var <$> qvarid
    ]

literalExpr :: Parser Expr
literalExpr =
  Lit
    <$> choice
      [ LChar <$> charLiteral
      , LString <$> stringLiteral
      , LInt <$> integer
      ]

parenExpr :: Parser Expr
parenExpr = do
  void (symbol "(")
  choice
    [ Unit <$ symbol ")"
    , try rightSection
    , parenOrTupleOrLeftSection
    ]
 where
  rightSection = do
    op <- qop
    expr <- exprParser
    void (symbol ")")
    pure (RightSection op expr)
  parenOrTupleOrLeftSection = do
    firstExpr <- exprParser
    choice
      [ try (tupleExpr firstExpr)
      , try (leftSection firstExpr)
      , Paren firstExpr <$ symbol ")"
      ]
  tupleExpr firstExpr = do
    void comma
    rest <- exprParser `sepBy1` comma
    void (symbol ")")
    pure (Tuple (firstExpr : rest))
  leftSection firstExpr = do
    op <- qop
    void (symbol ")")
    pure (LeftSection firstExpr op)

listExpr :: Parser Expr
listExpr = do
  void (symbol "[")
  choice
    [ List [] <$ symbol "]"
    , listBody
    ]
 where
  listBody = do
    firstExpr <- exprParser
    choice
      [ try (listComprehension firstExpr)
      , try (arithmeticSequence firstExpr)
      , listTail firstExpr
      ]
  listComprehension firstExpr = do
    void (symbol "|")
    ListComp firstExpr <$> stmtParser `sepBy1` comma <* symbol "]"
  arithmeticSequence firstExpr =
    firstAndStep firstExpr <|> firstOnly firstExpr
  firstOnly firstExpr = do
    void (symbol "..")
    upper <- optional exprParser
    void (symbol "]")
    pure (ArithmeticSeq firstExpr Nothing upper)
  firstAndStep firstExpr = do
    void comma
    secondExpr <- exprParser
    void (symbol "..")
    upper <- optional exprParser
    void (symbol "]")
    pure (ArithmeticSeq firstExpr (Just secondExpr) upper)
  listTail firstExpr = do
    rest <- many (comma *> exprParser)
    void (symbol "]")
    pure (List (firstExpr : rest))

stmtParser :: Parser Stmt
stmtParser =
  choice
    [ try bindStmt
    , letStmt
    , ExprStmt <$> exprParser
    ]
 where
  bindStmt = do
    pat <- patParser
    void (symbol "<-")
    BindStmt pat <$> exprParser
  letStmt = do
    reserved "let"
    LetStmt <$> layoutBlock declParser

altParser :: Parser Alt
altParser = do
  pat <- patParser
  rhs <- altRhsParser
  Alt pat rhs <$> optionalWhereDecls

altRhsParser :: Parser Rhs
altRhsParser =
  guardedAltRhs <|> unguardedAltRhs
 where
  guardedAltRhs = Guarded <$> some guardedBranch
  guardedBranch = do
    void (symbol "|")
    guardExpr <- exprParser
    void (symbol "->")
    scn
    bodyExpr <- exprParser
    pure (guardExpr, bodyExpr)
  unguardedAltRhs =
    Unguarded <$> (symbol "->" *> scn *> exprParser)

patParser :: Parser Pat
patParser =
  choice
    [ try asPat
    , try irrefutablePat
    , try conAppPat
    , patAtom
    ]
 where
  asPat = do
    name <- varid
    void (symbol "@")
    PAs name <$> patParser
  irrefutablePat =
    PIrrefutable <$> (symbol "~" *> patParser)
  conAppPat = do
    constructor <- qconid
    args <- many patAtom
    pure (PCon constructor args)

patAtom :: Parser Pat
patAtom =
  choice
    [ PWildcard <$ symbol "_"
    , try parenPat
    , listPat
    , PLit <$> literalParser
    , PCon <$> qconid <*> pure []
    , PVar <$> varid
    ]

parenPat :: Parser Pat
parenPat = do
  void (symbol "(")
  choice
    [ PTuple [] <$ symbol ")"
    , patBody
    ]
 where
  patBody = do
    firstPat <- patParser
    choice
      [ do
          void comma
          rest <- patParser `sepBy1` comma
          void (symbol ")")
          pure (PTuple (firstPat : rest))
      , PParen firstPat <$ symbol ")"
      ]

listPat :: Parser Pat
listPat =
  PList <$> bracketsComma patParser

literalParser :: Parser Literal
literalParser =
  choice
    [ LChar <$> charLiteral
    , LString <$> stringLiteral
    , LInt <$> integer
    ]

typeParser :: Parser HsType
typeParser = do
  context <- optional (try (contextParser <* symbol "=>"))
  body <- functionType
  pure (maybe body (`TyContext` body) context)

contextParser :: Parser [HsType]
contextParser =
  try (parensComma classConstraint) <|> ((: []) <$> classConstraint)

classConstraint :: Parser HsType
classConstraint = do
  className <- qconid
  args <- many typeAtom
  pure (foldl TyApp (TyCon className) args)

functionType :: Parser HsType
functionType = do
  lhs <- appType
  option lhs (TyFun lhs <$> (symbol "->" *> functionType))

appType :: Parser HsType
appType = do
  parts <- some typeAtom
  pure (foldl1 TyApp parts)

typeAtom :: Parser HsType
typeAtom =
  choice
    [ try parenType
    , TyList <$> (symbol "[" *> typeParser <* symbol "]")
    , TyCon <$> qconid
    , TyVar <$> varid
    ]

parenType :: Parser HsType
parenType = do
  void (symbol "(")
  choice
    [ TyCon "()" <$ symbol ")"
    , typeBody
    ]
 where
  typeBody = do
    firstType <- typeParser
    choice
      [ do
          void comma
          rest <- typeParser `sepBy1` comma
          void (symbol ")")
          pure (TyTuple (firstType : rest))
      , TyParen firstType <$ symbol ")"
      ]

constructorDecl :: Parser ConDecl
constructorDecl =
  ConDecl <$> qconid <*> many typeAtom

derivingDecl :: Parser [Text]
derivingDecl =
  option [] . try $ do
    reserved "deriving"
    parensComma qconid <|> ((: []) <$> qconid)

typeHead :: Parser (Text, [Text])
typeHead =
  (,) <$> qconid <*> many varid

optionalWhereDecls :: Parser [Decl]
optionalWhereDecls =
  option [] (reserved "where" *> layoutBlock declParser)

qvarid :: Parser Text
qvarid =
  qualified varid

qconid :: Parser Text
qconid =
  qualified conid

qualified :: Parser Text -> Parser Text
qualified terminal =
  try qualifiedName <|> terminal
 where
  qualifiedName = do
    prefixes <- some (try (conid <* symbol "."))
    final <- terminal
    pure (Text.intercalate "." (prefixes <> [final]))

qop :: Parser Text
qop =
  choice
    [ try qualifiedOperator
    , try backtickName
    , symbol ":" *> pure ":"
    , operator
    ]
 where
  qualifiedOperator = do
    prefixes <- some (try (conid <* symbol "."))
    op <- operator <|> (symbol ":" *> pure ":")
    pure (Text.intercalate "." (prefixes <> [op]))
  backtickName =
    symbol "`" *> (qvarid <|> qconid) <* symbol "`"

functionName :: Parser Text
functionName =
  qvarid <|> parens qop

bindingName :: Parser Text
bindingName =
  functionName <|> qconid

importedName :: Parser Text
importedName =
  bindingName

comma :: Parser ()
comma =
  void (symbol ",")

parens :: Parser a -> Parser a
parens parser =
  symbol "(" *> parser <* symbol ")"

parensComma :: Parser a -> Parser [a]
parensComma parser =
  symbol "(" *> parser `sepEndBy` comma <* symbol ")"

allChildren :: Parser [Text]
allChildren =
  symbol "(" *> symbol ".." *> symbol ")" *> pure [".."]

bracketsComma :: Parser a -> Parser [a]
bracketsComma parser =
  symbol "[" *> parser `sepBy` comma <* symbol "]"
