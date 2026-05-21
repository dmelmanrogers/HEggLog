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
calls, superclass dictionary fields/projection, default class methods,
derived `Eq`/`Ord`/`Show` dictionaries for supported data/newtype declarations including
parameterized, recursive, `String`-field, and list-backed cases,
overlapping-instance rejection, structured placeholder diagnostics for remaining unsupported constraint contexts,
source-spanned typecheck diagnostics including delayed dictionary failures,
documented nullary-binding monomorphism/defaulting behavior, boxed `Char`
literals and literal cases, scalar `main :: Char` output, and built-in
`Eq Int`, `Eq Bool`, `Eq Char`, structural `Eq [a]`, `Ord Int`, `Ord Bool`, `Ord Char`, structural `Ord [a]`, and executable `Num Int`
class methods, plus guarded RHSs, guarded case alternatives, as-pattern
aliases, and guard-fallthrough no-match behavior, plus the first IO printing/input
slice for `IO`, `main :: IO ()`,
`putStrLn`, `getLine`, `print`, and higher-kinded `Monad` dictionaries for
`IO`, `Maybe`, and lists, including `return`, `(>>)`, `(>>=)`, `fail`, generic
expression and bind-statement `do` sequencing, and refutable do-bind failure, and
built-in `Show Int`/`Show Bool`/`Show Char`/`Show String` plus generated
structural list `Show` dictionaries, plus executable arithmetic sequences over
`Int` and `Char` ranges, public `Enum Int`/`Enum Char` and
`Bounded Int`/`Bounded Char`/`Bounded Bool` dictionaries, plus executable list comprehensions with generator
scoping, Bool guards, `let` qualifiers, nested generators, and refutable
pattern filtering. A Core
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
executes `main :: IO ()` actions for `putStrLn`, `getLine`, and `print` using
list-of-`Char` traversal, built-in scalar/string `Show` results represented as
lists, generated list `Show` dictionaries, Monad-backed do-bind result values,
explicit `(>>=)`, `failIO#` aborts for IO fail paths, and a compatibility path
for legacy internal string payloads. Dedicated
native wet tests now cover direct string output, list operations over strings,
show-produced strings, explicit `Char` cons patterns, and string literal
patterns, plus `Int`/`Char` arithmetic sequences, list comprehensions, and
Monad IO/Maybe/list do-notation in both default and `--no-egglog` modes.
Static `foreign import ccall` declarations now lower through Core/STG foreign
IR to native LLVM external declarations and direct calls for the supported
scalar and pointer ABI slice: boxed `Int`/`Bool`/`Char`, boxed `Ptr`/`FunPtr`,
static `&symbol` data and function addresses, signed and unsigned integer C ABI
declarations, checked integer marshalling, pointer arguments/results, and
result-carrying `IO` sequencing. `dynamic` imports now lower to indirect
`FunPtr` calls, and `wrapper` imports now generate C-callable callback
trampolines backed by process-lifetime closure slots. `foreign export ccall`
declarations now lower to C-callable native LLVM entrypoints for the supported
scalar/pointer ABI slice; entrypoints allocate the module closure graph, box C
arguments, enter the exported Haskell closure, force pure or `IO` results, and
marshal results back to C. Native wet tests link generated LLVM against C
helper files and check side-effect ordering, pointer mutation, indirect
function-pointer calls, Haskell callbacks re-entering boxed closures, and C
helpers calling exported Haskell entrypoints. Explicit `StablePtr` ownership
and manual `ForeignPtr` finalizer APIs are implemented with native wet coverage:
stable pointers can be created, dereferenced, cast to raw pointers, cast back,
and explicitly freed, while foreign pointers own raw addresses, accept bounded
process-lifetime finalizer lists, support `withForeignPtr`, and finalize
idempotently. Floating-point marshalling, broader link metadata, automatic GC
finalizer scheduling, `freeHaskellFunPtr`/callback-slot reclamation, and richer
`Foreign.*` marshalling modules remain later FFI work.
Multi-module Haskell 2010 compilation now also follows the Report's special
instance import/export rule for the executable source-instance subset:
instances move across empty export lists, empty import lists, and transitive
import chains independently of ordinary name filtering.
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
are represented as explicit failing or unsupported-documented fixtures. `Read`
is a documented Prelude/typeclass deviation: `Read` constraints are recognized
only far enough to fail explicitly as unsupported until the compiler has
coherent `ReadS`, lexical read parsing, standard instances, and derived `Read`
support.

Current status:

- Haskell 2010 parser/layout: parsed and parser-tested
- Haskell 2010 renamer: implemented and unit-tested, including module graph
  imports/exports, aliases, hiding, qualified imports, and Haskell 2010
  implicit Prelude insertion with explicit Prelude import suppression through
  the generated `Haskell2010.StandardLibrary` `Prelude` interface, plus
  source instance propagation through module interfaces
- Haskell 2010 typed Core: implemented and unit-tested as an isolated IR
- Haskell 2010 HM typechecker: implemented and unit-tested for the first
  executable subset, including custom ADTs, polymorphic constructors, recursive
  binding groups, lists, tuples, and built-in Prelude data constructors
- Haskell source desugaring to typed Core: implemented and unit-tested for
  functions, lambdas, application, `let`, `if`, Bool/user-constructor `case`,
  nested/list/tuple constructor patterns, list/tuple expressions, short-circuit
  Bool operators, generated Prelude list functions including `(++)`, primitive `/`, boxed
  `Char` literals and literal cases, and dictionary-backed `Eq`/`Ord`/`Num`
  methods, guarded RHSs, guarded case
  alternatives, and as-pattern aliases, including singleton self-recursive bindings and
  mutually recursive top-level groups, user-defined single-parameter classes,
  concrete instances, structured explicit constraints, placeholder diagnostics
  for remaining unsupported constraint contexts, superclass dictionaries,
  default class methods, overlapping-instance rejection, dictionary constructors/selectors,
  dictionary-passed method calls, and built-in `Eq Int`, `Eq Bool`, `Eq Char`,
  `Ord Int`, `Ord Bool`, `Ord Char`, structural list `Ord`, derived `Eq`/`Ord`/`Show`,
  `Num Int`, `Show Int`, `Show Bool`, `Show Char`,
  `Show String`, structural list `Show`, `Enum Int`, `Enum Char`,
  `Bounded Int`, `Bounded Char`, `Bounded Bool`, and higher-kinded `Monad`
  dictionaries for `IO`, `Maybe`, and lists, plus source-spanned Haskell 2010
  typecheck diagnostics, plus `putStrLn`, `getLine`, `print`, `return`,
  `(>>)`, `(>>=)`, `fail`, and generic expression/bind-statement
  `do` sequencing, plus executable `Int`/`Char` arithmetic sequences and list
  comprehensions
- Haskell 2010 Core reference evaluator: implemented and unit-tested for
  arithmetic, polymorphic instantiation, Bool and user ADT cases, lazy
  lets/arguments, lazy constructor fields, Prelude list functions including `(++)`, tuple and
  built-in Prelude constructor cases, short-circuit Bool operators, and
  guarded self recursion, local factorial recursion, top-level fibonacci
  recursion, mutual recursion, recursive list functions, recursive pattern
  bindings, user class dictionary
  calls, built-in `Eq`/`Ord`/`Num`/`Enum`/`Bounded`/`Monad` dictionary calls, `Char` literals and
  literal cases, arithmetic sequences, list comprehensions, guarded RHS/as-pattern programs, IO output actions, empty-stdin `getLine` oracle behavior, Monad `fail`, guard
  fallthrough no-match reporting, and division-by-zero reporting
- Haskell 2010 STG-like lazy IR/runtime MVP: implemented and unit-tested for
  validation, lazy lets/arguments, case demand, constructor dispatch, thunk
  sharing/update behavior, single-entry thunks, black-hole detection, and
  checked primitive errors, including single-entry IO thunks so repeated IO
  actions re-execute effects instead of sharing cached results
- Core-to-STG lowering: implemented and unit-tested for Core-0 arithmetic,
  polymorphic type erasure, Bool/user ADT case, nested constructor patterns,
  list/tuple/Prelude constructor cases, generated Prelude list functions including `(++)`, lazy
  lets/arguments, recursive binding groups, `Char` literal cases and equality,
  forced runtime errors, and curried partial application, plus guarded
  RHS/as-pattern semantics and guard fallthrough errors
- Haskell 2010 native executable path: implemented and wet-tested for
  arithmetic, polymorphic identity, lazy lets/arguments, Bool case, custom ADTs,
  `Maybe`, built-in `Maybe`/`Either`/`Ordering`, lists, tuples, Prelude list
  functions including `(++)`, short-circuit Bool operators, nested constructor patterns, lazy
  constructor fields, top-level/local/mutual/list recursion, forced
  division-by-zero failure, curried partial application, user-defined type
  class dictionary calls, built-in `Eq`/`Ord`/`Num` class dictionary calls,
  `Eq Char`, public `Enum`/`Bounded` examples, `Char` literal cases, scalar `main :: Char` printing, guarded
  RHS/as-pattern programs, `main :: IO ()` printing through `putStrLn`,
  `print`, native `getLine` over stdin, Monad-backed do-bind statements,
  refutable do-bind `fail`, and explicit `(>>=)`, process-lifetime runtime allocation, and guard-fallthrough runtime
  failure, plus executable `Int`/`Char` arithmetic sequences, list comprehensions,
  implicit, explicit, and qualified Prelude import programs, and hidden
  transitive source-instance provider programs
- Haskell 2010 Egglog Core optimizer: implemented and unit/wet-tested for
  safe Core-0 arithmetic identities, checked constant folding, known Bool case
  selection, known literal and saturated known-constructor case/projection
  rewrites, typed Core extraction/validation, selected-Core validation,
  provenance reporting, lazy let preservation, lazy constructor-field
  preservation, strict bottom preservation, and optimized/unoptimized native
  agreement
- Haskell 2010 conformance suite: implemented as
  `haskell2010-conformance-test`; it contains 103 manifest-tracked fixtures with
  72 native-success cases, 3 native-runtime-error cases, 22 compile-error cases,
  and 6 unsupported-documented cases
- Haskell 2010 standard library layout: implemented for the current executable
  subset as a generated/importable `Prelude` module interface; broader standard
  modules remain reserved and documented in
  [haskell2010-standard-library-layout.md](haskell2010-standard-library-layout.md)

Progress is tracked in
[haskell2010-conformance-matrix.md](haskell2010-conformance-matrix.md).

## Current Next Focus

The next coherent chunk is Prelude, deriving, and typeclass library completion.
SURFACE-001 completed the current source-surface audit and matrix
reconciliation, SURFACE-002 completed user-defined operator bindings and infix
calls, SURFACE-003 completed line-broken `where` layout coverage, DIAG-009
completed supported-subset pattern-match diagnostics, TEST-CONF-013 completed
source-surface negative fixtures, TEST-CONF-014 completed machine-checked
source matrix closure, and ADT-007 completed record
update expressions.

The following coherent chunk is Prelude, deriving, and typeclass library
completion: TC-029, TC-030, TC-031, TC-032, TC-033, PRELUDE-009,
PRELUDE-019, PRELUDE-020, and TEST-CONF-015. Remaining FFI closure is tracked
separately by FFI-010 through FFI-013.

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
  programs, user-defined type class dictionary programs, derived `Eq`/`Ord`/`Show`
  programs, and built-in `Eq`/`Ord`/`Num`/`Show`/`Enum`/`Bounded` dictionary programs, numeric-defaulting and
  monomorphism/defaulting decision programs, multi-file module programs,
  implicit, explicit, and qualified Prelude import programs,
  known-constructor optimizer programs, plus line-oriented IO
  printing/input programs, and compiles selected emitted LLVM through `clang`
- `haskell2010-conformance-test`, included in `cabal test all`, which reads the
  JSON conformance manifest, invokes the built `hegglog` executable as a
  subprocess, compiles native-success cases to actual executables, executes
  those artifacts directly, compares stdout exactly, verifies runtime-error
  cases exit nonzero, verifies compile-error diagnostics, and ensures
  unsupported-documented cases fail explicitly rather than silently passing

Future Haskell 2010 conformance work should extend this direct executable
coverage as report-complete pattern coverage/runtime attribution,
the report-compatible `showsPrec`/`showList` hierarchy, exhaustive Unicode/string escape fidelity,
additional string library behavior, and broader IO are implemented. Source-spanned
non-exhaustive and redundant pattern warnings are already exposed through the
Haskell 2010 typechecker, native compilation result APIs, and compile CLI.
