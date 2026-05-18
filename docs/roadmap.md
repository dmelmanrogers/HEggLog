# HeggLog Roadmap

The authoritative project roadmap is now
[HeggLog Roadmap: Haskell 2010 Native Compiler](haskell2010-roadmap.md).

## Active Target

HeggLog is a Haskell 2010 native compiler project implemented in Haskell. The
active target is Haskell 2010 source compiled to native machine-code
executables through LLVM and clang.

The current strict `.hg` compiler is the backend/middle-end substrate and
regression baseline. It is not the final source-language endpoint. The Haskell
2010 path now compiles the documented executable subset, while the full
Haskell 2010 surface remains roadmap work.

## Current `.hg` Compiler Baseline

Implemented and tested for the current `.hg` compiler-supported subset:

- parser, typechecker, and report/interpreter mode
- ANF and resolved ANF
- Egglog backend for supported typed strict ANF fragments
- checked signed `Int64` semantics
- ordered top-level first-order functions
- lambda lifting for eligible non-capturing lambdas
- closure conversion for supported local function values
- Backend IR and LLVM IR generation
- native executable output through `clang`
- mandatory end-to-end wet tests of native artifacts
- CI build/test/package checks and wet-test execution

For the detailed current support matrix, see
[current-capabilities.md](current-capabilities.md).

## Haskell 2010 Tracking Docs

- [Haskell 2010 roadmap](haskell2010-roadmap.md)
- [Haskell 2010 conformance matrix](haskell2010-conformance-matrix.md)
- [Haskell 2010 implementation plan](haskell2010-implementation-plan.md)
- [Haskell 2010 frontend specification](haskell2010-frontend-spec.md)
- [Laziness and STG plan](laziness-and-stg-plan.md)
- [Egglog Core optimizer plan](egglog-core-optimizer-plan.md)

## Immediate Next Tasks

1. Haskell 2010 conformance matrix expansion for the broader executable surface.
2. Type class dictionary representation.
3. Pattern-match diagnostics, guards, and remaining pattern forms.

Completed Haskell 2010 roadmap work:

- Haskell 2010 parser/layout MVP: implemented as an isolated `Haskell2010`
  frontend AST, lexer, layout parser, parser, and parser tests.
- Haskell 2010 renamer MVP: implemented as an isolated unique-name pass with
  lexical scopes, namespace separation, duplicate/unbound diagnostics, explicit
  import ambiguity checks, and fixity resolution.
- Haskell 2010 typed Core MVP: implemented as an isolated typed Core IR with
  expression type metadata, primitive operations, constructors, lambdas,
  type abstractions/applications, applications, nonrecursive and recursive
  lets, cases, a validator, free-variable analysis, capture-aware
  substitution, pretty-printing, and unit tests.
- Haskell 2010 Core-0 typechecker/desugarer MVP: implemented as a renamed AST
  to typed Core pass for `Int`, `Bool`, explicit signatures, HM
  generalization/instantiation, top-level functions, lambdas, application,
  local `let`, `if`, Bool `case`, and primitive arithmetic/comparison.
- Haskell 2010 Core-0 reference evaluator: implemented as a validating typed
  Core evaluator with lazy let/function argument thunks, erased Core type
  abstraction/application, Bool case execution, checked `Int` primitives, and
  structured runtime errors.
- Haskell 2010 Lazy/STG runtime MVP: implemented as an isolated STG-like IR,
  validator, and pure heap evaluator with function closures, updateable and
  single-entry thunk closures, constructor closures, `let`/`letrec`, case
  demand, sharing, black-hole detection, Bool constructor dispatch, and checked
  primitive runtime errors.
- Haskell 2010 Core-to-STG lowering MVP: implemented as a validating lowering
  pass from typed Core-0 modules to STG, with Core type erasure, curried
  function lowering, thunked non-atomic operands/intermediate applications,
  `let`/`letrec`, Bool cases, primitive operations, and STG evaluator
  preservation tests.
- Haskell 2010 native executable path for the first Core-0 slice: implemented
  as boxed STG-to-LLVM lowering with closure allocation, thunk forcing/update,
  enter/apply, Bool case dispatch, checked primitive aborts, `.hs`
  compile-mode integration, and native wet tests for arithmetic, polymorphism,
  laziness, partial application, Bool case, and forced division-by-zero failure.
- Haskell 2010 Egglog Core optimizer: implemented for safe typed Core-0
  `Int`/`Bool` fragments with checked constant folding, safe arithmetic
  identities, known Bool case selection, typed Core extraction/validation,
  provenance, `--no-egglog` native comparison, and Core/STG/native oracle
  tests preserving laziness and forced runtime errors.
- Haskell 2010 ADT and pattern-match Core support: implemented for custom
  `data` declarations, polymorphic constructors, constructor cases, nested
  constructor patterns, lazy constructor fields, Core/STG validation, native
  boxed constructor objects, and default/no-egglog wet tests for custom ADTs and
  `Maybe`.
- Haskell 2010 Prelude Bool/list/tuple runtime expansion: implemented for
  built-in list, tuple, unit, `Maybe`, `Either`, and `Ordering`
  constructors/types, list and tuple expressions/patterns, short-circuiting
  Bool operators, and generated Core Prelude bindings for `id`, `const`, `not`,
  `otherwise`, `map`, `foldr`, `length`, `filter`, and `reverse`.
- Haskell 2010 recursion coverage: implemented for singleton self-recursive
  top-level/local bindings, mutually recursive functions, fibonacci/factorial
  programs, cons-pattern recursive list functions, and default/no-egglog native
  wet tests.

## Non-Negotiable Project Direction

- The source-language target is Haskell 2010.
- The compiler emits native executables.
- LLVM is the machine-code path.
- Egglog optimization remains central.
- Laziness must be implemented for Haskell 2010.
- Bottom/runtime-error behavior must be preserved.
- Current `.hg` functionality remains preserved as substrate and regression
  coverage.
- GHC compatibility is not claimed.
