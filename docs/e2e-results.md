# End-to-End Wet Test Results

Recorded for the mandatory wet-test baseline added on top of commit `59e9b81`
(`Merge pull request #9 from drewmelmanrogers/dmelmanrogers/v0-2-main`). The
final commit hash for these changes is reported after commit creation because a
commit cannot contain its own final hash.

Run metadata:

- Date/time: `2026-05-18 01:29:13 UTC`
- OS: `macOS 15.7.3 24G419`, Darwin `24.6.0`, `arm64`
- GHC: `9.10.1`
- Cabal: `3.12.1.0`
- clang: `Apple clang version 15.0.0 (clang-1500.3.9.4)`
- Command: `scripts/e2e-wet-test.sh`

Summary:

- HUnit checks: 45
- Source files: 20
- Successful source cases: 12
- Runtime-error source cases: 5
- Compile-error source cases: 3
- Native compile/run checks: 28
- Default Egglog native checks: 20
- `--no-egglog` native checks: 8
- Emit-LLVM checks: 5
- Report/interpreter comparisons: 12
- Failures: 0

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
| addition-overflow | `test/e2e/programs/runtime-errors/addition-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| subtraction-overflow | `test/e2e/programs/runtime-errors/subtraction-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| multiplication-overflow | `test/e2e/programs/runtime-errors/multiplication-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-by-zero | `test/e2e/programs/runtime-errors/division-by-zero.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-by-zero | `test/e2e/programs/runtime-errors/division-by-zero.hg` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-overflow | `test/e2e/programs/runtime-errors/division-overflow.hg` | runtime-error | native/default | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| division-overflow | `test/e2e/programs/runtime-errors/division-overflow.hg` | runtime-error | native/no-egglog | nonzero exit | compile exit 0; run nonzero; stdout/stderr empty | pass |
| open-free-variable | `test/e2e/programs/compile-errors/open-free-variable.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |
| type-error | `test/e2e/programs/compile-errors/type-error.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |
| unsupported-recursion | `test/e2e/programs/unsupported/unsupported-recursion.hg` | compile-error | native/default | nonzero compile; no executable; category diagnostic | nonzero compile, no executable, category matched | pass |

## Diagnostic Gaps

Generated native runtime errors currently abort with nonzero exit and no
runtime message. The wet tests record and enforce that convention so it remains
visible. Improving native runtime diagnostics is future CLI/runtime polish, not
part of this baseline.
