#!/usr/bin/env python3
"""Validate Haskell 2010 conformance manifest and matrix bookkeeping."""

from __future__ import annotations

import json
import re
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

SOURCE_SURFACE_TABLE_HEADER = (
    "| Source area | Matrix row | Coverage status | Manifest fixtures | "
    "Remaining task/deviation | Notes |"
)

LIBRARY_CLOSURE_TABLE_HEADER = (
    "| Library area | Report surface | Coverage status | Manifest fixtures | "
    "Remaining task/deviation | Notes |"
)

SOURCE_SURFACE_MANIFEST_CATEGORIES = {"declarations", "expressions", "patterns"}

SOURCE_SURFACE_ADDITIONAL_FIXTURES = {
    "test/haskell2010/conformance/negative/constructor-operator-binding.hs",
    "test/haskell2010/conformance/negative/duplicate-function-parameter.hs",
    "test/haskell2010/conformance/negative/duplicate-monad-io.hs",
    "test/haskell2010/conformance/negative/ffi-wrapper-bad-shape.hs",
    "test/haskell2010/conformance/negative/impossible-case-pattern.hs",
    "test/haskell2010/conformance/negative/invalid-pattern-binding.hs",
    "test/haskell2010/conformance/negative/misindented-where-keyword.hs",
    "test/haskell2010/conformance/negative/malformed-where-layout.hs",
    "test/haskell2010/conformance/negative/unbound-variable.hs",
    "test/haskell2010/conformance/unsupported/constrained-expression-signature.hs",
    "test/haskell2010/conformance/unsupported/method-specific-constraint.hs",
    "test/haskell2010/conformance/typeclasses/instance-context.hs",
}

SOURCE_SURFACE_ROWS = {
    ("Declarations", "value bindings"),
    ("Declarations", "type signatures"),
    ("Declarations", "fixity declarations"),
    ("Declarations", "data declarations"),
    ("Declarations", "newtype declarations"),
    ("Declarations", "type synonyms"),
    ("Declarations", "class declarations"),
    ("Declarations", "instance declarations"),
    ("Declarations", "default declarations"),
    ("Declarations", "foreign declarations"),
    ("Expressions", "variables"),
    ("Expressions", "constructors"),
    ("Expressions", "literals"),
    ("Expressions", "application"),
    ("Expressions", "infix application"),
    ("Expressions", "lambda"),
    ("Expressions", "let"),
    ("Expressions", "where"),
    ("Expressions", "if"),
    ("Expressions", "case"),
    ("Expressions", "do"),
    ("Expressions", "list syntax"),
    ("Expressions", "tuple syntax"),
    ("Expressions", "sections"),
    ("Expressions", "expression type signatures"),
    ("Expressions", "arithmetic sequences"),
    ("Expressions", "list comprehensions"),
    ("Patterns", "variable patterns"),
    ("Patterns", "wildcard patterns"),
    ("Patterns", "literal patterns"),
    ("Patterns", "constructor patterns"),
    ("Patterns", "tuple patterns"),
    ("Patterns", "list patterns"),
    ("Patterns", "as-patterns"),
    ("Patterns", "irrefutable patterns"),
    ("Patterns", "nested patterns"),
    ("Patterns", "guards"),
}

LIBRARY_CLOSURE_ROWS = {
    ("Prelude", "root exported data/types"),
    ("Prelude", "classes and numeric tower"),
    ("Prelude", "text Show/Read"),
    ("Prelude", "list/function exports"),
    ("Control.Monad", "module"),
    ("Data.Array/Data.Ix", "modules"),
    ("Data.Bits", "module"),
    ("Data.Char", "module"),
    ("Data.Complex", "module"),
    ("Data.Int/Data.Word", "modules"),
    ("Data.List", "module"),
    ("Data.Maybe", "module"),
    ("Data.Ratio", "module"),
    ("Foreign", "implemented slices"),
    ("Foreign", "C.Error/Alloc/Array/Storable modules"),
    ("Numeric", "module"),
    ("System.Environment/System.Exit", "modules"),
    ("System.IO/System.IO.Error", "modules"),
}

LIBRARY_CLOSURE_REQUIRED_FIXTURES = {
    "test/haskell2010/conformance/adts/maybe-constructor-case.hs",
    "test/haskell2010/conformance/ffi/dynamic-wrapper.hs",
    "test/haskell2010/conformance/ffi/floating-ccall.hs",
    "test/haskell2010/conformance/ffi/foreign-library-surface.hs",
    "test/haskell2010/conformance/ffi/foreign-export.hs",
    "test/haskell2010/conformance/ffi/pointer-address.hs",
    "test/haskell2010/conformance/ffi/stable-foreignptr-finalizers.hs",
    "test/haskell2010/conformance/ffi/static-ccall.hs",
    "test/haskell2010/conformance/io/getline.hs",
    "test/haskell2010/conformance/io/io-error.hs",
    "test/haskell2010/conformance/io/printing.hs",
    "test/haskell2010/conformance/modules/standard-library-modules.hs",
    "test/haskell2010/conformance/modules/standard-library-scalar-types.hs",
    "test/haskell2010/conformance/modules/data-array.hs",
    "test/haskell2010/conformance/modules/data-array-duplicate-partial.hs",
    "test/haskell2010/conformance/modules/data-array-partial.hs",
    "test/haskell2010/conformance/modules/data-char.hs",
    "test/haskell2010/conformance/modules/data-char-partial.hs",
    "test/haskell2010/conformance/modules/data-ix.hs",
    "test/haskell2010/conformance/prelude/append.hs",
    "test/haskell2010/conformance/prelude/broad-show.hs",
    "test/haskell2010/conformance/prelude/char-runtime.hs",
    "test/haskell2010/conformance/prelude/enum-bounded.hs",
    "test/haskell2010/conformance/prelude/foldl.hs",
    "test/haskell2010/conformance/prelude/functions.hs",
    "test/haskell2010/conformance/prelude/head-empty.hs",
    "test/haskell2010/conformance/prelude/numeric-hierarchy.hs",
    "test/haskell2010/conformance/prelude/prelude-classes.hs",
    "test/haskell2010/conformance/prelude/prelude-lists.hs",
    "test/haskell2010/conformance/prelude/read-standard.hs",
    "test/haskell2010/conformance/prelude/string-char-list.hs",
    "test/haskell2010/conformance/typeclasses/derived-bounded.hs",
    "test/haskell2010/conformance/typeclasses/derived-enum.hs",
    "test/haskell2010/conformance/typeclasses/derived-read.hs",
    "test/haskell2010/conformance/typeclasses/derived-show.hs",
    "test/haskell2010/conformance/typeclasses/monad-explicit-fail.hs",
    "test/haskell2010/conformance/typeclasses/monad.hs",
    "test/haskell2010/conformance/unsupported/handle-io.hs",
    "test/haskell2010/conformance/unsupported/library-data-bits.hs",
    "test/haskell2010/conformance/unsupported/library-data-complex.hs",
    "test/haskell2010/conformance/unsupported/library-data-ratio.hs",
    "test/haskell2010/conformance/unsupported/library-foreign-c-error.hs",
    "test/haskell2010/conformance/unsupported/library-foreign-marshal.hs",
    "test/haskell2010/conformance/unsupported/library-foreign-storable.hs",
    "test/haskell2010/conformance/unsupported/library-numeric.hs",
    "test/haskell2010/conformance/unsupported/library-system-environment.hs",
    "test/haskell2010/conformance/unsupported/library-system-exit.hs",
}

FIXTURE_PATH_RE = re.compile(r"`(test/haskell2010/conformance/[^`]+\.hs)`")
TASK_ID_RE = re.compile(r"`[A-Z][A-Z0-9-]+-[0-9]{3}`")


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


def parse_table_cells(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        fail(f"malformed source surface closure table row: {line}")
    return [cell.strip() for cell in stripped.strip("|").split("|")]


def is_markdown_separator(cells: list[str]) -> bool:
    return bool(cells) and all(cell and set(cell) <= {"-", ":", " "} and "-" in cell for cell in cells)


def read_source_surface_rows(matrix_text: str) -> list[list[str]]:
    lines = matrix_text.splitlines()
    header_index = next(
        (index for index, line in enumerate(lines) if line.strip() == SOURCE_SURFACE_TABLE_HEADER),
        None,
    )
    if header_index is None:
        fail("missing Source Surface Matrix Closure table")
    if header_index + 1 >= len(lines):
        fail("Source Surface Matrix Closure table is missing its separator row")

    separator_cells = parse_table_cells(lines[header_index + 1])
    if len(separator_cells) != 6 or not is_markdown_separator(separator_cells):
        fail("Source Surface Matrix Closure table has an invalid separator row")

    rows: list[list[str]] = []
    for line in lines[header_index + 2 :]:
        if not line.strip():
            break
        if not line.lstrip().startswith("|"):
            break
        cells = parse_table_cells(line)
        if len(cells) != 6:
            fail(f"Source Surface Matrix Closure table row must have 6 cells: {line}")
        rows.append(cells)

    if not rows:
        fail("Source Surface Matrix Closure table must contain at least one row")
    return rows


def read_library_closure_rows(matrix_text: str) -> list[list[str]]:
    lines = matrix_text.splitlines()
    header_index = next(
        (index for index, line in enumerate(lines) if line.strip() == LIBRARY_CLOSURE_TABLE_HEADER),
        None,
    )
    if header_index is None:
        fail("missing Library Conformance Closure table")
    if header_index + 1 >= len(lines):
        fail("Library Conformance Closure table is missing its separator row")

    separator_cells = parse_table_cells(lines[header_index + 1])
    if len(separator_cells) != 6 or not is_markdown_separator(separator_cells):
        fail("Library Conformance Closure table has an invalid separator row")

    rows: list[list[str]] = []
    for line in lines[header_index + 2 :]:
        if not line.strip():
            break
        if not line.lstrip().startswith("|"):
            break
        cells = parse_table_cells(line)
        if len(cells) != 6:
            fail(f"Library Conformance Closure table row must have 6 cells: {line}")
        rows.append(cells)

    if not rows:
        fail("Library Conformance Closure table must contain at least one row")
    return rows


def validate_source_surface_closure(
    matrix_text: str,
    manifest_sources_by_category: dict[str, set[str]],
) -> int:
    manifest_sources = {
        source_file
        for sources in manifest_sources_by_category.values()
        for source_file in sources
    }
    source_surface_manifest_sources = {
        source_file
        for category in SOURCE_SURFACE_MANIFEST_CATEGORIES
        for source_file in manifest_sources_by_category.get(category, set())
    } | SOURCE_SURFACE_ADDITIONAL_FIXTURES

    seen_rows: set[tuple[str, str]] = set()
    table_fixture_paths: set[str] = set()

    for area, row_name, status, fixtures, task_or_deviation, notes in read_source_surface_rows(matrix_text):
        key = (area, row_name)
        if key in seen_rows:
            fail(f"duplicate Source Surface Matrix Closure row: {area} / {row_name}")
        if key not in SOURCE_SURFACE_ROWS:
            fail(f"unexpected Source Surface Matrix Closure row: {area} / {row_name}")
        if not status:
            fail(f"Source Surface Matrix Closure row {area} / {row_name} must have a coverage status")
        if not task_or_deviation:
            fail(f"Source Surface Matrix Closure row {area} / {row_name} must have a remaining task/deviation")
        if task_or_deviation != "none" and not TASK_ID_RE.search(task_or_deviation):
            fail(
                f"Source Surface Matrix Closure row {area} / {row_name} must use `none` "
                "or cite a tracker task ID"
            )
        if not notes:
            fail(f"Source Surface Matrix Closure row {area} / {row_name} must have notes")

        fixture_paths = set(FIXTURE_PATH_RE.findall(fixtures))
        if not fixture_paths:
            fail(f"Source Surface Matrix Closure row {area} / {row_name} must list a manifest fixture")
        for fixture_path in sorted(fixture_paths):
            if fixture_path not in manifest_sources:
                fail(
                    f"Source Surface Matrix Closure row {area} / {row_name} references "
                    f"a fixture not in the manifest: {fixture_path}"
                )
        table_fixture_paths.update(fixture_paths)
        seen_rows.add(key)

    missing_rows = sorted(SOURCE_SURFACE_ROWS - seen_rows)
    if missing_rows:
        fail(
            "Source Surface Matrix Closure table is missing rows: "
            + ", ".join(f"{area} / {row}" for area, row in missing_rows)
        )

    missing_manifest_sources = sorted(source_surface_manifest_sources - table_fixture_paths)
    if missing_manifest_sources:
        fail(
            "source-surface manifest fixtures are missing from the closure table: "
            + ", ".join(missing_manifest_sources)
        )

    return len(seen_rows)


def validate_library_closure(
    matrix_text: str,
    manifest_sources_by_category: dict[str, set[str]],
) -> int:
    manifest_sources = {
        source_file
        for sources in manifest_sources_by_category.values()
        for source_file in sources
    }

    seen_rows: set[tuple[str, str]] = set()
    table_fixture_paths: set[str] = set()

    for area, report_surface, status, fixtures, task_or_deviation, notes in read_library_closure_rows(matrix_text):
        key = (area, report_surface)
        if key in seen_rows:
            fail(f"duplicate Library Conformance Closure row: {area} / {report_surface}")
        if key not in LIBRARY_CLOSURE_ROWS:
            fail(f"unexpected Library Conformance Closure row: {area} / {report_surface}")
        if not status:
            fail(f"Library Conformance Closure row {area} / {report_surface} must have a coverage status")
        if not task_or_deviation:
            fail(
                f"Library Conformance Closure row {area} / {report_surface} "
                "must have a remaining task/deviation"
            )
        if task_or_deviation != "none" and not TASK_ID_RE.search(task_or_deviation):
            fail(
                f"Library Conformance Closure row {area} / {report_surface} must use `none` "
                "or cite a tracker task ID"
            )
        if not notes:
            fail(f"Library Conformance Closure row {area} / {report_surface} must have notes")

        fixture_paths = set(FIXTURE_PATH_RE.findall(fixtures))
        if not fixture_paths:
            fail(f"Library Conformance Closure row {area} / {report_surface} must list a manifest fixture")
        for fixture_path in sorted(fixture_paths):
            if fixture_path not in manifest_sources:
                fail(
                    f"Library Conformance Closure row {area} / {report_surface} references "
                    f"a fixture not in the manifest: {fixture_path}"
                )
        table_fixture_paths.update(fixture_paths)
        seen_rows.add(key)

    missing_rows = sorted(LIBRARY_CLOSURE_ROWS - seen_rows)
    if missing_rows:
        fail(
            "Library Conformance Closure table is missing rows: "
            + ", ".join(f"{area} / {surface}" for area, surface in missing_rows)
        )

    missing_required_fixtures = sorted(LIBRARY_CLOSURE_REQUIRED_FIXTURES - table_fixture_paths)
    if missing_required_fixtures:
        fail(
            "library conformance fixtures are missing from the closure table: "
            + ", ".join(missing_required_fixtures)
        )

    return len(seen_rows)


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
    manifest_sources_by_category: dict[str, set[str]] = {}

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
        manifest_sources_by_category.setdefault(category, set()).add(source_file)

    duplicate_names = sorted({name for name in names if names.count(name) > 1})
    if duplicate_names:
        fail("duplicate case names: " + ", ".join(duplicate_names))

    source_surface_row_count = validate_source_surface_closure(matrix_text, manifest_sources_by_category)
    library_row_count = validate_library_closure(matrix_text, manifest_sources_by_category)

    print(
        "validated "
        f"{len(cases)} Haskell 2010 conformance cases; "
        f"source_surface_rows={source_surface_row_count}; "
        f"library_rows={library_row_count}; "
        f"statuses={dict(sorted(status_counts.items()))}; "
        f"categories={dict(sorted(category_counts.items()))}"
    )


if __name__ == "__main__":
    main()
