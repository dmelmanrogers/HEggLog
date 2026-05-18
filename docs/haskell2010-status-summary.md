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

HeggLog now compiles the current Haskell 2010 executable subset from `.hs`
source to native executables. The subset includes `Int`, `Bool`, functions,
lazy lets and arguments, custom ADTs, polymorphic constructors, constructor
cases, nested constructor patterns, list and tuple expressions/patterns/types,
built-in `Maybe`, `Either`, and `Ordering`, generated Core bindings for basic
Prelude list/Bool functions, and lazy constructor fields. The following Haskell
2010 requirements are planned but not implemented:

- recursive top-level and local definitions beyond the currently generated
  Prelude helpers
- remaining pattern forms and pattern-match diagnostics
- type classes and dictionary passing
- broader Prelude/library subset
- Haskell source desugaring beyond the current executable subset
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

The Haskell2010 path now typechecks renamed source and emits validating typed
Core for the current executable subset: explicit signatures, HM generalization
and instantiation, top-level functions, lambdas, application, local `let`, `if`
desugared to Bool `case`, explicit Bool and user-constructor `case`, custom
`data` declarations, polymorphic constructors, constructor patterns, nested
constructor patterns, list and tuple expressions/patterns/types, built-in
Prelude data constructors, wildcard patterns, literal patterns, short-circuit
`&&`/`||`, generated Prelude bindings for `id`, `const`, `not`, `otherwise`,
`map`, `foldr`, `length`, `filter`, and `reverse`, and primitive `+`, `-`,
`*`, `/`, `<`, and `==`.

Core-0 equality is deliberately limited to first-order literal value types
(`Int`, `Bool`, `Char`, and `String`) until class constraints and dictionaries
exist.

## What Core Evaluates Today

The Core reference evaluator executes validating typed Core modules and bindings
for the current executable subset. It implements lazy let, function argument, and
constructor field thunks, forces case scrutinees and primitive operands, erases
Core type abstraction/application at runtime, evaluates Bool and user
constructor cases, reuses the checked signed `Int64` arithmetic/division
helpers, and reports structured runtime errors such as division by zero and no
matching case alternative.
It now also evaluates list and tuple values/patterns, built-in
`Maybe`/`Either`/`Ordering` constructors, short-circuit Bool operators, and the
generated Prelude list functions.

This is a reference oracle for the native path. Source-spanned Haskell 2010
type diagnostics remain later work because the renamed AST is currently
spanless.

## What STG Runtime Exists Today

The Haskell2010 STG layer now provides an isolated STG-like IR, validator, and
pure heap evaluator for the lazy runtime MVP. It models function closures,
thunk closures, constructor closures, constructor fields, `let`/`letrec`, case
demand, updateable-thunk sharing, single-entry thunk re-entry, black-hole
detection, Bool and user-constructor dispatch, and checked `Int` primitive
runtime errors.

The boxed LLVM/native runtime path is implemented for the current executable
subset, including ADT constructor objects, list/tuple/Prelude data constructor
objects, and lazy field projection. Runtime expansion for IO remains later
work.

## What Core Optimizes Today

The Haskell 2010 native path now runs a typed Core Egglog optimizer before
STG lowering unless `--no-egglog` is selected. The implemented adapter supports
safe Core-0 `Int`/`Bool` fragments, including checked constant folding, safe
arithmetic identities, known Bool case selection, typed Core extraction,
post-extraction Core validation, and provenance reporting. It deliberately
skips lazy-sensitive or unsupported Core shapes instead of forcing a rewrite.

The optimizer is tested against Core evaluation, lowered STG evaluation, and
native LLVM execution in both default and `--no-egglog` modes. Tests also cover
lazy let preservation and a strict-bottom case where `x * 0` must not erase a
forced division by zero.

## What Lowers To STG Today

The Core-to-STG lowering path translates validating Core modules into validating
STG programs. It erases Core type abstraction/application, lowers Core lambdas
as unary curried STG functions, wraps non-atomic operands and intermediate
applications in thunks, preserves `let`/`letrec`, cases, Bool and user
constructors, list/tuple/Prelude constructors, constructor field laziness, and
primitive operations, and rejects invalid Core before lowering.

Lowered STG runs through the in-process STG evaluator as the semantic check.
The current executable Haskell 2010 subset is also emitted as boxed lazy STG LLVM
and compiled to native executables through the existing clang toolchain.

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
   as oracle. Completed for the safe Core-0 `Int`/`Bool` fragment.
10. Broader ADT and pattern-match Core support. Completed for custom ADTs,
    polymorphic constructors, constructor cases, nested constructor patterns,
    lazy constructor fields, STG lowering/evaluation, native LLVM execution,
    and wet-tested default/no-egglog CLI runs.
11. Prelude Bool/list/tuple runtime expansion. Completed for built-in list,
    tuple, unit, `Maybe`, `Either`, and `Ordering` constructors/types,
    short-circuit Bool operators, generated Core Prelude bindings for `id`,
    `const`, `not`, `otherwise`, `map`, `foldr`, `length`, `filter`, and
    `reverse`, STG lowering/evaluation, native LLVM execution, and wet-tested
    default/no-egglog CLI runs.

## Where Egglog Fits

The existing ANF Egglog backend is now reused by a typed Haskell 2010 Core
adapter for safe Core-0 fragments. The adapter preserves laziness, bottom, and
runtime-error behavior by validating Core before and after extraction and by
omitting unsafe rewrites unless the fragment has facts strong enough to justify
them. Broader Core facts for ADTs, dictionaries, and full pattern matching
remain later Phase 15 expansion work.

## Where LLVM/Native Output Fits

Native executable output exists for the current `.hg` supported subset and for
the current Haskell 2010 executable subset. The Haskell 2010 path lowers typed
Core to STG-like lazy IR, emits a boxed lazy LLVM runtime with closure
allocation, enter/apply, thunk forcing/update, Bool and user-constructor case
dispatch, list/tuple/Prelude constructor dispatch, boxed constructor fields,
and checked primitives, and invokes clang to produce native machine-code
executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Task

Broaden the Haskell 2010 executable surface with recursive top-level and local
function/data-structure coverage while preserving the `.hg` compiler, Core
evaluator, STG runtime, Core-to-STG lowering, native executable path, Egglog
Core optimizer, ADT/list/tuple/Prelude support, and wet-test baseline.
