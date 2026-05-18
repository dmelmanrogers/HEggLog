# Current Capabilities

This document is the quick reference for what HeggLog can run, optimize, and
compile today. For the longer project plan, see [roadmap.md](roadmap.md).

## Working Compiler Baseline

HeggLog is a working compiler for a supported typed functional subset. The
compiler can parse and typecheck source programs, lower them through ANF and
Backend IR, optionally optimize supported ANF with the Egglog backend, emit
LLVM IR, and build native executables through `clang`.

The source interpreter remains the semantic reference for the language. The
LLVM/native backend is intentionally narrower than the interpreter and rejects
unsupported programs structurally.

## Interpreted Language Support

Report/interpreter mode supports the implemented expression language:

- signed checked `Int64` runtime values
- `Bool`
- variables
- nonrecursive `let`
- `if`
- integer `+`, `-`, `*`, and `/`
- integer `<`
- `==` over `Int` and `Bool`
- lambda expressions
- function application
- ordered nonrecursive top-level first-order function definitions
- local higher-order functions
- optional lambda parameter annotations when monomorphic inference is concrete

Run report/interpreter mode with:

```bash
cabal run hegglog -- examples/test.hg
```

## Egglog Optimization Support

The compile path tries Egglog optimization by default when the program shape is
inside the supported optimizer fragment. Unsupported optimizer fragments fall
back explicitly to unoptimized ANF; they do not block compilation.

The Egglog backend currently optimizes typed pure first-order ANF with:

- integer constants and checked arithmetic: `+`, `-`, `*`, `/`
- integer `<`
- integer and boolean `==`
- boolean and integer `if`
- variables
- lets
- integer constant, boolean constant, and zero/nonzero lattice facts

The Egglog backend does not currently optimize local closures, higher-order
programs, recursive functions, user-defined data, or effectful constructs.

Use `--no-egglog` to compile without Egglog optimization:

```bash
cabal run hegglog -- compile examples/llvm/division.hg -o /tmp/hegglog-division --no-egglog
```

## LLVM And Native Compile Support

The LLVM/native backend supports closed programs with printable `Int` or `Bool`
roots. Supported compiled forms include:

- `Int` and `Bool` literals
- variables bound by `let`
- nonrecursive `let`
- `if`
- checked integer `+`, `-`, `*`, and `/`
- integer `<`
- `==` over `Int` and `Bool`
- ordered top-level first-order functions
- saturated direct calls to top-level functions
- lambda-lifted non-capturing lambdas
- closure-converted local function values, including captured variables and
  local closure calls

Unsupported compile targets include:

- function-valued roots
- partial or over-applied top-level calls
- using a top-level function as a first-class value
- recursion
- open programs with free variables
- strings, arrays, records, tuples, modules, imports, ADTs, and pattern matching

Emit LLVM IR:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/hegglog.ll
```

Build a native executable:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic
/tmp/hegglog-arithmetic
```

Build and run in one command:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic --run
```

Native executable output requires `clang`. LLVM text output does not require an
external LLVM toolchain.

## Runtime Semantics

Runtime behavior is strict and checked:

- `Int` is a signed 64-bit runtime value.
- Integer literals must fit in the nonnegative source literal range before
  evaluation.
- `+`, `-`, and `*` are checked for signed `Int64` overflow.
- `/` checks division by zero and the minimum-`Int / -1` overflow case.
- `if` evaluates the condition, then only the selected branch.
- `let` evaluates the right-hand side before the body.
- Generated native code prints `Int` roots as decimal text and `Bool` roots as
  `0` or `1`.
- Generated native code aborts on checked arithmetic runtime errors.

## Known Limitations

- User-facing Hindley-Milner polymorphism is not implemented.
- Optional top-level type signatures are not implemented; top-level definitions
  require explicit signatures.
- ADTs, pattern matching, modules, imports, strings, and aggregate data types
  are absent.
- Some diagnostics remain developer-oriented, especially parser normalization
  and precise nested runtime-error source locations.
- Closure allocation currently uses process-lifetime heap ownership; long-term
  ownership and freeing are not finalized.
- Advanced Egglog boolean/domain reasoning and indexed/adaptive joins remain
  future work.
- Release packaging is still minimal Cabal metadata rather than a polished
  distribution.

## Next Roadmap Items

The next high-value stabilization work is:

- normalize the CLI around explicit `check`, `run`, `compile`, and `report`
  commands
- add process-level CLI artifact tests
- improve nested runtime-error source spans
- decide the v1 Bool output policy
- expand CI to cover required LLVM toolchains where appropriate
