# Haskell 2010 Standard Library Layout

This document records the compiler boundary for Haskell 2010 standard-library
modules. The Haskell 2010 Report treats `Prelude` as a distinguished module
that is imported by default, while still being an ordinary module for import
filtering and qualification. It also defines a fixed standard-library surface
outside `Prelude`.

## Implemented Boundary

The compiler currently implements one generated standard-library module:

| Module | Implementation owner | Status |
| --- | --- | --- |
| `Prelude` | `Haskell2010.StandardLibrary` | generated/importable interface for the current executable subset |

`Haskell2010.StandardLibrary` owns the generated `Prelude` module identity,
export names, `Thing(..)` children, fixities, and the implicit import
declaration used by the renamer. The renamer consumes this through
`ModuleInterface` just like source-module interfaces, instead of carrying an
ad hoc fallback scope.

The current `Prelude` interface exports only the implemented executable-subset
surface: supported built-in data constructors, classes, class methods, list and
IO functions, generated list functions, and fixities. It is intentionally not a
claim that the full Haskell 2010 Prelude is present.

## Reserved Standard Modules

The broader Haskell 2010 library module set, including modules such as
`Data.Char`, `Data.List`, `Data.Maybe`, `Control.Monad`, `System.IO`, and
`Numeric`, remains reserved for future implementation. These modules are not
silently exposed as empty modules; importing one still requires an implemented
source/module-graph path or a future generated interface. This avoids accepting
programs whose standard-library dependencies are not actually supported.

## Interface Model

`Haskell2010.ModuleInterface` is the shared module-boundary data model:

- exported names
- parent-to-child export relationships for data constructors and class methods
- imported fixities
- instance exports

The `interfaceInstances` field is present now so PRELUDE-017 does not bake in a
name-only module model. It is deliberately empty for generated `Prelude` and is
populated structurally from renamed source `instance` declarations. Source
module interfaces retain every instance declaration in scope, and those
instances propagate across later imports independently of export lists,
ordinary import lists, `hiding`, and qualification, matching the Haskell 2010
module rule.

## Non-Goals

- No package database or search path behavior is added here.
- No additional Haskell 2010 library modules are made importable.
- No new Prelude functions/classes/instances are claimed solely by this layout
  task.
- Generated `Prelude` instances remain owned by the typechecker/runtime
  implementation until a broader standard-library instance interface is needed.

References:

- Haskell 2010 Report, Section 5.6, Standard Prelude:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch5.html>
- Haskell 2010 Report, Chapter 9, Standard Prelude:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch9.html>
