# Egglog Engine Specification

This document describes the generic Egglog-style engine role in HeggLog.

## Engine Role

`Egglog.*` is a frontend-independent equality-saturation kernel implemented in
Haskell. It provides sorts, values, functions, merge behavior, union-find,
rebuild, rule evaluation, extraction, and provenance/debug tracing.

The engine is not tied to the current `.hg` frontend and must remain independent
of the future Haskell 2010 frontend.

## Current Adapters

The current production `.hg` compiler adapter is the ANF Egglog backend in
`Optimize.EgglogBackend.*`. It encodes a typed, pure ANF fragment into Egglog
sorts, runs strictness-safe rules, extracts valid ANF, and checks type and
runtime-error preservation.

The Haskell 2010 compiler has an initial typed Core adapter in
`Optimize.CoreEgglog`. It encodes safe Core-0 `Int`/`Bool` fragments through
the existing ANF Egglog backend, decodes extracted representatives back to
typed Core, validates the extracted Core, and records selected rewrite
provenance. It is deliberately conservative: unsupported or lazy-sensitive Core
is left unchanged.

## Full Haskell 2010 Adapter Direction

The broader typed Core Egglog adapter is described in
[`egglog-core-optimizer-plan.md`](egglog-core-optimizer-plan.md).

The full adapter remains responsible for:

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
