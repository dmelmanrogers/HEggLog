# HeggLog Roadmap

The authoritative project roadmap is now
[HeggLog Roadmap: Haskell 2010 Native Compiler](haskell2010-roadmap.md).

## Active Target

HeggLog is a Haskell 2010 native compiler project implemented in Haskell. The
active target is Haskell 2010 source compiled to native machine-code
executables through LLVM and clang.

The current strict `.hg` compiler is the backend/middle-end substrate and
regression baseline. It is not the final source-language endpoint. The Haskell
2010 path now compiles the documented executable subset, while the full
Haskell 2010 surface remains roadmap work.

## Current `.hg` Compiler Baseline

Implemented and tested for the current `.hg` compiler-supported subset:

- parser, typechecker, and report/interpreter mode
- ANF and resolved ANF
- Egglog backend for supported typed strict ANF fragments
- checked signed `Int64` semantics
- ordered top-level first-order functions
- lambda lifting for eligible non-capturing lambdas
- closure conversion for supported local function values
- Backend IR and LLVM IR generation
- native executable output through `clang`
- mandatory end-to-end wet tests of native artifacts
- CI build/test/package checks and wet-test execution

For the detailed current support matrix, see
[current-capabilities.md](current-capabilities.md).

## Haskell 2010 Tracking Docs

- [Haskell 2010 roadmap](haskell2010-roadmap.md)
- [Haskell 2010 engineering backlog](haskell2010-todo.md)
- [Haskell 2010 conformance matrix](haskell2010-conformance-matrix.md)
- [Haskell 2010 implementation plan](haskell2010-implementation-plan.md)
- [Haskell 2010 frontend specification](haskell2010-frontend-spec.md)
- [Haskell 2010 standard library layout](haskell2010-standard-library-layout.md)
- [Haskell 2010 FFI design](haskell2010-ffi-design.md)
- [Laziness and STG plan](laziness-and-stg-plan.md)
- [Egglog Core optimizer plan](egglog-core-optimizer-plan.md)

## Immediate Next Tasks

The authoritative queue is the Haskell 2010 task tracker. The source-surface
chunk is complete: SURFACE-001, SURFACE-002, and SURFACE-003 are implemented
and covered by parser/renamer/Core/STG/native tests plus manifest fixtures.
The next chunk is Prelude, deriving, and typeclass library completion.

TEST-CONF-014 source matrix closure is complete and now enforced by the
conformance validator.

The next library chunk is the numbered LIB follow-ups from TEST-CONF-015;
TC-029 is complete for Report-shaped `Show`, and TC-030 is complete for
Report-shaped `Read`.
PRELUDE-019 is complete for the current high-value function slice, and
PRELUDE-020 is complete for the current generated standard-library module
interface slice. TEST-CONF-015 is complete: Chapter 9 Prelude and the Part II
Haskell 2010 Libraries module inventory are reconciled against manifest-backed
coverage and numbered remaining tasks. FFI-010 is complete for floating-point
FFI marshalling across static calls, dynamic calls, wrapper callbacks, and
foreign export entrypoints. FFI-011 is complete for FFI link metadata and
explicit native link inputs. FFI-012 is complete for explicit wrapper
callback/finalizer lifetime behavior: `freeHaskellFunPtr`, slot reclamation,
callback-after-free rejection, idempotent double-free, and reverse-order manual
ForeignPtr finalization are covered. Remaining FFI closure is the
FFI-013-documented errno, Storable, allocation, array, and C-string library gaps.

Completed Haskell 2010 roadmap work:

- MOD-009 instance import/export behavior: implemented with source instance
  propagation through `ModuleInterface`, empty export-list and `import M ()`
  visibility, transitive import-chain dictionary availability, native
  conformance coverage, and a negative missing-instance import fixture.
- PRELUDE-017 standard library module layout: implemented with a dedicated
  `Haskell2010.StandardLibrary` module, generated/importable `Prelude`
  interface, shared `ModuleInterface` data model, and instance-export boundary
  used by MOD-009.
- PRELUDE-020 standard library module expansion: implemented with generated
  importable interfaces for `Control.Monad`, `Data.Int`, `Data.List`,
  `Data.Maybe`, `Data.Word`, `System.IO`, and implemented `Foreign.*` module
  slices, including real `Functor(fmap)` support for `[]`, `Maybe`, and `IO`,
  while keeping reserved Report modules unimportable until they have real
  support.
- FFI-013 Foreign library surface completion: implemented for the current
  runtime-supported `Foreign.Ptr`, `Foreign.ForeignPtr`, `Foreign.Marshal`,
  `Foreign.Marshal.Error`, and `Foreign.Marshal.Utils` slices with native
  fixture coverage, while keeping errno, Storable, raw allocation, array
  marshalling, and C string marshalling functions explicit as pending gaps.
- FFI-012 callback and finalizer lifetime completion: implemented
  `freeHaskellFunPtr`, reclaimable wrapper callback slots, idempotent
  double-free for wrapper pointers, callback-after-free runtime failure, and
  explicit reverse-order/idempotent ForeignPtr finalization under the
  process-lifetime runtime model.
- FFI-011 FFI link metadata: implemented with native-result link metadata,
  emitted LLVM comments for headers/imports/addresses/exports, CLI link flags,
  toolchain propagation to clang, and conformance harness link-object coverage.
- PRELUDE-002/MOD-010 implicit Prelude import behavior: implemented with
  synthetic `import Prelude` insertion only when no explicit `Prelude` import
  exists, explicit Prelude import-list/hiding/qualified filtering, and native
  conformance coverage for implicit, explicit, and qualified Prelude imports.
- TC-020 Monad class surface: implemented for the supported executable subset
  with higher-kinded `Monad`, dictionaries for `IO`/`Maybe`/`[]`, generic
  `do` desugaring, refutable do-bind `fail`, and native conformance coverage.
- Haskell 2010 parser/layout MVP: implemented as an isolated `Haskell2010`
  frontend AST, lexer, layout parser, parser, and parser tests.
- Haskell 2010 renamer MVP: implemented as an isolated unique-name pass with
  lexical scopes, namespace separation, duplicate/unbound diagnostics, explicit
  import ambiguity checks, and fixity resolution.
- Haskell 2010 typed Core MVP: implemented as an isolated typed Core IR with
  expression type metadata, primitive operations, constructors, lambdas,
  type abstractions/applications, applications, nonrecursive and recursive
  lets, cases, a validator, free-variable analysis, capture-aware
  substitution, pretty-printing, and unit tests.
- Haskell 2010 Core-0 typechecker/desugarer MVP: implemented as a renamed AST
  to typed Core pass for `Int`, `Bool`, explicit signatures, HM
  generalization/instantiation, top-level functions, lambdas, application,
  local `let`, `if`, Bool `case`, and primitive arithmetic/comparison.
- Haskell 2010 Core-0 reference evaluator: implemented as a validating typed
  Core evaluator with lazy let/function argument thunks, erased Core type
  abstraction/application, Bool case execution, checked `Int` primitives, and
  structured runtime errors.
- Haskell 2010 Lazy/STG runtime MVP: implemented as an isolated STG-like IR,
  validator, and pure heap evaluator with function closures, updateable and
  single-entry thunk closures, constructor closures, `let`/`letrec`, case
  demand, sharing, black-hole detection, Bool constructor dispatch, and checked
  primitive runtime errors.
- Haskell 2010 Core-to-STG lowering MVP: implemented as a validating lowering
  pass from typed Core-0 modules to STG, with Core type erasure, curried
  function lowering, thunked non-atomic operands/intermediate applications,
  `let`/`letrec`, Bool cases, primitive operations, and STG evaluator
  preservation tests.
- Haskell 2010 native executable path for the first Core-0 slice: implemented
  as boxed STG-to-LLVM lowering with closure allocation, thunk forcing/update,
  enter/apply, Bool case dispatch, checked primitive aborts, `.hs`
  compile-mode integration, and native wet tests for arithmetic, polymorphism,
  laziness, partial application, Bool case, and forced division-by-zero failure.
- Haskell 2010 Egglog Core optimizer: implemented for safe typed Core-0
  `Int`/`Bool` fragments with checked constant folding, safe arithmetic
  identities, known Bool case selection, typed Core extraction/validation,
  provenance, `--no-egglog` native comparison, and Core/STG/native oracle
  tests preserving laziness and forced runtime errors. Expanded with known
  literal and saturated known-constructor case/projection rewrites for
  ADT/list/tuple/dictionary-shaped Core, including unused lazy-field and forced
  field-bottom preservation.
- Haskell 2010 ADT and pattern-match Core support: implemented for custom
  `data` declarations, polymorphic constructors, constructor cases, nested
  constructor patterns, lazy constructor fields, Core/STG validation, native
  boxed constructor objects, and default/no-egglog wet tests for custom ADTs and
  `Maybe`.
- Haskell 2010 Prelude Bool/list/tuple runtime expansion: implemented for
  built-in list, tuple, unit, `Maybe`, `Either`, and `Ordering`
  constructors/types, list and tuple expressions/patterns, short-circuiting
  Bool operators, and generated Core Prelude bindings for `id`, `const`, `not`,
  `otherwise`, `($)`, `(.)`, `flip`, `map`, `foldr`, `foldl`, `head`, `tail`,
  `null`, `fst`, `snd`, `length`, `filter`, `reverse`, and `(++)`.
- Haskell 2010 recursion coverage: implemented for singleton self-recursive
  top-level/local bindings, mutually recursive functions, fibonacci/factorial
  programs, cons-pattern recursive list functions, and default/no-egglog native
  wet tests.
- Haskell 2010 type class dictionary representation: implemented for
  user-defined single-parameter classes, concrete instances, explicit
  constrained functions, generated dictionary constructors/selectors, Core
  dictionary arguments, STG/native lowering, and default/no-egglog wet tests.
- Haskell 2010 built-in Prelude class dictionaries: implemented for `Eq Int`,
  `Eq Bool`, `Eq Char`, `Ord Int`, `Ord Bool`, `Ord Char`, executable `Num Int`,
  executable `Real Int`, executable `Integral Int`, Report-shaped `Show Int`,
  `Show Bool`, `Show Char`, exact `Show String`, and generated
  structural list `Show` methods, including overloaded comparison/arithmetic/show method
  desugaring, Core/STG/native lowering, and default/no-egglog wet tests.
- Haskell 2010 numeric literals/defaulting: implemented for dictionary-backed
  `fromInteger`, overloaded integer literals, executable `Int` numeric
  defaulting, inferred constrained helper schemes, SCC-based binding
  generalization, Core/STG/native lowering, and default/no-egglog wet tests.
- Haskell 2010 `Char` runtime representation: implemented for boxed native
  `Char` values, literal `Char` case dispatch, built-in `Eq Char`, scalar
  `main :: Char` printing, Core/STG/native oracles, conformance fixtures, and
  default/no-egglog wet tests.
- Haskell 2010 `String = [Char]` source/runtime alignment: implemented for
  source string expressions and string literal patterns as ordinary list
  constructors, Core/STG evaluator list values, built-in `show` results as
  lists, native LLVM without per-literal string globals, conformance fixtures,
  and default/no-egglog wet tests.
- Haskell 2010 string literal native wet tests: implemented direct source
  string output, `reverse`/`length` over strings, `putStrLn` over built-in
  `show` results, explicit `Char` cons patterns, string literal patterns,
  conformance fixtures, default/no-egglog runs, and emit-LLVM wet checks.
- Haskell 2010 modules/whole-program compilation: implemented for import-driven
  dependency-file loading, module graph cycle/name diagnostics, actual
  exported-name import resolution, export/import filtering, hiding, qualified
  aliases, `Thing(..)` children, root `main` selection, and default/no-egglog
  multi-file native wet tests.
- Haskell 2010 guarded RHS/case alternatives and as-patterns: implemented for
  multi-branch guards, guards after constructor/list/tuple/as-pattern case
  alternatives, as-pattern aliases in parameters and case patterns, Core/STG
  no-matching-alternative behavior for guard fallthrough, native empty-case
  lowering, and default/no-egglog wet tests. Irrefutable/lazy pattern semantics
  are implemented for the executable subset; richer source-spanned pattern
  diagnostics remain planned.
- Haskell 2010 IO printing slice: implemented `IO` typechecking and native
  `main :: IO ()` entrypoint execution, `putStrLn`, `print`, `return`, `(>>)`,
  `(>>=)`, expression and bind-statement `do` sequencing with local `let`, broadened built-in
  `Show` dictionaries, Core/STG IO output/result reference values, source strings and
  built-in show results as list-of-`Char` values, and default/no-egglog wet
  tests.
- Haskell 2010 arithmetic sequences: implemented executable `Int` and `Char`
  sequence forms plus derived-enumeration ranges, including bounded
  ascending/descending ranges and lazily consumed open ranges, through Core,
  STG, LLVM, conformance, and wet tests.
- Haskell 2010 derived `Enum`: implemented generated `Enum` dictionaries for
  nullary-constructor data declarations, declaration-order constructor indices,
  `succ`/`pred`/`toEnum` bounds errors, `fromEnum`, range methods, negative
  invalid-deriving diagnostics, conformance fixtures, and default/no-egglog wet
  tests.
- Haskell 2010 derived `Bounded`: implemented generated `Bounded`
  dictionaries for all-nullary enumerations and single-constructor products,
  records, and newtypes, with field-wise bounds, invalid mixed-constructor
  diagnostics, conformance fixtures, and default/no-egglog wet tests.
- Haskell 2010 list comprehensions: implemented executable list
  comprehensions with generator scoping, Bool guards, `let` qualifiers,
  nested generators, tuple/list/constructor/literal/refutable pattern
  filtering, and native wet tests over `Int`, `Char`, `String`, `Maybe`, and
  tuple-shaped examples.

## Non-Negotiable Project Direction

- The source-language target is Haskell 2010.
- The compiler emits native executables.
- LLVM is the machine-code path.
- Egglog optimization remains central.
- Laziness must be implemented for Haskell 2010.
- Bottom/runtime-error behavior must be preserved.
- Current `.hg` functionality remains preserved as substrate and regression
  coverage.
- GHC compatibility is not claimed.
