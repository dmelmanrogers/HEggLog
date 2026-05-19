# Haskell 2010 Conformance Results

Date/time: 2026-05-19 04:01:57 UTC

Commit hash tested: TYPE-016 working tree before final task commit. The final
commit for the task records the same source tree plus this results document.

Primary conformance command run:

```bash
cabal test haskell2010-conformance-test --test-options='--hide-successes'
```

Required task validation also passed:

```bash
cabal build all
cabal test hegglog-test --test-options='--hide-successes'
cabal test haskell2010-conformance-test --test-options='--hide-successes'
python3 scripts/validate-haskell2010-todo.py
git diff --check
./scripts/smoke-test.sh
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
| Manifest conformance fixtures | 50 |
| Haskell source files in corpus | 51 |
| HUnit test cases executed | 52 |
| Native-success fixtures | 36 |
| Native-runtime-error fixtures | 1 |
| Compile-error fixtures | 6 |
| Unsupported-documented fixtures | 7 |
| Native subprocess compile/run checks | 39 |
| Failures | 0 |
| Errors | 0 |

Pass/fail summary: `haskell2010-conformance-test` passed. The current compiler
passes the documented executable-subset conformance cases. Full Haskell 2010
conformance remains incomplete, and unsupported features are represented as
explicit conformance cases rather than omitted.

## Category Summary

| Category | Manifest fixtures | Status |
| --- | ---: | --- |
| `adts` | 2 | representative native tests exist |
| `declarations` | 4 | representative native tests exist |
| `egglog` | 1 | optimized/unoptimized native agreement covered |
| `expressions` | 10 | representative native tests exist |
| `io` | 1 | current output-only IO slice covered |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 2 | single-module and same-directory import tests exist |
| `negative` | 6 | compile-error diagnostics covered |
| `patterns` | 1 | guards/as-patterns representative native test exists |
| `prelude` | 2 | list functions and class dictionaries covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 2 | user dictionary and synonym-normalized constraint tests exist |
| `types` | 3 | polymorphism/defaulting/synonym representative native tests exist |
| `unsupported` | 7 | unsupported features documented by failing cases |
