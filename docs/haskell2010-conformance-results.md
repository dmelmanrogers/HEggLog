# Haskell 2010 Conformance Results

Date/time: 2026-05-18 13:45:49 UTC

Commit hash tested: `4d4a715` plus the Haskell 2010 conformance baseline
working tree added by this task. The final commit for the task records the same
source tree plus this results document.

Primary conformance command run:

```bash
cabal test haskell2010-conformance-test --test-options='--hide-successes'
```

Required task validation also passed:

```bash
cabal build all
cabal test all --test-options='--hide-successes'
cabal check
git diff --check
scripts/e2e-wet-test.sh
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
| Manifest conformance fixtures | 46 |
| Haskell source files in corpus | 47 |
| HUnit test cases executed | 47 |
| Native-success fixtures | 32 |
| Native-runtime-error fixtures | 1 |
| Compile-error fixtures | 5 |
| Unsupported-documented fixtures | 8 |
| Native subprocess compile/run checks | 34 |
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
| `declarations` | 3 | representative native tests exist |
| `egglog` | 1 | optimized/unoptimized native agreement covered |
| `expressions` | 9 | representative native tests exist |
| `io` | 1 | current output-only IO slice covered |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 2 | single-module and same-directory import tests exist |
| `negative` | 5 | compile-error diagnostics covered |
| `patterns` | 1 | guards/as-patterns representative native test exists |
| `prelude` | 2 | list functions and class dictionaries covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 1 | user dictionary representative native test exists |
| `types` | 2 | polymorphism/defaulting representative native tests exist |
| `unsupported` | 8 | unsupported features documented by failing cases |
