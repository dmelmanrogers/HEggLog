# HeggLog Runtime Specification

This document describes the current runtime behavior and the intended direction
for future runtime features. The current runtime is mostly interpreter behavior
plus the small C/LLVM-facing runtime surface emitted by the LLVM backend.

## Current Runtime Values

Implemented source/interpreter values:

- `Int`: checked signed 64-bit integer, represented in Haskell as `HInt`.
- `Bool`: boolean.
- Closure: interpreter value containing:
  - captured lexical environment
  - parameter name
  - body expression

Implemented LLVM values:

- `Int`: LLVM `i64`.
- `Bool`: LLVM `i1`.
- Closure: opaque LLVM `ptr` to a heap object whose first field is a code
  pointer and whose remaining fields are captured values.

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
HeggLog is strict: evaluating an expression includes evaluating every enclosing
`let` right-hand side and every condition needed to choose a branch. An
optimization is unsound if it removes an evaluation that would have raised a
checked integer runtime error.

Required preservation:

- Successful program result stays equal.
- Integer overflow must not be optimized away.
- A successful arithmetic expression must not be rewritten into one that
  overflows.
- Division by zero must not be hidden.
- Division overflow, such as minimum `Int` divided by `-1`, must not be hidden.
- An erroring `if` condition must not be hidden even when both branches are
  syntactically equal.
- Unsupported backend features must fail structurally rather than being
  miscompiled.

Examples:

- `x + 0 -> x` is safe for checked integers.
- `x * 1 -> x`, `1 * x -> x`, `x - 0 -> x`, and `x / 1 -> x` are safe because
  they preserve evaluation of `x`.
- Open multiplication-by-zero identities such as `x * 0 -> 0` and `0 * x -> 0`
  are not default Egglog compiler rules. In ANF, `x` may be a local binding
  whose right-hand side overflows or divides by zero; replacing the whole
  expression with `0` would erase that strict runtime error.
- Constant multiplication by zero, such as `3 * 0 -> 0` and `0 * 3 -> 0`, is
  allowed when the optimizer has derived checked constant facts for the
  operands. Checked facts are not produced for overflowing arithmetic, division
  by zero, or division overflow.
- `if true then a else b -> a` and `if false then a else b -> b` are safe.
- `if c then a else a -> a` is not a default Egglog compiler rule because it
  can erase evaluation of an erroring condition `c`.
- Distributivity is not generally safe under checked overflow and is not in the
  default compiler rules.
- Constant folding is allowed only when the checked operation succeeds.

## LLVM Runtime Surface

Current external declarations:

```llvm
declare i32 @printf(ptr, ...)
declare void @abort()
declare noalias ptr @malloc(i64)
```

Checked arithmetic intrinsics are declared only when needed:

```llvm
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
```

`malloc` is declared only for programs that allocate closures. There is no
custom HeggLog runtime library yet.

## Function Runtime

Top-level first-order functions compile to direct LLVM functions.

Direct-call model:

- Each top-level HeggLog function becomes an LLVM function.
- Arguments and results use backend types (`i64` for `Int`, `i1` for `Bool`).
- Calls are direct and do not allocate.

## Closure Runtime

Closure conversion uses this representation:

```text
closure object = code pointer + captured environment fields
```

The closure pointer itself is passed as the environment pointer to generated
closure-code functions. Field 0 is the loaded code pointer. Fields 1..n store
captured values in deterministic name order.

Current policy:

- Environment layout: one LLVM struct shape per closure capture list.
- Allocation: heap allocation with `malloc`.
- Allocation failure: null-check and `abort`.
- Lifetime management: process-lifetime allocation; closures are not freed in
  the first runtime pass.
- Calling convention: closure calls load field 0 and perform an indirect LLVM
  call with the closure pointer followed by the source argument.
- Runtime type uniformity: `Int` and `Bool` remain unboxed; closures are boxed.

Future refinements:

- Free or collect closure objects.
- Stack-allocate non-escaping closures after escape analysis.
- Introduce a custom runtime allocator if future aggregate values need it.

## Future Allocation And Memory Management

Closure conversion introduces heap allocation for closure objects.

Possible policies:

- Arena allocation for short-lived compiled programs.
- Reference counting for deterministic cleanup.
- Tracing garbage collection for richer functional workloads.
- Borrow/escape analysis to stack-allocate non-escaping environments.

Decision needed:

- Choose the long-term ownership policy for closures and future aggregate
  values.

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
- LLVM closure differential examples for captured variables, returned closures,
  and higher-order local function values when execution tools are available.
