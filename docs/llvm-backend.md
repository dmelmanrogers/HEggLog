# HeggLog LLVM Backend

This document describes the LLVM/native backend for the current strict `.hg`
compiler-supported subset. The backend emits LLVM IR and can produce native
executables through `clang` for that subset.

The Haskell 2010 target will reuse the LLVM/native direction, but Haskell 2010
lowering requires typed Core, an STG-like lazy IR, runtime linking, and lazy
runtime support. The current strict backend is not sufficient for lazy Haskell
semantics by itself.

The LLVM backend is the first executable code generation path for HeggLog. It is
intentionally narrow but now includes a first closure runtime pass: it compiles
closed, pure programs with first-order roots, ordered top-level functions,
saturated direct calls, lambda-lifted non-capturing functions, and local closure
calls into a small typed backend IR, lowers that IR into structured LLVM IR, and
emits either textual LLVM or a native executable through `clang`.

For the normative semantic contract, see
[`docs/llvm-backend-spec.md`](llvm-backend-spec.md).

```text
source -> typecheck -> lambda lift -> ANF or closure conversion -> Backend IR -> LLVM IR -> text or clang executable
```

## Supported Fragment

Supported in v0:

- closed programs
- `Int` literals
- `Bool` literals
- variables bound by `let`
- `let` bindings
- integer `+`, `-`, `*`, and checked `/`
- integer `<`
- `==` over `Int` or `Bool`
- `if` expressions with `Bool` conditions and same-typed branches
- ordered top-level first-order functions
- saturated direct calls to top-level functions
- lambda lifting for non-capturing let-bound lambdas and lambdas used directly
  in function position
- closure conversion for local function values, including captured variables,
  returned closures, and calls through local closure variables

Rejected structurally:

- free variables and open ANF
- function-valued root expressions
- partial and over-applied top-level calls
- using a top-level function as a first-class value
- recursion
- strings and user-defined data

The regular interpreter remains the semantic reference for source execution.
The LLVM backend does not replace it.

## Type Mapping

HeggLog types lower to backend types before LLVM:

- `Int` -> `BI64` -> LLVM `i64`
- `Bool` -> `BI1` -> LLVM `i1`
- `T1 -> T2` -> `BClosure arg result` -> opaque LLVM `ptr`

Backend types are ordinary Haskell constructors, not raw strings. Validation
checks all variable, primitive, `if`, and root types before LLVM lowering.

## Backend IR

The backend IR is smaller than ANF and codegen-oriented. It contains typed atoms,
typed primitive expressions, scoped `let`, typed `if`, top-level function
definitions, direct function calls, closure allocation, closure application,
environment-field access, and a closed root expression. It has no source lambda
constructor; closure conversion lowers lambdas before LLVM codegen.

## LLVM Lowering

Lowering uses SSA:

- literals become LLVM constants
- variables are looked up in the current SSA environment
- `let` lowers the RHS and binds the source name to the resulting SSA operand
- `+`, `-`, and `*` lower to the LLVM checked overflow intrinsics for signed
  `i64`
- `/` lowers to explicit zero-divisor and minimum-`Int / -1` checks followed by
  `sdiv i64`
- `<` lowers to `icmp slt`
- `==` lowers to `icmp eq`
- `if` lowers to then/else/join blocks with a `phi` in the join block
- top-level functions lower to LLVM functions with typed parameters
- direct calls lower to ordinary LLVM `call` instructions
- closure allocation calls `malloc`, stores a code pointer plus captured fields,
  and aborts on null allocation
- closure calls load the code pointer and lower to indirect LLVM calls

Nested `if` expressions work because each branch returns the current predecessor
block label for the enclosing `phi`.

For `+`, `-`, and `*`, lowering emits `llvm.sadd.with.overflow.i64`,
`llvm.ssub.with.overflow.i64`, or `llvm.smul.with.overflow.i64`, extracts the
value and overflow flag, and branches to an `abort` block when the flag is set.
For `/`, lowering checks the divisor for zero and checks minimum `Int` divided
by `-1` before emitting `sdiv i64`; either failed check branches to `abort`.

## Generated Functions

For `Int` roots the backend emits:

```llvm
define i64 @hegglog_main_i64() { ... }
```

For `Bool` roots it emits:

```llvm
define i1 @hegglog_main_i1() { ... }
```

It also emits:

```llvm
declare i32 @printf(ptr, ...)
define i32 @main() { ... }
```

Programs that contain checked `+`, `-`, or `*` declare the corresponding LLVM
overflow intrinsics and `abort`. Programs that contain checked `/` declare
`abort`. Programs that allocate closures declare `malloc` and `abort`.

Top-level source functions emit deterministic LLVM functions named with a
collision-free escaped form of the source name, prefixed by `hegglog_fun_`.
Source parameters lower to LLVM function parameters with the same escaping
policy, and direct calls in function bodies or the root call those generated
functions.

`main` prints `Int` roots as decimal integers and `Bool` roots as `0` or `1`.
The emitter uses opaque pointer syntax (`ptr`) for the `printf` declaration and
format-string pointers.

## CLI Usage

Existing report mode is unchanged:

```bash
cabal run hegglog -- examples/test.hg
```

LLVM compile mode:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o build/arithmetic.ll
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm --no-egglog
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm --run-llvm
```

Native executable mode:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg -o build/arithmetic
./build/arithmetic

cabal run hegglog -- compile examples/llvm/arithmetic.hg -o build/arithmetic --run
cabal run hegglog -- compile examples/llvm/division.hg -o build/division --no-egglog
```

The shorthand form also works:

```bash
cabal run hegglog -- examples/llvm/arithmetic.hg --emit-llvm
```

When Egglog optimization is enabled and unsupported, compile mode reports the
reason and continues with unoptimized ANF. Backend unsupported constructs still
produce structured compile errors.

## Assembly And Executable Workflow

The compiler can either write textual LLVM IR directly or build a native
executable by passing generated LLVM text to `clang` with an argument list:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o build/arithmetic.ll
llvm-as build/arithmetic.ll -o build/arithmetic.bc
lli build/arithmetic.ll
clang build/arithmetic.ll -o build/arithmetic
./build/arithmetic

cabal run hegglog -- compile examples/llvm/arithmetic.hg -o build/arithmetic
./build/arithmetic
```

`llvm-as` checks that emitted text is accepted by LLVM's parser and assembler.
`lli` is useful for fast interpretation. `clang` produces a native executable
and links against the platform C runtime for `printf` and `abort`.

Native executable mode requires `clang`. If `clang` is unavailable, the CLI
prints a structured toolchain error and exits nonzero. Temporary LLVM files used
only for native builds are cleaned up after the clang invocation. `--run` builds
the requested executable and then runs it, preserving program stdout; build
status and toolchain diagnostics are written to stderr. Runtime errors in
generated code call `abort`, so the executable exits unsuccessfully.

The test suite validates selected LLVM golden outputs against checked-in text.
When `llvm-as` is available, those same emitted modules are also assembled to
bitcode. It also runs a small differential corpus through both the interpreter
and LLVM execution path when `lli` or `clang` is available, comparing LLVM stdout
against the interpreter-derived root value. Native executable tests compile and
run representative artifacts with `clang` when available, including arithmetic,
comparison, division, Bool roots, `--no-egglog`, and runtime-error aborts. The
corpus includes captured closures, returned closures, and higher-order local
function values.

## External Tools

Textual IR and structural tests do not require LLVM tools. Execution tests detect
available tools:

- `llvm-as`, if available, for assembly validation
- `lli`, if available
- otherwise `clang`, if available
- `clang`, required for native executable output

If the relevant external tool is unavailable, that external-tool check is
skipped gracefully. Pure Haskell validation and textual golden tests still run.

## Integer Semantics

HeggLog `Int` is a signed 64-bit integer with checked arithmetic. Source integer
literals are currently unsigned decimal atoms and must fit in
`[0, 9223372036854775807]`; out-of-range literals are rejected before code
generation. Negative values can still be produced by checked arithmetic. The
source interpreter, ANF interpreter, simplifier, Egglog constant facts, backend
IR, and LLVM lowering all share the signed `Int64` runtime policy.

Checked `+`, `-`, and `*` either produce an in-range `Int` or report overflow.
Checked `/` reports division by zero or minimum-`Int / -1` overflow before the
generated code reaches `sdiv`. LLVM programs abort on these runtime errors.

Tests cover this runtime-error equivalence for checked arithmetic: the same
source program must fail in the interpreter with the corresponding checked
runtime error, emit guarded LLVM, and terminate unsuccessfully when run through
the available LLVM execution toolchain.

## Relationship With Egglog

The LLVM pipeline can lower original ANF, Egglog-optimized ANF, or
closure-converted source:

1. parse
2. typecheck
3. lambda-lift eligible non-capturing lambdas
4. lower to ANF and validate it
5. optionally try Egglog optimization for the first-order fragment, or
   closure-convert higher-order source programs
6. validate Backend IR
7. lower to LLVM IR
8. validate and emit LLVM IR
9. optionally validate emitted text with `llvm-as`
10. optionally run LLVM text with `lli` or a temporary clang executable
11. optionally build the requested native executable with `clang`

Egglog remains an optimizer. LLVM remains a code generation backend.
The current Egglog optimizer is expression-oriented; source programs with
top-level, lambda-lifted, or closure-converted functions bypass Egglog and lower
through the original ANF or closure-converted Backend IR.

## Future Work

- recursion
- closure memory reclamation
- richer primitives
- LLVM optimization pass integration
