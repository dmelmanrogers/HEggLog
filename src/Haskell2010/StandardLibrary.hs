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
    , (dataIntModuleName, dataIntInterface)
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
    <> dataIntNames
    <> dataListNames
    <> dataMaybeNames
    <> dataWordNames
    <> systemIONames
    <> systemIOErrorNames

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
  | moduleName == dataListModuleName = Just dataListSourceModule
  | moduleName == dataMaybeModuleName = Just dataMaybeSourceModule
  | otherwise = Nothing

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
