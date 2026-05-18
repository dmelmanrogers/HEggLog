# Haskell 2010 Conformance Matrix

This matrix tracks the active Haskell 2010 target. Rows marked
`current .hg only` describe infrastructure that exists for the strict `.hg`
substrate but is not yet implemented for Haskell 2010 source.

Status values: `not started`, `current .hg only`, `parsed`, `renamed`,
`typechecked`, `desugared to Core`, `compiled to native`, `wet-tested`,
`complete`, `deferred`, `documented deviation`.

| Haskell 2010 area | Feature | Current status | Planned milestone | Parser | Renamer | Typechecker | Core | STG/runtime | LLVM/native | Tests | Notes/deviations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lexical/layout | identifiers | renamed | Phase 2/3 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Haskell variable and constructor identifiers parse and resolve to unique names. |
| Lexical/layout | operators | renamed | Phase 2/3 | parsed | renamed/fixity-resolved | .hg only | .hg only | .hg only | .hg only | parser and renamer tests | Operators parse as unresolved infix trees and are reassociated by fixity during renaming. |
| Lexical/layout | reserved words | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Haskell reserved words and reserved operators are rejected as identifiers/operators. |
| Lexical/layout | comments | parsed | Phase 2 | parsed | n/a | n/a | n/a | n/a | n/a | parser tests | Line comments and nested block comments are supported by the Haskell2010 lexer. |
| Lexical/layout | layout rule | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Layout blocks parse for modules, `where`, `let`, `do`, and `case`; malformed indentation is rejected. |
| Lexical/layout | numeric literals | parsed | Phase 2/5 | parsed integers | not started | .hg Int only | .hg only | .hg only | .hg only | parser tests | Decimal, hex, and octal integers parse; floating literals and overloading/defaulting are later. |
| Lexical/layout | char literals | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; runtime Char representation is later. |
| Lexical/layout | string literals | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list/Char runtime support is later. |
| Modules | module header | parsed | Phase 2/14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed into `HsModule`; whole-program module resolution is later. |
| Modules | import declarations | renamed | Phase 2/14 | parsed | explicit imports renamed | not started | not started | not started | not started | parser and renamer tests | Explicit import specs create external names; open import export discovery remains later. |
| Modules | export lists | renamed | Phase 14 | parsed | export names resolved | not started | not started | not started | not started | parser and renamer tests | Export name lookup is resolved; visibility checks and `Thing(..)` expansion remain later. |
| Modules | qualified imports | renamed | Phase 14 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Qualified explicit imports resolve to external names. |
| Modules | hiding | parsed | Phase 14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; namespace filtering is later. |
| Modules | aliases | renamed | Phase 14 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Import aliases are available in the module namespace for explicit imports. |
| Modules | module graph | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Cycle detection pending. |
| Declarations | value bindings | renamed | Phase 2/5 | parsed | renamed | .hg monomorphic only | .hg ANF/Core only | .hg strict only | .hg only | parser and renamer tests | Function and pattern bindings get unique names; recursive semantics are later. |
| Declarations | type signatures | renamed | Phase 2/5 | parsed | renamed | .hg monomorphic only | not started | not started | not started | parser and renamer tests | Signature names resolve and type variables are scoped; type checking is later. |
| Declarations | fixity declarations | renamed | Phase 2/3 | parsed | renamed/fixity-resolved | not started | not started | not started | not started | parser and renamer tests | Fixity declarations resolve to operator names and drive expression reassociation. |
| Declarations | data declarations | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Type and constructor namespaces are separated; ADT semantics and representation are later. |
| Declarations | newtype declarations | renamed | Phase 2/16 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Type and constructor names resolve; representation strategy is later. |
| Declarations | type synonyms | renamed | Phase 2/16 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Type synonym names and referenced types resolve; expansion rules are later. |
| Declarations | class declarations | renamed | Phase 2/12 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Class and method namespaces resolve; dictionary passing is later. |
| Declarations | instance declarations | renamed | Phase 2/12 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Instance heads and method names resolve; coherence and dictionaries are later. |
| Declarations | default declarations | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; numeric defaulting is later. |
| Declarations | foreign declarations | parsed | Phase 16 | parsed raw | not started | not started | not started | not started | not started | parser tests | Raw FFI declarations parse so source is preserved; FFI remains semantically deferred. |
| Expressions | variables | renamed | Phase 2/3 | parsed | renamed | .hg only | .hg only | .hg only | .hg only | parser and renamer tests | Variable occurrences resolve to unique binders or fail. |
| Expressions | constructors | renamed | Phase 9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Constructor occurrences resolve in the constructor namespace. |
| Expressions | literals | parsed | Phase 2/5/10 | parsed | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Int, Char, and String parse; overloading and runtime support are later. |
| Expressions | application | renamed | Phase 2/5 | parsed | renamed | .hg only | .hg only | .hg only | .hg only | parser and renamer tests | Function and argument occurrences are resolved; Haskell laziness is later. |
| Expressions | infix application | renamed | Phase 2/3 | parsed unresolved | renamed/fixity-resolved | .hg only | .hg only | .hg only | .hg only | parser and renamer tests | Parsed operator trees are reassociated using fixity declarations. |
| Expressions | lambda | renamed | Phase 2/5 | parsed | renamed | .hg monomorphic only | .hg only | .hg strict only | .hg only | parser and renamer tests | Lambda binders introduce unique term names; lazy argument semantics are later. |
| Expressions | let | renamed | Phase 2/5/6 | parsed | renamed | .hg monomorphic only | .hg only | .hg strict only | .hg only | parser and renamer tests | Layout-aware `let` groups introduce recursive unique-name scopes; recursive/lazy semantics are later. |
| Expressions | where | renamed | Phase 2/16 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | `where` groups introduce unique-name scopes; desugaring is later. |
| Expressions | if | parsed | Phase 2/5 | parsed | not started | .hg only | .hg only | .hg strict only | .hg only | parser tests | Parsed only; Haskell demand semantics are later. |
| Expressions | case | renamed | Phase 2/5/6 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Alternatives and pattern scopes rename; Core/STG demand form is later. |
| Expressions | do | renamed | Phase 2/13 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Statement binders scope over following statements; desugaring and IO are later. |
| Expressions | list syntax | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list constructors are later. |
| Expressions | tuple syntax | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; tuple constructors are later. |
| Expressions | sections | parsed | Phase 2/16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; full fixity-sensitive semantics are later. |
| Expressions | arithmetic sequences | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; Enum/Num support is later. |
| Expressions | list comprehensions | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; desugaring is later. |
| Patterns | variable patterns | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Pattern variables bind unique names and scope over guarded RHSs. |
| Patterns | wildcard patterns | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Wildcards rename without binding. |
| Patterns | literal patterns | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Literals pass through renaming; equality semantics are later. |
| Patterns | constructor patterns | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Constructor patterns resolve in the constructor namespace. |
| Patterns | tuple patterns | renamed | Phase 2/9/10 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Tuple pattern binders are scoped; tuple runtime is later. |
| Patterns | list patterns | renamed | Phase 2/9/10 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | List pattern binders are scoped; list runtime is later. |
| Patterns | as-patterns | renamed | Phase 2/9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | As-pattern binders are unique and checked for duplicates. |
| Patterns | irrefutable patterns | renamed | Phase 16 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Irrefutable pattern binders are scoped; lazy pattern semantics are later. |
| Patterns | nested patterns | renamed | Phase 9 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Nested pattern binders and constructor uses resolve. |
| Patterns | guards | renamed | Phase 2/9/16 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Guard expressions see pattern binders; guard desugaring is later. |
| Types | type variables | renamed | Phase 5 | parsed | renamed | infrastructure only | not started | not started | not started | parser and renamer tests | Type variables are implicitly or explicitly scoped during renaming. |
| Types | function types | renamed | Phase 5 | parsed | renamed | .hg only | not started | not started | .hg closure only | parser and renamer tests | Function type names resolve; Haskell typechecking is later. |
| Types | tuple types | renamed | Phase 10 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Tuple element types resolve; tuple runtime is later. |
| Types | list types | renamed | Phase 10 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | List element types resolve; list runtime is later. |
| Types | type constructors | renamed | Phase 9/10 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Type constructors resolve in the type namespace. |
| Types | type classes | renamed | Phase 12 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Class heads and constraints resolve in the class namespace. |
| Types | constraints | renamed | Phase 12 | parsed | renamed | not started | not started | not started | not started | parser and renamer tests | Constraint names and type variables resolve; solver is later. |
| Types | kind checking | not started | Phase 12/16 | not started | not started | not started | not started | not started | not started | not started | Needed for type constructors/classes. |
| Types | polymorphism | not started | Phase 5 | not started | not started | infrastructure only | not started | not started | not started | principal tests only | User-facing .hg polymorphism deferred. |
| Types | defaulting | not started | Phase 12/16 | not started | not started | not started | not started | not started | not started | not started | Numeric defaulting pending. |
| Compiler IR | typed Core syntax | complete | Phase 4 | n/a | n/a | n/a | implemented | not started | not started | Core unit tests | Isolated `Haskell2010.Core` IR supports typed variables, literals, constructors, lambdas, applications, lets, letrec, cases, primitive operations, and type metadata. |
| Compiler IR | Core validator | complete | Phase 4 | n/a | n/a | n/a | implemented | not started | not started | Core unit tests | Validates unique binders, resolved variables, expression types, primitive signatures, constructor arities, and case alternative result types. |
| Compiler IR | Core utilities | complete | Phase 4 | n/a | n/a | n/a | implemented | not started | not started | Core unit tests | Free-variable analysis, capture-aware substitution, and stable pretty-printing are implemented for the isolated Core IR. |
| Compiler IR | Haskell source to Core | not started | Phase 5 | parsed | renamed | not started | not started | not started | not started | not started | The typed Core layer exists, but Haskell source is not yet typechecked or desugared into it. |
| Runtime/semantics | laziness | not started | Phase 6 | n/a | n/a | not started | not started | not started | not started | not started | Required for Haskell 2010. |
| Runtime/semantics | sharing | not started | Phase 6/7 | n/a | n/a | n/a | not started | not started | not started | not started | Thunk updates pending. |
| Runtime/semantics | bottom | not started | Phase 6/15 | n/a | n/a | n/a | not started | not started | not started | not started | Must constrain optimizer rules. |
| Runtime/semantics | checked Int64 bridge/current runtime | current .hg only | Phase 7 | .hg only | n/a | .hg only | .hg only | .hg strict only | .hg native wet-tested | wet-tested for .hg | Haskell numeric model to be specified. |
| Runtime/semantics | constructors | not started | Phase 7/9 | not started | not started | not started | not started | not started | not started | not started | Closure layout pending. |
| Runtime/semantics | pattern-match failure | not started | Phase 9/17 | not started | not started | not started | not started | not started | not started | not started | Diagnostics pending. |
| Runtime/semantics | IO | not started | Phase 13 | not started | not started | not started | not started | not started | not started | not started | Native entrypoint pending. |
| Runtime/semantics | exceptions | deferred | post-Haskell 2010 baseline | not started | not started | not started | not started | not started | not started | not started | Documented as deferred initially. |
| Runtime/semantics | FFI | deferred | Phase 16 or later | not started | not started | not started | not started | not started | not started | not started | Initially a documented deviation. |
| Prelude/libraries | Bool | current .hg only | Phase 10 | .hg literal only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Haskell Prelude bindings pending. |
| Prelude/libraries | Maybe | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | ADT support required. |
| Prelude/libraries | Either | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | ADT support required. |
| Prelude/libraries | Ordering | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | ADT support required. |
| Prelude/libraries | lists | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | Constructors and recursion required. |
| Prelude/libraries | tuples | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | Tuple constructors required. |
| Prelude/libraries | Eq | not started | Phase 12 | not started | not started | not started | not started | not started | not started | not started | Type classes pending. |
| Prelude/libraries | Ord | not started | Phase 12 | not started | not started | not started | not started | not started | not started | not started | Type classes pending. |
| Prelude/libraries | Show | not started | Phase 12/13 | not started | not started | not started | not started | not started | not started | not started | Needed for `print`. |
| Prelude/libraries | Num | not started | Phase 12 | not started | not started | not started | not started | not started | not started | not started | Overloaded literals pending. |
| Prelude/libraries | Enum | not started | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Arithmetic sequences pending. |
| Prelude/libraries | Bounded | not started | Phase 12/16 | not started | not started | not started | not started | not started | not started | not started | Deriving/defaults pending. |
| Prelude/libraries | Monad | not started | Phase 13 | not started | not started | not started | not started | not started | not started | not started | IO/do notation pending. |
| Prelude/libraries | IO | not started | Phase 13 | not started | not started | not started | not started | not started | not started | not started | Native Haskell main pending. |
| Prelude/libraries | basic list functions | not started | Phase 10/11 | not started | not started | not started | not started | not started | not started | not started | Requires lists and recursion. |
