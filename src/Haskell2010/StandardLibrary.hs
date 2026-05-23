module Haskell2010.StandardLibrary
  ( implicitPreludeImport
  , standardLibrarySourceModule
  , standardLibraryExternalName
  , standardLibraryModuleInterfaces
  , standardPreludeFixities
  , standardPreludeInterface
  , standardPreludeModuleName
  , standardPreludeNames
  )
where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Haskell2010.ModuleInterface
import Haskell2010.Names
import qualified Haskell2010.Syntax as S

standardPreludeModuleName :: S.ModuleName
standardPreludeModuleName =
  S.ModuleName ["Prelude"]

implicitPreludeImport :: S.ImportDecl
implicitPreludeImport =
  S.ImportDecl
    { S.importQualified = False
    , S.importModule = standardPreludeModuleName
    , S.importAs = Nothing
    , S.importSpecs = Nothing
    }

standardLibraryModuleInterfaces :: Map.Map S.ModuleName ModuleInterface
standardLibraryModuleInterfaces =
  Map.fromList
    [ (standardPreludeModuleName, standardPreludeInterface)
    , (controlMonadModuleName, controlMonadInterface)
    , (dataArrayModuleName, dataArrayInterface)
    , (dataBitsModuleName, dataBitsInterface)
    , (dataCharModuleName, dataCharInterface)
    , (dataIntModuleName, dataIntInterface)
    , (dataIxModuleName, dataIxInterface)
    , (dataListModuleName, dataListInterface)
    , (dataMaybeModuleName, dataMaybeInterface)
    , (dataWordModuleName, dataWordInterface)
    , (systemIOModuleName, systemIOInterface)
    , (systemIOErrorModuleName, systemIOErrorInterface)
    , (foreignModuleName, foreignInterface)
    , (foreignCModuleName, foreignCInterface)
    , (foreignCStringModuleName, foreignCStringInterface)
    , (foreignCTypesModuleName, foreignCTypesInterface)
    , (foreignForeignPtrModuleName, foreignForeignPtrInterface)
    , (foreignMarshalModuleName, foreignMarshalInterface)
    , (foreignMarshalErrorModuleName, foreignMarshalErrorInterface)
    , (foreignMarshalUtilsModuleName, foreignMarshalUtilsInterface)
    , (foreignPtrModuleName, foreignPtrInterface)
    , (foreignStablePtrModuleName, foreignStablePtrInterface)
    ]

standardPreludeInterface :: ModuleInterface
standardPreludeInterface =
  ModuleInterface
    { interfaceModuleName = standardPreludeModuleName
    , interfaceExports = standardPreludeExportNames
    , interfaceChildren = standardPreludeExportChildren
    , interfaceFixities = standardPreludeFixities
    , interfaceInstances = []
    }

standardPreludeFixities :: Map.Map Text S.Fixity
standardPreludeFixities =
  Map.fromList
    [ (":", S.Fixity S.InfixR 5)
    , ("++", S.Fixity S.InfixR 5)
    , ("!!", S.Fixity S.InfixL 9)
    , ("+", S.Fixity S.InfixL 6)
    , ("-", S.Fixity S.InfixL 6)
    , ("*", S.Fixity S.InfixL 7)
    , ("/", S.Fixity S.InfixL 7)
    , ("==", S.Fixity S.InfixN 4)
    , ("/=", S.Fixity S.InfixN 4)
    , ("<", S.Fixity S.InfixN 4)
    , ("<=", S.Fixity S.InfixN 4)
    , (">", S.Fixity S.InfixN 4)
    , (">=", S.Fixity S.InfixN 4)
    , ("\\\\", S.Fixity S.InfixL 5)
    , ("&&", S.Fixity S.InfixR 3)
    , ("||", S.Fixity S.InfixR 2)
    , (">>=", S.Fixity S.InfixL 1)
    , (">>", S.Fixity S.InfixL 1)
    , ("=<<", S.Fixity S.InfixR 1)
    , (">=>", S.Fixity S.InfixR 1)
    , ("<=<", S.Fixity S.InfixR 1)
    , ("$", S.Fixity S.InfixR 0)
    , (".", S.Fixity S.InfixR 9)
    ]

standardPreludeNames :: [(Namespace, Text)]
standardPreludeNames =
  fmap (TermNamespace,)
    [ "+"
    , "-"
    , "*"
    , "/"
    , "=="
    , "/="
    , "<"
    , "<="
    , ">"
    , ">="
    , "&&"
    , "||"
    , "compare"
    , "max"
    , "min"
    , "succ"
    , "pred"
    , "toEnum"
    , "fromEnum"
    , "enumFrom"
    , "enumFromThen"
    , "enumFromTo"
    , "enumFromThenTo"
    , "minBound"
    , "maxBound"
    , "negate"
    , "abs"
    , "signum"
    , "fromInteger"
    , "toRational"
    , "quot"
    , "rem"
    , "div"
    , "mod"
    , "quotRem"
    , "divMod"
    , "toInteger"
    , "++"
    , ">>="
    , ">>"
    , "=<<"
    , "$"
    , "."
    , "flip"
    , "pure"
    , "return"
    , "fail"
    , "fmap"
    , "mapM"
    , "mapM_"
    , "sequence"
    , "sequence_"
    , "map"
    , "foldr"
    , "foldl"
    , "head"
    , "tail"
    , "null"
    , "fst"
    , "snd"
    , "length"
    , "filter"
    , "reverse"
    , "showsPrec"
    , "show"
    , "showList"
    , "shows"
    , "readsPrec"
    , "readList"
    , "reads"
    , "read"
    , "lex"
    , "readParen"
    , "putStrLn"
    , "getLine"
    , "print"
    , "ioError"
    , "userError"
    , "catch"
    , "not"
    , "id"
    , "const"
    , "otherwise"
    ]
    <> fmap (ConstructorNamespace,) ["True", "False", "Nothing", "Just", "Left", "Right", "LT", "EQ", "GT", ":"]
    <> fmap (TypeNamespace,) ["Int", "Integer", "Float", "Double", "Rational", "Bool", "Char", "String", "FilePath", "ReadS", "ShowS", "[]", "IO", "IOError", "CString", "Maybe", "Either", "Ordering", "()"]
    <> fmap (ClassNamespace,) ["Eq", "Ord", "Show", "Read", "Num", "Real", "Integral", "Enum", "Bounded", "Functor", "Monad"]

standardPreludeExportNames :: [RName]
standardPreludeExportNames =
  [standardPreludeExternalName namespace occurrence | (namespace, occurrence) <- standardPreludeNames]

standardPreludeExportChildren :: Map.Map RName [RName]
standardPreludeExportChildren =
  Map.fromList
    [ typed "Bool" ["True", "False"]
    , typed "Maybe" ["Nothing", "Just"]
    , typed "Either" ["Left", "Right"]
    , typed "Ordering" ["LT", "EQ", "GT"]
    , typed "[]" [":"]
    , classified "Eq" ["==", "/="]
    , classified "Ord" ["compare", "<", "<=", ">", ">=", "max", "min"]
    , classified "Show" ["showsPrec", "show", "showList"]
    , classified "Read" ["readsPrec", "readList"]
    , classified "Num" ["+", "-", "*", "negate", "abs", "signum", "fromInteger"]
    , classified "Real" ["toRational"]
    , classified "Integral" ["quot", "rem", "div", "mod", "quotRem", "divMod", "toInteger"]
    , classified "Enum" ["succ", "pred", "toEnum", "fromEnum", "enumFrom", "enumFromThen", "enumFromTo", "enumFromThenTo"]
    , classified "Bounded" ["minBound", "maxBound"]
    , classified "Functor" ["fmap"]
    , classified "Monad" [">>=", ">>", "return", "fail"]
    ]
 where
  typed parent children =
    (standardPreludeExternalName TypeNamespace parent, map (standardPreludeExternalName ConstructorNamespace) children)
  classified parent children =
    (standardPreludeExternalName ClassNamespace parent, map (standardPreludeExternalName TermNamespace) children)

standardPreludeExternalName :: Namespace -> Text -> RName
standardPreludeExternalName namespace occurrence =
  standardLibraryExternalName namespace occurrence

standardLibraryExternalName :: Namespace -> Text -> RName
standardLibraryExternalName namespace occurrence =
  RName
    { nameNamespace = namespace
    , nameOcc = occurrence
    , nameUnique = standardLibraryExternalUnique namespace occurrence
    , nameExternal = True
    }

standardLibraryExternalUnique :: Namespace -> Text -> Int
standardLibraryExternalUnique namespace occurrence =
  namespaceBase + maybe 0 id (List.elemIndex occurrence orderedOccurrences)
 where
  namespaceBase =
    case namespace of
      TermNamespace -> -100000
      ConstructorNamespace -> -110000
      TypeNamespace -> -120000
      ClassNamespace -> -130000
      ModuleNamespace -> -140000
      TypeVariableNamespace -> -150000
  orderedOccurrences =
    List.nub [occ | (candidateNamespace, occ) <- standardLibraryNames, candidateNamespace == namespace]

controlMonadModuleName :: S.ModuleName
controlMonadModuleName =
  S.ModuleName ["Control", "Monad"]

dataIntModuleName :: S.ModuleName
dataIntModuleName =
  S.ModuleName ["Data", "Int"]

dataCharModuleName :: S.ModuleName
dataCharModuleName =
  S.ModuleName ["Data", "Char"]

dataArrayModuleName :: S.ModuleName
dataArrayModuleName =
  S.ModuleName ["Data", "Array"]

dataBitsModuleName :: S.ModuleName
dataBitsModuleName =
  S.ModuleName ["Data", "Bits"]

dataIxModuleName :: S.ModuleName
dataIxModuleName =
  S.ModuleName ["Data", "Ix"]

dataListModuleName :: S.ModuleName
dataListModuleName =
  S.ModuleName ["Data", "List"]

dataMaybeModuleName :: S.ModuleName
dataMaybeModuleName =
  S.ModuleName ["Data", "Maybe"]

dataWordModuleName :: S.ModuleName
dataWordModuleName =
  S.ModuleName ["Data", "Word"]

systemIOModuleName :: S.ModuleName
systemIOModuleName =
  S.ModuleName ["System", "IO"]

systemIOErrorModuleName :: S.ModuleName
systemIOErrorModuleName =
  S.ModuleName ["System", "IO", "Error"]

foreignModuleName :: S.ModuleName
foreignModuleName =
  S.ModuleName ["Foreign"]

foreignPtrModuleName :: S.ModuleName
foreignPtrModuleName =
  S.ModuleName ["Foreign", "Ptr"]

foreignStablePtrModuleName :: S.ModuleName
foreignStablePtrModuleName =
  S.ModuleName ["Foreign", "StablePtr"]

foreignForeignPtrModuleName :: S.ModuleName
foreignForeignPtrModuleName =
  S.ModuleName ["Foreign", "ForeignPtr"]

foreignMarshalModuleName :: S.ModuleName
foreignMarshalModuleName =
  S.ModuleName ["Foreign", "Marshal"]

foreignMarshalErrorModuleName :: S.ModuleName
foreignMarshalErrorModuleName =
  S.ModuleName ["Foreign", "Marshal", "Error"]

foreignMarshalUtilsModuleName :: S.ModuleName
foreignMarshalUtilsModuleName =
  S.ModuleName ["Foreign", "Marshal", "Utils"]

foreignCModuleName :: S.ModuleName
foreignCModuleName =
  S.ModuleName ["Foreign", "C"]

foreignCStringModuleName :: S.ModuleName
foreignCStringModuleName =
  S.ModuleName ["Foreign", "C", "String"]

foreignCTypesModuleName :: S.ModuleName
foreignCTypesModuleName =
  S.ModuleName ["Foreign", "C", "Types"]

controlMonadInterface :: ModuleInterface
controlMonadInterface =
  standardLibraryInterfaceWith
    controlMonadModuleName
    controlMonadNames
    [ ((ClassNamespace, "Functor"), fmap (TermNamespace,) ["fmap"])
    , ((ClassNamespace, "Monad"), fmap (TermNamespace,) [">>=", ">>", "return", "fail"])
    , ((ClassNamespace, "MonadPlus"), fmap (TermNamespace,) ["mzero", "mplus"])
    ]
    (standardLibraryFixitiesFor controlMonadNames)

dataIntInterface :: ModuleInterface
dataIntInterface =
  standardLibraryInterface dataIntModuleName dataIntNames

dataCharInterface :: ModuleInterface
dataCharInterface =
  standardLibraryInterfaceWith
    dataCharModuleName
    dataCharNames
    [((TypeNamespace, "GeneralCategory"), fmap (ConstructorNamespace,) generalCategoryConstructors)]
    Map.empty

dataArrayInterface :: ModuleInterface
dataArrayInterface =
  standardLibraryInterfaceWith
    dataArrayModuleName
    (dataIxNames <> dataArrayNames)
    [((ClassNamespace, "Ix"), fmap (TermNamespace,) ["range", "index", "inRange", "rangeSize"])]
    (Map.fromList [("!", S.Fixity S.InfixL 9), ("//", S.Fixity S.InfixL 9)])

dataBitsInterface :: ModuleInterface
dataBitsInterface =
  standardLibraryInterfaceWith
    dataBitsModuleName
    dataBitsNames
    [((ClassNamespace, "Bits"), fmap (TermNamespace,) dataBitsMethodNames)]
    ( Map.fromList
        [ (".&.", S.Fixity S.InfixL 7)
        , ("xor", S.Fixity S.InfixL 6)
        , (".|.", S.Fixity S.InfixL 5)
        , ("shift", S.Fixity S.InfixL 8)
        , ("rotate", S.Fixity S.InfixL 8)
        , ("shiftL", S.Fixity S.InfixL 8)
        , ("shiftR", S.Fixity S.InfixL 8)
        , ("rotateL", S.Fixity S.InfixL 8)
        , ("rotateR", S.Fixity S.InfixL 8)
        ]
    )

dataIxInterface :: ModuleInterface
dataIxInterface =
  standardLibraryInterfaceWith
    dataIxModuleName
    dataIxNames
    [((ClassNamespace, "Ix"), fmap (TermNamespace,) ["range", "index", "inRange", "rangeSize"])]
    Map.empty

dataListInterface :: ModuleInterface
dataListInterface =
  standardLibraryInterfaceWith
    dataListModuleName
    dataListNames
    []
    (standardLibraryFixitiesFor dataListNames)

dataMaybeInterface :: ModuleInterface
dataMaybeInterface =
  standardLibraryInterfaceWith
    dataMaybeModuleName
    dataMaybeNames
    [((TypeNamespace, "Maybe"), fmap (ConstructorNamespace,) ["Nothing", "Just"])]
    Map.empty

dataWordInterface :: ModuleInterface
dataWordInterface =
  standardLibraryInterface dataWordModuleName dataWordNames

systemIOInterface :: ModuleInterface
systemIOInterface =
  standardLibraryInterface systemIOModuleName systemIONames

systemIOErrorInterface :: ModuleInterface
systemIOErrorInterface =
  standardLibraryInterface systemIOErrorModuleName systemIOErrorNames

foreignInterface :: ModuleInterface
foreignInterface =
  standardLibraryInterface foreignModuleName foreignNames

foreignPtrInterface :: ModuleInterface
foreignPtrInterface =
  standardLibraryInterface foreignPtrModuleName foreignPtrNames

foreignStablePtrInterface :: ModuleInterface
foreignStablePtrInterface =
  standardLibraryInterface foreignStablePtrModuleName foreignStablePtrNames

foreignForeignPtrInterface :: ModuleInterface
foreignForeignPtrInterface =
  standardLibraryInterface foreignForeignPtrModuleName foreignForeignPtrNames

foreignMarshalInterface :: ModuleInterface
foreignMarshalInterface =
  standardLibraryInterface foreignMarshalModuleName foreignMarshalNames

foreignMarshalErrorInterface :: ModuleInterface
foreignMarshalErrorInterface =
  standardLibraryInterface foreignMarshalErrorModuleName foreignMarshalErrorNames

foreignMarshalUtilsInterface :: ModuleInterface
foreignMarshalUtilsInterface =
  standardLibraryInterface foreignMarshalUtilsModuleName foreignMarshalUtilsNames

foreignCInterface :: ModuleInterface
foreignCInterface =
  standardLibraryInterface foreignCModuleName foreignCNames

foreignCStringInterface :: ModuleInterface
foreignCStringInterface =
  standardLibraryInterface foreignCStringModuleName foreignCStringNames

foreignCTypesInterface :: ModuleInterface
foreignCTypesInterface =
  standardLibraryInterface foreignCTypesModuleName foreignCTypesNames

standardLibraryInterface :: S.ModuleName -> [(Namespace, Text)] -> ModuleInterface
standardLibraryInterface moduleName names =
  standardLibraryInterfaceWith moduleName names [] Map.empty

standardLibraryInterfaceWith ::
  S.ModuleName ->
  [(Namespace, Text)] ->
  [((Namespace, Text), [(Namespace, Text)])] ->
  Map.Map Text S.Fixity ->
  ModuleInterface
standardLibraryInterfaceWith moduleName names children fixities =
  ModuleInterface
    { interfaceModuleName = moduleName
    , interfaceExports = [standardLibraryExternalName namespace occurrence | (namespace, occurrence) <- names]
    , interfaceChildren = standardLibraryChildren children
    , interfaceFixities = fixities
    , interfaceInstances = []
    }

standardLibraryChildren :: [((Namespace, Text), [(Namespace, Text)])] -> Map.Map RName [RName]
standardLibraryChildren children =
  Map.fromList
    [
      ( standardLibraryExternalName parentNamespace parentOccurrence
      , fmap (uncurry standardLibraryExternalName) childNames
      )
    | ((parentNamespace, parentOccurrence), childNames) <- children
    ]

standardLibraryFixitiesFor :: [(Namespace, Text)] -> Map.Map Text S.Fixity
standardLibraryFixitiesFor names =
  Map.filterWithKey (\occurrence _ -> occurrence `elem` termOccurrences) standardPreludeFixities
 where
  termOccurrences = [occurrence | (TermNamespace, occurrence) <- names]

standardLibraryNames :: [(Namespace, Text)]
standardLibraryNames =
  standardPreludeNames
    <> foreignNames
    <> foreignCNames
    <> foreignCStringNames
    <> foreignCTypesNames
    <> foreignPtrNames
    <> foreignMarshalNames
    <> controlMonadNames
    <> dataArrayNames
    <> dataCharNames
    <> dataIntNames
    <> dataIxNames
    <> dataListNames
    <> dataMaybeNames
    <> dataWordNames
    <> systemIONames
    <> systemIOErrorNames
    <> dataBitsNames

controlMonadNames :: [(Namespace, Text)]
controlMonadNames =
  (ClassNamespace, "Functor")
    : (ClassNamespace, "Monad")
    : (ClassNamespace, "MonadPlus")
    : fmap
      (TermNamespace,)
      [ "fmap"
      , ">>="
      , ">>"
      , "return"
      , "fail"
      , "mzero"
      , "mplus"
      , "mapM"
      , "mapM_"
      , "forM"
      , "forM_"
      , "sequence"
      , "sequence_"
      , "=<<"
      , ">=>"
      , "<=<"
      , "forever"
      , "void"
      , "join"
      , "msum"
      , "filterM"
      , "mapAndUnzipM"
      , "zipWithM"
      , "zipWithM_"
      , "foldM"
      , "foldM_"
      , "replicateM"
      , "replicateM_"
      , "guard"
      , "when"
      , "unless"
      , "liftM"
      , "liftM2"
      , "liftM3"
      , "liftM4"
      , "liftM5"
      , "ap"
      ]

dataIntNames :: [(Namespace, Text)]
dataIntNames =
  fmap (TypeNamespace,) ["Int8", "Int16", "Int32", "Int64"]

dataCharNames :: [(Namespace, Text)]
dataCharNames =
  fmap (TypeNamespace,) ["Char", "String", "GeneralCategory"]
    <> fmap (ConstructorNamespace,) generalCategoryConstructors
    <> fmap
      (TermNamespace,)
      [ "isControl"
      , "isSpace"
      , "isLower"
      , "isUpper"
      , "isAlpha"
      , "isAlphaNum"
      , "isPrint"
      , "isDigit"
      , "isOctDigit"
      , "isHexDigit"
      , "isLetter"
      , "isMark"
      , "isNumber"
      , "isPunctuation"
      , "isSymbol"
      , "isSeparator"
      , "isAscii"
      , "isLatin1"
      , "isAsciiUpper"
      , "isAsciiLower"
      , "generalCategory"
      , "toUpper"
      , "toLower"
      , "toTitle"
      , "digitToInt"
      , "intToDigit"
      , "ord"
      , "chr"
      , "showLitChar"
      , "lexLitChar"
      , "readLitChar"
      ]

generalCategoryConstructors :: [Text]
generalCategoryConstructors =
  [ "UppercaseLetter"
  , "LowercaseLetter"
  , "TitlecaseLetter"
  , "ModifierLetter"
  , "OtherLetter"
  , "NonSpacingMark"
  , "SpacingCombiningMark"
  , "EnclosingMark"
  , "DecimalNumber"
  , "LetterNumber"
  , "OtherNumber"
  , "ConnectorPunctuation"
  , "DashPunctuation"
  , "OpenPunctuation"
  , "ClosePunctuation"
  , "InitialQuote"
  , "FinalQuote"
  , "OtherPunctuation"
  , "MathSymbol"
  , "CurrencySymbol"
  , "ModifierSymbol"
  , "OtherSymbol"
  , "Space"
  , "LineSeparator"
  , "ParagraphSeparator"
  , "Control"
  , "Format"
  , "Surrogate"
  , "PrivateUse"
  , "NotAssigned"
  ]

dataIxNames :: [(Namespace, Text)]
dataIxNames =
  (ClassNamespace, "Ix")
    : fmap (TermNamespace,) ["range", "index", "inRange", "rangeSize"]

dataArrayNames :: [(Namespace, Text)]
dataArrayNames =
  (TypeNamespace, "Array")
    : fmap
      (TermNamespace,)
      [ "array"
      , "listArray"
      , "accumArray"
      , "!"
      , "bounds"
      , "indices"
      , "elems"
      , "assocs"
      , "//"
      , "accum"
      , "ixmap"
      ]

dataBitsNames :: [(Namespace, Text)]
dataBitsNames =
  (ClassNamespace, "Bits") : fmap (TermNamespace,) dataBitsMethodNames

dataBitsMethodNames :: [Text]
dataBitsMethodNames =
  [ ".&."
  , ".|."
  , "xor"
  , "complement"
  , "shift"
  , "rotate"
  , "bit"
  , "setBit"
  , "clearBit"
  , "complementBit"
  , "testBit"
  , "bitSize"
  , "isSigned"
  , "shiftL"
  , "shiftR"
  , "rotateL"
  , "rotateR"
  ]

dataListNames :: [(Namespace, Text)]
dataListNames =
  fmap
    (TermNamespace,)
    [ "++"
    , "head"
    , "last"
    , "tail"
    , "init"
    , "null"
    , "length"
    , "map"
    , "reverse"
    , "intersperse"
    , "intercalate"
    , "transpose"
    , "subsequences"
    , "permutations"
    , "foldl"
    , "foldl'"
    , "foldl1"
    , "foldl1'"
    , "foldr"
    , "foldr1"
    , "concat"
    , "concatMap"
    , "and"
    , "or"
    , "any"
    , "all"
    , "sum"
    , "product"
    , "maximum"
    , "minimum"
    , "scanl"
    , "scanl1"
    , "scanr"
    , "scanr1"
    , "mapAccumL"
    , "mapAccumR"
    , "iterate"
    , "repeat"
    , "replicate"
    , "cycle"
    , "unfoldr"
    , "take"
    , "drop"
    , "splitAt"
    , "takeWhile"
    , "dropWhile"
    , "span"
    , "break"
    , "stripPrefix"
    , "group"
    , "inits"
    , "tails"
    , "isPrefixOf"
    , "isSuffixOf"
    , "isInfixOf"
    , "elem"
    , "notElem"
    , "lookup"
    , "find"
    , "filter"
    , "partition"
    , "!!"
    , "elemIndex"
    , "elemIndices"
    , "findIndex"
    , "findIndices"
    , "zip"
    , "zip3"
    , "zip4"
    , "zip5"
    , "zip6"
    , "zip7"
    , "zipWith"
    , "zipWith3"
    , "zipWith4"
    , "zipWith5"
    , "zipWith6"
    , "zipWith7"
    , "unzip"
    , "unzip3"
    , "unzip4"
    , "unzip5"
    , "unzip6"
    , "unzip7"
    , "lines"
    , "words"
    , "unlines"
    , "unwords"
    , "nub"
    , "delete"
    , "\\\\"
    , "union"
    , "intersect"
    , "sort"
    , "insert"
    , "nubBy"
    , "deleteBy"
    , "deleteFirstsBy"
    , "unionBy"
    , "intersectBy"
    , "groupBy"
    , "sortBy"
    , "insertBy"
    , "maximumBy"
    , "minimumBy"
    , "genericLength"
    , "genericTake"
    , "genericDrop"
    , "genericSplitAt"
    , "genericIndex"
    , "genericReplicate"
    ]

dataMaybeNames :: [(Namespace, Text)]
dataMaybeNames =
  (TypeNamespace, "Maybe")
    : fmap (ConstructorNamespace,) ["Nothing", "Just"]
    <> fmap
      (TermNamespace,)
      [ "maybe"
      , "isJust"
      , "isNothing"
      , "fromJust"
      , "fromMaybe"
      , "listToMaybe"
      , "maybeToList"
      , "catMaybes"
      , "mapMaybe"
      ]

dataWordNames :: [(Namespace, Text)]
dataWordNames =
  fmap (TypeNamespace,) ["Word", "Word8", "Word16", "Word32", "Word64"]

fixedWidthWordNames :: [(Namespace, Text)]
fixedWidthWordNames =
  fmap (TypeNamespace,) ["Word8", "Word16", "Word32", "Word64"]

systemIONames :: [(Namespace, Text)]
systemIONames =
  (TypeNamespace, "IO")
    : (TypeNamespace, "Handle")
    : (TypeNamespace, "FilePath")
    : fmap (TermNamespace,) ["putStrLn", "getLine", "print"]

systemIOErrorNames :: [(Namespace, Text)]
systemIOErrorNames =
  fmap (TypeNamespace,) ["IOError", "IOErrorType"]
    <> fmap
      (TermNamespace,)
      [ "userError"
      , "mkIOError"
      , "annotateIOError"
      , "isAlreadyExistsError"
      , "isDoesNotExistError"
      , "isAlreadyInUseError"
      , "isFullError"
      , "isEOFError"
      , "isIllegalOperation"
      , "isPermissionError"
      , "isUserError"
      , "ioeGetErrorString"
      , "ioeGetHandle"
      , "ioeGetFileName"
      , "alreadyExistsErrorType"
      , "doesNotExistErrorType"
      , "alreadyInUseErrorType"
      , "fullErrorType"
      , "eofErrorType"
      , "illegalOperationErrorType"
      , "permissionErrorType"
      , "userErrorType"
      , "ioError"
      , "catch"
      , "try"
      ]

foreignNames :: [(Namespace, Text)]
foreignNames =
  foreignTypeNames <> foreignStablePtrNames <> foreignForeignPtrNames <> foreignMarshalNames

foreignTypeNames :: [(Namespace, Text)]
foreignTypeNames =
  dataIntNames <> fixedWidthWordNames <> foreignPtrNames

foreignPtrNames :: [(Namespace, Text)]
foreignPtrNames =
  fmap (TypeNamespace,) ["Ptr", "FunPtr"]
    <> fmap
      (TermNamespace,)
      [ "nullPtr"
      , "castPtr"
      , "nullFunPtr"
      , "castFunPtr"
      , "castFunPtrToPtr"
      , "castPtrToFunPtr"
      , "freeHaskellFunPtr"
      ]

foreignStablePtrNames :: [(Namespace, Text)]
foreignStablePtrNames =
  (TypeNamespace, "StablePtr")
    : fmap
      (TermNamespace,)
      [ "newStablePtr"
      , "deRefStablePtr"
      , "freeStablePtr"
      , "castStablePtrToPtr"
      , "castPtrToStablePtr"
      ]

foreignForeignPtrNames :: [(Namespace, Text)]
foreignForeignPtrNames =
  fmap (TypeNamespace,) ["ForeignPtr", "FinalizerPtr", "FinalizerEnvPtr"]
    <> fmap
      (TermNamespace,)
      [ "newForeignPtr"
      , "newForeignPtr_"
      , "addForeignPtrFinalizer"
      , "finalizeForeignPtr"
      , "unsafeForeignPtrToPtr"
      , "withForeignPtr"
      , "touchForeignPtr"
      , "castForeignPtr"
      ]

foreignMarshalNames :: [(Namespace, Text)]
foreignMarshalNames =
  foreignMarshalErrorNames <> foreignMarshalUtilsNames

foreignMarshalErrorNames :: [(Namespace, Text)]
foreignMarshalErrorNames =
  fmap (TermNamespace,) ["throwIf", "throwIf_", "throwIfNull", "void"]

foreignMarshalUtilsNames :: [(Namespace, Text)]
foreignMarshalUtilsNames =
  fmap (TermNamespace,) ["maybeNew", "maybeWith", "maybePeek"]

foreignCNames :: [(Namespace, Text)]
foreignCNames =
  foreignCStringNames <> foreignCTypesNames

foreignCStringNames :: [(Namespace, Text)]
foreignCStringNames =
  fmap (TypeNamespace,) ["CString", "CStringLen", "CWString", "CWStringLen"]

foreignCTypesNames :: [(Namespace, Text)]
foreignCTypesNames =
  fmap (TypeNamespace,) foreignCTypeOccurrences

foreignCTypeOccurrences :: [Text]
foreignCTypeOccurrences =
  [ "CChar"
  , "CSChar"
  , "CUChar"
  , "CShort"
  , "CUShort"
  , "CInt"
  , "CUInt"
  , "CLong"
  , "CULong"
  , "CLLong"
  , "CULLong"
  , "CFloat"
  , "CDouble"
  , "CPtrdiff"
  , "CSize"
  , "CWchar"
  , "CSigAtomic"
  , "CIntPtr"
  , "CUIntPtr"
  , "CIntMax"
  , "CUIntMax"
  , "CClock"
  , "CTime"
  , "CFile"
  , "CFpos"
  , "CJmpBuf"
  ]

standardLibrarySourceModule :: S.ModuleName -> Maybe Text
standardLibrarySourceModule moduleName
  | moduleName == dataArrayModuleName = Just dataArraySourceModule
  | moduleName == dataCharModuleName = Just dataCharSourceModule
  | moduleName == dataListModuleName = Just dataListSourceModule
  | moduleName == dataMaybeModuleName = Just dataMaybeSourceModule
  | otherwise = Nothing

dataArraySourceModule :: Text
dataArraySourceModule =
  Text.unlines
    [ "module Data.Array (module Data.Ix, Array, array, listArray, accumArray, (!), bounds, indices, elems, assocs, (//), accum, ixmap) where"
    , ""
    , "import Prelude"
    , "import Data.Ix"
    , "import Data.List (zipWith, notElem, foldl)"
    , ""
    , "infixl 9 !, //"
    , ""
    , "data Array i e = MkArray (i, i) [i] (i -> e)"
    , ""
    , "array :: Ix i => (i, i) -> [(i, e)] -> Array i e"
    , "array b ivs = if anyOutOfRange b ivs then head [] else MkArray b (range b) (lookupArray ivs)"
    , ""
    , "anyOutOfRange :: Ix i => (i, i) -> [(i, e)] -> Bool"
    , "anyOutOfRange b xs = case xs of"
    , "  [] -> False"
    , "  iv:rest -> if inRange b (fst iv) then anyOutOfRange b rest else True"
    , ""
    , "lookupArray :: Eq i => [(i, e)] -> i -> e"
    , "lookupArray ivs j = case [v | (i, v) <- ivs, i == j] of"
    , "  [v] -> v"
    , "  [] -> head []"
    , "  _ -> head []"
    , ""
    , "listArray :: Ix i => (i, i) -> [e] -> Array i e"
    , "listArray b vs = array b (zipWith pair (range b) vs)"
    , "  where"
    , "    pair i v = (i, v)"
    , ""
    , "(!) :: Ix i => Array i e -> i -> e"
    , "(!) (MkArray _ _ f) = f"
    , ""
    , "bounds :: Ix i => Array i e -> (i, i)"
    , "bounds (MkArray b _ _) = b"
    , ""
    , "indices :: Ix i => Array i e -> [i]"
    , "indices (MkArray _ is _) = is"
    , ""
    , "elems :: Ix i => Array i e -> [e]"
    , "elems (MkArray _ is f) = [f i | i <- is]"
    , ""
    , "assocs :: Ix i => Array i e -> [(i, e)]"
    , "assocs a = [(i, a ! i) | i <- indices a]"
    , ""
    , "(//) :: Ix i => Array i e -> [(i, e)] -> Array i e"
    , "a // newIvs = array (bounds a) ([(i, a ! i) | i <- indices a, notElem i [j | (j, _) <- newIvs]] ++ newIvs)"
    , ""
    , "accum :: Ix i => (e -> a -> e) -> Array i e -> [(i, a)] -> Array i e"
    , "accum f a ivs = foldl (accumOne f) a ivs"
    , ""
    , "accumOne :: Ix i => (e -> a -> e) -> Array i e -> (i, a) -> Array i e"
    , "accumOne f a iv = a // [(fst iv, f (a ! fst iv) (snd iv))]"
    , ""
    , "accumArray :: Ix i => (e -> a -> e) -> e -> (i, i) -> [(i, a)] -> Array i e"
    , "accumArray f z b ivs = accum f (array b [(i, z) | i <- range b]) ivs"
    , ""
    , "ixmap :: (Ix i, Ix j) => (i, i) -> (i -> j) -> Array j e -> Array i e"
    , "ixmap b f a = array b [(i, a ! f i) | i <- range b]"
    , ""
    , "instance Ix i => Functor (Array i) where"
    , "  fmap f (MkArray b is g) = MkArray b is (\\i -> f (g i))"
    , ""
    , "instance (Ix i, Eq e) => Eq (Array i e) where"
    , "  a == a' = assocs a == assocs a'"
    , "  a /= a' = not (a == a')"
    , ""
    , "instance (Ix i, Ord e) => Ord (Array i e) where"
    , "  compare a a' = compare (assocs a) (assocs a')"
    , "  a < a' = assocs a < assocs a'"
    , "  a <= a' = assocs a <= assocs a'"
    , "  a > a' = assocs a > assocs a'"
    , "  a >= a' = assocs a >= assocs a'"
    , "  max a a' = if a >= a' then a else a'"
    , "  min a a' = if a <= a' then a else a'"
    , ""
    , "arrPrec :: Int"
    , "arrPrec = 10"
    , ""
    , "arrayShowBounds :: Show i => (i, i) -> String"
    , "arrayShowBounds b = \"(\" ++ showsPrec 0 (fst b) (\",\" ++ showsPrec 0 (snd b) \")\")"
    , ""
    , "arrayShowAssoc :: (Show i, Show e) => (i, e) -> String"
    , "arrayShowAssoc iv = \"(\" ++ showsPrec 0 (fst iv) (\",\" ++ showsPrec 0 (snd iv) \")\")"
    , ""
    , "arrayShowAssocs :: (Show i, Show e) => [(i, e)] -> String"
    , "arrayShowAssocs xs = case xs of"
    , "  [] -> \"[]\""
    , "  iv:rest -> \"[\" ++ arrayShowAssocsTail iv rest"
    , ""
    , "arrayShowAssocsTail :: (Show i, Show e) => (i, e) -> [(i, e)] -> String"
    , "arrayShowAssocsTail iv rest = case rest of"
    , "  [] -> arrayShowAssoc iv ++ \"]\""
    , "  next:more -> arrayShowAssoc iv ++ \",\" ++ arrayShowAssocsTail next more"
    , ""
    , "arrayShowBody :: (Ix i, Show i, Show e) => Array i e -> String"
    , "arrayShowBody a = \"array \" ++ arrayShowBounds (bounds a) ++ \" \" ++ arrayShowAssocs (assocs a)"
    , ""
    , "arrayShowParen :: Bool -> String -> String"
    , "arrayShowParen p s = if p then \"(\" ++ s ++ \")\" else s"
    , ""
    , "arrayShowList :: (Ix i, Show i, Show e) => [Array i e] -> String"
    , "arrayShowList xs = case xs of"
    , "  [] -> \"[]\""
    , "  a:rest -> \"[\" ++ arrayShowListTail a rest"
    , ""
    , "arrayShowListTail :: (Ix i, Show i, Show e) => Array i e -> [Array i e] -> String"
    , "arrayShowListTail a rest = case rest of"
    , "  [] -> arrayShowBody a ++ \"]\""
    , "  b:bs -> arrayShowBody a ++ \",\" ++ arrayShowListTail b bs"
    , ""
    , "instance (Ix i, Show i, Show e) => Show (Array i e) where"
    , "  showsPrec p a rest = arrayShowParen (p > arrPrec) (arrayShowBody a) ++ rest"
    , "  show = arrayShowBody"
    , "  showList xs rest = arrayShowList xs ++ rest"
    , ""
    , "readArrayBounds :: Read i => ReadS (i, i)"
    , "readArrayBounds r = [((lo, hi), u) | (\"(\", s) <- lex r, (lo, t) <- readsPrec 0 s, (\",\", v) <- lex t, (hi, w) <- readsPrec 0 v, (\")\", u) <- lex w]"
    , ""
    , "readArrayAssoc :: (Read i, Read e) => ReadS (i, e)"
    , "readArrayAssoc r = [((i, e), u) | (\"(\", s) <- lex r, (i, t) <- readsPrec 0 s, (\",\", v) <- lex t, (e, w) <- readsPrec 0 v, (\")\", u) <- lex w]"
    , ""
    , "readArrayAssocs :: (Read i, Read e) => ReadS [(i, e)]"
    , "readArrayAssocs r = [(ivs, u) | (\"[\", s) <- lex r, (ivs, u) <- readArrayAssocsTail s]"
    , ""
    , "readArrayAssocsTail :: (Read i, Read e) => ReadS [(i, e)]"
    , "readArrayAssocsTail r = [([], s) | (\"]\", s) <- lex r] ++ [(iv:ivs, u) | (iv, s) <- readArrayAssoc r, (ivs, u) <- readArrayAssocsRest s]"
    , ""
    , "readArrayAssocsRest :: (Read i, Read e) => ReadS [(i, e)]"
    , "readArrayAssocsRest r = [(ivs, u) | (\",\", s) <- lex r, (ivs, u) <- readArrayAssocsTail s] ++ [([], s) | (\"]\", s) <- lex r]"
    , ""
    , "readArrayBody :: (Ix i, Read i, Read e) => ReadS (Array i e)"
    , "readArrayBody r = [(array b as, u) | (\"array\", s) <- lex r, (b, t) <- readArrayBounds s, (as, u) <- readArrayAssocs t]"
    , ""
    , "readArrayElement :: (Ix i, Read i, Read e) => ReadS (Array i e)"
    , "readArrayElement = readParen False readArrayBody"
    , ""
    , "readArrayList :: (Ix i, Read i, Read e) => ReadS [Array i e]"
    , "readArrayList r = [(xs, u) | (\"[\", s) <- lex r, (xs, u) <- readArrayListTail s]"
    , ""
    , "readArrayListTail :: (Ix i, Read i, Read e) => ReadS [Array i e]"
    , "readArrayListTail r = [([], s) | (\"]\", s) <- lex r] ++ [(a:as, u) | (a, s) <- readArrayElement r, (as, u) <- readArrayListRest s]"
    , ""
    , "readArrayListRest :: (Ix i, Read i, Read e) => ReadS [Array i e]"
    , "readArrayListRest r = [(as, u) | (\",\", s) <- lex r, (as, u) <- readArrayListTail s] ++ [([], s) | (\"]\", s) <- lex r]"
    , ""
    , "instance (Ix i, Read i, Read e) => Read (Array i e) where"
    , "  readsPrec p = readParen (p > arrPrec) readArrayBody"
    , "  readList = readArrayList"
    , ""
    ]

dataCharSourceModule :: Text
dataCharSourceModule =
  Text.unlines
    [ "module Data.Char (Char, String, isControl, isSpace, isLower, isUpper, isAlpha, isAlphaNum, isPrint, isDigit, isOctDigit, isHexDigit, isLetter, isMark, isNumber, isPunctuation, isSymbol, isSeparator, isAscii, isLatin1, isAsciiUpper, isAsciiLower, GeneralCategory(..), generalCategory, toUpper, toLower, toTitle, digitToInt, intToDigit, ord, chr, showLitChar, lexLitChar, readLitChar) where"
    , ""
    , "import Prelude"
    , ""
    , "data GeneralCategory = UppercaseLetter | LowercaseLetter | TitlecaseLetter | ModifierLetter | OtherLetter | NonSpacingMark | SpacingCombiningMark | EnclosingMark | DecimalNumber | LetterNumber | OtherNumber | ConnectorPunctuation | DashPunctuation | OpenPunctuation | ClosePunctuation | InitialQuote | FinalQuote | OtherPunctuation | MathSymbol | CurrencySymbol | ModifierSymbol | OtherSymbol | Space | LineSeparator | ParagraphSeparator | Control | Format | Surrogate | PrivateUse | NotAssigned deriving (Eq, Ord, Enum, Bounded, Show, Read)"
    , ""
    , "isControl :: Char -> Bool"
    , "isControl c = case generalCategory c of"
    , "  Control -> True"
    , "  _ -> False"
    , ""
    , "isSpace :: Char -> Bool"
    , "isSpace c = isSpaceControl c || (case generalCategory c of"
    , "  Space -> True"
    , "  LineSeparator -> True"
    , "  ParagraphSeparator -> True"
    , "  _ -> False)"
    , ""
    , "isSpaceControl :: Char -> Bool"
    , "isSpaceControl c = c == '\\t' || c == '\\n' || c == '\\r' || c == '\\f' || c == '\\v'"
    , ""
    , "isLower :: Char -> Bool"
    , "isLower c = case generalCategory c of"
    , "  LowercaseLetter -> True"
    , "  _ -> False"
    , ""
    , "isUpper :: Char -> Bool"
    , "isUpper c = case generalCategory c of"
    , "  UppercaseLetter -> True"
    , "  TitlecaseLetter -> True"
    , "  _ -> False"
    , ""
    , "isAlpha :: Char -> Bool"
    , "isAlpha = isLetter"
    , ""
    , "isAlphaNum :: Char -> Bool"
    , "isAlphaNum c = isAlpha c || isNumber c"
    , ""
    , "isPrint :: Char -> Bool"
    , "isPrint c = case generalCategory c of"
    , "  Control -> False"
    , "  Format -> False"
    , "  Surrogate -> False"
    , "  PrivateUse -> False"
    , "  NotAssigned -> False"
    , "  _ -> True"
    , ""
    , "isDigit :: Char -> Bool"
    , "isDigit c = codeBetween (ord '0') (ord '9') (ord c)"
    , ""
    , "isOctDigit :: Char -> Bool"
    , "isOctDigit c = codeBetween (ord '0') (ord '7') (ord c)"
    , ""
    , "isHexDigit :: Char -> Bool"
    , "isHexDigit c = isDigit c || codeBetween (ord 'a') (ord 'f') (ord c) || codeBetween (ord 'A') (ord 'F') (ord c)"
    , ""
    , "isLetter :: Char -> Bool"
    , "isLetter c = case generalCategory c of"
    , "  UppercaseLetter -> True"
    , "  LowercaseLetter -> True"
    , "  TitlecaseLetter -> True"
    , "  ModifierLetter -> True"
    , "  OtherLetter -> True"
    , "  _ -> False"
    , ""
    , "isMark :: Char -> Bool"
    , "isMark c = case generalCategory c of"
    , "  NonSpacingMark -> True"
    , "  SpacingCombiningMark -> True"
    , "  EnclosingMark -> True"
    , "  _ -> False"
    , ""
    , "isNumber :: Char -> Bool"
    , "isNumber c = case generalCategory c of"
    , "  DecimalNumber -> True"
    , "  LetterNumber -> True"
    , "  OtherNumber -> True"
    , "  _ -> False"
    , ""
    , "isPunctuation :: Char -> Bool"
    , "isPunctuation c = case generalCategory c of"
    , "  ConnectorPunctuation -> True"
    , "  DashPunctuation -> True"
    , "  OpenPunctuation -> True"
    , "  ClosePunctuation -> True"
    , "  InitialQuote -> True"
    , "  FinalQuote -> True"
    , "  OtherPunctuation -> True"
    , "  _ -> False"
    , ""
    , "isSymbol :: Char -> Bool"
    , "isSymbol c = case generalCategory c of"
    , "  MathSymbol -> True"
    , "  CurrencySymbol -> True"
    , "  ModifierSymbol -> True"
    , "  OtherSymbol -> True"
    , "  _ -> False"
    , ""
    , "isSeparator :: Char -> Bool"
    , "isSeparator c = case generalCategory c of"
    , "  Space -> True"
    , "  LineSeparator -> True"
    , "  ParagraphSeparator -> True"
    , "  _ -> False"
    , ""
    , "isAscii :: Char -> Bool"
    , "isAscii c = codeBetween 0 127 (ord c)"
    , ""
    , "isLatin1 :: Char -> Bool"
    , "isLatin1 c = codeBetween 0 255 (ord c)"
    , ""
    , "isAsciiUpper :: Char -> Bool"
    , "isAsciiUpper c = codeBetween (ord 'A') (ord 'Z') (ord c)"
    , ""
    , "isAsciiLower :: Char -> Bool"
    , "isAsciiLower c = codeBetween (ord 'a') (ord 'z') (ord c)"
    , ""
    , "generalCategory :: Char -> GeneralCategory"
    , "generalCategory c = categoryFromRanges (ord c) unicodeCategoryRanges"
    , ""
    , "toUpper :: Char -> Char"
    , "toUpper = mapCharCode toUpperRanges"
    , ""
    , "toLower :: Char -> Char"
    , "toLower = mapCharCode toLowerRanges"
    , ""
    , "toTitle :: Char -> Char"
    , "toTitle = mapCharCode toTitleRanges"
    , ""
    , "digitToInt :: Char -> Int"
    , "digitToInt c = if isDigit c then ord c - ord '0' else if codeBetween (ord 'a') (ord 'f') (ord c) then ord c - ord 'a' + 10 else if codeBetween (ord 'A') (ord 'F') (ord c) then ord c - ord 'A' + 10 else head []"
    , ""
    , "intToDigit :: Int -> Char"
    , "intToDigit n = if codeBetween 0 9 n then chr (ord '0' + n) else if codeBetween 10 15 n then chr (ord 'a' + n - 10) else head []"
    , ""
    , "ord :: Char -> Int"
    , "ord = fromEnum"
    , ""
    , "chr :: Int -> Char"
    , "chr = toEnum"
    , ""
    , "showLitChar :: Char -> ShowS"
    , "showLitChar c rest = stripCharQuotes (show c) ++ protectShownLiteral c rest"
    , ""
    , "protectShownLiteral :: Char -> String -> String"
    , "protectShownLiteral c rest = if ord c == 14 then protectSOEscape rest else rest"
    , ""
    , "protectSOEscape :: String -> String"
    , "protectSOEscape rest = case rest of"
    , "  'H':_ -> \"\\\\&\" ++ rest"
    , "  _ -> rest"
    , ""
    , "stripCharQuotes :: String -> String"
    , "stripCharQuotes xs = case xs of"
    , "  [] -> []"
    , "  _:body -> dropLastChar body"
    , ""
    , "dropLastChar :: String -> String"
    , "dropLastChar xs = case xs of"
    , "  [] -> []"
    , "  c:rest -> case rest of"
    , "    [] -> []"
    , "    _ -> c : dropLastChar rest"
    , ""
    , "lexLitChar :: ReadS String"
    , "lexLitChar input = case readLitChar input of"
    , "  [] -> []"
    , "  (_, rest):_ -> [(takeReadPrefix input rest, rest)]"
    , ""
    , "readLitChar :: ReadS Char"
    , "readLitChar input = case input of"
    , "  [] -> []"
    , "  c:rest -> if ord c == 92 then readEscapedChar rest else [(c, rest)]"
    , ""
    , "readEscapedChar :: String -> [(Char, String)]"
    , "readEscapedChar input = case input of"
    , "  [] -> []"
    , "  c:rest -> if c == 'a' then [('\\a', rest)] else if c == 'b' then [('\\b', rest)] else if c == 't' then [('\\t', rest)] else if c == 'n' then [('\\n', rest)] else if c == 'v' then [('\\v', rest)] else if c == 'f' then [('\\f', rest)] else if c == 'r' then [('\\r', rest)] else if ord c == 92 then [(chr 92, rest)] else if ord c == 34 then [(chr 34, rest)] else if ord c == 39 then [(chr 39, rest)] else if c == 'o' then readDigitsWith isOctDigit 8 rest else if c == 'x' then readDigitsWith isHexDigit 16 rest else if isDigit c then readDigitsRest 10 (digitToInt c) rest else readNamedEscape input"
    , ""
    , "readDigitsWith :: (Char -> Bool) -> Int -> String -> [(Char, String)]"
    , "readDigitsWith predicate base input = case input of"
    , "  [] -> []"
    , "  c:rest -> if predicate c then readDigitsRest base (digitToInt c) rest else []"
    , ""
    , "readDigitsRest :: Int -> Int -> String -> [(Char, String)]"
    , "readDigitsRest base acc input = case input of"
    , "  [] -> charCodeResult acc []"
    , "  c:rest -> if baseDigit base c then readDigitsRest base (acc * base + digitToInt c) rest else charCodeResult acc input"
    , ""
    , "baseDigit :: Int -> Char -> Bool"
    , "baseDigit base c = if base == 8 then isOctDigit c else if base == 16 then isHexDigit c else isDigit c"
    , ""
    , "charCodeResult :: Int -> String -> [(Char, String)]"
    , "charCodeResult code rest = if codeBetween 0 1114111 code then [(chr code, rest)] else []"
    , ""
    , "readNamedEscape :: String -> [(Char, String)]"
    , "readNamedEscape input = readNamedEscapes namedEscapeTable input"
    , ""
    , "namedEscapeTable :: [(String, Int)]"
    , "namedEscapeTable = [(\"NUL\",0),(\"SOH\",1),(\"STX\",2),(\"ETX\",3),(\"EOT\",4),(\"ENQ\",5),(\"ACK\",6),(\"BEL\",7),(\"BS\",8),(\"HT\",9),(\"LF\",10),(\"VT\",11),(\"FF\",12),(\"CR\",13),(\"SO\",14),(\"SI\",15),(\"DLE\",16),(\"DC1\",17),(\"DC2\",18),(\"DC3\",19),(\"DC4\",20),(\"NAK\",21),(\"SYN\",22),(\"ETB\",23),(\"CAN\",24),(\"EM\",25),(\"SUB\",26),(\"ESC\",27),(\"FS\",28),(\"GS\",29),(\"RS\",30),(\"US\",31),(\"DEL\",127)]"
    , ""
    , "readNamedEscapes :: [(String, Int)] -> String -> [(Char, String)]"
    , "readNamedEscapes table input = case table of"
    , "  [] -> []"
    , "  (token, code):rest -> case matchToken token input of"
    , "    [] -> readNamedEscapes rest input"
    , "    suffix:_ -> [(chr code, suffix)]"
    , ""
    , "matchToken :: String -> String -> [String]"
    , "matchToken token input = case token of"
    , "  [] -> [input]"
    , "  expected:expectedRest -> case input of"
    , "    [] -> []"
    , "    c:actualRest -> if c == expected then matchToken expectedRest actualRest else []"
    , ""
    , "takeReadPrefix :: String -> String -> String"
    , "takeReadPrefix input suffix = if sameString input suffix then [] else case input of"
    , "  [] -> []"
    , "  c:rest -> c : takeReadPrefix rest suffix"
    , ""
    , "sameString :: String -> String -> Bool"
    , "sameString lhs rhs = case lhs of"
    , "  [] -> case rhs of"
    , "    [] -> True"
    , "    _ -> False"
    , "  l:ls -> case rhs of"
    , "    [] -> False"
    , "    r:rs -> l == r && sameString ls rs"
    , ""
    , "codeBetween :: Int -> Int -> Int -> Bool"
    , "codeBetween low high value = low <= value && value <= high"
    , ""
    , "categoryFromRanges :: Int -> [(Int, Int, GeneralCategory)] -> GeneralCategory"
    , "categoryFromRanges code ranges = case ranges of"
    , "  [] -> NotAssigned"
    , "  (low, high, category):rest -> if code < low then NotAssigned else if code <= high then category else categoryFromRanges code rest"
    , ""
    , "mapCharCode :: [(Int, Int, Int)] -> Char -> Char"
    , "mapCharCode ranges c = chr (mappedCode (ord c) ranges)"
    , ""
    , "mappedCode :: Int -> [(Int, Int, Int)] -> Int"
    , "mappedCode code ranges = case ranges of"
    , "  [] -> code"
    , "  (low, high, mappedLow):rest -> if code < low then code else if code <= high then mappedLow + (code - low) else mappedCode code rest"
    , ""
    , "unicodeCategoryRanges :: [(Int, Int, GeneralCategory)]"
    , "unicodeCategoryRanges = [(0, 31, Control), (32, 32, Space), (33, 35, OtherPunctuation), (36, 36, CurrencySymbol), (37, 39, OtherPunctuation), (40, 40, OpenPunctuation), (41, 41, ClosePunctuation), (42, 43, MathSymbol), (44, 44, OtherPunctuation), (45, 45, DashPunctuation), (46, 47, OtherPunctuation), (48, 57, DecimalNumber), (58, 59, OtherPunctuation), (60, 62, MathSymbol), (63, 64, OtherPunctuation), (65, 90, UppercaseLetter), (91, 91, OpenPunctuation), (92, 92, OtherPunctuation), (93, 93, ClosePunctuation), (94, 94, ModifierSymbol), (95, 95, ConnectorPunctuation), (96, 96, ModifierSymbol), (97, 122, LowercaseLetter), (123, 123, OpenPunctuation), (124, 124, MathSymbol), (125, 125, ClosePunctuation), (126, 126, MathSymbol), (127, 159, Control), (160, 160, Space), (161, 161, OtherPunctuation), (162, 165, CurrencySymbol), (166, 169, OtherSymbol), (170, 170, LowercaseLetter), (171, 171, InitialQuote), (172, 174, OtherSymbol), (175, 175, ModifierSymbol), (176, 177, MathSymbol), (178, 179, OtherNumber), (180, 180, ModifierSymbol), (181, 181, LowercaseLetter), (182, 184, OtherPunctuation), (185, 185, OtherNumber), (186, 186, LowercaseLetter), (187, 187, FinalQuote), (188, 190, OtherNumber), (191, 191, OtherPunctuation), (192, 214, UppercaseLetter), (215, 215, MathSymbol), (216, 222, UppercaseLetter), (223, 246, LowercaseLetter), (247, 247, MathSymbol), (248, 255, LowercaseLetter), (256, 383, LowercaseLetter), (384, 591, OtherLetter), (768, 879, NonSpacingMark), (880, 912, OtherLetter), (913, 929, UppercaseLetter), (931, 939, UppercaseLetter), (940, 974, LowercaseLetter), (8192, 8202, Space), (8232, 8232, LineSeparator), (8233, 8233, ParagraphSeparator), (8239, 8239, Space), (8287, 8287, Space), (8364, 8364, CurrencySymbol), (12288, 12288, Space)]"
    , ""
    , "toUpperRanges :: [(Int, Int, Int)]"
    , "toUpperRanges = [(97, 122, 65), (224, 246, 192), (248, 254, 216), (255, 255, 376), (945, 961, 913), (963, 971, 931)]"
    , ""
    , "toLowerRanges :: [(Int, Int, Int)]"
    , "toLowerRanges = [(65, 90, 97), (192, 214, 224), (216, 222, 248), (376, 376, 255), (913, 929, 945), (931, 939, 963)]"
    , ""
    , "toTitleRanges :: [(Int, Int, Int)]"
    , "toTitleRanges = toUpperRanges"
    ]
dataMaybeSourceModule :: Text
dataMaybeSourceModule =
  Text.unlines
    [ "module Data.Maybe (Maybe(..), maybe, isJust, isNothing, fromJust, fromMaybe, listToMaybe, maybeToList, catMaybes, mapMaybe) where"
    , ""
    , "import Prelude"
    , ""
    , "maybe :: b -> (a -> b) -> Maybe a -> b"
    , "maybe defaultValue f value = case value of"
    , "  Nothing -> defaultValue"
    , "  Just x -> f x"
    , ""
    , "isJust :: Maybe a -> Bool"
    , "isJust value = case value of"
    , "  Nothing -> False"
    , "  Just _ -> True"
    , ""
    , "isNothing :: Maybe a -> Bool"
    , "isNothing value = case value of"
    , "  Nothing -> True"
    , "  Just _ -> False"
    , ""
    , "fromJust :: Maybe a -> a"
    , "fromJust value = case value of"
    , "  Nothing -> head []"
    , "  Just x -> x"
    , ""
    , "fromMaybe :: a -> Maybe a -> a"
    , "fromMaybe defaultValue value = case value of"
    , "  Nothing -> defaultValue"
    , "  Just x -> x"
    , ""
    , "listToMaybe :: [a] -> Maybe a"
    , "listToMaybe xs = case xs of"
    , "  [] -> Nothing"
    , "  x:_ -> Just x"
    , ""
    , "maybeToList :: Maybe a -> [a]"
    , "maybeToList value = case value of"
    , "  Nothing -> []"
    , "  Just x -> [x]"
    , ""
    , "catMaybes :: [Maybe a] -> [a]"
    , "catMaybes values = case values of"
    , "  [] -> []"
    , "  value:rest -> case value of"
    , "    Nothing -> catMaybes rest"
    , "    Just x -> x : catMaybes rest"
    , ""
    , "mapMaybe :: (a -> Maybe b) -> [a] -> [b]"
    , "mapMaybe f xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> case f x of"
    , "    Nothing -> mapMaybe f rest"
    , "    Just y -> y : mapMaybe f rest"
    ]

dataListSourceModule :: Text
dataListSourceModule =
  Text.unlines
    [ "module Data.List ((++), head, last, tail, init, null, length, map, reverse, intersperse, intercalate, transpose, subsequences, permutations, foldl, foldl', foldl1, foldl1', foldr, foldr1, concat, concatMap, and, or, any, all, sum, product, maximum, minimum, scanl, scanl1, scanr, scanr1, mapAccumL, mapAccumR, iterate, repeat, replicate, cycle, unfoldr, take, drop, splitAt, takeWhile, dropWhile, span, break, stripPrefix, group, inits, tails, isPrefixOf, isSuffixOf, isInfixOf, elem, notElem, lookup, find, filter, partition, (!!), elemIndex, elemIndices, findIndex, findIndices, zip, zip3, zip4, zip5, zip6, zip7, zipWith, zipWith3, zipWith4, zipWith5, zipWith6, zipWith7, unzip, unzip3, unzip4, unzip5, unzip6, unzip7, lines, words, unlines, unwords, nub, delete, (\\\\), union, intersect, sort, insert, nubBy, deleteBy, deleteFirstsBy, unionBy, intersectBy, groupBy, sortBy, insertBy, maximumBy, minimumBy, genericLength, genericTake, genericDrop, genericSplitAt, genericIndex, genericReplicate) where"
    , ""
    , "import Prelude"
    , ""
    , "infixr 5 ++"
    , "infixl 5 \\\\"
    , "infixl 9 !!"
    , ""
    , "last :: [a] -> a"
    , "last xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> case rest of"
    , "    [] -> x"
    , "    _ -> last rest"
    , ""
    , "init :: [a] -> [a]"
    , "init xs = case xs of"
    , "  [] -> tail []"
    , "  x:rest -> case rest of"
    , "    [] -> []"
    , "    _ -> x : init rest"
    , ""
    , "intersperse :: a -> [a] -> [a]"
    , "intersperse separator xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> case rest of"
    , "    [] -> [x]"
    , "    _ -> x : separator : intersperse separator rest"
    , ""
    , "intercalate :: [a] -> [[a]] -> [a]"
    , "intercalate separator xs = concat (intersperse separator xs)"
    , ""
    , "transpose :: [[a]] -> [[a]]"
    , "transpose xss = case dropEmptyRows xss of"
    , "  [] -> []"
    , "  rows -> transposeHeads rows : transpose (transposeTails rows)"
    , ""
    , "dropEmptyRows :: [[a]] -> [[a]]"
    , "dropEmptyRows rows = case rows of"
    , "  [] -> []"
    , "  row:rest -> case row of"
    , "    [] -> dropEmptyRows rest"
    , "    _ -> row : dropEmptyRows rest"
    , ""
    , "transposeHeads :: [[a]] -> [a]"
    , "transposeHeads rows = case rows of"
    , "  [] -> []"
    , "  row:rest -> case row of"
    , "    [] -> transposeHeads rest"
    , "    x:_ -> x : transposeHeads rest"
    , ""
    , "transposeTails :: [[a]] -> [[a]]"
    , "transposeTails rows = case rows of"
    , "  [] -> []"
    , "  row:rest -> case row of"
    , "    [] -> transposeTails rest"
    , "    _:xs -> xs : transposeTails rest"
    , ""
    , "subsequences :: [a] -> [[a]]"
    , "subsequences xs = [] : nonEmptySubsequences xs"
    , ""
    , "nonEmptySubsequences :: [a] -> [[a]]"
    , "nonEmptySubsequences xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> [x] : prependSubsequences x (nonEmptySubsequences rest)"
    , ""
    , "prependSubsequences :: a -> [[a]] -> [[a]]"
    , "prependSubsequences x yss = case yss of"
    , "  [] -> []"
    , "  ys:rest -> ys : (x : ys) : prependSubsequences x rest"
    , ""
    , "permutations :: [a] -> [[a]]"
    , "permutations xs = xs : permutationsRest xs []"
    , ""
    , "permutationsRest :: [a] -> [a] -> [[a]]"
    , "permutationsRest xs is = case xs of"
    , "  [] -> []"
    , "  t:ts -> foldr (permutationInterleave t ts) (permutationsRest ts (t : is)) (permutations is)"
    , ""
    , "permutationInterleave :: a -> [a] -> [a] -> [[a]] -> [[a]]"
    , "permutationInterleave t ts xs r = case permutationInterleave' t ts id xs r of"
    , "  pair -> case pair of"
    , "    (_, zs) -> zs"
    , ""
    , "permutationInterleave' :: a -> [a] -> ([a] -> [a]) -> [a] -> [[a]] -> ([a], [[a]])"
    , "permutationInterleave' t ts f xs r = case xs of"
    , "  [] -> (ts, r)"
    , "  y:ys -> case permutationInterleave' t ts (\\rest -> f (y : rest)) ys r of"
    , "    pair -> case pair of"
    , "      (us, zs) -> (y : us, f (t : y : us) : zs)"
    , ""
    , "foldl' :: (a -> b -> a) -> a -> [b] -> a"
    , "foldl' f z xs = case xs of"
    , "  [] -> z"
    , "  x:rest -> case f z x of"
    , "    z' -> foldl' f z' rest"
    , ""
    , "foldl1 :: (a -> a -> a) -> [a] -> a"
    , "foldl1 f xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> foldl f x rest"
    , ""
    , "foldl1' :: (a -> a -> a) -> [a] -> a"
    , "foldl1' f xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> foldl' f x rest"
    , ""
    , "foldr1 :: (a -> a -> a) -> [a] -> a"
    , "foldr1 f xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> case rest of"
    , "    [] -> x"
    , "    _ -> f x (foldr1 f rest)"
    , ""
    , "concat :: [[a]] -> [a]"
    , "concat xss = case xss of"
    , "  [] -> []"
    , "  xs:rest -> xs ++ concat rest"
    , ""
    , "concatMap :: (a -> [b]) -> [a] -> [b]"
    , "concatMap f xs = concat (map f xs)"
    , ""
    , "and :: [Bool] -> Bool"
    , "and xs = case xs of"
    , "  [] -> True"
    , "  x:rest -> x && and rest"
    , ""
    , "or :: [Bool] -> Bool"
    , "or xs = case xs of"
    , "  [] -> False"
    , "  x:rest -> x || or rest"
    , ""
    , "any :: (a -> Bool) -> [a] -> Bool"
    , "any p xs = case xs of"
    , "  [] -> False"
    , "  x:rest -> p x || any p rest"
    , ""
    , "all :: (a -> Bool) -> [a] -> Bool"
    , "all p xs = case xs of"
    , "  [] -> True"
    , "  x:rest -> p x && all p rest"
    , ""
    , "sum :: Num a => [a] -> a"
    , "sum = foldl' (+) 0"
    , ""
    , "product :: Num a => [a] -> a"
    , "product = foldl' (*) 1"
    , ""
    , "maximum :: Ord a => [a] -> a"
    , "maximum = maximumBy compare"
    , ""
    , "minimum :: Ord a => [a] -> a"
    , "minimum = minimumBy compare"
    , ""
    , "scanl :: (a -> b -> a) -> a -> [b] -> [a]"
    , "scanl f q xs = q : (case xs of"
    , "  [] -> []"
    , "  y:ys -> scanl f (f q y) ys)"
    , ""
    , "scanl1 :: (a -> a -> a) -> [a] -> [a]"
    , "scanl1 f xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> scanl f x rest"
    , ""
    , "scanr :: (a -> b -> b) -> b -> [a] -> [b]"
    , "scanr f q xs = case xs of"
    , "  [] -> [q]"
    , "  x:rest -> case scanr f q rest of"
    , "    qs@(q':_) -> f x q' : qs"
    , "    [] -> []"
    , ""
    , "scanr1 :: (a -> a -> a) -> [a] -> [a]"
    , "scanr1 f xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> case rest of"
    , "    [] -> [x]"
    , "    _ -> case scanr1 f rest of"
    , "      qs@(q:_) -> f x q : qs"
    , "      [] -> []"
    , ""
    , "mapAccumL :: (acc -> x -> (acc, y)) -> acc -> [x] -> (acc, [y])"
    , "mapAccumL f s xs = case xs of"
    , "  [] -> (s, [])"
    , "  x:rest -> case f s x of"
    , "    (s', y) -> case mapAccumL f s' rest of"
    , "      (s'', ys) -> (s'', y : ys)"
    , ""
    , "mapAccumR :: (acc -> x -> (acc, y)) -> acc -> [x] -> (acc, [y])"
    , "mapAccumR f s xs = case xs of"
    , "  [] -> (s, [])"
    , "  x:rest -> case mapAccumR f s rest of"
    , "    (s', ys) -> case f s' x of"
    , "      (s'', y) -> (s'', y : ys)"
    , ""
    , "iterate :: (a -> a) -> a -> [a]"
    , "iterate f x = x : iterate f (f x)"
    , ""
    , "repeat :: a -> [a]"
    , "repeat x = x : repeat x"
    , ""
    , "replicate :: Int -> a -> [a]"
    , "replicate n x"
    , "  | n <= 0 = []"
    , "  | otherwise = x : replicate (n - 1) x"
    , ""
    , "cycle :: [a] -> [a]"
    , "cycle xs = case xs of"
    , "  [] -> tail []"
    , "  _ -> xs ++ cycle xs"
    , ""
    , "unfoldr :: (b -> Maybe (a, b)) -> b -> [a]"
    , "unfoldr f seed = case f seed of"
    , "  Nothing -> []"
    , "  Just (x, seed') -> x : unfoldr f seed'"
    , ""
    , "take :: Int -> [a] -> [a]"
    , "take n xs"
    , "  | n <= 0 = []"
    , "  | otherwise = case xs of"
    , "    [] -> []"
    , "    x:rest -> x : take (n - 1) rest"
    , ""
    , "drop :: Int -> [a] -> [a]"
    , "drop n xs"
    , "  | n <= 0 = xs"
    , "  | otherwise = case xs of"
    , "    [] -> []"
    , "    _:rest -> drop (n - 1) rest"
    , ""
    , "splitAt :: Int -> [a] -> ([a], [a])"
    , "splitAt n xs = (take n xs, drop n xs)"
    , ""
    , "takeWhile :: (a -> Bool) -> [a] -> [a]"
    , "takeWhile p xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> if p x then x : takeWhile p rest else []"
    , ""
    , "dropWhile :: (a -> Bool) -> [a] -> [a]"
    , "dropWhile p xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> if p x then dropWhile p rest else xs"
    , ""
    , "span :: (a -> Bool) -> [a] -> ([a], [a])"
    , "span p xs = case xs of"
    , "  [] -> ([], [])"
    , "  x:rest -> if p x then (case span p rest of"
    , "    (ys, zs) -> (x : ys, zs)) else ([], xs)"
    , ""
    , "break :: (a -> Bool) -> [a] -> ([a], [a])"
    , "break p = span (not . p)"
    , ""
    , "stripPrefix :: Eq a => [a] -> [a] -> Maybe [a]"
    , "stripPrefix prefix ys = case prefix of"
    , "  [] -> Just ys"
    , "  x:xs -> case ys of"
    , "    y:rest -> if x == y then stripPrefix xs rest else Nothing"
    , "    [] -> Nothing"
    , ""
    , "group :: Eq a => [a] -> [[a]]"
    , "group = groupBy (==)"
    , ""
    , "inits :: [a] -> [[a]]"
    , "inits xs = case xs of"
    , "  [] -> [[]]"
    , "  x:rest -> [] : map (\\prefix -> x : prefix) (inits rest)"
    , ""
    , "tails :: [a] -> [[a]]"
    , "tails xs = case xs of"
    , "  [] -> [[]]"
    , "  _:rest -> xs : tails rest"
    , ""
    , "isPrefixOf :: Eq a => [a] -> [a] -> Bool"
    , "isPrefixOf prefix ys = case prefix of"
    , "  [] -> True"
    , "  x:xs -> case ys of"
    , "    [] -> False"
    , "    y:rest -> x == y && isPrefixOf xs rest"
    , ""
    , "isSuffixOf :: Eq a => [a] -> [a] -> Bool"
    , "isSuffixOf xs ys = isPrefixOf (reverse xs) (reverse ys)"
    , ""
    , "isInfixOf :: Eq a => [a] -> [a] -> Bool"
    , "isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)"
    , ""
    , "elem :: Eq a => a -> [a] -> Bool"
    , "elem x xs = case xs of"
    , "  [] -> False"
    , "  y:rest -> x == y || elem x rest"
    , ""
    , "notElem :: Eq a => a -> [a] -> Bool"
    , "notElem x xs = not (elem x xs)"
    , ""
    , "lookup :: Eq a => a -> [(a, b)] -> Maybe b"
    , "lookup key xys = case xys of"
    , "  [] -> Nothing"
    , "  (x, y):rest -> if key == x then Just y else lookup key rest"
    , ""
    , "find :: (a -> Bool) -> [a] -> Maybe a"
    , "find p xs = case xs of"
    , "  [] -> Nothing"
    , "  x:rest -> if p x then Just x else find p rest"
    , ""
    , "partition :: (a -> Bool) -> [a] -> ([a], [a])"
    , "partition p xs = case xs of"
    , "  [] -> ([], [])"
    , "  x:rest -> case partition p rest of"
    , "    (trues, falses) -> if p x then (x : trues, falses) else (trues, x : falses)"
    , ""
    , "(!!) :: [a] -> Int -> a"
    , "xs !! n = case xs of"
    , "  [] -> head []"
    , "  x:rest -> if n == 0 then x else if n > 0 then rest !! (n - 1) else head []"
    , ""
    , "elemIndex :: Eq a => a -> [a] -> Maybe Int"
    , "elemIndex x xs = findIndex (== x) xs"
    , ""
    , "elemIndices :: Eq a => a -> [a] -> [Int]"
    , "elemIndices x xs = findIndices (== x) xs"
    , ""
    , "findIndex :: (a -> Bool) -> [a] -> Maybe Int"
    , "findIndex p xs = findIndexFrom 0 p xs"
    , ""
    , "findIndexFrom :: Int -> (a -> Bool) -> [a] -> Maybe Int"
    , "findIndexFrom n p xs = case xs of"
    , "  [] -> Nothing"
    , "  x:rest -> if p x then Just n else findIndexFrom (n + 1) p rest"
    , ""
    , "findIndices :: (a -> Bool) -> [a] -> [Int]"
    , "findIndices p xs = findIndicesFrom 0 p xs"
    , ""
    , "findIndicesFrom :: Int -> (a -> Bool) -> [a] -> [Int]"
    , "findIndicesFrom n p xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> if p x then n : findIndicesFrom (n + 1) p rest else findIndicesFrom (n + 1) p rest"
    , ""
    , "zip :: [a] -> [b] -> [(a, b)]"
    , "zip as bs = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> (a, b) : zip as' bs'"
    , ""
    , "zip3 :: [a] -> [b] -> [c] -> [(a, b, c)]"
    , "zip3 as bs cs = zipWith3 (\\a b c -> (a, b, c)) as bs cs"
    , ""
    , "zip4 :: [a] -> [b] -> [c] -> [d] -> [(a, b, c, d)]"
    , "zip4 as bs cs ds = zipWith4 (\\a b c d -> (a, b, c, d)) as bs cs ds"
    , ""
    , "zip5 :: [a] -> [b] -> [c] -> [d] -> [e] -> [(a, b, c, d, e)]"
    , "zip5 as bs cs ds es = zipWith5 (\\a b c d e -> (a, b, c, d, e)) as bs cs ds es"
    , ""
    , "zip6 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [(a, b, c, d, e, f)]"
    , "zip6 as bs cs ds es fs = zipWith6 (\\a b c d e f -> (a, b, c, d, e, f)) as bs cs ds es fs"
    , ""
    , "zip7 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g] -> [(a, b, c, d, e, f, g)]"
    , "zip7 as bs cs ds es fs gs = zipWith7 (\\a b c d e f g -> (a, b, c, d, e, f, g)) as bs cs ds es fs gs"
    , ""
    , "zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]"
    , "zipWith f as bs = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> f a b : zipWith f as' bs'"
    , ""
    , "zipWith3 :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]"
    , "zipWith3 f as bs cs = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> case cs of"
    , "      [] -> []"
    , "      c:cs' -> f a b c : zipWith3 f as' bs' cs'"
    , ""
    , "zipWith4 :: (a -> b -> c -> d -> e) -> [a] -> [b] -> [c] -> [d] -> [e]"
    , "zipWith4 f as bs cs ds = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> case cs of"
    , "      [] -> []"
    , "      c:cs' -> case ds of"
    , "        [] -> []"
    , "        d:ds' -> f a b c d : zipWith4 f as' bs' cs' ds'"
    , ""
    , "zipWith5 :: (a -> b -> c -> d -> e -> f) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f]"
    , "zipWith5 f as bs cs ds es = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> case cs of"
    , "      [] -> []"
    , "      c:cs' -> case ds of"
    , "        [] -> []"
    , "        d:ds' -> case es of"
    , "          [] -> []"
    , "          e:es' -> f a b c d e : zipWith5 f as' bs' cs' ds' es'"
    , ""
    , "zipWith6 :: (a -> b -> c -> d -> e -> f -> g) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g]"
    , "zipWith6 f as bs cs ds es fs = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> case cs of"
    , "      [] -> []"
    , "      c:cs' -> case ds of"
    , "        [] -> []"
    , "        d:ds' -> case es of"
    , "          [] -> []"
    , "          e:es' -> case fs of"
    , "            [] -> []"
    , "            f':fs' -> f a b c d e f' : zipWith6 f as' bs' cs' ds' es' fs'"
    , ""
    , "zipWith7 :: (a -> b -> c -> d -> e -> f -> g -> h) -> [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [g] -> [h]"
    , "zipWith7 f as bs cs ds es fs gs = case as of"
    , "  [] -> []"
    , "  a:as' -> case bs of"
    , "    [] -> []"
    , "    b:bs' -> case cs of"
    , "      [] -> []"
    , "      c:cs' -> case ds of"
    , "        [] -> []"
    , "        d:ds' -> case es of"
    , "          [] -> []"
    , "          e:es' -> case fs of"
    , "            [] -> []"
    , "            f':fs' -> case gs of"
    , "              [] -> []"
    , "              g:gs' -> f a b c d e f' g : zipWith7 f as' bs' cs' ds' es' fs' gs'"
    , ""
    , "unzip :: [(a, b)] -> ([a], [b])"
    , "unzip xs = case xs of"
    , "  [] -> ([], [])"
    , "  (a, b):rest -> case unzip rest of"
    , "    (as, bs) -> (a : as, b : bs)"
    , ""
    , "unzip3 :: [(a, b, c)] -> ([a], [b], [c])"
    , "unzip3 xs = case xs of"
    , "  [] -> ([], [], [])"
    , "  (a, b, c):rest -> case unzip3 rest of"
    , "    (as, bs, cs) -> (a : as, b : bs, c : cs)"
    , ""
    , "unzip4 :: [(a, b, c, d)] -> ([a], [b], [c], [d])"
    , "unzip4 xs = case xs of"
    , "  [] -> ([], [], [], [])"
    , "  (a, b, c, d):rest -> case unzip4 rest of"
    , "    (as, bs, cs, ds) -> (a : as, b : bs, c : cs, d : ds)"
    , ""
    , "unzip5 :: [(a, b, c, d, e)] -> ([a], [b], [c], [d], [e])"
    , "unzip5 xs = case xs of"
    , "  [] -> ([], [], [], [], [])"
    , "  (a, b, c, d, e):rest -> case unzip5 rest of"
    , "    (as, bs, cs, ds, es) -> (a : as, b : bs, c : cs, d : ds, e : es)"
    , ""
    , "unzip6 :: [(a, b, c, d, e, f)] -> ([a], [b], [c], [d], [e], [f])"
    , "unzip6 xs = case xs of"
    , "  [] -> ([], [], [], [], [], [])"
    , "  (a, b, c, d, e, f):rest -> case unzip6 rest of"
    , "    (as, bs, cs, ds, es, fs) -> (a : as, b : bs, c : cs, d : ds, e : es, f : fs)"
    , ""
    , "unzip7 :: [(a, b, c, d, e, f, g)] -> ([a], [b], [c], [d], [e], [f], [g])"
    , "unzip7 xs = case xs of"
    , "  [] -> ([], [], [], [], [], [], [])"
    , "  (a, b, c, d, e, f, g):rest -> case unzip7 rest of"
    , "    (as, bs, cs, ds, es, fs, gs) -> (a : as, b : bs, c : cs, d : ds, e : es, f : fs, g : gs)"
    , ""
    , "lines :: String -> [String]"
    , "lines xs = case xs of"
    , "  [] -> []"
    , "  _ -> case break (== '\\n') xs of"
    , "    (line, suffix) -> case suffix of"
    , "      [] -> [line]"
    , "      _:rest -> line : lines rest"
    , ""
    , "words :: String -> [String]"
    , "words xs = case dropWhile isSpaceChar xs of"
    , "  [] -> []"
    , "  rest -> case break isSpaceChar rest of"
    , "    (word, suffix) -> word : words suffix"
    , ""
    , "isSpaceChar :: Char -> Bool"
    , "isSpaceChar c = c == ' ' || c == '\\t' || c == '\\n' || c == '\\r' || c == '\\f' || c == '\\v'"
    , ""
    , "unlines :: [String] -> String"
    , "unlines xs = case xs of"
    , "  [] -> []"
    , "  line:rest -> line ++ ('\\n' : unlines rest)"
    , ""
    , "unwords :: [String] -> String"
    , "unwords xs = case xs of"
    , "  [] -> []"
    , "  word:rest -> case rest of"
    , "    [] -> word"
    , "    _ -> word ++ (' ' : unwords rest)"
    , ""
    , "nub :: Eq a => [a] -> [a]"
    , "nub = nubBy (==)"
    , ""
    , "delete :: Eq a => a -> [a] -> [a]"
    , "delete = deleteBy (==)"
    , ""
    , "(\\\\) :: Eq a => [a] -> [a] -> [a]"
    , "xs \\\\ ys = deleteFirstsBy (==) xs ys"
    , ""
    , "union :: Eq a => [a] -> [a] -> [a]"
    , "union = unionBy (==)"
    , ""
    , "intersect :: Eq a => [a] -> [a] -> [a]"
    , "intersect = intersectBy (==)"
    , ""
    , "sort :: Ord a => [a] -> [a]"
    , "sort = sortBy compare"
    , ""
    , "insert :: Ord a => a -> [a] -> [a]"
    , "insert = insertBy compare"
    , ""
    , "nubBy :: (a -> a -> Bool) -> [a] -> [a]"
    , "nubBy eq xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> x : nubBy eq (filter (\\y -> not (eq x y)) rest)"
    , ""
    , "deleteBy :: (a -> a -> Bool) -> a -> [a] -> [a]"
    , "deleteBy eq x ys = case ys of"
    , "  [] -> []"
    , "  y:rest -> if eq x y then rest else y : deleteBy eq x rest"
    , ""
    , "deleteFirstsBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]"
    , "deleteFirstsBy eq xs ys = case ys of"
    , "  [] -> xs"
    , "  y:rest -> deleteFirstsBy eq (deleteBy eq y xs) rest"
    , ""
    , "unionBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]"
    , "unionBy eq xs ys = xs ++ deleteFirstsBy eq (nubBy eq ys) xs"
    , ""
    , "intersectBy :: (a -> a -> Bool) -> [a] -> [a] -> [a]"
    , "intersectBy eq xs ys = [x | x <- xs, any (eq x) ys]"
    , ""
    , "groupBy :: (a -> a -> Bool) -> [a] -> [[a]]"
    , "groupBy eq xs = case xs of"
    , "  [] -> []"
    , "  x:rest -> case span (eq x) rest of"
    , "    (ys, zs) -> (x : ys) : groupBy eq zs"
    , ""
    , "sortBy :: (a -> a -> Ordering) -> [a] -> [a]"
    , "sortBy cmp = foldr (insertBy cmp) []"
    , ""
    , "insertBy :: (a -> a -> Ordering) -> a -> [a] -> [a]"
    , "insertBy cmp x ys = case ys of"
    , "  [] -> [x]"
    , "  y:rest -> case cmp x y of"
    , "    GT -> y : insertBy cmp x rest"
    , "    _ -> x : ys"
    , ""
    , "maximumBy :: (a -> a -> Ordering) -> [a] -> a"
    , "maximumBy cmp xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> foldl (maximumByStep cmp) x rest"
    , ""
    , "maximumByStep :: (a -> a -> Ordering) -> a -> a -> a"
    , "maximumByStep cmp best value = case cmp best value of"
    , "  GT -> best"
    , "  _ -> value"
    , ""
    , "minimumBy :: (a -> a -> Ordering) -> [a] -> a"
    , "minimumBy cmp xs = case xs of"
    , "  [] -> head []"
    , "  x:rest -> foldl (minimumByStep cmp) x rest"
    , ""
    , "minimumByStep :: (a -> a -> Ordering) -> a -> a -> a"
    , "minimumByStep cmp best value = case cmp best value of"
    , "  GT -> value"
    , "  _ -> best"
    , ""
    , "genericLength :: Num i => [b] -> i"
    , "genericLength = foldl' (\\n _ -> n + 1) 0"
    , ""
    , "genericTake :: Integral i => i -> [a] -> [a]"
    , "genericTake n xs"
    , "  | n <= 0 = []"
    , "  | otherwise = case xs of"
    , "    [] -> []"
    , "    x:rest -> x : genericTake (n - 1) rest"
    , ""
    , "genericDrop :: Integral i => i -> [a] -> [a]"
    , "genericDrop n xs"
    , "  | n <= 0 = xs"
    , "  | otherwise = case xs of"
    , "    [] -> []"
    , "    _:rest -> genericDrop (n - 1) rest"
    , ""
    , "genericSplitAt :: Integral i => i -> [b] -> ([b], [b])"
    , "genericSplitAt n xs = (genericTake n xs, genericDrop n xs)"
    , ""
    , "genericIndex :: Integral i => [b] -> i -> b"
    , "genericIndex xs n = case xs of"
    , "  [] -> head []"
    , "  x:rest -> if n == 0 then x else if n > 0 then genericIndex rest (n - 1) else head []"
    , ""
    , "genericReplicate :: Integral i => i -> a -> [a]"
    , "genericReplicate n x"
    , "  | n <= 0 = []"
    , "  | otherwise = x : genericReplicate (n - 1) x"
    ]
