#!/usr/bin/env bash
set -euo pipefail

strict_native=0
if [[ "${1:-}" == "--strict-native" ]]; then
  strict_native=1
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--strict-native]\n' "$0" >&2
  exit 2
fi

printf '== cabal build all ==\n'
cabal build all

printf '== cabal test all ==\n'
cabal test all

printf '== cabal check ==\n'
cabal check

printf '== Haskell 2010 backlog validation ==\n'
python3 scripts/validate-haskell2010-todo.py

if ! command -v clang >/dev/null 2>&1; then
  if [[ "$strict_native" -eq 1 ]]; then
    printf 'clang is required for --strict-native smoke tests\n' >&2
    exit 1
  fi
  printf '== native smoke tests skipped: clang unavailable ==\n'
  exit 0
fi

printf '== native executable smoke tests ==\n'

cabal run -v0 hegglog -- compile examples/llvm/arithmetic.hg -o /tmp/hegglog-smoke-arithmetic >/tmp/hegglog-smoke-arithmetic.build 2>&1
[[ "$(/tmp/hegglog-smoke-arithmetic)" == "14" ]]

cabal run -v0 hegglog -- compile examples/llvm/division.hg -o /tmp/hegglog-smoke-division --no-egglog >/tmp/hegglog-smoke-division.build 2>&1
[[ "$(/tmp/hegglog-smoke-division)" == "5" ]]

cabal run -v0 hegglog -- compile examples/llvm/bool-root.hg -o /tmp/hegglog-smoke-bool >/tmp/hegglog-smoke-bool.build 2>&1
[[ "$(/tmp/hegglog-smoke-bool)" == "1" ]]

printf 'smoke tests passed\n'
