# Haskell 2010 Conformance Results

Date/time: 2026-05-24 04:30:21 UTC

Code hash tested: source implementation in the MOD-003 import-search-path
working tree before final commit.

Primary conformance command run:

```bash
cabal test haskell2010-conformance-test
```

Required task validation also passed:

```bash
cabal build all
cabal check
cabal test hegglog-test
cabal test haskell2010-conformance-test
cabal test e2e-wet-test
jq empty docs/haskell2010-todo.json test/haskell2010/conformance/manifest.json
python3 scripts/validate-haskell2010-conformance.py
python3 scripts/validate-haskell2010-todo.py
git diff --check
```

Toolchain:

| Tool | Version |
| --- | --- |
| GHC | The Glorious Glasgow Haskell Compilation System, version 9.10.1 |
| Cabal | cabal-install version 3.12.1.0, Cabal library 3.12.1.0 |
| clang | Apple clang version 15.0.0 (clang-1500.3.9.4) |

Summary:

| Metric | Count |
| --- | ---: |
| Manifest conformance fixtures | 155 |
| Manifest source files in corpus | 155 |
| HUnit test cases executed | 233 |
| Native-success fixtures | 106 |
| Native-runtime-error fixtures | 15 |
| Compile-error fixtures | 28 |
| Unsupported-documented fixtures | 6 |
| Native subprocess compile/run checks | 199 |
| Failures | 0 |
| Errors | 0 |

Pass/fail summary: `haskell2010-conformance-test` passed. The current compiler
passes the documented executable-subset conformance cases. Full Haskell 2010
conformance remains incomplete, and unsupported features are represented as
explicit conformance cases rather than omitted.

LIB-001 through LIB-012 audit checkpoint: the implemented library tasks
`LIB-001` through `LIB-012` are covered by the tracker, matrix, manifest,
validators, and the full Cabal test suite. `LIB-011` is now covered by native
generated-module fixtures for `System.Environment` and `System.Exit`.
`System.Environment` exposes `getArgs`, `getProgName`, and `getEnv` against
native process arguments and environment variables, including catchable
`DoesNotExistError` failures for missing variables. `System.Exit` exposes
`ExitCode(ExitSuccess, ExitFailure)`, `exitWith`, `exitFailure`, and
`exitSuccess`; valid exit actions propagate as non-catchable process termination
with the requested process status, while the POSIX-prohibited `ExitFailure 0`
path is a catchable illegal-operation `IOError`.

LIB-012 is now covered by unit and conformance paths for the strict native
runtime model. `System.IO` exposes the Report handle/mode/buffering/seek/text
IO surface at the generated interface and typechecking boundaries; Core, STG,
native lowering, validators, and the optimizer all recognize the expanded
primitive set. Native conformance now includes `io.system-io`, which exercises
standard-handle buffering calls, `hPutStr`, `hPutChar`, `hPutStrLn`, `hPrint`,
`getLine`, `getContents`, `hIsEOF`, and `hShow` in default and `--no-egglog`
modes. File-backed handle state, real seek/position state, lazy semi-closed
`hGetContents`, and productive `fixIO` remain documented strict-runtime
deviations rather than unsupported imports.

FFI-011 is now covered by the conformance/native path. Header-qualified static
`ccall` imports preserve link metadata, C helper fixtures are linked through
the `hegglog compile --link-object` path, and the unit suite covers LLVM link
metadata comments plus missing link-input diagnostics.

FFI-012 is now covered by native unit and conformance paths. `freeHaskellFunPtr`
is imported through the generated `Foreign`/`Foreign.Ptr` surface, wrapper
slots are reclaimed after explicit release, double-free of a wrapper pointer is
idempotent, callback-after-free exits nonzero, and manual `ForeignPtr`
finalization remains explicit, idempotent, and reverse-order under the
process-lifetime runtime model. The new `ffi.wrapper-reclamation` and
`ffi.wrapper-after-free` fixtures run in default and `--no-egglog` modes.

TEST-CONF-014 source matrix closure is now validator-backed. The conformance
validator checks 37 declaration/expression/pattern closure rows, rejects fixture
paths not present in the manifest, and rejects any `declarations`,
`expressions`, or `patterns` manifest fixture omitted from the closure table.
It also requires the source-surface negative and unsupported fixtures introduced
for malformed where layout, misindented line-broken where keywords, duplicate
binders, impossible patterns, unsupported constraint positions, and FFI shape
boundaries to stay linked from the closure table.

SURFACE-002 is now covered by native and negative conformance fixtures:
`expressions.user-defined-operators` checks symbolic and backtick value
operators, local fixity, and Prelude-shadowing `(++)`;
`negative.constructor-operator-binding` rejects colon-prefixed constructor
operators in value-binding syntax.

SURFACE-003 is now covered by native and negative conformance fixtures:
`expressions.where-layout` checks report-shaped line-broken `where` groups on
function bindings and case alternatives; `negative.misindented-where-keyword`
rejects a line-broken `where` at the enclosing declaration column.

TC-031 is now covered by native, runtime-error, and negative conformance
fixtures. `typeclasses.derived-enum` checks generated `Enum` dictionaries for
nullary-constructor data declarations, declaration-order constructor indices,
`succ`/`pred`, `toEnum`/`fromEnum`, range methods, and source range syntax.
`typeclasses.derived-enum-runtime-error` checks bounds failure at runtime, and
`negative.derived-enum-field-constructor` rejects non-enumeration deriving.

TC-032 is now covered by native and negative conformance fixtures.
`typeclasses.derived-bounded` checks generated `Bounded` dictionaries for
all-nullary enumerations, single-constructor products, records, and newtypes,
including field-wise `minBound`/`maxBound` dictionaries. The negative
`derived-bounded-mixed-constructors` fixture rejects declarations that are
neither enumerations nor single-constructor shapes.

TC-033 is now covered by native and negative conformance fixtures.
`prelude.numeric-hierarchy` checks executable `Real Int` and `Integral Int`
dictionaries for `toRational`, `quot`, `rem`, `div`, `mod`, `quotRem`,
`divMod`, `toInteger`, and supported `Integer` default declarations in default
and `--no-egglog` modes. The negative `invalid-default-type` fixture rejects a
non-numeric default declaration with an explicit diagnostic.

TC-030 is now covered by native conformance fixtures. `prelude.read-standard`
checks `ReadS`, `readsPrec`, `readList`, `reads`, `read`, `lex`, `readParen`,
standard supported `Read` instances, partial-read behavior, and token-boundary
rejection. `typeclasses.derived-read` checks generated `Read` dictionaries for
nullary constructors, products, records, recursive data, newtypes, `String`
fields, list-backed contexts, and precedence-sensitive nested constructor
parsing in default and `--no-egglog` modes.

PRELUDE-009 is now covered by native conformance and e2e fixtures.
`prelude.foldl` checks generated `foldl` for left-to-right accumulator order,
polymorphic accumulator/list element types, empty-list behavior, and lazy
ignored accumulator arguments in default and `--no-egglog` modes.

PRELUDE-019 is now covered by native conformance and e2e fixtures.
`prelude.functions` checks generated `($)`, `(.)`, `flip`, `head`, `tail`,
`null`, `fst`, and `snd` through Core/STG/native execution, including function
composition/application, list selectors, pair selectors, list null checks, and
String output as `[Char]`. `prelude.head-empty` locks the partial-selector
boundary by requiring empty-list `head` to compile and fail at native runtime in
default and `--no-egglog` modes.

PRELUDE-020 is now covered by native conformance and e2e fixtures.
`modules.standard-library-modules` checks generated/importable interfaces for
`Data.List`, `Data.Maybe`, `Data.Char`, `Control.Monad`, and `System.IO` with explicit
import lists, `Functor(fmap)` and `Maybe(..)` child exports, imported fixities,
ordinary Prelude-backed semantics, and default plus `--no-egglog` native execution. The
unsupported package/database fixture imports unimplemented `Data.Set` so
unimplemented standard-library modules continue to fail explicitly.

MOD-003 is now covered by unit, conformance, and native e2e fixtures.
`modules.import-search-path` compiles a root `Main` module whose dependency is
outside the root module directory and supplied through an ordered `-i` source
root. The native default/`--no-egglog` and emit-LLVM wet paths also pass the
same cross-directory source import through the CLI. Package databases,
interface-file roots, and unimplemented library modules remain documented
separately from source import path support.

LIB-002 is now covered by native conformance and e2e fixtures.
`modules.data-list` compiles a source-backed virtual `Data.List` module through
the ordinary module graph, parser, renamer, typechecker, Core/STG lowering, and
native backend. The fixture exercises transformations, folds/scans, map
accumulators, sublists, searches, indexing, zips/unzips, text helpers, set-like
operations, `By` variants, ordered-list helpers, and generic functions in
default, `--no-egglog`, and emit-LLVM modes. `modules.data-list-partial` locks
empty-list partial selector behavior with a native runtime-error case.

LIB-003 is now covered by native conformance and e2e fixtures.
`modules.data-maybe` compiles a source-backed virtual `Data.Maybe` module
through the ordinary module graph, parser, renamer, typechecker, Core/STG
lowering, and native backend. The fixture exercises `Maybe(..)`, `maybe`,
`isJust`, `isNothing`, `fromJust`, `fromMaybe`, `maybeToList`, `listToMaybe`,
`catMaybes`, and `mapMaybe` in default, `--no-egglog`, and emit-LLVM modes.
`modules.data-maybe-partial` locks `fromJust Nothing` as a native runtime-error
case.

LIB-004 is now covered by native conformance and e2e fixtures.
`modules.data-char` compiles a source-backed virtual `Data.Char` module through
the ordinary module graph, parser, renamer, typechecker, Core/STG lowering, and
native backend. The fixture exercises `GeneralCategory(..)`, classification
predicates, case conversion, digit conversion, `ord`, `chr`, `showLitChar`,
`lexLitChar`, and `readLitChar` in default, `--no-egglog`, and emit-LLVM modes.
`modules.data-char-partial` locks invalid `digitToInt` input as a native
runtime-error case. The implementation documents its compact character-table
policy instead of claiming an untested full Unicode database.
`modules.data-bits` now positively checks the generated `Data.Bits` module,
the Haskell 2010 `Bits` method surface, `Bits Int`, checked shift/rotate
semantics, and emit-LLVM lowering. `modules.data-bits-negative-shift-partial`
locks directional negative bit counts as native runtime errors.

LIB-007 is now covered by native conformance and e2e fixtures.
`modules.data-ratio` checks the generated `Data.Ratio` module, `Ratio` and
`Rational` imports, normalized `(%)`, `numerator`, `denominator`,
`approxRational`, Prelude `toRational`, and built-in `Ratio Int`
`Eq`/`Ord`/`Num`/`Real`/`Show`/`Read` behavior in default, `--no-egglog`, and
emit-LLVM modes. `modules.data-ratio-zero-denominator-partial` locks zero
denominator handling as a native runtime-error case.

TEST-CONF-015 is now validator-backed. The conformance matrix contains a
Library Conformance Closure table covering Chapter 9 Prelude areas and every
Part II Libraries module group. The conformance validator now checks all 18
library closure rows, verifies that each row cites manifest-backed fixtures and
numbered remaining tracker tasks, and requires the library closure fixtures to
stay represented in the matrix. Reserved Report modules now have explicit
unsupported-documented fixtures for `Foreign.C.Error`,
`Foreign.Marshal.Alloc`/array allocation, and `Foreign.Storable`.
`System.Environment`, `System.Exit`, and `Numeric` have moved from that
reserved set to native/generated or source-backed fixtures.
`modules.data-complex` and `prelude.floating-numeric` now positively check
the LIB-008 floating numeric tower and importable `Data.Complex` module in
default and `--no-egglog` native modes.
`io.io-error` now positively checks the generated `System.IO.Error` surface for
recoverable `IOError` behavior, and `modules.standard-library-scalar-types`
positively checks the generated `Data.Int`, `Data.Word`, and `Foreign.C.Types`
scalar type-name surface.

LIB-009 is now covered by native conformance fixtures. `modules.data-int-word`
checks real fixed-width `Data.Int`/`Data.Word` runtime behavior across modulo
overflow, signed and unsigned bounds, unsigned `Word64` rendering, quotient and
remainder, `Bits`, oversized signed/unsigned shifts, rotates, `Enum`, `Ix`,
`Read`, and `Show` in default and `--no-egglog` modes.
`ffi.fixed-width-scalars` checks static C marshalling for `Int8`, `Word8`, and
`Word64`, while `negative.ffi-word-not-basic` keeps plain `Word` rejected as a
non-basic Haskell 2010 FFI type.

`ffi.foreign-library-surface` positively checks the implemented `Foreign.Ptr`, `Foreign.ForeignPtr`,
`Foreign.Marshal.Error`, and `Foreign.Marshal.Utils` surface in native default
and `--no-egglog` modes. `ffi.floating-ccall` positively checks
`Float`/`Double`/`CFloat`/`CDouble` FFI marshalling across static calls,
dynamic calls, wrapper callbacks, and foreign export entrypoints.

## Category Summary

| Category | Manifest fixtures | Status |
| --- | ---: | --- |
| `adts` | 5 | representative native tests exist, including record labels/selectors and record updates |
| `declarations` | 6 | representative native tests exist |
| `egglog` | 1 | optimized/unoptimized native agreement covered |
| `expressions` | 13 | representative native tests exist, including user-defined infix operators and line-broken `where` layout |
| `ffi` | 10 | static ccall, fixed-width scalar ccall, floating ccall, pointer/address, dynamic/wrapper, wrapper reclamation/after-free, foreign export, StablePtr/ForeignPtr ownership, and broader Foreign library surface native fixtures link C helpers and run in default and `--no-egglog` modes |
| `io` | 6 | line-oriented stdin/stdout IO, expanded `System.IO` standard-handle text behavior, and recoverable IO-error behavior covered, including do-bind, explicit `(>>=)`, `getLine`, `getContents`, `hPutStr`/`hPutChar`/`hPutStrLn`, `hPrint`, `hShow`, explicit `fail`, `ioError`, `catch`, `try`, and System.IO.Error examples |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 32 | single-module, same-directory import, ordered `-i` source import paths, implicit/explicit/qualified Prelude import, source-instance import/export, generated standard-library module imports, source-backed `Data.List`/`Data.Maybe`/`Data.Char`/`Data.Complex`, `Data.Array`, `Data.Ix`, `Data.Bits`, `Data.Ratio`, scalar standard-library imports, fixed-width `Data.Int`/`Data.Word`, `System.Environment`/`System.Exit`, and partial runtime-error coverage exist |
| `negative` | 28 | compile-error diagnostics covered, including source-spanned type errors, module/import failures, Prelude visibility, malformed where layout, misindented where keywords, duplicate source binders, invalid pattern bindings, constructor-operator binding misuse, impossible case patterns, invalid record updates, invalid default declarations, invalid derived Enum and Bounded declarations, duplicate built-in instances, and FFI shape/lifetime boundary failures |
| `patterns` | 3 | guards/as-patterns, unit/wildcard, and irrefutable/lazy pattern representative native tests exist |
| `prelude` | 19 | list functions, append, foldl, function/selector completion, class dictionaries, native Char runtime, `String = [Char]`, string native wet cases, broadened Show, Report-shaped Read, Real/Integral numeric hierarchy, Enum/Bounded, arithmetic sequences, list comprehensions, and floating numeric Prelude coverage covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 13 | user dictionary, instance context, superclass/default method, synonym-normalized constraint, Monad IO/Maybe/list, explicit fail, derived Eq, derived Ord, derived Show, derived Read, derived Enum, and derived Bounded tests exist |
| `types` | 4 | polymorphism/defaulting/monomorphism/synonym representative native tests exist |
| `unsupported` | 6 | unsupported features documented by failing cases, including constrained expression signatures, package databases/unimplemented library imports, method-specific constraints, and reserved Report library modules |
