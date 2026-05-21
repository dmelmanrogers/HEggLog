# End-to-End Wet Test Results

Recorded for the mandatory wet-test suite after TC-032 added derived `Bounded`
native coverage. The suite covers
the existing `.hg` native compiler baseline and Haskell 2010 executable-subset
`.hs` programs that compile to native executables, compare lazy runtime
behavior, and run both default Egglog and `--no-egglog` modes for Haskell 2010
optimizer coverage.

Run metadata:

- Date/time: `2026-05-21 05:47:13 UTC`
- OS: `macOS 15.7.3 24G419`, Darwin `24.6.0`, `arm64`
- GHC: `9.10.1`
- Cabal: `3.12.1.0`
- clang: `Apple clang version 15.0.0 (clang-1500.3.9.4)`
- Command: `cabal test e2e-wet-test`

Summary:

- HUnit checks: 173
- Source files: 67
- Successful source cases: 56
- Runtime-error source cases: 8
- Compile-error source cases: 3
- Native compile/run checks: 124
- Default Egglog native checks: 68
- `--no-egglog` native checks: 56
- Emit-LLVM checks: 37
- Report/interpreter comparisons: 11
- Failures: 0

This update adds dedicated Haskell 2010 native cases for TC-032: a positive
derived `Bounded` program that exercises all-nullary enumerations,
single-constructor products, records, newtypes, field-wise bounds, and
`Show`/`Enum` interoperation. The fixture runs in default and `--no-egglog`
modes and emits LLVM compiled through clang.

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
| haskell2010-prelude-append | `test/e2e/programs/haskell2010/prelude-append.hs` | success | native/default | `[1,2,3,4]\nhegglog\n[1,2,3]\n[True,False]\nhey\nheglog` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-prelude-append | `test/e2e/programs/haskell2010/prelude-append.hs` | success | native/no-egglog | `[1,2,3,4]\nhegglog\n[1,2,3]\n[True,False]\nhey\nheglog` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-prelude-append | `test/e2e/programs/haskell2010/prelude-append.hs` | success | emit-llvm/default | `[1,2,3,4]\nhegglog\n[1,2,3]\n[True,False]\nhey\nheglog` | LLVM compiled through clang, stdout matched, stderr empty, exit 0 | pass |
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
| haskell2010-numeric-hierarchy | `test/e2e/programs/haskell2010/numeric-hierarchy.hs` | success | native/default | `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7` | stdout `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7`, stderr empty, exit 0 | pass |
| haskell2010-numeric-hierarchy | `test/e2e/programs/haskell2010/numeric-hierarchy.hs` | success | native/no-egglog | `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7` | stdout `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7`, stderr empty, exit 0 | pass |
| haskell2010-numeric-hierarchy | `test/e2e/programs/haskell2010/numeric-hierarchy.hs` | success | emit-llvm/default | `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7` | LLVM compiled through clang, stdout `3\n2\n-4\n3\n-3\n-2\n3\n2\n-4\n3\n7\n1\n7`, stderr empty, exit 0 | pass |
| haskell2010-prelude-foldl | `test/e2e/programs/haskell2010/prelude-foldl.hs` | success | native/default | `1234\n-6\nabcd\n2\n7\n5` | stdout `1234\n-6\nabcd\n2\n7\n5`, stderr empty, exit 0 | pass |
| haskell2010-prelude-foldl | `test/e2e/programs/haskell2010/prelude-foldl.hs` | success | native/no-egglog | `1234\n-6\nabcd\n2\n7\n5` | stdout `1234\n-6\nabcd\n2\n7\n5`, stderr empty, exit 0 | pass |
| haskell2010-prelude-foldl | `test/e2e/programs/haskell2010/prelude-foldl.hs` | success | emit-llvm/default | `1234\n-6\nabcd\n2\n7\n5` | LLVM compiled through clang, stdout `1234\n-6\nabcd\n2\n7\n5`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | native/default | `20` | stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | native/no-egglog | `20` | stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-modules | `test/e2e/programs/haskell2010/modules/Main.hs` | success | emit-llvm/default | `20` | LLVM compiled through clang, stdout `20`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | native/default | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | native/no-egglog | `7` | stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-egglog-known-constructor | `test/e2e/programs/haskell2010/egglog-known-constructor.hs` | success | emit-llvm/default | `7` | LLVM compiled through clang, stdout `7`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | native/default | `ok\nanswer\n42\nTrue` | stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | native/no-egglog | `ok\nanswer\n42\nTrue` | stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-io-printing | `test/e2e/programs/haskell2010/io-printing.hs` | success | emit-llvm/default | `ok\nanswer\n42\nTrue` | LLVM compiled through clang, stdout `ok\nanswer\n42\nTrue`, stderr empty, exit 0 | pass |
| haskell2010-io-normal-examples | `test/e2e/programs/haskell2010/io-normal-examples.hs` | success | native/default | `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]` | stdout `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]`, stderr empty, exit 0 | pass |
| haskell2010-io-normal-examples | `test/e2e/programs/haskell2010/io-normal-examples.hs` | success | native/no-egglog | `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]` | stdout `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]`, stderr empty, exit 0 | pass |
| haskell2010-io-normal-examples | `test/e2e/programs/haskell2010/io-normal-examples.hs` | success | emit-llvm/default | `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]` | LLVM compiled through clang, stdout `hello\nbound\n"quoted"\n'X'\n"plain"\n[1,2,3]\n[True,False]`, stderr empty, exit 0 | pass |
| haskell2010-io-getline | `test/e2e/programs/haskell2010/io-getline.hs` | success | native/default | `first=hegg\nsecond=log\n7` | stdout matched with stdin `hegg\nlog\nunused\n`, stderr empty, exit 0 | pass |
| haskell2010-io-getline | `test/e2e/programs/haskell2010/io-getline.hs` | success | native/no-egglog | `first=hegg\nsecond=log\n7` | stdout matched with stdin `hegg\nlog\nunused\n`, stderr empty, exit 0 | pass |
| haskell2010-io-getline | `test/e2e/programs/haskell2010/io-getline.hs` | success | emit-llvm/default | `first=hegg\nsecond=log\n7` | LLVM compiled through clang, stdout matched with stdin `hegg\nlog\nunused\n`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | native/default | `15` | stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | native/no-egglog | `15` | stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-guards-as-patterns | `test/e2e/programs/haskell2010/guards-as-patterns.hs` | success | emit-llvm/default | `15` | LLVM compiled through clang, stdout `15`, stderr empty, exit 0 | pass |
| haskell2010-user-defined-operators | `test/e2e/programs/haskell2010/user-defined-operators.hs` | success | native/default | `537` | stdout `537`, stderr empty, exit 0 | pass |
| haskell2010-user-defined-operators | `test/e2e/programs/haskell2010/user-defined-operators.hs` | success | native/no-egglog | `537` | stdout `537`, stderr empty, exit 0 | pass |
| haskell2010-user-defined-operators | `test/e2e/programs/haskell2010/user-defined-operators.hs` | success | emit-llvm/default | `537` | LLVM compiled through clang, stdout `537`, stderr empty, exit 0 | pass |
| haskell2010-where-layout | `test/e2e/programs/haskell2010/where-layout.hs` | success | native/default | `14` | stdout `14`, stderr empty, exit 0 | pass |
| haskell2010-where-layout | `test/e2e/programs/haskell2010/where-layout.hs` | success | native/no-egglog | `14` | stdout `14`, stderr empty, exit 0 | pass |
| haskell2010-where-layout | `test/e2e/programs/haskell2010/where-layout.hs` | success | emit-llvm/default | `14` | LLVM compiled through clang, stdout `14`, stderr empty, exit 0 | pass |
| haskell2010-arithmetic-sequences | `test/e2e/programs/haskell2010/arithmetic-sequences.hs` | success | native/default | `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]` | stdout `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]`, stderr empty, exit 0 | pass |
| haskell2010-arithmetic-sequences | `test/e2e/programs/haskell2010/arithmetic-sequences.hs` | success | native/no-egglog | `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]` | stdout `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]`, stderr empty, exit 0 | pass |
| haskell2010-arithmetic-sequences | `test/e2e/programs/haskell2010/arithmetic-sequences.hs` | success | emit-llvm/default | `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]` | LLVM compiled through clang, stdout `[1,2,3,4]\n[1,3,5,7]\n[6,4,2,0]\nabcd\nfdb\n[7,8,9]`, stderr empty, exit 0 | pass |
| haskell2010-derived-enum | `test/e2e/programs/haskell2010/derived-enum.hs` | success | native/default | `0\n2\n2\n1\nWest\n[1,2,3]\n[3,2,1,0]\n[1,2,3]\n[0,2]\n[3,2,1,0]\n[1,2,3]\n[3,2,1,0]\n0` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-enum | `test/e2e/programs/haskell2010/derived-enum.hs` | success | native/no-egglog | `0\n2\n2\n1\nWest\n[1,2,3]\n[3,2,1,0]\n[1,2,3]\n[0,2]\n[3,2,1,0]\n[1,2,3]\n[3,2,1,0]\n0` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-enum | `test/e2e/programs/haskell2010/derived-enum.hs` | success | emit-llvm/default | `0\n2\n2\n1\nWest\n[1,2,3]\n[3,2,1,0]\n[1,2,3]\n[0,2]\n[3,2,1,0]\n[1,2,3]\n[3,2,1,0]\n0` | LLVM compiled through clang, stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-bounded | `test/e2e/programs/haskell2010/derived-bounded.hs` | success | native/default | `0\n3\nPair (False) (North)\nPair (True) (West)\nRecord { low = (False), high = (North) }\nRecord { low = (True), high = (West) }\nFlag (False)\nFlag (True)` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-bounded | `test/e2e/programs/haskell2010/derived-bounded.hs` | success | native/no-egglog | `0\n3\nPair (False) (North)\nPair (True) (West)\nRecord { low = (False), high = (North) }\nRecord { low = (True), high = (West) }\nFlag (False)\nFlag (True)` | stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-bounded | `test/e2e/programs/haskell2010/derived-bounded.hs` | success | emit-llvm/default | `0\n3\nPair (False) (North)\nPair (True) (West)\nRecord { low = (False), high = (North) }\nRecord { low = (True), high = (West) }\nFlag (False)\nFlag (True)` | LLVM compiled through clang, stdout matched, stderr empty, exit 0 | pass |
| haskell2010-derived-enum-runtime-error | `test/e2e/programs/haskell2010/derived-enum-runtime-error.hs` | runtime-error | native/default | non-zero exit | runtime error forced by `fromEnum (succ West)` | pass |
| haskell2010-derived-enum-runtime-error | `test/e2e/programs/haskell2010/derived-enum-runtime-error.hs` | runtime-error | native/no-egglog | non-zero exit | runtime error forced by `fromEnum (succ West)` | pass |
| haskell2010-list-comprehensions | `test/e2e/programs/haskell2010/list-comprehensions.hs` | success | native/default | `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]` | stdout `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]`, stderr empty, exit 0 | pass |
| haskell2010-list-comprehensions | `test/e2e/programs/haskell2010/list-comprehensions.hs` | success | native/no-egglog | `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]` | stdout `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]`, stderr empty, exit 0 | pass |
| haskell2010-list-comprehensions | `test/e2e/programs/haskell2010/list-comprehensions.hs` | success | emit-llvm/default | `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]` | LLVM compiled through clang, stdout `[2,3,4,6,8,12]\nabde\n[3,4]\n[3,7]\n[9]\n[12,13]`, stderr empty, exit 0 | pass |
| haskell2010-pattern-diagnostics | `test/e2e/programs/haskell2010/pattern-diagnostics.hs` | success | native/default | `7` | compile stderr contained `non-exhaustive pattern match`, `case alternatives`, and `False`; stdout `7`, run stderr empty, exit 0 | pass |
| haskell2010-pattern-diagnostics | `test/e2e/programs/haskell2010/pattern-diagnostics.hs` | success | native/no-egglog | `7` | compile stderr contained `non-exhaustive pattern match`, `case alternatives`, and `False`; stdout `7`, run stderr empty, exit 0 | pass |
| haskell2010-pattern-diagnostics | `test/e2e/programs/haskell2010/pattern-diagnostics.hs` | success | emit-llvm/default | `7` | compile stderr contained `non-exhaustive pattern match`, `case alternatives`, and `False`; LLVM compiled through clang, stdout `7`, run stderr empty, exit 0 | pass |
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
