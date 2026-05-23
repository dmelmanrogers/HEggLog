# Haskell 2010 Standard Library Layout

This document records the compiler boundary for Haskell 2010 standard-library
modules. The Haskell 2010 Report treats `Prelude` as a distinguished module
that is imported by default, while still being an ordinary module for import
filtering and qualification. The Libraries Report also defines a fixed module
surface outside `Prelude`; the compiler exposes only modules whose exported
names have real parser, renamer, typechecker, Core/STG, and native support.

## Implemented Boundary

`Haskell2010.StandardLibrary` owns every implemented standard-library module
boundary. Generated interfaces and source-backed virtual modules both flow
through the normal module graph and renamer; the renamer consumes their
interfaces through `ModuleInterface`, the same data model used by source
modules:

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
| `Control.Monad` | implemented for supported monads | `Functor(fmap)`, `Monad(..)`, `MonadPlus(..)`, and the Haskell 2010 monadic combinator surface (`mapM`, `mapM_`, `forM`, `forM_`, `sequence`, `sequence_`, `(=<<)`, `(>=>)`, `(<=<)`, `forever`, `void`, `join`, `msum`, `filterM`, `mapAndUnzipM`, `zipWithM`, `zipWithM_`, `foldM`, `foldM_`, `replicateM`, `replicateM_`, `guard`, `when`, `unless`, `liftM` through `liftM5`, and `ap`) for the supported `IO`, `Maybe`, and list instances |
| `Data.Array` | source-backed native module | `Array`, immutable non-strict array construction/access/update functions (`array`, `listArray`, `accumArray`, `(!)`, `bounds`, `indices`, `elems`, `assocs`, `(//)`, `accum`, and `ixmap`), `Data.Ix` re-export, `!`/`//` fixities, and `Functor`/`Eq`/`Ord`/`Show`/`Read` instances for supported element types |
| `Data.Bits` | generated class interface plus native integral dictionaries | `Bits(..)` with Haskell 2010 method exports and fixities, a `Num` superclass edge, `Bits Int` plus fixed-width `Int*`/`Word*` instances, Core/STG interpreter support, and native LLVM lowering for bitwise operations, shifts, rotates, bit constructors, bit predicates, and Report-specified oversized shift behavior |
| `Data.Int` | generated native fixed-width module | `Int8`, `Int16`, `Int32`, and `Int64` have real modulo fixed-width representations, `Eq`/`Ord`/`Num`/`Real`/`Integral`/`Enum`/`Bounded`/`Ix`/`Bits`/`Show`/`Read` dictionaries, and native scalar FFI marshalling for Report basic foreign types; `Storable` remains owned by `FFI-013` |
| `Data.Char` | source-backed native module | `Char`, `String`, `GeneralCategory(..)`, classification predicates, ASCII digit predicates, `generalCategory`, case conversion, `digitToInt`, `intToDigit`, `ord`, `chr`, `showLitChar`, `lexLitChar`, and `readLitChar`; compact character-table policy covers the Haskell lexical ASCII surface, Latin-1, common Greek letters, combining marks, Unicode separators needed by `isSpace`, and the Euro sign |
| `Data.Complex` | source-backed native module | `Complex((:+))`, `realPart`, `imagPart`, `conjugate`, `mkPolar`, `cis`, `polar`, `magnitude`, `phase`, `:+` fixity, and generic `RealFloat a`-constrained `Eq`/`Num`/`Fractional`/`Floating`/`Show`/`Read` instances under `LIB-008` |
| `Data.Ix` | generated class interface plus native dictionaries | `Ix(range, index, inRange, rangeSize)`, scalar instances for `Int`, `Char`, `Bool`, `Ordering`, and `()`, structural tuple instances, and derived `Ix` for supported enumeration and single-constructor product data types |
| `Data.List` | source-backed native module | Haskell 2010 Report list API: shared Prelude list functions plus transformations, folds/scans, map accumulators, infinite-list producers, sublists, predicates, searches, indexing, zips/unzips, text helpers, set-like list operations, ordered-list helpers, `By` variants, and generic functions; `(++)`, `(!!)`, and `(\\)` fixities are imported |
| `Data.Maybe` | source-backed native module | `Maybe(..)`, `maybe`, `isJust`, `isNothing`, `fromJust`, `fromMaybe`, `listToMaybe`, `maybeToList`, `catMaybes`, and `mapMaybe` |
| `Data.Ratio` | generated interface plus native `Ratio Int` representation | `Ratio`, `Rational`, `(%)`, `numerator`, `denominator`, `approxRational`, `%` fixity, normalized `Rational = Ratio Int` over the current `Integer`-as-`Int` runtime, and built-in `Eq`/`Ord`/`Num`/`Real`/`Show`/`Read` dictionaries for that representation |
| `Data.Word` | generated native fixed-width module | `Word`, `Word8`, `Word16`, `Word32`, and `Word64` have real unsigned modulo representations, `Eq`/`Ord`/`Num`/`Real`/`Integral`/`Enum`/`Bounded`/`Ix`/`Bits`/`Show`/`Read` dictionaries, unsigned `Word64` rendering, and native scalar FFI marshalling for `Word8`/`Word16`/`Word32`/`Word64`; plain `Word` is deliberately not accepted as a Haskell 2010 basic FFI type, and `Storable` remains owned by `FFI-013` |
| `System.IO` | partial generated interface | `IO`, `Handle`, `FilePath`, `putStrLn`, `getLine`, and `print`; `LIB-012` owns handles, files, buffering, seek, and EOF-specific handle behavior |
| `System.IO.Error` | partial generated interface | `IOError`, `IOErrorType`, error-type constants, `userError`, `mkIOError`, `annotateIOError`, classifiers, accessors, `ioError`, `catch`, and `try`; `LIB-012` owns handle/file-backed error producers beyond the current line-oriented IO subset |
| `Foreign` | partial generated interface | supported scalar/floating/pointer foreign type names, pointer null/cast helpers, `StablePtr`, manual `ForeignPtr` ownership APIs, and implemented `Foreign.Marshal.Error`/`Foreign.Marshal.Utils` helpers |
| `Foreign.C` | partial generated interface | `CString`, `CStringLen`, `CWString`, `CWStringLen`, and supported `Foreign.C.Types` type names |
| `Foreign.C.String` | partial generated interface | `CString = Ptr CChar`, `CStringLen = (CString, Int)`, `CWString = Ptr CWchar`, and `CWStringLen = (CWString, Int)` type synonyms |
| `Foreign.C.Types` | partial generated interface | supported C scalar type names used by FFI typechecking and native ABI lowering, including `CFloat`/`CDouble` floating-point ABI values |
| `Foreign.ForeignPtr` | partial generated interface | `ForeignPtr`, `FinalizerPtr`, `FinalizerEnvPtr`, `newForeignPtr`, `newForeignPtr_`, `addForeignPtrFinalizer`, `finalizeForeignPtr`, `unsafeForeignPtrToPtr`, `withForeignPtr`, `touchForeignPtr`, and `castForeignPtr` |
| `Foreign.Marshal` | partial generated interface | implemented `Foreign.Marshal.Error` and `Foreign.Marshal.Utils` helper subset |
| `Foreign.Marshal.Error` | partial generated interface | `throwIf`, `throwIf_`, `throwIfNull`, and `void` |
| `Foreign.Marshal.Utils` | partial generated interface | `maybeNew`, `maybeWith`, and `maybePeek` |
| `Foreign.Ptr` | partial generated interface | `Ptr`, `FunPtr`, `nullPtr`, `castPtr`, `nullFunPtr`, `castFunPtr`, `castFunPtrToPtr`, and `castPtrToFunPtr` |
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
| `Foreign.C.Error` | reserved | `FFI-013` |
| `Foreign.Marshal.Alloc` | reserved | `FFI-013` |
| `Foreign.Marshal.Array` | reserved | `FFI-013` |
| `Foreign.Storable` | reserved | `FFI-013` |
| `Numeric` | reserved | `LIB-010` |
| `System.Environment` | reserved | `LIB-011` |
| `System.Exit` | reserved | `LIB-011` |

`LIB-002` moved `Data.List` from a generated subset to a source-backed virtual
standard-library module. The virtual module is parsed, renamed, typechecked,
lowered, and compiled by the same frontend/Core/STG/native path as user source,
which keeps the broad list API out of ad hoc compiler-internal Core builders
while preserving explicit import/export and fixity behavior.

`LIB-003` moved `Data.Maybe` from a constructor-only generated interface to a
source-backed virtual standard-library module. The virtual module re-exports
the built-in `Maybe` type and constructors and implements the Haskell 2010
helper functions in ordinary source so the same parser, renamer, typechecker,
Core/STG, and native paths validate the module.

`LIB-004` moved `Data.Char` from a reserved module to a source-backed virtual
standard-library module. The module owns `GeneralCategory(..)` and the
Report-shaped character classification, conversion, digit, ordinal, and
literal read/show helper surface. The compact table is intentionally explicit:
it covers the executable Haskell lexical ASCII/Latin-1 surface plus selected
validated Unicode ranges, and unlisted code points classify as `NotAssigned`
until a generated Unicode database table is introduced.

`LIB-005` moved `Data.Ix` and `Data.Array` out of the reserved set. `Data.Ix`
is represented as the built-in Report class plus generated/native dictionaries
for scalar, tuple, and derived instances. `Data.Array` is a source-backed
virtual module compiled through the normal frontend/Core/STG/native path, so
array construction, lookup, updates, accumulation, `ixmap`, and instances are
validated as ordinary standard-library code rather than as fake import names.

`LIB-007` moved `Data.Ratio` out of the reserved set. The module is importable
through a generated interface and its runtime representation is a real
`Ratio Int` constructor, not the old executable pair encoding. The boundary is
still explicit: generic `Ratio a`, arbitrary-precision `Integer`, and
floating/fractional integration remain in later numeric-library tasks.

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
- Haskell 2010 Libraries, `Data.List`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch20.html>
- Haskell 2010 Libraries, `Data.Maybe`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch21.html>
- Haskell 2010 Libraries, `Data.Char`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch16.html>
- Haskell 2010 Libraries, `Data.Array`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch14.html>
- Haskell 2010 Libraries, `Data.Ix`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch19.html>
- Haskell 2010 Libraries, `Data.Ratio`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch22.html>
