# Compiler Readiness Audit

Date: 2026-05-17

This audit evaluates the current HeggLog codebase as a compiler implementation, with emphasis on end-to-end readiness, semantic correctness, optimizer safety, LLVM backend completeness, diagnostics, tests, documentation, and remaining work required for a practical v1 compiler.

The audit was performed against the current working tree, not only committed `HEAD`. At audit time the worktree included uncommitted Phase 8 Egglog backend and roadmap changes in:

- `docs/egglog-backend.md`
- `docs/roadmap.md`
- `src/Optimize/EgglogBackend/Rules.hs`
- `test/Main.hs`

Those changes materially affect this audit because they remove unsafe default Egglog rewrites and mark Phase 8 complete.

## 1. Executive Summary

HeggLog is a credible partial compiler for a well-defined, typed expression language subset. It currently has the major pieces expected of a small compiler:

- Located parsing for source files.
- Type inference and elaboration, including optional lambda annotations.
- Source interpreter and ANF interpreter.
- ANF conversion and validation.
- A simplifier, an experimental e-graph path, and a more substantial Egglog-style optimizer backend.
- Lambda lifting and closure conversion.
- Backend IR validation and LLVM text emission.
- LLVM validation and execution through external LLVM tools.
- A meaningful test suite across parser, typechecker, interpreter, optimizer, backend, goldens, and properties.

The project is not yet a fully working production compiler in the ordinary user-facing sense. The largest gap is artifact production: `hegglog compile file.hg -o program` currently writes LLVM IR text to `program`; it does not produce a native executable. Native execution is available only through `--run-llvm`, using `lli` or a temporary clang path.

The LLVM backend is correct-looking and well tested for its intended subset: closed `Int`/`Bool` roots, `let`, `if`, checked `+`, `-`, `*`, `<`, `==`, top-level first-order calls, lambda lifting, and local closures. Division remains unsupported in LLVM compile mode, even though the interpreter, ANF, runtime semantics, and Egglog backend know about checked division.

The optimizer story is better than the average experimental compiler at this stage. The default compiler path uses the Egglog backend when supported and falls back explicitly when unsupported. The current uncommitted Phase 8 changes also remove several unsafe default rewrites that would otherwise violate strict runtime-error preservation. This materially improves compiler trustworthiness.

The highest-priority readiness gaps are:

1. Add real native executable output mode.
2. Lower checked division to LLVM.
3. Normalize CLI commands and stdout/stderr behavior.
4. Improve source locations for nested runtime errors.
5. Reconcile docs drift, especially the stale runtime-spec statement about `x * 0`.

## 2. Baseline Validation

Repository state observed during the audit:

- Branch: `dmelmanrogers/top-def-calls`
- Tracking state: branch and `origin/dmelmanrogers/egglog-audit` had diverged; local branch had 36 commits not on the remote, and the remote had 6 commits not local.
- Worktree: dirty, with the Phase 8 files listed above.
- Recent commits:
  - `7e11cc3 Add checked Egglog division`
  - `f831618 Add checked Egglog subtraction`
  - `fff77a6 Extend Egglog backend to comparisons`
  - `6148b48 Add Egglog zero-info lattice`
  - `61b2fbc Add Egglog join planning`
  - `7f40768 Add Egglog provenance traces`
  - `9c3349f Add semi-naive Egglog evaluation`
  - `1b3972f Add optional lambda inference`
  - `749c300 Define type inference direction`
  - `1c9d08f Add closure conversion runtime`

Baseline commands:

| Command | Result |
| --- | --- |
| `git status` | Completed; dirty working tree as described above. |
| `git log --oneline -n 10` | Completed; recent commits listed above. |
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
| LLVM output path | `examples/llvm/arithmetic.hg -o .context/audit-cli/program` | Passed, but wrote LLVM IR text to `program`; did not produce a native executable. |

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
   - Emit LLVM text.
   - Optionally validate LLVM with `llvm-as`.
   - Optionally run LLVM text with `lli` or a temporary clang executable.

The compiler can run generated code for representative examples with the installed toolchain. It cannot yet produce a persistent native executable as the normal output artifact.

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
| `/` | Yes | Yes | Yes | Yes | Egglog yes | No | Yes | Yes | Compile mode rejects source division before LLVM lowering. |
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
| ADTs/patterns/modules | No | No | No | No | No | No | No | No | Out of scope today. |

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
- The compiler/backend path, which is narrower and emits LLVM text.
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
- LLVM lowering implements checked `+`, `-`, and `*`.
- LLVM rejects division structurally instead of lowering it unsafely.
- The Egglog backend now has specific runtime-error preservation checks and avoids the dangerous default rewrites that would drop strict dependencies.

Important consistency gaps:

1. LLVM division is missing.
   - Source and interpreter support division.
   - Egglog supports checked division reasoning.
   - Backend compile mode still rejects source division before LLVM lowering.
   - This means the full source language is not compilable.

2. Runtime-error source spans are still coarse.
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
- The uncommitted Phase 8 changes remove unsafe default rewrites:
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

2. Compile mode rejects division too early for Egglog to help LLVM.
   - Even a constant or provably safe division cannot currently be optimized away before the structural LLVM division rejection.
   - This makes Egglog division support useful in report/backend tests but not yet useful for end-to-end source division compilation.

3. Multiple optimizer implementations increase drift risk.
   - The simplifier, e-graph prototype, and Egglog rules do not all share one declarative rewrite source.
   - This is manageable while only Egglog is compiler-active, but it should be documented and tested.

4. The e-graph path remains prototype-grade.
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
- LLVM validation through `llvm-as` when available.
- LLVM execution through `lli` when available, with clang fallback.

Unsupported:

- Division lowering.
- Native executable output as the ordinary `-o` artifact.
- Function-valued roots.
- Partial top-level application.
- Top-level function values as first-class values.
- Overapplied top-level calls.
- Recursion.
- Heap ownership beyond process-lifetime closure allocation.

The most important user-facing finding is the current meaning of `-o`. In compile mode, `-o path` writes LLVM IR text to `path`; it does not produce a native binary. This is surprising for a compiler CLI. A practical v1 should make native executable output the default compile artifact and move LLVM text behind `--emit-llvm`.

## 10. Runtime Audit

The checked-runtime model is well specified and substantially implemented:

- Addition, subtraction, and multiplication are checked in LLVM.
- Division is checked in interpreters and Egglog reasoning, but not lowered to LLVM.
- Runtime traps are represented cleanly enough for tests.
- Closure allocation is intentionally process-lifetime allocation.

Readiness gaps:

- Add checked division lowering.
- Decide whether Bool roots should print as `true`/`false` or remain `0`/`1`.
- Add more precise source locations for runtime errors.
- Decide whether process-lifetime closure allocation is acceptable for v1 or whether explicit ownership/freeing is required.

The current runtime model is good enough for a small language compiler, but division and diagnostics should be completed before claiming full source-language compilation.

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
  - `compile` emits LLVM text.
  - `--run-llvm` runs generated code.
  - `--run-llvm` prints program output to stderr so stdout can remain usable for LLVM text.
- `-o` does not produce a native executable.
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
- `docs/egglog-backend.md` documents the current Egglog backend and, in the dirty working tree, Phase 8 strictness improvements.
- `docs/roadmap.md` is being actively updated with phase status.

Known inconsistency:

- `docs/runtime-spec.md` still contains an outdated claim that `x * 0 -> 0` is safe in ANF because `x` has already been evaluated. The current Egglog backend correctly treats this as unsafe in the presence of strict local bindings whose right-hand side may fail. This stale text should be corrected.

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
- Egglog tests now include strictness-sensitive optimization cases.
- Golden tests make report shape visible.
- External LLVM tool tests skip rather than fail when tools are unavailable.

Coverage gaps:

1. Native executable output cannot be tested because it does not exist yet.
2. Source division cannot be compiled to LLVM, so interpreter-vs-LLVM division equivalence is absent.
3. Actual process-level CLI tests are thinner than library-level tests.
4. Parser diagnostics are not fully normalized and goldened as compiler diagnostics.
5. Runtime-error source-span precision is not deeply tested.
6. Property tests are useful but bounded and do not replace end-to-end fuzzing.
7. Closure memory ownership is not stress-tested because the current model is process-lifetime allocation.

Overall, the test suite is strong for the implementation stage. The next test investments should follow artifact output, division lowering, and CLI normalization.

## 14. Architecture Risks

| Risk | Severity | Why It Matters | Recommended Response |
| --- | --- | --- | --- |
| No native executable output | High | Users expect `compile -o program` to create an executable. | Add native output mode and make LLVM text explicit. |
| LLVM division missing | High | The source language supports `/`, but the compiler cannot compile it. | Implement checked LLVM division. |
| Early division rejection | High | Egglog cannot optimize away even safe or constant divisions before backend rejection. | Move unsupported checks after optimization or add division lowering. |
| CLI mode confusion | Medium | Report, compile, emit, and run modes are not yet user-clean. | Introduce `check`, `run`, `compile`, `report`. |
| Docs drift | Medium | Multiple specs can contradict code as semantics evolve. | Add docs consistency checks and resolve stale runtime text. |
| Optimizer implementation drift | Medium | Simplifier, e-graph, and Egglog rules may diverge. | Keep only one production optimizer active or share rule specs. |
| Closure memory model | Medium | Process-lifetime allocation is okay for examples but not long-running programs. | Decide v1 scope; document or implement ownership. |
| Runtime span precision | Medium | Correct compiler errors still feel poor if they point to broad expressions. | Thread source spans deeper into runtime errors. |
| LLVM tool skipping | Low/Medium | Tests can pass on machines without LLVM tools, hiding integration issues. | Add CI lane with required LLVM tools. |
| Branch/worktree state | Medium | Dirty changes and branch divergence complicate release confidence. | Land or isolate Phase 8 changes, then audit from clean main. |

## 15. Fully Working Compiler Gap List

To claim HeggLog is a fully working compiler for its current source language, the project still needs:

1. Native executable output.
2. Checked LLVM division lowering.
3. A clean CLI contract for checking, running, compiling, reporting, and emitting LLVM.
4. End-to-end tests that verify native artifacts run outside the compiler process.
5. Source/LLVM equivalence tests for division success and division runtime failures.
6. Precise runtime-error diagnostics.
7. A documented v1 language subset table.
8. Docs reconciliation for stale optimizer/runtime claims.
9. A CI lane that actually has `lli`, `llvm-as`, and clang available.
10. A decision on Bool output format.
11. A decision on closure lifetime/ownership scope.
12. A release-oriented README path that teaches normal users the simplest successful workflow.

Items not required for a v1 of the current language, but required for a larger general-purpose language:

- Recursion.
- ADTs and pattern matching.
- Modules/imports.
- Strings and aggregate data types.
- Better package/build support.
- A stable ABI/runtime library story.

## 16. Prioritized Roadmap To Full Compiler

### Phase A: Artifact Correctness

Goal: make `hegglog compile` behave like a real compiler command.

Tasks:

1. Add native executable output mode.
2. Keep LLVM text output behind explicit `--emit-llvm`.
3. Add process-level CLI tests for output files and executable behavior.
4. Update README and LLVM backend docs.

Exit criteria:

- `hegglog compile examples/llvm/arithmetic.hg -o /tmp/arithmetic` creates an executable.
- Running the executable prints `14`.
- `hegglog compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/arithmetic.ll` writes LLVM text.

### Phase B: Full Current-Source Arithmetic

Goal: make `/` compile with the same checked semantics as the interpreter.

Tasks:

1. Add backend IR division if not already represented in the backend lowering path.
2. Lower checked division to LLVM.
3. Handle division by zero.
4. Handle `minBound / -1`.
5. Add interpreter-vs-LLVM tests for successful division and both failure cases.

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

1. Fix the stale runtime spec statement about `x * 0`.
2. Write a compact optimizer soundness spec.
3. Decide the production status of simplifier and e-graph paths.
4. Expand Egglog support to top-level-definition programs where safe.
5. Add more optimizer differential tests.

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

1. Add native executable output mode.
   - Files likely affected: `src/Main.hs`, `src/Backend/LLVM/Toolchain.hs`, `src/Backend/Compile.hs`, README, LLVM docs, tests.
   - Acceptance: `hegglog compile file.hg -o program` produces an executable; `--emit-llvm` produces LLVM text.
   - Suggested commit: `Add native executable output mode`

2. Lower checked division to LLVM.
   - Files likely affected: backend IR, backend lowering, LLVM lowering/emission, validators, runtime docs, tests.
   - Acceptance: division success, division-by-zero, and `minBound / -1` match interpreter behavior.
   - Suggested commit: `Lower checked division to LLVM`

3. Normalize the CLI command model.
   - Files likely affected: `src/Main.hs`, `src/CLI/Report.hs`, README, CLI/golden tests.
   - Acceptance: `check`, `run`, `compile`, and `report` have clear stdout/stderr and exit-code behavior.
   - Suggested commit: `Normalize compiler CLI commands`

4. Track precise runtime-error source spans.
   - Files likely affected: located syntax, ANF/source mapping, interpreters, compile diagnostics, tests.
   - Acceptance: nested runtime errors report the smallest useful source expression.
   - Suggested commit: `Track runtime error source spans`

5. Finalize v1 docs and CI tooling.
   - Files likely affected: docs, README, CI config, examples.
   - Acceptance: docs no longer contradict current strictness rules; CI exercises LLVM tools; v1 language subset is explicit.
   - Suggested commit: `Finalize compiler v1 docs`

## 18. Readiness Verdict

HeggLog is ready to be described as an actively working compiler prototype with a real typed frontend, optimizer stack, closure-aware backend path, and LLVM execution path for a defined subset.

It is not yet ready to be described as a complete compiler for its own current source language because source division does not compile to LLVM and because `compile -o` does not produce a native executable.

The implementation direction is sound. The next best work is not more abstract architecture; it is closing the concrete artifact and source-language completeness gaps: native executable output, checked LLVM division, CLI normalization, precise runtime diagnostics, and final docs reconciliation.
