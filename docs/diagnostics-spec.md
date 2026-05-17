# Diagnostics Specification

This document describes the diagnostic format currently emitted by HeggLog's
user-facing compile paths.

## Source Locations

Source ranges are rendered as:

```text
path:start-line:start-column-end-column
path:start-line:start-column-end-line:end-column
```

Columns are 1-based. Same-line ranges omit the ending line number. The ending
column is the Megaparsec position immediately after the final token in the
range.

The parser produces a parallel located AST. The unspanned `Expr` AST remains the
semantic input for ANF, interpreters, optimizers, and backend lowering.

## Parser Diagnostics

Parser diagnostics are Megaparsec `ParseErrorBundle` output. They include the
source path, line, and column reported by Megaparsec, followed by the parser's
expected-token summary.

Example:

```text
examples/bad.hg:1:4:
  |
1 | let
  |    ^
unexpected end of input
expecting letter or '_'
```

Parser diagnostics are not yet normalized into the same one-line source-range
format used by later compiler phases.

## Typechecker Diagnostics

Type errors use the located AST and identify the smallest practical source
construct that explains the failure.

Examples:

```text
examples/type-errors/add-bool.hg:1:5-9: type error: operator + expects Int operands, got Bool
examples/type-errors/if-non-bool.hg:1:4-5: type error: if condition must be Bool, got Int
```

The CLI report mode wraps these lines in a section header:

```text
== Type error ==
examples/type-errors/add-bool.hg:1:5-9: type error: operator + expects Int operands, got Bool
```

## Runtime Diagnostics

Runtime diagnostics currently attach to the root source expression. This is
stable enough to identify the failing input, but it is not yet an exact
subexpression trace for nested runtime failures.

Example:

```text
<test>:1:1-24: runtime error: checked Int + overflowed: 9223372036854775807 + 1
```

Future interpreter work should preserve evaluation source positions so
division-by-zero and overflow diagnostics can point to the exact primitive
operation.

## LLVM Diagnostics

The LLVM compile path typechecks the located source first, then rejects source
constructs known to be outside the current LLVM fragment before lowering to ANF.
This gives unsupported-feature errors source ranges instead of backend-only ANF
shapes.

Examples:

```text
<llvm-diagnostic>:1:1-14: LLVM backend unsupported: LLVM backend does not support lambda expressions
<llvm-diagnostic>:1:3-8: LLVM backend unsupported: LLVM backend does not support division
```

The current LLVM source-fragment rejections are:

- lambda expressions
- unsupported applications, such as closure calls, calls through local
  variables, partial calls, and over-applied top-level calls
- using a top-level function as a first-class value
- division

Closed first-order source that passes this check can still fail later backend
validation if an internal lowering bug constructs invalid ANF, backend IR, or
LLVM IR.

## Test Coverage

Diagnostic behavior is covered by:

- parser source-location smoke tests
- golden type-error diagnostics
- golden LLVM unsupported-feature diagnostics
- existing negative type fixtures in `examples/type-errors/`
