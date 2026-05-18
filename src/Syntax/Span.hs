module Syntax.Span
  ( SourceSpan (..)
  , mergeSourceSpans
  , renderSourceDiagnostic
  , renderSourceSpan
  , sourceSpan
  , sourceSpanFromStart
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import Text.Megaparsec (SourcePos, sourceColumn, sourceLine, sourceName, unPos)

data SourceSpan = SourceSpan
  { spanFile :: FilePath
  , spanStartLine :: Int
  , spanStartColumn :: Int
  , spanEndLine :: Int
  , spanEndColumn :: Int
  }
  deriving stock (Show, Eq, Ord)

sourceSpan :: SourcePos -> SourcePos -> SourceSpan
sourceSpan start end =
  SourceSpan
    { spanFile = sourceName start
    , spanStartLine = unPos (sourceLine start)
    , spanStartColumn = unPos (sourceColumn start)
    , spanEndLine = unPos (sourceLine end)
    , spanEndColumn = unPos (sourceColumn end)
    }

sourceSpanFromStart :: SourcePos -> SourceSpan -> SourceSpan
sourceSpanFromStart start end =
  SourceSpan
    { spanFile = sourceName start
    , spanStartLine = unPos (sourceLine start)
    , spanStartColumn = unPos (sourceColumn start)
    , spanEndLine = spanEndLine end
    , spanEndColumn = spanEndColumn end
    }

mergeSourceSpans :: SourceSpan -> SourceSpan -> SourceSpan
mergeSourceSpans start end =
  start
    { spanEndLine = spanEndLine end
    , spanEndColumn = spanEndColumn end
    }

renderSourceSpan :: SourceSpan -> Text
renderSourceSpan sourceRange =
  Text.pack (spanFile sourceRange)
    <> ":"
    <> Text.pack (show (spanStartLine sourceRange))
    <> ":"
    <> Text.pack (show (spanStartColumn sourceRange))
    <> endSuffix
 where
  endSuffix
    | spanStartLine sourceRange == spanEndLine sourceRange =
        "-"
          <> Text.pack (show (spanEndColumn sourceRange))
    | otherwise =
        "-"
          <> Text.pack (show (spanEndLine sourceRange))
          <> ":"
          <> Text.pack (show (spanEndColumn sourceRange))

renderSourceDiagnostic :: SourceSpan -> Text -> Text -> Text
renderSourceDiagnostic sourceRange severity message =
  renderSourceSpan sourceRange <> ": " <> severity <> ": " <> message
