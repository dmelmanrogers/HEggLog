# Haskell 2010 Conformance Matrix

This matrix tracks the active Haskell 2010 target. Rows marked
`current .hg only` describe infrastructure that exists for the strict `.hg`
substrate but is not yet implemented for Haskell 2010 source.

Status values: `not started`, `current .hg only`, `parsed`, `renamed`,
`typechecked`, `desugared to Core`, `compiled to native`, `wet-tested`,
`complete`, `deferred`, `documented deviation`.

| Haskell 2010 area | Feature | Current status | Planned milestone | Parser | Renamer | Typechecker | Core | STG/runtime | LLVM/native | Tests | Notes/deviations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lexical/layout | identifiers | current .hg only | Phase 2 | .hg only | not started | not started | not started | not started | not started | .hg tests only | Haskell lexical classes not implemented. |
| Lexical/layout | operators | current .hg only | Phase 2 | .hg only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Haskell fixity not implemented. |
| Lexical/layout | reserved words | current .hg only | Phase 2 | .hg only | not started | not started | not started | not started | not started | .hg tests only | Haskell reserved set pending. |
| Lexical/layout | comments | current .hg only | Phase 2 | .hg only | n/a | n/a | n/a | n/a | n/a | .hg tests only | Nested Haskell comments need confirmation. |
| Lexical/layout | layout rule | not started | Phase 2 | not started | not started | not started | not started | not started | not started | not started | Required for Haskell 2010. |
| Lexical/layout | numeric literals | current .hg only | Phase 2/5 | .hg only | not started | .hg Int only | .hg only | .hg only | .hg only | .hg tests only | Haskell defaulting/overloading pending. |
| Lexical/layout | char literals | not started | Phase 2 | not started | not started | not started | not started | not started | not started | not started | Requires Char runtime representation. |
| Lexical/layout | string literals | not started | Phase 2/10 | not started | not started | not started | not started | not started | not started | not started | Depends on list/Char support. |
| Modules | module header | not started | Phase 2/14 | not started | not started | not started | not started | not started | not started | not started | Whole-program module system pending. |
| Modules | import declarations | not started | Phase 2/14 | not started | not started | not started | not started | not started | not started | not started | Import resolution pending. |
| Modules | export lists | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Visibility checks pending. |
| Modules | qualified imports | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Namespace model pending. |
| Modules | hiding | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Namespace model pending. |
| Modules | aliases | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Namespace model pending. |
| Modules | module graph | not started | Phase 14 | not started | not started | not started | not started | not started | not started | not started | Cycle detection pending. |
| Declarations | value bindings | current .hg only | Phase 2/5 | .hg top-level only | not started | .hg monomorphic only | .hg ANF/Core only | .hg strict only | .hg only | .hg tests only | Haskell binding groups and patterns pending. |
| Declarations | type signatures | current .hg only | Phase 2/5 | .hg top-level required | not started | .hg monomorphic only | not started | not started | not started | .hg tests only | Haskell signature scope pending. |
| Declarations | fixity declarations | not started | Phase 2/3 | not started | not started | not started | not started | not started | not started | not started | Needed before full infix parsing. |
| Declarations | data declarations | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | ADTs pending. |
| Declarations | newtype declarations | not started | Phase 2/16 | not started | not started | not started | not started | not started | not started | not started | Representation strategy pending. |
| Declarations | type synonyms | not started | Phase 2/16 | not started | not started | not started | not started | not started | not started | not started | Expansion rules pending. |
| Declarations | class declarations | not started | Phase 2/12 | not started | not started | not started | not started | not started | not started | not started | Dictionary passing pending. |
| Declarations | instance declarations | not started | Phase 2/12 | not started | not started | not started | not started | not started | not started | not started | Coherence rules pending. |
| Declarations | default declarations | not started | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Defaulting pending. |
| Declarations | foreign declarations | deferred | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Initially documented as deferred. |
| Expressions | variables | current .hg only | Phase 2/3 | .hg only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Haskell namespaces pending. |
| Expressions | constructors | not started | Phase 9 | not started | not started | not started | not started | not started | not started | not started | ADT constructors pending. |
| Expressions | literals | current .hg only | Phase 2/5/10 | .hg Int/Bool only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Char/String and overloaded literals pending. |
| Expressions | application | current .hg only | Phase 2/5 | .hg only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Haskell laziness pending. |
| Expressions | infix application | current .hg only | Phase 2/3 | .hg fixed precedence only | not started | .hg only | .hg only | .hg only | .hg only | .hg tests only | Haskell fixity pending. |
| Expressions | lambda | current .hg only | Phase 2/5 | .hg only | not started | .hg monomorphic only | .hg only | .hg strict only | .hg only | .hg tests only | Haskell lazy arguments pending. |
| Expressions | let | current .hg only | Phase 2/5/6 | .hg nonrecursive only | not started | .hg monomorphic only | .hg only | .hg strict only | .hg only | .hg tests only | Haskell recursive/lazy let pending. |
| Expressions | where | not started | Phase 2/16 | not started | not started | not started | not started | not started | not started | not started | Desugars to let after renaming. |
| Expressions | if | current .hg only | Phase 2/5 | .hg only | not started | .hg only | .hg only | .hg strict only | .hg only | .hg tests only | Lazy branch semantics already compatible; condition demand pending in STG. |
| Expressions | case | not started | Phase 2/5/6 | not started | not started | not started | not started | not started | not started | not started | Core/STG demand form required. |
| Expressions | do | not started | Phase 2/13 | not started | not started | not started | not started | not started | not started | not started | Desugaring and IO pending. |
| Expressions | list syntax | not started | Phase 2/10 | not started | not started | not started | not started | not started | not started | not started | List constructors pending. |
| Expressions | tuple syntax | not started | Phase 2/10 | not started | not started | not started | not started | not started | not started | not started | Tuple constructors pending. |
| Expressions | sections | not started | Phase 2/16 | not started | not started | not started | not started | not started | not started | not started | Depends on fixity. |
| Expressions | arithmetic sequences | not started | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Depends on Enum/Num support. |
| Expressions | list comprehensions | not started | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Desugaring pending. |
| Patterns | variable patterns | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | Pattern scopes pending. |
| Patterns | wildcard patterns | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | Pattern compiler pending. |
| Patterns | literal patterns | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | Equality semantics pending. |
| Patterns | constructor patterns | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | ADTs pending. |
| Patterns | tuple patterns | not started | Phase 2/9/10 | not started | not started | not started | not started | not started | not started | not started | Tuples pending. |
| Patterns | list patterns | not started | Phase 2/9/10 | not started | not started | not started | not started | not started | not started | not started | Lists pending. |
| Patterns | as-patterns | not started | Phase 2/9 | not started | not started | not started | not started | not started | not started | not started | Pattern binding pending. |
| Patterns | irrefutable patterns | not started | Phase 16 | not started | not started | not started | not started | not started | not started | not started | Requires lazy pattern semantics. |
| Patterns | nested patterns | not started | Phase 9 | not started | not started | not started | not started | not started | not started | not started | Pattern compiler pending. |
| Patterns | guards | not started | Phase 2/9/16 | not started | not started | not started | not started | not started | not started | not started | Guard desugaring pending. |
| Types | type variables | not started | Phase 5 | not started | not started | infrastructure only | not started | not started | not started | principal tests only | Current principal engine exists for .hg direction. |
| Types | function types | current .hg only | Phase 5 | .hg only | not started | .hg only | not started | not started | .hg closure only | .hg tests only | Haskell types pending. |
| Types | tuple types | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | Tuple runtime pending. |
| Types | list types | not started | Phase 10 | not started | not started | not started | not started | not started | not started | not started | List runtime pending. |
| Types | type constructors | not started | Phase 9/10 | not started | not started | not started | not started | not started | not started | not started | ADTs pending. |
| Types | type classes | not started | Phase 12 | not started | not started | not started | not started | not started | not started | not started | Dictionary passing pending. |
| Types | constraints | not started | Phase 12 | not started | not started | not started | not started | not started | not started | not started | Constraint solver pending. |
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
