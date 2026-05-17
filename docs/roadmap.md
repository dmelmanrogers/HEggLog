# HeggLog Roadmap

This roadmap is the project-level source of truth for what exists now, what is
being stabilized, and what should be built next. It is synchronized with the
current codebase as of the checked `Int64` semantics, Egglog backend, and LLVM
backend work.

## Current Baseline

Implemented:

- Parser and pretty-printer for expression-level HeggLog.
- Typechecker with explicit function parameter annotations.
- Source interpreter and ANF interpreter.
- ANF lowering, validation, and deterministic generated names.
- Resolved ANF with deterministic binder ids and explicit free variables.
- Fact inference over ANF.
- Sound local ANF simplifier with validation before and after optimization.
- Prototype e-graph optimizer for a narrow ANF fragment.
- Standalone Egglog-style kernel with sorts, values, functions, merge behavior,
  union-find, rebuild, rules, rewrite sugar, and extraction.
- Compiler-facing Egglog backend for typed pure first-order ANF: integer
  `Add`/`Mul`, boolean and integer `if`, constants, variables, and lets.
- Backend IR and LLVM backend v0 for closed first-order programs.
- CLI report mode and LLVM compile mode, including optional LLVM execution.
- HeggLog `Int` semantics as checked signed 64-bit values:
  - source and ANF interpreters use `HInt`
  - out-of-range literals are rejected
  - simplifier, e-graph prototype, and Egglog constants avoid overflowing folds
  - backend IR stores checked `HInt`
  - LLVM emits checked signed overflow intrinsics for `+`, `-`, and `*`
  - generated LLVM aborts on overflow
- Test coverage across parser, typechecker, interpreter, ANF, simplifier,
  e-graph prototype, Egglog kernel/backend, LLVM lowering, goldens, and
  QuickCheck properties.
- MIT license metadata.
- Minimal GitHub Actions CI for build, test, package metadata, and whitespace
  checks.
- Language and runtime specifications for the current expression language,
  checked `Int64` semantics, runtime errors, evaluation order, and current
  decision points.

Not implemented:

- Source spans in the AST.
- Rich diagnostics with file/line/column ranges.
- Top-level definitions.
- Backend support for first-order function calls beyond the current root.
- Lambda lifting.
- Closure conversion or closure runtime.
- Heap allocation and memory management policy.
- Hindley-Milner inference.
- Algebraic data types or pattern matching.
- Egglog semi-naive evaluation, join planning, and provenance.
- Release packaging beyond basic Cabal metadata.

## Phase 0 - Project Hygiene And Semantic Stabilization

Status: mostly complete.

Motivation: Make the current compiler checkpoint explicit, reproducible, and
semantically coherent before expanding the language.

Deliverables:

- Completed: commit the current checked-`Int64` LLVM/Egglog checkpoint.
- Completed: choose MIT and replace `license: NONE` in `hegglog.cabal`.
- Completed: run and fix `cabal check`.
- Completed: add a minimal CI workflow for `cabal build all`, `cabal test all`,
  `cabal check`, and `git diff --check`.
- Ongoing: keep `HInt` as the single language integer policy.
- Ongoing: keep docs synchronized with implementation boundaries.

Non-goals:

- New language features.
- Runtime allocation or closure support.
- Large optimizer expansion.

Acceptance criteria:

- Fresh checkout builds and tests with one command.
- `README.md`, `docs/llvm-backend.md`, `docs/egglog-backend.md`, and this
  roadmap agree on the implemented fragment.
- No documented arbitrary-precision/LLVM `i64` semantic gap remains.

Tests required:

- `cabal build all`
- `cabal test`
- `git diff --check`
- `cabal check`

Risks:

- Cabal metadata and CI can drift if not treated as part of the release surface.

Definition of done:

- The baseline is committed, licensed, and covered by CI.

## Phase 1 - Precise Language Semantics

Status: complete for the current language baseline.

Motivation: Ensure every frontend and backend observes the same language
contract.

Deliverables:

- Completed: write `docs/language-spec.md`.
- Completed: write `docs/runtime-spec.md`.
- Completed: specify lexical structure, grammar, expression forms, types,
  scoping, and evaluation order.
- Completed: specify nonrecursive `let`, shadowing, lambdas, application, and
  primitive operations.
- Completed: specify runtime values and runtime errors.
- Completed: document that source literals are currently unsigned decimal atoms,
  while runtime `Int` values are signed 64-bit.
- Completed: record the unary negative literal decision point and recommended
  direction.

Non-goals:

- Hindley-Milner inference.
- Top-level declarations.
- Pattern matching.

Acceptance criteria:

- The language spec can be used to decide whether parser, typechecker,
  interpreter, ANF interpreter, optimizers, and LLVM agree.
- Every current primitive has specified success and runtime-error behavior.

Tests required:

- Parser precedence tests.
- Typechecker negative fixture tests.
- Source-vs-ANF semantic preservation tests.
- Overflow and division-by-zero tests.

Risks:

- Adding signed literals naively can change tokenization of `x-1`; unary syntax
  must be designed deliberately.

Definition of done:

- There is a checked-in language/runtime spec pair and every current semantic
  decision is either explicit or marked as a decision needed.

## Phase 2 - Diagnostics And Source Spans

Status: not started.

Motivation: Structured errors are necessary before larger language features make
failures harder to inspect.

Deliverables:

- Add source spans to AST nodes or a parallel located AST.
- Preserve useful spans through typechecking and core diagnostics.
- Improve parser/typechecker/runtime/backend error rendering.
- Add `docs/diagnostics-spec.md`.

Non-goals:

- IDE protocol support.
- Full recovery parsing.

Acceptance criteria:

- Parser and typechecker errors include file, line, column, and a useful
  message.
- Backend unsupported-feature errors identify the source construct when
  possible.

Tests required:

- Golden negative diagnostics.
- Parser and typechecker fixture coverage.
- Backend unsupported diagnostics.

Risks:

- Retrofitting spans late can cause churn across syntax, typechecking, and ANF.

Definition of done:

- All user-facing compile errors have stable structured formatting.

## Phase 3 - LLVM Backend Correctness

Status: partial.

Motivation: LLVM must be a semantic implementation of the language fragment, not
just a printer for simple examples.

Deliverables:

- Keep checked arithmetic lowering for `+`, `-`, and `*`.
- Add runtime-error equivalence testing for overflow and, when division is
  supported, division by zero.
- Strengthen Backend IR and LLVM IR validators as new IR forms are added.
- Add compile-to-executable workflow documentation.
- Add `docs/llvm-backend-spec.md` or fold the same precision into
  `docs/llvm-backend.md`.

Non-goals:

- Closures.
- Heap allocation.
- LLVM optimization passes.

Acceptance criteria:

- LLVM execution matches the interpreter for successful closed first-order
  programs in the supported fragment.
- LLVM failures match the interpreter's runtime-error class for supported
  runtime errors.
- Unsupported constructs fail structurally before LLVM generation.

Tests required:

- LLVM golden tests.
- `llvm-as` validation for emitted goldens.
- Optional `lli`/`clang` execution tests.
- Interpreter-vs-LLVM differential tests.

Risks:

- Introducing new control-flow-producing primitives can break phi predecessor
  labels if not validated carefully.

Definition of done:

- The LLVM fragment has a documented semantic contract and differential tests.

## Phase 4 - Top-Level First-Order Functions

Status: not started.

Motivation: Move beyond single-expression programs without requiring closures.

Deliverables:

- Source syntax for top-level definitions.
- Typechecking for top-level definitions and calls.
- ANF representation for top-level function bodies.
- Backend function IR.
- LLVM function declarations/definitions and direct calls.

Non-goals:

- Capturing lambdas.
- Recursive functions unless explicitly designed.
- Polymorphic functions.

Acceptance criteria:

- Closed first-order programs with multiple top-level functions compile to LLVM.
- Direct calls execute the same as interpreter evaluation.

Tests required:

- Parser/typechecker tests for top-level defs.
- Shadowing and duplicate-name tests.
- Interpreter-vs-LLVM call tests.
- Backend unsupported tests for higher-order cases.

Risks:

- Top-level scoping rules must be clear before recursion or mutual recursion.

Definition of done:

- Direct first-order function calls are part of the supported LLVM fragment.

## Phase 5 - Lambda Lifting

Status: not started.

Motivation: Support a useful subset of lambdas while preserving a simple backend
model.

Deliverables:

- Detect non-capturing lambdas.
- Lift eligible lambdas to generated top-level functions.
- Reject capturing lambdas structurally until closure conversion exists.
- Preserve deterministic generated names.

Non-goals:

- Closure allocation.
- Captured environments.
- Full higher-order optimization.

Acceptance criteria:

- Non-capturing lambdas compile through LLVM.
- Capturing lambdas still run in interpreter/report mode and are rejected by
  backend compile mode with structured diagnostics.

Tests required:

- Free-variable analysis tests.
- Lambda-lifting golden ANF/backend tests.
- Interpreter-vs-LLVM tests for non-capturing lambdas.

Risks:

- Incorrect capture analysis is a semantic bug, not just a compile failure.

Definition of done:

- The backend supports non-capturing lambdas without introducing closure
  runtime dependencies.

## Phase 6 - Closure Conversion And Runtime

Status: not started.

Motivation: Support real higher-order programs.

Deliverables:

- Runtime spec for closures: code pointer plus environment pointer.
- Closure-converted IR.
- Environment layout and access rules.
- Allocation strategy.
- Closure call lowering.
- Runtime error functions.
- Memory management policy.

Non-goals:

- Optimized garbage collection in the first pass.
- Polymorphic closures.

Acceptance criteria:

- Capturing lambdas compile and run for representative examples.
- Runtime layout is documented and tested.

Tests required:

- Closure conversion unit tests.
- Interpreter-vs-LLVM closure tests.
- Memory/runtime smoke tests.

Risks:

- Runtime allocation decisions will constrain future data types and closures.

Definition of done:

- Higher-order examples run through LLVM with a documented runtime model.

## Phase 7 - Type System Improvements

Status: not started.

Motivation: Improve ergonomics without weakening the compiler's invariants.

Deliverables:

- Decide whether to implement Hindley-Milner inference.
- Improve function annotation syntax if needed.
- Define polymorphism scope.
- Keep a roadmap for ADTs and pattern matching.

Non-goals:

- Mixing type inference changes with closure runtime work.

Acceptance criteria:

- Any inference feature has principal-type tests and clear error reporting.

Tests required:

- Type inference property/unit tests.
- Negative ambiguity/generalization tests.
- Existing annotated programs continue to typecheck.

Risks:

- Inference can obscure diagnostics and interact with backend specialization.

Definition of done:

- The chosen type-system direction is specified and implemented incrementally.

## Phase 8 - Egglog Backend Expansion

Status: partial.

Motivation: Make Egglog the main optimizing backend for the ANF fragment while
preserving runtime errors.

Deliverables:

- Add comparison support where safe: `Lt` and `Eq`.
- Add subtraction with checked `Int64` semantics.
- Add division only with explicit `NonZero` and overflow constraints.
- Add richer boolean reasoning.
- Improve lattices and optimization explanations.
- Strengthen extraction and cost model.

Non-goals:

- Unsound algebraic rewrites.
- Rewrites that change overflow or division-by-zero behavior.

Acceptance criteria:

- Every Egglog optimization preserves successful results and runtime-error
  behavior.
- Unsupported operations remain explicit rather than silently ignored.

Tests required:

- Closed semantic preservation tests.
- Open-fragment type consistency tests.
- Overflow and division-by-zero preservation tests.
- Extraction determinism tests.

Risks:

- Algebraic identities such as distributivity can change overflow behavior under
  checked integers.

Definition of done:

- The Egglog backend covers the same first-order arithmetic and boolean
  fragment as the LLVM backend where semantic preservation is proven.

## Phase 9 - Egglog Engine Authenticity

Status: not started.

Motivation: Move the kernel from a correct bounded prototype toward a scalable
egglog-like engine.

Deliverables:

- Semi-naive evaluation.
- Delta relations.
- Rule scheduling.
- Join planning.
- Richer lattice merges.
- Provenance/debug traces.

Non-goals:

- Compiler-specific shortcuts inside the core Egglog kernel.

Acceptance criteria:

- Existing compiler backend behavior is unchanged.
- Larger rule sets run faster or with better convergence diagnostics.

Tests required:

- Kernel regression tests.
- Rule scheduling tests.
- Delta evaluation equivalence tests.
- Provenance rendering tests.

Risks:

- Performance changes can hide semantic regressions if equivalence tests are
  weak.

Definition of done:

- The kernel has scalable evaluation mechanics while remaining frontend
  independent.

## Phase 10 - Packaging, CI, And Polish

Status: not started.

Motivation: Make HeggLog easy to build, test, inspect, and release.

Deliverables:

- Stable CLI.
- Complete docs index.
- Curated examples.
- `cabal check` clean.
- CI matrix.
- Formatting/linting policy.
- Release-quality README.

Non-goals:

- New language semantics.

Acceptance criteria:

- New contributors can build, test, run examples, and understand the roadmap
  from the README.

Tests required:

- CI build/test jobs.
- Documentation link checks if practical.
- Example smoke tests.

Risks:

- Docs and examples can drift unless tested or reviewed as release artifacts.

Definition of done:

- The project is ready for repeated development on `main` without hidden local
  setup knowledge.

## Acceptance Test Matrix

| Phase | Required acceptance tests |
| --- | --- |
| 0 | `cabal build all`, `cabal test`, `git diff --check`, `cabal check`, CI green |
| 1 | Parser, typechecker, interpreter, ANF interpreter, overflow, division-by-zero |
| 2 | Golden diagnostics for parser, typechecker, runtime, backend unsupported |
| 3 | LLVM goldens, `llvm-as`, interpreter-vs-LLVM, runtime-error equivalence |
| 4 | Top-level parser/typechecker tests, direct-call LLVM differential tests |
| 5 | Capture analysis, lambda-lifting tests, non-capturing lambda LLVM tests |
| 6 | Closure conversion tests, runtime layout tests, higher-order LLVM examples |
| 7 | Type inference tests, negative ambiguity tests, annotation compatibility |
| 8 | Egglog semantic preservation, overflow preservation, extraction determinism |
| 9 | Kernel equivalence tests, delta/semi-naive scheduling tests, provenance tests |
| 10 | CI matrix, docs/examples smoke tests, packaging checks |

## Implementation Queue

### Task A - Commit Current Semantic Checkpoint

Status: complete.

Prerequisite: current workspace validation passes.

Implementation scope:

- Commit the checked `Int64`, Egglog, LLVM, docs, and golden updates.

Files likely touched:

- No code edits expected; git commit only.

Tests required:

- `cabal build all`
- `cabal test`
- `git diff --check`

Acceptance criteria:

- The commit is reviewable as a coherent semantic checkpoint.

Commit message suggestion:

```text
Enforce checked Int64 semantics
```

### Task B - Project Metadata And CI

Status: complete.

Prerequisite: Task A.

Implementation scope:

- Choose and add a license.
- Fix `hegglog.cabal` metadata enough for `cabal check`.
- Add a minimal GitHub Actions workflow.

Files likely touched:

- `LICENSE`
- `hegglog.cabal`
- `.github/workflows/ci.yml`
- `README.md`

Tests required:

- `cabal check`
- `cabal build all`
- `cabal test`
- `git diff --check`

Acceptance criteria:

- CI runs the same checks a local developer is expected to run.

Commit message suggestion:

```text
Add project metadata and CI
```

### Task C - Language And Runtime Specs

Status: complete.

Prerequisite: current roadmap.

Implementation scope:

- Completed: add `docs/language-spec.md`.
- Completed: add `docs/runtime-spec.md`.
- Completed: clarify unsigned source literal syntax versus signed runtime
  values.
- Completed: record decision needed for unary negative literals.

Files likely touched:

- `docs/language-spec.md`
- `docs/runtime-spec.md`
- `README.md`

Tests required:

- Documentation review.
- `git diff --check`

Acceptance criteria:

- Every current source form and runtime error has a documented meaning.

Commit message suggestion:

```text
Document language and runtime semantics
```

### Task D - Source Spans And Diagnostics

Prerequisite: Task C.

Implementation scope:

- Add source spans to parser output.
- Thread spans into parser/typechecker diagnostics.
- Add golden negative diagnostic tests.

Files likely touched:

- `src/Syntax/*`
- `src/Typecheck/*`
- `src/CLI/*`
- `test/Main.hs`
- `examples/type-errors/*`

Tests required:

- Parser/typechecker diagnostics goldens.
- Existing full suite.

Acceptance criteria:

- User-facing errors include source locations without weakening existing type
  or runtime behavior.

Commit message suggestion:

```text
Add source spans to diagnostics
```

### Task E - Egglog Comparisons

Prerequisite: checked `Int64` semantics and current Egglog backend.

Implementation scope:

- Add `Lt` and safe `Eq` support to the typed Egglog backend.
- Add bool constant facts where useful.
- Preserve checked integer and runtime-error semantics.

Files likely touched:

- `src/Optimize/EgglogBackend/*`
- `src/Egglog/Pattern.hs`
- `test/Main.hs`

Tests required:

- Egglog semantic preservation tests.
- Open-fragment type consistency tests.
- Comparison constant folding tests.

Acceptance criteria:

- Egglog can optimize comparison-heavy first-order ANF without changing
  successful results or runtime errors.

Commit message suggestion:

```text
Extend Egglog backend to comparisons
```

### Task F - Top-Level First-Order Functions

Prerequisite: source spans recommended; Task E optional.

Implementation scope:

- Add top-level function syntax and typechecking.
- Extend ANF/backend IR for direct first-order functions.
- Emit LLVM functions and direct calls.

Files likely touched:

- `src/Syntax/*`
- `src/Typecheck/*`
- `src/IR/*`
- `src/Backend/*`
- `src/Backend/LLVM/*`
- `test/Main.hs`

Tests required:

- Parser/typechecker tests.
- Interpreter-vs-LLVM differential tests.
- Unsupported higher-order backend tests.

Acceptance criteria:

- Multiple top-level first-order functions compile and run through LLVM.

Commit message suggestion:

```text
Compile top-level first-order functions
```

### Task G - Lambda Lifting For Non-Capturing Lambdas

Prerequisite: Task F.

Implementation scope:

- Detect and lift non-capturing lambdas.
- Keep capturing lambdas rejected by backend compile mode.

Files likely touched:

- `src/IR/*`
- `src/Backend/*`
- `src/CLI/*`
- `test/Main.hs`

Tests required:

- Capture analysis tests.
- Interpreter-vs-LLVM tests for non-capturing lambdas.

Acceptance criteria:

- Non-capturing lambda examples compile to LLVM with no closure runtime.

Commit message suggestion:

```text
Lambda lift non-capturing functions
```

### Task H - Closure Runtime

Prerequisite: Task G and runtime spec.

Implementation scope:

- Implement closure conversion.
- Add runtime representation: code pointer plus environment pointer.
- Add allocation and closure call lowering.

Files likely touched:

- `src/IR/*`
- `src/Backend/*`
- `src/Backend/LLVM/*`
- runtime support files if introduced
- `test/Main.hs`

Tests required:

- Closure conversion unit tests.
- Higher-order interpreter-vs-LLVM tests.
- Runtime allocation smoke tests.

Acceptance criteria:

- Capturing lambda examples compile and run through LLVM.

Commit message suggestion:

```text
Add closure conversion runtime
```

### Task I - Hindley-Milner Direction

Prerequisite: diagnostics and top-level function decisions.

Implementation scope:

- Decide and document inference scope.
- Implement incrementally if approved.

Files likely touched:

- `docs/language-spec.md`
- `src/Typecheck/*`
- `test/Main.hs`

Tests required:

- Principal type tests.
- Negative ambiguity tests.
- Existing annotated programs remain valid.

Acceptance criteria:

- The type system improves ergonomics without creating backend ambiguity.

Commit message suggestion:

```text
Define type inference roadmap
```

### Task J - Semi-Naive Egglog Evaluation

Prerequisite: stable Egglog backend tests.

Implementation scope:

- Add delta relations and semi-naive rule evaluation.
- Add rule scheduling and join planning.
- Preserve kernel/frontend separation.

Files likely touched:

- `src/Egglog/*`
- `test/Main.hs`
- `docs/egglog-backend.md`

Tests required:

- Kernel equivalence tests.
- Performance/convergence smoke tests.
- Existing backend preservation tests.

Acceptance criteria:

- Existing rule results match the naive evaluator with better execution
  mechanics.

Commit message suggestion:

```text
Add semi-naive Egglog evaluation
```

## Next Recommended Prompt

```text
Add source spans and diagnostics: introduce source locations in parser output,
thread them into parser/typechecker/runtime/backend diagnostics, add golden
negative diagnostic tests, and preserve current language semantics.
```
