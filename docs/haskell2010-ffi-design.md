# Haskell 2010 FFI Design

This document records the required Haskell 2010 Foreign Function Interface
surface and the planned compiler architecture for implementing it. It is a
secondary design document for the runtime/semantics FFI workstream; the
engineering backlog remains in `docs/haskell2010-todo.md`.

## Report Requirements

Haskell 2010 includes FFI in Chapter 8 of the Report. A complete
implementation needs the following behavior.

### Declarations

The parser must accept top-level foreign declarations:

- `foreign import callconv [safety] impent var :: ftype`
- `foreign export callconv expent var :: ftype`

`foreign import` defines a new Haskell variable backed by an external entity.
`foreign export` exposes an existing top-level Haskell variable to foreign
code. Imported variables must participate in normal binding, duplicate-name,
module export, and import/export behavior.

### Calling Conventions

The Report requires any FFI implementation to support at least `ccall`.
`stdcall` semantics are also defined. The names `cplusplus`, `jvm`, and
`dotnet` are reserved calling-convention identifiers whose detailed semantics
are implementation-specific rather than portable Haskell 2010 behavior.

The implementation model should therefore be:

- required: `ccall`
- required for full report-defined support where the target ABI exposes it:
  `stdcall`
- recognized but rejected with clear diagnostics unless implemented:
  `cplusplus`, `jvm`, `dotnet`, and implementation-specific conventions

### Safety

Foreign imports may specify `safe` or `unsafe`; omitted safety defaults to
`safe`.

- `safe` calls must leave the Haskell runtime in a state that permits callbacks
  into Haskell.
- `unsafe` calls are lower overhead but must not trigger callbacks; doing so is
  undefined behavior.

The compiler must preserve this distinction in the IR and runtime contract.

### External Entity Specifications

For `ccall` imports, entity strings cover:

- static functions: `"static [header.h] symbol"` or just `"symbol"`
- static addresses: `"[header.h] &symbol"`
- dynamic stubs: `"dynamic"`
- wrapper stubs: `"wrapper"`

If the entity string is omitted, the external symbol defaults to the Haskell
variable name. Header names must end in `.h`. Header references do not define
Haskell semantics, but they are important for generated C/stub paths and for
portable C prototype availability.

For `ccall` exports, entity strings name the exported C identifier; if omitted,
the exported symbol defaults to the Haskell variable name.

### Foreign Types

Foreign types are restricted. Arguments must be marshallable foreign types.
Results must be marshallable result types.

Basic foreign types:

- Prelude: `Char`, `Int`, `Double`, `Float`, `Bool`
- `Foreign`: `Int8`, `Int16`, `Int32`, `Int64`
- `Foreign`: `Word8`, `Word16`, `Word32`, `Word64`
- `Foreign`: `Ptr a`, `FunPtr a`, `StablePtr a`

`ForeignPtr a` is a managed ownership type in the standard library surface, but
it is not itself a direct C ABI argument or result type. Code passes it to C by
unwrapping it with `withForeignPtr`, which supplies a `Ptr a` while preserving
the Haskell-side liveness/finalizer contract.

Type synonyms may expand to valid foreign types. Newtypes may wrap valid
foreign types when the constructor is visible at the use site, so abstractly
exported newtypes are not marshallable outside their defining module.

Result types additionally permit:

- `()`
- `IO t` where `t` is a marshallable foreign type or `()`
- non-`IO` pure results for externally pure imported functions

External functions are strict in all arguments.

### Standard Library Surface

The FFI requires standard modules and types beyond the current generated
Prelude surface:

- `Foreign`
- `Foreign.C`
- `Foreign.C.Types`
- `Foreign.C.String`
- `Foreign.C.Error`
- `Foreign.Ptr`
- `Foreign.StablePtr`
- `Foreign.ForeignPtr`
- `Foreign.Storable`
- `Foreign.Marshal.*`

These modules are part of the full goal. Implementation order may be staged for
engineering control, but the design target is the complete Report surface, not
a reduced FFI subset.

## Compiler Architecture

FFI should be represented explicitly from the frontend through native lowering.
Stringly typed foreign declarations should be parsed once into structured
entities, while retaining the original string for diagnostics and exact source
reporting.

### Frontend AST

Add source AST forms:

- `ForeignImportDecl`
- `ForeignExportDecl`
- `CallConv`
- `Safety`
- `ForeignImportEntity`
- `ForeignExportEntity`
- `ForeignType`

The parser should keep the raw entity string and defer calling-convention
specific parsing to a small FFI entity parser module. This keeps the base
Haskell parser simple and makes non-`ccall` diagnostics precise.

### Renamer

Renaming rules:

- `foreign import` binds a top-level term name.
- `foreign export` references an existing top-level term, field selector, or
  class method in scope.
- foreign declarations participate in duplicate-name checks.
- imported foreign names can be exported and imported through normal module
  interfaces.

Module interfaces should gain an explicit foreign-export summary only if needed
by separate compilation or link planning. Ordinary foreign imports behave like
top-level value declarations after renaming.

### Typechecker

The typechecker should validate:

- every foreign declaration has a valid foreign type
- argument and result types are marshallable
- newtype transparency is allowed only when constructors are visible
- `dynamic` has shape `FunPtr ft -> ft`
- `wrapper` has shape `ft -> IO (FunPtr ft)`
- static address imports have shape `Ptr a` or `FunPtr a`
- `foreign export` type is an instance of the exported variable's type

Do not attempt to prove consistency with C prototypes. The Report explicitly
places that responsibility on the programmer except for checks the
implementation can reasonably perform.

### Core

Core should contain explicit foreign operation nodes rather than encoding FFI
as magic named calls:

- `CoreForeignImport` metadata for calling convention, safety, entity, binder,
  and foreign type
- `CForeignCall CoreForeignImport [CoreExpr] CoreType` for strict static
  external calls, indirect `dynamic` calls, and `wrapper` callback creation
- `CForeignImportValue CoreForeignImport CoreType` for address imports that
  produce boxed pointer values
- `CoreForeignExport` module metadata for exported C entrypoints, carrying
  calling convention, export entity, exported binder, and foreign type
- typed pointer and C scalar representations

Pure foreign imports may lower to ordinary Core expressions. `IO` foreign
imports must lower to Core IO actions so ordering and effects remain explicit.
Foreign exports are not ordinary expressions; they are retained as module-level
metadata through Core/STG so the native backend can generate external C ABI
entrypoints.

### STG And Runtime

STG should model FFI calls as strict call nodes with evaluated arguments:

- force arguments before the external call
- marshal boxed Haskell values to ABI values
- invoke the external symbol or generated stub
- marshal the result back into boxed Haskell values
- sequence `IO` results through the existing IO action runtime

Runtime support needs a stable boundary for:

- scalar boxing/unboxing
- pointer values
- function pointer values
- stable pointer table
- wrapper callback entrypoints
- safe-call callback state

The current native runtime keeps the process-lifetime arena allocation policy
and implements explicit ownership records for the FFI values that need lifetime
semantics:

- `StablePtr a` allocates a process-lifetime record containing the referenced
  Haskell value and an alive flag. `deRefStablePtr` checks the flag and returns
  the referenced value; `freeStablePtr` invalidates the record. Dereference or
  double-free after invalidation is a checked runtime abort.
- `castStablePtrToPtr` and `castPtrToStablePtr` reinterpret the stable pointer
  record as the raw pointer-shaped representation required by the FFI surface;
  they do not transfer ownership.
- `ForeignPtr a` allocates a process-lifetime owner record for a raw address and
  a bounded process-lifetime finalizer list. `finalizeForeignPtr` marks the
  owner finalized before invoking callbacks, so finalization is idempotent and
  re-entrant safe. Finalizers run in reverse registration order.
- `withForeignPtr` obtains the raw `Ptr a`, runs the Haskell continuation, then
  touches the owner record after forcing the result. `touchForeignPtr` is a
  liveness barrier for generated code; it does not itself schedule or run
  finalizers.
- `freeHaskellFunPtr` releases only `FunPtr` values returned by Haskell
  `wrapper` imports. Release clears the callback closure slot, double-free of
  the same wrapper pointer is idempotent, unknown function pointers abort, and
  any later C call through a freed wrapper aborts before re-entering Haskell.
  Freed slots are eligible for reuse by later wrapper allocations.

Automatic GC-triggered finalizer scheduling and heap reclamation are not
claimed by the current backend; explicit `finalizeForeignPtr` and
`freeHaskellFunPtr` are the supported lifetime controls under the
process-lifetime allocation model.

### LLVM And Linking

LLVM lowering should emit:

- external `declare`s for static imported functions
- pointer-valued globals or symbol references for static addresses
- generated wrapper functions for `foreign export`
- typed indirect calls for `dynamic` `FunPtr` interop
- generated callback trampolines and process-lifetime callback slots for
  `wrapper` `FunPtr` interop
- ABI-accurate scalar argument and result types
- link metadata and CLI hooks for user-supplied object files and libraries

Headers are not semantically required by LLVM lowering, but the compiler should
preserve them for possible C stub generation and diagnostics. The current
implementation carries `ForeignLinkMetadata` in the Haskell 2010 native result
and emits LLVM comments for header-qualified imports, static/address symbols,
and exported C symbols. Build-time objects and libraries are explicit CLI
inputs: `--link-object`, `--link-library`, `--library-path`, and `--framework`
are passed through to clang, so the frontend does not guess non-Report library
or object requirements from a foreign entity string.

## Implementation Order

These steps are an engineering order for reaching full Haskell 2010 FFI. They
are not scoped-down product slices.

1. Parse and rename foreign declarations, while representing every
   report-defined convention/entity form structurally. Status: complete for
   source/renamed AST representation and module-interface name movement.
2. Add `Foreign`/`Foreign.C.Types` generated module interfaces and scalar
   newtypes. Status: complete for generated `Foreign`, `Foreign.C`, and
   `Foreign.C.Types` type export surfaces and kind-visible
   `Ptr`/`FunPtr`/`StablePtr`/`ForeignPtr` plus C scalar type constructors and
   explicit ownership/finalizer term APIs.
3. Typecheck the full foreign type grammar, including synonyms and visible
   newtypes. Status: complete for the current typechecker boundary:
   `ccall`/`stdcall` validation, marshallable scalar/floating/pointer/synonym/local
   visible-newtype validation, `static`/address/`dynamic`/`wrapper` import
   shape checks, and foreign export target type matching.
4. Add explicit Core/STG foreign-import/export IR. Status: complete for static,
   `dynamic`, and `wrapper` imports as eta-expanded
   `CForeignCall`/`STGForeignCall`, and for address imports as inert
   foreign-import values. `foreign export` declarations are preserved as
   Core/STG module metadata for native lowering. Core/STG validators,
   pretty-printers, evaluators, and optimizer traversal preserve the IR.
   Core/STG evaluators still report
   precise runtime FFI boundaries; the native LLVM backend now lowers supported
   static, dynamic, wrapper, and export `ccall` forms.
5. Implement `foreign import ccall` static functions for scalar pure and `IO`
   functions by adding ABI marshalling and native call lowering. Status:
   complete for direct C symbols with boxed `Int`/`Bool`/`Char`/`Float`/`Double`
   values, `Ptr`/`FunPtr` pointer values, signed/unsigned integer C ABI
   declarations and range-checked integer marshalling, `CFloat`/`CDouble`
   floating-point ABI lowering, LLVM `declare`/`call` emission, and `IO`
   sequencing through the existing native `IO` runtime.
6. Add native wet tests that compile/link a C helper object with Haskell code.
   Status: complete for static scalar `ccall` calls covering pure results,
   `IO ()`, result-carrying `IO`, Bool and Char scalar conversion, and ordered
   `IO` side effects; and for pointer/address calls covering static data
   addresses, static function addresses, pointer arguments, pointer results,
   and ordered pointer mutation through `IO`; and for dynamic/wrapper calls
   covering indirect `FunPtr` invocation, multiple live callback wrappers, and
   Haskell callback re-entry with `IO` and result marshalling; and for
   `foreign export ccall` entrypoints covering C-to-Haskell calls into exported
   pure and `IO` functions; and for floating-point `Float`/`Double`,
   `CFloat`, and `CDouble` marshalling across static calls, dynamic calls, wrapper callbacks,
   and foreign export entrypoints; and for explicit `StablePtr`/`ForeignPtr`
   ownership, finalizer ordering, and idempotent finalization behavior.
7. Implement static address imports with `Ptr`/`FunPtr`. Status: complete for
   direct C data symbols as boxed `Ptr a` values and direct C function symbols
   as boxed `FunPtr ft` values. Header/symbol link metadata is preserved, and
   native wet tests link explicit helper objects through the compile CLI.
8. Implement `dynamic` imports and `wrapper` imports. Status: complete for the
   current scalar/floating/pointer ABI slice. `dynamic` imports unbox `FunPtr ft` and
   emit typed indirect LLVM calls. `wrapper` imports allocate reclaimable
   process-lifetime callback slots, return C-callable `FunPtr ft` trampolines,
   box C arguments before entering Haskell closures, force callback `IO`
   results, and marshal results back to the C ABI. The current backend uses a
   bounded per-import wrapper pool, reuses slots released by
   `freeHaskellFunPtr`, and aborts on callback-after-free or pool exhaustion.
9. Implement `foreign export ccall` generated entrypoints. Status: complete
   for the current scalar/floating/pointer ABI slice. Exported entrypoints box incoming
   C arguments, allocate the module closure graph, enter the exported Haskell
   closure, force pure or `IO` results, and unbox results back to C. Current
   entrypoints are emitted as normal externally visible LLVM functions for
   explicitly named C symbols or the Haskell binder occurrence when no export
   entity string is supplied.
10. Implement explicit `StablePtr` and manual `ForeignPtr` ownership APIs.
   Status: complete for generated library surfaces, typechecking, Core/STG
   primitive representation, validators, evaluators, native LLVM runtime
   records, stable pointer dereference/free checks, `withForeignPtr`, bounded
   finalizer registration, reverse-order finalizer dispatch, idempotent
   finalization, `freeHaskellFunPtr` wrapper slot reclamation, and native
   C-helper wet tests. Automatic GC finalization remains scoped out under the
   current process-lifetime runtime model.
11. Add `stdcall` where the target ABI exposes it and target-specific
   diagnostics where it does not.
12. Fill out `Foreign.*` marshalling modules and conformance fixtures.
    Status: complete for generated/importable `Foreign.Marshal`,
    `Foreign.Marshal.Error`, and `Foreign.Marshal.Utils` slices that fit the
    current runtime model, with native fixtures for null-pointer guards,
    `void`, `throwIf`, `throwIf_`, `maybeNew`, `maybeWith`, and `maybePeek`.
    `Foreign.C.Error`, `Foreign.Storable`, raw allocation, array marshalling,
    and C string marshalling functions remain explicit pending surface.

## Tests

Required test layers:

- parser tests for every declaration form and reserved identifier behavior
- renamer tests for imported binding/exported reference behavior
- typechecker tests for accepted and rejected foreign types
- Core/STG validation tests for explicit FFI nodes
- native wet tests for static scalar `ccall`
- native wet tests for `IO` sequencing around foreign calls
- native wet tests for static addresses
- native wet tests for callbacks through `wrapper` and C-to-Haskell calls
  through `foreign export`
- native wet tests for `freeHaskellFunPtr`, wrapper slot reclamation,
  idempotent double-free, and callback-after-free runtime failure
- native wet tests for `StablePtr`, `ForeignPtr`, finalizer ordering,
  idempotent explicit finalization, and `withForeignPtr` liveness barriers
- negative tests for unsupported calling conventions and invalid entity strings

## Conformance Boundary

The goal is full Haskell 2010 FFI. The only explicit boundary here is the
Report itself:

- C prototype consistency remains the programmer's responsibility except where
  the compiler has enough information to diagnose a mismatch.
- Target-specific calling conventions may require target-specific diagnostics
  when the current platform cannot expose the convention.
- Reserved non-C convention names should be recognized and diagnosed unless an
  implementation-specific backend is deliberately added.

References:

- Haskell 2010 Report, Chapter 8, Foreign Function Interface:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch8.html>
- Haskell 2010 Report, Chapter 24, `Foreign`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch24.html>
- Haskell 2010 Report, Chapter 25, `Foreign.C`:
  <https://www.haskell.org/onlinereport/haskell2010/haskellch25.html>
