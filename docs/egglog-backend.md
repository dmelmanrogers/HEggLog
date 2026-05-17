# HeggLog Egglog Backend

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

Integer constructors include `INum`, `IVar`, `IAdd`, `IMul`, and `IIf`.
Boolean constructors include `BBool`, `BVar`, and `BIf`.

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
- `x * 0 = 0`
- `0 * x = 0`
- integer constant facts for `INum`, `IAdd`, and `IMul`
- boolean constant facts for `BBool`
- `if true then a else b = a`
- `if false then a else b = b`
- `if c then a else a = a`

Distributivity is kept out of the default compiler ruleset because it can grow
terms. It remains available as an experimental ruleset.

## Constants As Facts

Constants are represented inside Egglog as functions:

- `IConst : IExpr -> ConstInt`
- `BConst : BExpr -> ConstBool`

`ConstInt` and `ConstBool` are typed lattice values. Merging the same known
constant is stable, while conflicting known constants produce a conflict value.
No function entry still means "no fact"; it is not confused with unknown or
conflict.

`ConstInt` known values use the language `Int` policy: signed 64-bit literals
and checked `+`/`*` facts. If a constant rule would overflow, it does not derive
a false known constant, so extraction cannot mask a runtime overflow.

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

## Supported Fragment

Supported:

- `Int` literals
- `Bool` literals
- variables with resolvable type
- `let` bindings
- integer `Add`
- integer `Mul`
- `if` expressions with a `Bool` condition and branches of the same supported
  type

Unsupported:

- lambdas
- applications
- higher-order values
- recursion
- effects
- division
- subtraction
- equality and ordering primitives
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
- evaluation result is preserved
- extraction is deterministic in tests
- optimized cost does not exceed original cost after saturation

## Remaining Gaps

- semi-naive evaluation
- richer lattice values
- generic join planning
- rule language/parser
- full ANF integration
- binder-aware higher-order EqSat
- cost model improvements
