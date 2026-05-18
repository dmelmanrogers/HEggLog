# HeggLog

HeggLog is a Haskell 2010 native compiler project implemented in Haskell. The
current repository contains a working native compiler for a strict `.hg` subset,
including Egglog-inspired optimization, LLVM IR generation, native executable
output, and end-to-end wet tests. That compiler is the substrate for the active
Haskell 2010 compiler roadmap: layout-aware parsing, renaming, Hindley-Milner
typechecking, typed Core, Egglog Core optimization, STG-like lazy lowering,
runtime support, and LLVM machine-code output.

The active target is Haskell 2010 source to native executables through LLVM and
clang. Current `.hg` support is not Haskell 2010 and does not claim GHC
compatibility.

## Current Status

Implemented today for the current `.hg` compiler-supported subset:

- parsing, typechecking, and report/interpreter mode
- ANF and resolved ANF
- Egglog optimization for supported strict ANF fragments
- checked signed `Int64` runtime semantics
- top-level first-order functions, lambda lifting, and local closure conversion
- LLVM IR generation
- native executable output through `clang`
- mandatory black-box wet tests that compile real `.hg` files, execute native
  artifacts, verify stdout/stderr/exit codes, compare report-mode
  `Result: <value>` output, and compile selected emitted LLVM through `clang`

Planned for the Haskell 2010 target:

- layout-aware Haskell 2010 frontend
- renamer and module/import resolution
- typed Core IR, validator, and utilities
- Core-0 Hindley-Milner typechecker and source-to-Core desugaring for the
  first `Int`/`Bool` subset
- Core-0 reference evaluator for validated typed Core
- STG-like lazy IR and in-process runtime evaluator
- Core-to-STG lowering for the first Core-0 subset
- native executable output for the first Core-0 subset through a boxed lazy
  STG LLVM runtime
- full Haskell 2010 class constraints and dictionaries
- Egglog optimizer over typed Core
- broader runtime-linked LLVM/native executable output for `.hs` programs

## Quickstart

Build and test:

```bash
cabal build all
cabal test all
```

Run the mandatory end-to-end wet-test path:

```bash
scripts/e2e-wet-test.sh
```

Run current `.hg` report/interpreter mode:

```bash
cabal run hegglog -- examples/test.hg
```

Compile a current supported `.hg` program to a native executable:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-arithmetic
/tmp/hegglog-arithmetic
# 14
```

Compile a Core-0 Haskell 2010 `.hs` program to a native executable:

```bash
cabal run hegglog -- compile test/e2e/programs/haskell2010/lazy-argument.hs -o /tmp/hegglog-hs
/tmp/hegglog-hs
# 1
```

Emit LLVM IR instead of a native executable:

```bash
cabal run hegglog -- compile examples/llvm/arithmetic.hg --emit-llvm -o /tmp/hegglog-arithmetic.ll
```

Compile without Egglog optimization:

```bash
cabal run hegglog -- compile examples/llvm/division.hg -o /tmp/hegglog-division --no-egglog
```

Do not use Haskell 2010 `.hs` examples as working compile commands yet. Haskell
2010 source support is the active roadmap, not the current frontend.

## Haskell 2010 Roadmap

- [Haskell 2010 roadmap](docs/haskell2010-roadmap.md)
- [Haskell 2010 conformance matrix](docs/haskell2010-conformance-matrix.md)
- [Haskell 2010 implementation plan](docs/haskell2010-implementation-plan.md)
- [Haskell 2010 frontend specification](docs/haskell2010-frontend-spec.md)
- [Haskell 2010 status summary](docs/haskell2010-status-summary.md)
- [Laziness and STG plan](docs/laziness-and-stg-plan.md)
- [Egglog Core optimizer plan](docs/egglog-core-optimizer-plan.md)

Full documentation index:

- [docs/index.md](docs/index.md)

## Current Compiler vs Haskell 2010 Target

| Area | Status |
| --- | --- |
| Current `.hg` strict subset | Implemented and tested. |
| Haskell 2010 parser/layout | Implemented as an isolated parser/layout frontend and parser-tested; connected to the Core-0 native `.hs` compile path. |
| Haskell 2010 renamer | Implemented as an isolated unique-name pass and unit-tested; connected to the Core-0 native `.hs` compile path. |
| Haskell 2010 typed Core | Implemented as a typed IR with validator, free-variable analysis, substitution, pretty-printer, and Core-0 source generation. |
| Haskell 2010 Core-0 typechecker/desugarer | Implemented for explicit signatures, HM polymorphism, `Int`, `Bool`, top-level functions, lambdas, application, `let`, `if`, Bool `case`, and primitive arithmetic/comparison. |
| Haskell 2010 Core-0 reference evaluator | Implemented for validating typed Core with lazy let/function argument thunks, erased Core type abstraction/application, Bool case execution, checked `Int` primitives, and structured runtime errors; native executable compilation now exists through the STG path. |
| Haskell 2010 STG/lazy runtime | Implemented as an isolated STG-like IR, validator, pure heap evaluator, Core-to-STG lowering, and boxed LLVM/native runtime for the Core-0 `Int`/`Bool` subset, including thunks, enter/apply, Bool case dispatch, checked primitives, and native wet tests. |
| LLVM/native backend | Implemented for the current `.hg` supported subset. |
| Egglog ANF backend | Implemented for the current `.hg` supported subset. |
| Egglog Core optimizer | Planned for the Haskell 2010 Core pipeline. |
| Native wet tests | Implemented for the current `.hg` native compiler baseline; Haskell 2010 wet tests will be added with Haskell 2010 features. |

## Current `.hg` Language Support

Report/interpreter mode supports the implemented strict expression language:

- checked signed `Int64`
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

The LLVM/native backend is narrower than report mode. It supports closed
programs with printable `Int` or `Bool` roots, top-level first-order calls,
lambda-lifted non-capturing functions, and closure-converted local function
values. It rejects unsupported targets structurally.

HeggLog does not yet support Haskell 2010 modules, imports, ADTs, pattern
matching, classes/instances, Prelude, IO `main`, or lazy semantics.

## Existing Specs

- [Current capabilities](docs/current-capabilities.md)
- [Full compiler definition](docs/full-compiler-definition.md)
- [Language specification for `.hg`](docs/language-spec.md)
- [Runtime specification](docs/runtime-spec.md)
- [Diagnostics specification](docs/diagnostics-spec.md)
- [Optimizer specification](docs/optimizer-spec.md)
- [Egglog engine specification](docs/egglog-engine-spec.md)
- [Egglog backend](docs/egglog-backend.md)
- [LLVM backend](docs/llvm-backend.md)
- [LLVM backend specification](docs/llvm-backend-spec.md)
- [Type inference direction](docs/type-inference.md)
- [End-to-end wet testing](docs/e2e-wet-testing.md)
- [Recorded wet-test results](docs/e2e-results.md)

## CI

CI runs `cabal build all`, `cabal test all`, `cabal check`, `git diff --check`,
and mandatory clang-backed end-to-end wet tests on pushes to `main`/`develop`
and on pull requests.

## License

HeggLog is licensed under the MIT License. See [LICENSE](LICENSE).
