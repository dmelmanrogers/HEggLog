# HeggLog Runtime Specification

This document describes the current strict `.hg` runtime behavior and the
intended runtime direction for the Haskell 2010 native compiler target. The
current runtime is mostly interpreter behavior plus the small C/LLVM-facing
runtime surface emitted by the LLVM backend.

## Current Runtime

The current runtime belongs to the strict `.hg` compiler-supported subset. It
supports checked signed `Int64`, `Bool`, closures where currently supported by
the interpreter and LLVM closure-conversion path, native executable printing,
checked arithmetic/division, and runtime-error behavior for overflow and
division failures. Native heap allocation is now deliberately routed through
process-lifetime allocation helpers in both LLVM backends:
`hegglog_alloc_process_lifetime` for the strict `.hg` path and
`hegglog_hs_alloc_process_lifetime` for the Haskell 2010 STG path. These
helpers abort on allocation failure and never free objects during program
execution.

Native executable runtime errors currently call `abort`, exit nonzero, and do
not print a rich runtime diagnostic. The wet tests record that current
convention.

## Haskell 2010 Runtime Target

The Haskell 2010 runtime target requires:

- lazy thunks
- sharing and update
- constructor closures
- recursive heap bindings for `letrec`
- black holes or documented equivalent behavior
- case as demand
- IO
- heap management through a GC, arena, reference counting, or another explicit
  allocation model; the current executable subset uses process-lifetime
  allocation rather than GC

The current strict runtime is not sufficient for Haskell 2010 laziness. The
planned STG/runtime path is documented in
[laziness-and-stg-plan.md](laziness-and-stg-plan.md).

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
- Successful `/` uses signed quotient semantics that truncate toward zero,
  matching LLVM `sdiv`.

LLVM:

- `+` lowers to `llvm.sadd.with.overflow.i64`.
- `-` lowers to `llvm.ssub.with.overflow.i64`.
- `*` lowers to `llvm.smul.with.overflow.i64`.
- The overflow flag branches to an `abort` block.
- `/` lowers to explicit zero-divisor and minimum-`Int / -1` checks before a
  plain `sdiv i64`; failed checks branch to `abort`.

## Printing

The LLVM backend emits a C-compatible `main` wrapper for root values.

Current behavior:

- `Int` roots are printed with `printf("%lld\n", value)`.
- `Bool` roots are zero-extended to `i32` and printed with `printf("%d\n",
  value)`.
- In the Haskell 2010 path, `main :: IO ()` roots execute the compiled IO
  action instead of scalar root printing. The implemented IO subset supports
  `putStrLn`, `print` through the supported `Show` scalar/string/list subset,
  `return`, `(>>)`, `(>>=)`, expression `do`, local `let`, and `<-`
  bind-statement sequencing. Core and STG evaluator IO values accumulate stdout
  chunks while carrying the returned action result; native LLVM represents this
  by forcing the first action, entering the bind continuation with that result,
  and forcing the returned action.

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

The generated runtime keeps `malloc` behind a backend-owned allocation helper:

```llvm
define ptr @hegglog_alloc_process_lifetime(i64 %size) { ... }
define ptr @hegglog_hs_alloc_process_lifetime(i64 %size) { ... }
```

The helper is the current ownership boundary: allocation failure branches to
`abort`, returned memory is process-lifetime, and generated programs do not
emit object destructors or a collection phase.

Checked arithmetic intrinsics are declared only when needed:

```llvm
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
```

Division does not use an LLVM overflow intrinsic. It emits comparisons and
branches before `sdiv`, and declares `abort` when division checks are present.

In the strict `.hg` backend, `malloc` is declared only for programs that
allocate closures because only those programs need the process-lifetime helper.
The Haskell 2010 STG backend emits its boxed runtime helpers for the native
path, so `malloc` remains part of that generated runtime surface.

## Runtime Ownership And Leak Policy

RTS-019 fixes the current ownership contract as an explicit process-lifetime
model. This is an intentional executable-subset decision, not an accidental
memory leak in an otherwise collecting runtime.

Owned by generated process-lifetime allocation helpers:

- Strict `.hg` closure-converted local closures.
- Haskell 2010 boxed `Int`, `Bool`, `Char`, list-of-`Char` `String`, function,
  thunk, and data objects.
- Haskell 2010 closure/thunk environment arrays.
- Haskell 2010 boxed constructor field arrays.
- Haskell 2010 runtime string buffers produced while implementing `Show Int`.

Not heap-owned by the generated runtime:

- Unboxed strict `.hg` `Int`/`Bool` values.
- LLVM registers, stack values, and function parameters.
- Static format-string globals and other LLVM globals.
- Source/Core/STG interpreter data structures, which remain owned by the host
  Haskell process while tests or compiler commands run.

Leak policy:

- Generated native programs may retain every runtime allocation until process
  exit.
- There are no generated `free` calls, object finalizers, reference counts,
  tracing GC roots, or sweep phases in the current runtime.
- Allocation failure is the only allocation lifecycle event handled at runtime;
  helpers null-check `malloc` and call `abort`.
- Long-running programs and allocation-heavy workloads are outside the current
  executable-subset performance claim until an arena or GC task replaces this
  helper implementation.

Tests assert this ownership boundary by checking that generated LLVM direct
`malloc` calls occur only inside the named allocation helpers. Future arena or
GC work should preserve those helper names as the backend/runtime API unless a
deliberate migration updates the tests and documentation together.

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
- Allocation: process-lifetime heap allocation through the generated runtime
  allocation helper.
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

Closure conversion and the Haskell 2010 boxed STG runtime introduce heap
allocation for closure, thunk, constructor-field-array, and short-lived runtime
string-buffer objects.

Decision for RTS-009:

- The current supported native executable subset uses process-lifetime
  allocation.
- There is no tracing GC, reference counting, or per-object free in this
  version.
- All generated heap allocations go through a named runtime allocation helper
  before reaching `malloc`, making the ownership policy testable and leaving one
  IR/API boundary for a future arena block allocator or collector.

Documentation decision for RTS-019:

- The above ownership/leak policy is the current runtime contract.
- Process-lifetime retention is acceptable for the supported compiler examples,
  conformance fixtures, and wet tests.
- It is not a claim of suitability for long-running server-style programs or
  arbitrary allocation-heavy Haskell workloads.

Possible policies:

- Arena allocation for short-lived compiled programs. The current helper is the
  API boundary for this future optimization.
- Reference counting for deterministic cleanup.
- Tracing garbage collection for richer functional workloads.
- Borrow/escape analysis to stack-allocate non-escaping environments.

Future decision needed:

- Choose whether the helper remains process-lifetime allocation for v1 or grows
  a block arena or collector when larger aggregate-heavy programs become a
  supported workload.

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
- LLVM checked division success, division-by-zero abort, and division-overflow
  abort behavior when LLVM execution tools are available.
- LLVM execution matching interpreter output for supported examples.
- LLVM closure differential examples for captured variables, returned closures,
  and higher-order local function values when execution tools are available.
- LLVM shape tests that direct `malloc` calls stay inside process-lifetime
  allocation helpers for both native backends.
