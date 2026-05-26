module Haskell2010.Layout
  ( layoutBlock
  , layoutBlockFrom
  )
where

import Control.Applicative (optional, (<|>))
import Control.Monad (void, when)
import Haskell2010.Lexer (Parser, braces, reserved, scn, semi, symbol)
import qualified Text.Megaparsec.Char.Lexer as L
import Text.Megaparsec
  ( MonadParsec (try)
  , choice
  , getSourcePos
  , lookAhead
  , many
  , sepEndBy
  )
import Text.Megaparsec.Pos (Pos, sourceLine, unPos)

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
  scn
  firstIndent <- L.indentLevel
  firstItem <- item
  restItems <- sameIndentItems firstIndent item
  rejectMisalignedIndentedItem reference firstIndent
  pure (firstItem : restItems)

sameIndentItems :: Pos -> Parser a -> Parser [a]
sameIndentItems firstIndent item =
  many . try $ do
    (semi *> scn) <|> void (L.indentGuard scn EQ firstIndent)
    item

rejectMisalignedIndentedItem :: Pos -> Pos -> Parser ()
rejectMisalignedIndentedItem reference firstIndent = do
  beforeWhitespace <- getSourcePos
  scn
  afterWhitespace <- getSourcePos
  when (sourceLine afterWhitespace > sourceLine beforeWhitespace) $ do
    nextIndent <- L.indentLevel
    closesLayout <- nextTokenClosesLayout
    when (nextIndent > reference && nextIndent /= firstIndent && not closesLayout) $
      fail
        ( "layout item is indented to column "
            <> show (unPos nextIndent)
            <> "; expected column "
            <> show (unPos firstIndent)
            <> " for another item, or column "
            <> show (unPos reference)
            <> " or less to close the block"
        )

nextTokenClosesLayout :: Parser Bool
nextTokenClosesLayout = do
  closer <-
    optional . try . lookAhead $
      choice
        [ reserved "in"
        , reserved "else"
        , void (symbol ")")
        , void (symbol "]")
        , void (symbol "}")
        ]
  pure (maybe False (const True) closer)
