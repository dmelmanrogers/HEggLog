# End-to-End Wet Test Results

Recorded for the mandatory wet-test suite after PRELUDE-DATA-012 string literal
native wet-test expansion. The suite covers the
existing `.hg` native compiler baseline and Haskell 2010 executable-subset
`.hs` programs that compile to native executables, compare lazy runtime
behavior, and run both default Egglog and `--no-egglog` modes for Haskell 2010
optimizer coverage.

Run metadata:

- Date/time: `2026-05-20 01:46:13 UTC`
- OS: `macOS 15.7.3 24G419`, Darwin `24.6.0`, `arm64`
- GHC: `9.10.1`
- Cabal: `3.12.1.0`
- clang: `Apple clang version 15.0.0 (clang-1500.3.9.4)`
- Command: `cabal test e2e-wet-test`

Summary:

- HUnit checks: 132
- Source files: 55
- Successful source cases: 44
- Runtime-error source cases: 7
- Compile-error source cases: 3
- Native compile/run checks: 96
- Default Egglog native checks: 54
- `--no-egglog` native checks: 42
- Emit-LLVM checks: 24
- Report/interpreter comparisons: 12
- Failures: 0

PRELUDE-DATA-012 adds dedicated Haskell 2010 native cases for direct source
string output, list operations over strings, `putStrLn` over built-in `show`
results, explicit `Char` cons patterns, and string literal patterns. The
fixtures run in both default and `--no-egglog` modes and all three new e2e
programs also emit LLVM that is compiled through clang.

## Case Table

| Name | Source path | Category | Mode | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- | --- |
| arithmetic | `test/e2e/programs/arithmetic.hg` | success | native/default | `14` | stdout `14`, stderr empty, exit 0 | pass |
| arithmetic | `test/e2e/programs/arithmetic.hg` | success | native/no-egglog | `14` | stdout `14`, stderr empty, exit 0 | pass |
| arithmetic | `test/e2e/programs/arithmetic.hg` | success | emit-llvm/default | `14` | LLVM compiled through clang, stdout `14`, stderr empty, exit 0 | pass |
| arithmetic | `test/e2e/programs/arithmetic.hg` | success | report | `14` | `Result: 14` | pass |
| subtraction | `test/e2e/programs/subtraction.hg` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| subtraction | `test/e2e/programs/subtraction.hg` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| subtraction | `test/e2e/programs/subtraction.hg` | success | report | `7` | `Result: 7` | pass |
| division | `test/e2e/programs/division.hg` | success | native/default | `5` | stdout `5`, stderr empty, exit 0 | pass |
| division | `test/e2e/programs/division.hg` | success | native/no-egglog | `5` | stdout `5`, stderr empty, exit 0 | pass |
| division | `test/e2e/programs/division.hg` | success | emit-llvm/default | `5` | LLVM compiled through clang, stdout `5`, stderr empty, exit 0 | pass |
| division | `test/e2e/programs/division.hg` | success | report | `5` | `Result: 5` | pass |
| negative-quotient | `test/e2e/programs/negative-quotient.hg` | success | native/default | `-2` | stdout `-2`, stderr empty, exit 0 | pass |
| negative-quotient | `test/e2e/programs/negative-quotient.hg` | success | native/no-egglog | `-2` | stdout `-2`, stderr empty, exit 0 | pass |
| negative-quotient | `test/e2e/programs/negative-quotient.hg` | success | report | `-2` | `Result: -2` | pass |
| if-comparison | `test/e2e/programs/if-comparison.hg` | success | native/default | `6` | stdout `6`, stderr empty, exit 0 | pass |
| if-comparison | `test/e2e/programs/if-comparison.hg` | success | emit-llvm/default | `6` | LLVM compiled through clang, stdout `6`, stderr empty, exit 0 | pass |
| if-comparison | `test/e2e/programs/if-comparison.hg` | success | report | `6` | `Result: 6` | pass |
| bool-root | `test/e2e/programs/bool-root.hg` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| bool-root | `test/e2e/programs/bool-root.hg` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| bool-root | `test/e2e/programs/bool-root.hg` | success | emit-llvm/default | `1` | LLVM compiled through clang, stdout `1`, stderr empty, exit 0 | pass |
| bool-root | `test/e2e/programs/bool-root.hg` | success | report | `1` | `Result: 1` | pass |
| top-level-function | `test/e2e/programs/top-level-function.hg` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| top-level-function | `test/e2e/programs/top-level-function.hg` | success | report | `7` | `Result: 7` | pass |
| noncapturing-lambda | `test/e2e/programs/noncapturing-lambda.hg` | success | native/default | `42` | stdout `42`, stderr empty, exit 0 | pass |
| noncapturing-lambda | `test/e2e/programs/noncapturing-lambda.hg` | success | report | `42` | `Result: 42` | pass |
| capturing-closure | `test/e2e/programs/capturing-closure.hg` | success | native/default | `42` | stdout `42`, stderr empty, exit 0 | pass |
| capturing-closure | `test/e2e/programs/capturing-closure.hg` | success | emit-llvm/default | `42` | LLVM compiled through clang, stdout `42`, stderr empty, exit 0 | pass |
| capturing-closure | `test/e2e/programs/capturing-closure.hg` | success | report | `42` | `Result: 42` | pass |
| higher-order | `test/e2e/programs/higher-order.hg` | success | native/default | `42` | stdout `42`, stderr empty, exit 0 | pass |
| higher-order | `test/e2e/programs/higher-order.hg` | success | report | `42` | `Result: 42` | pass |
| egglog-beneficial | `test/e2e/programs/egglog-beneficial.hg` | success | native/default | `14` | stdout `14`, stderr empty, exit 0 | pass |
| egglog-beneficial | `test/e2e/programs/egglog-beneficial.hg` | success | native/no-egglog | `14` | stdout `14`, stderr empty, exit 0 | pass |
| egglog-beneficial | `test/e2e/programs/egglog-beneficial.hg` | success | report | `14` | `Result: 14` | pass |
| boolean-reasoning | `test/e2e/programs/boolean-reasoning.hg` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| boolean-reasoning | `test/e2e/programs/boolean-reasoning.hg` | success | report | `1` | `Result: 1` | pass |
| haskell2010-arithmetic | `test/e2e/programs/haskell2010/arithmetic.hs` | success | native/default | `9` | stdout `9`, stderr empty, exit 0 | pass |
| haskell2010-arithmetic | `test/e2e/programs/haskell2010/arithmetic.hs` | success | native/no-egglog | `9` | stdout `9`, stderr empty, exit 0 | pass |
| haskell2010-arithmetic | `test/e2e/programs/haskell2010/arithmetic.hs` | success | emit-llvm/default | `9` | LLVM compiled through clang, stdout `9`, stderr empty, exit 0 | pass |
| haskell2010-lazy-let | `test/e2e/programs/haskell2010/lazy-let.hs` | success | native/default | `5` | stdout `5`, stderr empty, exit 0 | pass |
| haskell2010-lazy-let | `test/e2e/programs/haskell2010/lazy-let.hs` | success | native/no-egglog | `5` | stdout `5`, stderr empty, exit 0 | pass |
| haskell2010-lazy-argument | `test/e2e/programs/haskell2010/lazy-argument.hs` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-lazy-argument | `test/e2e/programs/haskell2010/lazy-argument.hs` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-lazy-argument | `test/e2e/programs/haskell2010/lazy-argument.hs` | success | emit-llvm/default | `1` | LLVM compiled through clang, stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-partial-application | `test/e2e/programs/haskell2010/partial-application.hs` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-partial-application | `test/e2e/programs/haskell2010/partial-application.hs` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-bool-case | `test/e2e/programs/haskell2010/bool-case.hs` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-bool-case | `test/e2e/programs/haskell2010/bool-case.hs` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-tuple-case | `test/e2e/programs/haskell2010/tuple-case.hs` | success | native/default | `3` | stdout `3`, stderr empty, exit 0 | pass |
| haskell2010-tuple-case | `test/e2e/programs/haskell2010/tuple-case.hs` | success | native/no-egglog | `3` | stdout `3`, stderr empty, exit 0 | pass |
| haskell2010-prelude-lists | `test/e2e/programs/haskell2010/prelude-lists.hs` | success | native/default | `321` | stdout `321`, stderr empty, exit 0 | pass |
| haskell2010-prelude-lists | `test/e2e/programs/haskell2010/prelude-lists.hs` | success | native/no-egglog | `321` | stdout `321`, stderr empty, exit 0 | pass |
| haskell2010-prelude-lists | `test/e2e/programs/haskell2010/prelude-lists.hs` | success | emit-llvm/default | `321` | LLVM compiled through clang, stdout `321`, stderr empty, exit 0 | pass |
| haskell2010-prelude-maybe-ordering | `test/e2e/programs/haskell2010/prelude-maybe-ordering.hs` | success | native/default | `5` | stdout `5`, stderr empty, exit 0 | pass |
| haskell2010-prelude-maybe-ordering | `test/e2e/programs/haskell2010/prelude-maybe-ordering.hs` | success | native/no-egglog | `5` | stdout `5`, stderr empty, exit 0 | pass |
| haskell2010-short-circuit | `test/e2e/programs/haskell2010/short-circuit.hs` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-short-circuit | `test/e2e/programs/haskell2010/short-circuit.hs` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-guarded-self-recursion | `test/e2e/programs/haskell2010/guarded-self-recursion.hs` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-guarded-self-recursion | `test/e2e/programs/haskell2010/guarded-self-recursion.hs` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-local-factorial | `test/e2e/programs/haskell2010/local-factorial.hs` | success | native/default | `120` | stdout `120`, stderr empty, exit 0 | pass |
| haskell2010-local-factorial | `test/e2e/programs/haskell2010/local-factorial.hs` | success | native/no-egglog | `120` | stdout `120`, stderr empty, exit 0 | pass |
| haskell2010-local-factorial | `test/e2e/programs/haskell2010/local-factorial.hs` | success | emit-llvm/default | `120` | LLVM compiled through clang, stdout `120`, stderr empty, exit 0 | pass |
| haskell2010-fibonacci | `test/e2e/programs/haskell2010/fibonacci.hs` | success | native/default | `21` | stdout `21`, stderr empty, exit 0 | pass |
| haskell2010-fibonacci | `test/e2e/programs/haskell2010/fibonacci.hs` | success | native/no-egglog | `21` | stdout `21`, stderr empty, exit 0 | pass |
| haskell2010-mutual-recursion | `test/e2e/programs/haskell2010/mutual-recursion.hs` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-mutual-recursion | `test/e2e/programs/haskell2010/mutual-recursion.hs` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-recursive-list | `test/e2e/programs/haskell2010/recursive-list.hs` | success | native/default | `10` | stdout `10`, stderr empty, exit 0 | pass |
| haskell2010-recursive-list | `test/e2e/programs/haskell2010/recursive-list.hs` | success | native/no-egglog | `10` | stdout `10`, stderr empty, exit 0 | pass |
| haskell2010-typeclass-dictionary | `test/e2e/programs/haskell2010/typeclass-dictionary.hs` | success | native/default | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-typeclass-dictionary | `test/e2e/programs/haskell2010/typeclass-dictionary.hs` | success | native/no-egglog | `1` | stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-typeclass-dictionary | `test/e2e/programs/haskell2010/typeclass-dictionary.hs` | success | emit-llvm/default | `1` | LLVM compiled through clang, stdout `1`, stderr empty, exit 0 | pass |
| haskell2010-prelude-classes | `test/e2e/programs/haskell2010/prelude-classes.hs` | success | native/default | `6` | stdout `6`, stderr empty, exit 0 | pass |
| haskell2010-prelude-classes | `test/e2e/programs/haskell2010/prelude-classes.hs` | success | native/no-egglog | `6` | stdout `6`, stderr empty, exit 0 | pass |
| haskell2010-prelude-classes | `test/e2e/programs/haskell2010/prelude-classes.hs` | success | emit-llvm/default | `6` | LLVM compiled through clang, stdout `6`, stderr empty, exit 0 | pass |
| haskell2010-numeric-defaulting | `test/e2e/programs/haskell2010/numeric-defaulting.hs` | success | native/default | `7\n47` | stdout `7\n47`, stderr empty, exit 0 | pass |
| haskell2010-numeric-defaulting | `test/e2e/programs/haskell2010/numeric-defaulting.hs` | success | native/no-egglog | `7\n47` | stdout `7\n47`, stderr empty, exit 0 | pass |
| haskell2010-numeric-defaulting | `test/e2e/programs/haskell2010/numeric-defaulting.hs` | success | emit-llvm/default | `7\n47` | LLVM compiled through clang, stdout `7\n47`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | native/default | `20` | stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | native/no-egglog | `20` | stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | emit-llvm/default | `20` | LLVM compiled through clang, stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | emit-llvm/default | `7` | LLVM compiled through clang, stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | native/default | `ok\nanswer\n42\nTrue` | stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | native/no-egglog | `ok\nanswer\n42\nTrue` | stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | emit-llvm/default | `ok\nanswer\n42\nTrue` | LLVM compiled through clang, stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | native/default | `15` | stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | native/no-egglog | `15` | stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | emit-llvm/default | `15` | LLVM compiled through clang, stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-adt-box | `test/e2e/programs/haskell2010/adt-box.hs` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-adt-box | `test/e2e/programs/haskell2010/adt-box.hs` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-adt-box | `test/e2e/programs/haskell2010/adt-box.hs` | success | emit-llvm/default | `7` | LLVM compiled through clang, stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-adt-maybe | `test/e2e/programs/haskell2010/adt-maybe.hs` | success | native/default | `4` | stdout `4`, stderr empty, exit 0 | pass |
| haskell2010-adt-maybe | `test/e2e/programs/haskell2010/adt-maybe.hs` | success | native/no-egglog | `4` | stdout `4`, stderr empty, exit 0 | pass |
| haskell2010-adt-nested | `test/e2e/programs/haskell2010/adt-nested.hs` | success | native/default | `3` | stdout `3`, stderr empty, exit 0 | pass |
| haskell2010-adt-nested | `test/e2e/programs/haskell2010/adt-nested.hs` | success | native/no-egglog | `3` | stdout `3`, stderr empty, exit 0 | pass |
| haskell2010-adt-lazy-field | `test/e2e/programs/haskell2010/adt-lazy-field.hs` | success | native/default | `5` | stdout `5`, stderr empty, exit 0 | pass |
| haskell2010-adt-lazy-field | `test/e2e/programs/haskell2010/adt-lazy-field.hs` | success | native/no-egglog | `5` | stdout `5`, stderr empty, exit 0 | pass |
| addition-overflow | `test/e2e/programs/runtime-errors/addition-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| subtraction-overflow | `test/e2e/programs/runtime-errors/subtraction-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| multiplication-overflow | `test/e2e/programs/runtime-errors/multiplication-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-by-zero | `test/e2e/programs/runtime-errors/division-by-zero.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-by-zero | `test/e2e/programs/runtime-errors/division-by-zero.hg` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-overflow | `test/e2e/programs/runtime-errors/division-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-overflow | `test/e2e/programs/runtime-errors/division-overflow.hg` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| haskell2010-division-by-zero | `test/e2e/programs/haskell2010/division-by-zero.hs` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| haskell2010-division-by-zero | `test/e2e/programs/haskell2010/division-by-zero.hs` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| haskell2010-guard-fallthrough | `test/e2e/programs/haskell2010/guard-fallthrough.hs` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| haskell2010-guard-fallthrough | `test/e2e/programs/haskell2010/guard-fallthrough.hs` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| open-free-variable | `test/e2e/programs/compile-errors/open-free-variable.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |
| type-error | `test/e2e/programs/compile-errors/type-error.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |
| unsupported-recursion | `test/e2e/programs/unsupported/unsupported-recursion.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |

## Diagnostic Gaps

Generated native runtime errors currently abort with nonzero exit and no
runtime message. The wet tests record and enforce that convention so it remains
visible. Improving native runtime diagnostics is future CLI/runtime polish, not
part of this baseline.
