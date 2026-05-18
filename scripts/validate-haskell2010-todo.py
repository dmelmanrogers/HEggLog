#!/usr/bin/env python3
"""Validate the Haskell 2010 engineering backlog documents."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "docs" / "haskell2010-todo.json"
MARKDOWN_PATH = ROOT / "docs" / "haskell2010-todo.md"

ALLOWED_STATUSES = {
    "not started",
    "in progress",
    "blocked",
    "complete",
    "deferred",
    "documented deviation",
}

ALLOWED_CATEGORIES = {
    "frontend",
    "renamer",
    "typechecker",
    "core",
    "egglog",
    "stg",
    "runtime",
    "llvm",
    "libraries",
    "modules",
    "diagnostics",
    "testing",
    "docs",
    "cli",
    "release",
}

TASK_HEADING_RE = re.compile(r"^## ([A-Z][A-Z0-9-]*-\d{3}) — .+$", re.MULTILINE)


def fail(message: str) -> None:
    print(f"haskell2010 todo validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_tasks() -> list[dict[str, object]]:
    try:
        raw = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing {JSON_PATH.relative_to(ROOT)}")
    except json.JSONDecodeError as err:
        fail(f"invalid JSON in {JSON_PATH.relative_to(ROOT)}: {err}")

    if not isinstance(raw, dict):
        fail("JSON root must be an object")
    tasks = raw.get("tasks")
    if not isinstance(tasks, list):
        fail("JSON root must contain a tasks array")
    for task in tasks:
        if not isinstance(task, dict):
            fail("every task must be an object")
    return tasks


def markdown_task_ids() -> set[str]:
    try:
        markdown = MARKDOWN_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing {MARKDOWN_PATH.relative_to(ROOT)}")
    return set(TASK_HEADING_RE.findall(markdown))


def require_nonempty_list(task_id: str, task: dict[str, object], key: str) -> None:
    value = task.get(key)
    if not isinstance(value, list) or not value:
        fail(f"{task_id} must have a nonempty {key} list")
    if not all(isinstance(item, str) and item.strip() for item in value):
        fail(f"{task_id} has invalid {key} entries")


def main() -> None:
    tasks = load_tasks()
    ids: list[str] = []

    for task in tasks:
        task_id = task.get("id")
        if not isinstance(task_id, str) or not task_id.strip():
            fail("every task must have a nonempty id")
        ids.append(task_id)

    duplicate_ids = sorted({task_id for task_id in ids if ids.count(task_id) > 1})
    if duplicate_ids:
        fail(f"duplicate task IDs: {', '.join(duplicate_ids)}")

    id_set = set(ids)

    for task in tasks:
        task_id = str(task["id"])
        for key in ["title", "status", "category", "milestone"]:
            value = task.get(key)
            if not isinstance(value, str) or not value.strip():
                fail(f"{task_id} must have a nonempty {key}")
        if task["status"] not in ALLOWED_STATUSES:
            fail(f"{task_id} has invalid status {task['status']!r}")
        if task["category"] not in ALLOWED_CATEGORIES:
            fail(f"{task_id} has invalid category {task['category']!r}")

        for key in ["depends_on", "blocks", "docs"]:
            value = task.get(key)
            if not isinstance(value, list):
                fail(f"{task_id} must have a {key} list")
            if not all(isinstance(item, str) for item in value):
                fail(f"{task_id} has non-string {key} entries")

        require_nonempty_list(task_id, task, "acceptance_criteria")
        require_nonempty_list(task_id, task, "required_tests")

        for dep in task["depends_on"]:
            if dep not in id_set:
                fail(f"{task_id} depends on unknown task {dep}")
        for blocked in task["blocks"]:
            if blocked not in id_set:
                fail(f"{task_id} blocks unknown task {blocked}")

    md_ids = markdown_task_ids()
    json_only = sorted(id_set - md_ids)
    markdown_only = sorted(md_ids - id_set)
    if json_only:
        fail("task IDs in JSON but missing from markdown: " + ", ".join(json_only))
    if markdown_only:
        fail("task IDs in markdown but missing from JSON: " + ", ".join(markdown_only))

    print(f"validated {len(tasks)} Haskell 2010 backlog tasks")


if __name__ == "__main__":
    main()
