# HeggLog Roadmap

The authoritative project roadmap is now
[HeggLog Roadmap: Haskell 2010 Native Compiler](haskell2010-roadmap.md).

## Active Target

HeggLog is a Haskell 2010 native compiler project implemented in Haskell. The
active target is Haskell 2010 source compiled to native machine-code
executables through LLVM and clang.

The current strict `.hg` compiler is the backend/middle-end substrate and
regression baseline. It is not the final source-language endpoint and does not
compile Haskell 2010 source today.

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

1. Core-0 reference evaluator.
2. Lazy/STG runtime MVP.
3. Egglog Core optimizer implementation after Core has an execution oracle.

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
