# Haskell 2010 Frontend Specification

## Purpose

The Haskell2010 frontend parses, lays out, renames, and typechecks Haskell 2010
source before desugaring into typed Core.

The parser/layout layer is implemented as an isolated `Haskell2010` frontend
AST, lexer, layout parser, and parser. The renamer is implemented as a
unique-name pass over that AST. A typed Core IR and validator are implemented
as the target representation. A Core-0 typechecker/desugarer is implemented
for the first `Int`/`Bool` subset. The current `.hg` frontend still does not
compile Haskell 2010 source.

## Lexer and Layout

The lexer must recognize Haskell 2010 lexical categories:

- variable identifiers and constructor identifiers
- variable operators and constructor operators
- reserved words and reserved operators
- integer, floating, character, and string literals
- line comments and nested block comments
- explicit braces and semicolons
- virtual braces and semicolons inserted by the layout rule

Layout handling must be indentation-sensitive and must work for modules,
`where`, `let`, `do`, and declaration groups. Explicit braces and semicolons
must override layout where Haskell 2010 permits them.

Error handling requirements:

- invalid characters report source spans
- unterminated comments/strings/chars report source spans
- malformed layout reports the offending indentation or token
- lexer/layout diagnostics are stable enough for golden tests

## Parser

The parser must produce a Haskell 2010 source AST with these categories:

- modules
- imports
- declarations
- expressions
- patterns
- types
- classes and instances
- fixity declarations

The parser may initially accept a Core-0 subset, but every accepted construct
must be tracked in `docs/haskell2010-conformance-matrix.md`. Unsupported
constructs should fail with clear parse or planned-feature diagnostics, not
silently desugar to the wrong language.

## Renamer

The renamer assigns unique names and resolves every occurrence against the
correct namespace.

Current implementation status: the renamer emits a separate renamed AST and
handles lexical scopes, top-level scopes, `let`, `where`, lambda and pattern
scopes, class methods, instance methods, separated term/constructor/type/type
variable/class/module namespaces, duplicate and unbound-name diagnostics,
ambiguous explicit-import diagnostics, qualified explicit imports, and fixity
resolution. Whole-program module loading, open import export discovery, hiding
semantics, and complete Prelude coverage remain later module-system work.

Required namespaces and scopes:

- term variables
- data constructors
- type constructors
- classes
- modules
- top-level declarations
- local `let` and `where` bindings
- lambda binders
- pattern binders
- constructor fields when records are implemented

Required errors:

- duplicate binding
- unbound name
- ambiguous imported name
- invalid shadowing where Haskell forbids it
- invalid fixity declaration or use

Fixity handling belongs at the boundary between parsing and renaming. The
frontend may parse infix expressions as unresolved operator trees, then resolve
precedence and associativity after fixity declarations are known.

## Typechecker

The Haskell 2010 typechecker target is Hindley-Milner inference plus Haskell
2010 class constraints.

Required Core-0 capabilities:

- unification
- occurs check
- generalization
- instantiation
- explicit signatures
- polymorphic let
- recursive binding groups where supported
- source-spanned type errors

Planned Haskell 2010 capabilities:

- class constraints
- instance lookup
- dictionary-passing elaboration
- defaulting for numeric classes
- kind checking for type constructors and classes

The typechecker emits typed Core or rejects the program. It must not accept a
program that later fails only because Core lacks enough type information.

## Desugaring

The desugarer lowers renamed and typechecked Haskell syntax into typed Core.

Required desugarings include:

- `if` to `case`
- `where` to `let`
- function bindings to lambdas and case analysis
- pattern bindings
- guards
- do notation
- list syntax
- tuple syntax
- operator sections
- list comprehensions

Every desugared Core program must validate. Desugaring must preserve source
spans or provenance enough for diagnostics through later phases.

## Current Status

The Haskell2010 parser/layout layer, renamer, isolated typed Core layer, and
Core-0 source-to-Core typechecker/desugarer are implemented. The Core-0
typechecker currently covers explicit signatures, HM
generalization/instantiation, `Int`, `Bool`, top-level functions, lambdas,
application, local `let`, `if`, Bool `case`, and primitive
arithmetic/comparison. Full Haskell 2010 type classes, ADTs, broad pattern
matching, and executable lowering remain planned. The current
compiler-supported executable source language is still the strict `.hg` subset
documented in `docs/language-spec.md`. That strict frontend is useful substrate
and regression coverage, but it is not Haskell 2010:

- `.hg` has no layout rule
- `.hg` has no modules/imports
- `.hg` has no ADTs or pattern matching
- `.hg` has strict call-by-value evaluation
- `.hg` has no type classes or Prelude

Haskell 2010 implementation progress is tracked in
`docs/haskell2010-conformance-matrix.md`.
