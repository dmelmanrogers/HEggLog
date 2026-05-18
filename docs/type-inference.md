# Type Inference Direction

This document records the current `.hg` type-system direction and distinguishes
it from the future Haskell 2010 typechecker. It is intentionally conservative:
the current `.hg` compiler now has local closures in LLVM, so inference must
preserve the backend's explicit monomorphic representation instead of exposing
polymorphism that the current compiler cannot specialize yet.

## Current Decision

HeggLog should move toward Hindley-Milner inference incrementally. The
user-facing language now permits omitted lambda parameter annotations when they
resolve to concrete monomorphic types, while top-level signatures and
polymorphic lets remain explicit or deferred.

Implemented in this phase:

- `Typecheck.Principal` provides an Algorithm W-style principal type engine and
  a located source elaborator.
- The engine has explicit type variables, substitutions, instantiation,
  unification, let-generalization infrastructure, and principal type schemes.
- Optional lambda parameter annotations are resolved before any backend-facing
  lowering step. The elaborated located AST stores explicit parameter types.
- Tests cover principal types for annotated identity and higher-order closures,
  a negative monomorphic-let case, optional lambda inference, delayed equality
  resolution, source-spanned ambiguity diagnostics, and LLVM closure conversion
  for inferred captured lambdas.
- The production compile path elaborates source programs before interpretation,
  lambda lifting, closure conversion, ANF lowering, and LLVM lowering.

This gives the project a tested inference boundary without weakening existing
diagnostics, closure conversion, ANF lowering, or LLVM backend invariants.

## Scope

Allowed now:

- Explicit lambda parameter annotations.
- Optional lambda parameter annotations when inference resolves every omitted
  parameter to a concrete monomorphic type.
- Explicit top-level parameter and return annotations.
- Monomorphic local closure values.
- Principal type computation for the current core language.

Deferred:

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

## Completed Lambda Inference Increment

Optional lambda parameter annotations are supported in source programs:

```text
\x -> x + 1
```

The elaborator delays ambiguity checks until surrounding context has had a
chance to constrain omitted parameter types. For example, `(\x -> x == x) true`
resolves `x` to `Bool`, while `\x -> x` fails with a source-spanned ambiguity
diagnostic. Local lets remain monomorphic, so this feature does not expose
polymorphic source values.

Polymorphic let should wait until there is an explicit monomorphization plan for
compiled programs.

## Next Increment

The next type-system increment should specify backend monomorphization before
exposing polymorphic lets or optional top-level signatures. Until that exists,
the roadmap can move on to the Egglog backend work without blocking on more
type-system surface area.

## Haskell 2010 Typechecker Target

The Haskell 2010 compiler requires a separate frontend typechecker:

- Hindley-Milner inference for Haskell source
- polymorphic let
- explicit signatures
- type classes and constraints
- dictionary passing
- defaulting
- kind checking for type constructors/classes

The Haskell 2010 typechecker now has an explicit kind representation for the
next increment: `*`, kind arrows, rendered kinds, derived constructor arity, and
type-constructor metadata for user declarations and the supported built-in
constructors. This is representation infrastructure only; full kind
inference/checking remains the next Haskell 2010 typechecker task.

The existing optional monomorphic lambda parameter inference is carry-forward
infrastructure and a useful implementation reference, but it is not Haskell
2010 typechecking. Haskell 2010 progress is tracked in
[haskell2010-conformance-matrix.md](haskell2010-conformance-matrix.md) and
[haskell2010-frontend-spec.md](haskell2010-frontend-spec.md).
