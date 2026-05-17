module Syntax.Parser
  ( Parser
  , parseLocatedProgram
  , parseProgram
  )
where

import Control.Applicative (empty, many, some, (<|>))
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
  , satisfy
  )
import qualified Text.Megaparsec.Char as C
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void Text

parseProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) Expr
parseProgram path =
  fmap stripLocatedExpr . parseLocatedProgram path

parseLocatedProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) LocatedExpr
parseLocatedProgram path =
  parse (spaceConsumer *> expr <* eof) path

expr :: Parser LocatedExpr
expr =
  choice
    [ letExpr
    , ifExpr
    , lambdaExpr
    , equalityExpr
    ]

letExpr :: Parser LocatedExpr
letExpr = do
  start <- getSourcePos
  reserved "let"
  name <- identifier
  voidSymbol "="
  rhs <- expr
  reserved "in"
  body <- expr
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan body)) (LLet name rhs body))

ifExpr :: Parser LocatedExpr
ifExpr = do
  start <- getSourcePos
  reserved "if"
  cond <- expr
  reserved "then"
  thenBranch <- expr
  reserved "else"
  elseBranch <- expr
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan elseBranch)) (LIf cond thenBranch elseBranch))

lambdaExpr :: Parser LocatedExpr
lambdaExpr = do
  start <- getSourcePos
  void (symbol "\\")
  name <- identifier
  voidSymbol ":"
  argType <- typeExpr
  voidSymbol "->"
  body <- expr
  pure (LocatedExpr (sourceSpanFromStart start (locatedExprSpan body)) (LLam name argType body))

equalityExpr :: Parser LocatedExpr
equalityExpr =
  comparisonExpr `chainLeft` [("==", Eq)]

comparisonExpr :: Parser LocatedExpr
comparisonExpr =
  additiveExpr `chainLeft` [("<", Lt)]

additiveExpr :: Parser LocatedExpr
additiveExpr =
  multiplicativeExpr `chainLeft` [("+", Add), ("-", Sub)]

multiplicativeExpr :: Parser LocatedExpr
multiplicativeExpr =
  applicationExpr `chainLeft` [("*", Mul), ("/", Div)]

applicationExpr :: Parser LocatedExpr
applicationExpr = do
  atoms <- some atom
  pure (foldl1 locatedApp atoms)

atom :: Parser LocatedExpr
atom =
  choice
    [ parensExpr
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

parensExpr :: Parser LocatedExpr
parensExpr = do
  start <- getSourcePos
  voidSymbol "("
  inner <- expr
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
  ["let", "in", "if", "then", "else", "true", "false", "Int", "Bool"]

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
