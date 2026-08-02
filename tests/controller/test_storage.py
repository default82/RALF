from __future__ import annotations

import sqlite3

import pytest

from ralf_bootstrap.controller.storage import SCHEMA_VERSION, connect, init_database, transaction
from ralf_bootstrap.controller_db import main


def test_import_does_not_create_database(tmp_path):
    path = tmp_path / "missing" / "state.db"
    import ralf_bootstrap.controller.storage  # noqa: F401
    assert not path.exists()


def test_explicit_init_is_idempotent_and_enables_foreign_keys(controller_db):
    before = controller_db.stat().st_size
    init_database(controller_db)
    with connect(controller_db) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1
    assert controller_db.stat().st_size == before


def test_cli_initializes_only_explicit_target(tmp_path, capsys):
    path = tmp_path / "state.db"
    assert main(["init", "--database", str(path)]) == 0
    assert path.exists()
    assert "Schema 2" in capsys.readouterr().out


def _create_schema_1(path):
    from ralf_bootstrap.controller.storage import _migration_1

    with sqlite3.connect(path) as connection:
        _migration_1(connection)
        connection.execute(
            "INSERT INTO controller_meta VALUES (1, 1, '2026-08-02T00:00:00Z', '2026-08-02T00:00:00Z')"
        )
        connection.execute("PRAGMA user_version=1")


def test_schema_1_is_explicitly_migrated_to_schema_2(tmp_path):
    path = tmp_path / "state.db"
    _create_schema_1(path)
    init_database(path)
    with connect(path, read_only=True) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 2
        assert connection.execute("SELECT schema_version FROM controller_meta").fetchone()[0] == 2
        assert connection.execute(
            "SELECT name FROM sqlite_master WHERE name='verification_requests'"
        ).fetchone()


def test_app_and_status_do_not_auto_migrate_schema_1(tmp_path):
    from ralf_bootstrap.app import create_app
    from ralf_bootstrap.controller.storage import schema_status

    path = tmp_path / "state.db"
    _create_schema_1(path)
    assert schema_status(path) == {"status": "migration_required", "schema_version": 1}
    create_app(database_path=path).test_client().get("/controller/")
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 1


def test_schema_1_to_2_failure_rolls_back(tmp_path, monkeypatch):
    path = tmp_path / "state.db"
    _create_schema_1(path)

    def broken(connection):
        connection.execute("CREATE TABLE partial_v2(id INTEGER)")
        raise RuntimeError("migration 2 failed")

    monkeypatch.setattr("ralf_bootstrap.controller.storage._migration_2", broken)
    with pytest.raises(RuntimeError, match="migration 2 failed"):
        init_database(path)
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 1
        assert connection.execute(
            "SELECT name FROM sqlite_master WHERE name='partial_v2'"
        ).fetchone() is None


def test_unknown_schema_is_rejected(tmp_path):
    path = tmp_path / "state.db"
    with sqlite3.connect(path) as connection:
        connection.execute("PRAGMA user_version=99")
    with pytest.raises(RuntimeError, match="Unbekannte"):
        init_database(path)


def test_transaction_failure_leaves_no_partial_state(controller_db):
    with pytest.raises(RuntimeError):
        with transaction(controller_db) as connection:
            connection.execute("INSERT INTO setup_runs(status,revision,created_at,updated_at) VALUES ('draft',1,'x','x')")
            raise RuntimeError("stop")
    with connect(controller_db, read_only=True) as connection:
        assert connection.execute("SELECT COUNT(*) FROM setup_runs").fetchone()[0] == 0


def test_migration_failure_rolls_back_schema(tmp_path, monkeypatch):
    path = tmp_path / "state.db"

    def broken(connection):
        connection.execute("CREATE TABLE partial(id INTEGER)")
        raise RuntimeError("migration failed")

    monkeypatch.setattr("ralf_bootstrap.controller.storage._migration_1", broken)
    with pytest.raises(RuntimeError, match="migration failed"):
        init_database(path)
    with sqlite3.connect(path) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 0
        assert connection.execute("SELECT name FROM sqlite_master WHERE name='partial'").fetchone() is None


def test_schema_contains_no_password_or_credential_fields(controller_db):
    with connect(controller_db, read_only=True) as connection:
        columns = [
            row[1].lower()
            for table in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
            for row in connection.execute(f"PRAGMA table_info({table[0]})")
        ]
    assert not any(word in column for column in columns for word in ("password", "credential", "private_key", "plaintext"))
