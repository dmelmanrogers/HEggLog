# HeggLog Roadmap: Haskell 2010 Native Compiler

## Project Goal

HeggLog is a Haskell 2010 native-code compiler project implemented in Haskell.
The compiler's active target is Haskell 2010 source code compiled to real
native machine-code executables through LLVM and clang.

The current `.hg` compiler is the backend and middle-end substrate, the
regression baseline, and the existing proof that native executable output,
Egglog optimization, closure conversion infrastructure, LLVM lowering, and
end-to-end wet testing work. It is not the final source language endpoint. The
Haskell 2010 path now compiles the documented executable subset, while the
full Haskell 2010 surface remains roadmap work. Progress toward full
conformance is now measured by a mandatory manifest-backed Haskell 2010
conformance suite; passing representative executable-subset cases do not imply
complete Haskell 2010 support.

## Target Pipeline

```text
Haskell 2010 source
  -> layout-aware lexer/parser
  -> renamer
  -> typechecker
  -> desugarer
  -> typed Core
  -> Egglog Core optimizer
  -> STG-like lazy IR
  -> runtime system
  -> LLVM IR
  -> clang / LLVM toolchain
  -> native machine-code executable
```

## Output Criterion

The primary success criterion is:

```bash
hegglog compile Main.hs -o main
./main
```

The executable must behave according to the implemented Haskell 2010 semantics.

## Engineering Backlog

The detailed task backlog is maintained in
[haskell2010-todo.md](haskell2010-todo.md). The roadmap defines milestones; the
to-do document defines executable engineering tasks with stable IDs,
dependencies, acceptance criteria, tests, documentation requirements, a
machine-readable JSON mirror, and validation through
`scripts/validate-haskell2010-todo.py`.

## Completed Compiler Substrate

Implemented and tested today for the current `.hg` compiler-supported subset:

- strict `.hg` source frontend
- parser, typechecker, and interpreter
- ANF and resolved ANF
- Egglog backend for supported ANF fragments
- checked signed `Int64` semantics
- lambda lifting and closure conversion for currently supported local functions
- Backend IR
- LLVM IR generation
- native executable output through `clang`
- mandatory end-to-end wet testing of native executable artifacts
- CI build/test/package checks and wet-test execution

These are carry-forward compiler assets. They are not Haskell 2010 frontend
capabilities until a Haskell 2010 parser, renamer, typechecker, desugarer, lazy
runtime, and conformance tests exist.

## Phased Haskell 2010 Compiler Roadmap

### Phase 0 - Lock Existing Compiler Substrate

Deliverables:

- preserve current `.hg` compiler path
- preserve native executable output
- preserve Egglog backend
- preserve wet tests
- document current strict frontend as substrate

Acceptance criteria:

- `cabal build all` passes
- `cabal test all` passes
- `cabal check` passes
- wet tests pass
- current examples still work

### Phase 1 - Haskell 2010 Conformance Matrix

Deliverables:

- `docs/haskell2010-conformance-matrix.md`
- `docs/haskell2010-implementation-plan.md`
- `docs/haskell2010-frontend-spec.md`

Acceptance criteria:

- every major Haskell 2010 feature area is represented
- every feature has a status
- no feature is marked complete without tests

### Phase 2 - Haskell 2010 Lexer, Layout, and Parser

Deliverables:

- layout-aware lexer/parser
- module headers, imports, and top-level declarations
- type signatures, function bindings, and pattern bindings
- lambdas, application, infix operators, `if`, `case`, `let`, `where`, and
  parsed `do` notation
- list syntax, tuple syntax, sections, guards, and patterns
- parsed `data`, `newtype`, `type`, `class`, and `instance` declarations

Acceptance criteria:

- layout-sensitive parser tests
- malformed layout errors
- debug renderer or pretty-printer
- existing `.hg` parser still works

### Phase 3 - Renamer and Name Resolution

Deliverables:

- unique names
- lexical, top-level, local, `let`/`where`/lambda/pattern scopes
- constructor, type, class, and module namespaces
- duplicate binding errors
- unbound name errors
- fixity resolution

Acceptance criteria:

- every variable occurrence resolves to a unique binder or fails
- tests cover shadowing, duplicate names, unbound names, fixity, and pattern
  scope

### Phase 4 - Haskell Core IR

Deliverables:

- typed Core syntax, Core types, Core validator, Core pretty-printer
- free-variable and substitution utilities
- constructs: `Var`, `Lit`, `Lam`, `App`, `Let`, `LetRec`, `Case`,
  `Constructor`, `PrimOp`, and type annotations/metadata

Acceptance criteria:

- generated Core validates
- all binders are unique
- all variables are resolved
- primitive operations are typed
- constructors are arity-checked
- case alternatives are type-consistent

### Phase 5 - Haskell Typechecker, Core-0

Deliverables:

- Hindley-Milner inference
- unification, occurs check, generalization, and instantiation
- explicit type signatures
- Core generation
- Core-0: `Int`, `Bool`, functions, top-level definitions, lambdas,
  application, `let`/`letrec`, `if`, case over `Bool`, and primitive
  arithmetic/comparison

Acceptance criteria:

- `id :: a -> a` typechecks
- `const :: a -> b -> a` typechecks
- polymorphic let works
- ill-typed programs fail with spans
- generated Core validates

### Phase 6 - Lazy Semantics and STG-like IR

Deliverables:

- STG-like IR for functions, thunks, constructors, case expressions,
  `let`/`letrec`, updateable thunks, and primitive operations
- semantics where function arguments are lazy unless forced, case forces its
  scrutinee, let binds thunks, letrec supports recursive heap bindings,
  constructors are values, and primitive operations force operands

Required tests:

- `const 1 (1 \`div\` 0)` evaluates to `1`
- `let x = 1 \`div\` 0 in 5` evaluates to `5`
- `case (1 \`div\` 0) of ...` errors

Acceptance criteria:

- STG validates
- Core lowers to STG
- lazy semantics tests pass in interpreter and native executable path
- strict `.hg` pipeline remains isolated

### Phase 7 - Runtime System v1

Deliverables:

- runtime source files
- closure headers, function closures, thunk closures, constructor closures,
  indirection/update closures, and black-hole marker
- allocation, enter/force/update operations
- checked arithmetic/division runtime errors

Acceptance criteria:

- runtime builds and links with generated LLVM
- thunks are shared after evaluation
- runtime errors exit nonzero
- black-hole behavior is implemented or explicitly documented
- native wet tests pass

### Phase 8 - LLVM Backend for Lazy STG

Deliverables:

- STG-to-LLVM lowering
- runtime linking
- closure allocation lowering
- enter/apply convention
- constructor tag dispatch
- case lowering
- primitive lowering

Acceptance criteria:

- `hegglog compile Main.hs -o main` produces a native executable for Core-0
  lazy programs
- generated executable links runtime
- lazy semantic wet tests pass

### Phase 9 - ADTs and Pattern Matching

Status: the first executable ADT slice is implemented. `data` declarations now
feed constructor metadata into Core/STG/native compilation; value constructors,
nullary and unary/multi-field constructor applications, case alternatives,
variable patterns, wildcard patterns, literal patterns, nested constructor
patterns, tuple patterns, and list patterns are covered by Core, STG, native,
and wet tests. Guarded RHSs, guarded case alternatives, as-pattern aliases, and
guard-fallthrough no-match behavior are also implemented and wet-tested.
Irrefutable/lazy pattern semantics and richer source-spanned pattern diagnostics
remain later work.

Deliverables:

- data declarations and constructors
- constructor, literal, variable, wildcard, nested, tuple, list, and as-patterns
- guards
- pattern-match compiler to Core case

Acceptance criteria:

- `Maybe`, `Either`, and custom ADTs compile
- nested patterns compile
- pattern-bound names scope correctly
- native wet tests cover ADTs, nested patterns, guards, as-patterns, and guard
  fallthrough

### Phase 10 - Lists, Tuples, and Prelude Core

Status: implemented for the supported executable subset. The typechecker,
Core validator/evaluator, STG lowering/evaluator, native LLVM path, and wet
tests now cover built-in list, tuple, unit, `Maybe`, `Either`, and `Ordering`
constructors; list and tuple expressions/patterns/types; short-circuiting
`&&`/`||`; and generated Core bindings for `id`, `const`, `not`, `otherwise`,
`map`, `foldr`, `length`, `filter`, and `reverse`.

Deliverables:

- unit, tuples, lists, `Maybe`, `Either`, `Bool`, and `Ordering`
- basic Prelude functions
- boolean short-circuit semantics

Acceptance criteria:

- list programs compile
- tuple programs compile
- `map`, `foldr`, `length`, `filter`, and `reverse` examples compile
- wet tests cover list recursion and tuple destructuring

### Phase 11 - Recursion

Status: implemented for the supported executable subset. Singleton
self-recursive top-level and local bindings now emit recursive Core groups,
mutual binding groups remain recursive, cons patterns parse as constructor
patterns, and factorial, fibonacci, mutual recursion, guarded self recursion,
and recursive list functions are covered by Core, STG, native, and wet tests.
Nontermination remains isolated to the existing black-hole/runtime tests.

Deliverables:

- recursive top-level functions
- mutually recursive bindings
- recursive local `let`/`where`
- recursive closures/thunks

Acceptance criteria:

- factorial compiles
- fibonacci compiles
- recursive list functions compile
- nontermination tests are isolated from the normal test suite

### Phase 12 - Type Classes and Dictionary Passing

Status: dictionary representation is implemented for user-defined
single-parameter classes with concrete, context-free instances and for the
first built-in Prelude class slice. Class methods elaborate to selector
functions, instance declarations emit dictionary values, constrained source
functions receive explicit Core dictionary arguments, dictionary values lower
through STG as ordinary constructor/function values, and native wet tests cover
default Egglog and `--no-egglog` execution.
Class constraints are now represented explicitly as a class head plus ordered
argument list; the current executable slice checks the single-argument arity,
normalizes constraint arguments through type synonym expansion, and then feeds
the normalized constraints to defaulting and dictionary elaboration.

The built-in executable Prelude class slice now supports `Eq Int`, `Eq Bool`,
`Ord Int`, `Ord Bool`, `Num Int`, `Show Int`, and `Show Bool`: `(==)`, `(/=)`,
`compare`, `(<)`, `(<=)`, `(>)`, `(>=)`, `max`, `min`, `(+)`, `(-)`, `(*)`,
`negate`, `abs`, `signum`, `fromInteger`, and `show` lower through generated
dictionaries and selectors. Integer literals elaborate through `fromInteger`,
ambiguous numeric constraints default to the executable `Int` type, and binding
groups are dependency-sorted before generalization so helper functions can be
specialized by later bindings. `/` remains the existing checked `Int` division
primitive rather than a `Fractional` method.
Remaining Phase 12 work includes superclasses, default methods, instance
contexts, method-specific constraints/type variables, coherence diagnostics,
deriving, broader `Show` instances, and additional numeric classes.

Deliverables:

- class declarations, instance declarations, constraints, and superclasses
- method lookup, dictionary passing, default methods, and basic deriving
- initial `Eq`, `Ord`, `Show`, and `Num` support

Acceptance criteria:

- `Eq` and `Ord` methods work for supported built-in instances
- executable `Num Int` methods work through dictionaries
- `Show` works enough for print
- overloaded numeric literals work for supported numeric types
- initial dictionary-passing Core validates for user-defined classes
- native wet tests cover user-defined and built-in typeclass calls

### Phase 13 - IO and `main`

Status: the first IO printing slice is implemented for the executable subset.
The typechecker recognizes `IO`, `main :: IO ()`, `putStrLn`, `print`,
`return`, `(>>)`, and expression-only `do` sequencing with local `let`.
Core/STG reference evaluators model IO output for oracle tests, and the native
entrypoint executes `IO ()` actions instead of scalar root printing. Native
string literal objects, list-of-`Char` traversal, `Show Int`, and `Show Bool`
support `putStrLn` and `print` through default/no-egglog wet tests. `<-`
binding, `(>>=)`, real-world IO handles, and broader Prelude IO remain planned.

Deliverables:

- `main :: IO ()`
- `print`, `putStrLn`, and do-notation desugaring
- representation for `return`, `(>>=)`, and `(>>)`

Acceptance criteria:

- `main = print 42` compiles and runs
- `main = putStrLn "hello"` compiles and runs
- do notation compiles
- native executable entrypoint uses Haskell `main`

### Phase 14 - Modules and Whole-Program Compilation

Status: completed for the current executable subset. The compiler now loads
same-directory dependency files from source import declarations, detects module
cycles and module-name mismatches, renames modules in dependency order against
actual exported definitions, enforces explicit export/import filtering
including `Thing(..)` children and hiding, supports qualified aliases, flattens
the renamed module graph into one typed Core program, and selects the root
module's `main` as the native entry point. Broader package search paths and a
full Prelude module remain later work.

Deliverables:

- module declarations, imports, exports, qualified imports, and hiding
- module graph and cycle detection
- whole-program compilation

Acceptance criteria:

- multiple `.hs` files compile together
- imports resolve
- export lists restrict visibility
- qualified names work
- native wet tests compile multi-module programs

### Phase 15 - Egglog Core Optimizer

Status: the first safe Core optimizer slices are implemented. It optimizes
typed `Int`/`Bool` Core fragments before STG lowering, extracts validating Core,
reports provenance, preserves laziness/bottom by skipping unsafe fragments, and
is checked against Core, STG, and optimized/unoptimized native execution. The
optimizer also folds known literal cases and saturated known-constructor cases
for ADT/list/tuple/dictionary-shaped Core, including constructor-field
projection with tests for unused lazy fields and forced field bottom. Broader
dictionary simplification, strictness, and full Core-native equality-saturation
facts remain part of the full Phase 15 expansion.

Deliverables:

- Core-to-Egglog schema, Core encoding, typed Core facts, Core rewrite rules,
  Core extraction, and provenance/explanations
- facts: `TypeOf`, `Total`, `NoError`, `NonZero`, `NoOverflow`, `KnownConst`,
  `KnownConstructor`, `Demand`, `StrictIn`, and `DictionaryKnown`
- optimizations: constant folding, case-of-known-constructor, constructor
  projection, dictionary simplification, safe arithmetic identities, boolean
  simplification respecting bottom, and guarded dead branch elimination

Acceptance criteria:

- Core optimizer preserves lazy semantics
- bottom/runtime-error behavior is preserved
- extraction produces valid typed Core
- optimized and unoptimized native wet tests agree
- provenance explains selected rewrites

### Phase 16 - Haskell 2010 Surface Completion

Deliverables:

- list comprehensions, arithmetic sequences, remaining where/declaration forms,
  and lazy pattern forms
- records if included
- `newtype`, type synonyms, deriving, and default declarations
- foreign declarations documented as implemented, deferred, or deviating

Acceptance criteria:

- conformance matrix reflects implementation
- parser/renamer/typechecker/desugarer tests cover all implemented surface
  features
- native wet tests cover representative programs

### Phase 17 - Diagnostics

Deliverables:

- source spans through frontend
- layout, renamer, typechecker, pattern-match, backend, and runtime diagnostics
- runtime source attribution where possible

Acceptance criteria:

- parse/name/type errors have spans
- runtime errors are useful
- wet tests include diagnostic category checks
- docs show examples

### Phase 18 - CLI Productization

Commands:

- `hegglog check Main.hs`
- `hegglog run Main.hs`
- `hegglog compile Main.hs -o main`
- `hegglog report Main.hs`
- `hegglog emit-core Main.hs`
- `hegglog emit-stg Main.hs`
- `hegglog emit-llvm Main.hs`

Flags:

- `--no-egglog`
- `--strict-egglog`
- `--keep-intermediates`
- `--dump-core`
- `--dump-stg`
- `--dump-optimized-core`

Acceptance criteria:

- stable command model
- correct stdout/stderr discipline
- correct exit codes
- CLI wet tests cover common workflows

### Phase 19 - Haskell 2010 Conformance Suite

Status: baseline implemented. The project now has
`test/haskell2010/conformance/manifest.json`, a structured corpus under
`test/haskell2010/conformance/`, and the mandatory
`haskell2010-conformance-test` Cabal suite. The baseline currently records 46
fixtures: 32 native-success cases, 1 native-runtime-error case, 5 compile-error
cases, and 8 unsupported-documented cases. The suite invokes the built
`hegglog` executable as a subprocess, compiles native-success cases to actual
executables, executes those artifacts directly, compares stdout exactly, checks
runtime-error exits, checks compile-error diagnostics, and fails if documented
unsupported cases silently pass.

Full Phase 19 remains open until the corpus covers every Haskell 2010 Report
feature area deeply enough to support a conformance claim. The current baseline
is a progress-measurement artifact for the implemented executable subset, not a
full Haskell 2010 certification.

Deliverables:

- conformance test corpus for layout, expressions, declarations, patterns,
  ADTs, class/instance behavior, modules, Prelude, IO, runtime/laziness
- structured manifest with expected status, expected stdout or diagnostic
  category, required compiler stage, and notes/deviations
- Cabal test-suite wiring so conformance runs under `cabal test all`

Acceptance criteria:

- every conformance matrix row links to tests or a documented deviation
- no undocumented failures
- unsupported features remain explicit conformance cases until implemented

### Phase 20 - Release Quality

Deliverables:

- CI matrix, LLVM/clang docs, runtime build integration, installation docs,
  examples gallery, docs index, standard library layout, formatting/linting,
  benchmark suite, and release checklist

Acceptance criteria:

- fresh checkout builds
- CI runs unit/property/golden/wet tests
- user can install and compile a Haskell 2010 subset program
- package metadata is clean

## Parallel Workstreams

- Frontend team: Haskell 2010 lexer, layout, parser, pretty-printer, and
  frontend diagnostics. Boundary: emits source AST only.
- Type system team: renamer, HM inference, constraints, type classes, and
  dictionary-passing design. Boundary: emits typed Core and diagnostics.
- Core/Egglog team: Core syntax, validation, facts, CoreEgglog adapter, rules,
  extraction, and provenance. Boundary: Egglog kernel remains frontend
  independent.
- Runtime/STG team: lazy STG-like IR, thunk/closure runtime, constructor
  representation, update/black-hole behavior, and runtime tests.
- Backend team: STG-to-LLVM lowering, runtime linking, native executable
  output, and target-specific validation.
- Testing team: conformance matrix, unit/property/golden tests, native wet
  tests, negative diagnostics, and CI coverage.
- Documentation team: roadmap, specs, status reports, examples, and documented
  deviations.

## Immediate Next Five Tasks

1. Remaining pattern diagnostics and irrefutable/lazy pattern semantics.
2. Haskell 2010 conformance matrix expansion for the broader executable
   surface.
3. Broader `Show`/`String` interoperability, including `Show Char`,
   `Show String`, escapes, and additional string/list library behavior.
4. Superclass, default method, and instance-context support for type classes.
5. Broader IO and Monad support, including `<-`, `(>>=)`, `fail`, and handles.

Completed immediate tasks:

- Commit roadmap pivot.
- Haskell 2010 parser/layout MVP.
- Haskell 2010 renamer MVP.
- Haskell 2010 typed Core MVP, including Core syntax, Core types, validator,
  pretty-printer, free-variable analysis, and capture-aware substitution.
- Haskell 2010 Core-0 typechecker/desugarer MVP, including explicit
  signatures, HM generalization/instantiation, source-to-Core generation, and
  generated-Core validation for the first `Int`/`Bool` subset.
- Haskell 2010 Core-0 reference evaluator, including lazy Core thunks,
  erased type abstraction/application, Bool case evaluation, checked `Int`
  primitive behavior, and structured runtime errors.
- Haskell 2010 lazy/STG runtime MVP, including STG validation, in-process heap
  evaluation, sharing, single-entry thunks, black-hole detection, Bool case
  dispatch, and checked primitive runtime errors.
- Haskell 2010 Core-to-STG lowering MVP, including validated Core-to-STG
  lowering, type erasure, curried function lowering, thunked operands, and STG
  evaluator preservation tests.
- Haskell 2010 native executable path for the first Core-0 slice, including
  boxed STG-to-LLVM lowering, closure allocation, enter/apply, thunk
  forcing/update, Bool case dispatch, checked primitive aborts, CLI `.hs`
  compile integration, and native wet tests.
- Haskell 2010 Egglog Core optimizer for safe typed Core-0 `Int`/`Bool`
  fragments, including checked constant folding, safe arithmetic identities,
  known Bool case selection, typed Core extraction/validation, provenance,
  `--no-egglog` comparison, Core/STG/native oracle tests, lazy let preservation,
  and strict bottom preservation.
- Haskell 2010 Egglog Core optimizer known-constructor expansion, including
  known literal case selection, saturated known-constructor case selection,
  constructor-field projection for ADT/list/tuple/dictionary-shaped Core,
  selected-Core validation, provenance, unused lazy-field preservation, forced
  field-bottom preservation, and optimized/unoptimized native agreement.
- Haskell 2010 Lazy/STG runtime MVP, including STG syntax, validation,
  function closures, updateable and single-entry thunk closures, constructor
  closures, `let`/`letrec`, case demand, thunk sharing, black-hole detection,
  Bool constructor dispatch, and checked primitive runtime errors.
- Haskell 2010 Core-to-STG lowering MVP, including validated Core-to-STG
  translation, Core type-erasure, unary curried function lowering, thunked
  non-atomic operands and intermediate applications, Bool case lowering, and
  STG evaluator preservation tests.
- Broader Haskell 2010 ADT and pattern-match Core support, including constructor
  metadata from `data` declarations, polymorphic constructors, lazy constructor
  fields, constructor-field case binding, nested constructor patterns, Core/STG
  validation, boxed native constructor objects, and default/no-egglog native wet
  tests for custom ADTs and `Maybe`.
- Haskell 2010 Prelude Bool/list/tuple runtime expansion, including built-in
  list, tuple, unit, `Maybe`, `Either`, and `Ordering` constructors/types,
  list and tuple expression/pattern lowering, short-circuiting `&&`/`||`, and
  generated Core Prelude bindings for `id`, `const`, `not`, `otherwise`, `map`,
  `foldr`, `length`, `filter`, and `reverse`, with Core/STG/native and wet
  coverage.
- Haskell 2010 recursion coverage for the executable subset, including
  singleton self-recursive Core emission, local recursive `let` bindings,
  top-level fibonacci recursion, mutually recursive functions, cons-pattern
  recursive list functions, and default/no-egglog native wet tests.
- Haskell 2010 type class dictionary representation, including user-defined
  single-parameter classes, concrete instances, structured explicit source constraints,
  generated dictionary constructors/selectors, Core dictionary arguments,
  Core/STG preservation tests, native LLVM execution, and default/no-egglog
  native wet tests.
- Haskell 2010 built-in Prelude class dictionary coverage for `Eq Int`,
  `Eq Bool`, `Ord Int`, `Ord Bool`, and executable `Num Int` methods, including
  generated built-in dictionaries/selectors, overloaded comparison/arithmetic
  operator desugaring, Core/STG preservation tests, native LLVM execution, and
  default/no-egglog native wet tests.
- Haskell 2010 guarded RHS/case alternatives and as-pattern aliases, including
  multi-branch guarded function RHSs, guarded constructor/list/tuple/as-pattern
  case alternatives, alias bindings for as-patterns in parameters and case
  alternatives, Core/STG guard-fallthrough no-matching-alternative behavior,
  native empty-case lowering, and default/no-egglog native wet tests.
- Haskell 2010 IO printing slice, including `IO` typechecking, `main :: IO ()`
  native entrypoint execution, `putStrLn`, `print`, `return`, `(>>)`,
  expression-only `do` sequencing with local `let`, built-in `Show Int` and
  `Show Bool` dictionaries, Core/STG IO output oracles, native string literal
  and list-of-`Char` output, and default/no-egglog native wet tests.
- Haskell 2010 module graph and whole-program compilation for the executable
  subset, including dependency-file loading from imports, cycle/name-mismatch
  diagnostics, actual exported-name import resolution, explicit export/import
  filtering, qualified aliases, hiding, `Thing(..)` children, whole-program
  Core flattening, root `main` entrypoint selection, and default/no-egglog
  native wet tests.

## Non-Negotiable Rules

- The target is Haskell 2010.
- The compiler emits native executables.
- LLVM is the machine-code path.
- Egglog remains central.
- Laziness must be implemented.
- Bottom/runtime-error behavior must be preserved.
- Every phase has wet tests.
- No feature is complete until parsed, renamed, typechecked, desugared,
  compiled where applicable, and tested.
- GHC extensions are excluded initially.
- GHC compatibility is not claimed.
- The current `.hg` compiler remains the substrate.
- Parallel agents must work against documented IR boundaries.

## Definition of Success

The Haskell 2010 compiler succeeds when `hegglog compile Main.hs -o main` works
for the documented Haskell 2010 feature set, producing a native executable
whose behavior matches the implemented Haskell 2010 semantics.
