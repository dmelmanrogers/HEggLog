# HeggLog Roadmap: Haskell 2010 Native Compiler

## Project Goal

HeggLog is a Haskell 2010 native-code compiler project implemented in Haskell.
The compiler's active target is Haskell 2010 source code compiled to real
native machine-code executables through LLVM and clang.

The current `.hg` compiler is the backend and middle-end substrate, the
regression baseline, and the existing proof that native executable output,
Egglog optimization, closure conversion infrastructure, LLVM lowering, and
end-to-end wet testing work. It is not the final source language endpoint, and
it does not currently compile Haskell 2010 source programs.

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

Deliverables:

- data declarations and constructors
- constructor, literal, variable, wildcard, nested, tuple, list, and as-patterns
- guards
- pattern-match compiler to Core case

Acceptance criteria:

- `Maybe`, `Either`, and custom ADTs compile
- nested patterns compile
- pattern-bound names scope correctly
- native wet tests cover ADTs and nested patterns

### Phase 10 - Lists, Tuples, and Prelude Core

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

Deliverables:

- class declarations, instance declarations, constraints, and superclasses
- method lookup, dictionary passing, default methods, and basic deriving
- initial `Eq`, `Ord`, `Show`, and `Num` support

Acceptance criteria:

- `Eq` instances work
- `Show` works enough for print
- overloaded numeric literals work for supported numeric types
- dictionary-passing Core validates
- native wet tests cover typeclass calls

### Phase 13 - IO and `main`

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

- operator sections, list comprehensions, arithmetic sequences, guards, and
  where clauses
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

Deliverables:

- conformance test corpus for layout, expressions, declarations, patterns,
  ADTs, class/instance behavior, modules, Prelude, IO, runtime/laziness

Acceptance criteria:

- every conformance matrix row links to tests or a documented deviation
- no undocumented failures

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

1. Typed Core MVP.
2. Lazy runtime MVP.
3. Core validator and desugarer MVP.
4. Haskell 2010 typechecker MVP.
5. Core-to-STG lowering MVP.

Completed immediate tasks:

- Commit roadmap pivot.
- Haskell 2010 parser/layout MVP.
- Haskell 2010 renamer MVP.

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
