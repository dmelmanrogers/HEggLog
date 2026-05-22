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

The Haskell 2010 typechecker now has explicit kind inference/checking over
source type expressions. It represents `*`, kind arrows, and internal kind
metavariables; infers higher-kinded data parameters from constructor fields;
checks signatures, constructor fields, constraints, lists, tuples, functions,
and supported built-in/user constructors; and rejects partial or over-applied
type constructors before Core generation. Type synonyms are kind-inferred,
checked for recursive cycles, and expanded structurally before Core conversion.
Class constraints now use an explicit class-head-plus-arguments representation;
the current executable slice validates single-argument constraint arity before
kind checking and dictionary elaboration, and constraint arguments participate in
type synonym expansion and substitution like other source types. Superclass
contexts on single-parameter classes are represented in dictionary types as
leading superclass fields, default class methods are used to fill omitted
instance methods, and dictionary resolution can project superclass dictionaries
from local and instance dictionaries. Method-specific constraints, instance
contexts, and expression type-signature constraints still have structured
placeholder diagnostics until their dedicated class-system tasks are
implemented.

TC-020 adds the supported `Monad` class surface on top of that dictionary
model. The built-in `Monad` class parameter has kind `* -> *`, so constraint
and instance-head kind checking can validate higher-kinded arguments such as
`IO`, `Maybe`, and `[]` while rejecting `Monad Int`. The generated dictionary
constructor stores polymorphic method fields for `return`, `(>>=)`, `(>>)`, and
`fail`; selector bindings instantiate those method fields at each use site.
Built-in dictionaries for `Monad IO`, `Monad Maybe`, and `Monad []` drive
generic do-notation desugaring, including refutable pattern binds that call
`fail` instead of relying on a raw no-match case.

TC-030 promotes `Read` from the now-closed TC-016 documented deviation into the
supported Prelude/typeclass surface. The typechecker installs the `Read` class
with Report-shaped `readsPrec` and `readList` methods, generated `ReadS` and
`ShowS` synonyms, public `reads`, `read`, `lex`, and `readParen` bindings,
built-in scalar/list dictionaries, and derived `Read` dictionaries for the same
supported data/newtype shapes as derived `Show`. Generated read parsers lower
through the ordinary dictionary, Core, STG, LLVM, and native paths.

TYPE-019 records the monomorphism-restriction decision for the executable
subset: unsigned nullary value bindings without explicit signatures are eligible
for standard-class defaulting before generalization, while explicitly signed
bindings and functions with value parameters keep their result metavariables
protected from this defaulting pass. This matches the current executable
`Int`-defaulting behavior for numeric/simple class constraints, now including
standard-class compatibility with `Enum`/`Bounded` and with the supported
`Real`/`Integral` hierarchy when a `Num` constraint is present, without
claiming complete Haskell 2010 monomorphism-restriction coverage for every
pattern binding and class-library form. Full MR conformance should be revisited
when broader pattern bindings, Fractional/Floating classes, arbitrary-precision
`Integer`, and full `Ratio`/`Rational` behavior are in place.

TYPE-020 preserves source attribution for Haskell 2010 typecheck failures.
Parsed declarations, expressions, patterns, statements, alternatives,
constructor declarations, RHSs, and source types carry source spans into the
renamed AST. The typechecker records the active source node while checking and
renders failures through the shared `file:line:column` diagnostic formatter.
Class constraints also retain their originating expression/type span so delayed
dictionary-resolution failures, such as an unsolved `Num Bool` constraint, still
point back to the source expression that produced the constraint.

TYPE-021 adds generated inference-property coverage for the Haskell 2010
typechecker. QuickCheck now builds small `Int`/`Bool` programs with literals,
lets, lambdas, `if`, arithmetic, comparisons, and equality, then asserts that
well-typed programs infer and emit validating Core with the expected `main`
type. A separate generated custom-class slice checks dictionary solving and
dictionary constructor metadata, and generated signature-mismatch programs must
fail with structured type errors instead of producing Core.

Newtype declarations are typechecked with the required single-field invariant
and have a distinct Core representation. Constructors are recorded as
`CoreNewtypeConstructor`, construction and pattern unwrapping elaborate to typed
Core coercions, and Core-to-STG lowering erases the wrapper to the single field
representation before native code generation. Remaining class, deriving, and
broader surface work is tracked separately.

TC-023 adds derived `Eq` for the supported Haskell 2010 executable subset.
Derived instances are represented as ordinary dictionary bindings, including
polymorphic type lambdas and context dictionary arguments when constructor
fields require them. The generated methods compare constructors structurally,
short-circuit field equality with `&&`, define `(/=)` in terms of `(==)`, and
support recursive data, `newtype`, `String` fields, and list-backed contexts
through a generated structural `Eq [a]` dictionary.

TC-024 adds derived `Ord` for the same executable deriving surface. Generated
instances carry the required `Eq` superclass dictionary, compare constructors in
declaration order, compare product fields lexicographically with `compare`, and
derive the relational, `max`, and `min` methods from the generated comparison.
Structural `Ord [a]` is available for list and `String` fields, and superclass
projection now lowers through reusable Core selector bindings rather than
duplicating local projection cases.

TC-025 adds derived `Show` for the same executable deriving surface, and TC-029
promotes that implementation to the Haskell 2010 method shape. Generated
instances now synthesize `showsPrec`, `show`, and `showList` dictionary methods
for nullary constructors, product constructors, records, recursive data,
`newtype`, `String` fields, list-backed contexts, and parameterized
declarations. Product constructors render with application precedence 10,
nested constructor fields are parenthesized through `showsPrec 11`, records use
record-construction syntax, and the generated `showList` methods use the same
continuation-passing `ShowS` surface as the built-in dictionaries.

TC-031 adds derived `Enum` for nullary-constructor data declarations. Generated
dictionaries number constructors in declaration order, synthesize `succ`,
`pred`, `toEnum`, `fromEnum`, and the report-shaped range methods, and reject
constructors with fields as invalid deriving targets. Arithmetic-sequence
syntax now elaborates through the resolved `Enum` methods, so user-derived
enumerations share the same dictionary path as built-in `Int` and `Char`
ranges.

TC-032 adds derived `Bounded` for the Haskell 2010 shapes supported by the
current deriving pipeline. All-nullary data declarations synthesize
`minBound` as the first constructor and `maxBound` as the last constructor.
Single-constructor products, records, and newtypes synthesize constructor
applications whose fields are populated by field-wise `minBound`/`maxBound`
calls, so parameterized products acquire ordinary `Bounded` field constraints.
Mixed or multi-constructor declarations with fields are rejected with a stable
diagnostic. Generated derived methods are marked as compiler-generated for
pattern-coverage purposes so user-facing exhaustiveness warnings are not
polluted by internal dictionary bindings.

ADT-005 adds the supported record-label subset. Record declarations introduce
field selector names in the term namespace, record construction is typechecked
against the constructor's labelled fields and currently requires every field
exactly once, and record patterns desugar through the existing positional
constructor-pattern path with omitted fields treated as wildcards. Selector
bindings are emitted as ordinary Core functions: data selectors lower to cases
over the labelled constructors, while single-field newtype selectors lower to
typed coercions.

ADT-007 adds record update expressions as a distinct parsed and renamed AST
form, separate from record construction. The typechecker resolves every update
label through the record-selector table, requires all update labels to belong to
one datatype, rejects duplicate labels, and reports concrete non-record or
wrong-record scrutinees at the update source span. Valid updates lower to a
Core case over the scrutinee with alternatives only for constructors that
contain all updated labels. Each alternative reconstructs the original
constructor with new expressions for updated labels and reused field binders for
untouched labels, preserving laziness of untouched fields. Constructors in the
same datatype that do not contain every updated label are intentionally omitted,
so reaching one at runtime is the Haskell 2010 record-update error. Single-field
newtype record updates lower through the existing newtype coercion path. Partial
record construction semantics remain future surface work.

The existing optional monomorphic lambda parameter inference is carry-forward
infrastructure and a useful implementation reference, but it is not Haskell
2010 typechecking. Haskell 2010 progress is tracked in
[haskell2010-conformance-matrix.md](haskell2010-conformance-matrix.md) and
[haskell2010-frontend-spec.md](haskell2010-frontend-spec.md).
