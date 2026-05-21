# Haskell 2010 Conformance Results

Date/time: 2026-05-21 07:44:13 UTC

Commit hash tested: working tree with PRELUDE-020 standard-library module expansion changes.

Primary conformance command run:

```bash
cabal test haskell2010-conformance-test
```

Required task validation also passed:

```bash
cabal build all
cabal test hegglog-test --test-options='--hide-successes'
cabal test haskell2010-conformance-test --test-options='--hide-successes'
cabal test all --test-options='--hide-successes'
cabal check
python3 scripts/validate-haskell2010-conformance.py
python3 scripts/validate-haskell2010-todo.py
python3 -m json.tool docs/haskell2010-todo.json
python3 -m json.tool test/haskell2010/conformance/manifest.json
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
| Manifest conformance fixtures | 118 |
| Haskell source files in corpus | 125 |
| HUnit test cases executed | 160 |
| Native-success fixtures | 80 |
| Native-runtime-error fixtures | 5 |
| Compile-error fixtures | 27 |
| Unsupported-documented fixtures | 6 |
| Native subprocess compile/run checks | 127 |
| Failures | 0 |
| Errors | 0 |

Pass/fail summary: `haskell2010-conformance-test` passed. The current compiler
passes the documented executable-subset conformance cases. Full Haskell 2010
conformance remains incomplete, and unsupported features are represented as
explicit conformance cases rather than omitted.

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
import lists, `Maybe(..)` child exports, imported fixities, ordinary
Prelude-backed semantics, and default plus `--no-egglog` native execution. The
unsupported package/search-path fixture now imports reserved `Data.Char` so
unimplemented standard-library modules continue to fail explicitly.

## Category Summary

| Category | Manifest fixtures | Status |
| --- | ---: | --- |
| `adts` | 5 | representative native tests exist, including record labels/selectors and record updates |
| `declarations` | 6 | representative native tests exist |
| `egglog` | 1 | optimized/unoptimized native agreement covered |
| `expressions` | 13 | representative native tests exist, including user-defined infix operators and line-broken `where` layout |
| `ffi` | 5 | static ccall, pointer/address, dynamic/wrapper, foreign export, and StablePtr/ForeignPtr ownership native fixtures link C helpers and run in default and `--no-egglog` modes |
| `io` | 4 | current line-oriented stdin/stdout IO slice covered, including do-bind, explicit `(>>=)`, `getLine`, and explicit `fail` examples |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 7 | single-module, same-directory import, implicit/explicit/qualified Prelude import, source-instance import/export, and generated standard-library module imports exist |
| `negative` | 27 | compile-error diagnostics covered, including source-spanned type errors, module/import failures, Prelude visibility, malformed where layout, misindented where keywords, duplicate source binders, invalid pattern bindings, constructor-operator binding misuse, impossible case patterns, invalid record updates, invalid default declarations, invalid derived Enum and Bounded declarations, duplicate built-in instances, and FFI shape/lifetime boundary failures |
| `patterns` | 3 | guards/as-patterns, unit/wildcard, and irrefutable/lazy pattern representative native tests exist |
| `prelude` | 17 | list functions, append, foldl, function/selector completion, class dictionaries, native Char runtime, `String = [Char]`, string native wet cases, broadened Show, Real/Integral numeric hierarchy, Enum/Bounded, arithmetic sequences, and list comprehensions covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 11 | user dictionary, superclass/default method, synonym-normalized constraint, Monad IO/Maybe/list, explicit fail, derived Eq, derived Ord, derived Show, derived Enum, and derived Bounded tests exist |
| `types` | 4 | polymorphism/defaulting/monomorphism/synonym representative native tests exist |
| `unsupported` | 6 | unsupported features documented by failing cases, including TC-016 `Read` and constrained expression signatures |
