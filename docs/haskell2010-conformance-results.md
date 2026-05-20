# Haskell 2010 Conformance Results

Date/time: 2026-05-20 04:30:36 UTC

Commit hash tested: TC-016 working tree before final task commit.
The final commit for the task records the same source tree plus this results
document.

Primary conformance command run:

```bash
cabal test all --test-options='--hide-successes'
```

Required task validation also passed:

```bash
cabal build all
! cabal run hegglog -- compile test/haskell2010/conformance/unsupported/read-class.hs --emit-llvm -o .context/read-class.ll
cabal test all --test-options='--hide-successes'
cabal check
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
| Manifest conformance fixtures | 64 |
| Haskell source files in corpus | 65 |
| HUnit test cases executed | 77 |
| Native-success fixtures | 51 |
| Native-runtime-error fixtures | 1 |
| Compile-error fixtures | 6 |
| Unsupported-documented fixtures | 6 |
| Native subprocess compile/run checks | 65 |
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
| `io` | 2 | current output-only IO slice covered, including do-bind and explicit `(>>=)` examples |
| `laziness` | 3 | lazy success and forced runtime error covered |
| `lexical-layout` | 3 | representative layout tests exist |
| `lists-tuples` | 2 | representative native tests exist |
| `modules` | 2 | single-module and same-directory import tests exist |
| `negative` | 6 | compile-error diagnostics covered, including a source-spanned type error |
| `patterns` | 2 | guards/as-patterns and irrefutable/lazy pattern representative native tests exist |
| `prelude` | 12 | list functions, class dictionaries, native Char runtime, `String = [Char]`, string native wet cases, broadened Show, Enum/Bounded, arithmetic sequences, and list comprehensions covered |
| `recursion` | 1 | top-level recursion representative native test exists |
| `typeclasses` | 3 | user dictionary, superclass/default method, and synonym-normalized constraint tests exist |
| `types` | 4 | polymorphism/defaulting/monomorphism/synonym representative native tests exist |
| `unsupported` | 6 | unsupported features documented by failing cases, including TC-016 `Read` |
