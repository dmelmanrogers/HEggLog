# Haskell 2010 Conformance Results

Date/time: 2026-05-23 04:38:52 UTC

Code hash tested: working tree for the LIB-003 update, based on `030bf89`.

Primary conformance command run:

```bash
cabal test haskell2010-conformance-test --test-options='--hide-successes'
```

Required task validation also passed:

```bash
cabal build all
cabal test hegglog-test --test-options='--hide-successes'
cabal test haskell2010-conformance-test --test-options='--hide-successes'
cabal test e2e-wet-test --test-options='--hide-successes'
cabal check
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
| Manifest conformance fixtures | 143 |
| Haskell source files in corpus | 150 |
| HUnit test cases executed | 198 |
| Native-success fixtures | 90 |
| Native-runtime-error fixtures | 8 |
| Compile-error fixtures | 28 |
| Unsupported-documented fixtures | 17 |
| Native subprocess compile/run checks | 153 |
| Failures | 0 |
| Errors | 0 |

Pass/fail summary: `haskell2010-conformance-test` passed. The current compiler
passes the documented executable-subset conformance cases. Full Haskell 2010
conformance remains incomplete, and unsupported features are represented as
explicit conformance cases rather than omitted.

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
`Data.List`, `Data.Maybe`, `Control.Monad`, and `System.IO` with explicit
import lists, `Functor(fmap)` and `Maybe(..)` child exports, imported fixities,
ordinary Prelude-backed semantics, and default plus `--no-egglog` native execution. The
unsupported package/search-path fixture now imports reserved `Data.Char` so
unimplemented standard-library modules continue to fail explicitly.

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

TEST-CONF-015 is now validator-backed. The conformance matrix contains a
Library Conformance Closure table covering Chapter 9 Prelude areas and every
Part II Libraries module group. The conformance validator now checks all 18
library closure rows, verifies that each row cites manifest-backed fixtures and
numbered remaining tracker tasks, and requires the library closure fixtures to
stay represented in the matrix. Reserved Report modules now have explicit
unsupported-documented fixtures for `Data.Array`, `Data.Bits`, `Data.Char`,
`Data.Complex`, `Data.Ix`, `Data.Ratio`, `Numeric`, `System.Environment`,
`System.Exit`, `Foreign.C.Error`, `Foreign.Marshal.Alloc`/array allocation,
and `Foreign.Storable`.
`io.io-error` now positively checks the generated `System.IO.Error` surface for
recoverable `IOError` behavior, and `modules.standard-library-scalar-types`
positively checks the current generated `Data.Int`, `Data.Word`, and
`Foreign.C.Types` type-name surface. `ffi.foreign-library-surface` positively
checks the implemented `Foreign.Ptr`, `Foreign.ForeignPtr`,
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
| `ffi` | 9 | static ccall, floating ccall, pointer/address, dynamic/wrapper, wrapper reclamation/after-free, foreign export, StablePtr/ForeignPtr ownership, and broader Foreign library surface native fixtures link C helpers and run in default and `--no-egglog` modes |
| `io` | 5 | current line-oriented stdin/stdout IO slice and recoverable IO-error behavior covered, including do-bind, explicit `(>>=)`, `getLine`, explicit `fail`, `ioError`, `catch`, `try`, and System.IO.Error examples |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 13 | single-module, same-directory import, implicit/explicit/qualified Prelude import, source-instance import/export, generated standard-library module imports, source-backed `Data.List`/`Data.Maybe`, scalar standard-library type-name imports, and Data.List/Data.Maybe partial runtime-error coverage exist |
| `negative` | 28 | compile-error diagnostics covered, including source-spanned type errors, module/import failures, Prelude visibility, malformed where layout, misindented where keywords, duplicate source binders, invalid pattern bindings, constructor-operator binding misuse, impossible case patterns, invalid record updates, invalid default declarations, invalid derived Enum and Bounded declarations, duplicate built-in instances, and FFI shape/lifetime boundary failures |
| `patterns` | 3 | guards/as-patterns, unit/wildcard, and irrefutable/lazy pattern representative native tests exist |
| `prelude` | 18 | list functions, append, foldl, function/selector completion, class dictionaries, native Char runtime, `String = [Char]`, string native wet cases, broadened Show, Report-shaped Read, Real/Integral numeric hierarchy, Enum/Bounded, arithmetic sequences, and list comprehensions covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 12 | user dictionary, superclass/default method, synonym-normalized constraint, Monad IO/Maybe/list, explicit fail, derived Eq, derived Ord, derived Show, derived Read, derived Enum, and derived Bounded tests exist |
| `types` | 4 | polymorphism/defaulting/monomorphism/synonym representative native tests exist |
| `unsupported` | 17 | unsupported features documented by failing cases, including constrained expression signatures, handle IO, package/module search paths, and reserved Report library modules |
