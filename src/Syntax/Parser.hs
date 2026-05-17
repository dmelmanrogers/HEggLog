module Syntax.Parser
  ( Parser
  , parseLocatedProgram
  , parseLocatedSourceProgram
  , parseProgram
  , parseSourceProgram
  )
where

import Control.Applicative (empty, many, optional, some, (<|>))
import Control.Monad (void)
import Data.Char (isAlphaNum, isLetter)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void (Void)
import Syntax.AST
import Syntax.Located
import Syntax.Span
  ( SourceSpan
  , mergeSourceSpans
  , sourceSpan
  , sourceSpanFromStart
  )
import Text.Megaparsec
  ( MonadParsec (eof, notFollowedBy, try)
  , Parsec
  , ParseErrorBundle
  , between
  , chunk
  , choice
  , getSourcePos
  , parse
  , sepBy1
  , satisfy
  )
import qualified Text.Megaparsec.Char as C
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void Text

data LambdaAnnotationMode
  = RequireLambdaAnnotation
  | AllowInferredLambdaAnnotation

parseProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) Expr
parseProgram path =
  fmap stripLocatedExpr . parseLocatedProgram path

parseSourceProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) Program
parseSourceProgram path =
  fmap stripLocatedProgram . parseTypedLocatedSourceProgram path

parseLocatedProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) LocatedExpr
parseLocatedProgram path =
  parse (spaceConsumer *> expr RequireLambdaAnnotation <* eof) path

parseLocatedSourceProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) LocatedProgram
parseLocatedSourceProgram path =
  parse (spaceConsumer *> sourceProgram AllowInferredLambdaAnnotation <* eof) path

parseTypedLocatedSourceProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) LocatedProgram
parseTypedLocatedSourceProgram path =
  parse (spaceConsumer *> sourceProgram RequireLambdaAnnotation <* eof) path

sourceProgram :: LambdaAnnotationMode -> Parser LocatedProgram
sourceProgram mode = do
  defs <- many (topDef mode)
  LocatedProgram defs <$> expr mode

topDef :: LambdaAnnotationMode -> Parser LocatedTopDef
topDef mode = do
  start <- getSourcePos
  reserved "def"
  name <- identifier
  params <- parens (topParam `sepBy1` voidSymbol ",")
  voidSymbol ":"
  returnType <- typeExpr
  voidSymbol "="
  body <- expr mode
  (_, closeSpan) <- lexemeSpanned (chunk ";")
  pure
    LocatedTopDef
      { locatedTopDefSpan = sourceSpanFromStart start closeSpan
      , locatedTopDefName = name
      , locatedTopDefParams = params
      , locatedTopDefReturnType = returnType
      , locatedTopDefBody = body
      }

topParam :: Parser LocatedParam
topParam = do
  start <- getSourcePos
  name <- identifier
  voidSymbol ":"
  ty <- typeExpr
  end <- getSourcePos
  pure (LocatedParam (sourceSpan start end) (Param name ty))

expr :: LambdaAnnotationMode -> Parser LocatedExpr
expr mode =
  choice
    [ letExpr mode
    , ifExpr mode
    , lambdaExpr mode
    , equalityExpr mode
    ]

letExpr :: LambdaAnnotationMode -> Parser LocatedExpr
letExpr mode = do
  start <- getSourcePos
  reserved "let"
  name <- identifier
  voidSymbol "="
  rhs <- expr mode
  reserved "in"
  body <- expr mode
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan body)) (LLet name rhs body))

ifExpr :: LambdaAnnotationMode -> Parser LocatedExpr
ifExpr mode = do
  start <- getSourcePos
  reserved "if"
  cond <- expr mode
  reserved "then"
  thenBranch <- expr mode
  reserved "else"
  elseBranch <- expr mode
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan elseBranch)) (LIf cond thenBranch elseBranch))

lambdaExpr :: LambdaAnnotationMode -> Parser LocatedExpr
lambdaExpr mode = do
  start <- getSourcePos
  void (symbol "\\")
  name <- identifier
  argType <-
    case mode of
      RequireLambdaAnnotation ->
        Just <$> (voidSymbol ":" *> typeExpr)
      AllowInferredLambdaAnnotation ->
        optional (voidSymbol ":" *> typeExpr)
  voidSymbol "->"
  body <- expr mode
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan body)) (LLam name argType body))

equalityExpr :: LambdaAnnotationMode -> Parser LocatedExpr
equalityExpr mode =
  comparisonExpr mode `chainLeft` [("==", Eq)]

comparisonExpr :: LambdaAnnotationMode -> Parser LocatedExpr
comparisonExpr mode =
  additiveExpr mode `chainLeft` [("<", Lt)]

additiveExpr :: LambdaAnnotationMode -> Parser LocatedExpr
additiveExpr mode =
  multiplicativeExpr mode `chainLeft` [("+", Add), ("-", Sub)]

multiplicativeExpr :: LambdaAnnotationMode -> Parser LocatedExpr
multiplicativeExpr mode =
  applicationExpr mode `chainLeft` [("*", Mul), ("/", Div)]

applicationExpr :: LambdaAnnotationMode -> Parser LocatedExpr
applicationExpr mode = do
  atoms <- some (atom mode)
  pure (foldl1 locatedApp atoms)

atom :: LambdaAnnotationMode -> Parser LocatedExpr
atom mode =
  choice
    [ parensExpr mode
    , locatedReserved "true" (LBool True)
    , locatedReserved "false" (LBool False)
    , locatedInt
    , locatedVar
    ]

chainLeft :: Parser LocatedExpr -> [(Text, BinOp)] -> Parser LocatedExpr
chainLeft operand ops = do
  firstOperand <- operand
  rest firstOperand
 where
  rest lhs =
    ( do
        op <- choice [operator symbolText binOp | (symbolText, binOp) <- ops]
        rhs <- operand
        rest (locatedBin op lhs rhs)
    )
      <|> pure lhs

locatedApp :: LocatedExpr -> LocatedExpr -> LocatedExpr
locatedApp fn arg =
  LocatedExpr (mergeSourceSpans (locatedExprSpan fn) (locatedExprSpan arg)) (LApp fn arg)

locatedBin :: BinOp -> LocatedExpr -> LocatedExpr -> LocatedExpr
locatedBin op lhs rhs =
  LocatedExpr (mergeSourceSpans (locatedExprSpan lhs) (locatedExprSpan rhs)) (LBin op lhs rhs)

operator :: Text -> BinOp -> Parser BinOp
operator symbolText binOp =
  binOp <$ symbol symbolText

locatedInt :: Parser LocatedExpr
locatedInt = do
  (value, sourceRange) <- lexemeSpanned L.decimal
  pure (LocatedExpr sourceRange (LInt value))

locatedVar :: Parser LocatedExpr
locatedVar = do
  (name, sourceRange) <- lexemeSpanned identifierRaw
  pure (LocatedExpr sourceRange (LVar name))

locatedReserved :: Text -> LocatedExprNode -> Parser LocatedExpr
locatedReserved word node = do
  ((), sourceRange) <- lexemeSpanned (reservedRaw word)
  pure (LocatedExpr sourceRange node)

parensExpr :: LambdaAnnotationMode -> Parser LocatedExpr
parensExpr mode = do
  start <- getSourcePos
  voidSymbol "("
  inner <- expr mode
  (_, closeSpan) <- lexemeSpanned (chunk ")")
  pure (LocatedExpr (sourceSpanFromStart start closeSpan) (locatedExprNode inner))

identifier :: Parser Name
identifier =
  lexeme identifierRaw

identifierRaw :: Parser Name
identifierRaw = try $ do
  firstChar <- satisfy isIdentStart
  restChars <- many (satisfy isIdentRest)
  let ident = Text.pack (firstChar : restChars)
  if ident `elem` reservedWords
    then empty
    else pure (Name ident)

reserved :: Text -> Parser ()
reserved word =
  lexeme (reservedRaw word)

reservedRaw :: Text -> Parser ()
reservedRaw word = try $ do
    voidText word
    notFollowedBy (satisfy isIdentRest)

reservedWords :: [Text]
reservedWords =
  ["def", "let", "in", "if", "then", "else", "true", "false", "Int", "Bool"]

typeExpr :: Parser Type
typeExpr = do
  lhs <- typeAtom
  ( try $ do
      voidSymbol "->"
      TFun lhs <$> typeExpr
    )
    <|> pure lhs

typeAtom :: Parser Type
typeAtom =
  choice
    [ TInt <$ reserved "Int"
    , TBool <$ reserved "Bool"
    , parens typeExpr
    ]

isIdentStart :: Char -> Bool
isIdentStart c =
  isLetter c || c == '_'

isIdentRest :: Char -> Bool
isIdentRest c =
  isAlphaNum c || c == '_' || c == '\''

parens :: Parser a -> Parser a
parens =
  between (symbol "(") (symbol ")")

symbol :: Text -> Parser Text
symbol =
  lexeme . chunk

voidSymbol :: Text -> Parser ()
voidSymbol symbolText =
  void (symbol symbolText)

voidText :: Text -> Parser ()
voidText text =
  void (chunk text)

lexeme :: Parser a -> Parser a
lexeme =
  L.lexeme spaceConsumer

lexemeSpanned :: Parser a -> Parser (a, SourceSpan)
lexemeSpanned parser = do
  start <- getSourcePos
  result <- parser
  end <- getSourcePos
  spaceConsumer
  pure (result, sourceSpan start end)

spaceConsumer :: Parser ()
spaceConsumer =
  L.space C.space1 lineComment blockComment
 where
  lineComment = L.skipLineComment "--"
  blockComment = L.skipBlockComment "{-" "-}"
