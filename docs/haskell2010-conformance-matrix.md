# Haskell 2010 Conformance Matrix

This matrix tracks the active Haskell 2010 target. Rows marked
`current .hg only` describe infrastructure that exists for the strict `.hg`
substrate but is not yet implemented for Haskell 2010 source.

Status values: `not started`, `current .hg only`, `parsed`, `renamed`,
`typechecked`, `desugared to Core`, `compiled to native`, `wet-tested`,
`complete`, `deferred`, `documented deviation`.

| Haskell 2010 area | Feature | Current status | Planned milestone | Parser | Renamer | Typechecker | Core | STG/runtime | LLVM/native | Tests | Notes/deviations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lexical/layout | identifiers | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Haskell variable and constructor identifiers now parse into the Haskell2010 AST. |
| Lexical/layout | operators | parsed | Phase 2 | parsed | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Operators parse as unresolved infix trees; fixity resolution is Phase 3. |
| Lexical/layout | reserved words | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Haskell reserved words and reserved operators are rejected as identifiers/operators. |
| Lexical/layout | comments | parsed | Phase 2 | parsed | n/a | n/a | n/a | n/a | n/a | parser tests | Line comments and nested block comments are supported by the Haskell2010 lexer. |
| Lexical/layout | layout rule | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Layout blocks parse for modules, `where`, `let`, `do`, and `case`; malformed indentation is rejected. |
| Lexical/layout | numeric literals | parsed | Phase 2/5 | parsed integers | not started | .hg Int only | .hg only | .hg only | .hg only | parser tests | Decimal, hex, and octal integers parse; floating literals and overloading/defaulting are later. |
| Lexical/layout | char literals | parsed | Phase 2 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; runtime Char representation is later. |
| Lexical/layout | string literals | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list/Char runtime support is later. |
| Modules | module header | parsed | Phase 2/14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed into `HsModule`; whole-program module resolution is later. |
| Modules | import declarations | parsed | Phase 2/14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; import resolution is later. |
| Modules | export lists | parsed | Phase 14 | parsed | not started | not started | not started | not started | not started | parser tests | Names, `Thing(..)`, and module exports parse; visibility checks are later. |
| Modules | qualified imports | parsed | Phase 14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; namespace model is later. |
| Modules | hiding | parsed | Phase 14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; namespace filtering is later. |
| Modules | aliases | parsed | Phase 14 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; alias resolution is later. |
| Modules | module graph | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Cycle detection pending. |
| Declarations | value bindings | parsed | Phase 2/5 | parsed | not started | .hg monomorphic only | .hg ANF/Core only | .hg strict only | .hg only | parser tests | Function and pattern bindings parse; binding groups, recursion, and semantics are later. |
| Declarations | type signatures | parsed | Phase 2/5 | parsed | not started | .hg monomorphic only | not started | not started | not started | parser tests | Parsed only; signature scope and checking are later. |
| Declarations | fixity declarations | parsed | Phase 2/3 | parsed | not started | not started | not started | not started | not started | parser tests | Declarations parse; operator trees remain unresolved until Phase 3. |
| Declarations | data declarations | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; ADT semantics and representation are later. |
| Declarations | newtype declarations | parsed | Phase 2/16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; representation strategy is later. |
| Declarations | type synonyms | parsed | Phase 2/16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; expansion rules are later. |
| Declarations | class declarations | parsed | Phase 2/12 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; dictionary passing is later. |
| Declarations | instance declarations | parsed | Phase 2/12 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; coherence and dictionaries are later. |
| Declarations | default declarations | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; numeric defaulting is later. |
| Declarations | foreign declarations | parsed | Phase 16 | parsed raw | not started | not started | not started | not started | not started | parser tests | Raw FFI declarations parse so source is preserved; FFI remains semantically deferred. |
| Expressions | variables | parsed | Phase 2/3 | parsed | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Parsed only; Haskell namespace resolution is Phase 3. |
| Expressions | constructors | parsed | Phase 9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; ADT constructor resolution is later. |
| Expressions | literals | parsed | Phase 2/5/10 | parsed | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Int, Char, and String parse; overloading and runtime support are later. |
| Expressions | application | parsed | Phase 2/5 | parsed | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Parsed only; Haskell laziness is later. |
| Expressions | infix application | parsed | Phase 2/3 | parsed unresolved | not started | .hg only | .hg only | .hg only | .hg only | parser tests | Parsed as left-associated unresolved operators; fixity is Phase 3. |
| Expressions | lambda | parsed | Phase 2/5 | parsed | not started | .hg monomorphic only | .hg only | .hg strict only | .hg only | parser tests | Parsed only; lazy argument semantics are later. |
| Expressions | let | parsed | Phase 2/5/6 | parsed | not started | .hg monomorphic only | .hg only | .hg strict only | .hg only | parser tests | Layout-aware `let` parses; recursive/lazy semantics are later. |
| Expressions | where | parsed | Phase 2/16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed on bindings and case alternatives; desugaring is later. |
| Expressions | if | parsed | Phase 2/5 | parsed | not started | .hg only | .hg only | .hg strict only | .hg only | parser tests | Parsed only; Haskell demand semantics are later. |
| Expressions | case | parsed | Phase 2/5/6 | parsed | not started | not started | not started | not started | not started | parser tests | Layout-aware alternatives parse; Core/STG demand form is later. |
| Expressions | do | parsed | Phase 2/13 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; desugaring and IO are later. |
| Expressions | list syntax | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list constructors are later. |
| Expressions | tuple syntax | parsed | Phase 2/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; tuple constructors are later. |
| Expressions | sections | parsed | Phase 2/16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; full fixity-sensitive semantics are later. |
| Expressions | arithmetic sequences | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; Enum/Num support is later. |
| Expressions | list comprehensions | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; desugaring is later. |
| Patterns | variable patterns | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; pattern scopes are later. |
| Patterns | wildcard patterns | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; pattern compiler is later. |
| Patterns | literal patterns | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; equality semantics are later. |
| Patterns | constructor patterns | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; ADT resolution is later. |
| Patterns | tuple patterns | parsed | Phase 2/9/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; tuple runtime is later. |
| Patterns | list patterns | parsed | Phase 2/9/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list runtime is later. |
| Patterns | as-patterns | parsed | Phase 2/9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; pattern binding is later. |
| Patterns | irrefutable patterns | parsed | Phase 16 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; lazy pattern semantics are later. |
| Patterns | nested patterns | parsed | Phase 9 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; pattern compiler is later. |
| Patterns | guards | parsed | Phase 2/9/16 | parsed | not started | not started | not started | not started | not started | parser tests | Binding and case guards parse; guard desugaring is later. |
| Types | type variables | parsed | Phase 5 | parsed | not started | infrastructure only | not started | not started | not started | parser tests | Parsed only; Haskell inference is later. |
| Types | function types | parsed | Phase 5 | parsed | not started | .hg only | not started | not started | .hg closure only | parser tests | Parsed only; Haskell typechecking is later. |
| Types | tuple types | parsed | Phase 10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; tuple runtime is later. |
| Types | list types | parsed | Phase 10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; list runtime is later. |
| Types | type constructors | parsed | Phase 9/10 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed only; ADTs are later. |
| Types | type classes | parsed | Phase 12 | parsed | not started | not started | not started | not started | not started | parser tests | Class heads and constraints parse; dictionary passing is later. |
| Types | constraints | parsed | Phase 12 | parsed | not started | not started | not started | not started | not started | parser tests | Parsed into contextual types; solver is later. |
| Types | kind checking | not started | Phase 12/16 | not started | not started | not started | not started | not started | not started | not started | Needed for type constructors/classes. |
| Types | polymorphism | not started | Phase 5 | not started | not started | infrastructure only | not started | not started | not started | principal tests only | User-facing .hg polymorphism deferred. |
| Types | defaulting | not started | Phase 12/16 | not started | not started | not started | not started | not started | not started | not started | Numeric defaulting pending. |
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
