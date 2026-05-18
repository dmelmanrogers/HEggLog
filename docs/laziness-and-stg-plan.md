# Laziness and STG Plan

## Why Laziness Is Required

A Haskell 2010 compiler must implement non-strict semantics. Strict compilation
is not Haskell semantics.

Required examples:

```haskell
const 1 (1 `div` 0)
```

evaluates to `1`.

```haskell
let x = 1 `div` 0 in 5
```

evaluates to `5`.

```haskell
case (1 `div` 0) of ...
```

raises a runtime error because `case` demands the scrutinee.

The current `.hg` runtime is strict and therefore is not sufficient for Haskell
2010. It remains the regression baseline for the current compiler-supported
subset.

## Runtime Objects

The Haskell 2010 runtime needs object representations for:

- closure header
- function closure
- thunk closure
- constructor closure
- indirection/update closure
- black-hole marker
- primitive values
- boxed and unboxed value decisions

The object header should carry enough tag or info-table data for enter,
update, case dispatch, and diagnostics. The first implementation can choose a
simple uniform representation before optimizing layout.

## Evaluation

Required evaluation operations:

- enter closure
- force thunk
- update thunk
- represent case as demand
- force primitive operands
- treat constructors as values
- preserve sharing after thunk evaluation
- support recursive heap bindings for `letrec`

Function arguments are lazy unless forced. Primitive operations force their
operands. Case forces the scrutinee enough to choose an alternative. Let binds
thunks rather than evaluating right-hand sides eagerly.

## STG-like IR

The STG-like IR should model:

- functions
- thunks
- constructors
- `let` and `letrec`
- case expressions
- alternatives
- primitive operations
- update flags

Validation must check unique binders, resolved variables, arity, constructor
tags, alternative coverage where applicable, and type/representation
consistency.

## LLVM Lowering

The lazy backend lowers STG-like IR to LLVM by using:

- closure layout
- runtime calls
- enter/apply convention
- case dispatch
- constructor tags
- heap allocation
- runtime linking

Generated LLVM for Haskell 2010 source must link the runtime system. The current
strict `.hg` LLVM backend does not by itself implement lazy Haskell semantics,
even though it already proves the project can emit LLVM and produce native
executables through `clang`.

## Testing

Required tests:

- laziness
- sharing
- recursive thunk/black-hole behavior
- constructor case dispatch
- checked arithmetic and division runtime errors
- native wet tests

Representative wet tests must compile `.hs` sources to native executables and
run the artifacts directly, comparing optimized and `--no-egglog` behavior
where applicable.
