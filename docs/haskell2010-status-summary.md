# Haskell 2010 Status Summary

## Active Target

HeggLog is a Haskell 2010 native compiler project implemented in Haskell. The
active target is Haskell 2010 source compiled to native machine-code
executables through LLVM and clang.

## Current Substrate

The repository currently contains a working native compiler for a strict `.hg`
subset. That substrate includes parsing, typechecking, interpretation, ANF,
Egglog optimization for supported ANF fragments, closure conversion, LLVM IR
generation, native executable output, CI checks, and mandatory end-to-end wet
tests.

## What Currently Compiles

The current compiler compiles supported `.hg` programs with `Int`, `Bool`,
`let`, `if`, arithmetic/comparison, ordered top-level first-order calls,
lambda-lifted non-capturing lambdas, and closure-converted local function
values when the root is printable.

## What Does Not Yet Compile

HeggLog does not yet compile Haskell 2010 `.hs` source. The following Haskell
2010 requirements are planned but not implemented:

- layout-aware parser
- renamer and module/import resolution
- Haskell Hindley-Milner typechecker
- ADTs and pattern matching
- type classes and dictionary passing
- Prelude/library subset
- lazy Core/STG/runtime path
- IO `main`
- Haskell 2010 conformance suite

## First Haskell 2010 Implementation Milestones

1. Haskell 2010 parser/layout MVP.
2. Renamer MVP.
3. Typed Core MVP.
4. Lazy/STG runtime MVP.
5. Egglog Core optimizer implementation after Core exists.

## Where Egglog Fits

The existing ANF Egglog backend proves the project can use an Egglog-style
optimizer in the compiler. The Haskell 2010 path will add a typed Core Egglog
adapter that preserves laziness, bottom, and runtime-error behavior.

## Where LLVM/Native Output Fits

Native executable output already exists for the current `.hg` supported subset.
The Haskell 2010 path will lower typed Core to STG-like lazy IR, link a runtime,
emit LLVM IR, and invoke clang to produce native machine-code executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Task

Build the Haskell 2010 parser/layout MVP while preserving the current `.hg`
compiler and wet-test baseline.
