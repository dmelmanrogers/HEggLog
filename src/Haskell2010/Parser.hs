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
import Haskell2010.Layout (layoutBlock, layoutBlockFrom)
import Haskell2010.Lexer
  ( Parser
  , charLiteral
  , conid
  , eof
  , floating
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
import Syntax.Span (SourceSpan, sourceSpan)
import Text.Megaparsec
  ( MonadParsec (lookAhead, try)
  , ParseErrorBundle
  , SourcePos
  , choice
  , getSourcePos
  , option
  , parse
  , sepBy
  , sepBy1
  , sepEndBy
  , sepEndBy1
  , sourceColumn
  , sourceLine
  )

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
    children <- try allChildren <|> parensComma importedName
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
    children <- try allChildren <|> parensComma importedName
    pure (ImportThing name children)

declParser :: Parser Decl
declParser =
  withSpan setDeclSpan $
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
  start <- getSourcePos
  reserved "class"
  context <- optional (try (contextParser <* symbol "=>"))
  className <- qconid
  typeVariable <- varid
  decls <- optionalWhereDeclsFrom start
  pure (ClassDecl (fromMaybe [] context) className typeVariable decls)

instanceDecl :: Parser Decl
instanceDecl = do
  start <- getSourcePos
  reserved "instance"
  context <- optional (try (contextParser <* symbol "=>"))
  instanceType <- typeParser
  decls <- optionalWhereDeclsFrom start
  pure (InstanceDecl (fromMaybe [] context) instanceType decls)

defaultDecl :: Parser Decl
defaultDecl = do
  reserved "default"
  DefaultDecl <$> parensComma typeParser

foreignDecl :: Parser Decl
foreignDecl = do
  reserved "foreign"
  ForeignDecl <$> (foreignImportDecl <|> foreignExportDecl)

foreignImportDecl :: Parser ForeignDeclInfo
foreignImportDecl = do
  reserved "import"
  callConv <- foreignCallConv
  safety <- option ForeignSafe (try foreignSafety)
  entity <- option defaultForeignImportEntity (try foreignImportEntitySpec)
  name <- bindingName
  void (symbol "::")
  ForeignImportDecl . ForeignImport callConv safety entity name <$> typeParser

foreignExportDecl :: Parser ForeignDeclInfo
foreignExportDecl = do
  reserved "export"
  callConv <- foreignCallConv
  entity <- option defaultForeignExportEntity (try foreignExportEntitySpec)
  name <- bindingName
  void (symbol "::")
  ForeignExportDecl . ForeignExport callConv entity name <$> typeParser

foreignCallConv :: Parser ForeignCallConv
foreignCallConv =
  callConvFromText <$> varid
 where
  callConvFromText = \case
    "ccall" -> ForeignCCall
    "stdcall" -> ForeignStdCall
    "cplusplus" -> ForeignCPlusPlus
    "jvm" -> ForeignJvm
    "dotnet" -> ForeignDotNet
    other -> ForeignOtherCallConv other

foreignSafety :: Parser ForeignSafety
foreignSafety = do
  token <- varid
  case token of
    "safe" -> pure ForeignSafe
    "unsafe" -> pure ForeignUnsafe
    other -> fail ("unknown foreign import safety " <> Text.unpack other)

foreignImportEntitySpec :: Parser ForeignImportEntity
foreignImportEntitySpec = do
  raw <- stringLiteral
  pure
    ForeignImportEntity
      { foreignImportEntityRaw = Just raw
      , foreignImportEntityKind = parseForeignImportEntity raw
      }

foreignExportEntitySpec :: Parser ForeignExportEntity
foreignExportEntitySpec = do
  raw <- stringLiteral
  pure
    ForeignExportEntity
      { foreignExportEntityRaw = Just raw
      , foreignExportEntitySymbol = if Text.null raw then Nothing else Just raw
      }

defaultForeignImportEntity :: ForeignImportEntity
defaultForeignImportEntity =
  ForeignImportEntity
    { foreignImportEntityRaw = Nothing
    , foreignImportEntityKind = ForeignImportDefault
    }

defaultForeignExportEntity :: ForeignExportEntity
defaultForeignExportEntity =
  ForeignExportEntity
    { foreignExportEntityRaw = Nothing
    , foreignExportEntitySymbol = Nothing
    }

parseForeignImportEntity :: Text -> ForeignImportEntityKind
parseForeignImportEntity raw =
  case Text.words raw of
    [] ->
      ForeignImportUnknown raw
    ["dynamic"] ->
      ForeignImportDynamic
    ["wrapper"] ->
      ForeignImportWrapper
    "static" : rest ->
      parseStaticImportEntity raw rest
    rest ->
      parseStaticImportEntity raw rest
 where
  parseStaticImportEntity rawText tokens =
    case tokens of
      [] ->
        ForeignImportUnknown rawText
      headerToken : symbolTokens
        | Just header <- parseHeader headerToken ->
            parseImportSymbol rawText (Just header) (Text.unwords symbolTokens)
      symbolTokens ->
        parseImportSymbol rawText Nothing (Text.unwords symbolTokens)

  parseImportSymbol rawText header symbolText
    | Text.null symbolText =
        ForeignImportUnknown rawText
    | Just ffiSymbol <- Text.stripPrefix "&" symbolText =
        if Text.null ffiSymbol then ForeignImportUnknown rawText else ForeignImportAddress header ffiSymbol
    | otherwise =
        ForeignImportStatic header symbolText

  parseHeader token
    | "[" `Text.isPrefixOf` token && "]" `Text.isSuffixOf` token =
        Just (Text.dropEnd 1 (Text.drop 1 token))
    | otherwise =
        Nothing

functionBinding :: Parser Decl
functionBinding =
  try infixFunctionBinding <|> prefixFunctionBinding

prefixFunctionBinding :: Parser Decl
prefixFunctionBinding = do
  start <- getSourcePos
  name <- functionName
  patterns <- many patParser
  rhs <- rhsParser
  whereDecls <- optionalWhereDeclsFrom start
  pure (FunctionBinding name patterns rhs whereDecls)

infixFunctionBinding :: Parser Decl
infixFunctionBinding = do
  start <- getSourcePos
  lhs <- patParser
  name <- qvarop
  rhsPat <- patParser
  rhs <- rhsParser
  whereDecls <- optionalWhereDeclsFrom start
  pure (FunctionBinding name [lhs, rhsPat] rhs whereDecls)

patternBinding :: Parser Decl
patternBinding = do
  start <- getSourcePos
  pat <- patParser
  rhs <- rhsParser
  whereDecls <- optionalWhereDeclsFrom start
  pure (PatternBinding pat rhs whereDecls)

rhsParser :: Parser Rhs
rhsParser =
  withSpan setRhsSpan $
    scn *> (try guardedRhs <|> unguardedRhs)
 where
  guardedRhs = Guarded <$> some (try guardedBranch)
  guardedBranch = do
    scn
    void (symbol "|")
    guardExpr <- exprParser
    void (symbol "=")
    scn
    bodyExpr <- exprParser
    pure (guardExpr, bodyExpr)
  unguardedRhs =
    Unguarded <$> (symbol "=" *> scn *> exprParser)

exprParser :: Parser Expr
exprParser = withSpan setExprSpan $ do
  expr <- choice [lambdaExpr, letExpr, ifExpr, caseExpr, doExpr, infixExpr]
  option expr (ExprTypeSig expr <$> (symbol "::" *> typeParser))

lambdaExpr :: Parser Expr
lambdaExpr = withSpan setExprSpan $ do
  void (symbol "\\")
  patterns <- some patParser
  void (symbol "->")
  scn
  Lambda patterns <$> exprParser

letExpr :: Parser Expr
letExpr = withSpan setExprSpan $ do
  start <- getSourcePos
  reserved "let"
  decls <- layoutBlockFrom (sourceColumn start) declParser
  scn
  reserved "in"
  Let decls <$> exprParser

ifExpr :: Parser Expr
ifExpr = withSpan setExprSpan $ do
  reserved "if"
  condition <- exprParser
  reserved "then"
  thenExpr <- exprParser
  reserved "else"
  If condition thenExpr <$> exprParser

caseExpr :: Parser Expr
caseExpr = withSpan setExprSpan $ do
  start <- getSourcePos
  reserved "case"
  scrutinee <- exprParser
  reserved "of"
  Case scrutinee <$> layoutBlockFrom (sourceColumn start) altParser

doExpr :: Parser Expr
doExpr = withSpan setExprSpan $ do
  start <- getSourcePos
  reserved "do"
  Do <$> layoutBlockFrom (sourceColumn start) stmtParser

infixExpr :: Parser Expr
infixExpr = withSpan setExprSpan $ do
  firstExpr <- appExpr
  rest <- many (try ((,) <$> qop <*> appExpr))
  pure (foldl applyInfix firstExpr rest)
 where
  applyInfix lhs (op, rhs) =
    InfixApp lhs op rhs

appExpr :: Parser Expr
appExpr = withSpan setExprSpan $ do
  atoms <- some postfixExpr
  pure (foldl1 App atoms)

postfixExpr :: Parser Expr
postfixExpr = withSpan setExprSpan $ do
  base <- atomExpr
  updates <- many (try recordUpdateSuffix)
  pure (foldl RecordUpdate base updates)

recordUpdateSuffix :: Parser [(Text, Expr)]
recordUpdateSuffix =
  bracesComma1 recordExprField

atomExpr :: Parser Expr
atomExpr =
  withSpan setExprSpan $
    choice
    [ try parenExpr
    , try listExpr
    , try recordConExpr
    , literalExpr
    , Var <$> qvarid
    , Con <$> qconid
    ]

recordConExpr :: Parser Expr
recordConExpr = withSpan setExprSpan $ do
  constructor <- qconid
  fields <- bracesComma recordExprField
  pure (RecordCon constructor fields)

recordExprField :: Parser (Text, Expr)
recordExprField = do
  name <- qvarid
  void (symbol "=")
  expr <- exprParser
  pure (name, expr)

literalExpr :: Parser Expr
literalExpr =
  Lit
    <$> choice
      [ LChar <$> charLiteral
      , LString <$> stringLiteral
      , LDouble <$> try floating
      , LInt <$> integer
      ]

parenExpr :: Parser Expr
parenExpr = withSpan setExprSpan $ do
  void (symbol "(")
  choice
    [ Unit <$ symbol ")"
    , try operatorVariable
    , try rightSection
    , parenOrTupleOrLeftSection
    ]
 where
  operatorVariable = do
    op <- qop
    void (symbol ")")
    pure (if operatorIsConstructor op then Con op else Var op)
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
listExpr = withSpan setExprSpan $ do
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
  withSpan setStmtSpan $
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
    start <- getSourcePos
    reserved "let"
    LetStmt <$> layoutBlockFrom (sourceColumn start) declParser

altParser :: Parser Alt
altParser = withSpan setAltSpan $ do
  start <- getSourcePos
  pat <- patParser
  rhs <- altRhsParser
  Alt pat rhs <$> optionalWhereDeclsFrom start

altRhsParser :: Parser Rhs
altRhsParser =
  withSpan setRhsSpan $
    scn *> (try guardedAltRhs <|> unguardedAltRhs)
 where
  guardedAltRhs = Guarded <$> some (try guardedBranch)
  guardedBranch = do
    scn
    void (symbol "|")
    guardExpr <- exprParser
    void (symbol "->")
    scn
    bodyExpr <- exprParser
    pure (guardExpr, bodyExpr)
  unguardedAltRhs =
    Unguarded <$> (symbol "->" *> scn *> exprParser)

patParser :: Parser Pat
patParser = withSpan setPatSpan $ do
  lhs <-
    choice
      [ try asPat
      , try irrefutablePat
      , try recordConPat
      , try conAppPat
      , patAtom
      ]
  option lhs (consPat lhs)
 where
  consPat lhs = do
    op <- qconop
    rhs <- patParser
    pure (PCon op [lhs, rhs])
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
  recordConPat = do
    constructor <- qconid
    fields <- bracesComma recordPatField
    pure (PRecordCon constructor fields)
  recordPatField = do
    name <- qvarid
    void (symbol "=")
    pat <- patParser
    pure (name, pat)

patAtom :: Parser Pat
patAtom =
  withSpan setPatSpan $
    choice
    [ PWildcard <$ symbol "_"
    , try parenPat
    , listPat
    , PLit <$> literalParser
    , PCon <$> qconid <*> pure []
    , PVar <$> varid
    ]

parenPat :: Parser Pat
parenPat = withSpan setPatSpan $ do
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
  withSpan setPatSpan $
    PList <$> bracketsComma patParser

literalParser :: Parser Literal
literalParser =
  choice
    [ LChar <$> charLiteral
    , LString <$> stringLiteral
    , LDouble <$> try floating
    , LInt <$> integer
    ]

typeParser :: Parser HsType
typeParser = withSpan setHsTypeSpan $ do
  context <- optional (try (contextParser <* symbol "=>"))
  body <- functionType
  pure (maybe body (`TyContext` body) context)

contextParser :: Parser [HsType]
contextParser =
  try (parensComma classConstraint) <|> ((: []) <$> classConstraint)

classConstraint :: Parser HsType
classConstraint = withSpan setHsTypeSpan $ do
  className <- qconid
  args <- many typeAtom
  pure (foldl TyApp (TyCon className) args)

functionType :: Parser HsType
functionType = withSpan setHsTypeSpan $ do
  lhs <- appType
  option lhs (TyFun lhs <$> (symbol "->" *> functionType))

appType :: Parser HsType
appType = withSpan setHsTypeSpan $ do
  parts <- some typeAtom
  pure (foldl1 TyApp parts)

typeAtom :: Parser HsType
typeAtom =
  withSpan setHsTypeSpan $
    choice
    [ try parenType
    , try (TyCon "[]" <$ symbol "[]")
    , TyList <$> (symbol "[" *> typeParser <* symbol "]")
    , TyCon <$> qconid
    , TyVar <$> varid
    ]

parenType :: Parser HsType
parenType = withSpan setHsTypeSpan $ do
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
  withSpan setConDeclSpan $
    try infixConstructorDecl <|> prefixConstructorDecl
 where
  infixConstructorDecl = do
    lhs <- typeAtom
    constructorName <- qconop
    rhs <- typeAtom
    pure (ConDecl constructorName [lhs, rhs])
  prefixConstructorDecl = do
    constructorName <- qconid
    try (RecordConDecl constructorName <$> bracesComma1 recordFieldDecl)
      <|> (ConDecl constructorName <$> many typeAtom)
  recordFieldDecl = do
    names <- qvarid `sepBy1` comma
    void (symbol "::")
    ConField names <$> typeParser

derivingDecl :: Parser [Text]
derivingDecl =
  option [] . try $ do
    reserved "deriving"
    parensComma qconid <|> ((: []) <$> qconid)

typeHead :: Parser (Text, [Text])
typeHead =
  (,) <$> qconid <*> many varid

optionalWhereDeclsFrom :: SourcePos -> Parser [Decl]
optionalWhereDeclsFrom reference =
  option [] $ do
    try (scn *> lookAhead (reserved "where"))
    wherePos <- getSourcePos
    validateWhereIndent reference wherePos
    reserved "where"
    layoutBlockFrom (sourceColumn reference) declParser

validateWhereIndent :: SourcePos -> SourcePos -> Parser ()
validateWhereIndent reference wherePos
  | sourceLine wherePos == sourceLine reference || sourceColumn wherePos > sourceColumn reference =
      pure ()
  | otherwise =
      fail "where keyword must be indented beyond the declaration or case alternative it belongs to"

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
    , operator
    , symbol ":" *> pure ":"
    ]
 where
  qualifiedOperator = do
    prefixes <- some (try (conid <* symbol "."))
    op <- operator <|> (symbol ":" *> pure ":")
    pure (Text.intercalate "." (prefixes <> [op]))
  backtickName =
    symbol "`" *> (qvarid <|> qconid) <* symbol "`"

qconop :: Parser Text
qconop =
  choice
    [ try qualifiedConstructorOperator
    , try backtickConstructorName
    , constructorOperator
    ]
 where
  qualifiedConstructorOperator = do
    prefixes <- some (try (conid <* symbol "."))
    op <- constructorOperator
    pure (Text.intercalate "." (prefixes <> [op]))
  backtickConstructorName =
    symbol "`" *> qconid <* symbol "`"
  constructorOperator =
    try
      ( do
          op <- operator
          if operatorIsConstructor op
            then pure op
            else fail ("variable operator " <> Text.unpack op <> " cannot be used as a constructor operator")
      )
      <|> (symbol ":" *> pure ":")

qvarop :: Parser Text
qvarop =
  choice
    [ try qualifiedVariableOperator
    , try backtickVariableName
    , variableOperator
    ]
 where
  qualifiedVariableOperator = do
    prefixes <- some (try (conid <* symbol "."))
    op <- variableOperator
    pure (Text.intercalate "." (prefixes <> [op]))
  backtickVariableName =
    symbol "`" *> qvarid <* symbol "`"

variableOperator :: Parser Text
variableOperator = do
  op <- operator
  if ":" `Text.isPrefixOf` op
    then fail ("constructor operator " <> Text.unpack op <> " cannot be used as a variable operator")
    else pure op

functionName :: Parser Text
functionName =
  qvarid <|> parens qvarop

bindingName :: Parser Text
bindingName =
  functionName <|> qconid

importedName :: Parser Text
importedName =
  try (parens qconop) <|> bindingName

operatorIsConstructor :: Text -> Bool
operatorIsConstructor op =
  case reverse (Text.splitOn "." op) of
    local : _ -> ":" `Text.isPrefixOf` local
    [] -> False

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

bracesComma :: Parser a -> Parser [a]
bracesComma parser =
  symbol "{" *> parser `sepEndBy` comma <* symbol "}"

bracesComma1 :: Parser a -> Parser [a]
bracesComma1 parser =
  symbol "{" *> parser `sepEndBy1` comma <* symbol "}"

withSpan :: (SourceSpan -> a -> a) -> Parser a -> Parser a
withSpan setSpan parser = do
  start <- getSourcePos
  value <- parser
  end <- getSourcePos
  pure (setSpan (sourceSpan start end) value)
