# Compiler Readiness Audit

Date: 2026-05-18

Current note: this is a historical audit of the strict `.hg` compiler
substrate. It is not the authoritative current Haskell 2010 status document.
The current Haskell 2010 compiler status is tracked in
[`haskell2010-status-summary.md`](haskell2010-status-summary.md),
[`current-capabilities.md`](current-capabilities.md), and
[`haskell2010-conformance-matrix.md`](haskell2010-conformance-matrix.md).
The Haskell 2010 executable subset now has parser/layout, renaming, module
graph loading, typed Core, typechecking/desugaring, Core evaluation, STG
lowering/evaluation, native LLVM output, IO printing, and Core Egglog
optimization for the documented subset. Haskell 2010 conformance progress is
now tracked by the dedicated mandatory `haskell2010-conformance-test` suite,
with explicit native-success, runtime-error, compile-error, and
unsupported-documented cases.

This audit predates or accompanies the Haskell 2010 pivot. It evaluates the
existing strict `.hg` compiler baseline. The active project target is now a
Haskell 2010 native compiler, tracked in
[`haskell2010-roadmap.md`](haskell2010-roadmap.md) and
[`haskell2010-conformance-matrix.md`](haskell2010-conformance-matrix.md).

This audit evaluates the current HeggLog codebase as a compiler implementation, with emphasis on end-to-end readiness, semantic correctness, optimizer safety, LLVM backend completeness, diagnostics, tests, documentation, and remaining work required for a practical v1 compiler.

This version of the audit is synchronized with the compiler baseline that
includes checked LLVM division, strictness-preserving Egglog rules, native
executable output through `clang`, and mandatory end-to-end wet testing.

## 1. Executive Summary

HeggLog is a credible native compiler baseline for a well-defined, typed
strict `.hg` expression-language subset. It currently has the major pieces
expected of a small compiler:

- Located parsing for source files.
- Type inference and elaboration, including optional lambda annotations.
- Source interpreter and ANF interpreter.
- ANF conversion and validation.
- A simplifier, an experimental e-graph path, and a more substantial Egglog-style optimizer backend.
- Lambda lifting and closure conversion.
- Backend IR validation, LLVM text emission, and native executable output
  through `clang`.
- LLVM validation and execution through external LLVM tools.
- Mandatory wet tests for native executable artifacts.
- A meaningful test suite across parser, typechecker, interpreter, optimizer, backend, goldens, and properties.

For the current supported runtime fragment, HeggLog is a working compiler:
successful supported programs can be compiled to native executables, and
unsupported compile targets fail structurally rather than silently producing
bad artifacts.

The project now has the core artifact behavior expected of a small compiler for
its supported subset: `hegglog compile file.hg -o program` generates LLVM IR
and invokes `clang` to produce a native executable, while `--emit-llvm` preserves
textual LLVM output. `--run-llvm` remains available for LLVM-tool execution, and
`--run` builds and runs the requested native executable.

The LLVM backend is correct-looking and well tested for its intended subset: closed `Int`/`Bool` roots, `let`, `if`, checked `+`, `-`, `*`, `/`, `<`, `==`, top-level first-order calls, lambda lifting, and local closures. Checked division was a gap at the original audit time; it is now lowered directly with division-by-zero and minimum-`Int / -1` runtime checks.

The optimizer story is stronger than a typical early compiler at this stage.
The default compiler path uses the Egglog backend when supported and falls back
explicitly when unsupported. The current baseline removes several unsafe default
rewrites that would otherwise violate strict runtime-error preservation. This
materially improves compiler trustworthiness.

For the current `.hg` substrate, the highest-priority readiness gaps are:

1. Normalize CLI commands into a polished `check`/`run`/`compile`/`report`
   surface.
2. Improve source locations for nested runtime errors.
3. Decide the Bool executable output format before a polished substrate
   release.
4. Keep CI and release packaging aligned with the native executable workflow.

For the active project target, the next readiness frontier is the Haskell 2010
frontend/Core/STG/lazy-runtime path.

## 2. Baseline Validation

Repository state observed during the stabilization pass:

- Branch: `dmelmanrogers/egglog-strict`
- Worktree: clean before stabilization edits.
- Latest relevant commits:
  - `5ab0b77 Add native executable compile mode`
  - `5a6d184 Add checked LLVM division lowering`
  - `88d2f5e Add sound Egglog strictness guards`
  - `45578d4 Add compiler readiness audit`

Baseline commands:

| Command | Result |
| --- | --- |
| `git status` | Completed; working tree clean before stabilization edits. |
| `git branch --show-current` | Completed; branch was `dmelmanrogers/egglog-strict`. |
| `git log --oneline -n 12` | Completed; recent commits listed above. |
| `git diff --check` | Passed. |
| `cabal build all` | Passed. |
| `cabal test all` | Passed. |
| `cabal check` | Passed with no package warnings or errors. |

Representative CLI checks:

| Mode | Program | Result |
| --- | --- | --- |
| Report | `examples/test.hg` | Passed; produced report with result `14` and Egglog optimization to `14`. |
| Report | `examples/if.hg` | Passed. |
| Report | `examples/inc.hg` | Passed. |
| Report | `examples/add.hg` | Passed. |
| Report | `examples/higher-order.hg` | Passed. |
| LLVM run | `examples/llvm/arithmetic.hg` | Passed; output `14`. |
| LLVM run | `examples/llvm/if-true.hg` | Passed; output `10`. |
| LLVM run | `examples/llvm/if-comparison.hg` | Passed; output `6`. |
| LLVM run | `examples/llvm/nested-if.hg` | Passed; output `2`. |
| LLVM run | `examples/llvm/let-chain.hg` | Passed; output `21`. |
| LLVM run | `examples/llvm/bool-root.hg` | Passed; output `1`. |
| LLVM run | `examples/llvm/top-level.hg` | Passed; output `42`. |
| LLVM run | `examples/inc.hg` | Passed; lambda-lifted output `42`. |
| LLVM run | `examples/add.hg` | Passed; lambda-lifted output `7`. |
| LLVM run | `examples/higher-order.hg` | Passed; closure output `42`. |
| LLVM emit | `examples/llvm/arithmetic.hg --emit-llvm -o .context/audit-cli/arithmetic.ll` | Passed; wrote LLVM IR text. |
| Native output path | `examples/llvm/arithmetic.hg -o .context/audit-cli/program` | Passed when `clang` was available; produced a native executable. |
| Native output path | `examples/llvm/division.hg -o /tmp/hegglog-division-no-egglog --no-egglog` | Passed; output `5`. |
| Native Bool root | `examples/llvm/bool-root.hg -o /tmp/hegglog-bool` | Passed; output `1`. |

## 3. Current End-to-End Compiler Capability

The compiler can currently process a source file through the following end-to-end paths:

1. Source report path:
   - Parse.
   - Typecheck and elaborate.
   - Interpret source.
   - Convert to ANF.
   - Validate ANF.
   - Interpret ANF.
   - Run simplifier/e-graph/Egglog reporting.
   - Print a rich report.

2. LLVM compile/run path:
   - Parse located source.
   - Typecheck and elaborate.
   - Lambda lift and re-typecheck.
   - Convert to ANF.
   - Optionally closure-convert if local closures are required.
   - Validate backend-compatible ANF or closure-converted backend IR.
   - Optionally run Egglog optimization for supported expression programs.
   - Lower to backend IR.
   - Lower backend IR to LLVM.
   - Emit LLVM text or compile it to a native executable with `clang`.
   - Optionally validate LLVM with `llvm-as`.
   - Optionally run LLVM text with `lli` or a temporary clang executable.
   - Optionally run the requested native executable.

The compiler can run generated code for representative examples with the
installed toolchain and can produce a persistent native executable as the normal
compile output artifact.

## 4. Current Source Language

Implemented source-level language features:

- `Int` literals.
- `Bool` literals.
- Variables.
- `let` bindings, including nesting and shadowing.
- `if` expressions.
- Integer arithmetic: `+`, `-`, `*`, `/`.
- Comparisons: `<`, `==`.
- Lambda expressions.
- Function application.
- Top-level function definitions.
- Optional lambda parameter annotations.
- Local higher-order functions through closure conversion.

Not currently implemented as source features:

- Dedicated boolean operators such as `&&`, `||`, `not`.
- Recursion.
- Algebraic data types.
- Pattern matching.
- Modules and imports.
- Strings, arrays, records, tuples, or user-defined structs.
- Native FFI.
- A package/build model.

The implemented language is enough to exercise a real compiler pipeline, but it remains a compact expression language rather than a general-purpose language.

## 5. Feature Support Matrix

| Feature | Parse | Typecheck | Interpret | ANF | Optimize | LLVM compile/run | Docs | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Int literals | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Fully supported in current subset. |
| Bool literals | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | LLVM prints bool roots as `0`/`1`. |
| Variables | Yes | Yes | Yes | Yes | Yes | Yes for closed programs | Yes | Yes | Free source variables are rejected. |
| `let` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Nested lets and shadowing are covered. |
| `if` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Condition must be Bool. |
| `+` | Yes | Yes | Yes | Yes | Yes | Yes, checked | Yes | Yes | LLVM uses checked Int64 behavior. |
| `-` | Yes | Yes | Yes | Yes | Yes | Yes, checked | Yes | Yes | LLVM checked subtraction is present. |
| `*` | Yes | Yes | Yes | Yes | Yes | Yes, checked | Yes | Yes | Current Egglog defaults avoid unsafe zero rewrites. |
| `/` | Yes | Yes | Yes | Yes | Egglog yes | Yes, checked | Yes | Yes | LLVM checks division by zero and minimum `Int / -1` before `sdiv`. |
| `<` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Integer comparison supported. |
| Integer `==` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Supported in LLVM and Egglog. |
| Boolean `==` | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Supported; Phase 8 adds strict-safe boolean Egglog rewrites. |
| Boolean operators | No | No | No | No | No | No | Mostly no | No | Can be encoded with `if` and `==`. |
| Lambdas | Yes | Yes | Yes | Yes | Limited | Yes for supported closures | Yes | Yes | Egglog does not optimize closure-converted programs. |
| Applications | Yes | Yes | Yes | Yes | Limited | Yes for supported call forms | Yes | Yes | Top-level partial applications are rejected. |
| Top-level definitions | Yes | Yes | Yes | Yes | Fallback | Yes | Yes | Yes | Egglog currently falls back for programs with definitions. |
| Non-capturing lambdas | Yes | Yes | Yes | Yes | Fallback | Yes via lambda lifting | Yes | Yes | Covered by examples. |
| Capturing lambdas | Yes | Yes | Yes | Yes | Fallback | Yes via closure conversion | Yes | Yes | Process-lifetime closure allocation. |
| Higher-order functions | Yes | Yes | Yes | Yes | Fallback | Partially yes | Yes | Yes | Local closure examples work. |
| Function-valued roots | Yes | Yes | Source yes | Yes | No | No | Yes | Some | LLVM rejects function-valued program roots. |
| Recursion | No | No | No | No | No | No | No | No | Not a current source feature. |
| Open programs | No source execution | Rejected if unbound | No | ANF fragments yes | Egglog fragments yes | No | Partial | Partial | Useful internally but not a source artifact mode. |
| ADTs/patterns/modules | No | No | No | No | No | No | No | No | Out of scope for `.hg`; the separate Haskell 2010 path now has an initial ADT/pattern slice. |

## 6. Pipeline Inventory

Major implementation areas:

- `Syntax.AST`, `Syntax.Located`, `Syntax.Parser`, `Syntax.Pretty`, `Syntax.Span`
  - Source syntax, located parsing, spans, and pretty-printing.
- `Typecheck.Types`, `Typecheck.Infer`, `Typecheck.Principal`
  - Type representation, inference, elaboration, principal-type checks.
- `Eval.Interpreter`, `Eval.ANFInterpreter`
  - Source and ANF execution.
- `IR.ANF`, `IR.ANF.Resolved`, `IR.ANF.Validate`, `IR.Core`
  - ANF representation, resolved ANF for optimization, validation, and older core IR work.
- `Analysis.Facts`, `Analysis.InferFacts`
  - Static fact inference used by optimizers.
- `Optimize.Simplify`, `Optimize.Rewrite`, `Optimize.EGraph`
  - Direct simplification, rewrite definitions, and an e-graph prototype.
- `Egglog.*`
  - The internal Egglog-like engine: database, rules, patterns, functions, extraction, rebuild, union-find, values, and pretty-printer.
- `Optimize.EgglogBackend.*`
  - ANF-to-Egglog optimization backend, rules, zero-info lattice, join planning, semi-naive evaluation, provenance, extraction, and validation.
- `Backend.LambdaLift`, `Backend.ClosureConvert`, `Backend.Lower`, `Backend.Validate`, `Backend.IR`, `Backend.Pretty`, `Backend.Compile`
  - Compiler backend pipeline and backend IR.
- `Backend.LLVM.*`
  - LLVM IR model, lowering, emission, validation, and toolchain interaction.
- `CLI.Report`, `Main`
  - User-facing report and compile commands.

The pipeline is reasonably modular. The main architectural split is between:

- The source/report path, which is broad and introspective.
- The compiler/backend path, which is narrower and emits LLVM text or native
  executables.
- The optimizer paths, where simplifier/e-graph are mostly reporting/prototype paths and Egglog is the real compile-time optimizer when supported.

## 7. Semantics Consistency Audit

The intended runtime model is strict and checked:

- Source evaluation is strict.
- `Int` is signed 64-bit.
- Arithmetic overflow is a runtime error.
- Division by zero is a runtime error.
- `minBound / -1` is a runtime error.
- `if` evaluates only the selected branch after evaluating the condition.
- `let` evaluates the right-hand side before the body.

The implementation mostly respects this model:

- Interpreters implement checked arithmetic.
- LLVM lowering implements checked `+`, `-`, `*`, and `/`.
- LLVM checks division by zero and minimum `Int / -1` before emitting `sdiv`.
- The Egglog backend now has specific runtime-error preservation checks and avoids the dangerous default rewrites that would drop strict dependencies.

Important consistency gaps:

1. Runtime-error source spans are still coarse.
   - The located parser and type errors have useful source positions.
   - Runtime errors are not yet consistently mapped to the most precise nested source expression.
   - This is a usability and debugging gap rather than a core semantic unsoundness.

3. Bool output differs by path.
   - Source reports print Bool values as language values.
   - LLVM executable output prints root Bool values as `0` or `1`.
   - This is documented as a decision point and should be resolved before a polished v1.

4. Function-valued results are not a backend-supported artifact.
   - Source semantics can represent function values.
   - LLVM roots must be printable scalar roots.
   - This is acceptable if documented as a backend restriction.

## 8. Optimizer Correctness Audit

The optimizer stack has three distinct layers:

- A direct simplifier.
- An e-graph prototype.
- The Egglog backend.

The Egglog backend is the only optimizer enabled by default in the compile path. It is used only when the current program shape is supported; otherwise compile continues with the original ANF and records the fallback in module comments.

Strong points:

- Optimized ANF is validated.
- Type preservation is checked.
- Runtime-error behavior is checked in Egglog backend tests.
- Extraction is deterministic.
- The backend has a cost model and reports cost changes.
- Unsupported features fall back instead of being miscompiled.
- The current strictness baseline removes unsafe default rewrites:
  - Open `x * 0 = 0`.
  - `x == x = true`.
  - `x < x = false`.
  - `if c then a else a = a`.
- Phase 8 adds strict-safe boolean rewrites:
  - `b == true -> b`.
  - `true == b -> b`.
  - `if b then true else false -> b`.
  - `if b then false else true -> b == false`.

Remaining risks:

1. Optimizer coverage is shape-limited.
   - Top-level definitions and closure-converted programs are currently outside Egglog optimization.
   - This is safe, but leaves optimization potential unused.

2. Multiple optimizer implementations increase drift risk.
   - The simplifier, e-graph prototype, and Egglog rules do not all share one declarative rewrite source.
   - This is manageable while only Egglog is compiler-active, but it should be documented and tested.

3. The e-graph path remains prototype-grade.
   - It is useful for report/debugging, but should not be marketed as the production optimizer until it has the same strictness and runtime-error preservation discipline as Egglog.

## 9. LLVM Backend Audit

The LLVM backend is credible for its declared subset.

Supported:

- `Int` and `Bool` roots.
- Checked `+`, `-`, `*`.
- `<` and `==`.
- `let`.
- `if`.
- Top-level first-order calls.
- Lambda-lifted non-capturing functions.
- Closure-converted local capturing functions.
- LLVM text emission.
- Native executable output via `clang`.
- LLVM validation through `llvm-as` when available.
- LLVM execution through `lli` when available, with clang fallback.

Unsupported:

- Function-valued roots.
- Partial top-level application.
- Top-level function values as first-class values.
- Overapplied top-level calls.
- Recursion.
- Heap ownership beyond process-lifetime closure allocation.

The most important user-facing LLVM finding is now CLI polish rather than
artifact production. In compile mode, `-o path` produces a native executable and
`--emit-llvm -o path.ll` writes LLVM text. A practical v1 should still normalize
top-level commands and stdout/stderr behavior so ordinary users have a simpler
`check`/`run`/`compile` story.

## 10. Runtime Audit

The checked-runtime model is well specified and substantially implemented:

- Addition, subtraction, multiplication, and division are checked in LLVM.
- Division is checked in interpreters, Egglog reasoning, and LLVM lowering.
- Runtime traps are represented cleanly enough for tests.
- Closure allocation is intentionally process-lifetime allocation.

Readiness gaps:

- Decide whether Bool roots should print as `true`/`false` or remain `0`/`1`.
- Add more precise source locations for runtime errors.
- Decide whether process-lifetime closure allocation is acceptable for v1 or whether explicit ownership/freeing is required.

The current runtime model is good enough for a small language compiler, but
diagnostics, Bool output policy, and CLI polish should be completed before
claiming polished compiler readiness.

## 11. Diagnostics And User Experience Audit

Current strengths:

- Type errors are structured and golden-tested.
- Backend unsupported errors are explicit.
- LLVM tool absence is handled gracefully in tests.
- Report mode provides unusually rich compiler visibility.

Current weaknesses:

- Parser errors mostly expose Megaparsec-style formatting rather than a normalized compiler diagnostic format.
- Runtime errors lack consistently precise nested spans.
- CLI shape is still transitional:
  - Passing a file path directly runs report mode.
  - `compile -o` emits a native executable.
  - `compile --emit-llvm` emits LLVM text.
  - `--run-llvm` runs generated code.
  - `--run-llvm` prints program output to stderr so stdout can remain usable for LLVM text.
  - `--run` builds and runs a requested native executable.
- There is no clean `hegglog run file.hg` command for ordinary users.

For compiler readiness, the CLI should eventually separate:

- `hegglog check file.hg`
- `hegglog run file.hg`
- `hegglog compile file.hg -o program`
- `hegglog compile file.hg --emit-llvm -o program.ll`
- `hegglog report file.hg`

This is not required for internal correctness, but it is important for a polished compiler.

## 12. Documentation And Code Consistency Audit

Documentation is generally in good shape for an active compiler project:

- `README.md` describes the language and LLVM support accurately at a high level.
- `docs/language-spec.md` identifies the implemented language and open decisions.
- `docs/runtime-spec.md` documents checked Int64 semantics and runtime errors.
- `docs/llvm-backend-spec.md` describes the v0 LLVM fragment and fallback behavior.
- `docs/egglog-backend.md` documents the current Egglog backend and strictness
  improvements.
- `docs/roadmap.md` is being actively updated with phase status.

Previously resolved inconsistency:

- `docs/runtime-spec.md` now correctly explains that open multiplication by
  zero is not a default Egglog compiler rule because it can erase strict
  runtime errors from local bindings.

Other docs gaps:

- There is no single consolidated optimizer-soundness spec.
- There is no single Egglog engine implementation spec separate from backend-facing docs.
- Several docs still have decision-needed sections, which is acceptable during development but should be resolved before a v1 claim.
- The docs do not yet present a crisp "compilable subset" table for users.

## 13. Test Coverage Audit

The test suite is broad and meaningful. It covers:

- Parser behavior and syntax failures.
- Type inference and type errors.
- Diagnostics goldens.
- Source interpreter behavior.
- ANF conversion and validation.
- ANF interpreter behavior.
- Direct simplifier behavior.
- E-graph prototype behavior.
- Egglog engine and backend behavior.
- Egglog strict runtime-error preservation.
- LLVM lowering, validation, execution, and goldens.
- Closure conversion and lambda lifting examples.
- Some property tests.

Strong points:

- Tests cover both successful execution and rejected unsupported backend cases.
- LLVM tests include runtime overflow behavior for supported arithmetic.
- Native executable tests cover representative successful programs and a
  runtime-error executable when `clang` is available.
- Egglog tests now include strictness-sensitive optimization cases.
- Golden tests make report shape visible.
- External LLVM tool tests skip rather than fail when tools are unavailable.

Coverage gaps:

1. Actual process-level CLI tests are thinner than library-level tests.
2. Parser diagnostics are not fully normalized and goldened as compiler diagnostics.
3. Runtime-error source-span precision is not deeply tested.
4. Property tests are useful but bounded and do not replace end-to-end fuzzing.
5. Closure memory ownership is not stress-tested because the current model is process-lifetime allocation.

Overall, the test suite is strong for the implementation stage. The next test
investments should focus on process-level CLI coverage, CLI normalization, and
diagnostics.

## 14. Architecture Risks

| Risk | Severity | Why It Matters | Recommended Response |
| --- | --- | --- | --- |
| CLI mode confusion | Medium | Report, compile, emit, and run modes are not yet user-clean. | Introduce `check`, `run`, `compile`, `report`. |
| Docs drift | Medium | Multiple specs can contradict code as semantics evolve. | Add docs consistency checks and resolve stale runtime text. |
| Optimizer implementation drift | Medium | Simplifier, e-graph, and Egglog rules may diverge. | Keep only one production optimizer active or share rule specs. |
| Closure memory model | Medium | Process-lifetime allocation is okay for examples but not long-running programs. | Decide v1 scope; document or implement ownership. |
| Runtime span precision | Medium | Correct compiler errors still feel poor if they point to broad expressions. | Thread source spans deeper into runtime errors. |
| LLVM tool skipping | Low/Medium | Tests can pass on machines without LLVM tools, hiding integration issues. | Add CI lane with required LLVM tools. |
| Branch/worktree state | Medium | Dirty changes and branch divergence complicate release confidence. | Land or isolate Phase 8 changes, then audit from clean main. |

## 15. Fully Working Compiler Gap List

To claim HeggLog is a fully working compiler for its current source language, the project still needs:

1. A clean CLI contract for checking, running, compiling, reporting, and emitting LLVM.
2. Process-level CLI tests that verify native artifacts run outside the compiler process.
3. Precise runtime-error diagnostics.
4. A documented v1 language subset table.
5. Docs reconciliation for stale optimizer/runtime claims.
6. A CI lane that actually has `lli`, `llvm-as`, and clang available.
7. A decision on Bool output format.
8. A decision on closure lifetime/ownership scope.
9. A release-oriented README path that teaches normal users the simplest successful workflow.

Items not required for a v1 of the current language, but required for a larger general-purpose language:

- Recursion.
- Broader ADTs and pattern matching.
- Modules/imports.
- Strings and aggregate data types.
- Better package/build support.
- A stable ABI/runtime library story.

## 16. Prioritized Roadmap To Full Compiler

### Phase A: Artifact Correctness

Goal: make `hegglog compile` behave like a real compiler command.

Tasks:

1. Completed: add native executable output mode.
2. Completed: keep LLVM text output behind explicit `--emit-llvm`.
3. Partial: add library-level native artifact tests; add process-level CLI tests
   next.
4. Completed: update README and LLVM backend docs.

Exit criteria:

- `hegglog compile examples/llvm/arithmetic.hg -o /tmp/arithmetic` creates an executable.
- Running the executable prints `14`.
- `hegglog compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/arithmetic.ll` writes LLVM text.

### Phase B: Full Current-Source Arithmetic

Goal: make `/` compile with the same checked semantics as the interpreter.

Tasks:

1. Completed: add backend IR division.
2. Completed: lower checked division to LLVM.
3. Completed: handle division by zero.
4. Completed: handle `minBound / -1`.
5. Completed: add interpreter-vs-LLVM tests for successful division and both failure cases.

Exit criteria:

- Source programs using `/` compile and run through LLVM.
- Runtime failures match interpreter behavior.
- Unsupported division rejection is removed for otherwise supported programs.

### Phase C: CLI And Diagnostics

Goal: make the compiler pleasant and predictable to use.

Tasks:

1. Add `check`, `run`, `compile`, and `report` commands.
2. Normalize stdout/stderr behavior.
3. Normalize parser diagnostics.
4. Thread precise source spans into runtime errors.
5. Golden-test CLI diagnostics.

Exit criteria:

- Normal users do not need to understand `--run-llvm`.
- Errors point to the smallest useful source span.
- CLI output is deterministic and golden-tested.

### Phase D: Optimizer Integration And Specs

Goal: preserve optimizer correctness as coverage grows.

Tasks:

1. Write a compact optimizer soundness spec.
2. Decide the production status of simplifier and e-graph paths.
3. Expand Egglog support to top-level-definition programs where safe.
4. Add more optimizer differential tests.

Exit criteria:

- Docs and tests describe the same strictness model.
- Production optimizer behavior is clearly separated from prototypes.
- No optimization can silently remove a strict runtime-error dependency.

### Phase E: Release Readiness

Goal: make the compiler reliable from a fresh checkout.

Tasks:

1. Add a CI lane with LLVM tools installed.
2. Add a v1 language subset document.
3. Add installation/build/run instructions.
4. Decide Bool output format.
5. Decide closure lifetime scope for v1.

Exit criteria:

- A new contributor can build, test, compile, and run examples from docs.
- CI proves the LLVM path on every relevant PR.
- Remaining language limitations are explicit, not surprising.

## 17. Recommended Next Five Implementation Tasks

1. Commit the roadmap pivot.
   - Files likely affected: docs and README.
   - Acceptance: the project identity, Haskell 2010 target, `.hg` substrate,
     Egglog role, and LLVM/native output role are clear and internally
     consistent.
   - Suggested commit: `Set Haskell 2010 native compiler roadmap`

2. Build the Haskell 2010 parser/layout MVP.
   - Files likely affected: `src/Haskell2010/*`, tests, docs.
   - Acceptance: layout-sensitive parsing works for a documented Core-0 source
     subset while the existing `.hg` parser still works.
   - Suggested commit: `Add Haskell 2010 parser layout MVP`

3. Add the renamer MVP.
   - Files likely affected: `src/Haskell2010/Names.hs`,
     `src/Haskell2010/Scope.hs`, `src/Haskell2010/Renamer.hs`, tests.
   - Acceptance: every accepted occurrence resolves to a unique binder or
     fails with a source-spanned diagnostic.
   - Suggested commit: `Add Haskell 2010 renamer MVP`

4. Add typed Core MVP.
   - Files likely affected: `src/Core/*`, `src/Haskell2010/Desugar.hs`, tests.
   - Acceptance: parsed/renamed Core-0 programs desugar to validated typed
     Core.
   - Suggested commit: `Add typed Core MVP`

5. Start the lazy/STG runtime MVP.
   - Files likely affected: `src/STG/*`, runtime files, LLVM backend
     integration, tests.
   - Acceptance: Core-0 lazy examples validate and run through a native wet
     path.
   - Suggested commit: `Add lazy runtime MVP`

## 18. Historical Readiness Verdict

HeggLog is ready to be described as an actively working native compiler
baseline for the documented strict `.hg` subset, with a real typed frontend,
optimizer stack, closure-aware backend path, LLVM execution path, native
executable output, and mandatory wet tests.

At the time of this historical audit, it was not yet ready to be described as a
Haskell 2010 compiler. That verdict has been superseded by later Haskell 2010
work: the current repository compiles the documented executable Haskell 2010
subset to native executables through LLVM and clang. Remaining Haskell 2010
work is tracked in the current roadmap/status/conformance documents rather than
this substrate audit.
