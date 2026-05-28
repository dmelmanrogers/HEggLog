module Haskell2010.Lexer
  ( Parser
  , braces
  , brackets
  , charLiteral
  , conid
  , eof
  , floating
  , integer
  , lexeme
  , moduleName
  , operator
  , parens
  , reserved
  , sc
  , scn
  , semi
  , stringLiteral
  , symbol
  , varid
  )
where

import Control.Monad (void)
import Data.Char (isAlphaNum, isDigit, isLower, isSpace, isUpper)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void (Void)
import Haskell2010.Syntax (ModuleName (..))
import Text.Megaparsec
  ( MonadParsec (eof, notFollowedBy, takeWhile1P, try)
  , Parsec
  , between
  , choice
  , many
  , manyTill
  , satisfy
  , single
  , some
  , (<|>)
  )
import qualified Text.Megaparsec.Char as C
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void Text

sc :: Parser ()
sc =
  L.space hspace1 lineComment blockComment

scn :: Parser ()
scn =
  L.space C.space1 lineComment blockComment

hspace1 :: Parser ()
hspace1 =
  void (takeWhile1P (Just "horizontal whitespace") isHorizontalSpace)

isHorizontalSpace :: Char -> Bool
isHorizontalSpace c =
  isSpace c && c /= '\n' && c /= '\r'

lineComment :: Parser ()
lineComment =
  L.skipLineComment "--"

blockComment :: Parser ()
blockComment =
  L.skipBlockCommentNested "{-" "-}"

lexeme :: Parser a -> Parser a
lexeme =
  L.lexeme sc

symbol :: Text -> Parser Text
symbol =
  L.symbol sc

reserved :: Text -> Parser ()
reserved word = lexeme . try $ do
  void (C.string word)
  notFollowedBy identContinue

varid :: Parser Text
varid =
  lexeme (identifierBy isVarStart)

conid :: Parser Text
conid =
  lexeme (identifierBy isConStart)

moduleName :: Parser ModuleName
moduleName = do
  firstPart <- conid
  rest <- many (symbol "." *> conid)
  pure (ModuleName (firstPart : rest))

identifierBy :: (Char -> Bool) -> Parser Text
identifierBy starts = try $ do
  firstChar <- satisfy starts
  restChars <- many identContinue
  let ident = Text.pack (firstChar : restChars)
  if ident `elem` reservedWords
    then fail ("reserved word " <> Text.unpack ident <> " cannot be an identifier")
    else pure ident

identContinue :: Parser Char
identContinue =
  satisfy (\c -> isAlphaNum c || c == '_' || c == '\'')

isVarStart :: Char -> Bool
isVarStart c =
  isLower c || c == '_'

isConStart :: Char -> Bool
isConStart =
  isUpper

operator :: Parser Text
operator =
  lexeme . try $ do
    op <- Text.pack <$> some (satisfy isOperatorChar)
    if op `elem` reservedOperators || "--" `Text.isPrefixOf` op
      then fail ("reserved operator " <> Text.unpack op <> " cannot be used here")
      else pure op

isOperatorChar :: Char -> Bool
isOperatorChar c =
  c `elem` (":!#$%&*+./<=>?@\\^|-~" :: String)

integer :: Parser Integer
integer =
  lexeme (choice [try hexadecimal, try octal, L.decimal])
 where
  hexadecimal = C.string "0x" *> L.hexadecimal <|> C.string "0X" *> L.hexadecimal
  octal = C.string "0o" *> L.octal <|> C.string "0O" *> L.octal

floating :: Parser Double
floating =
  lexeme . try $ do
    whole <- some (satisfy isDigit)
    fractional <- ((:) <$> single '.' <*> some (satisfy isDigit)) <|> pure ""
    exponentPart <- exponentPartParser <|> pure ""
    if null fractional && null exponentPart
      then fail "floating literal requires a fractional or exponent part"
      else pure (read (whole <> fractional <> exponentPart))
 where
  exponentPartParser = do
    marker <- single 'e' <|> single 'E'
    sign <- (: []) <$> (single '+' <|> single '-') <|> pure ""
    digits <- some (satisfy isDigit)
    pure (marker : sign <> digits)

charLiteral :: Parser Char
charLiteral =
  lexeme (between (single '\'') (single '\'') L.charLiteral)

stringLiteral :: Parser Text
stringLiteral =
  lexeme (Text.pack <$> (single '"' *> manyTill L.charLiteral (single '"')))

parens :: Parser a -> Parser a
parens =
  between (symbol "(") (symbol ")")

brackets :: Parser a -> Parser a
brackets =
  between (symbol "[") (symbol "]")

braces :: Parser a -> Parser a
braces =
  between (symbol "{") (symbol "}")

semi :: Parser ()
semi =
  void (symbol ";")

reservedWords :: [Text]
reservedWords =
  [ "case"
  , "class"
  , "data"
  , "default"
  , "deriving"
  , "do"
  , "else"
  , "foreign"
  , "hiding"
  , "if"
  , "import"
  , "in"
  , "infix"
  , "infixl"
  , "infixr"
  , "instance"
  , "let"
  , "module"
  , "newtype"
  , "of"
  , "qualified"
  , "then"
  , "type"
  , "where"
  , "_"
  ]

reservedOperators :: [Text]
reservedOperators =
  ["..", ":", "::", "=", "\\", "|", "<-", "->", "@", "~", "=>"]
