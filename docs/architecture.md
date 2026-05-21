# HeggLog Architecture

This document records the intended architecture for HeggLog as it grows from a
validated executable Haskell 2010 subset compiler into a fuller Haskell 2010
compiler. It also records the May 2026 architecture/code audit baseline.

The project currently contains two compiler surfaces:

- the original strict `.hg` compiler substrate
- the active Haskell 2010 native compiler path

The `.hg` path is kept as a regression baseline and reusable infrastructure. It
must not drive source-language decisions for the Haskell 2010 path.

## Architectural Goal

The target architecture is a stage-separated native compiler:

```text
Haskell 2010 source files
  -> layout-aware lexer/parser
  -> module graph loader
  -> renamer
  -> typechecker and desugarer
  -> typed Core
  -> validating Core optimizer
  -> lazy STG-like IR
  -> boxed runtime model
  -> LLVM IR
  -> clang-built native executable
```

Every stage should have a small, explicit contract:

- It accepts one well-defined input representation.
- It produces one well-defined output representation or a structured error.
- It does not reach backward into earlier concrete syntax except for spans and
  provenance.
- It validates its output before handing it to later stages when validation is
  meaningful.

This is the right architecture for the project because compilers fail by
semantic drift between stages more often than by lack of local cleverness. The
project already follows this principle in the Haskell 2010 path: parser AST,
renamed AST, typed Core, STG, LLVM IR, Core validation, STG validation, LLVM
validation, Core evaluation, STG evaluation, native wet tests, and manifest
conformance tests all exist as separate contracts.

## Current Pipeline Boundaries

### Source and Parsing

Primary modules:

- `Haskell2010.Syntax`
- `Haskell2010.Lexer`
- `Haskell2010.Layout`
- `Haskell2010.Parser`
- `Haskell2010.Pretty`

Responsibilities:

- Preserve source spans on syntax nodes that can later produce diagnostics.
- Parse Haskell 2010 surface forms without assigning semantic meaning too
  early.
- Keep parsed-only features represented honestly until later stages support
  them.

Architectural status: sound. The AST is intentionally broad and later stages
decide support. Pattern synonyms in `Syntax` keep construction ergonomic while
still storing spans.

### Modules and Renaming

Primary modules:

- `Haskell2010.ModuleGraph`
- `Haskell2010.Names`
- `Haskell2010.Renamed`
- `Haskell2010.Renamer`

Responsibilities:

- Load same-directory dependency modules.
- Detect missing modules, cycles, and module-name mismatches.
- Resolve names into namespace-tagged unique identifiers.
- Enforce import/export filtering and fixity resolution.
- Preserve enough source identity for typechecking and diagnostics.

Architectural status: sound, with one scaling concern. `Renamer` is large and
mixes module interfaces, scope management, declaration renaming, pattern/type
renaming, and fixity resolution. That is acceptable for the current size, but
future package-search, Prelude-module, and import/export expansion should split
this into focused modules.

Recommended target split when the next module-system work starts:

- `Haskell2010.Renamer.Scope`
- `Haskell2010.Renamer.Imports`
- `Haskell2010.Renamer.Exports`
- `Haskell2010.Renamer.Fixity`
- `Haskell2010.Renamer.Decls`

### Typechecking and Desugaring

Primary module:

- `Haskell2010.Typecheck`

Responsibilities currently implemented in one module:

- kind representation and kind inference/checking
- type constructor, synonym, newtype, data, record, and class collection
- class constraint representation
- defaulting and monomorphism decision
- source type conversion and synonym expansion
- HM inference, unification, generalization, and instantiation
- pattern checking and irrefutable pattern lowering
- binding dependency analysis
- dictionary generation and dictionary passing
- Prelude value/class synthesis
- source-to-Core desugaring
- source-spanned type errors and supported pattern-match warnings

Architectural status: semantically coherent but now too concentrated. The code
builds cleanly and is validated by broad tests, but this module is the primary
long-term maintainability risk.

Recommended target split:

- `Haskell2010.Typecheck.Types`
- `Haskell2010.Typecheck.Kinds`
- `Haskell2010.Typecheck.Env`
- `Haskell2010.Typecheck.SourceTypes`
- `Haskell2010.Typecheck.Patterns`
- `Haskell2010.Typecheck.Bindings`
- `Haskell2010.Typecheck.Constraints`
- `Haskell2010.Typecheck.Classes`
- `Haskell2010.Typecheck.Prelude`
- `Haskell2010.Typecheck.Desugar`
- `Haskell2010.Typecheck.Diagnostics`

The split should be incremental. Do not move code just to reduce line count.
Move a section when a new feature needs to modify that section anyway, and
preserve the existing public `Haskell2010.Typecheck` facade until downstream
imports can be changed safely.

### Typed Core

Primary modules:

- `Haskell2010.Core.Syntax`
- `Haskell2010.Core.Validate`
- `Haskell2010.Core.Eval`
- `Haskell2010.Core.FreeVars`
- `Haskell2010.Core.Subst`
- `Haskell2010.Core.Pretty`

Responsibilities:

- Represent a small typed Core language.
- Track constructor metadata, newtype erasure, binders, literals, lambdas,
  applications, type abstraction/application, lets, recursive groups, cases,
  coercions, and primitives.
- Validate binder uniqueness, namespaces, type annotations, constructors,
  alternatives, primitive arity/types, and coercions.
- Provide a reference evaluator for compiler-oracle tests.

Architectural status: strong. Core is the best boundary in the project. It is
small enough to reason about and heavily validated. The existing design should
remain the semantic center for Haskell 2010 expansion.

### Core Optimization

Primary modules:

- `Optimize.CoreEgglog`
- `Optimize.EgglogBackend`
- `Optimize.EgglogBackend.*`
- `Egglog.*`
- `Optimize.EGraph`
- `Optimize.Simplify`
- `Optimize.Rewrite`

Responsibilities:

- Keep the generic Egglog engine independent of source frontend details.
- Optimize safe `.hg` ANF fragments through the legacy optimizer path.
- Optimize Haskell 2010 typed Core through `Optimize.CoreEgglog`.
- Validate optimized Core before accepting rewrites.
- Preserve laziness and bottom behavior by skipping unsupported or unsafe
  fragments.

Architectural status: sound. The important property is conservatism: the
optimizer is allowed to do less, but it is not allowed to produce invalid Core
or erase strict runtime errors.

Audit change applied: the obsolete `Optimize.Placeholder` no-op module was
removed. The `.hg` report path now renders the lowered legacy Core directly,
and the design note in `IR.Core` makes clear that production optimization lives
elsewhere.

### STG and Runtime Model

Primary modules:

- `Haskell2010.STG.Syntax`
- `Haskell2010.STG.Validate`
- `Haskell2010.STG.Eval`
- `Haskell2010.STG.Lower`
- `Haskell2010.STG.LLVM`

Responsibilities:

- Represent lazy functions, thunks, constructors, recursive groups, case
  demand, primitive operations, and update flags.
- Validate STG names, constructor metadata, applications, alternatives, and
  primitive typing.
- Evaluate STG as a semantic check independent of LLVM.
- Lower validated Core into STG.
- Emit boxed lazy runtime LLVM for native execution.

Architectural status: sound, with one scaling concern. `STG.LLVM` currently
contains lowering logic, runtime object layout constants, runtime helper
functions, and low-level LLVM builder utilities in one module. That has been
effective for the current runtime, but future GC, broader `String`/`Char` APIs,
and IO expansion will benefit from a split.

Recommended target split:

- `Haskell2010.STG.LLVM.Builder`
- `Haskell2010.STG.LLVM.RuntimeLayout`
- `Haskell2010.STG.LLVM.RuntimeFunctions`
- `Haskell2010.STG.LLVM.EmitExpr`
- `Haskell2010.STG.LLVM.EmitCase`
- `Haskell2010.STG.LLVM.Primitives`

As with the typechecker, split only along active feature boundaries.

### LLVM and Native Toolchain

Primary modules:

- `Backend.LLVM.IR`
- `Backend.LLVM.Emit`
- `Backend.LLVM.Validate`
- `Backend.LLVM.Toolchain`
- `Backend.LLVM.Lower`

Responsibilities:

- Provide a small internal LLVM representation shared by `.hg` and Haskell
  2010.
- Render deterministic textual LLVM.
- Validate generated LLVM module structure before native build where possible.
- Encapsulate toolchain discovery, `lli`, `clang`, and native executable runs.

Architectural status: sound. Reusing generic LLVM IR/toolchain code from the
`.hg` substrate is an appropriate dependency. Haskell 2010 should not depend on
the `.hg` source AST or typechecker, but it can depend on generic backend IR
utilities and runtime integer semantics.

### CLI

Primary modules:

- `Main`
- `CLI.Compile`
- `CLI.Report`
- `Backend.Compile`
- `Haskell2010.Native`

Responsibilities:

- Route `.hs` source through the Haskell 2010 native path.
- Route `.hg` source through the legacy path.
- Support emit LLVM, build executable, and run modes.
- Keep user-facing errors structured and stage-specific.

Architectural status: adequate for the current phase. The CLI is not yet the
long-term product interface described by the roadmap. Future `check`, `run`,
`emit-core`, `emit-stg`, and `report` commands should move argument routing out
of `Main` into command modules.

### Tests and Conformance

Primary files/directories:

- `test/Main.hs`
- `test/e2e/Main.hs`
- `test/e2e/programs/`
- `test/haskell2010-conformance/Main.hs`
- `test/haskell2010/conformance/manifest.json`
- `test/haskell2010/conformance/`
- `scripts/smoke-test.sh`
- `scripts/e2e-wet-test.sh`
- `scripts/validate-haskell2010-todo.py`

Responsibilities:

- Unit-test parser, renamer, Core, typechecker, evaluators, STG, LLVM, Egglog,
  diagnostics, CLI behavior, and properties.
- Compile and run actual native artifacts.
- Keep Haskell 2010 conformance progress explicit through a manifest.
- Keep unsupported features represented as tests, not silent omissions.

Architectural status: strong on coverage, weak on organization. `test/Main.hs`
is the largest source file in the repository. It should eventually be split by
subsystem, but the current monolithic suite is still valuable because it
exercises cross-stage behavior. Splitting should happen when test ownership
becomes a blocker, not as a risky mechanical rewrite.

Recommended target split:

- `test/unit/ParserSpec.hs`
- `test/unit/Haskell2010/RenamerSpec.hs`
- `test/unit/Haskell2010/TypecheckSpec.hs`
- `test/unit/Haskell2010/CoreSpec.hs`
- `test/unit/Haskell2010/STGSpec.hs`
- `test/unit/OptimizeSpec.hs`
- `test/unit/LLVMBackendSpec.hs`
- `test/support/Haskell2010Fixtures.hs`
- `test/support/Assertions.hs`

## Dependency Rules

These rules should guide future changes:

1. `Haskell2010.Syntax` must not import renamer, typechecker, Core, STG, LLVM,
   optimizer, or CLI modules.
2. `Haskell2010.Renamed` may depend on parsed syntax names/spans and
   `Haskell2010.Names`, but not typechecking or Core.
3. `Haskell2010.Renamer` may depend on parsed and renamed syntax, but not
   Core/STG/LLVM.
4. `Haskell2010.Typecheck` may depend on renamed syntax and Core, but should
   not depend on STG, LLVM, or native toolchain modules.
5. `Haskell2010.Core.*` may depend on names and source literals/spans, but not
   on typechecker, STG, LLVM, or CLI.
6. `Optimize.CoreEgglog` may depend on Core and the generic Egglog engine, but
   must validate selected Core before returning it.
7. `Haskell2010.STG.Lower` may depend on Core and STG, but not LLVM.
8. `Haskell2010.STG.LLVM` may depend on STG and generic LLVM IR/toolchain
   support, but should not reach back into parser, renamer, or typechecker.
9. `Main` and `CLI.*` may orchestrate stages, but should not contain compiler
   semantics.
10. The `.hg` substrate may share backend/toolchain/runtime utilities with
    Haskell 2010, but Haskell 2010 source semantics should not depend on `.hg`
    AST or typechecker modules.

The current codebase mostly satisfies these rules. The accepted shared
dependencies are `Runtime.Int`, `Syntax.Span`, and generic LLVM backend
modules.

## Validation Gates

Every substantial compiler change should pass the narrowest relevant tests and
then the full smoke gate before merge:

```bash
cabal build all
cabal test hegglog-test --test-options='--hide-successes'
cabal test haskell2010-conformance-test --test-options='--hide-successes'
python3 scripts/validate-haskell2010-todo.py
git diff --check
./scripts/smoke-test.sh
```

Changes touching native runtime behavior should also run the mandatory wet
path, or rely on `cabal test all` through `smoke-test.sh` when the local
toolchain has `clang`.

## Audit Baseline

The May 2026 audit reviewed all tracked project files under:

- `.github`
- `docs`
- `examples`
- `scripts`
- `src`
- `test`
- root metadata files

The review checked:

- stage boundaries
- import direction
- stale placeholder code
- high-risk partial functions and TODOs
- validation coverage
- documentation consistency
- test and conformance organization
- package/CI wiring

Validation at this baseline passed through `./scripts/smoke-test.sh`.

## Immediate Findings

### Strengths

- Haskell 2010 compiler stages are cleanly separated from the legacy `.hg`
  frontend.
- Core and STG have explicit validators.
- Core and STG evaluators provide independent semantic oracles before LLVM.
- Native tests compile and execute actual binaries.
- The conformance manifest documents successful, failing, and unsupported
  Haskell 2010 cases.
- The optimizer validates output and is conservative around unsupported lazy
  fragments.
- Cabal uses warning flags and CI runs build, tests, package checks, backlog
  validation, wet tests, and whitespace checks.

### Risks

- `Haskell2010.Typecheck` is too broad for long-term feature growth.
- `Haskell2010.STG.LLVM` combines runtime layout, helper functions, and emitter
  logic.
- `Haskell2010.Renamer` will need a split when package/module support expands.
- `test/Main.hs` should become multiple test modules when practical.
- The conformance corpus is representative, not exhaustive.
- CLI productization still trails compiler capability.

### Applied Audit Cleanups

- Removed the obsolete no-op `Optimize.Placeholder` module.
- Made the legacy `.hg` report path render lowered Core directly.
- Reworded stale Haskell 2010 status-summary headings so supported compilation
  is not listed under "What Does Not Yet Compile".
- Added this architecture document and linked it from the documentation index.
- May 20 follow-up audit: verified the current import graph still obeys the
  stage dependency rules, removed partial root-module selection in the
  multi-module native path by resolving the renamed root explicitly by module
  name, and synchronized roadmap/status documents with the manifest's current
  conformance counts and completed `getLine`/typeclass work.

## File-Level Audit Notes

### Root and CI

| File | Audit note |
| --- | --- |
| `.github/workflows/ci.yml` | Sensible CI gate: toolchain install, build, backlog validation, tests, package check, wet tests, whitespace. Some duplication with scripts is intentional because scripts are also standalone local gates. |
| `.gitignore` | Standard generated-output exclusion. No architecture concern. |
| `LICENSE` | MIT license metadata. |
| `README.md` | Project-facing overview. Should continue to avoid claiming full Haskell 2010 conformance until conformance corpus is much deeper. |
| `cabal.project` | Minimal Cabal project file. |
| `hegglog.cabal` | Good explicit module list and warnings. Audit removed stale `Optimize.Placeholder` entries. |

### Scripts

| File | Audit note |
| --- | --- |
| `scripts/smoke-test.sh` | Good local top-level gate. Allows non-strict native skip unless requested. |
| `scripts/e2e-wet-test.sh` | Strong mandatory wet gate. Requires clang and runs native-oriented tests. |
| `scripts/validate-haskell2010-todo.py` | Good structural check for the task ledger and markdown mirror. |

### Source Modules

| File | Audit note |
| --- | --- |
| `src/Analysis/Facts.hs` | Small legacy `.hg` fact model. Appropriate dependency on source AST/pretty only. |
| `src/Analysis/InferFacts.hs` | Legacy ANF fact inference. Clear dependency on ANF and type environment. |
| `src/Backend/ClosureConvert.hs` | Legacy `.hg` closure conversion. Medium-large but cohesive. Errors are structured. |
| `src/Backend/Compile.hs` | Legacy `.hg` compile orchestration. Appropriate CLI/backend boundary. |
| `src/Backend/IR.hs` | Small backend IR for legacy path. Cohesive. |
| `src/Backend/LambdaLift.hs` | Legacy lambda lifting. Medium size, owns one transformation. |
| `src/Backend/Lower.hs` | Legacy ANF-to-backend lowering. Cohesive. |
| `src/Backend/Pretty.hs` | Small renderer. No concern. |
| `src/Backend/Validate.hs` | Backend IR validator. Good defensive boundary. |
| `src/Backend/LLVM/Emit.hs` | LLVM text renderer. Cohesive and shared by both compiler paths. |
| `src/Backend/LLVM/IR.hs` | Small LLVM IR model. Good shared backend boundary. |
| `src/Backend/LLVM/Lower.hs` | Legacy backend-to-LLVM lowering. Large enough to watch, but scoped to one stage. |
| `src/Backend/LLVM/Toolchain.hs` | Encapsulates external tools. Good separation from compiler semantics. |
| `src/Backend/LLVM/Validate.hs` | LLVM validation boundary. Good defensive check. |
| `src/CLI/Compile.hs` | Small compile-flag parser. Good CLI utility module. |
| `src/CLI/Report.hs` | Legacy `.hg` report orchestration. Audit removed obsolete placeholder optimizer dependency. |
| `src/Egglog/Database.hs` | Generic Egglog database. Cohesive. |
| `src/Egglog/Eval.hs` | Generic Egglog evaluator. Large but internally cohesive. |
| `src/Egglog/Extract.hs` | Extraction logic. Cohesive. |
| `src/Egglog/Function.hs` | Small function metadata module. |
| `src/Egglog/Pattern.hs` | Pattern matching and primitive/lattice helpers. Medium size, acceptable. |
| `src/Egglog/Pretty.hs` | Rendering/debug output. No concern. |
| `src/Egglog/Rebuild.hs` | Rebuild canonicalization. Cohesive. |
| `src/Egglog/Rule.hs` | Rule model. Small and clear. |
| `src/Egglog/Sort.hs` | Sort/function-name primitives. Small and clear. |
| `src/Egglog/UnionFind.hs` | Union-find implementation. Small and isolated. |
| `src/Egglog/Value.hs` | Egglog value model. Small and isolated. |
| `src/Eval/ANFInterpreter.hs` | Legacy ANF interpreter. Good oracle for old path. |
| `src/Eval/Interpreter.hs` | Legacy source interpreter. Cohesive. |
| `src/Haskell2010/Core/Eval.hs` | Haskell 2010 Core evaluator. Important semantic oracle, good stage boundary. |
| `src/Haskell2010/Core/FreeVars.hs` | Small free-variable utility. Good. |
| `src/Haskell2010/Core/Pretty.hs` | Core renderer. Good. |
| `src/Haskell2010/Core/Subst.hs` | Capture-aware substitution. Good boundary for optimizer/evaluator use. |
| `src/Haskell2010/Core/Syntax.hs` | Typed Core IR and builtin names. Strong architecture anchor. |
| `src/Haskell2010/Core/Validate.hs` | Core validator. Large but justified by invariant coverage. |
| `src/Haskell2010/Layout.hs` | Small layout helper over lexer/parser combinators. Good. |
| `src/Haskell2010/Lexer.hs` | Lexer and token utilities. Cohesive. |
| `src/Haskell2010/ModuleGraph.hs` | Module graph loader. Good isolated owner for filesystem/module loading. |
| `src/Haskell2010/Names.hs` | Unique-name model. Small and central. |
| `src/Haskell2010/Native.hs` | Haskell 2010 pipeline orchestration. Good facade exposing intermediate artifacts. |
| `src/Haskell2010/Parser.hs` | Parser. Large but expected; should remain syntax-only. |
| `src/Haskell2010/Pretty.hs` | Module-name renderer. Small. |
| `src/Haskell2010/Renamed.hs` | Renamed AST. Large but mostly structural data. |
| `src/Haskell2010/Renamer.hs` | Renaming, import/export, fixity, and scope logic. Correct layer, future split recommended. |
| `src/Haskell2010/STG/Eval.hs` | STG evaluator. Good independent lazy-runtime oracle. |
| `src/Haskell2010/STG/LLVM.hs` | Native STG-to-LLVM lowering and runtime helpers. Correct layer, future split strongly recommended. |
| `src/Haskell2010/STG/Lower.hs` | Core-to-STG lowering. Good transformation boundary. |
| `src/Haskell2010/STG/Syntax.hs` | STG IR. Small and cohesive. |
| `src/Haskell2010/STG/Validate.hs` | STG validator. Large but justified. |
| `src/Haskell2010/Syntax.hs` | Parsed Haskell 2010 AST. Broad by necessity. Good use of pattern synonyms and spans. |
| `src/Haskell2010/Typecheck.hs` | Largest architecture risk. Correct layer but owns too many responsibilities; split incrementally along future feature work. |
| `src/IR/ANF.hs` | Legacy ANF IR. Cohesive. |
| `src/IR/ANF/Resolved.hs` | Resolved ANF for Egglog. Cohesive. |
| `src/IR/ANF/Validate.hs` | ANF validator. Good defensive boundary. |
| `src/IR/Core.hs` | Legacy `.hg` report Core. Audit clarified it is report-only, not production optimizer substrate. |
| `src/Main.hs` | CLI entrypoint. Adequate now; should shrink when CLI productization expands. |
| `src/Optimize/CoreEgglog.hs` | Haskell 2010 Core optimizer adapter. Correctly validates input/output and preserves conservative behavior. |
| `src/Optimize/EGraph.hs` | Legacy e-graph optimizer. Cohesive. |
| `src/Optimize/EgglogBackend.hs` | Legacy ANF Egglog backend. Large but owns a single adapter. |
| `src/Optimize/EgglogBackend/Encode.hs` | Compatibility re-export. Acceptable short-term, but future public API should avoid thin placeholder modules unless they define stable boundaries. |
| `src/Optimize/EgglogBackend/Extract.hs` | Compatibility re-export. Same note as above. |
| `src/Optimize/EgglogBackend/Fragment.hs` | ANF fragment checking. Good separation. |
| `src/Optimize/EgglogBackend/Reconstruct.hs` | Compatibility re-export. Same note as above. |
| `src/Optimize/EgglogBackend/Rules.hs` | Egglog rule definitions. Good separation. |
| `src/Optimize/EgglogBackend/Schema.hs` | Egglog schema names. Good separation. |
| `src/Optimize/Rewrite.hs` | Legacy rewrite definitions. Cohesive. |
| `src/Optimize/Simplify.hs` | Legacy simplifier. Cohesive. |
| `src/Runtime/Int.hs` | Shared checked integer semantics. Good shared runtime primitive. |
| `src/Syntax/AST.hs` | Legacy `.hg` AST. Small and isolated. |
| `src/Syntax/Located.hs` | Legacy located AST utilities. One intentional partial path remains guarded by type inference; acceptable but should not spread. |
| `src/Syntax/Parser.hs` | Legacy `.hg` parser. Cohesive. |
| `src/Syntax/Pretty.hs` | Legacy pretty-printer. Cohesive. |
| `src/Syntax/Span.hs` | Shared span diagnostics. Good shared utility. |
| `src/Typecheck/Infer.hs` | Legacy `.hg` inference facade. Cohesive. |
| `src/Typecheck/Principal.hs` | Legacy principal type engine. Large but coherent. |
| `src/Typecheck/Types.hs` | Legacy type/error model. Cohesive. |

### Test and Fixture Files

| Path | Audit note |
| --- | --- |
| `test/Main.hs` | Broad unit/property/golden suite. Good coverage, organizational split recommended. |
| `test/e2e/Main.hs` | Native wet-test harness. Good artifact-level validation. |
| `test/e2e/programs/` | `.hg` and Haskell 2010 wet fixtures. Good executable examples. |
| `test/golden/` | Golden outputs for diagnostics/LLVM/reporting. Good regression surface. |
| `test/haskell2010-conformance/Main.hs` | Manifest-driven conformance harness. Good explicit status model. |
| `test/haskell2010/conformance/manifest.json` | Central Haskell 2010 conformance ledger. Good structure; expand coverage before claiming conformance. |
| `test/haskell2010/conformance/**` | Representative native, runtime-error, compile-error, and unsupported fixtures. Good baseline, not exhaustive. |

### Documentation Files

| File | Audit note |
| --- | --- |
| `docs/architecture.md` | This document. Architecture source of truth. |
| `docs/compiler-readiness-audit.md` | Historical readiness report. Keep as snapshot, not live status source. |
| `docs/current-capabilities.md` | Current capability summary. Should remain conservative. |
| `docs/diagnostics-spec.md` | Diagnostics direction. Good future-product reference. |
| `docs/e2e-results.md` | Recorded wet-test results. Keep updated only when intentionally recording snapshots. |
| `docs/e2e-wet-testing.md` | Wet testing rationale. Good. |
| `docs/egglog-backend.md` | Legacy Egglog backend docs. Good. |
| `docs/egglog-core-optimizer-plan.md` | Haskell 2010 Core optimizer plan. Good. |
| `docs/egglog-engine-spec.md` | Generic engine spec. Good. |
| `docs/full-compiler-definition.md` | Goal/baseline distinction. Important, keep conservative. |
| `docs/haskell2010-conformance-matrix.md` | Feature matrix. Critical status artifact. |
| `docs/haskell2010-conformance-results.md` | Latest conformance run snapshot. Good. |
| `docs/haskell2010-frontend-spec.md` | Frontend specification. Good. |
| `docs/haskell2010-implementation-plan.md` | Historical plan. Good. |
| `docs/haskell2010-roadmap.md` | Main roadmap. Good source of milestone state. |
| `docs/haskell2010-status-summary.md` | Live status summary. Audit fixed stale headings. |
| `docs/haskell2010-todo.json` | Machine-readable task ledger. Validated by script. |
| `docs/haskell2010-todo.md` | Human-readable task ledger. Large but useful; generated/validated mirror should remain synchronized. |
| `docs/index.md` | Documentation index. Audit linked architecture doc. |
| `docs/language-spec.md` | Legacy `.hg` language spec. Keep separate from Haskell 2010 claims. |
| `docs/laziness-and-stg-plan.md` | Lazy runtime plan. Good. |
| `docs/llvm-backend-spec.md` | LLVM backend design. Good. |
| `docs/llvm-backend.md` | LLVM backend status. Good. |
| `docs/optimizer-spec.md` | Legacy optimizer spec. Good. |
| `docs/roadmap.md` | General roadmap. Keep aligned with Haskell 2010 roadmap. |
| `docs/runtime-spec.md` | Runtime semantics. Good. |
| `docs/type-inference.md` | Legacy type inference direction. Good. |

### Examples

| Path | Audit note |
| --- | --- |
| `examples/*.hg` | Legacy `.hg` examples. Useful for substrate regression. |
| `examples/llvm/*.hg` | Native backend examples. Useful smoke-test inputs. |
| `examples/type-errors/*.hg` | Negative examples. Useful diagnostic fixtures. |

## Refactor Policy

Large compiler modules should be split by semantic ownership, not by arbitrary
line count. The safest rule is:

- First add tests for the behavior being touched.
- Move one cohesive group of types/functions.
- Preserve the public facade module.
- Run full validation.
- Only then make behavior changes.

The current codebase is well-made enough that the next work should prioritize
feature-coupled splits over a broad mechanical reorganization.
