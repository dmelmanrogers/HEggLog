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
- arithmetic lowers to `add`, `sub`, and `mul` on `i64`
- `<` lowers to `icmp slt`
- `==` lowers to `icmp eq`
- `if` lowers to then/else/join blocks with a `phi` in the join block

Nested `if` expressions work because each branch returns the current predecessor
block label for the enclosing `phi`.

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

## External Tools

Textual IR and structural tests do not require LLVM tools. Execution tests detect
available tools:

- `lli`, if available
- otherwise `clang`, if available

If neither is available, execution checks are skipped gracefully.

## Integer Semantics

LLVM v0 represents `Int` as signed 64-bit machine integers. Arithmetic uses LLVM
`i64 add`, `mul`, and `sub`. The interpreter currently uses Haskell `Integer`,
so programs outside the `i64` range expose a known semantic gap. Current tests
avoid overflow.

Future work should define a single language-level integer policy: fixed `Int64`,
checked overflow, wrapping semantics, or an arbitrary-precision runtime.

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
