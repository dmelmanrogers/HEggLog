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
Core Prelude bindings for basic list/Bool functions, plus recursive top-level
and local functions, plus the initial type class dictionary slice for
user-defined single-parameter classes, concrete instances, explicit source
constraints with normalized argument representation, dictionary-passed method
calls, structured placeholder diagnostics for unsupported constraint contexts,
source-spanned typecheck diagnostics including delayed dictionary failures,
documented nullary-binding monomorphism/defaulting behavior, boxed `Char`
literals and literal cases, scalar `main :: Char` output, and built-in
`Eq Int`, `Eq Bool`, `Eq Char`, `Ord Int`, `Ord Bool`, and executable `Num Int`
class methods, plus guarded RHSs, guarded case alternatives, as-pattern
aliases, and guard-fallthrough no-match behavior, plus the first IO printing
slice for `IO`, `main :: IO ()`,
`putStrLn`, `print`, `return`, `(>>)`, `(>>=)`, expression and bind-statement
`do` sequencing, and
built-in `Show Int`/`Show Bool`/`Show Char`/`Show String` plus generated
structural list `Show` dictionaries. A Core
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
boxed constructor field arrays, process-lifetime heap allocation through
`hegglog_hs_alloc_process_lifetime` under the documented no-free/no-GC
ownership policy, boxed `Char` values, `Eq Char` primitive lowering, scalar
`Char` root printing, source `String` literals as ordinary list-of-`Char`
constructor values, and checked primitive aborts, then uses the existing clang
toolchain path to produce native executables. The Haskell 2010 native path also
executes `main :: IO ()` actions for `putStrLn` and `print` output using
list-of-`Char` traversal, built-in scalar/string `Show` results represented as
lists, generated list `Show` dictionaries, do-bind result values, explicit
`(>>=)`, and a compatibility path for legacy internal string payloads. Dedicated
native wet tests now cover direct string output, list operations over strings,
show-produced strings, explicit `Char` cons patterns, and string literal
patterns in both default and `--no-egglog` modes.
The Haskell 2010
native path now runs an Egglog Core optimizer by
default for safe typed Core fragments before STG lowering; `--no-egglog`
disables that optimizer for comparison and debugging. The optimizer covers
safe Core-0 `Int`/`Bool` fragments plus known literal and saturated
known-constructor case/projection rewrites for ADT/list/tuple/dictionary-shaped
Core while preserving lazy constructor fields and forced bottom behavior.
Haskell 2010 conformance is now tracked by a dedicated mandatory suite backed
by `test/haskell2010/conformance/manifest.json`; the current compiler passes
the documented executable-subset cases, while incomplete Haskell 2010 features
are represented as explicit failing or unsupported-documented fixtures.

Current status:

- Haskell 2010 parser/layout: parsed and parser-tested
- Haskell 2010 renamer: implemented and unit-tested
- Haskell 2010 typed Core: implemented and unit-tested as an isolated IR
- Haskell 2010 HM typechecker: implemented and unit-tested for the first
  executable subset, including custom ADTs, polymorphic constructors, recursive
  binding groups, lists, tuples, and built-in Prelude data constructors
- Haskell source desugaring to typed Core: implemented and unit-tested for
  functions, lambdas, application, `let`, `if`, Bool/user-constructor `case`,
  nested/list/tuple constructor patterns, list/tuple expressions, short-circuit
  Bool operators, generated Prelude list functions, primitive `/`, boxed
  `Char` literals and literal cases, and dictionary-backed `Eq`/`Ord`/`Num`
  methods, guarded RHSs, guarded case
  alternatives, and as-pattern aliases, including singleton self-recursive bindings and
  mutually recursive top-level groups, user-defined single-parameter classes,
  concrete instances, structured explicit constraints, placeholder diagnostics
  for unsupported constraint contexts, dictionary constructors/selectors,
  dictionary-passed method calls, and built-in `Eq Int`, `Eq Bool`, `Eq Char`,
  `Ord Int`, `Ord Bool`, `Num Int`, `Show Int`, `Show Bool`, `Show Char`,
  `Show String`, and structural list `Show` dictionaries, plus
  source-spanned Haskell 2010 typecheck diagnostics, plus
  `putStrLn`, `print`, `return`, `(>>)`, `(>>=)`, and expression/bind-statement
  `do` sequencing
- Haskell 2010 Core reference evaluator: implemented and unit-tested for
  arithmetic, polymorphic instantiation, Bool and user ADT cases, lazy
  lets/arguments, lazy constructor fields, Prelude list functions, tuple and
  built-in Prelude constructor cases, short-circuit Bool operators, and
  guarded self recursion, local factorial recursion, top-level fibonacci
  recursion, mutual recursion, recursive list functions, recursive pattern
  bindings, user class dictionary
  calls, built-in `Eq`/`Ord`/`Num` dictionary calls, `Char` literals and
  literal cases, guarded RHS/as-pattern programs, IO output actions, guard
  fallthrough no-match reporting, and division-by-zero reporting
- Haskell 2010 STG-like lazy IR/runtime MVP: implemented and unit-tested for
  validation, lazy lets/arguments, case demand, constructor dispatch, thunk
  sharing/update behavior, single-entry thunks, black-hole detection, and
  checked primitive errors
- Core-to-STG lowering: implemented and unit-tested for Core-0 arithmetic,
  polymorphic type erasure, Bool/user ADT case, nested constructor patterns,
  list/tuple/Prelude constructor cases, generated Prelude list functions, lazy
  lets/arguments, recursive binding groups, `Char` literal cases and equality,
  forced runtime errors, and curried partial application, plus guarded
  RHS/as-pattern semantics and guard fallthrough errors
- Haskell 2010 native executable path: implemented and wet-tested for
  arithmetic, polymorphic identity, lazy lets/arguments, Bool case, custom ADTs,
  `Maybe`, built-in `Maybe`/`Either`/`Ordering`, lists, tuples, Prelude list
  functions, short-circuit Bool operators, nested constructor patterns, lazy
  constructor fields, top-level/local/mutual/list recursion, forced
  division-by-zero failure, curried partial application, user-defined type
  class dictionary calls, built-in `Eq`/`Ord`/`Num` class dictionary calls,
  `Eq Char`, `Char` literal cases, scalar `main :: Char` printing, guarded
  RHS/as-pattern programs, `main :: IO ()` printing through `putStrLn`,
  `print`, do-bind statements, and explicit `(>>=)`, process-lifetime runtime allocation, and guard-fallthrough runtime
  failure
- Haskell 2010 Egglog Core optimizer: implemented and unit/wet-tested for
  safe Core-0 arithmetic identities, checked constant folding, known Bool case
  selection, known literal and saturated known-constructor case/projection
  rewrites, typed Core extraction/validation, selected-Core validation,
  provenance reporting, lazy let preservation, lazy constructor-field
  preservation, strict bottom preservation, and optimized/unoptimized native
  agreement
- Haskell 2010 conformance suite: implemented as
  `haskell2010-conformance-test`; it contains 55 manifest-tracked fixtures with
  41 native-success cases, 1 native-runtime-error case, 6 compile-error cases,
  and 7 unsupported-documented cases

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
  `--no-egglog` native cases including ADT, list, tuple, Prelude, recursive
  programs, user-defined type class dictionary programs, and built-in
  `Eq`/`Ord`/`Num`/`Show` dictionary programs, numeric-defaulting and
  monomorphism/defaulting decision programs, multi-file module programs,
  known-constructor optimizer programs, plus IO
  printing programs, and compiles selected emitted LLVM through `clang`
- `haskell2010-conformance-test`, included in `cabal test all`, which reads the
  JSON conformance manifest, invokes the built `hegglog` executable as a
  subprocess, compiles native-success cases to actual executables, executes
  those artifacts directly, compares stdout exactly, verifies runtime-error
  cases exit nonzero, verifies compile-error diagnostics, and ensures
  unsupported-documented cases fail explicitly rather than silently passing

Future Haskell 2010 conformance work should extend this direct executable
coverage as the full pattern coverage checker, richer pattern diagnostics,
derived/user ADT-shaped `Show`, exhaustive Unicode/string escape fidelity,
additional string library behavior, and broader IO are implemented. Structured exhaustiveness
warning placeholders are already exposed through the Haskell 2010 typechecker
and native compilation result APIs.
