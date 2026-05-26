module Haskell2010.Diagnostics
  ( renderParseDiagnostic
  , renderParseDiagnosticWithSeverity
  )
where

import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void (Void)
import Syntax.Span (SourceSpan (..), renderSourceDiagnostic)
import Text.Megaparsec.Error
  ( ParseErrorBundle (..)
  , attachSourcePos
  , errorOffset
  , parseErrorTextPretty
  )
import Text.Megaparsec.Pos (SourcePos, sourceColumn, sourceLine, sourceName, unPos)

renderParseDiagnostic :: ParseErrorBundle Text Void -> Text
renderParseDiagnostic =
  renderParseDiagnosticWithSeverity "Haskell 2010 parse error"

renderParseDiagnosticWithSeverity :: Text -> ParseErrorBundle Text Void -> Text
renderParseDiagnosticWithSeverity severity bundle =
  Text.intercalate "\n" (renderAttached <$> NonEmpty.toList errorsWithPositions)
 where
  (errorsWithPositions, _) =
    attachSourcePos errorOffset (bundleErrors bundle) (bundlePosState bundle)

  renderAttached (parseError, position) =
    renderSourceDiagnostic
      (sourcePointSpan position)
      severity
      (oneLineMessage (Text.pack (parseErrorTextPretty parseError)))

sourcePointSpan :: SourcePos -> SourceSpan
sourcePointSpan position =
  SourceSpan
    { spanFile = sourceName position
    , spanStartLine = line
    , spanStartColumn = column
    , spanEndLine = line
    , spanEndColumn = column + 1
    }
 where
  line = unPos (sourceLine position)
  column = unPos (sourceColumn position)

oneLineMessage :: Text -> Text
oneLineMessage =
  Text.unwords . Text.words
