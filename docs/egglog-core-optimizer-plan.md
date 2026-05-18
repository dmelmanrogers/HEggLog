# Egglog Core Optimizer Plan

## Purpose

Egglog remains central. The current ANF Egglog backend is the prototype for the
optimization strategy over a strict `.hg` intermediate form. The Haskell 2010
compiler will use Egglog over typed Core.

## Pipeline Position

```text
Haskell2010 source
  -> parser/layout
  -> renamer
  -> typechecker
  -> desugarer
  -> typed Core
  -> Egglog Core optimizer
  -> STG-like lazy IR
  -> LLVM
  -> native executable
```

Core optimization happens before lowering to STG-like lazy IR. It must preserve
lazy semantics and bottom behavior.

## Core Egglog Schema

Planned sorts and facts:

- `CoreExpr`
- `CoreType`
- `KnownConst`
- `KnownConstructor`
- `Total`
- `NoError`
- `NonZero`
- `NoOverflow`
- `Demand`
- `StrictIn`
- `DictionaryKnown`

The adapter should live outside the generic Egglog kernel. The kernel remains a
frontend-independent equality-saturation engine; `Optimize.CoreEgglog` is the
compiler-specific encoding, rule, fact, extraction, and provenance layer.

## Soundness Under Laziness

Laziness and bottom make ordinary rewrites dangerous. A rewrite that is safe in
a strict language can be unsound in Haskell if it erases a demanded expression
that diverges or raises an error.

Forbidden unguarded rewrites:

- `x * 0 => 0`
- `if c then a else a => a`
- `x / x => 1`

Required guards include:

- totality
- no-error
- nonzero
- no-overflow
- known constructor
- demand/strictness facts

Bottom and runtime-error preservation are part of the optimizer contract.

## Optimizations

Planned optimizations:

- constant folding when total and safe
- case-of-known-constructor
- constructor projection
- dictionary simplification
- boolean simplification preserving bottom
- safe arithmetic identities
- dead branch elimination with guards

Every optimization must be validated against typed Core, a reference evaluator
or semantic oracle, and native wet tests once the executable path exists.

## Extraction

Extraction requirements:

- extraction produces typed Core
- Core validator runs after extraction
- no unbound variables
- type preservation
- bottom/error preservation
- deterministic output
- provenance/explanations

Optimized and unoptimized native executables must agree for all successful wet
tests. Runtime-error and bottom behavior must remain in the same observable
class unless a documented Haskell semantic rule says otherwise.
