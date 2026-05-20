# Haskell 2010 Implementation Plan

This document translates the Haskell 2010 roadmap into concrete module
boundaries and acceptance tests. Haskell 2010 source compilation now exists for
the documented executable subset; the remaining items track the path to broader
Haskell 2010 coverage.

## Source Layout

Frontend modules:

```text
src/Haskell2010/
  Syntax.hs
  Lexer.hs
  Layout.hs
  Parser.hs
  Pretty.hs
  Names.hs
  Renamed.hs
  Renamer.hs
  Typecheck.hs
  Infer.hs
  Desugar.hs
```

Implemented today: `Syntax`, `Lexer`, `Layout`, `Parser`, `Pretty`, `Names`,
`Renamed`, `Renamer`, and a `Typecheck` source-to-Core pass for the current
executable subset, including custom ADTs, constructor patterns, lists, tuples,
generated Core Prelude bindings for basic list/Bool functions, and recursive
top-level/local binding groups, plus initial user-defined single-parameter
type class dictionaries, built-in `Eq`/`Ord`/`Num` dictionaries, guarded RHSs,
guarded case alternatives, and as-pattern aliases. Broader
inference/desugaring modules for full Haskell 2010 remain planned.

Implemented Core modules:

```text
src/Haskell2010/Core/
  Syntax.hs
  Eval.hs
  Validate.hs
  Pretty.hs
  FreeVars.hs
  Subst.hs
```

Core types live in `Haskell2010.Core.Syntax` for the current MVP. The reference
evaluator in `Haskell2010.Core.Eval` executes validated typed Core, including
user ADT constructors, list/tuple/Prelude constructors, generated Prelude list
functions, recursive functions, lazy fields, and dictionary-passed user class
method calls, plus guarded RHS/as-pattern programs and guard-fallthrough
no-match errors, as the oracle for STG/native work.

Implemented STG modules:

```text
src/Haskell2010/STG/
  Syntax.hs
  Eval.hs
  Lower.hs
  Validate.hs
```

Proposed STG modules:

```text
src/Haskell2010/STG/
  Pretty.hs
```

Proposed runtime files:

```text
src/Runtime/ or runtime/
  hegglog_rts.c
  hegglog_rts.h
```

Implemented Core Egglog adapter:

```text
src/Optimize/CoreEgglog.hs
```

It currently adapts safe typed Core-0 `Int`/`Bool` fragments to the existing
ANF Egglog backend, decodes extracted ANF back into validating typed Core, and
records selected rewrite provenance. Splitting this module into schema,
encoding, facts, rules, and extraction submodules remains useful once ADTs,
dictionaries, strictness facts, and broader Core rewrites are added.

The existing `.hg` modules remain intact and isolated while Haskell 2010 support
is built alongside them.

## Milestone Build Order

1. Parser/layout.
2. Renamer.
3. Core IR. Completed.
4. Core validator. Completed.
5. Core-0 typechecker/desugarer. Completed.
6. Core evaluator. Completed.
7. STG IR. Completed.
8. Lazy runtime. Completed.
9. Core-to-STG lowering. Completed.
10. STG-to-LLVM. Completed for the current executable subset.
11. ADTs/pattern matching. Completed for custom ADTs, polymorphic constructors,
    constructor cases, nested constructor patterns, lazy constructor fields,
    Core/STG/native execution, and wet-tested default/no-egglog CLI runs.
12. Lists, tuples, and Prelude Core. Completed for built-in list, tuple, unit,
    `Maybe`, `Either`, and `Ordering` constructors/types, list and tuple
    expressions/patterns, short-circuit Bool operators, generated Core Prelude
    bindings for `id`, `const`, `not`, `otherwise`, `map`, `foldr`, `length`,
    `filter`, `reverse`, and `(++)`, Core/STG/native execution, and wet-tested
    default/no-egglog CLI runs.
13. Recursion. Completed for singleton self-recursive bindings, mutually
    recursive top-level groups, local recursive `let`, fibonacci/factorial
    programs, recursive list functions with cons patterns, Core/STG/native
    execution, and wet-tested default/no-egglog CLI runs.
14. Type classes/dictionaries. Completed for user-defined single-parameter
    classes, concrete context-free instances, structured explicit constraints,
    structured placeholder diagnostics for unsupported constraint contexts,
    generated dictionary constructors/selectors, built-in `Eq Int`, `Eq Bool`,
    `Eq Char`, `Ord Int`, `Ord Bool`, executable `Num Int`, `Show Int`,
    `Show Bool`, `Show Char`, exact `Show String`, and generated structural
    list `Show` dictionaries, derived `Eq`/`Ord`/`Show` dictionaries for supported
    data/newtype declarations, structural list `Eq`, and structural list `Ord`,
    source-spanned typecheck diagnostics including delayed class-constraint
    dictionary failures,
    documented executable-subset monomorphism/defaulting behavior,
    Core/STG/native execution, and wet-tested default/no-egglog CLI runs.
    Instance contexts, derived `Read`, the full `showsPrec`/`showList` hierarchy,
    and additional numeric classes remain planned.
15. Guarded RHS/case alternatives and as-pattern aliases. Completed for
    multi-branch guards, guarded case alternatives, as-pattern alias binding,
    Core/STG/native no-match behavior for guard fallthrough, and wet-tested
    default/no-egglog CLI runs.
16. IO printing and `Show` bootstrap. Completed for `IO`, `main :: IO ()`,
    `putStrLn`, `print`, `return`, `(>>)`, `(>>=)`, expression and bind-statement
    `do` sequencing with local `let`, Core/STG/native execution, and wet-tested
    default/no-egglog CLI runs.
17. Numeric literals and defaulting. Completed for dictionary-backed
    `fromInteger`, overloaded integer literals, executable `Int` defaulting,
    inferred constrained helper schemes, SCC-based binding generalization,
    Core/STG/native execution, and wet-tested default/no-egglog CLI runs.
18. Modules. Completed for dependency-file loading from import declarations,
    module graph cycle detection, module-aware renaming with actual exported
    names, explicit export filtering including `Thing(..)` children, hiding,
    qualified aliases, whole-program Core flattening for the executable subset,
    root-module `main` selection, Core/STG/native execution, and wet-tested
    default/no-egglog CLI runs.
19. Egglog Core optimizer. Completed for the first safe Core-0 fragment and
    expanded with known literal and saturated known-constructor case/projection
    rewrites for ADT/list/tuple/dictionary-shaped Core. The optimizer validates
    selected Core, records provenance, preserves unused lazy fields and forced
    field bottom, and is checked by Core/STG/native optimized-vs-unoptimized
    tests. Broader dictionary simplification, strictness facts, and full
    Core-native equality saturation remain planned.

## Tests Required Per Milestone

### Parser/Layout

- Unit tests: token classes, reserved words, comments, explicit braces,
  semicolons, layout insertion, and malformed layout.
- Negative tests: invalid indentation, invalid lexical forms, bad declarations.
- Golden tests: parse/render snapshots for representative modules.
- Property tests: pretty/parse round trips for a conservative AST subset.
- Wet tests: not required until executable pipeline exists, but parser CLI
  diagnostics should be process-tested when `check` exists.
- Conformance matrix: update every parsed feature row from `not started`.

### Renamer

- Unit tests: lexical scope, module scope, constructor/type/class namespaces,
  duplicate binders, unbound names, pattern scope, and fixity resolution.
- Negative tests: ambiguous names, duplicate definitions, missing imports.
- Golden tests: renamed AST with stable unique names.
- Property tests: every resolved occurrence points to an in-scope binder.
- Wet tests: CLI diagnostic checks for unbound/duplicate names.
- Conformance matrix: update renamer columns.

### Core IR and Validator

- Unit tests: Core constructors, type annotations, free variables, substitution,
  and alpha-stability.
- Negative tests: unbound variables, duplicate binders, bad primitive types,
  bad constructor arity, and inconsistent case alternatives.
- Golden tests: Core pretty output.
- Property tests: substitution preserves validation for generated well-typed
  fragments.
- Wet tests: not until Core lowers to executable code.
- Conformance matrix: update Core columns only for features that actually
  desugar.

### Desugarer

- Unit tests: function bindings, where-to-let, if-to-case, pattern bindings,
  guards, sections, tuples, lists, and do notation as each is implemented.
- Negative tests: unsupported surface forms must fail before invalid Core.
- Golden tests: source-to-Core snapshots.
- Property tests: generated desugared Core validates.
- Wet tests: once Core execution exists, compare desugared and source
  semantics for representative programs.
- Conformance matrix: mark rows `desugared to Core` only with tests.

### HM Typechecker

- Unit tests: unification, occurs check, generalization, instantiation,
  signatures, polymorphic let, recursive groups, and constraint generation.
- Negative tests: type mismatch, infinite types, ambiguous types, bad
  signatures, and scope-sensitive pattern errors.
- Golden tests: type diagnostics with spans.
- Property tests: generated typed Core validates.
- Wet tests: successful Core-0 programs compile/run; ill-typed programs fail
  with diagnostic category checks.
- Conformance matrix: update typechecker columns.

### Core Evaluator

- Unit tests: Core evaluation for Core-0, primitive errors, case, letrec, and
  constructor evaluation.
- Negative tests: invalid Core rejected by validator.
- Golden tests: reference outputs for small examples.
- Property tests: desugared source and Core evaluator agree where both exist.
- Wet tests: use Core evaluator as oracle for early native tests.
- Conformance matrix: no row moves past Core without execution tests.

### STG IR and Lazy Runtime

- Unit tests: thunk allocation, enter/force/update, constructor closure layout,
  case demand, letrec, sharing, and black-hole behavior.
- Negative tests: invalid STG rejected by validator.
- Golden tests: STG pretty output.
- Property tests: Core-to-STG generated programs preserve reference results.
- Wet tests: laziness examples compile to native and run.
- Conformance matrix: update STG/runtime columns.

### STG-to-LLVM

- Unit tests: closure layout lowering, enter/apply convention, case dispatch,
  constructor tags, runtime calls, and primitive lowering.
- Negative tests: missing runtime link, invalid STG, invalid LLVM.
- Golden tests: selected LLVM IR.
- Property tests: generated small STG fragments validate after lowering.
- Wet tests: `hegglog compile Main.hs -o main` plus direct executable runs.
- Conformance matrix: update LLVM/native columns only after native tests pass.

### ADTs, Recursion, Prelude, Type Classes, IO, Modules

- Unit tests: one layer below the feature surface and one layer at the user
  syntax boundary.
- Negative tests: malformed declarations, bad scopes, bad types, missing
  instances/imports, and runtime errors.
- Golden tests: diagnostics and selected Core/STG dumps.
- Property tests: validators and preservation checks for generated fragments.
- Wet tests: feature-level `.hs` files compiled to native executables.
- Conformance matrix: every implemented feature row links to test coverage or
  a documented deviation.

### Egglog Core Optimizer

- Unit tests: Core schema, facts, rules, extraction, and provenance.
- Negative tests: unsafe rewrites blocked by missing totality/no-error facts.
- Golden tests: optimized Core and provenance snapshots.
- Property tests: optimized Core validates and preserves reference semantics.
- Wet tests: optimized and `--no-egglog` native executables agree.
- Conformance matrix: optimizer status is separate from frontend conformance.

## Integration Boundaries

- `Haskell2010` frontend modules must not depend on LLVM internals.
- Core must not depend on Haskell parser internals.
- The Egglog kernel must remain frontend-independent.
- `Optimize.CoreEgglog` is the Haskell Core adapter to the generic Egglog
  kernel.
- STG/LLVM backend modules must not depend on surface syntax.
- The current `.hg` pipeline remains isolated and continues to serve as a
  regression baseline.
- Native wet tests are the acceptance boundary for executable behavior.
