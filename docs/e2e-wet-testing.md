# End-to-End Wet Testing

HeggLog wet tests verify the compiler as an external program. The test harness
does not call internal compiler APIs and does not run `cabal run` for each
case. It invokes the built `hegglog` executable as a subprocess, compiles real
`.hg` files from disk, checks the produced artifacts, executes native binaries
directly, and asserts exit code, stdout, and stderr behavior.

Current wet tests validate the existing `.hg` native compiler baseline and the
documented Haskell 2010 executable subset. Haskell 2010 conformance is tracked
by a separate dedicated suite, `haskell2010-conformance-test`, whose manifest
lives at `test/haskell2010/conformance/manifest.json`. That suite compiles
`.hs` files to native executables, executes artifacts directly, compares exact
stdout, verifies runtime-error exits, verifies compile-error diagnostics, and
keeps unsupported Haskell 2010 features visible as explicit cases.

This suite complements the existing unit, property, differential, and golden
tests. Internal tests prove compiler passes and invariants in isolation. Wet
tests prove that the packaged CLI, file IO, LLVM emission, `clang` toolchain
path, native executable permissions, runtime behavior, and report-mode output
work together from the user's point of view.

## Corpus Layout

The authoritative corpus lives under `test/e2e/programs/`.

- `test/e2e/programs/*.hg` contains successful programs that should compile and
  run as native executables.
- `test/e2e/programs/runtime-errors/*.hg` contains programs that compile
  successfully but abort at runtime in generated native code.
- `test/e2e/programs/compile-errors/*.hg` contains sources rejected before an
  executable artifact is produced.
- `test/e2e/programs/unsupported/*.hg` contains unsupported language intents
  that are classified as compile errors.

The authoritative manifest is in `test/e2e/Main.hs`. It records each case name,
source path, expected outcome, Egglog modes, and whether emitted LLVM must also
be compiled through `clang` and executed.

The Haskell 2010 conformance corpus lives under
`test/haskell2010/conformance/`. Its authoritative manifest is structured JSON,
not shell parsing, and records the case name, source file, category, expected
status, exact expected stdout where applicable, diagnostic category for failing
cases, required compiler stage, compiler mode, and notes/deviations.

## Categories

Successful cases assert that:

- `hegglog compile SOURCE -o TMP/CASE` exits successfully.
- The requested executable exists and has executable permissions.
- Running the executable directly exits successfully.
- Stdout exactly matches the expected value plus HeggLog's trailing newline.
- Stderr is empty.

Runtime-error cases assert that:

- Native compilation succeeds.
- The executable artifact exists.
- Running the executable exits nonzero.
- Stdout and stderr follow the current native runtime convention, which is
  empty output for checked arithmetic aborts.

Compile-error cases assert that:

- Native compilation exits nonzero.
- No executable is created at the requested output path.
- Combined stdout/stderr is nonempty.
- The diagnostic includes a stable category such as `type`, `parse`,
  `unsupported`, `free`, `backend`, `recursive`, or `unbound`.

Unsupported-documented Haskell 2010 conformance cases assert that:

- Native compilation exits nonzero.
- No executable is created at the requested output path.
- Combined stdout/stderr is nonempty.
- The manifest contains an explicit note/deviation explaining why the feature
  is outside the current supported subset.
- The diagnostic includes the manifest's expected category. If such a case
  starts passing accidentally, the conformance suite fails.

Emit-LLVM cases assert that:

- `hegglog compile SOURCE --emit-llvm -o TMP/CASE.ll` succeeds.
- The `.ll` file exists, is nonempty, and contains `define` and `@main`.
- `clang TMP/CASE.ll -o TMP/CASE_FROM_LLVM` succeeds.
- Running the resulting executable matches native stdout, stderr, and exit code
  expectations.

Report-mode comparisons assert that every successful source run through
`hegglog SOURCE` contains a stable machine-readable line:

```text
Result: <value>
```

The wet suite compares that result with the native executable stdout
convention. Boolean roots use the native convention, where `true` is `1` and
`false` is `0`.

## Egglog Modes

Every case runs through default compile behavior unless it is explicitly marked
otherwise. The manifest also covers `--no-egglog` for representative successful
programs, including division and an Egglog-beneficial arithmetic/boolean case.
Division runtime errors also run with `--no-egglog` so both optimized and
unoptimized native paths preserve checked failure behavior.

## Running Locally

Run the full mandatory wet-test path:

```bash
scripts/e2e-wet-test.sh
```

The script requires `clang`, then runs:

```bash
cabal build all
cabal test e2e-wet-test
cabal test all
cabal check
git diff --check
```

The Haskell test suites require `clang`; missing `clang` is a test failure, not
a skip. `llvm-as` and `lli` remain optional for other LLVM-focused checks, but
native wet testing and Haskell 2010 conformance depend on `clang`.

## CI

GitHub Actions installs `clang`, runs `cabal build all`,
`cabal test all --test-options='--hide-successes'`, `cabal check`, and then
runs `scripts/e2e-wet-test.sh`. Because `e2e-wet-test` and
`haskell2010-conformance-test` are Cabal test suites, `cabal test all` includes
both. The script then repeats the dedicated wet path with explicit section
headings for CI and local diagnosis.
