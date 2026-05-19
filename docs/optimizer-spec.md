# HeggLog Optimizer Specification

This document defines the runtime-safety contract for HeggLog optimizers. It
first describes optimizations valid for the current strict, checked-`Int64`
`.hg` language, then records the Haskell 2010 Core optimizer direction.

## Contract

For every optimized closed ANF program:

- If the original program succeeds, the optimized program must succeed with the
  same value.
- If the original program raises a runtime error, the optimized program must
  raise the same runtime error class.
- An optimizer must not turn an erroring program into a successful program.
- An optimizer must not turn a successful program into an erroring program.
- An optimizer must not rely on LLVM backend limitations to justify a rewrite;
  source, ANF, and optimizer semantics are defined independently of backend
  support.

For open fragments, the optimizer cannot execute the program to compare
results. Open-fragment rules must therefore be syntactically or factually
obvious under all substitutions that respect the fragment types.

## Strict Evaluation

HeggLog is strict:

- A `let` right-hand side is evaluated before the body.
- Binary primitive operands are evaluated before the primitive operation.
- An `if` condition is evaluated before selecting a branch.
- The unselected branch of an `if` is not evaluated.

Because checked arithmetic and division can fail, preserving strict evaluation
dependencies is part of optimizer correctness.

## Checked Integer Errors

Optimizers must preserve these runtime errors:

- Addition overflow.
- Subtraction overflow.
- Multiplication overflow.
- Division by zero.
- Division overflow, including minimum `Int` divided by `-1`.
- Out-of-range integer literals, when encountered defensively after parsing.

Constant folding is allowed only when the checked operation succeeds. Failed
checked operations must not produce constant facts.
Successful division uses signed quotient semantics that truncate toward zero,
matching the interpreter and LLVM `sdiv` after explicit runtime checks.

## Default Egglog Rules

The default Egglog compiler rules currently allow these strict-safe identities:

- `x + 0 -> x`
- `0 + x -> x`
- `x - 0 -> x`
- `x * 1 -> x`
- `1 * x -> x`
- `x / 1 -> x`
- `0 / x -> 0` only when the numerator is known zero and the denominator is
  known nonzero
- `b == true -> b`
- `true == b -> b`
- `if true then a else b -> a`
- `if false then a else b -> b`
- `if b then true else false -> b`
- `if b then false else true -> b == false`

The default rules also derive checked constant facts for successful arithmetic,
comparisons, and equality. These facts can fold examples such as `3 * 0` and
`0 * 3` to `0`.

## Disabled Or Non-Default Rules

These rewrites are not default Egglog compiler rules:

- `x * 0 -> 0`
- `0 * x -> 0`
- `x == x -> true`
- `x < x -> false`
- `if c then a else a -> a`
- Distributivity, such as `x * (y + z) -> x * y + x * z`

The first five can erase evaluation of an expression or condition that would
otherwise raise a runtime error. Distributivity can change checked-overflow
behavior and can grow terms, so it remains experimental rather than a compiler
default.

## Boolean Optimizations

The source language does not currently have dedicated `&&`, `||`, or `not`
operators. Boolean optimizer rules apply to `==` and `if`.

Boolean rewrites are valid when they preserve evaluation of the condition or
boolean operand. For example, `b == true -> b` is safe because both expressions
evaluate `b`. `if b then true else false -> b` is safe because both expressions
evaluate `b` and neither branch can fail.

`if c then a else a -> a` is not safe as a general rule because it can erase an
erroring condition `c`.

## Division Optimizations

Division rules must prove both denominator safety and overflow safety before
materializing constants or replacing expressions.

Current safe cases:

- Constant division facts only when the denominator is known nonzero and the
  checked division succeeds.
- `x / 1 -> x`, which preserves evaluation of `x`.
- `0 / x -> 0` only when the numerator is known zero and the denominator is
  known nonzero.

Unsafe cases:

- Folding division by zero.
- Folding minimum `Int / -1`.
- Replacing a division expression in a way that skips evaluation of an erroring
  numerator or denominator.

## Validation Requirements

Production optimizer changes should include:

- Closed semantic preservation tests for successful values.
- Runtime-error preservation tests for overflow and division errors.
- Open-fragment tests for type consistency and conservative behavior.
- Extraction determinism tests when extraction behavior changes.
- `cabal build all`, `cabal test all`, `cabal check`, and `git diff --check`.

## Haskell 2010 Egglog Core Direction

The current ANF optimizer is substrate for the compiler and the prototype for
the Haskell 2010 optimizer strategy. The future optimizer will operate over
typed Core, not directly over Haskell source syntax and not over the current
strict ANF representation.

The Haskell 2010 Core optimizer must preserve lazy semantics and bottom. That
requires facts and guards such as totality, no-error, nonzero, no-overflow,
known-constructor, demand, and strictness facts. Rewrites such as `x * 0 -> 0`,
`if c then a else a -> a`, and `x / x -> 1` are unsafe without guards because
they can erase bottom or runtime errors.

Extraction from Egglog must produce typed Core, run the Core validator, preserve
types, avoid unbound variables, preserve bottom/error behavior, and emit
deterministic output with provenance. Optimized and unoptimized native wet tests
must agree.

See [egglog-core-optimizer-plan.md](egglog-core-optimizer-plan.md).
