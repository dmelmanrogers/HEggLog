# Type Inference Direction

This document records the Phase 7 type-system direction. It is intentionally
conservative: HeggLog now has local closures in LLVM, so inference must preserve
the backend's explicit monomorphic representation instead of introducing
polymorphism that the compiler cannot specialize yet.

## Current Decision

HeggLog should move toward Hindley-Milner inference incrementally, but the
user-facing language remains explicitly annotated for now.

Implemented in this phase:

- `Typecheck.Principal` provides an Algorithm W-style principal type engine for
  the current annotated source language.
- The engine has explicit type variables, substitutions, instantiation,
  unification, let-generalization infrastructure, and principal type schemes.
- Tests cover principal types for annotated identity and higher-order closures,
  plus a negative monomorphic-let case.
- The production typechecker and backend compile path remain unchanged.

This gives the project a tested inference boundary without weakening existing
diagnostics, closure conversion, ANF lowering, or LLVM backend invariants.

## Scope

Allowed now:

- Explicit lambda parameter annotations.
- Explicit top-level parameter and return annotations.
- Monomorphic local closure values.
- Principal type computation for the current annotated language.

Deferred:

- Optional lambda parameter annotations in source syntax.
- Optional top-level return annotations.
- Polymorphic let in user-facing programs.
- Generalization across recursive definitions.
- Type classes or overloaded equality.
- Backend monomorphization for polymorphic functions.

## Why Not Expose HM Immediately

Full Hindley-Milner inference would allow source programs whose inferred types
contain universally quantified variables. The current backend does not yet have
a specialization pass that turns polymorphic functions into monomorphic Backend
IR or LLVM functions. Exposing polymorphism before monomorphization would force
one of two bad choices:

- reject programs late after type inference appears to accept them
- erase useful type distinctions in backend IR

The correct sequence is to build inference infrastructure first, then expose
syntax only when lowering and diagnostics can preserve the inferred contract.

## Next Increment

The next safe implementation step is optional lambda parameter annotations:

```text
\x -> x + 1
```

Acceptance requirements for that step:

- unannotated parameters infer a principal monotype
- ambiguous parameters fail with source-spanned diagnostics
- existing annotated syntax remains valid
- closure conversion receives fully resolved monomorphic function types
- LLVM differential tests cover inferred local closures

Polymorphic let should wait until there is an explicit monomorphization plan for
compiled programs.
