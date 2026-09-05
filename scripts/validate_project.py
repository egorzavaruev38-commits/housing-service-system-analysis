#!/usr/bin/env python3
"""Validate portfolio artifacts without third-party dependencies."""

from __future__ import annotations

import json
import re
import sqlite3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_json_files() -> dict:
    files = [ROOT / "api" / "openapi.json", *sorted((ROOT / "api" / "examples").glob("*.json"))]
    loaded = {}
    for path in files:
        with path.open("r", encoding="utf-8") as stream:
            loaded[path.name] = json.load(stream)
    return loaded


def check_openapi(document: dict) -> None:
    assert document.get("openapi", "").startswith("3.1."), "OpenAPI 3.1 is required"
    paths = document.get("paths")
    assert isinstance(paths, dict) and paths, "OpenAPI paths must not be empty"

    operation_ids: set[str] = set()
    methods = {"get", "post", "put", "patch", "delete", "options", "head", "trace"}
    for path, path_item in paths.items():
        assert path.startswith("/"), f"Invalid path: {path}"
        for method, operation in path_item.items():
            if method not in methods:
                continue
            operation_id = operation.get("operationId")
            assert operation_id, f"Missing operationId for {method.upper()} {path}"
            assert operation_id not in operation_ids, f"Duplicate operationId: {operation_id}"
            operation_ids.add(operation_id)
            responses = operation.get("responses", {})
            assert any(str(code).startswith("2") for code in responses), (
                f"Missing success response for {method.upper()} {path}"
            )

    required_operations = {
        "createRequest",
        "listRequests",
        "getRequest",
        "assignMaster",
        "changeRequestStatus",
        "getHealth",
    }
    assert required_operations <= operation_ids, "Required operations are missing"

    schemas = document.get("components", {}).get("schemas", {})
    for name in ("CreateRequest", "ServiceRequest", "Error", "RequestStatus"):
        assert name in schemas, f"Missing schema: {name}"


def check_examples(loaded: dict) -> None:
    request = loaded["create-request.json"]
    assert request["external_request_id"].startswith("REQ-")
    assert request["is_emergency"] is True
    assert request["resident"]["phone"].startswith("+")
    assert isinstance(request.get("attachments"), list)

    error = loaded["error-response.json"]
    assert {"code", "message", "correlation_id"} <= error.keys()

    event = loaded["status-event.json"]
    assert event["payload"]["previous_status"] != event["payload"]["new_status"]


def expect_integrity_error(action, label: str) -> None:
    try:
        action()
    except sqlite3.IntegrityError:
        return
    raise AssertionError(f"Expected database constraint failure: {label}")


def check_database() -> None:
    schema = (ROOT / "database" / "schema.sql").read_text(encoding="utf-8")
    seed = (ROOT / "database" / "seed.sql").read_text(encoding="utf-8")
    queries = (ROOT / "database" / "queries.sql").read_text(encoding="utf-8")

    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.executescript(schema)
    connection.executescript(seed)

    assert connection.execute("SELECT COUNT(*) FROM service_request").fetchone()[0] == 4
    assert connection.execute("SELECT COUNT(*) FROM request_status_history").fetchone()[0] == 4
    assert connection.execute("SELECT COUNT(*) FROM outbox_event").fetchone()[0] == 4

    def duplicate_external_id() -> None:
        connection.execute(
            """
            INSERT INTO service_request (
                external_request_id, resident_id, category, priority,
                description, complex_id, is_emergency
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            ("REQ-2026-0041", "RES-101", "other", "low", "Дубликат", "RC-01", 0),
        )

    expect_integrity_error(duplicate_external_id, "duplicate external_request_id")

    def invalid_emergency_priority() -> None:
        connection.execute(
            """
            INSERT INTO service_request (
                external_request_id, resident_id, category, priority,
                description, complex_id, is_emergency
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            ("REQ-TEST-EMERGENCY", "RES-101", "other", "low", "Аварийная", "RC-01", 1),
        )

    expect_integrity_error(invalid_emergency_priority, "emergency request without critical priority")

    request_id = connection.execute(
        "SELECT id FROM service_request WHERE external_request_id = 'REQ-2026-0041'"
    ).fetchone()[0]

    expect_integrity_error(
        lambda: connection.execute(
            "UPDATE service_request SET status = 'COMPLETED' WHERE id = ?", (request_id,)
        ),
        "CREATED to COMPLETED transition",
    )

    connection.execute(
        """
        UPDATE service_request
           SET assigned_master_id = 'MST-201', status = 'ASSIGNED',
               version = version + 1, updated_at = CURRENT_TIMESTAMP
         WHERE id = ?
        """,
        (request_id,),
    )
    connection.execute(
        """
        UPDATE service_request
           SET status = 'IN_PROGRESS', version = version + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = ?
        """,
        (request_id,),
    )

    status, version = connection.execute(
        "SELECT status, version FROM service_request WHERE id = ?", (request_id,)
    ).fetchone()
    assert status == "IN_PROGRESS" and version == 3
    assert connection.execute(
        "SELECT COUNT(*) FROM request_status_history WHERE request_id = ?", (request_id,)
    ).fetchone()[0] == 3
    assert connection.execute(
        "SELECT COUNT(*) FROM outbox_event WHERE aggregate_id = ?", (request_id,)
    ).fetchone()[0] == 3

    connection.executescript(queries)
    connection.close()


def check_readme_links() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", readme):
        if "://" in target or target.startswith("#"):
            continue
        path = ROOT / target.split("#", 1)[0]
        assert path.exists(), f"Broken local README link: {target}"


def main() -> int:
    checks = [
        ("JSON and examples", lambda: check_examples(check_json_files())),
        ("OpenAPI structure", lambda: check_openapi(check_json_files()["openapi.json"])),
        ("SQLite schema and rules", check_database),
        ("README links", check_readme_links),
    ]

    try:
        for label, check in checks:
            check()
            print(f"[OK] {label}")
    except (AssertionError, json.JSONDecodeError, sqlite3.Error, OSError) as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1

    print("All project checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
