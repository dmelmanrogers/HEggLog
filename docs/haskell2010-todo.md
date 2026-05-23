# HeggLog Haskell 2010 Compiler To-Do List

HeggLog is building a Haskell 2010 native-code compiler implemented in Haskell. The current `.hg` compiler remains the backend/middle-end substrate and regression baseline. This backlog tracks the work required to compile Haskell 2010 source programs to native executables through LLVM, with Egglog optimization over typed Core.

This document is the authoritative engineering backlog. The matching machine-readable index is `docs/haskell2010-todo.json`, and `scripts/validate-haskell2010-todo.py` fails if JSON and markdown task IDs, titles, statuses, or categories drift.

## Baseline Status

- Baseline branch observed: `dmelmanrogers/numeric-defaulting`.
- Baseline head before this backlog update: `0043a2d Add Haskell 2010 conformance suite baseline`.
- Baseline worktree before this backlog update: clean.
- `git diff --check`: passed before edits.
- `cabal build all`: passed before edits.
- Full validation status for this backlog update is recorded in the final task report for the change that edits this file.

# Milestone Index

## M0 — Current substrate preservation

- Goal: Keep the current .hg compiler, optimizer, LLVM/native path, docs, and wet tests stable while Haskell 2010 work proceeds.
- Exit criteria: Current .hg examples, native executable output, Egglog ANF behavior, and wet tests continue to pass unchanged.
- Task IDs included: BOOT-001, BOOT-002, BOOT-003, BOOT-004, BOOT-005, BOOT-006
- Required wet tests: Existing .hg e2e wet corpus plus compatibility examples.
- Risk level: low

## M1 — Haskell 2010 parser/layout

- Goal: Accept representative Haskell 2010 lexical, layout, declaration, expression, and pattern syntax into a source AST.
- Exit criteria: Parser accepts representative Haskell 2010 syntax fixtures, rejects malformed layout, and leaves .hg parsing unaffected.
- Task IDs included: FRONT-001, FRONT-002, FRONT-003, FRONT-004, FRONT-005, FRONT-006, FRONT-007, FRONT-008, FRONT-009, FRONT-010, FRONT-011, FRONT-012, FRONT-013, FRONT-014, FRONT-015, FRONT-016, FRONT-017, FRONT-018, FRONT-019, FRONT-020, FRONT-021, FRONT-022, FRONT-023, FRONT-024, FRONT-025, FRONT-026, FRONT-027, FRONT-028, FRONT-029, FRONT-030, FRONT-031, FRONT-032, FRONT-033, FRONT-034
- Required wet tests: No native wet tests required; parser/conformance syntax fixtures required.
- Risk level: medium

## M2 — Renamer and modules-lite

- Goal: Resolve source names to unique binders across lexical scopes and single-directory module graphs.
- Exit criteria: Every occurrence resolves to a unique binder or structured error; basic multi-module programs rename; duplicates/unbound names fail.
- Task IDs included: REN-001, REN-002, REN-003, REN-004, REN-005, REN-006, REN-007, REN-008, REN-009, REN-010, REN-011, REN-012, REN-013, REN-014, REN-015, REN-016, REN-017, REN-018, REN-019, REN-020, REN-021, REN-022, REN-023, REN-024, REN-025
- Required wet tests: Representative multi-module native programs once codegen is available.
- Risk level: medium

## M3 — Typed Core

- Goal: Provide the stable, typed Core IR boundary used by typechecking, optimization, STG lowering, and tests.
- Exit criteria: Simple parsed/renamed programs desugar to validated Core with resolved names and checked invariants.
- Task IDs included: CORE-001, CORE-002, CORE-003, CORE-004, CORE-005, CORE-006, CORE-007, CORE-008, CORE-009, CORE-010, CORE-011, CORE-012, CORE-013, CORE-014, CORE-015, CORE-016, CORE-017, CORE-018, CORE-019, CORE-020, CORE-021, CORE-022, CORE-023, CORE-024
- Required wet tests: No native wet tests required; Core golden and negative validation tests required.
- Risk level: medium

## M4 — HM typechecker

- Goal: Infer and check Haskell 2010 types for the supported subset and annotate/desugar to validating Core.
- Exit criteria: id, const, polymorphic let, signatures, and ill-typed programs behave correctly; generated Core validates.
- Task IDs included: TYPE-001, TYPE-002, TYPE-003, TYPE-004, TYPE-005, TYPE-006, TYPE-007, TYPE-008, TYPE-009, TYPE-010, TYPE-011, TYPE-012, TYPE-013, TYPE-014, TYPE-015, TYPE-016, TYPE-017, TYPE-018, TYPE-019, TYPE-020, TYPE-021, TYPE-022
- Required wet tests: Native smoke only after STG/LLVM; typechecker negative and conformance tests required.
- Risk level: high

## M5 — Lazy semantics and STG

- Goal: Represent lazy evaluation explicitly and lower typed Core into an STG-like IR with reference semantics.
- Exit criteria: Observable laziness, sharing, letrec, case demand, and black-hole behavior are tested or documented.
- Task IDs included: STG-001, STG-002, STG-003, STG-004, STG-005, STG-006, STG-007, STG-008, STG-009, STG-010, STG-011, STG-012, STG-013, STG-014, STG-015, STG-016, STG-017, STG-018, STG-019
- Required wet tests: Lazy semantics native wet tests once runtime/LLVM is available.
- Risk level: high

## M6 — Runtime system

- Goal: Provide runtime object layout and operations for closures, thunks, constructors, errors, and IO hooks.
- Exit criteria: Generated executables link the runtime; thunks allocate/enter/update correctly; runtime errors exit nonzero.
- Task IDs included: RTS-001, RTS-002, RTS-003, RTS-004, RTS-005, RTS-006, RTS-007, RTS-008, RTS-009, RTS-010, RTS-011, RTS-012, RTS-013, RTS-014, RTS-015, RTS-016, RTS-017, RTS-018, RTS-019, RTS-020, RTS-021
- Required wet tests: Native runtime error, thunk update, constructor, and IO hook wet tests.
- Risk level: high

## M7 — STG-to-LLVM native codegen

- Goal: Lower STG into LLVM IR and clang-linked native executables for lazy programs.
- Exit criteria: hegglog compile Main.hs -o main works for Core-0 lazy programs and lazy semantic native tests pass.
- Task IDs included: LLVM-001, LLVM-002, LLVM-003, LLVM-004, LLVM-005, LLVM-006, LLVM-007, LLVM-008, LLVM-009, LLVM-010, LLVM-011, LLVM-012, LLVM-013, LLVM-014, LLVM-015, LLVM-016, LLVM-017, LLVM-018
- Required wet tests: Core-0 lazy native wet tests, emitted LLVM validation tests.
- Risk level: high

## M8 — ADTs and pattern matching

- Goal: Compile Haskell data declarations, constructors, and pattern matching through Core/STG/native paths.
- Exit criteria: Maybe, Either, custom ADTs, constructor cases, nested patterns, and pattern-bound variables work.
- Task IDs included: ADT-001, ADT-002, ADT-003, ADT-004, ADT-005, ADT-006, ADT-007, PAT-001, PAT-002, PAT-003, PAT-004, PAT-005, PAT-006, PAT-007, PAT-008, PAT-009, PAT-010, PAT-011, PAT-012, PAT-013, PAT-014, PAT-015, PAT-016
- Required wet tests: ADT and pattern native wet tests, including negative pattern diagnostics.
- Risk level: high

## M9 — Recursion and letrec

- Goal: Support recursive top-level, mutual, and local bindings with lazy runtime semantics.
- Exit criteria: Recursive and mutually recursive functions compile natively; nontermination tests remain isolated.
- Task IDs included: CORE-REC-001, CORE-REC-002, CORE-REC-003, CORE-REC-004, STG-REC-001, STG-REC-002, RTS-REC-001, TEST-REC-001, TEST-REC-002, TEST-REC-003, TEST-REC-004
- Required wet tests: Factorial, fibonacci, recursive list, and mutual recursion native wet tests.
- Risk level: medium

## M10 — Lists, tuples, Char, String

- Goal: Implement standard Haskell data forms and literal representations needed by Prelude and IO.
- Exit criteria: Lists, tuples, Char, and String parse/typecheck/desugar/compile where intended with representative native tests.
- Task IDs included: PRELUDE-DATA-001, PRELUDE-DATA-002, PRELUDE-DATA-003, PRELUDE-DATA-004, PRELUDE-DATA-005, PRELUDE-DATA-006, PRELUDE-DATA-007, PRELUDE-DATA-008, PRELUDE-DATA-009, PRELUDE-DATA-010, PRELUDE-DATA-011, PRELUDE-DATA-012
- Required wet tests: List, tuple, and String literal native wet tests.
- Risk level: high

## M11 — Type classes and dictionaries

- Goal: Represent, solve, and lower Haskell 2010 classes, instances, constraints, defaults, and deriving where implemented.
- Exit criteria: Class methods compile through dictionaries; basic instances and numeric literals work; illegal instances fail.
- Task IDs included: TC-001, TC-002, TC-003, TC-004, TC-005, TC-006, TC-007, TC-008, TC-009, TC-010, TC-011, TC-012, TC-013, TC-014, TC-015, TC-016, TC-017, TC-018, TC-019, TC-020, TC-021, TC-022, TC-023, TC-024, TC-025, TC-026, TC-027, TC-028, TC-029, TC-030, TC-031, TC-032, TC-033
- Required wet tests: Typeclass and dictionary native wet tests plus negative instance tests.
- Risk level: high

## M12 — Prelude and libraries

- Goal: Provide a coherent Prelude strategy and enough library behavior for representative Haskell 2010 programs.
- Exit criteria: Representative Prelude programs compile; implicit import behavior works; deviations are explicit.
- Task IDs included: PRELUDE-001, PRELUDE-002, PRELUDE-003, PRELUDE-004, PRELUDE-005, PRELUDE-006, PRELUDE-007, PRELUDE-008, PRELUDE-009, PRELUDE-010, PRELUDE-011, PRELUDE-012, PRELUDE-013, PRELUDE-014, PRELUDE-015, PRELUDE-016, PRELUDE-017, PRELUDE-018, PRELUDE-019, PRELUDE-020, LIB-001, LIB-002, LIB-003, LIB-004, LIB-005, LIB-006, LIB-007, LIB-008, LIB-009, LIB-010, LIB-011, LIB-012
- Required wet tests: Prelude function and implicit-import native wet tests.
- Risk level: high

## M13 — IO and do-notation

- Goal: Compile Haskell IO programs and do-notation through native runtime hooks with clear stdout/stderr behavior.
- Exit criteria: print, putStrLn, return, bind/sequencing, and do notation compile and run for the intended subset.
- Task IDs included: IO-001, IO-002, IO-003, IO-004, IO-005, IO-006, IO-007, IO-008, IO-009, IO-010, IO-011, IO-012, IO-013, IO-014
- Required wet tests: IO printing, getLine where implemented, and do-notation native wet tests.
- Risk level: high

## M14 — Full modules

- Goal: Move from modules-lite to Haskell 2010 module/import/export behavior or explicit deviations.
- Exit criteria: Multi-file Haskell programs compile and imports/exports match Haskell 2010 or documented deviations.
- Task IDs included: MOD-001, MOD-002, MOD-003, MOD-004, MOD-005, MOD-006, MOD-007, MOD-008, MOD-009, MOD-010, MOD-011, MOD-012, MOD-013, MOD-014
- Required wet tests: Multi-module native and negative import/export tests.
- Risk level: high

## M15 — FFI implementation and closure

- Goal: Implement and track the Haskell 2010 FFI surface with explicit remaining gaps rather than a broad deferral.
- Exit criteria: Supported FFI import/export, marshalling, pointer, callback, and lifetime semantics work with tests; any remaining deviations are narrow task-backed items.
- Task IDs included: FFI-001, FFI-002, FFI-003, FFI-004, FFI-005, FFI-006, FFI-007, FFI-008, FFI-009, FFI-010, FFI-011, FFI-012, FFI-013
- Required wet tests: Native C-helper tests plus negative conformance tests for unsupported or invalid FFI shapes.
- Risk level: medium

## M16 — Egglog Core optimizer

- Goal: Optimize typed Core safely under lazy semantics with provenance and optimized/unoptimized agreement tests.
- Exit criteria: Extracted Core validates, lazy semantics are preserved, and optimized/unoptimized native outputs agree.
- Task IDs included: EGG-CORE-001, EGG-CORE-002, EGG-CORE-003, EGG-CORE-004, EGG-CORE-005, EGG-CORE-006, EGG-CORE-007, EGG-CORE-008, EGG-CORE-009, EGG-CORE-010, EGG-CORE-011, EGG-CORE-012, EGG-CORE-013, EGG-CORE-014, EGG-CORE-015, EGG-CORE-016, EGG-CORE-017, EGG-CORE-018, EGG-CORE-019, EGG-CORE-020
- Required wet tests: Optimized vs --no-egglog native wet tests and bottom-preservation tests.
- Risk level: high

## M17 — Diagnostics

- Goal: Make parse, rename, type, module, backend, and runtime diagnostics source-spanned and stable.
- Exit criteria: Parse/name/type errors have useful spans; diagnostics are stable enough for tests; runtime attribution is useful where possible.
- Task IDs included: DIAG-001, DIAG-002, DIAG-003, DIAG-004, DIAG-005, DIAG-006, DIAG-007, DIAG-008, DIAG-009, DIAG-010, DIAG-011, DIAG-012, DIAG-013, DIAG-014, DIAG-015, DIAG-016
- Required wet tests: Diagnostic category checks in conformance/wet tests.
- Risk level: medium

## M18 — CLI productization

- Goal: Provide stable user-facing commands, flags, stdout/stderr policy, and exit-code behavior.
- Exit criteria: Common workflows are covered by CLI wet tests and README examples match the CLI.
- Task IDs included: CLI-001, CLI-002, CLI-003, CLI-004, CLI-005, CLI-006, CLI-007, CLI-008, CLI-009, CLI-010, CLI-011, CLI-012, CLI-013, CLI-014, CLI-015, CLI-016
- Required wet tests: CLI wet tests for check/run/compile/report/emit modes.
- Risk level: medium

## M19 — Haskell 2010 conformance suite closure

- Goal: Close the gap between the conformance matrix, manifest, implementation, and documented deviations.
- Exit criteria: Every matrix row links to a test or deviation and no undocumented failures remain.
- Task IDs included: SURFACE-001, SURFACE-002, SURFACE-003, TEST-CONF-001, TEST-CONF-002, TEST-CONF-003, TEST-CONF-004, TEST-CONF-005, TEST-CONF-006, TEST-CONF-007, TEST-CONF-008, TEST-CONF-009, TEST-CONF-010, TEST-CONF-011, TEST-CONF-012, TEST-CONF-013, TEST-CONF-014, TEST-CONF-015
- Required wet tests: Native wet conformance suite across implemented Haskell 2010 feature areas.
- Risk level: high

## M20 — Release quality

- Goal: Make the project buildable, testable, installable, documented, versioned, and releasable from a fresh checkout.
- Exit criteria: Fresh checkout builds/tests, install instructions work, release checklist exists, and docs are internally consistent.
- Task IDs included: DOC-001, DOC-002, DOC-003, DOC-004, REL-001, REL-002, REL-003, REL-004, REL-005, REL-006, REL-007, REL-008, REL-009, REL-010, REL-011, REL-012, REL-013, REL-014
- Required wet tests: Full CI matrix and release smoke tests.
- Risk level: medium

# Dependency Graph

- Parser/layout -> renamer -> typechecker -> Core -> STG -> runtime/LLVM -> native wet tests
- ADTs -> pattern matching -> lists/tuples -> Prelude -> type classes -> IO
- Core -> Egglog Core optimizer -> optimized native wet tests
- Modules-lite -> full modules -> Prelude import behavior -> conformance closure
- Diagnostics spans -> parser/renamer/typechecker/backend/runtime diagnostics

# Parallelization Plan

- Frontend agent: FRONT and REN tasks.
- Type system agent: TYPE and TC tasks.
- Core agent: CORE and desugaring tasks.
- Runtime/STG agent: STG and RTS tasks.
- Backend agent: LLVM tasks.
- Egglog agent: EGG-CORE tasks.
- Testing agent: TEST-CONF, wet tests, property tests.
- Docs/release agent: DOC, REL, README, matrix updates.

Rules:
- each agent works only against documented IR boundaries
- each task must update tests
- each task must update the conformance matrix
- no agent changes another subsystem's invariants without updating docs and tests
- every merged task must pass full validation

# Next Implementation Tasks

## Source surface closure

Complete: SURFACE-001, SURFACE-002, and SURFACE-003.

## Next coherent chunk: Prelude, deriving, and typeclass library completion

1. LIB-001 — Control.Monad report completion.
2. LIB-002 — Data.List report completion.
3. LIB-003 — Data.Maybe report completion.
4. LIB-004 — Data.Char report completion.
5. LIB-007 — Data.Ratio and Rational report completion.
6. LIB-010 — Numeric report completion.

Completed in this chunk: PRELUDE-019 — Prelude function completion;
PRELUDE-020 — standard library module expansion; TEST-CONF-015 — validator-backed
library conformance reconciliation against Chapter 9 Prelude and the Part II
library inventory; TC-030 — Report-shaped Read implementation.
Haskell 2010 Libraries inventory.

## Remaining FFI closure chunk

FFI-010 is complete for floating-point FFI marshalling, and FFI-011 is complete
for FFI link metadata plus explicit native link inputs.

1. FFI-012 — callback and finalizer lifetime completion.
2. FFI-013 — Foreign library surface completion.

# Task Backlog

## BOOT-001 — Preserve current `.hg` native compiler path

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- FRONT-001
- FRONT-002
- FRONT-003
- FRONT-004
- FRONT-005
- FRONT-006
- FRONT-008
- FRONT-010
- FRONT-011
- FRONT-013
- FRONT-014
- FRONT-015
- FRONT-017
- FRONT-018
- FRONT-019
- FRONT-020
- FRONT-021
- FRONT-022
- FRONT-023
- FRONT-024
- FRONT-025
- FRONT-026
- FRONT-028
- FRONT-031
- FRONT-032
- FRONT-033
- FRONT-034

Scope:
- Deliver Preserve current `.hg` native compiler path for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Preserve current `.hg` native compiler path is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## BOOT-002 — Preserve current Egglog ANF backend regression coverage

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- none

Scope:
- Deliver Preserve current Egglog ANF backend regression coverage for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Preserve current Egglog ANF backend regression coverage is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## BOOT-003 — Preserve current LLVM/native executable pipeline

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- none

Scope:
- Deliver Preserve current LLVM/native executable pipeline for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Preserve current LLVM/native executable pipeline is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## BOOT-004 — Preserve current e2e wet test suite

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- none

Scope:
- Deliver Preserve current e2e wet test suite for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Preserve current e2e wet test suite is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## BOOT-005 — Keep current `.hg` language docs separated from Haskell 2010 target docs

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- none

Scope:
- Deliver Keep current `.hg` language docs separated from Haskell 2010 target docs for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Keep current `.hg` language docs separated from Haskell 2010 target docs is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## BOOT-006 — Add compatibility tests ensuring current `.hg` examples still run after Haskell 2010 work

Status:
- complete

Category:
- testing

Depends on:
- none

Blocks:
- none

Scope:
- Deliver Add compatibility tests ensuring current `.hg` examples still run after Haskell 2010 work for Current substrate preservation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- Add compatibility tests ensuring current `.hg` examples still run after Haskell 2010 work is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M0 (Current substrate preservation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-001 — Haskell 2010 token model

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- FRONT-007
- REN-001
- REN-002
- REN-003
- REN-004
- REN-005
- REN-006
- REN-008
- REN-009
- REN-010
- REN-012
- REN-013
- REN-014
- REN-015
- REN-016
- REN-017
- REN-018
- REN-019
- REN-020
- REN-021
- REN-023
- REN-024
- REN-025

Scope:
- Deliver Haskell 2010 token model for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Haskell 2010 token model is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-002 — comments and nested comments

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver comments and nested comments for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- comments and nested comments is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-003 — identifiers/operators/reserved words

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver identifiers/operators/reserved words for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- identifiers/operators/reserved words is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-004 — numeric literal parsing

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver numeric literal parsing for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- numeric literal parsing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-005 — char literal parsing

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver char literal parsing for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- char literal parsing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-006 — string literal parsing

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver string literal parsing for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- string literal parsing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-007 — layout rule implementation

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-001

Blocks:
- FRONT-009
- REN-001
- REN-002
- REN-003
- REN-004
- REN-005
- REN-006
- REN-008
- REN-009
- REN-010
- REN-012
- REN-013
- REN-014
- REN-015
- REN-016
- REN-017
- REN-018
- REN-019
- REN-020
- REN-021
- REN-023
- REN-024
- REN-025

Scope:
- Deliver layout rule implementation for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- layout rule implementation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-008 — explicit braces/semicolons

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver explicit braces/semicolons for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- explicit braces/semicolons is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-009 — module header parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-007

Blocks:
- FRONT-012

Scope:
- Deliver module header parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- module header parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-010 — import declaration parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver import declaration parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- import declaration parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-011 — export list parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver export list parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- export list parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-012 — top-level declaration parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-009

Blocks:
- FRONT-016
- FRONT-029

Scope:
- Deliver top-level declaration parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- top-level declaration parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-013 — type signature parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver type signature parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- type signature parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-014 — function binding parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver function binding parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- function binding parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-015 — pattern binding parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver pattern binding parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- pattern binding parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-016 — expression parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-012

Blocks:
- FRONT-027

Scope:
- Deliver expression parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- expression parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-017 — lambda/application parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver lambda/application parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- lambda/application parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-018 — infix expression parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver infix expression parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- infix expression parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-019 — operator section parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver operator section parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- operator section parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-020 — let/where parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver let/where parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- let/where parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-021 — if/case parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver if/case parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- if/case parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-022 — do-notation parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver do-notation parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- do-notation parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-023 — list syntax parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver list syntax parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list syntax parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-024 — tuple syntax parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver tuple syntax parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- tuple syntax parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-025 — arithmetic sequence parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver arithmetic sequence parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- arithmetic sequence parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-026 — list comprehension parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver list comprehension parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list comprehension parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-027 — pattern parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-016

Blocks:
- none

Scope:
- Deliver pattern parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- pattern parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-028 — guard parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver guard parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- guard parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-029 — data/newtype/type parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-012

Blocks:
- FRONT-030

Scope:
- Deliver data/newtype/type parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- data/newtype/type parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-030 — class/instance parser

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-029

Blocks:
- none

Scope:
- Deliver class/instance parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- class/instance parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-031 — fixity declaration parser

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver fixity declaration parser for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- fixity declaration parser is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-032 — parser error source spans

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- DIAG-001
- DIAG-002
- DIAG-003
- DIAG-004
- DIAG-005
- DIAG-006
- DIAG-007
- DIAG-008
- DIAG-009
- DIAG-010
- DIAG-011
- DIAG-012
- DIAG-013
- DIAG-014
- DIAG-015
- DIAG-016

Scope:
- Deliver parser error source spans for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- parser error source spans is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-033 — parser golden tests

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver parser golden tests for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- parser golden tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FRONT-034 — parser negative layout tests

Status:
- complete

Category:
- frontend

Depends on:
- BOOT-001

Blocks:
- none

Scope:
- Deliver parser negative layout tests for Haskell 2010 parser/layout while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Lexer.hs`
- `src/Haskell2010/Layout.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- parser negative layout tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- parser negative tests
- parser golden tests
- syntax conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M1 (Haskell 2010 parser/layout). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-001 — unique name representation

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- CORE-001
- CORE-004
- CORE-005
- CORE-006
- CORE-007
- CORE-008
- CORE-009
- CORE-010
- CORE-011
- CORE-012
- CORE-013
- CORE-014
- CORE-015
- CORE-016
- CORE-017
- CORE-018
- CORE-019
- CORE-020
- CORE-021
- CORE-022
- CORE-023
- CORE-024
- REN-007
- REN-011
- REN-022

Scope:
- Deliver unique name representation for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- unique name representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-002 — value namespace

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver value namespace for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- value namespace is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-003 — constructor namespace

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver constructor namespace for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- constructor namespace is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-004 — type constructor namespace

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver type constructor namespace for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- type constructor namespace is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-005 — class namespace

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver class namespace for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- class namespace is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-006 — module namespace

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver module namespace for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- module namespace is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-007 — local lexical scope

Status:
- complete

Category:
- renamer

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver local lexical scope for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- local lexical scope is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-008 — lambda binder scope

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver lambda binder scope for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- lambda binder scope is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-009 — let/where scope

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver let/where scope for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- let/where scope is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-010 — pattern binder scope

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver pattern binder scope for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- pattern binder scope is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-011 — top-level binding scope

Status:
- complete

Category:
- renamer

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver top-level binding scope for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- top-level binding scope is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-012 — duplicate binding detection

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver duplicate binding detection for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- duplicate binding detection is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-013 — unbound name diagnostics

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver unbound name diagnostics for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- unbound name diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-014 — qualified names

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver qualified names for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- qualified names is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-015 — import resolution, single-directory whole-program mode

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- MOD-001
- MOD-002
- MOD-003
- MOD-004
- MOD-005
- MOD-006
- MOD-007
- MOD-008
- MOD-009
- MOD-010
- MOD-011
- MOD-012
- MOD-013
- MOD-014

Scope:
- Deliver import resolution, single-directory whole-program mode for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- import resolution, single-directory whole-program mode is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-016 — export list filtering

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver export list filtering for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- export list filtering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-017 — qualified imports

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver qualified imports for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- qualified imports is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-018 — hiding imports

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver hiding imports for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- hiding imports is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-019 — import aliases

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver import aliases for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- import aliases is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-020 — module graph construction

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver module graph construction for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- module graph construction is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-021 — module cycle detection

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver module cycle detection for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- module cycle detection is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-022 — fixity declaration collection

Status:
- complete

Category:
- renamer

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver fixity declaration collection for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- fixity declaration collection is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-023 — infix reassociation using fixities

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver infix reassociation using fixities for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- infix reassociation using fixities is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-024 — renamer tests for shadowing

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver renamer tests for shadowing for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- renamer tests for shadowing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REN-025 — renamer tests for imports/exports

Status:
- complete

Category:
- renamer

Depends on:
- FRONT-001
- FRONT-007

Blocks:
- none

Scope:
- Deliver renamer tests for imports/exports for Renamer and modules-lite while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Names.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- renamer tests for imports/exports is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- renamer unit tests
- duplicate/unbound negative tests
- module import/export conformance tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M2 (Renamer and modules-lite). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-001 — Core name/binder model

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- CORE-002

Scope:
- Deliver Core name/binder model for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core name/binder model is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-002 — Core type representation

Status:
- complete

Category:
- core

Depends on:
- CORE-001

Blocks:
- CORE-003
- TYPE-001
- TYPE-002
- TYPE-004
- TYPE-005
- TYPE-006
- TYPE-008
- TYPE-009
- TYPE-010
- TYPE-011
- TYPE-012
- TYPE-013
- TYPE-014
- TYPE-015
- TYPE-016
- TYPE-017
- TYPE-018
- TYPE-019
- TYPE-020
- TYPE-021
- TYPE-022

Scope:
- Deliver Core type representation for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core type representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-003 — Core expression representation

Status:
- complete

Category:
- core

Depends on:
- CORE-002

Blocks:
- STG-001
- STG-002
- STG-003
- STG-004
- STG-005
- STG-006
- STG-007
- STG-008
- STG-009
- STG-010
- STG-011
- STG-012
- STG-013
- STG-014
- STG-015
- STG-016
- STG-017
- STG-018
- STG-019
- TYPE-002
- TYPE-004
- TYPE-005
- TYPE-006
- TYPE-008
- TYPE-009
- TYPE-010
- TYPE-011
- TYPE-012
- TYPE-013
- TYPE-014
- TYPE-015
- TYPE-016
- TYPE-017
- TYPE-018
- TYPE-019
- TYPE-020
- TYPE-021
- TYPE-022

Scope:
- Deliver Core expression representation for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core expression representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-004 — Core literal representation

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core literal representation for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core literal representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-005 — Core let/letrec

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core let/letrec for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core let/letrec is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-006 — Core case/alternatives

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- PAT-001
- PAT-002
- PAT-003
- PAT-004
- PAT-005
- PAT-006
- PAT-007
- PAT-008
- PAT-009
- PAT-010
- PAT-011
- PAT-012
- PAT-013
- PAT-014
- PAT-015
- PAT-016

Scope:
- Deliver Core case/alternatives for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core case/alternatives is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-007 — Core constructors

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core constructors for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core constructors is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-008 — Core primitive operations

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core primitive operations for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core primitive operations is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-009 — Core dictionaries placeholder

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- TC-001
- TC-002
- TC-003
- TC-004
- TC-005
- TC-006
- TC-007
- TC-008
- TC-009
- TC-010
- TC-011
- TC-012
- TC-013
- TC-014
- TC-015
- TC-016
- TC-017
- TC-018
- TC-019
- TC-020
- TC-021
- TC-022
- TC-023
- TC-024
- TC-025
- TC-026
- TC-027
- TC-028

Scope:
- Deliver Core dictionaries placeholder for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core dictionaries placeholder is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-010 — Core validator

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- EGG-CORE-001
- EGG-CORE-002
- EGG-CORE-003
- EGG-CORE-004
- EGG-CORE-005
- EGG-CORE-006
- EGG-CORE-007
- EGG-CORE-008
- EGG-CORE-009
- EGG-CORE-010
- EGG-CORE-011
- EGG-CORE-012
- EGG-CORE-013
- EGG-CORE-014
- EGG-CORE-015
- EGG-CORE-016
- EGG-CORE-017
- EGG-CORE-018
- EGG-CORE-019
- EGG-CORE-020

Scope:
- Deliver Core validator for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core validator is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-011 — Core pretty-printer

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core pretty-printer for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core pretty-printer is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-012 — Core free variable analysis

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core free variable analysis for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core free variable analysis is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-013 — Core substitution/capture avoidance

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core substitution/capture avoidance for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core substitution/capture avoidance is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-014 — Core alpha-equivalence helper

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core alpha-equivalence helper for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core alpha-equivalence helper is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-015 — Core evaluator/reference semantics, if required

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core evaluator/reference semantics, if required for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core evaluator/reference semantics, if required is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-016 — desugar variables/literals/lambda/app

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar variables/literals/lambda/app for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar variables/literals/lambda/app is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-017 — desugar let/where

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar let/where for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar let/where is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-018 — desugar if to case

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar if to case for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar if to case is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-019 — desugar simple case

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar simple case for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar simple case is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-020 — desugar guards

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar guards for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar guards is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-021 — desugar sections

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar sections for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar sections is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Left and right operator sections desugar through generated typed Core lambdas that reuse the existing infix operator inference path.

## CORE-022 — desugar list/tuple syntax placeholders

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver desugar list/tuple syntax placeholders for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- desugar list/tuple syntax placeholders is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-023 — Core golden tests

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core golden tests for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core golden tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-024 — Core validation negative tests

Status:
- complete

Category:
- core

Depends on:
- REN-001

Blocks:
- none

Scope:
- Deliver Core validation negative tests for Typed Core while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- Core validation negative tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M3 (Typed Core). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-001 — type variable representation

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002

Blocks:
- TYPE-003

Scope:
- Deliver type variable representation for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- type variable representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-002 — type schemes

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver type schemes for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- type schemes is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-003 — unification

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-001

Blocks:
- TYPE-007

Scope:
- Deliver unification for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- unification is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-004 — occurs check

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver occurs check for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- occurs check is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-005 — generalization

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver generalization for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- generalization is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-006 — instantiation

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver instantiation for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- instantiation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-007 — expression inference

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-003

Blocks:
- STG-002
- STG-003
- STG-004
- STG-005
- STG-006
- STG-007
- STG-008
- STG-009
- STG-010
- STG-011
- STG-012
- STG-013
- STG-014
- STG-015
- STG-016
- STG-017
- STG-018
- STG-019

Scope:
- Deliver expression inference for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- expression inference is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-008 — top-level type signatures

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver top-level type signatures for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- top-level type signatures is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-009 — let-polymorphism

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver let-polymorphism for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- let-polymorphism is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-010 — recursive binding typing

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver recursive binding typing for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- recursive binding typing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-011 — kind representation

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver kind representation for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- kind representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). The typechecker now represents `*`, kind arrows, rendered kinds, derived kind arity, and type-constructor info for user and supported built-in type constructors. TYPE-012 builds on this with source type-expression kind inference/checking.

## TYPE-012 — kind inference/checking

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver kind inference/checking for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- kind inference/checking is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). The typechecker now infers and checks `*` and arrow kinds for supported source monotypes, constructor fields, signatures, and constraints. It infers higher-kinded data parameters from constructor field use, rejects partial or over-applied type constructors before Core generation, and TYPE-013 expands type synonyms before Core conversion. Broader class typing and later surface features remain tracked by their dedicated tasks.

## TYPE-013 — type synonym expansion

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver type synonym expansion for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- type synonym expansion is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Type synonyms now carry inferred kinds, are rejected when recursive, and expand structurally in signatures, constructor fields, constraints, instance heads, and default declarations before Core conversion. Higher-kinded synonym parameters are inferred through the same kind machinery as data parameters.

## TYPE-014 — newtype typing

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver newtype typing for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- newtype typing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Newtype declarations now typecheck through the current constructor metadata path, enforce Haskell's exactly-one-field newtype constructor invariant, infer/check parameter kinds including higher-kinded fields, and support constructor expressions and patterns in the executable subset. Runtime/Core representation optimization remains ADT-004.

## TYPE-015 — ADT constructor typing

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- ADT-001
- ADT-002
- ADT-003
- ADT-004
- ADT-005
- ADT-006

Scope:
- Deliver ADT constructor typing for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- ADT constructor typing is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-016 — constraint representation

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- TC-001
- TC-002
- TC-003
- TC-004
- TC-005
- TC-006
- TC-007
- TC-008
- TC-009
- TC-010
- TC-011
- TC-012
- TC-013
- TC-014
- TC-015
- TC-016
- TC-017
- TC-018
- TC-019
- TC-020
- TC-021
- TC-022
- TC-023
- TC-024
- TC-025
- TC-026
- TC-027
- TC-028

Scope:
- Deliver constraint representation for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Class constraints use an explicit internal representation with a class head and ordered argument list.
- The current executable slice validates the supported single-argument class constraint arity before kind checking, scheme construction, defaulting, and dictionary elaboration.
- Constraint arguments are normalized through kind checking, type synonym expansion, substitution, generalization, and Core dictionary type construction.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Completed by adding the structured `ClassConstraint` model, explicit class-constraint arity diagnostics, normalized synonym-backed constraint arguments, and native conformance coverage for dictionary elaboration through a type synonym.

## TYPE-017 — class constraints placeholder

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver class constraints placeholder for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Unsupported class-constraint contexts are represented by a structured typechecker diagnostic rather than ad hoc placeholder strings.
- Superclass contexts, method-specific constraints, instance contexts, and expression type-signature constraints report the structured placeholder while preserving parsed/renamed constraint details.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Completed by introducing an explicit `UnsupportedClassConstraintContext` diagnostic for currently unsupported constraint positions, preserving constraint parsing/kind checks before rejection, and adding unit/conformance coverage for the placeholder behavior.

## TYPE-018 — numeric literal defaulting

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver numeric literal defaulting for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- numeric literal defaulting is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TYPE-019 — monomorphism restriction decision/documentation

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver monomorphism restriction decision/documentation for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- The executable-subset monomorphism/defaulting decision is documented in the type inference docs and conformance matrix.
- Unsigned nullary value bindings without explicit signatures are documented and tested as eligible for standard-class defaulting before generalization.
- Explicitly signed bindings and functions with value parameters are documented as protected from that defaulting pass; full Haskell 2010 monomorphism-restriction coverage is deferred until broader pattern-binding and class-library support exists.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Completed by documenting the executable-subset monomorphism/defaulting policy, pinning it to the existing defaulting code path, and adding unit/conformance coverage for unsigned nullary value binding defaulting.

## TYPE-020 — type error diagnostics with spans

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- DIAG-001
- DIAG-002
- DIAG-003
- DIAG-004
- DIAG-005
- DIAG-006
- DIAG-007
- DIAG-008
- DIAG-009
- DIAG-010
- DIAG-011
- DIAG-012
- DIAG-013
- DIAG-014
- DIAG-015
- DIAG-016

Scope:
- Deliver type error diagnostics with spans for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Parsed and renamed Haskell 2010 declarations, expressions, patterns, statements, alternatives, constructor declarations, RHSs, and source types preserve source spans.
- Typechecker failures thrown while a source node is active render with `file:line:column` source spans through the shared diagnostic formatter.
- Delayed class-constraint dictionary failures retain the originating expression/type span rather than losing attribution during Core elaboration.
- The CLI conformance manifest checks a negative type-error fixture for a concrete source-span prefix.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Completed by preserving spans through the Haskell 2010 parsed/renamed AST, threading span context through typechecking, retaining spans on class constraints for delayed dictionary failures, and adding unit plus CLI conformance coverage for source-spanned type errors.

## TYPE-021 — property tests for inference

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver property tests for inference for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Generated well-typed Haskell 2010 inference programs typecheck and emit validating Core.
- Generated custom type-class dictionary inference programs typecheck, emit validating Core, and retain dictionary constructor metadata.
- Generated signature-mismatch programs fail with structured inference/type errors rather than emitting Core.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Completed with QuickCheck-backed Haskell 2010 inference properties covering generated `Int`/`Bool` expressions, let/lambda/if/operator forms, custom dictionary solving, Core validation, and structured negative failures.

## TYPE-022 — negative type tests

Status:
- complete

Category:
- typechecker

Depends on:
- CORE-002
- CORE-003

Blocks:
- none

Scope:
- Deliver negative type tests for HM typechecker while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- negative type tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M4 (HM typechecker). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-001 — STG syntax

Status:
- complete

Category:
- stg

Depends on:
- CORE-003

Blocks:
- RTS-001
- RTS-002
- RTS-003
- RTS-004
- RTS-005
- RTS-006
- RTS-007
- RTS-008
- RTS-009
- RTS-010
- RTS-011
- RTS-012
- RTS-013
- RTS-014
- RTS-015
- RTS-016
- RTS-017
- RTS-018
- RTS-019
- RTS-020
- RTS-021

Scope:
- Deliver STG syntax for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG syntax is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-002 — STG value/atom representation

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG value/atom representation for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG value/atom representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-003 — STG closures

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG closures for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG closures is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-004 — STG thunks

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG thunks for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG thunks is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-005 — STG constructors

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG constructors for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG constructors is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-006 — STG let/letrec

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- CORE-REC-001
- CORE-REC-002
- CORE-REC-003
- CORE-REC-004
- RTS-REC-001
- STG-REC-001
- STG-REC-002
- TEST-REC-001
- TEST-REC-002
- TEST-REC-003
- TEST-REC-004

Scope:
- Deliver STG let/letrec for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG let/letrec is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-007 — STG case

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG case for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG case is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-008 — STG primitive operations

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG primitive operations for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG primitive operations is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-009 — STG update flags

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG update flags for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG update flags is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-010 — Core-to-STG lowering

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- LLVM-001
- LLVM-002
- LLVM-003
- LLVM-004
- LLVM-005
- LLVM-006
- LLVM-007
- LLVM-008
- LLVM-009
- LLVM-010
- LLVM-011
- LLVM-012
- LLVM-013
- LLVM-014
- LLVM-015
- LLVM-016
- LLVM-017
- LLVM-018

Scope:
- Deliver Core-to-STG lowering for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- Core-to-STG lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-011 — STG validator

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG validator for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG validator is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-012 — STG pretty-printer

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG pretty-printer for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG pretty-printer is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-013 — STG interpreter/reference evaluator

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver STG interpreter/reference evaluator for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- STG interpreter/reference evaluator is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-014 — laziness test: `const 1 (1 div 0)`

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver laziness test: `const 1 (1 div 0)` for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- laziness test: `const 1 (1 div 0)` is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-015 — laziness test: unused let

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver laziness test: unused let for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- laziness test: unused let is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-016 — case forces scrutinee test

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver case forces scrutinee test for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- case forces scrutinee test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-017 — sharing test

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver sharing test for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- sharing test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-018 — letrec test

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver letrec test for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- letrec test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-019 — black-hole behavior test/documented deviation

Status:
- complete

Category:
- stg

Depends on:
- CORE-003
- TYPE-007

Blocks:
- none

Scope:
- Deliver black-hole behavior test/documented deviation for Lazy semantics and STG while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- black-hole behavior test/documented deviation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M5 (Lazy semantics and STG). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-001 — runtime source layout

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver runtime source layout for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- runtime source layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-002 — closure header design

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- LLVM-001
- LLVM-002
- LLVM-003
- LLVM-004
- LLVM-005
- LLVM-006
- LLVM-007
- LLVM-008
- LLVM-009
- LLVM-010
- LLVM-011
- LLVM-012
- LLVM-013
- LLVM-014
- LLVM-015
- LLVM-016
- LLVM-017
- LLVM-018

Scope:
- Deliver closure header design for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- closure header design is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-003 — function closure layout

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver function closure layout for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- function closure layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-004 — thunk closure layout

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver thunk closure layout for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- thunk closure layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-005 — constructor closure layout

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver constructor closure layout for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- constructor closure layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-006 — indirection/update closure layout

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver indirection/update closure layout for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- indirection/update closure layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-007 — black-hole marker

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver black-hole marker for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- black-hole marker is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-008 — heap allocation API

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver heap allocation API for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- heap allocation API is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-009 — process-lifetime arena or GC decision

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver process-lifetime arena or GC decision for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Process-lifetime allocation is the implemented native runtime policy for the current strict `.hg` and Haskell 2010 executable subsets.
- Strict `.hg` closure allocation routes through `hegglog_alloc_process_lifetime`; Haskell 2010 STG heap allocation routes through `hegglog_hs_alloc_process_lifetime`.
- Allocation failure is checked inside the runtime allocation helper and aborts; generated programs do not free or collect heap objects before process exit.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Completed by centralizing generated native heap allocation behind process-lifetime runtime helpers and documenting GC/arena deferral.

## RTS-010 — enter closure

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver enter closure for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- enter closure is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-011 — force thunk

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver force thunk for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- force thunk is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-012 — update thunk

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver update thunk for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- update thunk is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-013 — case dispatch support

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver case dispatch support for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- case dispatch support is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-014 — checked arithmetic runtime helpers

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver checked arithmetic runtime helpers for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- checked arithmetic runtime helpers is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-015 — checked division runtime helpers

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver checked division runtime helpers for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- checked division runtime helpers is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-016 — runtime error API

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver runtime error API for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- runtime error API is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-017 — print/IO primitive hooks

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- IO-001
- IO-002
- IO-003
- IO-004
- IO-005
- IO-006
- IO-007
- IO-008
- IO-009
- IO-010
- IO-011
- IO-012
- IO-013
- IO-014

Scope:
- Deliver print/IO primitive hooks for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- print/IO primitive hooks is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-018 — runtime build integration

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver runtime build integration for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- runtime build integration is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-019 — runtime leak/ownership documentation

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver runtime leak/ownership documentation for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Runtime ownership documentation enumerates process-lifetime allocation classes and non-owned runtime values.
- The leak policy explicitly states that generated native programs may retain runtime allocations until process exit and currently emit no `free`, finalizers, reference counting, tracing GC, or sweep phase.
- Native LLVM shape tests assert direct `malloc` calls stay inside allocation helpers for both the strict `.hg` and Haskell 2010 STG backends.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Completed by documenting the intentional no-free/no-GC process-lifetime ownership contract and testing the generated LLVM allocation boundary.

## RTS-020 — runtime unit tests

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver runtime unit tests for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- runtime unit tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-021 — native runtime wet tests

Status:
- complete

Category:
- runtime

Depends on:
- STG-001

Blocks:
- none

Scope:
- Deliver native runtime wet tests for Runtime system while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- native runtime wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M6 (Runtime system). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-001 — STG-to-LLVM module boundary

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver STG-to-LLVM module boundary for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`
- `test/e2e/Main.hs`

Acceptance criteria:
- STG-to-LLVM module boundary is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-002 — runtime symbol declarations

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- FFI-001
- FFI-002
- FFI-003
- FFI-004
- FFI-005
- FFI-006
- FFI-007
- FFI-008
- FFI-009

Scope:
- Deliver runtime symbol declarations for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- runtime symbol declarations is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-003 — closure allocation lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver closure allocation lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- closure allocation lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-004 — function entry lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver function entry lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- function entry lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-005 — thunk entry lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver thunk entry lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- thunk entry lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-006 — enter/apply convention lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver enter/apply convention lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- enter/apply convention lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-007 — update lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver update lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- update lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-008 — constructor allocation lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- ADT-001
- ADT-002
- ADT-003
- ADT-004
- ADT-005
- ADT-006

Scope:
- Deliver constructor allocation lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- constructor allocation lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-009 — constructor tag dispatch

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver constructor tag dispatch for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- constructor tag dispatch is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-010 — case lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver case lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- case lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-011 — primitive arithmetic lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver primitive arithmetic lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- primitive arithmetic lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-012 — primitive comparison lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver primitive comparison lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- primitive comparison lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-013 — runtime error lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver runtime error lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- runtime error lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-014 — module entrypoint lowering

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver module entrypoint lowering for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- module entrypoint lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-015 — Haskell `main` entrypoint bridge

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- MOD-001
- MOD-002
- MOD-003
- MOD-004
- MOD-005
- MOD-006
- MOD-007
- MOD-008
- MOD-009
- MOD-010
- MOD-011
- MOD-012
- MOD-013
- MOD-014

Scope:
- Deliver Haskell `main` entrypoint bridge for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- Haskell `main` entrypoint bridge is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-016 — runtime linking through clang

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver runtime linking through clang for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- runtime linking through clang is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-017 — LLVM validation tests

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver LLVM validation tests for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- LLVM validation tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## LLVM-018 — native wet tests for lazy programs

Status:
- complete

Category:
- llvm

Depends on:
- STG-010
- RTS-002

Blocks:
- none

Scope:
- Deliver native wet tests for lazy programs for STG-to-LLVM native codegen while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Backend/LLVM/`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- native wet tests for lazy programs is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- LLVM validation tests
- native wet tests
- emit-LLVM tests
- toolchain negative tests

Documentation updates:
- `docs/llvm-backend-spec.md`
- `docs/llvm-backend.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M7 (STG-to-LLVM native codegen). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## ADT-001 — data declaration representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- PAT-001
- PAT-002
- PAT-003
- PAT-004
- PAT-005
- PAT-006
- PAT-007
- PAT-008
- PAT-009
- PAT-010
- PAT-011
- PAT-012
- PAT-013
- PAT-014
- PAT-015
- PAT-016
- PRELUDE-DATA-001
- PRELUDE-DATA-002
- PRELUDE-DATA-003
- PRELUDE-DATA-004
- PRELUDE-DATA-005
- PRELUDE-DATA-006
- PRELUDE-DATA-007
- PRELUDE-DATA-008
- PRELUDE-DATA-009
- PRELUDE-DATA-010
- PRELUDE-DATA-011
- PRELUDE-DATA-012

Scope:
- Deliver data declaration representation for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- data declaration representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after ADT-005 record field label implementation and should be revised whenever implementation or conformance coverage changes.

## ADT-002 — constructor metadata

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- none

Scope:
- Deliver constructor metadata for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- constructor metadata is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after the PAT-008 implementation and should be revised whenever implementation or conformance coverage changes.

## ADT-003 — polymorphic ADTs

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- none

Scope:
- Deliver polymorphic ADTs for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- polymorphic ADTs is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## ADT-004 — newtype representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- none

Scope:
- Deliver newtype representation for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- newtype representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Implementation notes:
- `newtype` constructors are represented distinctly in Core metadata as `CoreNewtypeConstructor`.
- Construction and pattern unwrapping elaborate to typed Core coercions instead of boxed data constructor values or constructor-case alternatives.
- Core-to-STG lowering erases newtype types to their runtime representation so native code does not allocate an additional wrapper beyond the existing baseline runtime objects.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## ADT-005 — record field labels

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- none

Scope:
- Deliver record field labels for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. The implemented subset parses and renames record declarations, emits selector functions, typechecks complete record construction, supports record patterns with omitted-field wildcards, handles single-field newtype selectors as coercions, and rejects incomplete/unknown/duplicate record construction fields.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Syntax.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`

Acceptance criteria:
- record field labels is implemented, completed, and covered for the supported executable subset.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Record update syntax, partial record construction with bottom-filled fields, and duplicate field labels spanning incompatible constructors remain outside this task.

## ADT-006 — constructor runtime layout

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-015
- LLVM-008

Blocks:
- none

Scope:
- Deliver constructor runtime layout for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- constructor runtime layout is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## ADT-007 — record update expressions

Status:
- complete

Category:
- typechecker

Depends on:
- ADT-005
- CORE-006
- LLVM-008

Blocks:
- none

Scope:
- Record update syntax is represented in parsed and renamed Haskell 2010 ASTs without being confused with record construction.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Record update syntax is represented in parsed and renamed Haskell 2010 ASTs without being confused with record construction.
- The typechecker validates update labels against the scrutinee record type, rejects ambiguous updates, and reports missing-field or non-record diagnostics with source spans.
- Record updates lower to validating Core/STG and execute natively for the supported ADT/newtype record subset while preserving laziness of untouched fields.
- Positive and negative conformance fixtures cover construction, selection, pattern matching, update, ambiguous labels, duplicate update fields, and invalid fields.
- The conformance matrix distinguishes record declarations/selectors/construction/patterns from record updates.

Required tests:
- parser tests
- renamer tests
- typechecker negative tests
- Core/STG validation tests
- native wet/conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Added or refreshed by the tracker reconciliation audit so future work has a stable task ID instead of living only in roadmap prose.
- Implemented as a distinct source and renamed AST form, parsed as postfix record-update syntax after atomic expressions while keeping constructor record syntax separate.
- Typechecking resolves labels through record selectors, rejects duplicate labels, rejects labels drawn from multiple datatypes, reports concrete wrong-record/non-record scrutinees at the update span, and lowers valid updates to typed Core cases that reconstruct only constructors containing all updated labels.
- Runtime constructors in the datatype that do not provide all updated labels intentionally have no generated case alternative, so they fail at runtime as required by Haskell 2010. Untouched fields are forwarded via case binders to preserve laziness.
- Covered by parser tests plus native, runtime-error, and negative conformance fixtures in the manifest and reflected in the conformance matrix.

## PAT-001 — variable patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver variable patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- variable patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-002 — wildcard patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver wildcard patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- wildcard patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-003 — literal patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver literal patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- literal patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-004 — constructor patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- PRELUDE-DATA-001
- PRELUDE-DATA-002
- PRELUDE-DATA-003
- PRELUDE-DATA-004
- PRELUDE-DATA-005
- PRELUDE-DATA-006
- PRELUDE-DATA-007
- PRELUDE-DATA-008
- PRELUDE-DATA-009
- PRELUDE-DATA-010
- PRELUDE-DATA-011
- PRELUDE-DATA-012

Scope:
- Deliver constructor patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- constructor patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-005 — tuple patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver tuple patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- tuple patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-006 — list patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver list patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- list patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-007 — as-patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver as-patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- as-patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-008 — irrefutable/lazy patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Irrefutable/lazy patterns are implemented for function and lambda parameters,
  case alternatives, constructor patterns, record constructor patterns, tuple
  patterns, list patterns, as-patterns, literals, wildcards, and nested lazy
  patterns. Lazy patterns bind variables through lazy Core lets and defer
  constructor mismatch or field projection failure until the demanded binder is
  evaluated.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/manifest.json`
- `test/haskell2010/conformance/patterns/irrefutable-pattern.hs`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- irrefutable/lazy patterns are implemented for the executable Haskell 2010 subset and validated through Core, STG, native, and conformance tests.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- desugaring tests
- Core evaluator lazy/demand tests
- native executable tests
- conformance native-success fixture

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-009 — nested patterns

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver nested patterns for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- nested patterns is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-010 — pattern guards

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver pattern guards for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- pattern guards is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-011 — function equation pattern compilation

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver function equation pattern compilation for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- function equation pattern compilation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-012 — pattern binding compilation

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver pattern binding compilation for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- pattern binding compilation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-013 — pattern-match failure behavior

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver pattern-match failure behavior for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- pattern-match failure behavior is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-014 — exhaustiveness warning placeholder

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Delivered a conservative Haskell 2010 typechecker warning channel for shallow pattern exhaustiveness placeholders. `typecheckModuleToCoreWithWarnings` returns source-spanned warning metadata for case alternatives, function pattern arguments, and lambda pattern arguments when the checker cannot prove coverage from irrefutable patterns, wildcard/default alternatives, or complete constructor families. Native compilation carries the same warning list in `Haskell2010LLVMResult` without changing CLI stderr or runtime semantics.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `docs/current-capabilities.md`
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-status-summary.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-todo.json`

Acceptance criteria:
- Source-spanned exhaustiveness/redundancy warnings are implemented as structured typechecker warnings with rendering and source spans where source spans are available.
- Partial `case` alternatives and partial function/lambda constructor patterns emit warnings; total Bool cases and complete constructor families do not.
- Native compile results and compile CLI rendering expose typecheck warnings without changing successful executable behavior.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Haskell 2010 typechecker warning API tests
- Haskell 2010 native warning propagation tests
- `cabal test hegglog-test --test-options='--hide-successes'`
- `cabal test haskell2010-conformance-test --test-options='--hide-successes'`
- `python3 scripts/validate-haskell2010-todo.py`

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-015 — pattern compiler to Core case

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver pattern compiler to Core case for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- pattern compiler to Core case is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PAT-016 — ADT/pattern native wet tests

Status:
- complete

Category:
- core

Depends on:
- ADT-001
- CORE-006

Blocks:
- none

Scope:
- Deliver ADT/pattern native wet tests for ADTs and pattern matching while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- ADT/pattern native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M8 (ADTs and pattern matching). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-REC-001 — top-level recursive functions

Status:
- complete

Category:
- core

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver top-level recursive functions for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- top-level recursive functions is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-REC-002 — mutually recursive top-level bindings

Status:
- complete

Category:
- core

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver mutually recursive top-level bindings for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- mutually recursive top-level bindings is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-REC-003 — recursive local let/where

Status:
- complete

Category:
- core

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver recursive local let/where for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Core/Syntax.hs`
- `src/Haskell2010/Core/Validate.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/Core/Pretty.hs`
- `test/Main.hs`

Acceptance criteria:
- recursive local let/where is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core validator tests
- Core golden tests
- desugaring tests
- negative Core tests

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CORE-REC-004 — recursive pattern bindings

Status:
- complete

Category:
- core

Depends on:
- STG-006

Blocks:
- none

Scope:
- Delivered recursive pattern bindings for the Haskell 2010 executable subset by lowering non-variable pattern bindings into lazy selector bindings that participate in the normal binding SCC analysis. Pattern selectors can now reference each other and other names in the same recursive group, emit Core `CoreRec` groups when needed, lower through STG, and compile through native execution.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `test/Main.hs`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-status-summary.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-todo.json`

Acceptance criteria:
- Recursive non-variable pattern bindings are accepted by the Haskell 2010 typechecker.
- Pattern-bound selector names participate in recursive SCC analysis and emit Core recursive groups where dependencies require them.
- Recursive pattern binding behavior is checked through Core evaluation, STG lowering/evaluation, and native LLVM/executable tests.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Haskell 2010 recursive pattern binding typechecker test
- Core recursive group assertion
- Core and STG evaluator oracle tests
- Haskell 2010 native LLVM/executable test coverage
- `cabal test hegglog-test --test-options='--hide-successes'`

Documentation updates:
- `docs/full-compiler-definition.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## SURFACE-001 — source surface audit and matrix reconciliation

Status:
- complete

Category:
- testing

Depends on:
- FRONT-020
- REN-009
- CORE-017
- PAT-012
- CORE-REC-003
- CORE-REC-004
- TEST-CONF-001

Blocks:
- none

Scope:
- Audit every currently parsed expression, declaration, local declaration, and pattern form against parser, renamer, typechecker, Core/STG lowering, native execution, and conformance matrix status.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Audit every currently parsed expression, declaration, local declaration, and pattern form against parser, renamer, typechecker, Core/STG lowering, native execution, and conformance matrix status.
- Where implementation already exists, add missing native, Core/STG, or negative fixtures before upgrading matrix rows.
- Where implementation is absent, leave an explicit unsupported-documented fixture or a stable follow-up task ID.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- tracker audit script
- conformance manifest review
- targeted source-surface fixtures

Documentation updates:
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-status-summary.md`

Notes:
- Completed by auditing parsed source-surface forms against parser, renamer, typechecker, Core/STG lowering, native execution, conformance matrix status, and manifest coverage. Added native conformance fixtures for where groups, top-level pattern bindings, local fixity plus expression type signatures, and unit/wildcard patterns. Negative source-surface breadth is covered by TEST-CONF-013, source matrix closure is completed by TEST-CONF-014, and record updates are tracked separately by completed ADT-007.

## SURFACE-002 — user-defined operator bindings and infix calls

Status:
- complete

Category:
- typechecker

Depends on:
- FRONT-003
- FRONT-019
- REN-009
- TYPE-007
- CORE-016

Blocks:
- none

Scope:
- Parenthesized symbolic value bindings and backtick value operators resolve as ordinary term binders where Haskell 2010 permits them.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Parenthesized symbolic value bindings and backtick value operators resolve as ordinary term binders where Haskell 2010 permits them.
- User-defined infix applications elaborate through ordinary function application when the resolved operator is not a built-in special form.
- Local fixity declarations apply to user-defined symbolic and backtick operators through parser, renamer, typechecker, Core/STG, and native execution.
- Unsupported or malformed operator binding shapes report stable parser, renamer, or typechecker diagnostics instead of falling through to generic unsupported Core forms.
- The Haskell 2010 conformance matrix and manifest distinguish built-in operator support from user-defined operator support.

Required tests:
- parser and renamer operator binding tests
- typechecker/Core/STG/native user-defined infix tests
- negative operator binding and fixity diagnostics
- conformance manifest fixtures

Documentation updates:
- docs/haskell2010-todo.md
- docs/haskell2010-conformance-matrix.md
- docs/haskell2010-status-summary.md

Notes:
- Complete. User-defined symbolic and backtick value operators now parse as ordinary binary function bindings, constructor-operator binding syntax is rejected at parse time, and non-built-in infix applications typecheck by elaborating through ordinary function application. Local fixity declarations apply through renaming, Core/STG/native execution, and the wet fixture also locks local shadowing of Prelude `(++)` so built-in special-casing cannot steal user-defined operators.
## SURFACE-003 — where layout position coverage

Status:
- complete

Category:
- frontend

Depends on:
- FRONT-001
- FRONT-020
- REN-009
- CORE-017

Blocks:
- none

Scope:
- Function-binding and case-alternative where groups parse when the where keyword appears on the following layout line in report-shaped source.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Function-binding and case-alternative where groups parse when the where keyword appears on the following layout line in report-shaped source.
- Accepted where groups continue to rename, typecheck, lower through Core/STG, and compile natively for the executable subset.
- Malformed where/layout combinations produce stable parse diagnostics and negative conformance fixtures.
- The conformance matrix explicitly separates implemented where semantics from remaining layout-position gaps.

Required tests:
- parser layout tests
- native conformance fixtures for report-shaped where layout
- negative malformed where/layout fixtures

Documentation updates:
- docs/haskell2010-todo.md
- docs/haskell2010-conformance-matrix.md
- docs/haskell2010-status-summary.md

Notes:
- Complete. Function-binding and case-alternative `where` groups now parse when the `where` keyword appears on the following layout line, while a line-broken `where` at the enclosing declaration/alternative column is rejected as a parse error. The coverage runs through parser tests, Core/STG/native unit examples, e2e wet tests, native conformance fixtures, and negative malformed-layout fixtures.
## STG-REC-001 — recursive closure allocation

Status:
- complete

Category:
- stg

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver recursive closure allocation for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- recursive closure allocation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## STG-REC-002 — recursive thunk semantics

Status:
- complete

Category:
- stg

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver recursive thunk semantics for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/Syntax.hs`
- `src/Haskell2010/STG/Lower.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/Validate.hs`
- `test/Main.hs`

Acceptance criteria:
- recursive thunk semantics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- STG validator tests
- STG evaluator tests
- lazy semantics tests
- black-hole tests

Documentation updates:
- `docs/laziness-and-stg-plan.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## RTS-REC-001 — recursive thunk black-hole behavior

Status:
- complete

Category:
- runtime

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver recursive thunk black-hole behavior for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- recursive thunk black-hole behavior is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-REC-001 — factorial native wet test

Status:
- complete

Category:
- testing

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver factorial native wet test for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- factorial native wet test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-REC-002 — fibonacci native wet test

Status:
- complete

Category:
- testing

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver fibonacci native wet test for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- fibonacci native wet test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-REC-003 — recursive list length native wet test

Status:
- complete

Category:
- testing

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver recursive list length native wet test for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- recursive list length native wet test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-REC-004 — mutual recursion native wet test

Status:
- complete

Category:
- testing

Depends on:
- STG-006

Blocks:
- none

Scope:
- Deliver mutual recursion native wet test for Recursion and letrec while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- mutual recursion native wet test is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M9 (Recursion and letrec). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-001 — unit type

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver unit type for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleInterface.hs`
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/ModuleGraph.hs`
- `test/Main.hs`

Acceptance criteria:
- unit type is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-002 — tuples through required arities

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver tuples through required arities for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- tuples through required arities is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-003 — list constructors

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- PRELUDE-001
- PRELUDE-002
- PRELUDE-003
- PRELUDE-004
- PRELUDE-005
- PRELUDE-006
- PRELUDE-007
- PRELUDE-008
- PRELUDE-009
- PRELUDE-010
- PRELUDE-011
- PRELUDE-012
- PRELUDE-013
- PRELUDE-014
- PRELUDE-015
- PRELUDE-016
- PRELUDE-017
- PRELUDE-018

Scope:
- Deliver list constructors for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list constructors is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-004 — list syntax desugaring

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver list syntax desugaring for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list syntax desugaring is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-005 — tuple syntax desugaring

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver tuple syntax desugaring for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- tuple syntax desugaring is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-006 — Char runtime representation

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver boxed native/runtime representation for `Char` in the current Haskell 2010 executable subset: `Char` literals lower to native boxed objects, literal `Char` case alternatives dispatch natively, `Eq Char` dictionaries lower through primitive equality, and scalar `main :: Char` prints through the native executable path. Keep broader `String = [Char]`, full Unicode IO semantics, and wider Prelude `Char` APIs in later tasks.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/e2e/programs/haskell2010/`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Char` literals, `Char` literal cases, `Eq Char`, and scalar `main :: Char` are implemented in Core/STG/native execution for the current executable subset.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Completed with boxed native `Char` values, an `Eq Char` built-in dictionary, scalar `Char` root printing, conformance fixtures, and default/no-egglog native wet tests. Broader `String = [Char]` and Unicode/output-library behavior remain tracked by later M10 and Prelude/IO tasks.

## PRELUDE-DATA-007 — String = [Char]

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- IO-001
- IO-002
- IO-003
- IO-004
- IO-005
- IO-006
- IO-007
- IO-008
- IO-009
- IO-010
- IO-011
- IO-012
- IO-013
- IO-014

Scope:
- Source string literals and string literal patterns desugar to ordinary `[]`/`(:)` lists of boxed `Char` before Core. Core and STG evaluators produce list-of-`Char` values for source strings and built-in `show` results, and native LLVM emits list constructors rather than generated per-literal string payload globals. `putStrLn` continues to consume list-of-`Char` values while retaining the legacy internal string payload path for compatibility with older direct STG forms.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/Main.hs`
- `test/e2e/programs/haskell2010/string-char-list.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Source string expressions elaborate to list constructors, not Core/STG string payload literals.
- String literal patterns elaborate through ordinary list-pattern matching.
- `length "..."`, `length (show 42)`, and native execution of the same program pass through Core, STG, and LLVM.
- Native LLVM no longer emits generated `@haskell2010_str_` globals or calls the special string payload allocator for source string literals.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Completed with source `String` literals and string literal patterns represented as ordinary `[Char]` values across typechecking, Core evaluation, STG evaluation, native LLVM, conformance, and wet tests. Broader Unicode text IO, exhaustive escape fidelity beyond the current parser/runtime subset, and additional string/list library behavior remain tracked by later Prelude/IO tasks.

## PRELUDE-DATA-008 — arithmetic sequences

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver the executable arithmetic sequence surface for supported `Int`, `Char`, and generated derived-enumeration ranges while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Public `Enum` dictionaries are tracked under TC-018, and derived `Enum` range behavior is now completed under TC-031.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- arithmetic sequences is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Completed for the executable subset with `[a..]`, `[a,b..]`, `[a..z]`, and `[a,b..z]` over `Int`, `Char`, and generated derived `Enum` dictionaries; sequence helpers preserve ascending/descending bounded behavior and lazy open-range consumption through Core, STG, and native LLVM. TC-018 reuses these helpers for the public `Enum Int` and `Enum Char` dictionaries, and TC-031 routes derived-enumeration ranges through the same `Enum` method surface.

## PRELUDE-DATA-009 — list comprehensions

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver list comprehensions for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list comprehensions is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Completed for the executable subset with list comprehension parsing, generator-binder renamer scoping, Bool guards, `let` qualifiers, nested generators, tuple/list/constructor/literal/refutable pattern filtering, and Core/STG/native execution. The lowering uses local recursive list walkers with accumulator tails, so output order is preserved without requiring a separate append helper. Native wet tests cover `Int` and `Char` range generators, `String` results, `Maybe` pattern filters, tuple patterns, nested refutable patterns, and local let qualifiers.

## PRELUDE-DATA-010 — list native wet tests

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver list native wet tests for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-011 — tuple native wet tests

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Deliver tuple native wet tests for Lists, tuples, Char, String while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- tuple native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-DATA-012 — String literal native wet tests

Status:
- complete

Category:
- libraries

Depends on:
- ADT-001
- PAT-004

Blocks:
- none

Scope:
- Lock the current `String = [Char]` native behavior with executable fixtures for direct source string output, list functions over strings, built-in `show` results consumed by `putStrLn`, explicit `Char` cons patterns over string values, and string literal patterns. Coverage lives in the unit native example corpus, the e2e wet suite, and the Haskell 2010 conformance manifest with default and `--no-egglog` native runs.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/e2e/programs/haskell2010/string-output.hs`
- `test/e2e/programs/haskell2010/string-show-output.hs`
- `test/e2e/programs/haskell2010/string-char-patterns.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Native example execution covers direct string literals, reversed string literals, and `length` over string/show output.
- Native example execution covers `putStrLn (show 42)` and `putStrLn (show False)`.
- Native example execution covers explicit `Char` cons patterns and string literal patterns over source string values.
- E2E wet tests run the new string fixtures in default and `--no-egglog` modes with emit-LLVM coverage.
- Haskell 2010 conformance manifest includes the same exact-stdout native-success fixtures.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M10 (Lists, tuples, Char, String). Completed with direct native executable coverage for string literals as `[Char]`, list functions over strings, show-produced strings, `putStrLn`, explicit char-list patterns, string literal patterns, default/no-egglog runs, and emit-LLVM wet checks. Broader Unicode text IO and exhaustive escape fidelity remain tracked by later Prelude/IO tasks; `(++)` is now covered by PRELUDE-013.

## TC-001 — class declaration representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver class declaration representation for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- class declaration representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-002 — instance declaration representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver instance declaration representation for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- instance declaration representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-003 — superclass representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver superclass representation for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- superclass representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the current single-parameter class surface: class dictionaries now store superclass dictionaries before method fields, built-in `Ord` and `Num` expose their Haskell 2010 superclass edges, and dictionary resolution can project superclass dictionaries from local and instance dictionaries. Validated by unit, Core/STG/native, and conformance coverage.

## TC-004 — method signatures

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver method signatures for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- method signatures is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-005 — default methods

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver default methods for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- default methods is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for default method bindings that use the class type variable and existing supported expression surface. Instance dictionaries fill omitted methods from class defaults, including defaults that call superclass methods through dictionary projection. Method-specific constraints and instance contexts remain separate unsupported/deferred items.

## TC-006 — constraint solver

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver constraint solver for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- constraint solver is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-007 — instance resolution

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver instance resolution for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- instance resolution is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-008 — overlapping instance rejection per Haskell 2010

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver overlapping instance rejection per Haskell 2010 for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- overlapping instance rejection per Haskell 2010 is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the supported instance-head language: duplicate instances and unifiable overlapping instance heads are rejected, including overlap with built-in and structural `Show [a]` dictionaries. Validated by negative type-class dictionary tests.

## TC-009 — dictionary type representation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver dictionary type representation for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- dictionary type representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-010 — dictionary value generation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver dictionary value generation for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- dictionary value generation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-011 — method selection lowering

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver method selection lowering for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- method selection lowering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-012 — constraint passing in Core

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver constraint passing in Core for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- constraint passing in Core is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-013 — Eq

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- PRELUDE-001
- PRELUDE-002
- PRELUDE-003
- PRELUDE-004
- PRELUDE-005
- PRELUDE-006
- PRELUDE-007
- PRELUDE-008
- PRELUDE-009
- PRELUDE-010
- PRELUDE-011
- PRELUDE-012
- PRELUDE-013
- PRELUDE-014
- PRELUDE-015
- PRELUDE-016
- PRELUDE-017
- PRELUDE-018

Scope:
- Deliver Eq for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Eq is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-014 — Ord

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver Ord for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Ord is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-015 — Show

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Broaden the supported `Show` surface beyond the original exact `Int`/`Bool` dictionaries while preserving explicit dictionary passing. The implemented executable subset now includes exact `Show Char`, exact `Show String` with quoted string output, a generated structural `Show a => Show [a]` dictionary, nested list/string output such as `[String]`, `print` through the broadened dictionaries, and numeric-list defaulting for examples like `show [1, 2, 3]`.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/e2e/programs/haskell2010/broad-show.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Built-in `Show Char` and `Show String` dictionaries typecheck, elaborate to Core dictionaries, evaluate through Core/STG, and run natively.
- Generic structural `Show a => Show [a]` dictionary synthesis supports `Show [Int]`, `Show [Bool]`, and nested `Show [String]` without finite ad hoc list instances.
- `print` uses the broadened dictionaries for `Char` and `String`.
- Numeric-list defaulting supports `show [1, 2, 3]` in the executable `Int` subset.
- Haskell 2010 conformance and e2e wet tests cover the broadened Show surface in default and `--no-egglog` native modes.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Completed for the broadened executable Show subset: exact `Int`, `Bool`, `Char`, and `String`, plus generated list dictionaries. TC-029 later promoted this surface to the Report-shaped `showsPrec`/`show`/`showList` hierarchy with derived constructor precedence and supported lexical escaping.

## TC-016 — Close Read documented deviation

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Close the historical Haskell 2010 `Read` documented deviation now that TC-030 has implemented coherent `ReadS`/lexical parser support, `readsPrec`/`readList` methods, standard supported instances, and derived `Read` synthesis. The tracker, matrix, docs, and conformance suite must no longer present `Read` as an active unsupported/deviation boundary.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- TC-016 is marked complete rather than documented deviation.
- Read is no longer listed as an active Haskell 2010 Prelude/typeclass deviation.
- The old unsupported Read conformance fixture is removed and replaced by positive standard and derived Read coverage.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to TC-030 for implemented Read work and to concrete LIB tasks for remaining library gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete. TC-016 is closed as an active deviation: `Read` is no longer represented as unsupported in the current Haskell 2010 tracker, matrix, or conformance manifest. TC-030 owns the implemented Read surface, including `Read` dictionaries, lexical read helpers, standard supported instances, and derived `Read`; the old unsupported fixture has been replaced by positive native conformance coverage.

## TC-017 — Num

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver Num for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Num is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-018 — Enum

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver Enum for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Enum is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the current executable Prelude surface: `Enum` is exported as a built-in class with `succ`, `pred`, `toEnum`, `fromEnum`, `enumFrom`, `enumFromThen`, `enumFromTo`, and `enumFromThenTo`; built-in `Int` and `Char` instances share the arithmetic-sequence helpers and are validated through Core, STG, native, and conformance tests. TC-031 now completes generated derived `Enum` dictionaries for nullary-constructor data declarations.

## TC-019 — Bounded

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver Bounded for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Bounded is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the current executable Prelude surface: `Bounded` is exported as a built-in class with `minBound` and `maxBound`, with built-in instances for `Int`, `Char`, and `Bool`. Derived `Bounded` is now covered by TC-032.

## TC-020 — Monad

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver Monad for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Implemented slice:
- Built-in higher-kinded `Monad` class metadata with `return`, `(>>=)`, `(>>)`,
  and `fail`.
- Built-in `Monad IO`, `Monad Maybe`, and `Monad []` dictionaries using ordinary
  dictionary constructors/selectors.
- Generic `do` desugaring through Monad selectors for expression statements,
  local `let`, bind statements, and refutable pattern-bind failure.
- Core/STG/native validation and execution support for `failIO#` and list type
  constructor normalization needed by `Monad []`.
- Positive native conformance for IO/Maybe/list do-notation and a negative
  duplicate built-in instance fixture.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Monad is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-021 — numeric literal overloading

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver numeric literal overloading for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- numeric literal overloading is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-022 — defaulting

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver defaulting for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- defaulting is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-023 — derived Eq

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Derived `Eq` now synthesizes dictionary bindings for supported `data` and `newtype` declarations. The implementation covers nullary and product constructors, parameterized instances with context dictionaries, recursive data, `String` fields through structural list `Eq`, and generated `(==)`/`(/=)` methods while preserving the current .hg substrate and documented Haskell 2010 executable-subset behavior.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- derived Eq is implemented for the supported executable subset and represented in unit, native, and conformance coverage.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-024 — derived Ord

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Derived `Ord` now synthesizes dictionaries for supported `data` and `newtype` declarations. The implementation follows Haskell 2010 declaration-order constructor comparison and lexicographic product-field comparison, emits `Eq` superclass dictionaries, supports parameterized and recursive instances, handles `String` fields through structural `Ord [a]`, and generates `compare`, `<`, `<=`, `>`, `>=`, `max`, and `min` methods for the executable subset.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- derived Ord is implemented for the supported executable subset and represented in unit, native, and conformance coverage.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the current executable subset: supported data/newtype declarations can derive `Ord` when an `Eq` superclass dictionary is available, and structural list ordering supports string and list-backed fields. Derived `Show` is covered by TC-025, derived `Read` by TC-030, derived `Enum` by TC-031, and derived `Bounded` by TC-032.

## TC-025 — derived Show

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver derived `Show` for the supported Type classes and dictionaries executable subset while preserving the current `.hg` substrate. The compiler synthesizes ordinary `Show` dictionaries for supported `data` and `newtype` declarations, including nullary constructors, product constructors, records, recursive data, `String` fields, list-backed contexts, and parameterized instances.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- derived `Show` is implemented for the supported executable subset and represented in unit, native, and conformance coverage.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the derived executable subset: generated `Show` dictionaries return ordinary `[Char]` values and compose through the structural list/string `Show` surface. TC-029 later promoted derived `Show` to the Report-shaped `showsPrec`/`show`/`showList` hierarchy, so product-field parentheses now follow the active precedence context instead of the former conservative rendering.

## TC-026 — class negative tests

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver class negative tests for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- class negative tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-027 — dictionary Core validation tests

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver dictionary Core validation tests for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- dictionary Core validation tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-028 — typeclass native wet tests

Status:
- complete

Category:
- typechecker

Depends on:
- TYPE-016
- CORE-009

Blocks:
- none

Scope:
- Deliver typeclass native wet tests for Type classes and dictionaries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Syntax.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- typeclass native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TC-029 — report-shaped Show hierarchy

Status:
- complete

Category:
- typechecker

Depends on:
- TC-015
- TC-025
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- `Show` exposes and uses the Haskell 2010 method shape around `showsPrec`, `show`, `showList`, and `shows` without breaking existing executable `show` and `print` behavior.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `test/Main.hs`
- `test/e2e/programs/haskell2010/`
- `test/haskell2010/conformance/`
- `test/haskell2010/conformance/manifest.json`
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- `Show` exposes and uses the Haskell 2010 method shape around `showsPrec`, `show`, `showList`, and `shows` without breaking existing executable `show` and `print` behavior.
- Generated and built-in Show dictionaries implement precedence-sensitive constructor rendering and report-compatible character/string/list escaping for the supported value surface.
- Derived `Show` uses the same method hierarchy instead of a separate string-only path.
- Native and conformance tests cover scalar, list, string, product, record, recursive, and precedence-sensitive output.
- The matrix no longer describes full `showsPrec`/`showList` as future work once this task is complete.

Required tests:
- typechecker unit tests
- dictionary/Core validation tests
- native wet tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. The generated Prelude now exposes `shows` and the `Show` class uses
  the Report-shaped `showsPrec`, `show`, and `showList` dictionary layout.
  Built-in `Show Int`, `Show Bool`, `Show Char`, exact `Show String`,
  generated structural list dictionaries, and supported derived data/newtype
  dictionaries all use the same method hierarchy. Derived product constructors
  honor application precedence, nested constructor fields use `showsPrec 11`,
  records render with record-construction syntax, `ShowS` continuations are
  respected for lists, and native/conformance coverage locks scalar, list,
  string, product, record, recursive, precedence-sensitive, and supported
  escaping behavior.

## TC-030 — Read implementation

Status:
- complete

Category:
- typechecker

Depends on:
- TC-016
- TC-029
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- `Read` is promoted from documented deviation to implemented class support with `ReadS`, `readsPrec`, `readList`, `reads`, and `read` where required by the Report surface.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- `Read` is promoted from documented deviation to implemented class support with `ReadS`, `readsPrec`, `readList`, `reads`, and `read` where required by the Report surface.
- Lexical read parsing accepts report-compatible whitespace and token forms for supported scalar, list, tuple, and ADT values.
- Built-in and derived `Read` dictionaries lower through Core/STG/native using the same dictionary model as other classes.
- Invalid and partial reads have documented behavior and conformance fixtures.
- The existing unsupported `Read` fixture is removed or converted only when replacement positive and negative coverage exists.

Required tests:
- typechecker unit tests
- parser/lexer read tests
- dictionary/Core validation tests
- native wet tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M11 (Type classes and dictionaries). Complete for the current executable subset: the generated Prelude exposes `ReadS`, `readsPrec`, `readList`, `reads`, `read`, `lex`, and `readParen`; built-in dictionaries cover `Int`, `Bool`, `Char`, `String`, structural lists, `Ordering`, and unit; derived `Read` synthesizes dictionaries for supported data/newtype declarations including nullary constructors, products, records, recursive data, `String` fields, list-backed contexts, and precedence-sensitive nested constructors. Core/STG/native unit tests and manifest-backed native fixtures cover successful parsing, partial-read behavior, token-boundary rejection, and derived constructor parsing. Remaining richer numeric read helpers and broader library exports stay owned by their LIB tasks.

## TC-031 — derived Enum

Status:
- complete

Category:
- typechecker

Depends on:
- TC-018
- ADT-001

Blocks:
- none

Scope:
- Derived `Enum` is generated for eligible nullary-constructor data declarations with Haskell 2010 constructor ordering semantics. Generated dictionaries implement `succ`, `pred`, `toEnum`, `fromEnum`, `enumFrom`, `enumFromThen`, `enumFromTo`, and `enumFromThenTo`; source arithmetic-sequence syntax dispatches through the same `Enum` methods so user-derived enumeration ranges run through Core, STG, and native LLVM.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Derived `Enum` is generated for eligible nullary-constructor data declarations with Haskell 2010 constructor ordering semantics.
- Generated dictionaries implement `succ`, `pred`, `toEnum`, `fromEnum`, and enumeration methods with correct bounds/error behavior for the supported runtime.
- Invalid deriving cases, including constructors with fields and unsupported declaration shapes, fail with stable diagnostics.
- Native and conformance fixtures cover positive and negative derived `Enum` cases.
- The matrix records both public built-in `Enum` instances and generated derived `Enum` dictionaries.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- native wet tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Nullary-constructor data declarations can derive `Enum`; the generated dictionaries use declaration-order constructor indices, report-shaped `succ`/`pred`/`toEnum` bounds errors, `fromEnum`, and range methods based on `map toEnum` over integer ranges. The compiler rejects derived `Enum` for constructors with fields, and unit, conformance, e2e, default Egglog, and `--no-egglog` native coverage now lock the behavior down.

## TC-032 — derived Bounded

Status:
- complete

Category:
- typechecker

Depends on:
- TC-019
- ADT-001

Blocks:
- none

Scope:
- Derived `Bounded` is generated for eligible all-nullary enumerations, single-constructor product types, records, and supported newtype shapes according to Haskell 2010 rules.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Derived `Bounded` is generated for eligible all-nullary enumerations, single-constructor product types, records, and supported newtype shapes according to Haskell 2010 rules.
- Generated dictionaries implement `minBound` and `maxBound` with constructor-order and field-bound semantics where applicable.
- Invalid deriving cases fail with stable diagnostics.
- Native and conformance fixtures cover positive and negative derived `Bounded` cases.
- The matrix records both public built-in `Bounded` instances and derived `Bounded` support.

Required tests:
- typechecker unit tests
- negative type tests
- dictionary/Core validation tests
- native wet tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. All-nullary data declarations derive `Bounded` by selecting the first and last constructors in declaration order. Single-constructor product, record, and newtype declarations derive `minBound`/`maxBound` by applying the constructor to field-wise `minBound`/`maxBound` calls, which produces ordinary field `Bounded` constraints for parameterized products. Mixed or multi-constructor non-enumeration declarations are rejected with a stable diagnostic, and Core, STG, native, e2e, default Egglog, `--no-egglog`, and conformance fixtures cover the positive and negative paths.

## TC-033 — numeric class hierarchy expansion

Status:
- complete

Category:
- typechecker

Depends on:
- TC-017
- TC-021
- TC-022

Blocks:
- none

Scope:
- Broaden the numeric class hierarchy beyond the current executable `Num Int` path, including the standard superclass/method relationships needed for Haskell 2010 numeric code.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Broaden the numeric class hierarchy beyond the current executable `Num Int` path, including the standard superclass/method relationships needed for Haskell 2010 numeric code.
- Defaulting follows Haskell 2010 rules for the expanded numeric universe and keeps the current checked-runtime guarantees for bounded executable `Int` behavior.
- Unsupported numeric types or methods have explicit diagnostics rather than silent fallback.
- Core/STG/native and conformance fixtures cover overloaded literals, default declarations, numeric methods, and invalid ambiguity cases.
- Docs clearly separate implemented numeric support from remaining arbitrary-precision or floating behavior.

Required tests:
- typechecker unit tests
- numeric defaulting tests
- dictionary/Core validation tests
- native wet tests
- conformance tests

Documentation updates:
- `docs/type-inference.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. The built-in numeric hierarchy now includes report-shaped `Real`
  and `Integral` classes above the existing executable `Num Int` path. The
  `Int` dictionaries implement `toRational`, `quot`, `rem`, `div`, `mod`,
  `quotRem`, `divMod`, and `toInteger`, with Core/STG/native lowering for a
  checked remainder primitive and Haskell 2010 `quot`/`rem` versus `div`/`mod`
  semantics. Defaulting recognizes `Real` and `Integral` constraints in the
  supported standard-class numeric universe, `Integer` defaults continue to
  map to the checked executable `Int` representation, and invalid default
  declarations remain explicit compile errors. Fractional, floating,
  arbitrary-precision `Integer`, and full `Ratio`/`Rational` behavior remain
  tracked as future library/runtime work rather than being silently claimed.

## PRELUDE-001 — Prelude module strategy

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Prelude module strategy for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Prelude module strategy is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-002 — implicit Prelude import

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver implicit Prelude import for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- implicit Prelude import is implemented for the built-in Prelude surface: modules
  without an explicit `Prelude` import are renamed as if they had `import
  Prelude`, and any explicit `Prelude` import suppresses that implicit import.
- Explicit Prelude import lists, empty import lists, `hiding`, duplicate imports
  of the same entity, and `qualified` imports are handled by the same import
  filtering rules used for ordinary modules.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Complete for the current built-in
  Prelude surface: renamer tests cover implicit, explicit, qualified,
  cumulative, and duplicate Prelude imports; conformance fixtures cover native
  implicit/explicit/qualified Prelude imports and negative empty/qualified
  unqualified-name failures.

## PRELUDE-003 — Bool

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Bool for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Bool is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-004 — Maybe

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Maybe for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Maybe is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-005 — Either

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Either for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Either is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-006 — Ordering

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Ordering for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Ordering is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-007 — list functions: map

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver list functions: map for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- list functions: map is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-008 — foldr

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver foldr for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- foldr is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-009 — foldl

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver foldl for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- foldl is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Generated Prelude `foldl` now has the Haskell 2010 source shape
  `(b -> a -> b) -> b -> [a] -> b`, elaborates to recursive Core, lowers
  through STG/native, and preserves lazy accumulator behavior for ignored
  accumulator arguments. Core, STG, LLVM/native, e2e, and conformance fixtures
  cover left-to-right accumulator order, polymorphic accumulator/list element
  types, empty-list behavior, and native default/no-egglog execution.

## PRELUDE-010 — length

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver length for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- length is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-011 — filter

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver filter for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- filter is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-012 — reverse

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver reverse for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- reverse is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-013 — append

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver append for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. `(++)` is available as a polymorphic list append function, as an infix operator with Prelude fixity, as a parenthesized symbolic variable, and in left/right operator sections; strings work through the existing `String = [Char]` representation.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- append is implemented for supported list and string programs and represented in unit, native, conformance, and wet-test coverage.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Complete for the current executable subset: generated Core implements `(++)` recursively over list constructors, and tests cover list append, string append, right-associativity, prefix `(++)`, and operator sections through Core/STG/native execution.

## PRELUDE-014 — function combinators: id, const, ., $

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver function combinators: id, const, ., $ for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- function combinators: id, const, ., $ is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-015 — boolean operators with short-circuit semantics

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver boolean operators with short-circuit semantics for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- boolean operators with short-circuit semantics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-016 — numeric functions

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver numeric functions for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- numeric functions is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-017 — standard library module layout

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver standard library module layout for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- standard library module layout is implemented for the current executable
  subset with a generated/importable `Prelude` module interface owned outside
  the renamer.
- The module interface data model includes exported names, child exports,
  fixities, and explicit instance exports consumed by MOD-009.
- Reserved Haskell 2010 standard modules are documented without being silently
  exposed as empty importable modules.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-standard-library-layout.md`

Notes:
- Milestone M12 (Prelude and libraries). Complete for the current executable
  subset: generated `Prelude` exports/fixities/children are centralized in
  `Haskell2010.StandardLibrary`, and `Haskell2010.ModuleInterface` carries the
  instance boundary used by MOD-009.

## PRELUDE-018 — Prelude conformance tests

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- TC-013

Blocks:
- none

Scope:
- Deliver Prelude conformance tests for Prelude and libraries while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Prelude conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M12 (Prelude and libraries). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## PRELUDE-019 — Prelude function completion

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-009
- PRELUDE-018

Blocks:
- none

Scope:
- Fill high-value missing Prelude functions beyond the currently generated executable subset, continuing after `foldl` and tracking each newly claimed function in the matrix.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Renamer.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/`
- `test/e2e/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Fill high-value missing Prelude functions beyond the currently generated executable subset, continuing after `foldl` and tracking each newly claimed function in the matrix.
- Implemented functions use ordinary Haskell 2010 source/Core/STG/library semantics rather than backend-specific shortcuts where practical.
- Strictness, laziness, error behavior, and list-fusion-sensitive behavior are documented for every supported function.
- Native and conformance fixtures cover each newly claimed Prelude function.
- Remaining Prelude functions stay explicitly unclaimed or receive dedicated task IDs.

Required tests:
- library unit tests
- Core/STG preservation tests
- native wet tests
- Prelude conformance tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. The generated Prelude now claims and emits ordinary Core bindings
  for `($)`, `(.)`, `flip`, `head`, `tail`, `null`, `fst`, and `snd` in
  addition to the previously supported list functions. `($)`, `(.)`, and
  `flip` are lazy higher-order wrappers with no backend shortcut. `head`,
  `tail`, and `null` case-analyze ordinary lists; `head` and `tail` intentionally
  preserve partial-selector behavior by omitting the empty-list alternative so
  forced empty-list use becomes the same no-match runtime failure as other
  partial pattern matches. `fst` and `snd` case-analyze ordinary pair tuples and
  force only the tuple header plus the selected field. No list-fusion rewrites
  are introduced. Core, STG, LLVM/native, e2e, and conformance fixtures cover
  the successful function slice plus empty-list `head` native runtime failure.
  Remaining Prelude functions stay unclaimed and continue under PRELUDE-020,
  TEST-CONF-015, or later dedicated library tasks.

## PRELUDE-020 — standard library module expansion

Status:
- complete

Category:
- libraries

Depends on:
- PRELUDE-017
- MOD-003

Blocks:
- none

Scope:
- Generated/importable standard-library module interfaces expand beyond `Prelude` to the modules required by the Haskell 2010 Report as implementation support lands.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Generated/importable standard-library module interfaces expand beyond `Prelude` to the modules required by the Haskell 2010 Report as implementation support lands.
- Module ownership stays explicit: no standard module is silently importable with an empty or fake surface.
- Import, export, child export, fixity, and instance behavior for standard modules follows the same `ModuleInterface` model as user modules.
- Docs and conformance fixtures identify every standard module as implemented, partially implemented, reserved, or unsupported-documented.
- The standard-library layout doc remains synchronized with the generated module interfaces.

Required tests:
- standard-library interface unit tests
- module conformance tests
- backlog validator
- matrix review

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Added or refreshed by the tracker reconciliation audit so future work has a stable task ID instead of living only in roadmap prose.

## LIB-001 — Control.Monad report completion

Status:
- complete

Category:
- libraries

Depends on:
- TC-020
- PRELUDE-020

Blocks:
- none

Scope:
- Complete the Haskell 2010 `Control.Monad` surface around `Functor`, `Monad`, `mapM`, `mapM_`, `sequence`, `sequence_`, `(=<<)`, and related report combinators for supported Monad instances.

Non-goals:
- Do not add transformer libraries or post-2010 APIs.
- Do not claim polymorphic behavior without Core/STG/native tests.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`
- `test/e2e/programs/haskell2010/control-monad.hs`

Acceptance criteria:
- `Control.Monad` exports the full Haskell 2010 report surface for Functor, Monad, and standard monadic combinators.
- `mapM`, `mapM_`, `sequence`, `sequence_`, `(=<<)`, and related combinators compile through Core/STG/native for supported Monad instances.
- Generated module interfaces, Prelude exports, fixities, conformance matrix rows, and fixtures agree on the supported surface.

Required tests:
- module import conformance tests
- Monad native wet tests
- negative unsupported-boundary tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. `Control.Monad` now exports `Functor(fmap)`, `Monad(..)`, `MonadPlus(..)`, and the Haskell 2010 monadic combinator surface for supported `IO`, `Maybe`, and list instances. Prelude also exposes the Report monadic exports `mapM`, `mapM_`, `sequence`, `sequence_`, and `(=<<)`. The implementation has generated Core bindings, built-in `MonadPlus` dictionaries for `Maybe` and lists, interface/fixity coverage, conformance coverage, and a broad native e2e fixture covering every new combinator.

## LIB-002 — Data.List report completion

Status:
- not started

Category:
- libraries

Depends on:
- PRELUDE-019
- PRELUDE-020

Blocks:
- none

Scope:
- Complete the Haskell 2010 `Data.List` report API beyond the generated list/function slice.

Non-goals:
- Do not introduce fusion rewrites or optimizer-specific behavior as part of the library semantics.
- Do not weaken existing list laziness or partial-function boundaries.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.List` exports the Haskell 2010 list API beyond the current generated slice.
- List transformations, folds, scans, sublists, searches, indexing, zips, unzips, special-list helpers, and generic functions have real implementations or explicit narrower deviations.
- Partial functions and bottom behavior are documented and tested through native or runtime-error fixtures.

Required tests:
- `Data.List` conformance fixtures
- native wet tests
- runtime-error tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to make remaining list-library breadth explicit.

## LIB-003 — Data.Maybe report completion

Status:
- not started

Category:
- libraries

Depends on:
- PRELUDE-DATA-003
- PRELUDE-020

Blocks:
- none

Scope:
- Complete the Haskell 2010 `Data.Maybe` module surface using the existing built-in `Maybe` constructors and dictionary machinery.

Non-goals:
- Do not change the representation of `Maybe`.
- Do not hide partial `fromJust` behavior behind total helpers.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Maybe` exports `Maybe(..)`, `maybe`, `isJust`, `isNothing`, `fromJust`, `fromMaybe`, `maybeToList`, `listToMaybe`, `catMaybes`, and `mapMaybe` where required by the Haskell 2010 Libraries Report.
- Partial `fromJust` behavior has an explicit runtime-error fixture.
- Prelude and `Data.Maybe` imports share the same implemented definitions without ambiguity.

Required tests:
- `Data.Maybe` conformance fixtures
- native wet tests
- runtime-error tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to track the currently partial generated `Data.Maybe` interface.

## LIB-004 — Data.Char report completion

Status:
- not started

Category:
- libraries

Depends on:
- PRELUDE-DATA-007
- PRELUDE-020

Blocks:
- none

Scope:
- Implement the Haskell 2010 `Data.Char` classification, conversion, digit, numeric representation, and string representation APIs.

Non-goals:
- Do not claim full Unicode behavior without explicit tests and documented character-table policy.
- Do not implement Show/Read escape behavior separately from TC-029 and TC-030.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Char` exports report-compatible character classification, case conversion, digit, numeric representation, and string representation functions.
- Character ordinal behavior, escape rendering, and lexical read helpers agree with Show/Read tasks where they overlap.
- Reserved `Data.Char` imports are replaced by positive and negative fixtures once implemented.

Required tests:
- `Data.Char` conformance fixtures
- Show/Read character tests
- native wet tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015; the unsupported fixture keeps this reserved module explicit.

## LIB-005 — Data.Array and Data.Ix report completion

Status:
- not started

Category:
- libraries

Depends on:
- PRELUDE-020
- TC-031

Blocks:
- none

Scope:
- Implement `Data.Ix` and immutable non-strict `Data.Array` per the Haskell 2010 Libraries Report.

Non-goals:
- Do not implement mutable arrays or post-2010 array packages.
- Do not add boxed-array runtime behavior without clear forcing and bounds semantics.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Ix` exports the `Ix` class and `range`/`index`/`inRange`/`rangeSize` behavior with derived `Ix` support where required.
- `Data.Array` exports immutable non-strict arrays, construction, access, updates, derived arrays, and report-specified errors.
- Array and Ix semantics are covered by native and negative conformance fixtures.

Required tests:
- `Data.Ix` conformance fixtures
- `Data.Array` native wet tests
- negative bounds/error tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to replace unnumbered array/Ix future work.

## LIB-006 — Data.Bits report completion

Status:
- not started

Category:
- libraries

Depends on:
- TC-033
- PRELUDE-020

Blocks:
- none

Scope:
- Implement the Haskell 2010 `Data.Bits` class and operations for supported integral representations.

Non-goals:
- Do not silently generalize over numeric types without checked dictionary support.
- Do not rely on undefined target shift behavior.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Bits` exports the Haskell 2010 bit class and operations for supported integral types.
- Bit shifts, rotates, complements, bit tests, and pop-count style helpers have checked behavior for fixed-width and Int-backed representations.
- Unsupported type combinations fail explicitly until broader numeric representations are implemented.

Required tests:
- `Data.Bits` conformance fixtures
- native wet tests
- negative type tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 so the reserved `Data.Bits` module has a numbered owner.

## LIB-007 — Data.Ratio and Rational report completion

Status:
- not started

Category:
- libraries

Depends on:
- TC-033
- PRELUDE-020

Blocks:
- none

Scope:
- Replace the current executable-subset rational pair behavior with a report-shaped `Ratio`/`Rational` library surface.

Non-goals:
- Do not implement floating decimal parsing here.
- Do not change `Integral Int` behavior without preserving existing tests.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Ratio` exports `Ratio`, `Rational`, `(%)`, `numerator`, `denominator`, and report-compatible normalization behavior.
- Prelude `Rational` and `toRational` use the same representation instead of the current executable-subset pair encoding.
- Zero denominator and sign normalization behavior are tested explicitly.

Required tests:
- `Data.Ratio` conformance fixtures
- numeric native wet tests
- negative/runtime-error tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to make the Rational gap explicit.

## LIB-008 — Data.Complex and floating numeric tower

Status:
- not started

Category:
- libraries

Depends on:
- FFI-010
- LIB-007
- PRELUDE-020

Blocks:
- none

Scope:
- Implement `Float`/`Double`, the floating Prelude classes, and the Haskell 2010 `Data.Complex` module.

Non-goals:
- Do not claim IEEE edge-case conformance before explicit platform tests exist.
- Do not implement only parser syntax without native semantics.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Float` and `Double` representations support `Fractional`, `Floating`, `RealFrac`, and `RealFloat` methods required by Prelude.
- `Data.Complex` exports `Complex` and rectangular, polar, magnitude, phase, conjugate, and numeric instances.
- Floating edge cases and native lowering are tested for supported targets.

Required tests:
- floating numeric conformance fixtures
- `Data.Complex` native wet tests
- backend/FFI marshalling tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to tie the reserved `Data.Complex` module to the numeric tower work.

## LIB-009 — Data.Int and Data.Word report completion

Status:
- not started

Category:
- libraries

Depends on:
- TC-033
- PRELUDE-020

Blocks:
- none

Scope:
- Move `Data.Word.Word` plus the fixed-width `Data.Int`/`Data.Word` support from importable type names to real representations, instances, and runtime behavior.

Non-goals:
- Do not conflate C ABI type aliases with Haskell fixed-width types unless the representation contract is explicit.
- Do not widen silently without checked conversions.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Data.Word.Word` and the fixed-width `Data.Int`/`Data.Word` types have real runtime representations, numeric instances, bounds, enum behavior, and conversions rather than only importable type names.
- Overflow, bounds, show/read, enum, bits, and FFI interactions are specified and tested.
- Generated module interfaces expose only implemented types and instances.

Required tests:
- fixed-width numeric conformance fixtures
- native wet tests
- FFI scalar tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- TEST-CONF-015 added a positive import fixture for the current type-name-only boundary and this task owns the real implementation.

## LIB-010 — Numeric report completion

Status:
- not started

Category:
- libraries

Depends on:
- TC-029
- TC-030
- LIB-007
- LIB-008

Blocks:
- none

Scope:
- Implement the Haskell 2010 `Numeric` module and integrate it with report-shaped Show, Read, Ratio, and floating support.

Non-goals:
- Do not implement duplicate numeric parsers separate from TC-030 lexical read behavior.
- Do not claim formatting bases or floating rendering without golden tests.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `Numeric` exports report-compatible showing, reading, and miscellaneous numeric formatting/parsing helpers.
- `showSigned`/`showInt`/`readSigned`/`readDec`/`showFloat`/`readFloat`/`lexDigits` integrate with Show and Read implementation choices.
- Positive and negative fixtures cover representative bases, signs, floats, and malformed inputs.

Required tests:
- `Numeric` conformance fixtures
- Show/Read integration tests
- native wet tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 so the reserved `Numeric` module is not hidden behind TC-029/TC-030 alone.

## LIB-011 — System.Environment and System.Exit report completion

Status:
- not started

Category:
- libraries

Depends on:
- IO-014
- PRELUDE-020

Blocks:
- none

Scope:
- Implement the Haskell 2010 process environment and exit modules with deterministic native behavior.

Non-goals:
- Do not introduce platform-specific process behavior without documented deviations.
- Do not mutate global environment state in tests without isolation.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `System.Environment` exports argument, program name, environment lookup, and environment mutation/query APIs where required by the Libraries Report.
- `System.Exit` exports `ExitCode` and process exit actions with deterministic native behavior.
- Command-line and environment-sensitive tests isolate process state and document platform limitations.

Required tests:
- `System.Environment` conformance fixtures
- `System.Exit` native wet tests
- CLI integration tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to replace unnumbered System module future work.

## LIB-012 — System.IO report completion

Status:
- not started

Category:
- libraries

Depends on:
- IO-011
- IO-014
- PRELUDE-020

Blocks:
- none

Scope:
- Expand `System.IO` from line-oriented stdin/stdout to the Haskell 2010 handle, file, buffering, seek, text IO, and error surfaces.

Non-goals:
- Do not implement asynchronous or post-2010 IO APIs.
- Do not expose handles before lifetime, close, and error behavior are specified.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `System.IO` expands from the line-oriented stdin/stdout subset to the report handle, file open/close, buffering, seek, text input/output, and error behavior surface.
- `System.IO.Error` integration is coordinated with IO-011 and tested through recoverable and unrecoverable IO cases.
- Native tests manage temporary files and handles deterministically.

Required tests:
- `System.IO` conformance fixtures
- `System.IO.Error` conformance fixtures
- native wet tests

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Created by TEST-CONF-015 to make the remaining IO library surface explicit.

## IO-001 — IO type representation

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver IO type representation for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- IO type representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-002 — runtime IO action representation

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver runtime IO action representation for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- runtime IO action representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-003 — `main :: IO ()`

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver `main :: IO ()` for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `main :: IO ()` is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-004 — putStrLn

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver putStrLn for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- putStrLn is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-005 — print

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver print for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- print is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-006 — getLine

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver getLine for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. `getLine` is available as a generated Prelude IO action returning ordinary `String = [Char]` values, native executables read from stdin line-by-line and strip line terminators, and IO-typed STG thunks are single-entry so repeated sequencing of the same IO action re-executes the effect instead of sharing a cached result.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- getLine is implemented for the supported native IO subset, including repeated line reads, do-bind use, append/length composition over returned strings, Core/STG empty-stdin oracle coverage, conformance coverage, and default/no-egglog wet tests with stdin.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Complete for current line-input subset: `getLine :: IO String` lowers through Core/STG/native, native runtime input builds list-backed strings, and stdin fixtures cover two sequential reads. Recoverable `IOError` behavior is implemented by IO-011; EOF-specific handle behavior remains owned by LIB-012.

## IO-007 — return

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver return for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- return is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-008 — (>>=)

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver `(>>=)` for the supported stdout-oriented IO subset while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Core and STG IO actions now carry both accumulated stdout chunks and a result value, explicit `(>>=)` enters the continuation with that result, and do-notation `<-` statements lower through the same bind path.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- `(>>=)` typechecks, lowers, evaluates, and compiles natively for supported `IO` actions.
- Do-notation `<-` bind statements typecheck, lower, evaluate, and compile natively for normal stdout examples.
- Core and STG evaluator IO values preserve the returned action result while accumulating stdout output.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Completed for explicit `(>>=)`, do-bind statements, `return`-produced values, normal `putStrLn`/`print` examples over `String`, `Char`, and lists, native `getLine` over stdin, recoverable `IOError` behavior, and the supported `Monad IO` dictionary. Handles, files, buffering, and seek behavior remain separate LIB-012 work.

## IO-009 — (>>)

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver (>>) for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- (>>) is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-010 — do-notation desugaring

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver do-notation desugaring for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- do-notation desugaring is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-011 — IO error behavior

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver IO error behavior for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Core, STG, and native IO actions now carry explicit success/failure results so handlers can observe `IOError` payloads instead of native execution aborting before recovery.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- Core, STG, and native IO actions represent success and failure explicitly so `ioError`, `catch`, `try`, and `fail` compose instead of aborting before handlers run.
- `System.IO.Error` exposes `IOError`, `IOErrorType` constants, `mkIOError`, `annotateIOError`, classifiers, accessors, `userError`, `ioError`, `catch`, and `try` for the supported executable subset.
- Uncaught native IO failures terminate nonzero, while caught failures preserve `IOError` payloads through `catch` and `try`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-012 — stdout/stderr conventions

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver stdout/stderr conventions for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- stdout/stderr conventions is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-013 — IO native wet tests

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver IO native wet tests for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- IO native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## IO-014 — IO conformance tests

Status:
- complete

Category:
- libraries

Depends on:
- RTS-017
- PRELUDE-DATA-007

Blocks:
- none

Scope:
- Deliver IO conformance tests for IO and do-notation while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/Core/Eval.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `test/haskell2010/conformance/`

Acceptance criteria:
- IO conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- library unit tests
- Prelude conformance tests
- native wet tests

Documentation updates:
- `docs/current-capabilities.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M13 (IO and do-notation). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-001 — whole-program module graph

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver whole-program module graph for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- whole-program module graph is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-002 — module file discovery

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver module file discovery for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- module file discovery is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-003 — import search path

Status:
- not started

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver import search path for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- import search path is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-004 — export list semantics

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver export list semantics for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- export list semantics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-005 — qualified import semantics

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver qualified import semantics for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- qualified import semantics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-006 — hiding import semantics

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver hiding import semantics for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- hiding import semantics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-007 — import aliases

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver import aliases for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- import aliases is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-008 — abstract datatype export behavior

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver abstract datatype export behavior for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- abstract datatype export behavior is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-009 — instance import/export behavior

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver instance import/export behavior for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/ModuleInterface.hs`
- `src/Haskell2010/Renamer.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/modules/`
- `test/haskell2010/conformance/negative/`

Acceptance criteria:
- Source module interfaces retain declared instances and every transitively
  imported instance regardless of the module's export list.
- Empty import lists, ordinary import lists, `hiding`, and qualified imports
  filter names only; they do not filter instances.
- Whole-program Haskell 2010 typechecking sees exactly the instances reachable
  through the loaded import graph, so imported source-instance dictionaries are
  emitted only when an import chain reaches the declaring module.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Complete for the current executable
  source-instance subset: instances cross empty export lists and `import M ()`
  through transitive module interfaces, with unit, native-success, and
  negative conformance coverage. User-written instance contexts and
  package-scale instance discovery remain separate later work.

## MOD-010 — Prelude implicit import

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver Prelude implicit import for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- Prelude implicit import is implemented in the module-aware renamer by adding a
  synthetic built-in `import Prelude` only when no explicit `Prelude` import
  declaration exists.
- Explicit `Prelude` imports, including `qualified`, `()`, and `hiding`, suppress
  the implicit import and participate in ordinary cumulative import semantics.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Complete for the current same-directory module
  graph and built-in Prelude surface; arbitrary package/module Prelude loading
  and broader standard library layout remain tracked separately.

## MOD-011 — separate compilation decision/documentation

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver separate compilation decision/documentation for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Current behavior is explicit source-graph whole-program compilation behind `Haskell2010.ModuleGraph.currentModuleCompilationBoundary`; true separate compilation is deferred until package/search-path identity and interface artifact invalidation are stable.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/modules/`
- `docs/haskell2010-module-compilation-boundary.md`

Acceptance criteria:
- separate compilation decision/documentation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-module-compilation-boundary.md`

Notes:
- Milestone M14 (Full modules). Complete as a documented and code-level boundary: same-directory source modules compile as one loaded graph, while persistent interface/object reuse remains a future implementation gated by stable module search policy.

## MOD-012 — interface file future plan

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver interface file future plan for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Current behavior deliberately emits no interface files; the planned artifact shape, invalidation requirements, and implementation order are documented in `docs/haskell2010-module-compilation-boundary.md`.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/Main.hs`
- `test/haskell2010/conformance/modules/`
- `docs/haskell2010-module-compilation-boundary.md`

Acceptance criteria:
- interface file future plan is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-module-compilation-boundary.md`

Notes:
- Milestone M14 (Full modules). Complete as a future plan and explicit code policy; interface files remain intentionally deferred until search roots, generated library module identity, fingerprints, and native link metadata can be encoded soundly.

## MOD-013 — multi-module native wet tests

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver multi-module native wet tests for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- multi-module native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## MOD-014 — module negative tests

Status:
- complete

Category:
- modules

Depends on:
- REN-015
- LLVM-015

Blocks:
- none

Scope:
- Deliver module negative tests for Full modules while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/ModuleGraph.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Native.hs`
- `test/haskell2010/conformance/modules/`

Acceptance criteria:
- module negative tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- module graph tests
- import/export negative tests
- multi-module native wet tests

Documentation updates:
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M14 (Full modules). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## FFI-001 — Haskell 2010 FFI scope decision

Status:
- complete

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver the Haskell 2010 FFI scope decision as a full-implementation design target while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- Haskell 2010 FFI is documented as a full implementation target, not a permanent deviation or reduced product slice.
- The design records the Report-required declaration forms, calling conventions, safety, entities, foreign types, standard-library surface, IR boundaries, runtime obligations, LLVM/linking obligations, and conformance test strategy.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- documentation/static checks

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). Complete as a scope/design decision: FFI is part of the full Haskell 2010 target.

## FFI-002 — foreign import parser

Status:
- complete

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver foreign import parser for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Syntax.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/Main.hs`

Acceptance criteria:
- `foreign import` parses into structured AST records for calling convention, safety, import entity, imported binder, and source type.
- Static function, static address, `dynamic`, `wrapper`, explicit safety, omitted safety, omitted entity, and implementation-specific calling-convention forms are represented without raw-string-only AST behavior.
- `foreign import` binds a top-level term during renaming, participates in duplicate-name checks, and can be exported/imported through module interfaces.
- Supported `foreign import ccall` declarations lower through explicit Core/STG foreign IR and native LLVM ABI lowering rather than being dropped.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- renamer unit tests
- typechecker signature-validation, Core/STG IR, and native lowering tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). Complete for frontend representation and renaming; supported import declarations now continue through FFI signature typechecking, Core/STG IR, native lowering, and wet tests.

## FFI-003 — foreign export parser, if implemented

Status:
- complete

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver foreign export parser for FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Syntax.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamed.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `test/Main.hs`

Acceptance criteria:
- `foreign export` parses into structured AST records for calling convention, export entity, exported binding name, and source type.
- `foreign export` resolves an existing top-level term during renaming and reports a normal unbound-name diagnostic when it references a missing binding.
- Supported `foreign export ccall` declarations are preserved as Core/STG module metadata and lower to native C-callable entrypoints rather than being dropped.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- renamer unit tests
- typechecker signature-validation, Core/STG metadata, and native export lowering tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-frontend-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). Complete for frontend representation, renaming, Core/STG metadata, and native foreign-export entrypoint lowering for the supported ccall ABI slice.

## FFI-004 — C calling convention representation

Status:
- in progress

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver C calling convention representation for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/Syntax.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- `ccall` and `stdcall` are represented structurally in parsed and renamed foreign declarations.
- The FFI typechecker accepts Haskell 2010 `ccall`/`stdcall` declarations and rejects non-Haskell-2010 calling conventions before lowering.
- The supported ccall ABI slice links to native runtime lowering; stdcall remains represented and typechecked but target-specific native lowering remains an explicit gap.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- parser unit tests
- typechecker unit tests
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). In progress: ccall/stdcall are represented structurally, unsupported conventions are rejected before lowering, and the supported ccall native ABI slice is implemented; stdcall target-specific native lowering remains explicit future work.

## FFI-005 — primitive marshalling

Status:
- in progress

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver primitive marshalling for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/StandardLibrary.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Generated `Foreign`, `Foreign.C`, and `Foreign.C.Types` module interfaces expose the current FFI type surface to ordinary imports.
- The typechecker validates marshallable scalar, pointer, type-synonym, and local visible-newtype foreign types.
- Static, address, `dynamic`, and `wrapper` import signatures receive shape-specific diagnostics.
- `foreign export` declarations validate that the exported binding can instantiate to the declared foreign type.
- Runtime primitive marshalling and ABI conversion are implemented for the supported scalar integer/Bool/Char/Float/Double and pointer ABI slice; remaining Foreign library marshalling for Storable, allocation, arrays, errno, and C strings remains explicit future work.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- typechecker unit tests
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). In progress: generated library surfaces, source-level marshallable type validation, scalar/integer/Bool/Char/Float/Double/pointer/newtype/synonym marshalling, dynamic/wrapper shape checks, export validation, and the FFI-013 Foreign.Ptr/Foreign.ForeignPtr/Foreign.Marshal.Error/Foreign.Marshal.Utils surface are implemented; remaining Foreign library marshalling for Storable, allocation, arrays, errno, and C strings remains explicit future work.

## FFI-006 — runtime integration

Status:
- in progress

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver runtime integration for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Static, `dynamic`, and `wrapper` foreign imports lower to explicit Core/STG foreign-call nodes.
- Address imports lower to explicit inert Core/STG foreign-import value nodes.
- Core/STG validators, pretty-printers, evaluators, optimizer traversal, and native backend boundaries preserve the foreign IR without silently dropping imports.
- Core/STG evaluation reports explicit unsupported runtime diagnostics when foreign calls are reached outside native lowering.
- Supported `foreign import ccall` nodes lower to native LLVM declarations/direct calls or indirect `FunPtr` calls with scalar integer/Bool/Char/Float/Double marshalling, `Ptr`/`FunPtr` pointer marshalling, static `&symbol` address boxing, `wrapper` callback trampolines, and `IO` sequencing.
- Explicit `StablePtr` ownership, manual `ForeignPtr` finalizer APIs, `freeHaskellFunPtr`, wrapper callback-slot reclamation, callback-after-free rejection, and reverse-order/idempotent finalization are implemented and wet-tested; automatic GC finalizer scheduling remains scoped out under the process-lifetime runtime model.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). In progress: Core/STG IR is complete for imports and export metadata, scalar/floating/pointer/static-address/dynamic/wrapper/export ccall native runtime integration is implemented and wet-tested, and unsupported FFI entities still fail at explicit boundaries.

## FFI-007 — LLVM external declaration lowering

Status:
- in progress

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver LLVM external declaration lowering for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Supported static `foreign import ccall` symbols emit LLVM external declarations with ABI-accurate argument and result types.
- Static scalar and pointer calls emit direct LLVM `call` instructions and link successfully against C helper objects in native wet tests.
- Static `&symbol` imports for `Ptr a` and `FunPtr ft` emit external data/function declarations and box the raw address as a pointer value.
- `dynamic` imports emit typed indirect calls through unboxed `FunPtr` values.
- `wrapper` imports emit reclaimable process-lifetime callback slots and C-callable trampoline functions for the supported scalar/floating/pointer ABI slice.
- Unsupported FFI entities still report explicit native ABI diagnostics instead of being silently dropped.
- Automatic GC finalization remains scoped out under the process-lifetime runtime model; explicit wrapper callback release is implemented through `freeHaskellFunPtr`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). In progress: static scalar/floating/pointer ccall declarations/direct calls, address imports, dynamic imports, wrapper callbacks with `freeHaskellFunPtr` reclamation, and foreign export ccall entrypoints are implemented; FFI link metadata is complete.

## FFI-008 — FFI native tests

Status:
- in progress

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- Deliver FFI native tests for Haskell 2010 FFI while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/STG/LLVM.hs`
- `src/Haskell2010/Native.hs`
- `src/Backend/LLVM/Toolchain.hs`
- `docs/runtime-spec.md`

Acceptance criteria:
- Static scalar and floating `ccall` native tests compile/link generated LLVM with a C helper and assert stdout.
- Static pointer/address native tests cover `Ptr`, `FunPtr`, data `&symbol`, function `&symbol`, pointer arguments, pointer results, and ordered pointer mutation through `IO`.
- Dynamic/wrapper native tests cover indirect `FunPtr` calls, multiple live wrapped callbacks, C-to-Haskell callback re-entry, callback `IO`, result marshalling, explicit wrapper release, double-free/idempotence, slot reclamation, and callback-after-free runtime failure.
- Foreign export native tests cover C helpers calling exported pure and `IO` Haskell functions; remaining FFI forms add native tests as each ABI feature lands.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- runtime unit tests
- native runtime wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/runtime-spec.md`
- `docs/laziness-and-stg-plan.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M15 (FFI). In progress: static scalar, floating, pointer/address, dynamic/wrapper lifetime, foreign-export, StablePtr, and ForeignPtr finalizer native C-helper wet tests are implemented; link metadata and explicit link-object coverage are complete, while broader Foreign library coverage remains open.

## FFI-009 — FFI-wide deferral retired

Status:
- complete

Category:
- runtime

Depends on:
- LLVM-002

Blocks:
- none

Scope:
- The project no longer treats Haskell 2010 FFI as a whole-feature documented deviation.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- The project no longer treats Haskell 2010 FFI as a whole-feature documented deviation.
- Implemented FFI support is tracked by FFI-001 through FFI-008, and remaining gaps are tracked by dedicated follow-up tasks instead of one broad deferral bucket.
- Unsupported FFI behavior remains explicit in the conformance matrix and docs until each follow-up task is implemented.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- documentation/static checks
- conformance matrix review
- unsupported/deviation fixture review

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Added or refreshed by the tracker reconciliation audit so future work has a stable task ID instead of living only in roadmap prose.

## FFI-010 — floating-point FFI marshalling

Status:
- complete

Category:
- runtime

Depends on:
- FFI-005
- FFI-007

Blocks:
- none

Scope:
- Foreign imports and exports validate and marshal `Float`, `Double`, `CFloat`, and `CDouble` according to the supported C ABI.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Foreign imports and exports validate and marshal `Float`, `Double`, `CFloat`, and `CDouble` according to the supported C ABI.
- Core/STG/LLVM types distinguish floating-point ABI values from boxed runtime values without corrupting existing integer/pointer marshalling.
- Native C-helper fixtures cover direct calls, callbacks, exports, and result marshalling for floating-point values.
- Unsupported foreign ABI combinations continue to fail explicitly until implemented.
- Docs and matrix remove floating-point FFI from the remaining-gap list only after native coverage passes.

Required tests:
- typechecker tests
- Core/STG validation tests
- LLVM lowering tests
- native C-helper wet tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Native floating FFI marshalling maps `Float`/`CFloat` to LLVM `float` and `Double`/`CDouble` to LLVM `double`, boxes runtime `Float`/`Double` values separately from integer/pointer objects, and covers static calls, dynamic `FunPtr` calls, wrapper callbacks, and `foreign export` through `ffi.floating-ccall` in default and no-egglog modes.

## FFI-011 — FFI link metadata

Status:
- complete

Category:
- runtime

Depends on:
- FFI-002
- FFI-007
- LLVM-016

Blocks:
- none

Scope:
- Foreign import entity metadata preserves header/library/object requirements needed for portable C linking.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Foreign import entity metadata preserves header/library/object requirements needed for portable C linking.
- The CLI/native toolchain accepts and propagates required extra objects or libraries without hardcoding test-only paths.
- Conformance and e2e fixtures cover header-qualified entities and explicit link inputs.
- Missing link dependencies report stable diagnostics.
- Docs describe the supported link model and remaining platform-specific limitations.

Required tests:
- parser tests
- toolchain tests
- native C-helper wet tests
- negative link diagnostics

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/llvm-backend-spec.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Foreign import/export lowering now carries `ForeignLinkMetadata` through the Haskell 2010 native result and emits LLVM comments for header-qualified imports, static/address symbols, and exported C symbols. The CLI and LLVM toolchain accept repeated `--link-object`, `--link-library`, `--library-path`, and `--framework` flags and pass them to clang. The conformance harness now builds FFI helper fixtures through those link flags instead of a side-channel manual clang path, and tests cover header-qualified ccall metadata plus missing link-input diagnostics.

## FFI-012 — callback and finalizer lifetime completion

Status:
- complete

Category:
- runtime

Depends on:
- FFI-006
- FFI-007
- FFI-008

Blocks:
- none

Scope:
- `freeHaskellFunPtr` and callback-slot reclamation are implemented with documented ownership and re-entry behavior.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- `freeHaskellFunPtr` and callback-slot reclamation are implemented with documented ownership and re-entry behavior.
- Automatic `ForeignPtr` finalizer scheduling is implemented or explicitly scoped against the project runtime ownership model.
- Callback and finalizer lifetimes are safe across nested C-to-Haskell re-entry and explicit `StablePtr` usage.
- Native wet tests cover reclamation, double-free/idempotence, callback-after-free rejection, and finalizer ordering.
- Docs distinguish manual process-lifetime behavior from any automatic lifetime guarantees.

Required tests:
- runtime unit tests
- native callback wet tests
- finalizer wet tests
- runtime-error conformance tests

Documentation updates:
- `docs/haskell2010-ffi-design.md`
- `docs/runtime-spec.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. `freeHaskellFunPtr` is now a generated `Foreign`/`Foreign.Ptr` binding that lowers through Core, STG, validation, evaluation, optimization boundaries, and native LLVM. Wrapper imports now allocate from reclaimable per-import callback slots, double-free of a wrapper pointer is idempotent, unknown frees and callback-after-free paths abort instead of re-entering stale closures, and freed slots can be reused after the fixed pool is saturated. Manual `ForeignPtr` finalization remains explicit under the process-lifetime allocation model: automatic GC scheduling is not claimed, while `finalizeForeignPtr` is idempotent and finalizers run in reverse registration order. Unit/native and conformance fixtures cover wrapper reclamation, callback-after-free runtime failure, double-free/idempotence, finalizer ordering, StablePtr round trips, and withForeignPtr/touchForeignPtr liveness barriers.

## FFI-013 — Foreign library surface completion

Status:
- complete

Category:
- libraries

Depends on:
- FFI-005
- PRELUDE-020

Blocks:
- none

Scope:
- The `Foreign`, `Foreign.C`, `Foreign.C.Types`, `Foreign.Ptr`, `Foreign.StablePtr`, `Foreign.ForeignPtr`, `Foreign.Marshal.*`, and `Foreign.Storable` surfaces are tracked module-by-module against the Haskell 2010 libraries.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- The `Foreign`, `Foreign.C`, `Foreign.C.Types`, `Foreign.Ptr`, `Foreign.StablePtr`, `Foreign.ForeignPtr`, `Foreign.Marshal.*`, and `Foreign.Storable` surfaces are tracked module-by-module against the Haskell 2010 libraries.
- Implemented functions and types use generated module interfaces, ordinary import/export rules, and conformance fixtures.
- Unsupported functions remain explicit unsupported-documented cases rather than implicit omissions.
- Docs identify the exact implemented, partial, and pending Foreign module surfaces.
- Library coverage is reflected in the standard-library layout and conformance matrix.

Required tests:
- standard-library interface tests
- typechecker tests
- native wet tests
- unsupported conformance fixtures

Documentation updates:
- `docs/haskell2010-standard-library-layout.md`
- `docs/haskell2010-ffi-design.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete for the current generated/importable Foreign library surface. `Foreign.Ptr` now exposes null pointer values and pointer/function-pointer casts; `Foreign.ForeignPtr` exposes `FinalizerPtr`, `FinalizerEnvPtr`, `unsafeForeignPtrToPtr`, and `castForeignPtr`; `Foreign.Marshal`, `Foreign.Marshal.Error`, and `Foreign.Marshal.Utils` expose the implemented guard and Maybe pointer-helper subset. Native conformance fixture `ffi.foreign-library-surface` covers the added surface in default and no-egglog modes. Remaining `Foreign.C.Error`, `Foreign.Storable`, raw allocation, array marshalling, and C string marshalling functions stay explicitly documented as reserved/pending rather than implicit omissions.

## EGG-CORE-001 — Core Egglog schema

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver Core Egglog schema for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- Core Egglog schema is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-002 — Core-to-Egglog encoder

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver Core-to-Egglog encoder for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- Core-to-Egglog encoder is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-003 — Egglog-to-Core extractor

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver Egglog-to-Core extractor for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- Egglog-to-Core extractor is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-004 — Core type preservation checks

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver Core type preservation checks for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- Core type preservation checks is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-005 — Core totality facts

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver Core totality facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- Core totality facts is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-006 — no-error facts

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver no-error facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- no-error facts is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-007 — known constant facts

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver known constant facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- known constant facts is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-008 — known constructor facts

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver known constructor facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- known constructor facts is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-009 — demand facts

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver demand facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- demand facts is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-010 — strictness facts

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver strictness facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- strictness facts is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-011 — dictionary-known facts

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver dictionary-known facts for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- dictionary-known facts is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-012 — safe constant folding

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver safe constant folding for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- safe constant folding is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-013 — case-of-known-constructor

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver case-of-known-constructor for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- case-of-known-constructor is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-014 — constructor projection

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver constructor projection for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- constructor projection is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-015 — dictionary simplification

Status:
- not started

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver dictionary simplification for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- dictionary simplification is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-016 — bottom-preserving boolean simplification

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver bottom-preserving boolean simplification for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- bottom-preserving boolean simplification is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-017 — guarded arithmetic identities

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver guarded arithmetic identities for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- guarded arithmetic identities is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-018 — provenance/explanations

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver provenance/explanations for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- provenance/explanations is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-019 — optimized vs unoptimized native wet tests

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver optimized vs unoptimized native wet tests for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- optimized vs unoptimized native wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## EGG-CORE-020 — no unsafe bottom-erasing rewrite tests

Status:
- complete

Category:
- egglog

Depends on:
- CORE-010

Blocks:
- none

Scope:
- Deliver no unsafe bottom-erasing rewrite tests for Egglog Core optimizer while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.

Files likely touched:
- `src/Optimize/CoreEgglog.hs`
- `src/Optimize/EgglogBackend/`
- `src/Egglog/`
- `test/Main.hs`
- `test/haskell2010/conformance/egglog/`

Acceptance criteria:
- no unsafe bottom-erasing rewrite tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- Core Egglog unit tests
- optimized vs --no-egglog native wet tests
- bottom-preservation tests

Documentation updates:
- `docs/egglog-core-optimizer-plan.md`
- `docs/optimizer-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M16 (Egglog Core optimizer). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-001 — common source span representation

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver common source span representation for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- common source span representation is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-002 — lexer diagnostics

Status:
- in progress

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver lexer diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- lexer diagnostics is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-003 — layout diagnostics

Status:
- in progress

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver layout diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- layout diagnostics is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-004 — parser diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver parser diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- parser diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-005 — renamer diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver renamer diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- renamer diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-006 — typechecker diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver typechecker diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- typechecker diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-007 — kind diagnostics

Status:
- not started

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver kind diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- kind diagnostics is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-008 — class/instance diagnostics

Status:
- in progress

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver class/instance diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- class/instance diagnostics is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-009 — pattern-match diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver pattern-match diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- pattern-match diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Complete for the current executable subset:
  supported non-exhaustive `case`, function, and lambda patterns emit
  source-spanned warnings with missing witnesses where finite constructor
  coverage can identify them, supported duplicate/unreachable alternatives emit
  redundant-pattern warnings, native compile results preserve warnings, and the
  compile CLI renders warnings to stderr. Broader report-complete coverage and
  lazy runtime source attribution remain tracked outside this task.

## DIAG-010 — module/import diagnostics

Status:
- in progress

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver module/import diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- module/import diagnostics is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-011 — Core validation diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver Core validation diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- Core validation diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-012 — backend diagnostics

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver backend diagnostics for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- backend diagnostics is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-013 — runtime source attribution

Status:
- not started

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver runtime source attribution for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- runtime source attribution is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-014 — nested runtime spans

Status:
- not started

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver nested runtime spans for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- nested runtime spans is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-015 — CLI diagnostic renderer

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- CLI-001
- CLI-002
- CLI-003
- CLI-004
- CLI-005
- CLI-006
- CLI-007
- CLI-008
- CLI-009
- CLI-010
- CLI-011
- CLI-012
- CLI-013
- CLI-014
- CLI-015
- CLI-016

Scope:
- Deliver CLI diagnostic renderer for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- CLI diagnostic renderer is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DIAG-016 — diagnostic golden tests

Status:
- complete

Category:
- diagnostics

Depends on:
- FRONT-032
- TYPE-020

Blocks:
- none

Scope:
- Deliver diagnostic golden tests for Diagnostics while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Syntax/Span.hs`
- `src/Haskell2010/Parser.hs`
- `src/Haskell2010/Renamer.hs`
- `src/Haskell2010/Typecheck.hs`
- `src/CLI/Report.hs`
- `test/golden/`

Acceptance criteria:
- diagnostic golden tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- diagnostic golden tests
- negative conformance tests
- CLI rendering tests

Documentation updates:
- `docs/diagnostics-spec.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M17 (Diagnostics). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-001 — command model

Status:
- in progress

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver command model for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- command model is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-002 — `hegglog check`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog check` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog check` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-003 — `hegglog run`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog run` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog run` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-004 — `hegglog compile`

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- TEST-CONF-001
- TEST-CONF-002
- TEST-CONF-003
- TEST-CONF-004
- TEST-CONF-005
- TEST-CONF-006
- TEST-CONF-007
- TEST-CONF-008
- TEST-CONF-009
- TEST-CONF-010
- TEST-CONF-011
- TEST-CONF-012

Scope:
- Deliver `hegglog compile` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog compile` is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-005 — `hegglog report`

Status:
- in progress

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog report` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog report` is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-006 — `hegglog emit-core`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog emit-core` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog emit-core` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-007 — `hegglog emit-stg`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog emit-stg` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog emit-stg` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-008 — `hegglog emit-llvm`

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `hegglog emit-llvm` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `hegglog emit-llvm` is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-009 — `--no-egglog`

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `--no-egglog` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `--no-egglog` is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-010 — `--strict-egglog`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `--strict-egglog` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `--strict-egglog` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-011 — `--keep-intermediates`

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver `--keep-intermediates` for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- `--keep-intermediates` is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-012 — dump flags

Status:
- not started

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver dump flags for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- dump flags is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-013 — stdout/stderr policy

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver stdout/stderr policy for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- stdout/stderr policy is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-014 — exit-code policy

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver exit-code policy for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- exit-code policy is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-015 — CLI wet tests

Status:
- complete

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver CLI wet tests for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- CLI wet tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## CLI-016 — help text tests

Status:
- in progress

Category:
- cli

Depends on:
- DIAG-015

Blocks:
- none

Scope:
- Deliver help text tests for CLI productization while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Main.hs`
- `src/CLI/Compile.hs`
- `src/CLI/Report.hs`
- `test/Main.hs`
- `test/e2e/Main.hs`

Acceptance criteria:
- help text tests is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CLI unit tests
- help text tests
- CLI wet tests

Documentation updates:
- `README.md`
- `docs/current-capabilities.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M18 (CLI productization). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-001 — conformance manifest

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- DOC-001
- DOC-002
- DOC-003
- DOC-004
- REL-001
- REL-002
- REL-003
- REL-004
- REL-005
- REL-006
- REL-007
- REL-008
- REL-009
- REL-010
- REL-011
- REL-012
- REL-013
- REL-014

Scope:
- Deliver conformance manifest for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- conformance manifest is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-002 — parser conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver parser conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- parser conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Complete for the current manifest-backed parser coverage, including lexical/layout positives and malformed-layout negative coverage.

## TEST-CONF-003 — renamer conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver renamer conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- renamer conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Complete for the current manifest-backed renamer coverage, including module graph, Prelude visibility, foreign export target, and unbound/duplicate-name negatives.

## TEST-CONF-004 — typechecker conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver typechecker conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- typechecker conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-005 — desugaring/Core conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver desugaring/Core conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- desugaring/Core conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Complete for the current manifest-backed Core/desugaring coverage through native-success fixtures and the unit Core/STG validation suites.

## TEST-CONF-006 — native wet conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver native wet conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- native wet conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-007 — negative conformance tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver negative conformance tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- negative conformance tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-008 — documented deviation tests

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver documented deviation tests for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- documented deviation tests is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-009 — matrix auto/check script

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver matrix auto/check script for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- matrix auto/check script is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Complete via `scripts/validate-haskell2010-conformance.py`, which validates manifest schema, case uniqueness, source/helper file existence, status/mode values, and conformance-matrix coverage for every manifest source.

## TEST-CONF-010 — conformance results doc

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver conformance results doc for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- conformance results doc is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-011 — CI conformance job

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver CI conformance job for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- CI conformance job is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## TEST-CONF-012 — report coverage by Haskell 2010 section

Status:
- complete

Category:
- testing

Depends on:
- CLI-004

Blocks:
- none

Scope:
- Deliver report coverage by Haskell 2010 section for Haskell 2010 conformance suite closure while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/`
- `scripts/`

Acceptance criteria:
- report coverage by Haskell 2010 section is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- validation script tests
- conformance manifest tests
- CI test coverage

Documentation updates:
- `docs/e2e-wet-testing.md`
- `docs/e2e-results.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-conformance-matrix.md`

Notes:
- Milestone M19 (Haskell 2010 conformance suite closure). Complete for the current executable-subset/report-section matrix: every manifest fixture is represented in the conformance matrix and unsupported Haskell 2010 areas remain explicit documented-deviation cases.

## TEST-CONF-013 — source-surface negative fixtures

Status:
- complete

Category:
- testing

Depends on:
- TEST-CONF-007
- SURFACE-001

Blocks:
- none

Scope:
- Negative fixtures cover malformed `where` groups, invalid pattern bindings, invalid record updates, unsupported expression forms, duplicate source binders, and impossible or redundant match surfaces.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Negative fixtures cover malformed `where` groups, invalid pattern bindings, invalid record updates, unsupported expression forms, duplicate source binders, and impossible or redundant match surfaces.
- Each negative fixture asserts a stable diagnostic category and fails if the compiler silently accepts the program.
- Unsupported source forms use `unsupported-documented` only when the limitation is explicit in the matrix and tracker.
- All new fixtures are listed in `test/haskell2010/conformance/manifest.json` and validated by the conformance script.
- The Haskell 2010 conformance matrix points to these fixtures from the relevant source-surface rows.

Required tests:
- negative conformance tests
- manifest validation
- diagnostic category checks

Documentation updates:
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete for current source-surface negative coverage. The manifest now
  includes stable diagnostic-category fixtures for malformed `where` layout,
  misindented line-broken `where` keywords,
  duplicate binders in top-level pattern bindings and function equations,
  constructor-operator misuse in value binding syntax,
  invalid record updates, an impossible `case` pattern/scrutinee combination,
  and a documented unsupported constrained expression signature.

## TEST-CONF-014 — source matrix closure

Status:
- complete

Category:
- testing

Depends on:
- SURFACE-001
- TEST-CONF-013

Blocks:
- none

Scope:
- Every expression, declaration, and pattern row in the conformance matrix is backed by an implemented fixture, a compile-error fixture, or an unsupported-documented fixture.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-results.md`
- `scripts/validate-haskell2010-conformance.py`

Acceptance criteria:
- Every expression, declaration, and pattern row in the conformance matrix is backed by an implemented fixture, a compile-error fixture, or an unsupported-documented fixture.
- Rows that are only parser/renamer-supported remain labelled as such and link to the next implementation task rather than being counted as executable support.
- The matrix, manifest, roadmap, status summary, and tracker agree on source-surface status.
- The conformance validator catches missing manifest-to-matrix coverage for source-surface fixtures.
- No broad source-surface work remains only in prose without a task ID.

Required tests:
- conformance validator
- matrix review
- manifest review

Documentation updates:
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Added a machine-checked Source Surface Matrix Closure table to
  the conformance matrix covering all declaration, expression, and pattern
  rows. The conformance validator now rejects missing closure rows, fixture
  paths not present in the manifest, and `declarations`/`expressions`/`patterns`
  manifest fixtures omitted from the closure table. It also requires the
  source-surface negative and unsupported fixtures to remain linked from the
  closure table. The SURFACE source-surface implementation gap tasks are now
  complete and backed by manifest fixtures.

## TEST-CONF-015 — library conformance closure

Status:
- complete

Category:
- testing

Depends on:
- PRELUDE-020

Blocks:
- none

Scope:
- Reconcile the Haskell 2010 Chapter 9 Prelude and Part II Libraries inventory against the generated standard-library boundary, conformance matrix, manifest, and tracker before additional library surface is claimed.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `src/Haskell2010/`
- `test/haskell2010/conformance/`
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- Every newly claimed standard class, derived instance, Prelude function, and standard-library module has manifest-backed positive and negative coverage.
- Chapter 9 Prelude and the Part II Haskell 2010 Libraries module inventory are reconciled against the tracker before additional library surface is claimed.
- Unsupported library features remain explicit unsupported-documented cases until implemented.
- The closure audit explicitly accounts for report-shaped Show/Read, remaining Prelude classes/functions, Control.Monad, Data.Array, Data.Bits, Data.Char, Data.Complex, Data.Int, Data.Ix, Data.List, Data.Maybe, Data.Ratio, Data.Word, Numeric, System.Environment, System.Exit, System.IO, System.IO.Error, and the FFI-owned Foreign.* modules.
- The conformance results summary reports library coverage by class/function/module instead of only by broad category.
- Docs, tracker, matrix, and manifest agree on library support boundaries.
- The validator catches manifest cases that are missing from the matrix or docs coverage summary.

Required tests:
- conformance suite
- manifest validation
- matrix validation
- native wet tests

Documentation updates:
- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-conformance-results.md`
- `docs/haskell2010-todo.md`

Notes:
- Complete. Reconciled the Haskell 2010 Chapter 9 Prelude and Part II Libraries inventory against the generated standard-library boundary, conformance matrix, manifest, and tracker. Added a validator-backed Library Conformance Closure table, explicit unsupported-documented fixtures for reserved Report modules, a positive scalar type import fixture for `Data.Int`/`Data.Word`/`Foreign.C.Types`, and numbered `LIB-*` follow-up tasks for every previously unnumbered library gap. Further library implementation must update the table, matrix, manifest, and generated module boundary together.

## DOC-001 — Backlog and roadmap consistency policy

Status:
- complete

Category:
- docs

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver Backlog and roadmap consistency policy for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- Backlog and roadmap consistency policy is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- backlog validator
- link consistency review
- conformance matrix review

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DOC-002 — Conformance matrix task-link discipline

Status:
- complete

Category:
- docs

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver Conformance matrix task-link discipline for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- Conformance matrix task-link discipline is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- backlog validator
- link consistency review
- conformance matrix review

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DOC-003 — Design document completion audit

Status:
- not started

Category:
- docs

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver Design document completion audit for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- Design document completion audit is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- backlog validator
- link consistency review
- conformance matrix review

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## DOC-004 — Examples and tutorial documentation plan

Status:
- not started

Category:
- docs

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver Examples and tutorial documentation plan for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`
- `docs/haskell2010-conformance-matrix.md`

Acceptance criteria:
- Examples and tutorial documentation plan is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- backlog validator
- link consistency review
- conformance matrix review

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-roadmap.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-001 — CI matrix

Status:
- in progress

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver CI matrix for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- CI matrix is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-002 — clang/LLVM toolchain installation docs

Status:
- in progress

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver clang/LLVM toolchain installation docs for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- clang/LLVM toolchain installation docs is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-003 — release workflow

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver release workflow for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- release workflow is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-004 — installation instructions

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver installation instructions for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- installation instructions is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-005 — docs index

Status:
- complete

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver docs index for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- docs index is implemented, completed, or explicitly documented according to status `complete`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-006 — examples gallery

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver examples gallery for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- examples gallery is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-007 — standard library packaging

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver standard library packaging for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- standard library packaging is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-008 — runtime build integration

Status:
- in progress

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver runtime build integration for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- runtime build integration is implemented, completed, or explicitly documented according to status `in progress`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-009 — formatting/linting

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver formatting/linting for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- formatting/linting is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-010 — coverage reporting

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver coverage reporting for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- coverage reporting is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-011 — benchmark suite

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver benchmark suite for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- benchmark suite is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-012 — release checklist

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver release checklist for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- release checklist is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-013 — versioning policy

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver versioning policy for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- versioning policy is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.

## REL-014 — changelog

Status:
- not started

Category:
- release

Depends on:
- TEST-CONF-001

Blocks:
- none

Scope:
- Deliver changelog for Release quality while preserving the current .hg substrate and the documented Haskell 2010 executable-subset behavior. Keep the work behind the IR/API boundary named by this category and update conformance status rather than claiming broader support.

Non-goals:
- Do not weaken existing .hg behavior or tests.
- Do not claim full Haskell 2010 or GHC compatibility from this task alone.
- Do not make unrelated architecture or formatting churn.
- Do not change runtime semantics unless this task explicitly owns runtime behavior.
- Do not add optimizer rewrites outside documented safety rules.

Files likely touched:
- `.github/workflows/ci.yml`
- `scripts/`
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Acceptance criteria:
- changelog is implemented, completed, or explicitly documented according to status `not started`.
- All affected compiler invariants remain validated by the relevant unit, conformance, and wet tests.
- The Haskell 2010 conformance matrix points to this task for implemented work or explicit remaining gaps.

Required tests:
- CI matrix run
- fresh checkout smoke test
- release checklist validation

Documentation updates:
- `README.md`
- `docs/index.md`
- `docs/haskell2010-todo.md`

Notes:
- Milestone M20 (Release quality). Status reflects the codebase after commit 0043a2d and should be revised whenever implementation or conformance coverage changes.
