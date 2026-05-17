# HeggLog

Initial vertical slice for a tiny typed functional language in Haskell.

## Build

```bash
cabal build
cabal test
```

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
- lowered Core IR

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
- selected golden CLI output sections
- QuickCheck property skeleton for ANF validation after lowering

Negative type fixtures live in `examples/type-errors/`. Golden fixtures live in
`test/golden/`.
