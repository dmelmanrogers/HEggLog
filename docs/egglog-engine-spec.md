# Egglog Engine Specification

This document describes the generic Egglog-style engine role in HeggLog.

## Engine Role

`Egglog.*` is a frontend-independent equality-saturation kernel implemented in
Haskell. It provides sorts, values, functions, merge behavior, union-find,
rebuild, rule evaluation, extraction, and provenance/debug tracing.

The engine is not tied to the current `.hg` frontend and must remain independent
of the future Haskell 2010 frontend.

## Current Adapter

The current production compiler adapter is the `.hg` ANF Egglog backend in
`Optimize.EgglogBackend.*`. It encodes a typed, pure ANF fragment into Egglog
sorts, runs strictness-safe rules, extracts valid ANF, and checks type and
runtime-error preservation.

This backend optimizes the current `.hg` compiler-supported subset only. It
does not optimize Haskell 2010 Core.

## Future Haskell 2010 Adapter

The Haskell 2010 compiler will add a typed Core Egglog adapter, described in
[`egglog-core-optimizer-plan.md`](egglog-core-optimizer-plan.md).

The future adapter is responsible for:

- Core schema and encoding
- Core facts
- Core rewrite rules
- typed Core extraction
- lazy semantics preservation
- bottom/runtime-error preservation
- provenance for selected rewrites

## Non-Negotiable Engine Boundaries

- The generic Egglog kernel must not import Haskell 2010 frontend modules.
- The generic Egglog kernel must not import LLVM backend modules.
- Frontend-specific facts and rules belong in adapter modules.
- Extraction must validate the target IR after reconstruction.
- Optimizer behavior must be tested against semantic preservation, not only
  against smaller costs.
