module Haskell2010.Layout
  ( layoutBlock
  , layoutBlockFrom
  )
where

import Control.Applicative ((<|>))
import Control.Monad (void)
import Haskell2010.Lexer (Parser, braces, scn, semi)
import qualified Text.Megaparsec.Char.Lexer as L
import Text.Megaparsec.Pos (Pos)
import Text.Megaparsec
  ( MonadParsec (try)
  , many
  , sepEndBy
  )

layoutBlock :: Parser a -> Parser [a]
layoutBlock item =
  explicitBlock item <|> implicitLooseBlock item

layoutBlockFrom :: Pos -> Parser a -> Parser [a]
layoutBlockFrom reference item =
  explicitBlock item <|> implicitIndentedBlock reference item

explicitBlock :: Parser a -> Parser [a]
explicitBlock item =
  braces (scn *> item `sepEndBy` (semi <* scn) <* scn)

implicitLooseBlock :: Parser a -> Parser [a]
implicitLooseBlock item = do
  scn
  firstIndent <- L.indentLevel
  firstItem <- item
  restItems <- sameIndentItems firstIndent item
  pure (firstItem : restItems)

implicitIndentedBlock :: Pos -> Parser a -> Parser [a]
implicitIndentedBlock reference item = do
  firstIndent <- L.indentGuard scn GT reference
  firstItem <- item
  restItems <- sameIndentItems firstIndent item
  pure (firstItem : restItems)

sameIndentItems :: Pos -> Parser a -> Parser [a]
sameIndentItems firstIndent item =
  many . try $ do
    (semi *> scn) <|> void (L.indentGuard scn EQ firstIndent)
    item
