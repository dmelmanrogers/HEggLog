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

HeggLog now compiles the first Haskell 2010 Core-0 `Int`/`Bool` subset from
`.hs` source to native executables. The following Haskell 2010 requirements are
planned but not implemented:

- ADTs and pattern matching
- type classes and dictionary passing
- Prelude/library subset
- Haskell source desugaring beyond the Core-0 `Int`/`Bool` subset
- IO `main`
- Haskell 2010 conformance suite

## What Is Parsed Today

The Haskell2010 frontend now parses source into an isolated AST. Covered parser
surface includes module headers, imports, exports, layout blocks, type
signatures, value and pattern bindings, fixity declarations, data/newtype/type
declarations, class and instance declarations, defaults, raw foreign
declarations, lambdas, application, unresolved infix expressions, `if`, `case`,
`let`, `where`, `do`, lists, tuples, sections, arithmetic sequences, list
comprehensions, guards, patterns, and common Haskell type syntax.

## What Is Renamed Today

The Haskell2010 renamer resolves parser AST names into a unique-name AST. It
handles top-level, local `let`/`where`, lambda, pattern, class-method, and
instance-method scopes; separates term, constructor, type, type-variable,
class, and module namespaces; reports duplicate binders, unbound names, and
ambiguous explicit imports; resolves qualified explicit imports; and resolves
infix expressions according to declared and Prelude fixities.

Whole-program module graph loading, open import export discovery, hiding
semantics, and full Prelude surface coverage remain later module-system work.

## What Core Exists Today

The Haskell2010 Core layer now provides an isolated typed Core IR with Core
types, expression-level type metadata, variables, literals, constructors,
lambdas, applications, nonrecursive and recursive lets, cases, and primitive
operations. It includes a validator for unique binders, resolved variables,
type annotations, function application, primitive signatures, constructor
arities, and case alternative result types, plus free-variable analysis,
capture-aware substitution, and a stable pretty-printer.

This Core layer is tested directly but is not yet generated from Haskell 2010
source outside the Core-0 subset.

## What Typechecks To Core Today

The Haskell2010 Core-0 path now typechecks renamed source and emits validating
typed Core for a first `Int`/`Bool` subset: explicit signatures, HM
generalization and instantiation, top-level functions, lambdas, application,
local `let`, `if` desugared to Bool `case`, explicit Bool `case`, and primitive
`+`, `-`, `*`, `/`, `<`, and `==`.

Core-0 equality is deliberately limited to first-order literal value types
(`Int`, `Bool`, `Char`, and `String`) until class constraints and dictionaries
exist.

## What Core Evaluates Today

The Core-0 reference evaluator executes validating typed Core modules and
bindings for the first executable subset. It implements lazy let and function
argument thunks, forces case scrutinees and primitive operands, erases Core type
abstraction/application at runtime, evaluates Bool cases, reuses the checked
signed `Int64` arithmetic/division helpers, and reports structured runtime
errors such as division by zero and no matching case alternative.

This is a reference oracle only. It does not lower Core to STG, allocate/update
native runtime thunks, or compile Haskell 2010 source to native executables.
Source-spanned Haskell 2010 type diagnostics also remain later work because the
renamed AST is currently spanless.

## What STG Runtime Exists Today

The Haskell2010 STG layer now provides an isolated STG-like IR, validator, and
pure heap evaluator for the lazy runtime MVP. It models function closures,
thunk closures, constructor closures, `let`/`letrec`, case demand,
updateable-thunk sharing, single-entry thunk re-entry, black-hole detection,
Bool constructor dispatch, and checked `Int` primitive runtime errors.

The boxed LLVM/native runtime path is implemented for the first Core-0
`Int`/`Bool` subset. Runtime expansion for ADTs, pattern fields, Prelude data,
and IO remains later work.

## What Lowers To STG Today

The Core-to-STG lowering path translates validating Core-0 modules into
validating STG programs. It erases Core type abstraction/application, lowers
Core lambdas as unary curried STG functions, wraps non-atomic operands and
intermediate applications in thunks, preserves `let`/`letrec`, cases, Bool
constructors, and primitive operations, and rejects invalid Core before
lowering.

Lowered STG currently runs through the in-process STG evaluator as the semantic
check. The Core-0 `Int`/`Bool` subset is now also emitted as boxed lazy STG
LLVM and compiled to native executables through the existing clang toolchain.

## First Haskell 2010 Implementation Milestones

1. Haskell 2010 parser/layout MVP. Completed.
2. Renamer MVP. Completed.
3. Typed Core MVP. Completed.
4. Core-0 Haskell typechecker/desugarer integration. Completed.
5. Core-0 reference evaluator. Completed.
6. Lazy/STG runtime MVP. Completed.
7. Core-to-STG lowering MVP. Completed.
8. Core-0 native executable path. Completed.
9. Egglog Core optimizer implementation using the Core/STG/native evaluators
   as oracle.

## Where Egglog Fits

The existing ANF Egglog backend proves the project can use an Egglog-style
optimizer in the compiler. The Haskell 2010 path will add a typed Core Egglog
adapter that preserves laziness, bottom, and runtime-error behavior.

## Where LLVM/Native Output Fits

Native executable output exists for the current `.hg` supported subset and for
the first Haskell 2010 Core-0 subset. The Haskell 2010 path lowers typed Core
to STG-like lazy IR, emits a boxed lazy LLVM runtime with closure allocation,
enter/apply, thunk forcing/update, Bool case dispatch, and checked primitives,
and invokes clang to produce native machine-code executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Task

Build the Egglog Core optimizer while preserving the current `.hg` compiler,
Core-0 reference evaluator, STG runtime MVP, Core-to-STG lowering, Core-0
native executable path, and wet-test baseline.
