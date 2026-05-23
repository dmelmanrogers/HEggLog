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

Implemented today for the Haskell 2010 target:

- layout-aware Haskell 2010 frontend
- renamer, module graph loading, imports, exports, qualified aliases, and
  whole-program flattening for the executable subset
- typed Core IR, validator, and utilities
- Hindley-Milner typechecker and source-to-Core desugaring for the documented
  executable subset
- Core-0 reference evaluator for validated typed Core
- STG-like lazy IR and in-process runtime evaluator
- Core-to-STG lowering for the executable subset
- native executable output for the executable subset through a boxed lazy
  STG LLVM runtime
- Egglog Core optimization for safe typed Core fragments, including Core-0
  arithmetic/Bool rewrites and known-constructor case/projection rewrites, with
  Core/STG/native oracle tests and `--no-egglog` comparison coverage
- custom ADTs, list/tuple and Prelude data constructors, recursion,
  user-defined dictionary-passed classes, built-in `Eq`/`Ord`/`Num`/`Show`
  dictionary calls, overloaded integer literals/defaulting, `main :: IO ()`,
  `putStrLn`, `print`, and same-directory multi-file modules
- a mandatory Haskell 2010 conformance baseline with a JSON manifest, 151
  fixtures, exact native stdout checks, runtime-error checks, compile-error
  checks, and explicit unsupported-feature cases

Planned for the broader Haskell 2010 target:

- broader `Show`/`String` interoperability and library behavior
- superclasses, default methods, instance contexts, deriving, additional
  numeric classes, and the broader Prelude hierarchy
- irrefutable/lazy pattern semantics, richer diagnostics, broader IO/Monad
  support, package search paths, and full Haskell 2010 conformance

The current compiler passes the documented executable-subset conformance cases.
Full Haskell 2010 conformance remains incomplete. Unsupported features are now
represented as explicit conformance fixtures rather than omitted from testing.

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

Run only the Haskell 2010 conformance baseline:

```bash
cabal test haskell2010-conformance-test --test-options='--hide-successes'
```

Validate the Haskell 2010 engineering backlog:

```bash
python3 scripts/validate-haskell2010-todo.py
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

Compile a supported Haskell 2010 `.hs` program to a native executable:

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

The same `--no-egglog` flag disables the Haskell 2010 Core optimizer for `.hs`
Core-0 programs.

## Haskell 2010 Roadmap

- [Haskell 2010 roadmap](docs/haskell2010-roadmap.md)
- [Haskell 2010 engineering backlog](docs/haskell2010-todo.md)
- [Haskell 2010 conformance matrix](docs/haskell2010-conformance-matrix.md)
- [Haskell 2010 conformance results](docs/haskell2010-conformance-results.md)
- [Haskell 2010 implementation plan](docs/haskell2010-implementation-plan.md)
- [Haskell 2010 frontend specification](docs/haskell2010-frontend-spec.md)
- [Haskell 2010 status summary](docs/haskell2010-status-summary.md)
- [Laziness and STG plan](docs/laziness-and-stg-plan.md)
- [Egglog Core optimizer plan](docs/egglog-core-optimizer-plan.md)

The detailed Haskell 2010 engineering backlog is tracked in
[docs/haskell2010-todo.md](docs/haskell2010-todo.md).

Full documentation index:

- [docs/index.md](docs/index.md)

## Current Compiler vs Haskell 2010 Target

| Area | Status |
| --- | --- |
| Current `.hg` strict subset | Implemented and tested. |
| Haskell 2010 parser/layout | Implemented as an isolated parser/layout frontend and parser-tested; connected to the executable `.hs` compile path. |
| Haskell 2010 renamer/modules | Implemented as an isolated unique-name pass with module graph loading, export/import filtering, qualified aliases, hiding, `Thing(..)` children, and root-module `main` selection for the executable subset. |
| Haskell 2010 typed Core | Implemented as a typed IR with validator, free-variable analysis, substitution, pretty-printer, and source generation for the executable subset. |
| Haskell 2010 typechecker/desugarer | Implemented for explicit signatures, HM polymorphism, functions, lambdas, application, `let`, `if`, cases, ADTs, lists/tuples, recursion, user-defined class dictionaries, built-in Prelude data, generated Prelude list functions, primitive `/`, dictionary-backed `Eq`/`Ord`/`Num`/`Show` methods, numeric defaulting, guards/as-patterns, module imports, and the first IO printing slice. |
| Haskell 2010 Core reference evaluator | Implemented for validating typed Core with lazy let/function/constructor-field thunks, erased Core type abstraction/application, Bool/user/list/tuple/Prelude-data case execution, generated Prelude functions, user and built-in class dictionary calls, IO output actions, checked `Int` primitives, and structured runtime errors. |
| Haskell 2010 STG/lazy runtime | Implemented as an isolated STG-like IR, validator, pure heap evaluator, Core-to-STG lowering, and boxed LLVM/native runtime for the current executable subset, including thunks, enter/apply, constructor dispatch, dictionary constructor/selector execution, IO output actions, checked primitives, and native wet tests. |
| Haskell 2010 conformance baseline | Implemented as the mandatory `haskell2010-conformance-test` Cabal suite. It reads `test/haskell2010/conformance/manifest.json`, invokes the built `hegglog` executable as a subprocess, compiles and runs native artifacts directly, checks exact stdout, and verifies runtime-error, compile-error, and unsupported-documented cases. |
| LLVM/native backend | Implemented for the current `.hg` supported subset. |
| Egglog ANF backend | Implemented for the current `.hg` supported subset. |
| Egglog Core optimizer | Implemented for safe Haskell 2010 Core fragments using typed Core validation, provenance, and optimized/unoptimized native agreement tests. Current rewrites cover Core-0 `Int`/`Bool` fragments plus known literal and saturated known-constructor case/projection rewrites. |
| Native wet tests | Implemented for the current `.hg` native compiler baseline and the Haskell 2010 executable native path, including default Egglog and `--no-egglog` modes. |

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

HeggLog now supports same-directory whole-program Haskell 2010
modules/imports, the documented executable pattern-matching subset, built-in
`Show Int`/`Show Bool`, numeric defaulting for the supported executable class
slice, and `main :: IO ()` for stdout-oriented programs. It does not yet
support the full class hierarchy/default methods/deriving, package databases,
irrefutable/lazy pattern semantics, broad `Show`/`String` interop, or broad
IO/Monad libraries. Those unsupported areas now have explicit conformance
fixtures, and lazy semantics are implemented for the current executable subset.

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
- [Haskell 2010 conformance results](docs/haskell2010-conformance-results.md)

## CI

CI runs `cabal build all`, `cabal test all --test-options='--hide-successes'`,
`cabal check`, `git diff --check`, and mandatory clang-backed end-to-end wet
tests on pushes to `main`/`develop` and on pull requests. The Haskell 2010
conformance suite is part of `cabal test all` and is not optional.

## License

HeggLog is licensed under the MIT License. See [LICENSE](LICENSE).
