# Egglog Core Optimizer Plan

## Purpose

Egglog remains central. The current ANF Egglog backend is the prototype and now
also the execution engine for the first Haskell 2010 typed Core optimizer
slice. The implemented `Optimize.CoreEgglog` adapter optimizes safe Core-0
`Int`/`Bool` fragments before STG lowering and leaves unsupported or
lazy-sensitive Core unchanged.

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

The implemented first slice reuses the typed ANF Egglog schema for safe
Core-0 fragments and translates extracted ANF representatives back into typed
Core. The full Core-native schema is still planned for broader Haskell 2010
features.

Planned full Core sorts and facts:

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

Implemented for Core fragments:

- checked constant folding through the existing Egglog integer facts
- safe arithmetic identities such as adding or multiplying by identity values
- case-of-known Bool constructor
- case-of-known ADT/list/tuple/dictionary constructor when the scrutinee is a
  saturated constructor value
- case-of-known literal
- constructor-field projection for selected known-constructor alternatives,
  preserving lazy unused fields and forced bottom behavior
- typed extraction back to Core
- selected-rule provenance and fragment cost reporting
- `--no-egglog` native comparison coverage

Planned full Core optimizations:

- constant folding when total and safe
- dictionary simplification
- boolean simplification preserving bottom
- safe arithmetic identities
- dead branch elimination with guards

Every optimization must be validated against typed Core, a reference evaluator
or semantic oracle, and native wet tests. The current Core-0 implementation is
checked by Core evaluator tests, STG evaluator tests, and optimized versus
unoptimized native execution tests.

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
