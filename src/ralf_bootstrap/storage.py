"""Read-only access to the future Bootstrap SQLite state."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from urllib.parse import quote

DEFAULT_DATABASE_PATH = Path("/var/lib/ralf/bootstrap/state.db")


def inspect_database(path: Path = DEFAULT_DATABASE_PATH) -> dict[str, object]:
    """Return a read-only summary without creating or changing a database."""

    database_path = Path(path)
    if not database_path.exists():
        return {"status": "not_initialized", "user_version": None}

    uri = f"file:{quote(str(database_path), safe='/')}?mode=ro"
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(uri, uri=True, timeout=0.2)
        row = connection.execute("PRAGMA user_version").fetchone()
        user_version = int(row[0]) if row else None
        return {"status": "ready", "user_version": user_version}
    except (OSError, sqlite3.Error, TypeError, ValueError):
        return {
            "status": "error",
            "user_version": None,
            "warning": "SQLite-Zustand konnte nicht read-only gelesen werden.",
        }
    finally:
        if connection is not None:
            connection.close()
