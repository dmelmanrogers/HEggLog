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
  renderParseDiagnosticWithSeverityFor classifyParseSeverity

renderParseDiagnosticWithSeverity :: Text -> ParseErrorBundle Text Void -> Text
renderParseDiagnosticWithSeverity severity =
  renderParseDiagnosticWithSeverityFor (const severity)

renderParseDiagnosticWithSeverityFor :: (Text -> Text) -> ParseErrorBundle Text Void -> Text
renderParseDiagnosticWithSeverityFor severityFor bundle =
  Text.intercalate "\n" (renderAttached <$> NonEmpty.toList errorsWithPositions)
 where
  (errorsWithPositions, _) =
    attachSourcePos errorOffset (bundleErrors bundle) (bundlePosState bundle)

  renderAttached (parseError, position) =
    let message = oneLineMessage (Text.pack (parseErrorTextPretty parseError))
     in renderSourceDiagnostic
          (sourcePointSpan position)
          (severityFor message)
          message

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

classifyParseSeverity :: Text -> Text
classifyParseSeverity message
  | "layout" `Text.isInfixOf` lowerMessage || "indent" `Text.isInfixOf` lowerMessage =
      "Haskell 2010 layout error"
  | otherwise =
      "Haskell 2010 parse error"
 where
  lowerMessage = Text.toLower message
