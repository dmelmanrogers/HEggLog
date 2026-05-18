# HeggLog Egglog Backend

This document describes the current `.hg` ANF Egglog backend. It is distinct
from the generic Egglog kernel in [egglog-engine-spec.md](egglog-engine-spec.md)
and is reused by the initial Haskell 2010 typed Core optimizer described in
[egglog-core-optimizer-plan.md](egglog-core-optimizer-plan.md).

The current backend optimizes the existing strict `.hg` compiler-supported
subset directly. Haskell 2010 Core optimization goes through
`Optimize.CoreEgglog`, which conservatively adapts safe Core-0 fragments to this
backend and decodes extracted results back into typed Core.

The Egglog backend is an isolated compiler optimization backend for a typed,
pure ANF fragment. It does not replace the existing simplifier or the older
e-graph prototype. The backend proves a narrower path:

```text
ANF -> resolved ANF -> typed Egglog database -> rules -> extraction -> valid ANF
```

## Typed Sorts

Compiler expressions are not encoded into one untyped `Expr` sort. The backend
uses separate Egglog sorts:

- `IExpr` for integer expressions
- `BExpr` for boolean expressions

Integer constructors include `INum`, `IVar`, `IAdd`, `ISub`, `IMul`, `IDiv`,
and `IIf`.
Boolean constructors include `BBool`, `BVar`, `ILt`, `IEq`, `BEq`, and `BIf`.

This keeps ill-typed terms out of the Egglog database. The extracted root must
have the same compiler type as the original ANF root.

## Resolved Binders

ANF is alpha-resolved before encoding. Every `let` and lambda binder receives a
stable `BinderId`, and variable references point either to a specific binder or
to an explicit free variable.

The backend never keys local variables by raw textual names alone. A shadowing
program such as:

```haskell
let x = 1 in
let y = let x = 2 in x in
x + y
```

uses distinct binder keys for the two `x` binders, so optimization preserves the
value `3`.

## Encoding

Each supported expression is encoded as an Egglog term. Local binders are encoded
as typed variable constructors with deterministic binder keys. A supported pure
let also adds an equality between the binder term and the encoded RHS term.

The backend keeps a map of encoded binders and reconstructs only the bindings
needed by the extracted root. Dead pure lets may be dropped.

## Rules

Compiler optimizations are ordinary Egglog `Rule` data. The default compiler
ruleset includes:

- `x + 0 = x`
- `0 + x = x`
- `x * 1 = x`
- `1 * x = x`
- integer constant facts for `INum`, `IAdd`, `ISub`, `IMul`, and checked
  `IDiv`
- boolean constant facts for `BBool`, integer `<`, integer `==`, and boolean
  `==`
- checked subtraction by zero
- checked division by one
- checked zero numerator division when the denominator is known nonzero
- boolean `== true` simplification
- boolean `if c then true else false = c`
- boolean `if c then false else true = c == false`
- zero-info-driven boolean facts for comparisons against zero
- `if true then a else b = a`
- `if false then a else b = b`

Distributivity is kept out of the default compiler ruleset because it can grow
terms. It remains available as an experimental ruleset.

The default compiler rules intentionally avoid open identities such as
`x * 0 = 0`, `0 * x = 0`, `x == x = true`, `x < x = false`, and
`if c then a else a = a` because those rewrites can erase strict evaluation of
a local binding or condition that would otherwise raise an integer runtime
error. Constant multiplication by zero can still fold through checked constant
facts, for example `3 * 0 = 0`, because those facts are not produced for
overflowing arithmetic, division by zero, or division overflow.

The optimizer runtime contract is specified in `docs/optimizer-spec.md`.

## Evaluation

The Egglog kernel runs rules with semi-naive evaluation by default. Initial
actions populate a delta database, and each later iteration evaluates a rule
once for each premise whose root lookup or root match has changed entries. Other
premises in that planned join still read the full database, so recursive rules
such as transitive closure see combinations of new and existing facts without
rescanning every unchanged tuple as the driver.

Rule evaluation uses a stable join planner in both naive and semi-naive modes.
The planner estimates relation sizes from the current function tables, treats a
semi-naive delta premise as the size of its delta table, prefers smaller ready
premises, and delays computed/equality premises until the variables needed to
evaluate them are bound. Ties fall back to original premise order so traces and
extraction remain deterministic.

The older naive mode remains available through `RunNaive` for equivalence tests
and debugging. Semi-naive and naive runs are checked against each other for
kernel transitive-closure behavior, and compiler backend tests compare optimized
ANF results across both modes.

Rules without a delta-eligible lookup or root function match still run naively.
That keeps equality-only and empty-premise rules correct while preserving the
same dependency-aware premise ordering.

## Constants As Facts

Constants are represented inside Egglog as functions:

- `IConst : IExpr -> ConstInt`
- `BConst : BExpr -> ConstBool`
- `IZero : IExpr -> ZeroInfo`

`ConstInt`, `ConstBool`, and `ZeroInfo` are typed lattice values. Merging the
same known fact is stable, unknown values refine to known values, while
conflicting known facts produce a conflict value. No function entry still means
"no fact"; it is not confused with unknown or conflict.

`ConstInt` known values use the language `Int` policy: signed 64-bit literals
and checked `+`/`-`/`*`/`/` facts. Division facts require a known nonzero
denominator, and `minBound / -1` overflow does not derive a false known
constant, so extraction cannot mask a runtime error.

`ZeroInfo` records whether a known integer expression is zero, nonzero,
unknown, or conflicted. It is derived from integer literals and folded integer
constants. Checked division consumes nonzero facts before deriving constants or
applying zero-numerator rewrites.

Constant folding is driven by Egglog rules over these facts, not by a Haskell
pre-pass.

## Extraction

Extraction starts from the typed root function and selects a cheapest equivalent
Egglog term. The backend reconstructs ANF rather than emitting a raw expression
tree:

- primitive operands are atomized with deterministic temporaries
- required binder definitions are retained
- unused pure bindings are dropped
- reconstructed ANF is validated
- reconstructed type must equal the original type
- closed supported programs are evaluated before and after optimization

If extraction chooses a binder as the best representative for that binder's own
RHS, the backend falls back to the original RHS to avoid emitting `let x = x`.
The synthetic root marker is ignored during root extraction so an expression
that cannot be folded still reconstructs as ordinary ANF.

## Provenance And Debug Traces

The Egglog kernel can preserve debug logs with `collectDebugLog = True`. Changed
initial actions, rule actions, and substitutions are recorded with compact
action renderings such as:

```text
rule edge-to-path substitution #0 {x=1, y=2}: assert path(?x:Int, ?y:Int)
```

Backend runs enable trace collection internally and expose both the raw
`encodedRunDebugLog` and the compact `provenanceTrace` on successful
optimization results. The compact trace summarizes encoded initial actions,
applied rules, function-entry counts, union counts, the extracted root term, the
reconstructed optimized ANF, and a bounded set of rule-action trace lines.

## Supported Fragment

Supported:

- `Int` literals
- `Bool` literals
- variables with resolvable type
- `let` bindings
- integer `Add`
- integer `Sub`
- integer `Mul`
- integer `Div`, with checked constant facts and conservative rewrites only
- integer `Lt`
- integer `Eq`
- boolean `Eq`
- `if` expressions with a `Bool` condition and branches of the same supported
  type

Unsupported:

- lambdas
- applications
- higher-order values
- recursion
- effects
- ill-typed or ambiguous terms

Unsupported terms return structured backend errors. The backend does not
silently fall back to another optimizer.

Open ANF fragments are supported only when every free variable occurrence has a
single inferred type. A free variable name that is used as both `Int` and `Bool`
is rejected during fragment classification instead of being encoded into
separate Egglog sorts and reconstructed as an impossible source variable.

## Semantic Contract

For supported closed ANF programs, the backend checks:

- optimized ANF validates
- optimized type equals original type
- successful results and runtime errors are preserved
- extraction is deterministic in tests
- optimized cost does not exceed original cost after saturation

If cost-driven extraction produces ANF that fails semantic validation, the
optimizer conservatively returns the original ANF and records semantic fallback
provenance. That preserves strict runtime-error dependencies instead of
turning an optimizer extraction mistake into a miscompile.

## Remaining Gaps

- additional domain-specific lattice values
- indexed/adaptive join execution beyond relation-size estimates
- rule language/parser
- full ANF integration
- binder-aware higher-order EqSat
- deeper cost model tuning
