module Haskell2010.FFI.LinkMetadata
  ( ForeignLinkMetadata (..)
  , emptyForeignLinkMetadata
  , foreignLinkMetadataForImportsExports
  , renderForeignLinkMetadataComments
  )
where

import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.Core.Syntax (CoreForeignExport (..), CoreForeignImport (..))
import Haskell2010.Names (nameOcc)
import qualified Haskell2010.Syntax as S

data ForeignLinkMetadata = ForeignLinkMetadata
  { foreignLinkHeaders :: [Text]
  , foreignLinkImportSymbols :: [Text]
  , foreignLinkAddressSymbols :: [Text]
  , foreignLinkExportSymbols :: [Text]
  }
  deriving stock (Show, Eq, Ord)

emptyForeignLinkMetadata :: ForeignLinkMetadata
emptyForeignLinkMetadata =
  ForeignLinkMetadata
    { foreignLinkHeaders = []
    , foreignLinkImportSymbols = []
    , foreignLinkAddressSymbols = []
    , foreignLinkExportSymbols = []
    }

foreignLinkMetadataForImportsExports ::
  [CoreForeignImport] ->
  [CoreForeignExport] ->
  ForeignLinkMetadata
foreignLinkMetadataForImportsExports foreignImports foreignExports =
  ForeignLinkMetadata
    { foreignLinkHeaders = uniqueTexts (concatMap foreignImportHeaders foreignImports)
    , foreignLinkImportSymbols = uniqueTexts (concatMap foreignImportSymbols foreignImports)
    , foreignLinkAddressSymbols = uniqueTexts (concatMap foreignAddressSymbols foreignImports)
    , foreignLinkExportSymbols = uniqueTexts (map foreignExportSymbol foreignExports)
    }

renderForeignLinkMetadataComments :: ForeignLinkMetadata -> [Text]
renderForeignLinkMetadataComments metadata =
  concat
    [ renderMany "foreign link header" (foreignLinkHeaders metadata)
    , renderMany "foreign link import symbol" (foreignLinkImportSymbols metadata)
    , renderMany "foreign link address symbol" (foreignLinkAddressSymbols metadata)
    , renderMany "foreign link export symbol" (foreignLinkExportSymbols metadata)
    ]
 where
  renderMany label values =
    [label <> ": " <> value | value <- values]

foreignImportHeaders :: CoreForeignImport -> [Text]
foreignImportHeaders foreignImport =
  case S.foreignImportEntityKind (coreForeignImportEntity foreignImport) of
    S.ForeignImportStatic (Just header) _ -> [header]
    S.ForeignImportAddress (Just header) _ -> [header]
    _ -> []

foreignImportSymbols :: CoreForeignImport -> [Text]
foreignImportSymbols foreignImport =
  case S.foreignImportEntityKind (coreForeignImportEntity foreignImport) of
    S.ForeignImportDefault -> [nameOcc (coreForeignImportName foreignImport)]
    S.ForeignImportStatic _ symbol -> [symbol]
    _ -> []

foreignAddressSymbols :: CoreForeignImport -> [Text]
foreignAddressSymbols foreignImport =
  case S.foreignImportEntityKind (coreForeignImportEntity foreignImport) of
    S.ForeignImportAddress _ symbol -> [symbol]
    _ -> []

foreignExportSymbol :: CoreForeignExport -> Text
foreignExportSymbol foreignExport =
  case S.foreignExportEntitySymbol (coreForeignExportEntity foreignExport) of
    Nothing -> nameOcc (coreForeignExportName foreignExport)
    Just symbol -> symbol

uniqueTexts :: [Text] -> [Text]
uniqueTexts =
  go Set.empty
 where
  go _ [] = []
  go seen (value : rest)
    | Text.null value = go seen rest
    | value `Set.member` seen = go seen rest
    | otherwise = value : go (Set.insert value seen) rest
