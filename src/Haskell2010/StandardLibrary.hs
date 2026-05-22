module Haskell2010.StandardLibrary
  ( implicitPreludeImport
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
    , ("&&", S.Fixity S.InfixR 3)
    , ("||", S.Fixity S.InfixR 2)
    , (">>=", S.Fixity S.InfixL 1)
    , (">>", S.Fixity S.InfixL 1)
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
    , "$"
    , "."
    , "flip"
    , "pure"
    , "return"
    , "fail"
    , "fmap"
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
    : fmap (TermNamespace,) ["fmap", ">>=", ">>", "return", "fail"]

dataIntNames :: [(Namespace, Text)]
dataIntNames =
  fmap (TypeNamespace,) ["Int8", "Int16", "Int32", "Int64"]

dataListNames :: [(Namespace, Text)]
dataListNames =
  fmap
    (TermNamespace,)
    ["++", "head", "tail", "null", "length", "map", "reverse", "foldl", "foldr", "filter"]

dataMaybeNames :: [(Namespace, Text)]
dataMaybeNames =
  (TypeNamespace, "Maybe")
    : fmap (ConstructorNamespace,) ["Nothing", "Just"]

dataWordNames :: [(Namespace, Text)]
dataWordNames =
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
  dataIntNames <> dataWordNames <> foreignPtrNames

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
