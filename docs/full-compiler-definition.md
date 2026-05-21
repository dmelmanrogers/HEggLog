# Full Compiler Definition

This document distinguishes the current full compiler baseline from the active
Haskell 2010 full compiler target.

## Current Full Compiler Baseline

The existing compiler is a working native compiler for the documented strict
`.hg` subset.

For supported `.hg` programs, the current compiler can:

- parse and typecheck source
- interpret source
- lower to ANF and backend IR
- optimize supported ANF through the Egglog backend
- lambda-lift and closure-convert currently supported local functions
- emit LLVM IR
- compile through `clang` to a native executable
- execute native artifacts under mandatory wet tests

This baseline is real compiler infrastructure, but it is not Haskell 2010
source support.

## Haskell 2010 Full Compiler

The active target is a Haskell 2010 compiler.

A full Haskell 2010 compiler requires:

- Haskell 2010 parser/layout
- renamer
- Hindley-Milner typechecker
- type classes
- ADTs
- pattern matching
- modules
- Prelude/library subset
- lazy runtime
- STG-like IR
- Egglog Core optimizer
- LLVM/native output
- conformance and wet tests
- documented deviations

The current executable Haskell 2010 subset includes typed Core desugaring for
left and right operator sections over the supported infix operator subset.
Sections lower to generated lambdas and then continue through the existing
Core, STG, LLVM, and native execution pipeline. Recursive non-variable pattern
bindings also lower into lazy selector bindings that participate in the normal
Core recursive binding model.

The Haskell 2010 typechecker also exposes source-spanned non-exhaustive and
redundant pattern-match warnings for supported `case`, function, and lambda
patterns through `typecheckModuleToCoreWithWarnings`; native compilation
preserves those warnings in `Haskell2010LLVMResult`, and the compile CLI renders
them to stderr. This is not yet a report-complete Haskell 2010 coverage checker
or runtime source-attribution system.

The success criterion is documented in
[`haskell2010-roadmap.md`](haskell2010-roadmap.md): `hegglog compile Main.hs -o
main` must produce a native executable whose behavior matches the implemented
Haskell 2010 semantics.
