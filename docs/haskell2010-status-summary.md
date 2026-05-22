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

## Current `.hg` Compilation

The current compiler compiles supported `.hg` programs with `Int`, `Bool`,
`let`, `if`, arithmetic/comparison, ordered top-level first-order calls,
lambda-lifted non-capturing lambdas, and closure-converted local function
values when the root is printable.

## Current Haskell 2010 Compilation

HeggLog now compiles the current Haskell 2010 executable subset from `.hs`
source to native executables. The subset includes `Int`, `Bool`, functions,
lazy lets and arguments, custom ADTs, polymorphic constructors, constructor
cases, nested constructor patterns, newtype constructor expressions and
patterns through the current boxed representation, list and tuple
expressions/patterns/types, built-in `Maybe`, `Either`, and `Ordering`,
generated Core bindings for basic Prelude list/Bool functions, recursive
top-level/local functions, recursive list functions, lazy constructor fields,
recursive non-variable pattern bindings through the Core recursion model,
user-defined single-parameter classes with concrete instances and explicit
constrained functions, boxed native `Char` literals and literal cases, scalar
`main :: Char` output, and built-in Prelude dictionaries for `Eq Int`,
`Eq Bool`, `Eq Char`, `Ord Int`, `Ord Bool`, `Ord Char`, executable `Num Int`, executable `Real Int`, and executable `Integral Int`
methods. Modules receive the built-in Prelude surface implicitly unless they
declare an explicit `import Prelude`, and explicit Prelude imports can restrict,
hide, or qualify names according to the current module import semantics. The
generated `Prelude` boundary now lives in `Haskell2010.StandardLibrary` as an
importable module interface rather than as an ad hoc renamer fallback.
Guarded RHSs, guarded case alternatives, as-pattern aliases, and
guard-fallthrough no-match behavior are also implemented. The first IO printing/input
slice is implemented for `IO`,
`main :: IO ()`, `putStrLn`, `getLine`, `print`, higher-kinded `Functor`
dictionaries for `IO`, `Maybe`, and lists with `fmap`, higher-kinded `Monad`
dictionaries for `IO`, `Maybe`, and lists, `return`, `(>>)`, `(>>=)`, `fail`,
generic expression and bind-statement `do` sequencing with local `let`, and
Report-shaped `Show` dictionaries for `Int`, `Bool`, `Char`, exact `String`,
generated structural lists, and supported derived data/newtype declarations.
Prelude also exposes `shows`.
The implemented FFI slice includes structured `foreign import`/`foreign export`
declarations, generated `Foreign`/`Foreign.C`/`Foreign.C.Types` interfaces,
marshallable scalar/pointer/synonym/local-newtype validation, static `ccall`,
address, `dynamic`, `wrapper`, foreign-export, `StablePtr`, and manual
`ForeignPtr` native wet coverage for the supported ABI surface.
The typechecker now also exposes source-spanned non-exhaustive and redundant
pattern-match warnings for supported `case`, function, and lambda patterns
through `typecheckModuleToCoreWithWarnings`; native compilation carries those
warnings in `Haskell2010LLVMResult`, and the compile CLI renders them to stderr.
The following Haskell 2010 requirements are planned but not
implemented:

- report-complete pattern coverage and runtime source attribution beyond the
  current executable-subset diagnostics
- remaining source-surface implementation closure
- instance contexts and derived `Read`
- Fractional/Floating classes, arbitrary-precision `Integer`, full
  `Ratio`/`Rational` behavior, and broader Prelude/library subset
- remaining standard-library value surfaces beyond the currently generated
  partial module interfaces
- Haskell source desugaring and negative fixtures beyond the current executable subset
- broader IO, including handles, rich recoverable IO errors, and effects beyond line-oriented stdin/stdout
- remaining FFI closure for floating-point marshalling, link metadata,
  callback/finalizer lifetimes, and broader `Foreign.*` modules
- full Haskell 2010 conformance suite breadth beyond the current
  manifest-backed executable subset

## Current Next Focus

The authoritative queue is the task tracker, not prose-only roadmap text. The
next implementation chunk is Prelude, deriving, and typeclass library
completion.
SURFACE-001 completed the current source-surface audit and matrix
reconciliation; SURFACE-002 completed user-defined operator bindings and infix
calls; SURFACE-003 completed report-shaped line-broken `where` layout
placement for function bindings and case alternatives. DIAG-009 completed supported-subset
pattern-match diagnostics, TEST-CONF-013 completed source-surface negative
fixtures, TEST-CONF-014 completed machine-checked source matrix closure, and
ADT-007 completed record update expressions for the supported record subset.

The following chunk is Prelude, deriving, and typeclass library completion.
PRELUDE-019 is complete for `($)`, `(.)`, `flip`, `head`, `tail`, `null`,
`fst`, and `snd`; PRELUDE-020 is complete for generated/importable
standard-library module interfaces that have real support, including
`Control.Monad` `Functor(fmap)` for `[]`, `Maybe`, and `IO`; and
TEST-CONF-015 is complete for validator-backed reconciliation of Chapter 9
Prelude plus the Part II library module inventory. TC-029 is complete for
report-shaped `Show`; the remaining tasks start with TC-030 for `Read`, then continue
through the numbered LIB-001 through LIB-012 standard-library module tasks.

Remaining FFI work is no longer tracked by a broad FFI-wide deferral. FFI-010
through FFI-013 now own floating-point marshalling, link metadata, callback and
finalizer lifetime completion, and broader `Foreign.*` library surface.

## What Is Parsed Today

The Haskell2010 frontend now parses source into an isolated AST. Covered parser
surface includes module headers, imports, exports, layout blocks, type
signatures, value and pattern bindings, fixity declarations, data/newtype/type
declarations, class and instance declarations, defaults, structured
`foreign import`/`foreign export` declarations, lambdas, application,
unresolved infix expressions, `if`, `case`, `let`, `where`, `do`, lists,
tuples, sections, arithmetic sequences, list comprehensions, guards, patterns,
and common Haskell type syntax.

## What Is Renamed Today

The Haskell2010 renamer resolves parser AST names into a unique-name AST. It
handles top-level, local `let`/`where`, lambda, pattern, class-method, and
instance-method scopes; separates term, constructor, type, type-variable,
class, and module namespaces; reports duplicate binders, unbound names, and
ambiguous explicit imports; resolves qualified explicit imports; and resolves
infix expressions according to declared and imported Prelude fixities. The module-aware
renamer now processes dependency modules in graph order, imports actual
exported definitions, enforces explicit export/import filtering, supports
qualified aliases and hiding, inserts a synthetic built-in `Prelude` import only
when no explicit `Prelude` import declaration exists, honors explicit Prelude
import lists, hiding, and qualified-only imports, and expands exported
`Thing(..)` children for the current executable subset. Module interfaces now
also propagate source instances independently of ordinary name export/import
filtering, so `module M ()`, `import M ()`, and transitive import chains keep
instances visible according to the Haskell 2010 module rule. Full package
search paths and full Prelude module surface coverage remain later
module-system work.

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
`data` declarations, `newtype` declarations with exactly one field,
polymorphic constructors, constructor patterns, nested constructor patterns,
list and tuple expressions/patterns/types, built-in Prelude data constructors,
wildcard patterns, literal patterns, short-circuit `&&`/`||`, generated Prelude
bindings for `id`, `const`, `not`, `otherwise`, `($)`, `(.)`, `flip`, `map`,
`foldr`, `foldl`, `head`, `tail`, `null`, `fst`, `snd`, `length`, `filter`,
`reverse`, and `(++)`; dictionary-backed `Eq`, `Ord`, and `Num` methods for
the first built-in instances, including `Eq Char`; guarded RHSs and
guarded case alternatives desugared to Bool `case`; as-pattern aliases lowered
as local Core bindings; `IO` actions for `putStrLn`, `getLine`, `print`,
`return`, `(>>)`, `(>>=)`, `fail`, expression `do`, and `<-` bind-statement
sequencing through built-in Monad dictionaries; left and right operator sections over the
supported infix subset desugared to generated Core lambdas; built-in `Show Int`,
`Show Bool`, `Show Char`, exact `Show String`, and generated list `Show`
dictionaries; and primitive `/`.
Foreign declarations now typecheck at the frontend boundary: generated
`Foreign`, `Foreign.C`, and `Foreign.C.Types` module interfaces expose the
initial FFI type surface, valid `ccall`/`stdcall` imports and exports are
checked for marshallable scalar/pointer/synonym/local-newtype shapes, and
invalid address, `dynamic`, `wrapper`, or export signatures fail before
lowering. Valid foreign imports now lower into explicit Core/STG foreign IR:
static imports, `dynamic`, and `wrapper` become eta-expanded foreign-call
nodes, while address imports become boxed pointer values; Core/STG eval reports
a precise unsupported runtime boundary when foreign calls are reached outside
the native backend. The native LLVM backend now lowers supported
`foreign import ccall` functions to external `declare`/direct `call`
instructions or indirect `FunPtr` calls, with boxed `Int`/`Bool`/`Char`, signed
and unsigned integer C ABI declarations, checked narrowing for outgoing integer
arguments, checked unsigned 64-bit result boxing, boxed `Ptr`/`FunPtr` values,
static `&symbol` data and function addresses, pointer arguments/results,
`IO` sequencing, and C-callable `wrapper` callbacks backed by process-lifetime
closure slots covered by linked C-helper native wet tests. `foreign export
ccall` declarations now lower through Core/STG export metadata into C-callable
native LLVM entrypoints for the supported scalar/pointer ABI slice; native wet
tests cover a C helper calling exported pure and `IO` Haskell functions.
Explicit `StablePtr` ownership and manual `ForeignPtr` finalizer APIs are also
implemented and wet-tested. Floating-point marshalling, broader link metadata,
automatic GC finalization, and `freeHaskellFunPtr`/callback-slot reclamation
remain pending.
Recursive top-level functions, mutually recursive
top-level groups, singleton self-recursive bindings, and local recursive `let`
bindings now emit recursive Core groups in the supported subset. The initial
type class slice typechecks user-defined single-parameter classes, concrete
context-free instances, explicit source constraints, and method calls by
emitting dictionary constructor values, selector functions, and explicit Core
dictionary arguments. Derived `Eq` and `Ord` synthesize supported data/newtype
dictionaries, including recursive, parameterized, `String`-field, and list-backed
cases. Built-in `Eq Int`, `Eq Bool`, `Eq Char`, `Ord Int`, `Ord Bool`,
`Ord Char`, structural `Eq [a]`, structural `Ord [a]`, `Num Int`, `Real Int`,
and `Integral Int` dictionaries cover `(==)`, `(/=)`, `compare`, `(<)`,
`(<=)`, `(>)`, `(>=)`, `max`, `min`, `(+)`, `(-)`, `(*)`, `negate`, `abs`,
`signum`, `toRational`, `quot`, `rem`, `div`, `mod`, `quotRem`, `divMod`,
and `toInteger`.
Built-in `Show Int`, `Show Bool`, `Show Char`, exact `Show String`, and
generated structural list `Show` cover `showsPrec`, `show`, `showList`,
`shows`, and `print` for the supported scalar/string/list executable subset.
Derived `Bounded` dictionaries now cover
all-nullary enumerations plus single-constructor products, records, and
newtypes with field-wise `minBound`/`maxBound` calls.
`fromInteger` is part of the executable `Num Int` dictionary, integer literals
elaborate through it, and ambiguous numeric constraints default to `Int`,
including the supported `Real`/`Integral` superclass hierarchy.
The current monomorphism-restriction decision is documented for the executable
subset: unsigned nullary value bindings without signatures can default direct
standard-class constraints before generalization, while signed bindings and
functions with value parameters are protected from that defaulting pass.
Type constructors now carry explicit `*`/arrow-kind metadata, and source type
expressions are kind-inferred/checked for signatures, constructor fields,
constraints, and supported built-in/user constructors; partial type-constructor
use is rejected before Core generation. Type synonyms are kind-inferred,
cycle-checked, and expanded through signatures, constructor fields,
constraints, instance heads, and default declarations before Core conversion.
Class constraints use an explicit class-head-plus-argument-list representation;
the supported executable slice accepts one argument per class constraint, rejects
malformed arity directly, kind-checks higher-kinded class arguments for built-in
classes such as `Monad`, and carries normalized constraint arguments through
defaulting and dictionary elaboration. Unsupported class-constraint positions
now use a structured placeholder diagnostic for method-specific constraints,
instance contexts, and expression type-signature constraints, so broader class
features remain planned without silent fallback.
`/` remains checked concrete `Int` division; derived `Show` is implemented with
Report-shaped `showsPrec`/`show`/`showList` methods for the executable
data/newtype subset, derived `Enum` is implemented for
nullary-constructor data declarations with report-shaped constructor ordering
and bounds behavior, and derived `Bounded` is implemented for the eligible
Haskell 2010 constructor shapes.

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
Core evaluation also covers guarded RHS/as-pattern programs and operator
sections, including lazy Boolean sections. It reports guard fallthrough as a
no-matching-alternative runtime error.
Core evaluation covers `Char` literals, literal `Char` cases, and `Eq Char`
dictionary calls in the executable subset.
It now models IO output and result values for `putStrLn`, `print`, `getLine`,
`return`, `(>>)`, `(>>=)`, `fail`, and Monad-backed expression/bind-statement
`do` sequencing so Core remains the oracle for native
`main :: IO ()` execution.

This is a reference oracle for the native path. Haskell 2010 type diagnostics
now preserve spans from the parsed AST through renaming and typechecking, and
delayed dictionary-resolution failures retain the expression or source type that
created the class constraint.

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
constructor closures. Native STG heap allocations now pass through the
`hegglog_hs_alloc_process_lifetime` runtime helper, making the current no-GC,
no-free ownership policy explicit and tested. The first IO action layer is
implemented for
line-oriented programs: STG can represent and evaluate IO output actions,
IO-typed thunks are single-entry so effects are not cached, native `getLine`
reads stdin into list-backed strings, `failIO#` aborts the current action, and
native `main :: IO ()` forces the compiled action instead of auto-printing a
scalar root.

## What Core Optimizes Today

The Haskell 2010 native path now runs a typed Core Egglog optimizer before
STG lowering unless `--no-egglog` is selected. The implemented adapter supports
safe Core-0 `Int`/`Bool` fragments, including checked constant folding, safe
arithmetic identities, known Bool case selection, typed Core extraction,
post-extraction Core validation, and provenance reporting. It also supports
known literal case selection and saturated known-constructor case/projection
for ADT/list/tuple/dictionary-shaped Core, with selected-Core validation before
the rewrite is accepted. It deliberately skips lazy-sensitive or unsupported
Core shapes instead of forcing a rewrite.

The optimizer is tested against Core evaluation, lowered STG evaluation, and
native LLVM execution in both default and `--no-egglog` modes. Tests also cover
lazy let preservation and a strict-bottom case where `x * 0` must not erase a
forced division by zero, plus constructor projection over an unused lazy field
and over a forced field that must still report division by zero.

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

Record field labels are implemented for the executable ADT subset. The parser
and renamer preserve labelled constructor declarations, complete record
construction, and record patterns; the typechecker emits selector functions as
Core bindings; and the native wet path includes a record selector/construction
example. Record updates are now parsed, renamed, typechecked, lowered through
Core/STG, and covered by native plus negative conformance fixtures; partial
record construction is still tracked as future surface semantics.

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
   as oracle. Completed for the safe Core-0 `Int`/`Bool` fragment and expanded
   to known literal and saturated known-constructor case/projection rewrites.
10. Broader ADT and pattern-match Core support. Completed for custom ADTs,
    newtype typing through the current boxed representation, polymorphic
    constructors, constructor cases, nested constructor patterns, lazy
    constructor fields, STG lowering/evaluation, native LLVM execution, and
    wet-tested default/no-egglog CLI runs.
11. Prelude Bool/list/tuple runtime expansion. Completed for built-in list,
    tuple, unit, `Maybe`, `Either`, and `Ordering` constructors/types,
    short-circuit Bool operators, generated Core Prelude bindings for `id`,
    `const`, `not`, `otherwise`, `($)`, `(.)`, `flip`, `map`, `foldr`,
    `foldl`, `head`, `tail`, `null`, `fst`, `snd`, `length`, `filter`,
    `reverse`, and `(++)`, STG lowering/evaluation, native LLVM execution, and wet-tested
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
    `Eq Bool`, `Eq Char`, `Ord Int`, `Ord Bool`, `Ord Char`, executable `Num Int`,
    executable `Real Int`, executable `Integral Int`, Report-shaped `Show Int`,
    `Show Bool`, `Show Char`, exact `Show String`, and generated
    structural list `Show` methods,
    including generated built-in dictionaries/selectors, overloaded
    comparison/arithmetic/show method desugaring, Core/STG lowering/evaluation,
    native LLVM execution, and wet-tested default/no-egglog CLI runs.
    `fromInteger`, overloaded integer literals, and numeric defaulting are now
    covered for the executable `Int` numeric universe, including numeric-list
    defaulting for `show [1, 2, 3]`.
15. Guarded RHS/case alternatives and as-pattern aliases. Completed for
    multi-branch guarded function RHSs, guarded constructor/list/as-pattern case
    alternatives, alias bindings for as-patterns in parameters and case
    alternatives, Core/STG no-matching-alternative behavior for guard
    fallthrough, native empty-case lowering, and wet-tested default/no-egglog
    CLI runs. Irrefutable/lazy patterns are implemented for the executable
    subset; source-spanned non-exhaustive/redundant pattern-match warnings are
    exposed by the typechecker, native API, and compile CLI for the supported
    finite executable subset.
16. IO printing/input and `Show` bootstrap. Completed for `IO`, `main :: IO ()`,
    `putStrLn`, `getLine`, `print`, `return`, `(>>)`, `(>>=)`, expression and bind-statement
    `do` sequencing with local `let`, broadened Report-shaped `Show`, Core/STG output/result oracles,
    source strings and built-in show results as list-of-`Char` output, native stdin line input, and
    wet-tested default/no-egglog CLI runs.
17. Numeric literals and defaulting. Completed for dictionary-backed
    `fromInteger`, overloaded integer literals, default declarations that map
    the supported default set to executable `Int`, ambiguous numeric defaulting
    for `Eq`/`Ord`/`Num`/`Show` constraints, derived `Eq`/`Ord`/`Show`, inferred constrained helper
    schemes, SCC-based binding generalization, Core/STG/native IO output
    oracles, and default/no-egglog wet tests.
18. Modules and whole-program compilation. Completed for same-directory
    dependency-file loading from import declarations, module graph cycle and
    name-mismatch diagnostics, module-aware renaming with actual exported
    names, export/import filtering, hiding, qualified aliases, `Thing(..)`
    child exports/imports, whole-program Core flattening for the executable
    subset, root-module `main` native entrypoint selection, Core/STG/native
    oracles, and default/no-egglog wet tests.
19. Egglog Core optimizer known-constructor expansion. Completed for known
    literal case selection, saturated known-constructor case selection, and
    constructor-field projection for ADT/list/tuple/dictionary-shaped Core,
    with selected-Core validation, provenance, Core/STG/native oracles,
    optimized/unoptimized native agreement, unused lazy-field preservation, and
    forced field-bottom preservation.
20. Char runtime representation. Completed for boxed native `Char` values,
    literal `Char` case dispatch, built-in `Eq Char` dictionaries,
    Core/STG/native oracles, scalar `main :: Char` printing, conformance
    fixtures, and default/no-egglog wet tests.
21. `String = [Char]` source/runtime alignment. Completed for source string
    literals, string literal patterns, Core/STG list-of-`Char` evaluator
    values, built-in `show` results as lists, native LLVM list construction
    without per-literal string globals, conformance fixtures, and
    default/no-egglog wet tests.
22. String literal native wet tests. Completed for direct string literal
    output, list functions over strings, `putStrLn` over built-in `show`
    results, explicit `Char` cons patterns, string literal patterns,
    conformance fixtures, default/no-egglog runs, and emit-LLVM wet checks.
23. Derived `Enum`. Completed for nullary-constructor data declarations with
    declaration-order constructor indices, generated `succ`, `pred`, `toEnum`,
    `fromEnum`, range methods, report-shaped runtime bounds errors, invalid
    field-constructor diagnostics, Core/STG/native oracles, conformance
    fixtures, and default/no-egglog wet tests.
24. Derived `Bounded`. Completed for all-nullary enumerations and
    single-constructor product, record, and newtype declarations, with
    first/last constructor bounds, field-wise `minBound`/`maxBound` calls,
    invalid mixed-constructor diagnostics, Core/STG/native oracles,
    conformance fixtures, and default/no-egglog wet tests.

## Where Egglog Fits

The existing ANF Egglog backend is now reused by a typed Haskell 2010 Core
adapter for safe Core-0 fragments. The adapter preserves laziness, bottom, and
runtime-error behavior by validating Core before and after extraction and by
omitting unsafe rewrites unless the fragment has facts strong enough to justify
them. The Core optimizer also selects known literal and saturated
known-constructor alternatives directly for ADT/list/tuple/dictionary-shaped
Core, validating the selected Core and preserving lazy unused fields and forced
field bottom. Broader dictionary simplification, strictness facts, and full
Core-native equality saturation remain later Phase 15 expansion work.

## Where LLVM/Native Output Fits

Native executable output exists for the current `.hg` supported subset and for
the current Haskell 2010 executable subset. The Haskell 2010 path lowers typed
Core to STG-like lazy IR, emits a boxed lazy LLVM runtime with closure
allocation through a process-lifetime runtime helper, enter/apply, thunk
forcing/update, Bool and user-constructor case dispatch, list/tuple/Prelude
constructor dispatch, boxed constructor fields,
recursive closure/thunk groups, user and built-in type class dictionary
constructor/selector execution, guarded RHS/as-pattern programs, empty-case
guard-fallthrough aborts, `putStrLn`/`print` output for `IO ()` programs with
source string literals as list-of-`Char` values, do-bind continuations, explicit
`(>>=)`, boxed `Char` values, `Eq Char`/`Ord Char`
primitive lowering, scalar `Char` root printing, built-in
`Show Int`/`Show Bool`/`Show Char`/`Show String`/list results as lists,
derived `Enum` dictionary calls, derived-enumeration ranges, derived `Bounded`
dictionary calls, checked
primitives, executable list comprehensions, and invokes clang to produce native
machine-code executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Focus

The authoritative queue is maintained in `docs/haskell2010-todo.md` and
validated against `docs/haskell2010-todo.json`. The source surface closure
tasks SURFACE-001, SURFACE-002, and SURFACE-003 are complete.
DIAG-009 pattern-match diagnostics, TEST-CONF-013 source-surface negative
fixtures, TEST-CONF-014 source matrix closure, and ADT-007 record updates are
complete and covered by focused tests/conformance fixtures.
Already-completed typeclass expansion work, including
superclass dictionaries, default methods, overlap rejection, public
`Enum`/`Bounded`, derived `Enum`/`Bounded`, numeric defaulting, the supported `Monad` class surface, and
MOD-009 instance import/export behavior should be preserved as regression
baseline while those tasks proceed.
