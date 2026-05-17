module Syntax.Parser
  ( Parser
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
import Text.Megaparsec
  ( MonadParsec (eof, notFollowedBy, try)
  , Parsec
  , ParseErrorBundle
  , between
  , chunk
  , choice
  , parse
  , satisfy
  )
import qualified Text.Megaparsec.Char as C
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void Text

parseProgram :: FilePath -> Text -> Either (ParseErrorBundle Text Void) Expr
parseProgram path =
  parse (spaceConsumer *> expr <* eof) path

expr :: Parser Expr
expr =
  choice
    [ letExpr
    , ifExpr
    , lambdaExpr
    , equalityExpr
    ]

letExpr :: Parser Expr
letExpr = do
  reserved "let"
  name <- identifier
  voidSymbol "="
  rhs <- expr
  reserved "in"
  ELet name rhs <$> expr

ifExpr :: Parser Expr
ifExpr = do
  reserved "if"
  cond <- expr
  reserved "then"
  thenBranch <- expr
  reserved "else"
  EIf cond thenBranch <$> expr

lambdaExpr :: Parser Expr
lambdaExpr = do
  void (symbol "\\")
  name <- identifier
  voidSymbol ":"
  argType <- typeExpr
  voidSymbol "->"
  ELam name argType <$> expr

equalityExpr :: Parser Expr
equalityExpr =
  comparisonExpr `chainLeft` [("==", Eq)]

comparisonExpr :: Parser Expr
comparisonExpr =
  additiveExpr `chainLeft` [("<", Lt)]

additiveExpr :: Parser Expr
additiveExpr =
  multiplicativeExpr `chainLeft` [("+", Add), ("-", Sub)]

multiplicativeExpr :: Parser Expr
multiplicativeExpr =
  applicationExpr `chainLeft` [("*", Mul), ("/", Div)]

applicationExpr :: Parser Expr
applicationExpr = do
  atoms <- some atom
  pure (foldl1 EApp atoms)

atom :: Parser Expr
atom =
  choice
    [ parens expr
    , EBool True <$ reserved "true"
    , EBool False <$ reserved "false"
    , EInt <$> integer
    , EVar <$> identifier
    ]

chainLeft :: Parser Expr -> [(Text, BinOp)] -> Parser Expr
chainLeft operand ops = do
  firstOperand <- operand
  rest firstOperand
 where
  rest lhs =
    ( do
        op <- choice [operator symbolText binOp | (symbolText, binOp) <- ops]
        rhs <- operand
        rest (EBin op lhs rhs)
    )
      <|> pure lhs

operator :: Text -> BinOp -> Parser BinOp
operator symbolText binOp =
  binOp <$ symbol symbolText

integer :: Parser Integer
integer =
  lexeme L.decimal

identifier :: Parser Name
identifier = lexeme . try $ do
  firstChar <- satisfy isIdentStart
  restChars <- many (satisfy isIdentRest)
  let ident = Text.pack (firstChar : restChars)
  if ident `elem` reservedWords
    then empty
    else pure (Name ident)

reserved :: Text -> Parser ()
reserved word =
  lexeme . try $ do
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
  L.symbol spaceConsumer

voidSymbol :: Text -> Parser ()
voidSymbol symbolText =
  void (symbol symbolText)

voidText :: Text -> Parser ()
voidText text =
  void (chunk text)

lexeme :: Parser a -> Parser a
lexeme =
  L.lexeme spaceConsumer

spaceConsumer :: Parser ()
spaceConsumer =
  L.space C.space1 lineComment blockComment
 where
  lineComment = L.skipLineComment "--"
  blockComment = L.skipBlockComment "{-" "-}"
