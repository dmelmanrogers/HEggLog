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
    , (foreignModuleName, foreignInterface)
    , (foreignStablePtrModuleName, foreignStablePtrInterface)
    , (foreignForeignPtrModuleName, foreignForeignPtrInterface)
    , (foreignCModuleName, foreignCInterface)
    , (foreignCTypesModuleName, foreignCTypesInterface)
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
    , "++"
    , ">>="
    , ">>"
    , "$"
    , "."
    , "pure"
    , "return"
    , "fail"
    , "fmap"
    , "map"
    , "foldr"
    , "length"
    , "filter"
    , "reverse"
    , "show"
    , "putStrLn"
    , "getLine"
    , "print"
    , "not"
    , "id"
    , "const"
    , "otherwise"
    ]
    <> fmap (ConstructorNamespace,) ["True", "False", "Nothing", "Just", "Left", "Right", "LT", "EQ", "GT", ":"]
    <> fmap (TypeNamespace,) ["Int", "Integer", "Bool", "Char", "String", "[]", "IO", "CString", "Maybe", "Either", "Ordering", "()"]
    <> fmap (ClassNamespace,) ["Eq", "Ord", "Show", "Read", "Num", "Enum", "Bounded", "Functor", "Monad"]

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
    , classified "Show" ["show"]
    , classified "Num" ["+", "-", "*", "negate", "abs", "signum", "fromInteger"]
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

foreignModuleName :: S.ModuleName
foreignModuleName =
  S.ModuleName ["Foreign"]

foreignStablePtrModuleName :: S.ModuleName
foreignStablePtrModuleName =
  S.ModuleName ["Foreign", "StablePtr"]

foreignForeignPtrModuleName :: S.ModuleName
foreignForeignPtrModuleName =
  S.ModuleName ["Foreign", "ForeignPtr"]

foreignCModuleName :: S.ModuleName
foreignCModuleName =
  S.ModuleName ["Foreign", "C"]

foreignCTypesModuleName :: S.ModuleName
foreignCTypesModuleName =
  S.ModuleName ["Foreign", "C", "Types"]

foreignInterface :: ModuleInterface
foreignInterface =
  standardLibraryInterface foreignModuleName foreignNames

foreignStablePtrInterface :: ModuleInterface
foreignStablePtrInterface =
  standardLibraryInterface foreignStablePtrModuleName foreignStablePtrNames

foreignForeignPtrInterface :: ModuleInterface
foreignForeignPtrInterface =
  standardLibraryInterface foreignForeignPtrModuleName foreignForeignPtrNames

foreignCInterface :: ModuleInterface
foreignCInterface =
  standardLibraryInterface foreignCModuleName foreignCNames

foreignCTypesInterface :: ModuleInterface
foreignCTypesInterface =
  standardLibraryInterface foreignCTypesModuleName foreignCTypesNames

standardLibraryInterface :: S.ModuleName -> [(Namespace, Text)] -> ModuleInterface
standardLibraryInterface moduleName names =
  ModuleInterface
    { interfaceModuleName = moduleName
    , interfaceExports = [standardLibraryExternalName namespace occurrence | (namespace, occurrence) <- names]
    , interfaceChildren = Map.empty
    , interfaceFixities = Map.empty
    , interfaceInstances = []
    }

standardLibraryNames :: [(Namespace, Text)]
standardLibraryNames =
  standardPreludeNames <> foreignNames <> foreignCNames <> foreignCTypesNames

foreignNames :: [(Namespace, Text)]
foreignNames =
  foreignTypeNames <> foreignStablePtrNames <> foreignForeignPtrNames

foreignTypeNames :: [(Namespace, Text)]
foreignTypeNames =
  fmap (TypeNamespace,)
    [ "Int8"
    , "Int16"
    , "Int32"
    , "Int64"
    , "Word8"
    , "Word16"
    , "Word32"
    , "Word64"
    , "Ptr"
    , "FunPtr"
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
  (TypeNamespace, "ForeignPtr")
    : fmap
      (TermNamespace,)
      [ "newForeignPtr"
      , "newForeignPtr_"
      , "addForeignPtrFinalizer"
      , "finalizeForeignPtr"
      , "withForeignPtr"
      , "touchForeignPtr"
      ]

foreignCNames :: [(Namespace, Text)]
foreignCNames =
  fmap (TypeNamespace,) ("CString" : "CWString" : foreignCTypeOccurrences)

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
