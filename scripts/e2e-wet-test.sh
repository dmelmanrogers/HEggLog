#!/usr/bin/env bash
set -euo pipefail

printf '== require clang ==\n'
if ! command -v clang >/dev/null 2>&1; then
  printf 'clang is required for mandatory e2e wet tests\n' >&2
  exit 1
fi
clang --version | head -n 1

printf '== cabal build all ==\n'
cabal build all

printf '== cabal test e2e-wet-test ==\n'
cabal test e2e-wet-test

printf '== cabal test all ==\n'
cabal test all

printf '== cabal check ==\n'
cabal check

printf '== git diff --check ==\n'
git diff --check

printf 'mandatory e2e wet tests passed\n'
