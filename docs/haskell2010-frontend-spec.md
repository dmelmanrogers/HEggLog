# Haskell 2010 Frontend Specification

## Purpose

The Haskell2010 frontend parses, lays out, renames, and typechecks Haskell 2010
source before desugaring into typed Core.

The parser/layout layer is implemented as an isolated `Haskell2010` frontend
AST, lexer, layout parser, and parser. The renamer is implemented as a
unique-name pass over that AST. A typed Core IR and validator are implemented
as the target representation. The typechecker/desugarer is implemented for the
first executable subset, including custom ADTs, constructor patterns, and
recursive top-level/local bindings, plus initial user-defined type class
dictionary passing. The
current `.hg` frontend remains separate substrate; Haskell 2010 source uses the
`Haskell2010` pipeline.

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
ambiguous explicit-import diagnostics, module-graph import resolution against
actual exported definitions, qualified aliases, hiding, `Thing(..)` child
expansion, and fixity resolution. Complete package search paths and complete
Prelude module coverage remain later module-system work.

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
- record field selectors for labelled constructors

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

Current initial Haskell 2010 class capabilities:

- class constraints represented as a class head plus ordered argument list, with
  the current executable slice validating single-argument arity
- structured placeholder diagnostics for superclass contexts, method-specific
  constraints, instance contexts, and expression type-signature constraints
- source spans preserved through parsed and renamed Haskell 2010 AST nodes for
  typechecker diagnostics, including delayed class-constraint dictionary errors
- instance lookup
- dictionary-passing elaboration
- generated built-in dictionaries for `Eq Int`, `Eq Bool`, `Ord Int`,
  `Ord Bool`, executable `Num Int`, `Show Int`, and `Show Bool`
- dictionary-backed built-in methods: `(==)`, `(/=)`, `compare`, `(<)`,
  `(<=)`, `(>)`, `(>=)`, `max`, `min`, `(+)`, `(-)`, `(*)`, `negate`, `abs`,
  `signum`, `fromInteger`, and `show`
- overloaded integer literals through `fromInteger`
- numeric defaulting to executable `Int` for ambiguous standard-class numeric
  constraints in the supported `Eq`/`Ord`/`Num`/`Show` slice
- executable-subset monomorphism/defaulting policy for unsigned nullary value
  bindings without signatures

Remaining planned Haskell 2010 capabilities:

- superclasses, default methods, deriving, and instance contexts
- broader `Show`, additional numeric classes, and fuller Prelude hierarchy
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
Non-variable pattern bindings lower to lazy selector bindings; when those
selectors are mutually recursive, they participate in the existing Core
recursive binding-group model.

## Current Status

The Haskell2010 parser/layout layer, renamer, isolated typed Core layer, and
source-to-Core typechecker/desugarer are implemented for the first executable
subset. The typechecker currently covers explicit signatures, HM
generalization/instantiation, `Int`, `Bool`, top-level functions, lambdas,
application, local `let`, `if`, Bool and user-constructor `case`, custom
`data` declarations, polymorphic constructors, nested/list/tuple constructor
patterns, list and tuple expressions/types, built-in `Maybe`, `Either`, and
`Ordering`, generated Core Prelude bindings for `id`, `const`, `not`,
`otherwise`, `map`, `foldr`, `length`, `filter`, and `reverse`, short-circuit
Bool operators, recursive top-level/local binding groups, primitive `/`, and
dictionary-backed `Eq`/`Ord`/`Num` methods, guarded RHSs, guarded case
alternatives, as-pattern aliases, and guard-fallthrough no-match behavior. It
also covers the initial type
class dictionary slice: user-defined single-parameter classes, concrete
context-free instances, explicit constrained functions, generated dictionary
constructors/selectors, dictionary-passed method calls, and built-in `Eq Int`,
`Eq Bool`, `Ord Int`, `Ord Bool`, executable `Num Int`, `Show Int`, and
`Show Bool` dictionaries. It also covers `IO`, `main :: IO ()`, `putStrLn`,
`print`, `return`, `(>>)`, and expression-only `do` sequencing with local
`let`. It also covers `fromInteger`, overloaded integer literals, numeric
defaulting to executable `Int`, inferred constrained helper schemes, and
SCC-based binding generalization, and recursive non-variable pattern bindings.
It also covers import-driven dependency-file loading, export/import filtering,
whole-program Core flattening, and root `main` native entrypoint selection for
the executable subset. It exposes structured exhaustiveness warning
placeholders for partial `case`, function, and lambda patterns through the
typechecker and native API. Full Haskell 2010 type classes, broader `Show`, a
full pattern coverage checker, richer pattern diagnostics, broader Prelude, and
broader IO remain planned. The strict
`.hg` frontend is useful substrate and regression coverage, but it is not
Haskell 2010:

- `.hg` has no layout rule
- `.hg` has no modules/imports
- `.hg` has no ADTs or pattern matching
- `.hg` has strict call-by-value evaluation
- `.hg` has no type classes or Prelude

Haskell 2010 implementation progress is tracked in
`docs/haskell2010-conformance-matrix.md`.
