# HeggLog Language Specification

This document describes the strict `.hg` language implemented by the current
compiler substrate. Future features are explicitly marked as decisions or
planned work.

# Relation to Haskell 2010

This specification describes the current `.hg` compiler-supported substrate. It
is not Haskell 2010.

Haskell 2010 source support is tracked separately:

- [Haskell 2010 roadmap](haskell2010-roadmap.md)
- [Haskell 2010 frontend specification](haskell2010-frontend-spec.md)
- [Laziness and STG plan](laziness-and-stg-plan.md)

The current `.hg` language uses strict call-by-value evaluation. Haskell 2010
requires non-strict semantics, so the future Haskell 2010 compiler requires
typed Core, STG-like lazy lowering, and a lazy runtime. Current `.hg` behavior
remains useful as a backend/middle-end substrate and regression baseline, but
it is not the final source-language endpoint.

## Source Unit

A HeggLog source file contains zero or more top-level first-order definitions
followed by one main expression.

Top-level definitions are ordered and nonrecursive. A definition body can refer
to its parameters and earlier top-level definitions. The main expression can
refer to all top-level definitions.

## Lexical Structure

Whitespace is insignificant between tokens.

Comments:

- Line comments start with `--` and continue to the end of the line.
- Block comments are delimited by `{-` and `-}`.

Identifiers:

- First character: ASCII/Unicode letter or `_`.
- Remaining characters: alphanumeric, `_`, or `'`.
- Reserved words cannot be identifiers.

Reserved words:

```text
def let in if then else true false Int Bool
```

Integer literals:

- Current source syntax accepts unsigned decimal literals only.
- The literal is typechecked against the HeggLog `Int` range.
- Negative values are expressible through checked arithmetic, for example
  `0 - 1`.

Decision needed:

- Whether to add signed integer literal syntax or unary negation.
- Recommendation: add a dedicated unary negation form rather than making `-`
  part of the decimal token. This avoids changing tokenization and precedence
  for expressions such as `x-1`.
- Consequence: the parser and pretty-printer need an explicit unary expression
  form or a carefully specified desugaring.

## Grammar Sketch

This sketch is intentionally close to the parser. It is not a Megaparsec grammar
dump, but it captures the implemented precedence.

```text
program     ::= topDef* expr EOF

topDef      ::= "def" name "(" param ("," param)* ")" ":" type "=" expr ";"
param       ::= name ":" type

expr        ::= letExpr
              | ifExpr
              | lambdaExpr
              | equalityExpr

letExpr     ::= "let" name "=" expr "in" expr
ifExpr      ::= "if" expr "then" expr "else" expr
lambdaExpr  ::= "\" name (":" type)? "->" expr

equality    ::= comparison ("==" comparison)*
comparison  ::= additive ("<" additive)*
additive    ::= multiplicative (("+" | "-") multiplicative)*
multiplicative ::= application (("*" | "/") application)*
application ::= atom+

atom        ::= integer
              | "true"
              | "false"
              | name
              | "(" expr ")"

type        ::= typeAtom "->" type
              | typeAtom
typeAtom    ::= "Int"
              | "Bool"
              | "(" type ")"
```

Associativity and precedence:

- Function application is left-associative and binds tighter than binary
  operators.
- `*` and `/` bind tighter than `+` and `-`.
- `<` binds looser than arithmetic.
- `==` binds looser than `<`.
- Binary operators at the same precedence level are parsed left-associatively.
- Function type arrow `->` is right-associative.
- `let`, `if`, and lambda expressions parse before the operator-precedence
  ladder and extend over full expressions.

## Types

Implemented types:

```text
Int
Bool
T1 -> T2
```

Top-level function parameters and returns require annotations in source syntax.
Lambda parameter annotations are optional when the compiler can infer a concrete
monomorphic type from local use and surrounding context. Ambiguous lambda
parameters, ambiguous equality operands, user-facing Hindley-Milner
polymorphism, algebraic data types, and pattern matching are not source features
yet. The staged inference direction is documented in `docs/type-inference.md`.

Top-level function parameters and returns must be first-order values (`Int` or
`Bool`). Function-typed top-level parameters and returns remain rejected while
the first closure runtime pass is limited to local function values.

## Top-Level Definitions

```text
def inc(x : Int) : Int = x + 1;
inc 41
```

Top-level definitions introduce named functions. They require at least one
parameter, and parameter names in a single definition must be unique.

Duplicate top-level names are rejected. Forward references are rejected because
definitions are checked in source order:

```text
def f(x : Int) : Int = g x; -- rejected: g is not in scope yet
def g(x : Int) : Int = x;
f 1
```

The interpreter evaluates top-level definitions in order and then evaluates the
main expression in the resulting environment.

## Expression Forms

### Integer Literals

Integer literals have type `Int` when the decimal value is in range.

Current accepted source literal range:

```text
0 through 9223372036854775807
```

The runtime `Int` domain is signed 64-bit:

```text
-9223372036854775808 through 9223372036854775807
```

### Boolean Literals

`true` and `false` have type `Bool`.

### Variables

A variable expression resolves to the nearest lexical binding with the same
name. The typechecker rejects unbound variables.

### Let

```text
let x = rhs in body
```

`let` is nonrecursive. The right-hand side is checked and evaluated in the
current environment; `x` is available only in the body.

Shadowing is lexical and allowed:

```text
let x = 1 in let x = 2 in x
```

The expression above evaluates to `2`.

### If

```text
if cond then thenExpr else elseExpr
```

The condition must have type `Bool`. The branches must have the same type. The
condition is evaluated first; only the selected branch is evaluated.

### Binary Operations

Implemented primitives:

| Operator | Operand types | Result type | Runtime behavior |
| --- | --- | --- | --- |
| `+` | `Int`, `Int` | `Int` | checked signed 64-bit addition |
| `-` | `Int`, `Int` | `Int` | checked signed 64-bit subtraction |
| `*` | `Int`, `Int` | `Int` | checked signed 64-bit multiplication |
| `/` | `Int`, `Int` | `Int` | checked signed 64-bit integer division; division by zero and minimum `Int / -1` are runtime errors |
| `<` | `Int`, `Int` | `Bool` | signed less-than |
| `==` | `Int`, `Int` | `Bool` | integer equality |
| `==` | `Bool`, `Bool` | `Bool` | boolean equality |

Equality on function values is rejected by the typechecker.

Division uses signed quotient semantics that truncate toward zero, matching
LLVM `sdiv` after explicit runtime checks.

### Lambda

```text
\x : Type -> body
\x -> body
```

Lambdas capture their lexical environment in the interpreter and have function
type `Type -> BodyType`. When the annotation is omitted, source elaboration
infers the parameter type before interpretation, ANF lowering, lambda lifting,
closure conversion, or LLVM lowering. The backend only sees explicit
monomorphic function types.

The LLVM backend lambda-lifts non-capturing lambdas when they are let-bound or
used directly in function position. Lifted lambdas become generated top-level
first-order functions when every local use is saturated. Remaining function
values are closure-converted for LLVM compile mode when the program's root value
is still `Int` or `Bool`.

### Application

```text
f arg
```

The function expression must have type `ArgType -> ResultType`, and the argument
type must equal `ArgType`.

Evaluation is call-by-value: evaluate the function, evaluate the argument, then
apply the closure.

The LLVM backend supports saturated direct calls to top-level first-order
functions and closure calls through local function values. Partial or
over-applied top-level calls are rejected structurally. Using a top-level
function as a first-class value is also outside the current LLVM fragment.

## Evaluation Order

HeggLog is currently a strict, call-by-value language:

- top-level definitions: evaluate in source order before the main expression.
- `let`: evaluate the right-hand side before the body.
- binary operations: evaluate the left operand, then the right operand, then the
  primitive.
- application: evaluate the function, then the argument, then the body in the
  closure environment extended with the argument binding.
- `if`: evaluate the condition first, then evaluate only the selected branch.
- lambda: evaluating a lambda creates a closure without evaluating the body.

ANF lowering makes operand evaluation order explicit by binding non-atomic
subexpressions to deterministic temporary names.

## Runtime Values

Implemented runtime values:

- `Int`: checked signed 64-bit integer.
- `Bool`: boolean.
- Closure: interpreter value containing captured environment, parameter name,
  and body expression. LLVM compile mode represents closures as heap objects
  containing a code pointer and captured fields.

## Runtime Errors

Implemented runtime errors:

- Unknown variable. Typechecked closed programs should not produce this.
- Runtime type error. Typechecked programs should not produce this.
- Division by zero.
- Integer literal out of range.
- Checked integer overflow.

The compiler should preserve runtime-error behavior for supported optimizations
and backend lowering. An optimization that changes success into overflow, or
overflow into success, is unsound.

## Open Terms

Source programs intended for ordinary execution should be closed. Some internal
optimizer APIs intentionally support open ANF fragments for analysis and testing.
Free variables in the Egglog backend must have a single inferred type.

## Examples

```haskell
let x = 3 in let y = x + 4 in y * 2
```

```haskell
if 1 < 2 then 10 else 20
```

```haskell
let dec = \x : Int -> x - 1 in dec 10
```

```haskell
0 - 1
```

The last example evaluates to `-1`; negative values are runtime values even
though negative source literals are not syntax yet.

## Planned Features

- User-facing Hindley-Milner polymorphism and optional top-level signatures.
- Algebraic data types and pattern matching, later.
