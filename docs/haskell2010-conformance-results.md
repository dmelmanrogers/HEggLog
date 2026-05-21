# Haskell 2010 Conformance Results

Date/time: 2026-05-20 23:36:36 UTC

Commit hash tested: 44dd0e5 with working-tree conformance-closure changes.

Primary conformance command run:

```bash
cabal test all --test-options='--hide-successes'
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
| Manifest conformance fixtures | 88 |
| Haskell source files in corpus | 95 |
| HUnit test cases executed | 114 |
| Native-success fixtures | 67 |
| Native-runtime-error fixtures | 2 |
| Compile-error fixtures | 14 |
| Unsupported-documented fixtures | 5 |
| Native subprocess compile/run checks | 95 |
| Failures | 0 |
| Errors | 0 |

Pass/fail summary: `haskell2010-conformance-test` passed. The current compiler
passes the documented executable-subset conformance cases. Full Haskell 2010
conformance remains incomplete, and unsupported features are represented as
explicit conformance cases rather than omitted.

## Category Summary

| Category | Manifest fixtures | Status |
| --- | ---: | --- |
| `adts` | 3 | representative native tests exist, including record labels/selectors |
| `declarations` | 4 | representative native tests exist |
| `egglog` | 1 | optimized/unoptimized native agreement covered |
| `expressions` | 10 | representative native tests exist |
| `ffi` | 5 | static ccall, pointer/address, dynamic/wrapper, foreign export, and StablePtr/ForeignPtr ownership native fixtures link C helpers and run in default and `--no-egglog` modes |
| `io` | 4 | current line-oriented stdin/stdout IO slice covered, including do-bind, explicit `(>>=)`, `getLine`, and explicit `fail` examples |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 6 | single-module, same-directory import, implicit/explicit/qualified Prelude import, and source-instance import/export tests exist |
| `negative` | 14 | compile-error diagnostics covered, including source-spanned type errors, module/import failures, Prelude visibility, duplicate built-in instances, and FFI shape/lifetime boundary failures |
| `patterns` | 2 | guards/as-patterns and irrefutable/lazy pattern representative native tests exist |
| `prelude` | 13 | list functions, append, class dictionaries, native Char runtime, `String = [Char]`, string native wet cases, broadened Show, Enum/Bounded, arithmetic sequences, and list comprehensions covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 8 | user dictionary, superclass/default method, synonym-normalized constraint, Monad IO/Maybe/list, explicit fail, derived Eq, derived Ord, and derived Show tests exist |
| `types` | 4 | polymorphism/defaulting/monomorphism/synonym representative native tests exist |
| `unsupported` | 5 | unsupported features documented by failing cases, including TC-016 `Read` |
