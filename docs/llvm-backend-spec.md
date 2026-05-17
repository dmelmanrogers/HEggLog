# LLVM Backend Specification

This specification defines the current HeggLog LLVM backend contract. It is
normative for the v0 backend fragment; `docs/llvm-backend.md` remains the
operational guide for CLI use and toolchain workflow.

## Scope

The LLVM backend compiles a typed, closed, first-order expression program to
deterministic textual LLVM IR.

The pipeline is:

```text
source -> located parse -> typecheck -> ANF -> optional Egglog -> Backend IR -> LLVM IR -> text
```

The source interpreter is the semantic reference. The LLVM backend must either:

- produce a program whose observable root output matches interpreter execution
  for the supported successful fragment
- abort on checked-`Int` overflow for supported arithmetic runtime failures
- reject unsupported source constructs before LLVM generation when possible
- reject invalid internal IR with structured validation errors

## Supported Source Fragment

The LLVM source fragment is closed and first-order.

Supported source forms:

- unsigned decimal `Int` literals that fit in HeggLog `Int`
- `Bool` literals
- variables bound by `let`
- nonrecursive `let`
- `if` expressions with `Bool` conditions and same-typed branches
- integer `+`, `-`, and `*`
- integer `<`
- `==` over `Int`
- `==` over `Bool`

Rejected source forms:

- lambdas
- function application
- higher-order values
- free variables
- division
- recursion
- heap allocation
- strings
- user-defined data

The compile path rejects lambdas, applications, and division using located source
diagnostics before ANF-to-backend lowering. Open programs and malformed internal
IR are still defended by ANF and backend validators.

## Type Mapping

HeggLog types map through Backend IR before LLVM:

| HeggLog | Backend IR | LLVM |
| --- | --- | --- |
| `Int` | `BI64` | `i64` |
| `Bool` | `BI1` | `i1` |

Function types have no LLVM backend representation in v0. Any function-typed
source expression is outside the supported fragment.

## Value Representation

`Int` is a checked signed 64-bit value. Backend IR stores integer constants as
`HInt`, so literals have already passed range validation before LLVM lowering.
`Bool` is represented as `i1`.

The generated C-compatible `main` prints root values as:

- `Int`: signed decimal text followed by a newline
- `Bool`: `1` for true and `0` for false, followed by a newline

## Evaluation Contract

ANF lowering makes operand evaluation order explicit before Backend IR lowering.
For supported source programs, LLVM output must preserve the interpreter result
for:

- literals
- let-bound variable lookup and shadowing
- primitive arithmetic and comparison
- equality over `Int` and `Bool`
- conditional branch selection

The supported fragment is pure. There are no user-visible side effects before
the generated `main` prints the root value.

## Runtime Errors

Supported arithmetic operations `+`, `-`, and `*` use checked signed overflow
lowering. LLVM lowering emits one of:

- `llvm.sadd.with.overflow.i64`
- `llvm.ssub.with.overflow.i64`
- `llvm.smul.with.overflow.i64`

The generated code extracts the result and overflow flag. If the overflow flag
is set, control branches to an overflow block that calls `abort` and ends with
`unreachable`.

Runtime-error equivalence for v0 means:

- the interpreter reports `RuntimeIntError (IntOverflow op lhs rhs)`
- generated LLVM contains the matching checked overflow intrinsic for `op`
- LLVM execution terminates unsuccessfully when an execution tool is available

Division is not part of the LLVM fragment, so division-by-zero equivalence is a
future contract.

## Backend IR Contract

Backend IR is the code-generation input. It contains:

- typed atoms: variables, `HInt`, and `Bool`
- typed primitive expressions
- typed `if`
- typed `let`
- a typed root expression
- provenance comments

Backend IR has no lambda or application constructors. The validator enforces:

- root type matches inferred root expression type
- variables are bound in scope
- atom annotations match inferred atom types
- primitive operands have the primitive's required operand type
- primitive result annotations match primitive result type
- `if` conditions are `BI1`
- `if` branches have matching types
- `let` body annotations match inferred body type

ANF-to-backend lowering must validate ANF before lowering and validate Backend IR
after lowering.

## LLVM IR Contract

Generated modules contain:

- comments describing HeggLog provenance and selected optimization status
- format-string globals for root printing
- external declarations required by the generated program
- one root function
- one C-compatible `main`

Root functions:

```llvm
define i64 @hegglog_main_i64() { ... }
define i1 @hegglog_main_i1() { ... }
```

Only one root function is emitted per module, selected by root type.

`main`:

- calls the selected root function
- zero-extends `i1` roots to `i32` for printing
- calls `printf`
- returns `i32 0` on successful execution

Control-flow lowering:

- each source/backend `if` lowers to then, else, and join blocks
- the join block contains a `phi`
- incoming `phi` labels use the actual predecessor blocks produced after nested
  lowering

LLVM validation enforces:

- unique function names
- unique block labels per function
- unique SSA registers per function
- known branch targets
- known local registers
- operand type consistency
- branch conditions are `i1`
- valid `extractvalue` aggregate types and indices
- nonempty `phi` incoming lists
- `phi` incoming labels reference existing blocks
- function return type matches terminator return type

## Egglog Optimization

Egglog optimization is optional in the LLVM pipeline.

If enabled and successful, LLVM lowers the optimized ANF. If Egglog reports an
unsupported fragment, LLVM compilation continues with original ANF and records
that fallback in module comments. If Egglog fails internally, LLVM compilation
fails before backend lowering.

The selected ANF, whether original or optimized, is validated before Backend IR
lowering.

## Toolchain Contract

Pure compiler validation does not require external LLVM tools. When tools are
available, tests add these checks:

- `llvm-as` assembles selected emitted golden modules to bitcode
- `lli` executes emitted LLVM text when available
- `clang` is the fallback execution path when `lli` is unavailable

External-tool checks skip gracefully when the relevant tool is unavailable.

## Required Tests

The current contract is covered by:

- Backend IR validation tests
- LLVM IR validation tests
- deterministic LLVM golden tests
- `llvm-as` validation for selected goldens when available
- optional `lli`/`clang` execution for fixture programs
- interpreter-vs-LLVM differential tests for successful supported programs
- interpreter-vs-LLVM runtime-error equivalence tests for checked arithmetic
  overflow

## Extension Rules

Future LLVM backend features must update this specification when they add or
change:

- supported source syntax
- runtime-error behavior
- Backend IR constructors or invariants
- LLVM IR shapes
- runtime declarations
- external tool expectations
- differential or golden test obligations
