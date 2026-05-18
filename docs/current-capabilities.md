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
and are unit-tested. A Haskell typechecker/desugarer now emits validating typed
Core for the current executable subset: `Int`, `Bool`, functions, lazy
lets/arguments, user `data` declarations, polymorphic constructors, constructor
cases, lazy constructor fields, nested constructor patterns, list and tuple
syntax/patterns/types, built-in `Maybe`, `Either`, `Ordering`, and generated
Core Prelude bindings for basic list/Bool functions. A Core
reference evaluator executes validating typed Core with erased type
abstraction/application, checked `Int` primitives, and structured runtime
errors. An isolated STG-like IR, validator, and pure heap evaluator now model
the lazy runtime MVP with updateable thunks, single-entry thunks, sharing,
black-hole detection, constructor case dispatch, constructor field binding,
list/tuple/Prelude constructor dispatch, and checked primitives. Core-to-STG
lowering now translates validating Core modules
into validating STG while preserving lazy semantics. The Haskell 2010 native
path now emits LLVM for the current executable subset using boxed values,
updateable and single-entry thunks, function closures, enter/apply, Bool,
user-constructor, list, tuple, `Maybe`/`Either`/`Ordering` case dispatch,
boxed constructor field arrays, and checked primitive aborts, then uses the
existing clang toolchain path to produce native executables. The Haskell 2010
native path now runs an Egglog Core optimizer by
default for safe typed Core fragments before STG lowering; `--no-egglog`
disables that optimizer for comparison and debugging.

Current status:

- Haskell 2010 parser/layout: parsed and parser-tested
- Haskell 2010 renamer: implemented and unit-tested
- Haskell 2010 typed Core: implemented and unit-tested as an isolated IR
- Haskell 2010 HM typechecker: implemented and unit-tested for the first
  executable subset, including custom ADTs, polymorphic constructors, lists,
  tuples, and built-in Prelude data constructors
- Haskell source desugaring to typed Core: implemented and unit-tested for
  functions, lambdas, application, `let`, `if`, Bool/user-constructor `case`,
  nested/list/tuple constructor patterns, list/tuple expressions, short-circuit
  Bool operators, generated Prelude list functions, and primitive
  arithmetic/comparison
- Haskell 2010 Core reference evaluator: implemented and unit-tested for
  arithmetic, polymorphic instantiation, Bool and user ADT cases, lazy
  lets/arguments, lazy constructor fields, Prelude list functions, tuple and
  built-in Prelude constructor cases, short-circuit Bool operators, and
  division-by-zero reporting
- Haskell 2010 STG-like lazy IR/runtime MVP: implemented and unit-tested for
  validation, lazy lets/arguments, case demand, constructor dispatch, thunk
  sharing/update behavior, single-entry thunks, black-hole detection, and
  checked primitive errors
- Core-to-STG lowering: implemented and unit-tested for Core-0 arithmetic,
  polymorphic type erasure, Bool/user ADT case, nested constructor patterns,
  list/tuple/Prelude constructor cases, generated Prelude list functions, lazy
  lets/arguments, forced runtime errors, and curried partial application
- Haskell 2010 native executable path: implemented and wet-tested for
  arithmetic, polymorphic identity, lazy lets/arguments, Bool case, custom ADTs,
  `Maybe`, built-in `Maybe`/`Either`/`Ordering`, lists, tuples, Prelude list
  functions, short-circuit Bool operators, nested constructor patterns, lazy
  constructor fields, forced division-by-zero failure, and curried partial
  application
- Haskell 2010 Egglog Core optimizer: implemented and unit/wet-tested for
  safe Core-0 arithmetic identities, checked constant folding, known Bool case
  selection, typed Core extraction/validation, provenance reporting, lazy
  let preservation, strict bottom preservation, and optimized/unoptimized
  native agreement
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
  `hegglog` CLI, compiles real `.hg` and executable-subset `.hs` files,
  executes native artifacts, verifies stdout/stderr/exit codes, compares
  report-mode `Result: <value>` output, runs Haskell 2010 default Egglog and
  `--no-egglog` native cases including ADT, list, tuple, and Prelude programs,
  and compiles selected emitted LLVM through `clang`

Future Haskell 2010 wet tests should extend this direct executable coverage as
remaining pattern forms, recursion, type classes, and IO are implemented.
