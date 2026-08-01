from __future__ import annotations

import os
import sqlite3

from ralf_bootstrap.storage import inspect_database


def test_missing_database_is_not_initialized(tmp_path):
    path = tmp_path / "state.db"
    assert inspect_database(path) == {"status": "not_initialized", "user_version": None}
    assert not path.exists()


def test_existing_database_is_read_only_and_reports_version(tmp_path):
    path = tmp_path / "state.db"
    with sqlite3.connect(path) as connection:
        connection.execute("PRAGMA user_version = 7")
    before = (path.stat().st_size, path.stat().st_mtime_ns)

    assert inspect_database(path) == {"status": "ready", "user_version": 7}
    after = (path.stat().st_size, path.stat().st_mtime_ns)
    assert after == before


def test_corrupt_database_returns_warning_without_raising(tmp_path):
    path = tmp_path / "state.db"
    path.write_bytes(b"not a sqlite database")

    result = inspect_database(path)

    assert result["status"] == "error"
    assert result["user_version"] is None
    assert "warning" in result


def test_production_path_is_not_created(tmp_path):
    missing = tmp_path / "nested" / "state.db"
    inspect_database(missing)
    assert not missing.parent.exists()
