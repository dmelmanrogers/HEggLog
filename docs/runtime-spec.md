# HeggLog Runtime Specification

This document describes the current runtime behavior and the intended direction
for future runtime features. The current runtime is mostly interpreter behavior
plus the small C/LLVM-facing runtime surface emitted by the LLVM backend.

## Current Runtime Values

Implemented source/interpreter values:

- `Int`: checked signed 64-bit integer, represented in Haskell as `HInt`.
- `Bool`: boolean.
- Closure: interpreter-only value containing:
  - captured lexical environment
  - parameter name
  - body expression

Implemented LLVM values:

- `Int`: LLVM `i64`.
- `Bool`: LLVM `i1`.

Closure values are not implemented in the LLVM backend yet.

## Int Representation

HeggLog `Int` is a signed 64-bit integer with checked arithmetic.

Range:

```text
-9223372036854775808 through 9223372036854775807
```

Implementation:

- `src/Runtime/Int.hs` defines `HInt`.
- `mkHIntLiteral` checks whether an `Integer` fits in the `Int64` range.
- `addHInt`, `subHInt`, `mulHInt`, and `divHInt` compute with unbounded
  Haskell `Integer` internally, then re-check the result before returning
  `HInt`.
- Comparisons and equality operate on `HInt` values.

Current source literal syntax accepts unsigned decimal atoms only. This means
the source parser cannot directly write `-9223372036854775808`, but the runtime
can represent that value if checked arithmetic produces it.

Decision needed:

- Add unary negation or signed literal syntax.
- Recommendation: add unary negation as an expression form, not as part of the
  decimal literal token, to avoid tokenization ambiguity with subtraction.

## Bool Representation

HeggLog `Bool` has two values:

```text
true
false
```

Interpreter representation is Haskell `Bool`. LLVM representation is `i1`.
The generated `main` wrapper prints `Bool` roots as `0` or `1`.

## Runtime Errors

Current runtime error classes:

- Unknown variable.
- Runtime type error.
- Division by zero.
- Integer literal out of range.
- Checked integer overflow.

Unknown-variable and runtime-type errors are defensive interpreter errors;
well-typed closed programs should not produce them.

## Integer Error Behavior

Literal range errors:

- Typechecking rejects out-of-range source integer literals.
- The source and ANF interpreters also check literals defensively.
- Backend lowering checks literals before producing backend IR.
- Egglog fragment classification rejects invalid integer literals.

Overflow:

- `+`, `-`, and `*` return an overflow error if the exact mathematical result is
  outside the signed `Int64` range.
- `/` returns division by zero when the divisor is zero.
- `/` returns overflow for cases such as minimum `Int` divided by `-1`.

LLVM:

- `+` lowers to `llvm.sadd.with.overflow.i64`.
- `-` lowers to `llvm.ssub.with.overflow.i64`.
- `*` lowers to `llvm.smul.with.overflow.i64`.
- The overflow flag branches to an `abort` block.
- Division is currently outside the LLVM backend fragment.

## Printing

The LLVM backend emits a C-compatible `main` wrapper for root values.

Current behavior:

- `Int` roots are printed with `printf("%lld\n", value)`.
- `Bool` roots are zero-extended to `i32` and printed with `printf("%d\n",
  value)`.

The interpreter/report mode prints values through Haskell renderers:

- `Int` as decimal text.
- `Bool` as `true` or `false`.
- Closure as `<function>`.

Decision needed:

- Whether LLVM `Bool` output should become `true`/`false` text for user-facing
  consistency. Current tests specify `0`/`1`.

## Optimization Runtime Contract

Optimizers must preserve both successful results and runtime-error behavior.

Required preservation:

- Successful program result stays equal.
- Integer overflow must not be optimized away.
- A successful arithmetic expression must not be rewritten into one that
  overflows.
- Division by zero must not be hidden.
- Unsupported backend features must fail structurally rather than being
  miscompiled.

Examples:

- `x + 0 -> x` is safe for checked integers.
- `x * 0 -> 0` is safe for checked integers because `x` is an already evaluated
  atom in ANF.
- Distributivity is not generally safe under checked overflow and is not in the
  default compiler rules.
- Constant folding is allowed only when the checked operation succeeds.

## LLVM Runtime Surface

Current external declarations:

```llvm
declare i32 @printf(ptr, ...)
declare void @abort()
```

Checked arithmetic intrinsics are declared only when needed:

```llvm
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
```

There is no custom HeggLog runtime library yet.

## Future Function Runtime

Top-level first-order functions should compile to direct LLVM functions before
closure runtime work begins.

Planned direct-call model:

- Each top-level HeggLog function becomes an LLVM function.
- Arguments and results use backend types (`i64` for `Int`, `i1` for `Bool`).
- Calls are direct and do not allocate.

## Future Closure Runtime

Closure conversion should use this representation:

```text
closure = code pointer + environment pointer
```

The code pointer identifies a generated function. The environment pointer points
to a runtime layout containing captured values.

Required design decisions:

- Environment layout: struct per closure shape versus uniform boxed frame.
- Allocation: stack allocation for proven-local closures versus heap allocation.
- Lifetime management: explicit freeing, reference counting, arena allocation,
  or garbage collection.
- Calling convention: direct call after unpacking versus indirect function
  pointer call.
- Runtime type uniformity: whether all values become boxed, or only closures and
  future aggregate values are boxed.

Recommendation:

- Implement top-level first-order functions and non-capturing lambda lifting
  first.
- For closure conversion, start with heap-allocated environment structs and a
  deliberately simple ownership policy, then refine after tests force the
  lifetime model.

## Future Allocation And Memory Management

No heap allocation exists today.

Possible policies:

- Arena allocation for short-lived compiled programs.
- Reference counting for deterministic cleanup.
- Tracing garbage collection for richer functional workloads.
- Borrow/escape analysis to stack-allocate non-escaping environments.

Decision needed:

- Choose the smallest runtime policy that is correct for closures and future
  aggregate values.

## Runtime Acceptance Criteria

For supported compiled programs:

- Interpreter result equals compiled result for successful programs.
- Interpreter runtime-error class equals compiled runtime-error class for
  supported runtime errors.
- Unsupported backend features are reported as unsupported, not compiled.

Current checked tests cover:

- Interpreter overflow.
- Simplifier overflow preservation.
- Egglog constant overflow preservation.
- LLVM checked overflow abort behavior when LLVM execution tools are available.
- LLVM execution matching interpreter output for supported examples.
