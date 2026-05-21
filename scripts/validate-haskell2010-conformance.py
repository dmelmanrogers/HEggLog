#!/usr/bin/env python3
"""Validate Haskell 2010 conformance manifest and matrix bookkeeping."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "test" / "haskell2010" / "conformance" / "manifest.json"
MATRIX_PATH = ROOT / "docs" / "haskell2010-conformance-matrix.md"

ALLOWED_STATUSES = {
    "parse-pass",
    "rename-pass",
    "typecheck-pass",
    "core-pass",
    "native-success",
    "native-runtime-error",
    "compile-error",
    "unsupported-documented",
}

ALLOWED_MODES = {"default", "no-egglog"}


def fail(message: str) -> None:
    print(f"haskell2010 conformance validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_string(case_name: str, case: dict[str, Any], key: str) -> str:
    value = case.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"{case_name} must have nonempty string field {key}")
    return value


def require_string_list(case_name: str, case: dict[str, Any], key: str) -> list[str]:
    value = case.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
        fail(f"{case_name} must have a string list field {key}")
    return value


def main() -> None:
    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing {MANIFEST_PATH.relative_to(ROOT)}")
    except json.JSONDecodeError as err:
        fail(f"invalid JSON in {MANIFEST_PATH.relative_to(ROOT)}: {err}")

    if manifest.get("schemaVersion") != 1:
        fail("manifest schemaVersion must be 1")

    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        fail("manifest cases must be a nonempty list")

    matrix_text = MATRIX_PATH.read_text(encoding="utf-8")
    names: list[str] = []
    status_counts: Counter[str] = Counter()
    category_counts: Counter[str] = Counter()

    for raw_case in cases:
        if not isinstance(raw_case, dict):
            fail("every manifest case must be an object")

        case_name = require_string("<unknown>", raw_case, "name")
        names.append(case_name)

        source_file = require_string(case_name, raw_case, "sourceFile")
        category = require_string(case_name, raw_case, "category")
        expected_status = require_string(case_name, raw_case, "expectedStatus")
        required_stage = require_string(case_name, raw_case, "requiredStage")
        notes = require_string(case_name, raw_case, "notes")
        compiler_modes = raw_case.get("compilerModes", ["default"])
        extra_objects = require_string_list(case_name, raw_case, "extraObjects")

        if expected_status not in ALLOWED_STATUSES:
            fail(f"{case_name} has unknown expectedStatus {expected_status!r}")
        if not isinstance(compiler_modes, list) or not compiler_modes:
            fail(f"{case_name} must have a nonempty compilerModes list when present")
        for mode in compiler_modes:
            if mode not in ALLOWED_MODES:
                fail(f"{case_name} has unknown compiler mode {mode!r}")

        source_path = ROOT / source_file
        if not source_path.is_file():
            fail(f"{case_name} sourceFile does not exist: {source_file}")
        for extra_object in extra_objects:
            if not (ROOT / extra_object).is_file():
                fail(f"{case_name} extraObjects entry does not exist: {extra_object}")

        if expected_status == "native-success" and not isinstance(raw_case.get("expectedStdout"), str):
            fail(f"{case_name} native-success must include expectedStdout")
        if expected_status == "unsupported-documented" and not notes.strip():
            fail(f"{case_name} unsupported-documented must include notes")
        if source_file not in matrix_text:
            fail(f"{case_name} sourceFile is missing from {MATRIX_PATH.relative_to(ROOT)}")
        if not required_stage.strip():
            fail(f"{case_name} requiredStage must not be empty")

        status_counts[expected_status] += 1
        category_counts[category] += 1

    duplicate_names = sorted({name for name in names if names.count(name) > 1})
    if duplicate_names:
        fail("duplicate case names: " + ", ".join(duplicate_names))

    print(
        "validated "
        f"{len(cases)} Haskell 2010 conformance cases; "
        f"statuses={dict(sorted(status_counts.items()))}; "
        f"categories={dict(sorted(category_counts.items()))}"
    )


if __name__ == "__main__":
    main()
