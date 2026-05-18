# Current Capabilities

This document describes what HeggLog can do today and separates current `.hg`
support from the active Haskell 2010 target.

## Current Native Compiler Capability

The current compiler-supported source language is the strict HeggLog `.hg`
subset. For that subset, HeggLog can:

- parse source files
- typecheck and elaborate source
- run report/interpreter mode
- lower to ANF and resolved ANF
- infer analysis facts
- optimize supported typed strict ANF through the Egglog backend
- lower to Backend IR
- emit LLVM IR
- build native executables through `clang`
- execute native artifacts under mandatory wet tests

The native executable path supports checked signed `Int64` arithmetic,
checked division, conditionals, top-level first-order direct calls,
lambda-lifted non-capturing lambdas, and closure-converted local function
values where the program root is printable.

## Current Source Language

The current compiled source is the strict HeggLog `.hg` subset. It is not
Haskell 2010.

Implemented `.hg` source forms:

- `Int` and `Bool` literals
- variables
- nonrecursive `let`
- `if`
- integer `+`, `-`, `*`, and `/`
- integer `<`
- `==` over `Int` and `Bool`
- lambda expressions
- function application
- ordered nonrecursive top-level first-order definitions
- optional lambda parameter annotations when monomorphic inference is concrete
- local higher-order functions through closure conversion

Not implemented in the current `.hg` language:

- Haskell 2010 layout
- modules and imports
- ADTs
- pattern matching
- type classes and instances
- Prelude/library surface
- IO `main`
- lazy semantics
- GHC extensions

## Haskell 2010 Target Status

Haskell 2010 compilation is the active roadmap. A Haskell2010 parser/layout
frontend now exists and produces an isolated source AST, and the renamer now
produces a unique-name resolved AST with lexical scopes, namespace separation,
import ambiguity checks, and fixity resolution. An isolated typed Core IR,
validator, free-variable pass, substitution pass, and pretty-printer now exist
and are unit-tested. A Core-0 Haskell typechecker/desugarer now emits
validating typed Core for the first `Int`/`Bool` subset. A Core-0 reference
evaluator now executes validating typed Core with lazy let/function argument
thunks, Bool case evaluation, erased type abstraction/application, checked
`Int` primitives, and structured runtime errors. An isolated STG-like IR,
validator, and pure heap evaluator now model the lazy runtime MVP with
updateable thunks, single-entry thunks, sharing, black-hole detection,
constructor case dispatch, and checked primitives. Core-to-STG lowering now
translates validating Core-0 modules into validating STG while erasing Core
type abstraction/application and preserving lazy semantics. The Haskell 2010
native path now emits LLVM for the first Core-0 `Int`/`Bool` subset using boxed
values, updateable and single-entry thunks, function closures, enter/apply,
Bool case dispatch, and checked primitive aborts, then uses the existing clang
toolchain path to produce native executables.

Current status:

- Haskell 2010 parser/layout: parsed and parser-tested
- Haskell 2010 renamer: implemented and unit-tested
- Haskell 2010 typed Core: implemented and unit-tested as an isolated IR
- Haskell 2010 Core-0 HM typechecker: implemented and unit-tested for the
  first `Int`/`Bool` subset
- Haskell source desugaring to typed Core: implemented and unit-tested for
  Core-0 functions, lambdas, application, `let`, `if`, Bool `case`, and
  primitive arithmetic/comparison
- Haskell 2010 Core-0 reference evaluator: implemented and unit-tested for
  arithmetic, polymorphic instantiation, Bool case, lazy lets/arguments, and
  division-by-zero reporting
- Haskell 2010 STG-like lazy IR/runtime MVP: implemented and unit-tested for
  validation, lazy lets/arguments, case demand, constructor dispatch, thunk
  sharing/update behavior, single-entry thunks, black-hole detection, and
  checked primitive errors
- Core-to-STG lowering: implemented and unit-tested for Core-0 arithmetic,
  polymorphic type erasure, Bool case, lazy lets/arguments, forced runtime
  errors, and curried partial application
- Haskell 2010 native executable path: implemented and wet-tested for Core-0
  arithmetic, polymorphic identity, lazy lets/arguments, Bool case, forced
  division-by-zero failure, and curried partial application
- Haskell 2010 conformance suite: planned

Progress is tracked in
[haskell2010-conformance-matrix.md](haskell2010-conformance-matrix.md).

## Carry-Forward Infrastructure

The current `.hg` compiler provides reusable compiler infrastructure for the
Haskell 2010 target:

- LLVM backend structure
- native executable toolchain integration through `clang`
- Backend IR validation patterns
- closure conversion infrastructure
- checked arithmetic/division runtime handling
- Egglog kernel
- current ANF Egglog backend as optimizer prototype
- provenance/debug tracing
- mandatory wet-test framework
- CI build/test/package checks

The future Haskell 2010 pipeline must keep these boundaries clean: the
Haskell2010 frontend emits typed Core, the Core Egglog adapter optimizes typed
Core, the STG/runtime layer implements laziness, and LLVM remains the native
machine-code path.

## Testing

Current tests include:

- parser, typechecker, interpreter, ANF, optimizer, Egglog, backend, LLVM,
  golden, and property tests
- native executable tests in the normal Cabal suite
- `e2e-wet-test`, included in `cabal test all`, which invokes the built
  `hegglog` CLI, compiles real `.hg` files, executes native artifacts, verifies
  stdout/stderr/exit codes, compares report-mode `Result: <value>` output, and
  compiles selected emitted LLVM through `clang`

Haskell 2010 wet tests will be added as Haskell 2010 features are implemented.
Those tests must compile `.hs` files to native executables and execute the
artifacts directly.
