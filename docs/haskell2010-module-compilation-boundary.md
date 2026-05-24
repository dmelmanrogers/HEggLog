# Haskell 2010 Module Compilation Boundary

## Status

This document closes `MOD-011` and `MOD-012` for the current compiler
architecture. The implemented boundary is explicit in
`Haskell2010.ModuleGraph.currentModuleCompilationBoundary`:

- module search policy: `RootDirectoryAndImportPathSourceSearch []`
- compilation mode: `WholeProgramSourceCompilation`
- interface-file policy: `InterfaceFilesDeferredUntilStableSearchPaths`

The compiler does not emit, read, or cache interface files yet. That is an
intentional architectural decision, not an untracked gap: package/search-path
identity, generated standard-library module boundaries, and native link
metadata must be stable before persistent interface artifacts can be correct.

## Current Behavior

The current Haskell 2010 module pipeline is source-graph whole-program
compilation:

1. `loadModuleGraph` starts from a root source file.
2. A source file with no module header is treated as `Main`.
3. Imports that name generated standard-library modules are satisfied from
   `Haskell2010.StandardLibrary.standardLibraryModuleInterfaces`.
4. Other imports are resolved by `RootDirectoryAndImportPathSourceSearch`:
   module `A.B` resolves to `A/B.hs` first under the root file's directory,
   then under each repeated CLI `-i`/`--import-path` directory in order.
5. The graph loader rejects unreadable modules, parse failures, module-name
   mismatches, duplicate module names from different files, and import cycles.
6. The renamer builds `ModuleInterface` values containing exports, child
   exports, fixities, and instance metadata.
7. Typechecking and lowering operate on the loaded source modules as one
   whole-program graph. `wholeProgramModule` preserves dependency declarations
   so instance dictionaries are available along the imported module chain.

Import and export visibility remains a renamer concern. Haskell 2010 instance
visibility is not filtered by import/export lists, so any later interface-file
format must carry instance metadata independently from exported value/type
names.

## Separate Compilation Decision

Separate compilation is deferred until module search paths settle. Implementing
object/interface caching before the resolver has stable module identity would
create incorrect cache keys and unsound reuse behavior.

The future separate-compilation implementation must not weaken current
semantics. It must preserve:

- Haskell 2010 implicit and explicit `Prelude` import rules
- cumulative imports and ambiguity diagnostics
- qualified and hiding import behavior
- `Thing(..)` child export/import expansion
- imported instance visibility independent of export lists
- fixity availability across imports
- generated standard-library module interfaces
- FFI import/export link metadata
- source-spanned diagnostics at least as precise as the current whole-program
  pipeline

The Haskell 2010 Report specifies module import/export semantics, but it does
not define a package database or compiler-specific search path protocol. This
compiler must therefore own that policy explicitly rather than treating it as a
Report requirement.

## Future Interface File Shape

A persistent interface file must be a semantic artifact, not a serialized copy
of a frontend AST. The planned interface boundary needs these fields:

- compiler interface format version
- target ABI and code-generation mode that affect callable artifacts
- module name and package/search identity
- source hash and normalized compiler options that affect exported semantics
- direct dependency fingerprints
- exported term, constructor, type, class, and module names
- child export metadata for data constructors, record selectors, and class
  methods
- fixity declarations visible to importers
- kind and type metadata required to rename and typecheck importers
- class metadata, superclass structure, default-method metadata, and method
  types
- declared and transitively visible instance metadata, including dictionary
  identifiers and dependency fingerprints
- foreign import/export declarations and link metadata needed by native builds
- enough provenance to produce stable import/type diagnostics

The invalidation rule must be conservative: if an importer can observe a change
through name resolution, typechecking, instance selection, fixity resolution,
foreign linking, or generated Core/STG ABI, the dependency fingerprint must
change.

## Implementation Plan

The correct order for full separate compilation is:

1. Extend the existing ordered source resolver with explicit package and
   interface roots while preserving root-directory-first source lookup.
2. Add a versioned interface artifact type next to `ModuleInterface`, with
   deterministic serialization and round-trip tests.
3. Make the renamer and typechecker consume either loaded source modules or
   loaded interface artifacts through the same semantic import environment.
4. Emit per-module Core/STG/native artifacts with dependency fingerprints and
   FFI link metadata.
5. Add a stale-interface detector that refuses unsound reuse and falls back to
   source recompilation where possible.
6. Add multi-module tests that compile a dependency, consume only its interface
   and object artifact from an importer, and prove that export changes,
   instance changes, fixity changes, type changes, and foreign link changes
   invalidate importers.

Until those pieces exist, the current whole-program mode is the correct
behavior for Haskell 2010 source execution in this codebase.

## Validation

The current boundary is covered by:

- `test/Main.hs` module graph tests, including import/export resolution,
  instance propagation, cycle rejection, and the explicit compilation-boundary
  value
- Haskell 2010 conformance tests for same-directory and `-i` source-path
  multi-module native execution, implicit and explicit `Prelude` imports,
  standard-library module imports, instance import/export behavior, bad
  imports, and unsupported package-database/unimplemented-library imports
- documentation tracker entries `MOD-003`, `MOD-011`, and `MOD-012`

## Report References

- Haskell 2010 Report, Chapter 5, Modules:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch5.html>
- Haskell 2010 Report, Section 5.6, Standard Prelude:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch5.html#x11-1040005.6>
- Haskell 2010 Report, Section 5.7, Separate Compilation:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch5.html#x11-1120005.7>
- Haskell 2010 Libraries contents:
  <https://www.haskell.org/onlinereport/haskell2010/haskellli1.html>
