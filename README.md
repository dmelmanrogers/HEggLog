# HeggLog

Initial vertical slice for a tiny typed functional language in Haskell.

## Roadmap

The living development roadmap is in [docs/roadmap.md](docs/roadmap.md). It
tracks the implemented compiler baseline, remaining semantic work, and the next
implementation queue.

Current semantic specs:

- [Language specification](docs/language-spec.md)
- [Runtime specification](docs/runtime-spec.md)

## Build

```bash
cabal build
cabal test
```

CI runs `cabal build all`, `cabal test all`, `cabal check`, and
`git diff --check` on pushes to `main`/`develop` and on pull requests.

## Run

```bash
cabal run hegglog -- examples/test.hg
```

The CLI prints:

- parsed AST
- type
- result
- ANF IR
- inferred analysis facts
- optimized ANF IR
- applied rewrite trace
- report-only e-graph optimized ANF IR, or a structured unsupported-fragment
  message
- Egglog optimizer status, optimized ANF, costs, bounded run/rebuild stats, and
  structured unsupported/failure reasons
- lowered Core IR

## LLVM Backend

Closed first-order programs can be compiled to textual LLVM IR:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o build/arithmetic.ll
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm --run-llvm
```

The LLVM v0 backend supports `Int`, `Bool`, `let`, `if`, `+`, `-`, `*`, `<`,
and `==` over closed first-order programs. Lambdas, applications, closures,
recursion, heap allocation, free variables, and division are rejected
structurally. `Int` is a checked signed 64-bit value across the interpreter,
optimizers, backend IR, and LLVM lowering; overflow is reported by interpreters
and aborts in generated LLVM.

See `docs/llvm-backend.md` for the supported fragment, lowering strategy, CLI
behavior, and LLVM toolchain notes.

## Language MVP

Supported source forms:

- integer and boolean literals
- variables
- `let` bindings
- `if` / `then` / `else`
- arithmetic operators: `+`, `-`, `*`, `/`
- comparison operators: `<`, `==`
- lambda expressions: `\x : Int -> x + 1`
- function application: `f x`
- function types: `Int -> Int`
- parentheses

Function parameter annotations are required. Hindley-Milner inference and
generalization are intentionally out of scope for this slice.

## Architecture

- `Syntax.*` owns parsed source syntax and pretty-printing.
- `Typecheck.*` performs a simple environment-based typecheck with no
  Hindley-Milner generalization.
- `Eval.*` interprets checked expressions into runtime values.
- `IR.ANF` makes evaluation order explicit by atomizing primitive and
  application operands.
- `Analysis.*` defines relational facts over ANF terms. This keeps future
  egglog-style optimization grounded in analysis facts instead of a bare rewrite
  engine.
- `IR.Core` lowers syntax into explicit Core nodes for future equality
  saturation work.
- `Optimize.Placeholder` is isolated from parsing, typechecking, and eval. This
  is where future egglog extraction and rewrite passes should live.
- `Optimize.Rewrite` describes future conditional rewrites. Guards such as
  `NonZero x` are preferable to globally unsound rules like unconditional
  `x / x => 1`.
- `Optimize.Simplify` is a small fact-aware ANF rewrite engine. It validates
  optimizer input and output, records applied rules, and is intentionally
  replaceable by a future e-graph or egglog backend.
- `Optimize.EGraph` is an isolated prototype e-graph backend for a pure
  first-order ANF fragment. It supports arithmetic, boolean literals,
  variables, and simple `if` terms; lambdas and applications return structured
  unsupported-fragment diagnostics.
- `IR.ANF.Resolved` alpha-resolves ANF binders into deterministic binder ids and
  explicit free variables. It is generic ANF infrastructure, not tied to the
  Egglog backend.
- `Egglog.*` is a standalone typed equality-saturation kernel with user sorts,
  function declarations, merge behavior, rebuild, rule evaluation, and
  extraction.
- `Optimize.EgglogBackend` is the compiler adapter from resolved ANF into the
  Egglog kernel. It classifies a typed first-order fragment, encodes integer and
  boolean terms into separate Egglog sorts, runs compiler rules as `Rule` data,
  extracts back to valid ANF, and reports structured unsupported/failure states.
- `Backend.*` lowers closed first-order ANF into a typed backend IR and then into
  deterministic textual LLVM IR with a small C-compatible printing `main`.

Binder-aware equality saturation remains future work. Lambda rewrites require
alpha equivalence, capture avoidance, beta-reduction discipline, and extraction
cost models before they can be optimized safely.

## Test Harness

The test suite is grouped by compiler concern:

- parser precedence and grouping
- structured negative typechecking cases
- source-vs-ANF semantic preservation
- ANF validation and invariants
- relational fact inference
- fact-aware simplification and semantic preservation
- e-graph insertion, union/find, extraction, rewrite behavior, unsupported
  fragments, and semantic preservation on the supported fragment
- Egglog kernel invariants, resolved ANF binding behavior, backend encoding,
  compiler rules, extraction/reconstruction, structured unsupported reporting,
  deterministic optimization, and semantic preservation on supported programs
- LLVM backend validation, structured unsupported cases, deterministic SSA/phi
  lowering, selected LLVM golden files, and optional execution checks against
  the interpreter when LLVM tools are available
- selected golden CLI output sections
- QuickCheck properties for ANF validation after lowering and Egglog semantic
  preservation on generated supported ANF fragments

Negative type fixtures live in `examples/type-errors/`. Golden fixtures live in
`test/golden/`.

## License

HeggLog is licensed under the MIT License. See [LICENSE](LICENSE).
