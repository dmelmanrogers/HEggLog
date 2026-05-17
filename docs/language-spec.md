# HeggLog Language Specification

This document describes the language implemented by the current codebase. Future
features are explicitly marked as decisions or planned work.

## Source Unit

A HeggLog source file currently contains exactly one expression followed by end
of file.

Top-level definitions are not source syntax yet. They are planned in the
roadmap before lambda lifting and closure conversion.

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
let in if then else true false Int Bool
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
program     ::= expr EOF

expr        ::= letExpr
              | ifExpr
              | lambdaExpr
              | equalityExpr

letExpr     ::= "let" name "=" expr "in" expr
ifExpr      ::= "if" expr "then" expr "else" expr
lambdaExpr  ::= "\" name ":" type "->" expr

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

Function parameters require annotations. There is no Hindley-Milner inference,
generalization, polymorphism, algebraic data type, or pattern matching support
yet.

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
| `/` | `Int`, `Int` | `Int` | checked signed 64-bit integer division; division by zero is a runtime error |
| `<` | `Int`, `Int` | `Bool` | signed less-than |
| `==` | `Int`, `Int` | `Bool` | integer equality |
| `==` | `Bool`, `Bool` | `Bool` | boolean equality |

Equality on function values is rejected by the typechecker.

Division is implemented in the source and ANF interpreters. The LLVM backend
currently rejects division structurally.

### Lambda

```text
\x : Type -> body
```

Lambdas capture their lexical environment in the interpreter and have function
type `Type -> BodyType`.

The LLVM backend currently rejects lambdas structurally.

### Application

```text
f arg
```

The function expression must have type `ArgType -> ResultType`, and the argument
type must equal `ArgType`.

Evaluation is call-by-value: evaluate the function, evaluate the argument, then
apply the closure.

The LLVM backend currently rejects applications structurally.

## Evaluation Order

HeggLog is currently a strict, call-by-value language:

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
- Closure: interpreter-only value containing captured environment, parameter
  name, and body expression.

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

- Source spans and richer diagnostics.
- Top-level first-order definitions.
- Direct backend support for first-order function calls.
- Lambda lifting for non-capturing lambdas.
- Closure conversion and runtime closure representation.
- Hindley-Milner direction decision.
- Algebraic data types and pattern matching, later.
