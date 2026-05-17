# HeggLog Roadmap

This roadmap is the project-level source of truth for what exists now, what is
being stabilized, and what should be built next. It is synchronized with the
current codebase as of the checked `Int64` semantics, Egglog backend, LLVM
backend, source diagnostics, top-level first-order functions, lambda lifting,
closure conversion runtime work, and optional monomorphic lambda parameter
inference.

## Current Baseline

Implemented:

- Parser and pretty-printer for expression-level HeggLog plus ordered top-level
  first-order definitions.
- Production typechecker with explicit top-level signatures and optional lambda
  parameter annotation elaboration.
- Separate Algorithm W-style principal-type engine and located source
  elaborator for monomorphic lambda inference.
- Typechecking and source interpretation for ordered nonrecursive top-level
  definitions.
- Source interpreter and ANF interpreter.
- ANF lowering, validation, top-level function representation, direct calls, and
  deterministic generated names.
- Resolved ANF with deterministic binder ids and explicit free variables.
- Fact inference over ANF.
- Sound local ANF simplifier with validation before and after optimization.
- Prototype e-graph optimizer for a narrow ANF fragment.
- Standalone Egglog-style kernel with sorts, values, functions, merge behavior,
  union-find, rebuild, rules, rewrite sugar, and extraction.
- Compiler-facing Egglog backend for typed pure first-order ANF: integer
  `Add`/`Mul`, boolean and integer `if`, constants, variables, and lets.
- Backend IR and LLVM backend v0 for closed first-order programs, including
  top-level first-order functions and saturated direct calls.
- Lambda lifting for non-capturing let-bound lambdas and lambdas used directly
  in function position, with generated top-level functions.
- Closure conversion for local function values, with heap-allocated closure
  objects containing a code pointer and captured fields.
- LLVM indirect closure calls through local function values, including captured
  variables, returned closures, and higher-order local functions.
- CLI report mode and LLVM compile mode, including optional LLVM execution.
- LLVM toolchain checks that assemble selected emitted goldens with `llvm-as`
  when available, plus documented `llvm-as`/`lli`/`clang` executable workflow.
- Interpreter-vs-LLVM differential corpus for successful closed first-order and
  closure source programs when `lli` or `clang` is available.
- Runtime-error equivalence tests for checked-`Int` overflow in LLVM `+`, `-`,
  and `*` lowering.
- Dedicated LLVM backend specification for the current supported fragment,
  runtime behavior, IR invariants, validation boundaries, and toolchain checks.
- Parallel located source AST used by parser, typechecker, runtime report, and
  LLVM unsupported-feature diagnostics.
- Stable diagnostics specification with golden negative diagnostics for
  typechecker and LLVM unsupported-source errors.
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
- Language and runtime specifications for the current source language, checked
  `Int64` semantics, runtime errors, evaluation order, top-level first-order
  definitions, lambda lifting, closure runtime layout, and current decision
  points.
- Type inference direction document covering principal-type infrastructure,
  completed optional lambda annotations, and polymorphism deferral.

Not implemented:

- Normalized one-line parser diagnostics beyond Megaparsec's built-in bundles.
- Exact subexpression runtime spans beyond the root source expression.
- Long-term heap ownership policy beyond process-lifetime closure allocation.
- User-facing Hindley-Milner polymorphism and optional top-level signatures.
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
- Recursive top-level declarations.
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

Status: complete for the current compile/report surfaces.

Motivation: Structured errors are necessary before larger language features make
failures harder to inspect.

Deliverables:

- Completed: add a parallel located AST for parsed expressions.
- Completed: preserve useful spans through typechecking diagnostics.
- Completed: improve CLI report errors with file/line/column source ranges for
  typechecker failures and root-expression runtime failures.
- Completed: improve LLVM compile errors with source ranges for unsupported
  lambdas, applications, and division.
- Completed: add `docs/diagnostics-spec.md`.

Non-goals:

- IDE protocol support.
- Full recovery parsing.
- Precise nested runtime source traces.
- Parser diagnostic normalization beyond Megaparsec output.

Acceptance criteria:

- Parser errors include file, line, and column through Megaparsec.
- Typechecker errors include file, line, column range, and a useful message.
- Backend unsupported-feature errors identify the source construct when
  possible.

Tests required:

- Completed: golden negative diagnostics.
- Completed: parser and typechecker fixture coverage.
- Completed: backend unsupported diagnostics.

Risks:

- Retrofitting spans late can cause churn across syntax, typechecking, and ANF.

Definition of done:

- Current user-facing compile errors have stable formatting, with documented
  precision limits for parser and runtime diagnostics.

Next recommended task:

- Start Phase 3 by strengthening LLVM backend correctness around runtime-error
  equivalence and executable workflow documentation.

## Phase 3 - LLVM Backend Correctness

Status: complete for the current LLVM v0 fragment.

Motivation: LLVM must be a semantic implementation of the language fragment, not
just a printer for simple examples.

Deliverables:

- Completed: keep checked arithmetic lowering for `+`, `-`, and `*`.
- Completed: assemble selected emitted LLVM goldens with `llvm-as` when the tool
  is available.
- Completed: document `llvm-as`, `lli`, and `clang` workflows for validating,
  interpreting, and compiling emitted LLVM.
- Completed: add a small interpreter-vs-LLVM differential corpus for successful
  closed first-order programs in the supported fragment.
- Completed: add runtime-error equivalence testing for checked-`Int` overflow
  in LLVM `+`, `-`, and `*`.
- Completed: add `docs/llvm-backend-spec.md` for the current LLVM semantic
  contract, IR invariants, validation boundaries, and test obligations.
- Future: add division-by-zero runtime-error equivalence when LLVM division is
  supported.
- Ongoing: strengthen Backend IR and LLVM IR validators as new IR forms are
  added.

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

- Completed: LLVM golden tests.
- Completed: `llvm-as` validation for emitted goldens when available.
- Completed: optional `lli`/`clang` execution tests.
- Completed: interpreter-vs-LLVM differential tests for successful executions.
- Completed: interpreter-vs-LLVM runtime-error equivalence tests for checked
  arithmetic overflow.

Risks:

- Introducing new control-flow-producing primitives can break phi predecessor
  labels if not validated carefully.

Definition of done:

- The current LLVM fragment has a documented semantic contract and differential
  tests.

Next recommended task:

- Start Phase 5 by lambda-lifting non-capturing lambdas onto the new top-level
  function path.

## Phase 4 - Top-Level First-Order Functions

Status: complete for ordered nonrecursive first-order definitions.

Motivation: Move beyond single-expression programs without requiring closures.

Deliverables:

- Completed: source syntax for top-level definitions.
- Completed: typechecking for ordered top-level definitions and saturated direct
  calls.
- Completed: duplicate top-level name and duplicate parameter rejection.
- Completed: rejection of function-typed top-level parameters and returns.
- Completed: ANF representation for top-level function bodies and direct calls.
- Completed: Backend function IR, validation, and direct calls.
- Completed: LLVM function definitions with typed parameters and direct calls.

Non-goals:

- Capturing lambdas.
- Recursive functions unless explicitly designed.
- Polymorphic functions.

Acceptance criteria:

- Completed: closed first-order programs with multiple top-level functions
  compile to LLVM.
- Completed: direct calls execute the same as interpreter evaluation.

Tests required:

- Completed: parser/typechecker tests for top-level defs.
- Completed: duplicate-name and duplicate-parameter tests.
- Completed: forward-reference rejection tests.
- Completed: interpreter and LLVM direct-call tests.
- Completed: backend unsupported tests for higher-order cases.

Risks:

- Top-level scoping rules must be clear before recursion or mutual recursion.

Definition of done:

- Direct first-order function calls are part of the supported LLVM fragment.

Next recommended task:

- Start Phase 5 by detecting non-capturing lambdas and lowering them into
  generated top-level functions.

## Phase 5 - Lambda Lifting

Status: complete for non-capturing let-bound lambdas and immediate lambda calls.

Motivation: Support a useful subset of lambdas while preserving a simple backend
model.

Deliverables:

- Completed: detect non-capturing lambdas.
- Completed: lift eligible let-bound lambdas and lambdas used directly in
  function position to generated top-level functions.
- Completed: leave capturing and otherwise non-liftable lambdas for closure
  conversion.
- Completed: preserve deterministic generated names.

Non-goals:

- Full higher-order optimization.

Acceptance criteria:

- Completed: non-capturing lambda examples compile through LLVM.
- Completed: capturing lambdas are not lambda-lifted and are handled by the
  closure-conversion path.

Tests required:

- Completed: free-variable capture tests.
- Completed: lambda-lifting ANF/backend tests.
- Completed: interpreter-vs-LLVM tests for non-capturing lambdas.

Risks:

- Incorrect capture analysis is a semantic bug, not just a compile failure.

Definition of done:

- The backend supports non-capturing lambdas without introducing closure
  runtime dependencies.

Next recommended task:

- Completed by Phase 6 closure conversion and runtime representation.

## Phase 6 - Closure Conversion And Runtime

Status: complete for monomorphic local closures with first-order roots.

Motivation: Support real higher-order programs.

Deliverables:

- Completed: runtime spec for closures as heap objects with code pointer plus
  captured fields.
- Completed: Backend IR constructors for closure allocation, closure
  application, and environment-field access.
- Completed: deterministic environment layout and access rules.
- Completed: heap allocation with `malloc` and null-allocation abort.
- Completed: closure call lowering through loaded code pointers and indirect
  LLVM calls.
- Completed: process-lifetime memory management policy for the first pass.

Non-goals:

- Optimized garbage collection in the first pass.
- Polymorphic closures.
- Function-valued program roots.
- Top-level functions as first-class values.

Acceptance criteria:

- Completed: capturing lambdas compile and run for representative examples.
- Completed: returned closures and higher-order local function values compile
  and match interpreter output when LLVM execution tools are available.
- Completed: runtime layout is documented and tested.

Tests required:

- Completed: closure conversion LLVM shape tests.
- Completed: interpreter-vs-LLVM closure tests.
- Completed: memory/runtime smoke tests through closure allocation and
  execution.

Risks:

- Process-lifetime closure allocation is correct for current compiled programs
  but must be replaced or refined before long-running programs or aggregate
  values.

Definition of done:

- Higher-order examples run through LLVM with a documented runtime model.

Next recommended task:

- Start Phase 8 by expanding the Egglog backend evaluation strategy.

## Phase 7 - Type System Improvements

Status: complete for monomorphic optional lambda parameter inference;
polymorphism deferred.

Motivation: Improve ergonomics without weakening the compiler's invariants.

Deliverables:

- Completed: decide to implement Hindley-Milner incrementally behind explicit
  backend monomorphism.
- Completed: add `docs/type-inference.md`.
- Completed: add an Algorithm W-style principal-type engine for the current
  core language.
- Completed: improve function annotation syntax with optional lambda parameter
  annotations.
- Completed: elaborate omitted lambda parameter annotations to explicit
  monomorphic backend-facing types before interpretation, ANF, lambda lifting,
  closure conversion, and LLVM lowering.
- Future: define and implement polymorphism scope after monomorphization is
  specified.
- Keep a roadmap for ADTs and pattern matching.

Non-goals:

- Exposing polymorphic source syntax before backend monomorphization would
  create late compile failures or ambiguous closure lowering.

Acceptance criteria:

- Completed: principal-type tests cover annotated identity, higher-order
  closures, and a monomorphic-let negative case.
- Completed: optional lambda syntax has source-spanned diagnostics and backend
  compatibility tests.
- Future polymorphism syntax must have a backend monomorphization plan.

Tests required:

- Completed: principal-type unit tests.
- Completed: negative monomorphic-let test.
- Completed: existing annotated programs continue to typecheck.
- Completed: optional lambda inference tests, delayed equality context test, and
  inferred closure-conversion LLVM test.

Risks:

- Inference can obscure diagnostics and interact with backend specialization.

Definition of done:

- The chosen monomorphic inference direction is specified and implemented
  through optional lambda parameter annotations.

Next recommended task:

- Add semi-naive Egglog evaluation.

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

Status: complete.

Prerequisite: source spans recommended; Task E optional.

Implementation scope:

- Completed: add top-level function syntax and typechecking.
- Completed: extend ANF/backend IR for direct first-order functions.
- Completed: emit LLVM functions and direct calls.

Files likely touched:

- `src/Syntax/*`
- `src/Typecheck/*`
- `src/IR/*`
- `src/Backend/*`
- `src/Backend/LLVM/*`
- `test/Main.hs`

Tests required:

- Completed: parser/typechecker tests.
- Completed: interpreter and LLVM direct-call execution tests.
- Completed: unsupported higher-order backend tests.

Acceptance criteria:

- Completed: multiple top-level first-order functions compile and run through
  LLVM.

Commit message suggestion:

```text
Compile top-level first-order functions
```

### Task G - Lambda Lifting For Non-Capturing Lambdas

Status: complete.

Prerequisite: Task F.

Implementation scope:

- Completed: detect and lift non-capturing lambdas.
- Completed: leave capturing and non-liftable higher-order lambdas for closure
  conversion.

Files likely touched:

- `src/IR/*`
- `src/Backend/*`
- `src/CLI/*`
- `test/Main.hs`

Tests required:

- Completed: capture analysis tests.
- Completed: lambda-lifting ANF/backend tests.
- Completed: interpreter-vs-LLVM tests for non-capturing lambdas.

Acceptance criteria:

- Completed: saturated non-capturing lambda examples compile to LLVM with no
  closure runtime.

Commit message suggestion:

```text
Lambda lift non-capturing functions
```

### Task H - Closure Runtime

Status: complete for monomorphic local closures with first-order roots.

Prerequisite: Task G and runtime spec.

Implementation scope:

- Completed: implement closure conversion.
- Completed: add runtime representation as code pointer plus captured
  environment fields.
- Completed: add allocation and closure call lowering.

Files touched:

- `src/Backend/*`
- `src/Backend/LLVM/*`
- `test/Main.hs`
- `docs/*`

Tests required:

- Completed: closure conversion LLVM shape tests.
- Completed: higher-order interpreter-vs-LLVM tests.
- Completed: runtime allocation smoke tests.

Acceptance criteria:

- Completed: capturing lambda examples compile and run through LLVM.

Commit message suggestion:

```text
Add closure conversion runtime
```

### Task I - Hindley-Milner Direction

Status: complete for the direction decision, principal-type infrastructure, and
optional monomorphic lambda parameter annotations.

Prerequisite: diagnostics and top-level function decisions.

Implementation scope:

- Completed: decide and document inference scope.
- Completed: add Algorithm W-style principal-type infrastructure for the
  current core language.
- Completed: expose optional lambda parameter annotations with source-spanned
  ambiguity diagnostics.
- Completed: propagate inferred lambda parameter types into the backend-facing
  located AST before closure conversion and LLVM lowering.

Files touched:

- `docs/type-inference.md`
- `docs/language-spec.md`
- `README.md`
- `src/Typecheck/*`
- `src/Syntax/*`
- `src/Backend/*`
- `src/CLI/Report.hs`
- `test/Main.hs`

Tests required:

- Completed: principal type tests.
- Completed: negative monomorphic-let/generalization boundary test.
- Completed: existing annotated programs remain valid.
- Completed: optional lambda parameter inference and ambiguity tests.
- Completed: inferred captured lambda closure-conversion test.

Acceptance criteria:

- Completed: optional lambda inference improves ergonomics without creating
  backend ambiguity.

Commit message suggestion:

```text
Add optional lambda inference
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
Add semi-naive Egglog evaluation: introduce delta relations, rule scheduling,
and join-planning scaffolding while preserving existing kernel equivalence and
backend semantic-preservation tests.
```
