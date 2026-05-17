# HeggLog LLVM Backend

The LLVM backend is the first executable code generation path for HeggLog. It is
intentionally narrow: it compiles closed, pure, first-order ANF programs into a
small typed backend IR, lowers that IR into structured LLVM IR, and emits textual
LLVM.

```text
source -> typecheck -> ANF -> optional Egglog -> Backend IR -> LLVM IR
```

## Supported Fragment

Supported in v0:

- closed programs
- `Int` literals
- `Bool` literals
- variables bound by `let`
- `let` bindings
- integer `+`, `-`, and `*`
- integer `<`
- `==` over `Int` or `Bool`
- `if` expressions with `Bool` conditions and same-typed branches

Rejected structurally:

- free variables and open ANF
- lambdas
- applications
- higher-order values
- recursion
- heap allocation
- strings and user-defined data
- division

The regular interpreter remains the semantic reference for source execution.
The LLVM backend does not replace it.

## Type Mapping

HeggLog types lower to backend types before LLVM:

- `Int` -> `BI64` -> LLVM `i64`
- `Bool` -> `BI1` -> LLVM `i1`

Backend types are ordinary Haskell constructors, not raw strings. Validation
checks all variable, primitive, `if`, and root types before LLVM lowering.

## Backend IR

The backend IR is smaller than ANF and codegen-oriented. It contains typed atoms,
typed primitive expressions, scoped `let`, typed `if`, and a closed root
expression. It has no lambda/application constructors, so unsupported
higher-order programs cannot leak into codegen.

## LLVM Lowering

Lowering uses SSA:

- literals become LLVM constants
- variables are looked up in the current SSA environment
- `let` lowers the RHS and binds the source name to the resulting SSA operand
- arithmetic lowers to the LLVM checked overflow intrinsics for signed `i64`
- `<` lowers to `icmp slt`
- `==` lowers to `icmp eq`
- `if` lowers to then/else/join blocks with a `phi` in the join block

Nested `if` expressions work because each branch returns the current predecessor
block label for the enclosing `phi`.

For `+`, `-`, and `*`, lowering emits `llvm.sadd.with.overflow.i64`,
`llvm.ssub.with.overflow.i64`, or `llvm.smul.with.overflow.i64`, extracts the
value and overflow flag, and branches to an `abort` block when the flag is set.

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

Programs that contain checked arithmetic also declare the corresponding LLVM
overflow intrinsics and `abort`.

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

The shorthand form also works:

```bash
cabal run hegglog -- examples/llvm/arithmetic.hg --emit-llvm
```

When Egglog optimization is enabled and unsupported, compile mode reports the
reason and continues with unoptimized ANF. Backend unsupported constructs still
produce structured compile errors.

## Assembly And Executable Workflow

The compiler emits textual LLVM IR. A local LLVM toolchain can validate,
interpret, or compile that IR:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o build/arithmetic.ll
llvm-as build/arithmetic.ll -o build/arithmetic.bc
lli build/arithmetic.ll
clang build/arithmetic.ll -o build/arithmetic
./build/arithmetic
```

`llvm-as` checks that emitted text is accepted by LLVM's parser and assembler.
`lli` is useful for fast interpretation. `clang` produces a native executable
and links against the platform C runtime for `printf` and `abort`.

The test suite validates selected LLVM golden outputs against checked-in text.
When `llvm-as` is available, those same emitted modules are also assembled to
bitcode. It also runs a small differential corpus through both the interpreter
and LLVM execution path when `lli` or `clang` is available, comparing LLVM stdout
against the interpreter-derived root value.

## External Tools

Textual IR and structural tests do not require LLVM tools. Execution tests detect
available tools:

- `llvm-as`, if available, for assembly validation
- `lli`, if available
- otherwise `clang`, if available

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
LLVM programs abort on overflow. Division remains outside the LLVM backend
fragment.

Tests cover this runtime-error equivalence for checked `+`, `-`, and `*`: the
same source program must fail in the interpreter with a checked-`Int` overflow,
emit the corresponding LLVM overflow intrinsic, and terminate unsuccessfully
when run through the available LLVM execution toolchain.

## Relationship With Egglog

The LLVM pipeline can lower either original ANF or Egglog-optimized ANF:

1. parse
2. typecheck
3. lower to ANF
4. validate ANF
5. optionally try Egglog optimization
6. validate the selected ANF
7. lower to Backend IR
8. validate Backend IR
9. lower to LLVM IR
10. validate and emit LLVM IR
11. optionally validate emitted text with `llvm-as`
12. optionally run with `lli` or compile and run with `clang`

Egglog remains an optimizer. LLVM remains a code generation backend.

## Future Work

- top-level functions
- lambda lifting
- closure conversion
- recursion
- runtime representation
- heap allocation
- richer primitives
- LLVM optimization pass integration
