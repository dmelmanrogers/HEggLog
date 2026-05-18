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
Prelude list/Bool functions, recursive top-level/local functions, recursive
list functions, lazy constructor fields, user-defined single-parameter classes
with concrete instances and explicit constrained functions, and built-in
Prelude dictionaries for `Eq Int`, `Eq Bool`, `Ord Int`, `Ord Bool`, and
executable `Num Int` methods. Guarded RHSs, guarded case alternatives,
as-pattern aliases, and guard-fallthrough no-match behavior are also
implemented. The first IO printing slice is implemented for `IO`,
`main :: IO ()`, `putStrLn`, `print`, `return`, `(>>)`, expression-only `do`
sequencing with local `let`, and built-in `Show Int`/`Show Bool` dictionaries.
The following Haskell 2010 requirements are planned but not
implemented:

- irrefutable/lazy pattern semantics and richer pattern-match diagnostics
- superclasses, default methods, instance contexts, deriving, and broader
  `Show`
- broader Prelude/library subset
- Haskell source desugaring beyond the current executable subset
- broader IO, including `<-`, `(>>=)`, handles, and effects beyond stdout
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
`map`, `foldr`, `length`, `filter`, and `reverse`; dictionary-backed `Eq`,
`Ord`, and `Num` methods for the first built-in instances; guarded RHSs and
guarded case alternatives desugared to Bool `case`; as-pattern aliases lowered
as local Core bindings; `IO` actions for `putStrLn`, `print`, `return`, `(>>)`,
expression-only `do` sequencing; built-in `Show Int` and `Show Bool`
dictionaries; and primitive `/`.
Recursive top-level functions, mutually recursive
top-level groups, singleton self-recursive bindings, and local recursive `let`
bindings now emit recursive Core groups in the supported subset. The initial
type class slice typechecks user-defined single-parameter classes, concrete
context-free instances, explicit source constraints, and method calls by
emitting dictionary constructor values, selector functions, and explicit Core
dictionary arguments. Built-in `Eq Int`, `Eq Bool`, `Ord Int`, `Ord Bool`, and
`Num Int` dictionaries cover `(==)`, `(/=)`, `compare`, `(<)`, `(<=)`, `(>)`,
`(>=)`, `max`, `min`, `(+)`, `(-)`, `(*)`, `negate`, `abs`, and `signum`.
Built-in `Show Int` and `Show Bool` cover enough `show` support for `print`.
`fromInteger` is part of the executable `Num Int` dictionary, integer literals
elaborate through it, and ambiguous numeric constraints default to `Int`.
`/` remains checked concrete `Int` division; broader `Show` remains planned.

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
generated Prelude list functions. Core evaluation covers guarded self recursion,
local factorial recursion, top-level fibonacci recursion, mutual recursion, and
recursive list functions. It also evaluates dictionary-passed user class
method calls and built-in `Eq`/`Ord`/`Num` class methods through generated
selector functions and instance dictionary values.
Core evaluation also covers guarded RHS/as-pattern programs and reports
guard fallthrough as a no-matching-alternative runtime error.
It now models IO output for `putStrLn`, `print`, `return`, `(>>)`, and
expression-only `do` sequencing so Core remains the oracle for native
`main :: IO ()` execution.

This is a reference oracle for the native path. Source-spanned Haskell 2010
type diagnostics remain later work because the renamed AST is currently
spanless.

## What STG Runtime Exists Today

The Haskell2010 STG layer now provides an isolated STG-like IR, validator, and
pure heap evaluator for the lazy runtime MVP. It models function closures,
thunk closures, constructor closures, constructor fields, `let`/`letrec`, case
demand, recursive heap bindings, updateable-thunk sharing, single-entry thunk
re-entry, black-hole detection, Bool and user-constructor dispatch, and checked
`Int` primitive runtime errors.

The boxed LLVM/native runtime path is implemented for the current executable
subset, including ADT constructor objects, list/tuple/Prelude data constructor
objects, lazy field projection, and type class dictionary values as ordinary
constructor closures. The first IO action layer is implemented for
output-oriented programs: STG can represent and evaluate IO output actions, and
native `main :: IO ()` forces the compiled action instead of auto-printing a
scalar root.

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
applications in thunks, preserves `let`/`letrec`, recursive top-level and local
binding groups, cases, Bool and user
constructors, list/tuple/Prelude constructors, constructor field laziness, and
primitive operations, including the initial IO primitives, and rejects invalid
Core before lowering. Dictionary
records, selectors, constrained functions, and concrete instance dictionaries
lower through the same Core-to-STG path. Guarded RHS/as-pattern Core and
guard-fallthrough no-match errors are covered by Core-to-STG preservation
tests, alongside IO output preservation tests.

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
12. Recursive top-level and local function/data-structure coverage. Completed
    for singleton self-recursive bindings, mutually recursive top-level groups,
    local recursive `let`, fibonacci/factorial programs, recursive list
    functions with cons patterns, STG lowering/evaluation, native LLVM
    execution, and wet-tested default/no-egglog CLI runs.
13. Type class dictionary representation. Completed for user-defined
    single-parameter classes, concrete context-free instances, explicit
    constrained functions, generated dictionary constructors/selectors, Core
    dictionary arguments, STG lowering/evaluation, native LLVM execution, and
    wet-tested default/no-egglog CLI runs.
14. Built-in Prelude class dictionary coverage. Completed for `Eq Int`,
    `Eq Bool`, `Ord Int`, `Ord Bool`, executable `Num Int`, `Show Int`, and
    `Show Bool` methods,
    including generated built-in dictionaries/selectors, overloaded
    comparison/arithmetic/show method desugaring, Core/STG lowering/evaluation,
    native LLVM execution, and wet-tested default/no-egglog CLI runs.
    `fromInteger`, overloaded integer literals, and numeric defaulting are now
    covered for the executable `Int` numeric universe. Broader `Show` remains
    planned.
15. Guarded RHS/case alternatives and as-pattern aliases. Completed for
    multi-branch guarded function RHSs, guarded constructor/list/as-pattern case
    alternatives, alias bindings for as-patterns in parameters and case
    alternatives, Core/STG no-matching-alternative behavior for guard
    fallthrough, native empty-case lowering, and wet-tested default/no-egglog
    CLI runs. Irrefutable/lazy pattern semantics and richer source-spanned
    pattern diagnostics remain planned.
16. IO printing and `Show` bootstrap. Completed for `IO`, `main :: IO ()`,
    `putStrLn`, `print`, `return`, `(>>)`, expression-only `do` sequencing with
    local `let`, built-in `Show Int`/`Show Bool`, Core/STG output oracles,
    native string literal and list-of-`Char` output, and wet-tested
    default/no-egglog CLI runs.
17. Numeric literals and defaulting. Completed for dictionary-backed
    `fromInteger`, overloaded integer literals, default declarations that map
    the supported default set to executable `Int`, ambiguous numeric defaulting
    for `Eq`/`Ord`/`Num`/`Show` constraints, inferred constrained helper
    schemes, SCC-based binding generalization, Core/STG/native IO output
    oracles, and default/no-egglog wet tests.

## Where Egglog Fits

The existing ANF Egglog backend is now reused by a typed Haskell 2010 Core
adapter for safe Core-0 fragments. The adapter preserves laziness, bottom, and
runtime-error behavior by validating Core before and after extraction and by
omitting unsafe rewrites unless the fragment has facts strong enough to justify
them. Broader Core facts for ADTs, dictionary simplification, and full pattern
matching remain later Phase 15 expansion work.

## Where LLVM/Native Output Fits

Native executable output exists for the current `.hg` supported subset and for
the current Haskell 2010 executable subset. The Haskell 2010 path lowers typed
Core to STG-like lazy IR, emits a boxed lazy LLVM runtime with closure
allocation, enter/apply, thunk forcing/update, Bool and user-constructor case
dispatch, list/tuple/Prelude constructor dispatch, boxed constructor fields,
recursive closure/thunk groups, user and built-in type class dictionary
constructor/selector execution, guarded RHS/as-pattern programs, empty-case
guard-fallthrough aborts, `putStrLn`/`print` output for `IO ()` programs with
native string literal objects, list-of-`Char` traversal, and built-in
`Show Int`/`Show Bool`, and checked primitives, and invokes clang to produce
native machine-code executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Task

Implement remaining pattern diagnostics and irrefutable/lazy pattern semantics
while preserving the `.hg` compiler, Core evaluator, STG runtime,
Core-to-STG lowering, native executable path, Egglog Core optimizer,
ADT/list/tuple/Prelude/recursion/typeclass-dictionary support, built-in
`Eq`/`Ord`/`Num`/`Show` dictionary support, numeric defaulting,
guard/as-pattern support, IO printing support, and wet-test baseline.
