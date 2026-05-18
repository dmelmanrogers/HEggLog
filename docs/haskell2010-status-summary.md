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

HeggLog does not yet compile Haskell 2010 `.hs` source. The following Haskell
2010 requirements are planned but not implemented:

- Haskell Hindley-Milner typechecker
- ADTs and pattern matching
- type classes and dictionary passing
- Prelude/library subset
- Haskell source desugaring beyond the Core-0 `Int`/`Bool` subset
- lazy STG/runtime path
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

This is a source-to-Core milestone only. It does not yet evaluate Core, lower
Core to STG, or compile Haskell 2010 source to native executables. Source-spanned
Haskell 2010 type diagnostics also remain later work because the renamed AST is
currently spanless.

## First Haskell 2010 Implementation Milestones

1. Haskell 2010 parser/layout MVP. Completed.
2. Renamer MVP. Completed.
3. Typed Core MVP. Completed.
4. Core-0 Haskell typechecker/desugarer integration. Completed.
5. Core-0 reference evaluator.
6. Lazy/STG runtime MVP.
7. Egglog Core optimizer implementation after Core has an execution oracle.

## Where Egglog Fits

The existing ANF Egglog backend proves the project can use an Egglog-style
optimizer in the compiler. The Haskell 2010 path will add a typed Core Egglog
adapter that preserves laziness, bottom, and runtime-error behavior.

## Where LLVM/Native Output Fits

Native executable output already exists for the current `.hg` supported subset.
The Haskell 2010 path will lower typed Core to STG-like lazy IR, link a runtime,
emit LLVM IR, and invoke clang to produce native machine-code executables.

## GHC Compatibility

GHC compatibility is not claimed. The initial target is documented Haskell 2010
semantics and explicitly tracked deviations. GHC extensions are excluded
initially.

## Next Immediate Implementation Task

Build a Core-0 reference evaluator while preserving the current `.hg` compiler
and wet-test baseline.
