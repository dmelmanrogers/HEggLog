# LLVM Backend Specification

This specification defines the current HeggLog LLVM backend contract for the
strict `.hg` compiler-supported subset. It is normative for the v0 backend
fragment; `docs/llvm-backend.md` remains the operational guide for CLI use and
toolchain workflow.

The future Haskell 2010 backend will still use LLVM/native machine-code output,
but it must lower from STG-like lazy IR and link a runtime system. This current
strict backend does not implement lazy Haskell semantics on its own.

## Scope

The LLVM backend compiles a typed, closed source program with an `Int` or `Bool`
root to deterministic textual LLVM IR, and the CLI can pass that generated IR to
`clang` to produce a native executable. Source programs may include ordered
top-level first-order functions, saturated direct calls, lambda-lifted
non-capturing functions, and local closure values.

The pipeline is:

```text
source -> located parse -> typecheck -> lambda lift -> ANF or closure conversion -> Backend IR -> LLVM IR -> text or clang executable
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
- integer `+`, `-`, `*`, and `/`
- integer `<`
- `==` over `Int`
- `==` over `Bool`
- ordered top-level function definitions with `Int`/`Bool` parameters and
  `Int`/`Bool` returns
- saturated direct calls to top-level functions
- non-capturing let-bound lambdas and lambdas used directly in function position,
  after lambda lifting to generated top-level functions

Rejected source forms:

- function-valued root expressions
- partial or over-applied top-level calls
- using a top-level function as a first-class value
- free variables
- recursion
- strings
- user-defined data

The compile path lambda-lifts eligible lambdas. Programs that still contain
local function values use closure conversion. Top-level function values,
partial top-level calls, and function-valued roots are rejected before LLVM
generation when possible. Open programs and malformed internal IR are still
defended by ANF and backend validators.

## Type Mapping

HeggLog types map through Backend IR before LLVM:

| HeggLog | Backend IR | LLVM |
| --- | --- | --- |
| `Int` | `BI64` | `i64` |
| `Bool` | `BI1` | `i1` |
| `T1 -> T2` | `BClosure arg result` | `ptr` |

Top-level function signatures lower to LLVM function signatures. Top-level
function-typed parameters and returns are still outside the supported fragment;
local function values lower to heap-allocated closures.

## Value Representation

`Int` is a checked signed 64-bit value. Backend IR stores integer constants as
`HInt`, so literals have already passed range validation before LLVM lowering.
`Bool` is represented as `i1`. Closure values are opaque pointers to heap
objects. Field 0 stores the generated code pointer, and fields 1..n store
captured values in deterministic name order.

The generated C-compatible `main` prints root values as:

- `Int`: signed decimal text followed by a newline
- `Bool`: `1` for true and `0` for false, followed by a newline

The Haskell 2010 STG-to-LLVM path additionally recognizes `main :: IO ()`.
For that entrypoint shape, `main` forces the compiled IO action instead of
auto-printing a scalar root. The implemented IO subset supports `putStrLn`,
`print` through the supported `Show` scalar/string/list subset, `return`, and
`(>>)`.

## Evaluation Contract

ANF lowering makes operand evaluation order explicit before Backend IR lowering.
For supported source programs, LLVM output must preserve the interpreter result
for:

- literals
- let-bound variable lookup and shadowing
- primitive arithmetic and comparison
- equality over `Int` and `Bool`
- conditional branch selection
- ordered top-level function scope
- saturated direct calls to top-level functions
- closure creation
- captured variable lookup through the closure environment
- closure calls through local function values

The strict `.hg` supported fragment is pure. Haskell 2010 `main :: IO ()`
programs in the implemented output subset can write stdout through the compiled
IO action.

## Runtime Errors

Supported arithmetic operations use checked signed `Int64` lowering. For `+`,
`-`, and `*`, LLVM lowering emits one of:

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

For `/`, LLVM lowering checks the divisor against zero and checks the
minimum-`Int / -1` overflow case before emitting `sdiv i64`. Failed checks call
`abort` and end with `unreachable`; successful division uses signed quotient
semantics that truncate toward zero, matching LLVM `sdiv`.

## Backend IR Contract

Backend IR is the code-generation input. It contains:

- typed atoms: variables, `HInt`, and `Bool`
- typed primitive expressions
- typed `if`
- typed `let`
- top-level function definitions with typed parameters and returns
- typed direct calls to top-level functions
- typed closure allocation
- typed closure application
- typed environment-field access
- a typed root expression
- provenance comments

Backend IR has no source lambda constructor. The validator
enforces:

- root type matches inferred root expression type
- function names are unique
- function parameter names are unique per function
- function body type matches the declared return type
- direct call targets exist
- direct call arity matches the target function
- direct call argument types match the target parameter types
- closure code functions have the expected environment, argument, and return
  signature
- closure captures match environment field types
- closure applications call closure-typed atoms with matching argument types
- environment-field accesses use valid indices and field types
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
- zero or more top-level functions
- zero or more generated closure-code functions
- one root function
- one C-compatible `main`

Top-level functions use deterministic names:

```llvm
define i64 @hegglog_fun_inc(i64 %arg_x) { ... }
```

Source identifiers are escaped injectively before they are used as LLVM function
or parameter names, so distinct source names cannot collide after lowering.

Root functions:

```llvm
define i64 @hegglog_main_i64() { ... }
define i1 @hegglog_main_i1() { ... }
```

Only one root function is emitted per module, selected by root type. Top-level
functions are emitted before the root function.

Closure-code functions are emitted as ordinary LLVM functions. Their first
parameter is the closure object pointer, used as the environment pointer. Their
second parameter is the source lambda argument. Closure calls load field 0 from
the closure object and emit an indirect LLVM call with the closure pointer and
argument.

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

The current Egglog optimizer works over expression ANF. Source programs with
top-level, lambda-lifted, or closure-converted definitions are treated as
unsupported for Egglog and continue through the original ANF program or
closure-converted Backend IR.

The selected ANF, whether original or optimized, is validated before Backend IR
lowering.

## Toolchain Contract

Pure compiler validation and LLVM text emission do not require external LLVM
tools. Native executable output requires `clang`; absence of `clang` is reported
as a structured toolchain error by the CLI. When tools are available, tests add
these checks:

- `llvm-as` assembles selected emitted golden modules to bitcode
- `lli` executes emitted LLVM text when available
- `clang` is the fallback execution path when `lli` is unavailable
- `clang` builds persistent native executables for representative programs

External-tool checks skip gracefully when the relevant tool is unavailable.
Native compile mode does not shell-concatenate commands; it invokes `clang` with
an argument list, captures stdout and stderr, and returns structured build
failure information that includes the command, exit code, stdout, and stderr.

## Required Tests

The current contract is covered by:

- Backend IR validation tests
- LLVM IR validation tests
- deterministic LLVM golden tests
- `llvm-as` validation for selected goldens when available
- optional `lli`/`clang` execution for fixture programs
- native executable build/run tests when `clang` is available
- interpreter-vs-LLVM differential tests for successful supported programs
- top-level parser/typechecker tests, lambda-lifting tests, and direct-call LLVM
  execution tests
- closure-conversion LLVM tests and interpreter-vs-LLVM closure differential
  examples
- interpreter-vs-LLVM runtime-error equivalence tests for checked arithmetic
  overflow and division failures

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

Haskell 2010 lowering must also update this specification or add a successor
spec covering STG-to-LLVM lowering, runtime linking, constructor/thunk layout,
enter/apply convention, and lazy runtime diagnostics.
