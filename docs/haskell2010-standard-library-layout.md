# Haskell 2010 Standard Library Layout

This document records the compiler boundary for Haskell 2010 standard-library
modules. The Haskell 2010 Report treats `Prelude` as a distinguished module
that is imported by default, while still being an ordinary module for import
filtering and qualification. The Libraries Report also defines a fixed module
surface outside `Prelude`; the compiler exposes only modules whose exported
names have real parser, renamer, typechecker, Core/STG, and native support.

## Implemented Boundary

`Haskell2010.StandardLibrary` owns every generated standard-library module
interface. The renamer consumes those interfaces through `ModuleInterface`,
the same data model used by source modules:

- exported names
- parent-to-child exports for `Thing(..)` data constructors and class methods
- imported fixities
- instance exports

Generated interfaces deliberately carry no fake declarations and no empty
module placeholders. Importing a reserved module still fails through the module
graph path until that module has an implemented surface.

| Module | Status | Generated surface |
| --- | --- | --- |
| `Prelude` | implemented for current executable subset | supported built-in data constructors, classes, class methods, list functions, IO functions, tuple/list/unit types, `Thing(..)` children, and Prelude fixities |
| `Control.Monad` | partial generated interface | `Functor(fmap)` plus `Monad(..)` for `return`, `(>>=)`, `(>>)`, and `fail`, with method fixities where applicable; `LIB-001` owns the remaining Report combinators |
| `Data.Int` | partial generated interface | `Int8`, `Int16`, `Int32`, `Int64` type names for the supported scalar foreign-type surface; `LIB-009` owns real fixed-width representations and instances |
| `Data.List` | partial generated interface | `(++)`, `head`, `tail`, `null`, `length`, `map`, `reverse`, `foldl`, `foldr`, and `filter`, plus `(++)` fixity; `LIB-002` owns the remaining Report list API |
| `Data.Maybe` | partial generated interface | `Maybe(..)` with `Nothing` and `Just`; `LIB-003` owns the remaining Report functions |
| `Data.Word` | partial generated interface | `Word8`, `Word16`, `Word32`, `Word64` type names for the supported scalar foreign-type surface; `LIB-009` owns real fixed-width representations and instances |
| `System.IO` | partial generated interface | `IO`, `Handle`, `FilePath`, `putStrLn`, `getLine`, and `print`; `LIB-012` owns handles, files, buffering, seek, and EOF-specific handle behavior |
| `System.IO.Error` | partial generated interface | `IOError`, `IOErrorType`, error-type constants, `userError`, `mkIOError`, `annotateIOError`, classifiers, accessors, `ioError`, `catch`, and `try`; `LIB-012` owns handle/file-backed error producers beyond the current line-oriented IO subset |
| `Foreign` | partial generated interface | supported scalar/pointer foreign type names plus `StablePtr` and manual `ForeignPtr` ownership APIs |
| `Foreign.C` | partial generated interface | `CString`, `CWString`, and supported `Foreign.C.Types` type names |
| `Foreign.C.String` | partial generated interface | `CString` and `CWString` type names |
| `Foreign.C.Types` | partial generated interface | supported C scalar type names used by FFI typechecking and native ABI lowering |
| `Foreign.ForeignPtr` | partial generated interface | `ForeignPtr`, `newForeignPtr`, `newForeignPtr_`, `addForeignPtrFinalizer`, `finalizeForeignPtr`, `withForeignPtr`, and `touchForeignPtr` |
| `Foreign.Ptr` | partial generated interface | `Ptr` and `FunPtr` |
| `Foreign.StablePtr` | partial generated interface | `StablePtr`, `newStablePtr`, `deRefStablePtr`, `freeStablePtr`, `castStablePtrToPtr`, and `castPtrToStablePtr` |

The generated interfaces reuse the same external names as the corresponding
`Prelude` surface where names overlap. That keeps cumulative imports such as
`import Prelude (map)` plus `import Data.List (map)` unambiguous when both
imports refer to the same implemented standard binding.

## Reserved Report Modules

These Haskell 2010 Libraries modules are reserved: they are documented as part
of the full target, but are not importable until implemented because their
exported value/type/class surface is not yet real in the compiler.

| Module | Status | Owner task |
| --- | --- | --- |
| `Data.Array` | reserved | `LIB-005` |
| `Data.Bits` | reserved | `LIB-006` |
| `Data.Char` | reserved | `LIB-004` |
| `Data.Complex` | reserved | `LIB-008` |
| `Data.Ix` | reserved | `LIB-005` |
| `Data.Ratio` | reserved | `LIB-007` |
| `Foreign.C.Error` | reserved | `FFI-013` |
| `Foreign.Marshal` | reserved | `FFI-013` |
| `Foreign.Marshal.Alloc` | reserved | `FFI-013` |
| `Foreign.Marshal.Array` | reserved | `FFI-013` |
| `Foreign.Marshal.Error` | reserved | `FFI-013` |
| `Foreign.Marshal.Utils` | reserved | `FFI-013` |
| `Foreign.Storable` | reserved | `FFI-013` |
| `Numeric` | reserved | `LIB-010` |
| `System.Environment` | reserved | `LIB-011` |
| `System.Exit` | reserved | `LIB-011` |

`TEST-CONF-015` completed the Report-wide reconciliation for this table. Each
reserved module and each partial generated interface now points to implemented
support with fixtures or to a narrower numbered tracker item before the
compiler claims more standard-library conformance.

## Instance Boundary

`interfaceInstances` is part of `ModuleInterface` and is populated from renamed
source `instance` declarations. Generated standard-library interfaces still
leave it empty. Built-in dictionaries and standard instances are generated by
the typechecker/runtime path, not by module-interface instance imports. This
keeps the module boundary honest while leaving space for future module-owned
standard instances if the implementation moves in that direction.

## Non-Goals

- No package database or package search path behavior is added here.
- No reserved Report module is made importable as an empty or fake module.
- No additional values/classes/functions are claimed solely by layout work.
- Generated standard-library instances remain owned by the typechecker/runtime
  implementation for now.

References:

- Haskell 2010 Report, Section 5.6, Standard Prelude:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch5.html>
- Haskell 2010 Report, Chapter 9, Standard Prelude:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch9.html>
- Haskell 2010 Libraries contents:
  <https://www.haskell.org/onlinereport/haskell2010/haskellli1.html>
