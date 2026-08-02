"""Transactional SQLite persistence for the inventory-first controller."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
from typing import Iterator

from .catalog import load_catalog
from .models import (
    PREFERENCES,
    REQUIREMENTS,
    SECTIONS,
    ValidationError,
    canonical_json,
    normalize_text,
    require_choice,
    validate_identifier,
    validate_inventory,
)

SCHEMA_VERSION = 1


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def connect(database: Path, *, read_only: bool = False) -> sqlite3.Connection:
    path = Path(database)
    if read_only:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=1.0)
    else:
        connection = sqlite3.connect(path, timeout=3.0)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    if connection.execute("PRAGMA foreign_keys").fetchone()[0] != 1:
        connection.close()
        raise RuntimeError("SQLite-Fremdschlüssel konnten nicht aktiviert werden.")
    return connection


@contextmanager
def transaction(database: Path) -> Iterator[sqlite3.Connection]:
    connection = connect(database)
    try:
        connection.execute("BEGIN IMMEDIATE")
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


@contextmanager
def read_connection(database: Path) -> Iterator[sqlite3.Connection]:
    connection = connect(database, read_only=True)
    try:
        yield connection
    finally:
        connection.close()


def init_database(database: Path) -> None:
    """Create or validate schema only when explicitly invoked."""

    path = Path(database)
    if not path.parent.exists():
        raise FileNotFoundError(f"Elternverzeichnis fehlt: {path.parent}")
    with transaction(path) as connection:
        current = int(connection.execute("PRAGMA user_version").fetchone()[0])
        if current not in {0, SCHEMA_VERSION}:
            raise RuntimeError(f"Unbekannte Controller-Schemaversion: {current}")
        if current == SCHEMA_VERSION:
            return
        _migration_1(connection)
        catalog = load_catalog()
        now = utc_now()
        connection.execute(
            "INSERT INTO controller_meta(schema_version, catalog_version, created_at, updated_at) VALUES (?, ?, ?, ?)",
            (SCHEMA_VERSION, catalog.catalog_version, now, now),
        )
        connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")


def _migration_1(connection: sqlite3.Connection) -> None:
    schema = """
        CREATE TABLE controller_meta (
            schema_version INTEGER NOT NULL,
            catalog_version INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE setup_runs (
            id INTEGER PRIMARY KEY,
            status TEXT NOT NULL CHECK (status IN ('draft','inventory_review','requirements_review','preferences_review','plan_ready','plan_confirmed','blocked','obsolete')),
            revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE inventory_items (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            capability_id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            product_name TEXT NOT NULL DEFAULT '',
            location TEXT NOT NULL DEFAULT '',
            management_url TEXT,
            source TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('unknown','reported','verified','unavailable','conflict','declined')),
            verification_method TEXT CHECK (verification_method IS NULL OR verification_method IN ('manual','connector','local_probe','imported_evidence')),
            verification_scope TEXT NOT NULL DEFAULT '',
            verification_consent INTEGER NOT NULL DEFAULT 0 CHECK (verification_consent IN (0,1)),
            verification_evidence TEXT NOT NULL DEFAULT '',
            last_verified_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(setup_run_id, provider_id)
        );
        CREATE TABLE capability_requirements (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            capability_id TEXT NOT NULL,
            requirement TEXT NOT NULL CHECK (requirement IN ('required','optional','not_needed','deferred')),
            reason TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(setup_run_id, capability_id)
        );
        CREATE TABLE provider_preferences (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            capability_id TEXT NOT NULL,
            provider_reference TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            preference TEXT NOT NULL CHECK (preference IN ('preferred','allowed_fallback','excluded','deferred','recommend_then_confirm')),
            rank INTEGER CHECK (rank IS NULL OR rank > 0),
            reason TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(setup_run_id, capability_id, provider_reference)
        );
        CREATE UNIQUE INDEX one_preferred_provider
            ON provider_preferences(setup_run_id, capability_id)
            WHERE preference = 'preferred';
        CREATE UNIQUE INDEX unique_fallback_rank
            ON provider_preferences(setup_run_id, capability_id, rank)
            WHERE preference = 'allowed_fallback' AND rank IS NOT NULL;
        CREATE TABLE answers (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            question_id TEXT NOT NULL,
            answer_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(setup_run_id, question_id)
        );
        CREATE TABLE section_confirmations (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            section_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            confirmed_at TEXT NOT NULL,
            UNIQUE(setup_run_id, section_id)
        );
        CREATE TABLE plans (
            id INTEGER PRIMARY KEY,
            setup_run_id INTEGER NOT NULL REFERENCES setup_runs(id) ON DELETE CASCADE,
            revision INTEGER NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('draft','blocked','ready','confirmed','obsolete')),
            plan_hash TEXT NOT NULL,
            blockers_json TEXT NOT NULL DEFAULT '[]',
            open_checks_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL,
            confirmed_at TEXT,
            obsolete_reason TEXT
        );
        CREATE TABLE plan_steps (
            id INTEGER PRIMARY KEY,
            plan_id INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            step_type TEXT NOT NULL CHECK (step_type IN ('verify_provider','reuse_provider','resolve_conflict','decide_integration','install_provider','configure_provider','defer_capability','manual_action')),
            capability_id TEXT NOT NULL,
            provider_reference TEXT,
            state TEXT NOT NULL,
            title TEXT NOT NULL,
            rationale TEXT NOT NULL,
            prerequisites_json TEXT NOT NULL,
            expected_effects_json TEXT NOT NULL,
            mutation_class TEXT NOT NULL CHECK (mutation_class IN ('read_only','local_persistent','future_infrastructure')),
            UNIQUE(plan_id, position)
        );
        CREATE TABLE plan_confirmations (
            id INTEGER PRIMARY KEY,
            plan_id INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
            plan_hash TEXT NOT NULL,
            confirmed_at TEXT NOT NULL,
            confirmation_text_version INTEGER NOT NULL,
            UNIQUE(plan_id)
        );
        CREATE TABLE csrf_tokens (
            token_hash TEXT PRIMARY KEY,
            form_id TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            consumed_at TEXT
        );
        CREATE TABLE audit_events (
            id INTEGER PRIMARY KEY,
            event_type TEXT NOT NULL,
            object_type TEXT NOT NULL,
            object_id TEXT NOT NULL,
            before_hash TEXT,
            after_hash TEXT,
            created_at TEXT NOT NULL
        );
        """
    # executescript() may commit an already-open transaction. Executing each
    # fixed schema statement separately preserves the explicit migration transaction.
    for statement in schema.split(";"):
        if statement.strip():
            connection.execute(statement)


def schema_status(database: Path) -> dict[str, object]:
    path = Path(database)
    if not path.exists():
        return {"status": "not_initialized", "schema_version": None}
    try:
        with read_connection(path) as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version != SCHEMA_VERSION:
                return {"status": "unsupported", "schema_version": version}
            return {"status": "ready", "schema_version": version}
    except sqlite3.Error:
        return {"status": "error", "schema_version": None}


def create_setup_run(database: Path) -> int:
    now = utc_now()
    with transaction(database) as connection:
        cursor = connection.execute(
            "INSERT INTO setup_runs(status, revision, created_at, updated_at) VALUES ('draft', 1, ?, ?)",
            (now, now),
        )
        run_id = int(cursor.lastrowid)
        _audit(connection, "setup.started", "setup_run", str(run_id), None, _hash({"status": "draft"}))
        return run_id


def latest_run(database: Path) -> sqlite3.Row | None:
    with read_connection(database) as connection:
        return connection.execute("SELECT * FROM setup_runs ORDER BY id DESC LIMIT 1").fetchone()


def get_run(connection: sqlite3.Connection, run_id: int) -> sqlite3.Row:
    row = connection.execute("SELECT * FROM setup_runs WHERE id = ?", (run_id,)).fetchone()
    if row is None:
        raise ValidationError("Setup-Lauf wurde nicht gefunden.")
    return row


def list_rows(database: Path, table: str, run_id: int) -> list[dict[str, object]]:
    allowed = {"inventory_items", "capability_requirements", "provider_preferences", "answers", "section_confirmations"}
    if table not in allowed:
        raise ValueError("Unbekannte Tabelle")
    with read_connection(database) as connection:
        rows = connection.execute(
            f"SELECT * FROM {table} WHERE setup_run_id = ? ORDER BY id", (run_id,)
        ).fetchall()
        return [dict(row) for row in rows]


def get_inventory_item(database: Path, run_id: int, item_id: int) -> dict[str, object] | None:
    with read_connection(database) as connection:
        row = connection.execute(
            "SELECT * FROM inventory_items WHERE setup_run_id = ? AND id = ?", (run_id, item_id)
        ).fetchone()
        return dict(row) if row else None


def save_inventory(database: Path, run_id: int, values: dict[str, object], *, item_id: int | None = None) -> int:
    clean = validate_inventory(values)
    now = utc_now()
    with transaction(database) as connection:
        get_run(connection, run_id)
        before = None
        if item_id is None:
            cursor = connection.execute(
                """INSERT INTO inventory_items(
                    setup_run_id, capability_id, provider_id, display_name, product_name,
                    location, management_url, source, state, verification_method,
                    verification_scope, verification_consent, verification_evidence,
                    last_verified_at, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (run_id, *clean.values(), now, now),
            )
            item_id = int(cursor.lastrowid)
            event = "inventory.created"
        else:
            existing = connection.execute(
                "SELECT * FROM inventory_items WHERE setup_run_id = ? AND id = ?", (run_id, item_id)
            ).fetchone()
            if existing is None:
                raise ValidationError("Inventareintrag wurde nicht gefunden.")
            before = _hash(dict(existing))
            connection.execute(
                """UPDATE inventory_items SET capability_id=?, provider_id=?, display_name=?,
                    product_name=?, location=?, management_url=?, source=?, state=?,
                    verification_method=?, verification_scope=?, verification_consent=?,
                    verification_evidence=?, last_verified_at=?, updated_at=?
                   WHERE setup_run_id=? AND id=?""",
                (*clean.values(), now, run_id, item_id),
            )
            event = "inventory.updated"
        _invalidate(connection, run_id, {"inventory", "verification_scope"}, "Inventar geändert")
        _audit(connection, event, "inventory_item", str(item_id), before, _hash(clean))
        return item_id


def delete_inventory(database: Path, run_id: int, item_id: int) -> None:
    with transaction(database) as connection:
        row = connection.execute(
            "SELECT * FROM inventory_items WHERE setup_run_id=? AND id=?", (run_id, item_id)
        ).fetchone()
        if row is None:
            raise ValidationError("Inventareintrag wurde nicht gefunden.")
        connection.execute("DELETE FROM inventory_items WHERE id=?", (item_id,))
        _invalidate(connection, run_id, {"inventory", "verification_scope"}, "Inventar gelöscht")
        _audit(connection, "inventory.deleted", "inventory_item", str(item_id), _hash(dict(row)), None)


def save_requirement(database: Path, run_id: int, capability_id: str, requirement: str, reason: str = "") -> None:
    capability_id = validate_identifier(capability_id, "Fähigkeit")
    require_choice(requirement, REQUIREMENTS, "Anforderung")
    reason = normalize_text(reason, "Begründung", maximum=500, multiline=True)
    now = utc_now()
    with transaction(database) as connection:
        get_run(connection, run_id)
        connection.execute(
            """INSERT INTO capability_requirements(setup_run_id, capability_id, requirement, reason, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(setup_run_id, capability_id) DO UPDATE SET requirement=excluded.requirement,
               reason=excluded.reason, updated_at=excluded.updated_at""",
            (run_id, capability_id, requirement, reason, now, now),
        )
        _invalidate(connection, run_id, {"requirements"}, "Anforderung geändert")
        _audit(connection, "requirement.updated", "capability", capability_id, None, _hash({"requirement": requirement}))


def save_answer(database: Path, run_id: int, question_id: str, answer_json: str) -> None:
    question_id = validate_identifier(question_id, "Frage")
    try:
        json.loads(answer_json)
    except json.JSONDecodeError as exc:
        raise ValidationError("Antwort ist kein gültiges JSON.") from exc
    now = utc_now()
    with transaction(database) as connection:
        get_run(connection, run_id)
        connection.execute(
            """INSERT INTO answers(setup_run_id, question_id, answer_json, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(setup_run_id, question_id) DO UPDATE SET
               answer_json=excluded.answer_json, updated_at=excluded.updated_at""",
            (run_id, question_id, answer_json, now, now),
        )
        _invalidate(connection, run_id, set(SECTIONS), "Antwort geändert")
        _audit(connection, "answer.updated", "question", question_id, None, _hash(json.loads(answer_json)))


def save_preference(
    database: Path,
    run_id: int,
    capability_id: str,
    provider_reference: str,
    provider_id: str,
    preference: str,
    rank: int | None = None,
    reason: str = "",
) -> None:
    capability_id = validate_identifier(capability_id, "Fähigkeit")
    provider_id = validate_identifier(provider_id, "Provider")
    provider_reference = normalize_text(
        provider_reference, "Providerreferenz", maximum=160, required=True
    )
    reason = normalize_text(reason, "Begründung", maximum=500, multiline=True)
    require_choice(preference, PREFERENCES, "Präferenz")
    if rank is not None and (not isinstance(rank, int) or rank < 1):
        raise ValidationError("Fallbackrang muss eine positive Ganzzahl sein.")
    if preference != "allowed_fallback":
        rank = None
    now = utc_now()
    with transaction(database) as connection:
        get_run(connection, run_id)
        try:
            connection.execute(
                """INSERT INTO provider_preferences(setup_run_id, capability_id, provider_reference,
                   provider_id, preference, rank, reason, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(setup_run_id, capability_id, provider_reference) DO UPDATE SET
                   provider_id=excluded.provider_id, preference=excluded.preference, rank=excluded.rank,
                   reason=excluded.reason, updated_at=excluded.updated_at""",
                (run_id, capability_id, provider_reference, provider_id, preference, rank, reason, now, now),
            )
        except sqlite3.IntegrityError as exc:
            raise ValidationError("Pro Fähigkeit ist nur ein bevorzugter Provider und eine eindeutige Fallbackrangfolge erlaubt.") from exc
        _invalidate(connection, run_id, {"preferences"}, "Providerpräferenz geändert")
        _audit(connection, "preference.updated", "provider", provider_reference, None, _hash({"preference": preference, "rank": rank}))


def section_payload(connection: sqlite3.Connection, run_id: int, section: str) -> object:
    if section == "inventory":
        tables = ("inventory_items", "answers")
    elif section == "requirements":
        tables = ("capability_requirements",)
    elif section == "preferences":
        tables = ("provider_preferences",)
    elif section == "verification_scope":
        tables = ("inventory_items",)
    else:
        raise ValidationError("Unbekannter Bestätigungsabschnitt.")
    payload: dict[str, object] = {}
    for table in tables:
        rows = connection.execute(
            f"SELECT * FROM {table} WHERE setup_run_id=? ORDER BY id", (run_id,)
        ).fetchall()
        values = [dict(row) for row in rows]
        for value in values:
            for key in ("created_at", "updated_at"):
                value.pop(key, None)
        if section == "verification_scope":
            values = [
                {
                    key: value[key]
                    for key in ("id", "state", "verification_scope", "verification_consent")
                }
                for value in values
                if value["state"] == "reported"
            ]
        payload[table] = values
    return payload


def content_hash(connection: sqlite3.Connection, run_id: int, section: str) -> str:
    return _hash(section_payload(connection, run_id, section))


def confirm_section(database: Path, run_id: int, section: str) -> str:
    require_choice(section, SECTIONS, "Abschnitt")
    with transaction(database) as connection:
        get_run(connection, run_id)
        digest = content_hash(connection, run_id, section)
        now = utc_now()
        connection.execute(
            """INSERT INTO section_confirmations(setup_run_id, section_id, content_hash, confirmed_at)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(setup_run_id, section_id) DO UPDATE SET content_hash=excluded.content_hash,
               confirmed_at=excluded.confirmed_at""",
            (run_id, section, digest, now),
        )
        confirmed = {
            row["section_id"]
            for row in connection.execute(
                "SELECT section_id FROM section_confirmations WHERE setup_run_id=?", (run_id,)
            )
        }
        if confirmed & {"preferences", "verification_scope"}:
            run_status = "preferences_review"
        elif "requirements" in confirmed:
            run_status = "requirements_review"
        else:
            run_status = "inventory_review"
        connection.execute(
            "UPDATE setup_runs SET status=?, updated_at=? WHERE id=?", (run_status, now, run_id)
        )
        _audit(connection, "section.confirmed", "section", section, None, digest)
        return digest


def confirmation_status(database: Path, run_id: int) -> dict[str, bool]:
    with read_connection(database) as connection:
        get_run(connection, run_id)
        saved = {
            row["section_id"]: row["content_hash"]
            for row in connection.execute(
                "SELECT section_id, content_hash FROM section_confirmations WHERE setup_run_id=?", (run_id,)
            )
        }
        return {section: saved.get(section) == content_hash(connection, run_id, section) for section in sorted(SECTIONS)}


def store_plan(
    database: Path,
    run_id: int,
    status: str,
    plan_hash: str,
    steps: list[dict[str, object]],
    blockers: list[str],
    open_checks: list[str],
) -> int:
    now = utc_now()
    with transaction(database) as connection:
        run = get_run(connection, run_id)
        connection.execute(
            "UPDATE plans SET status='obsolete', obsolete_reason='Neuer Plan erzeugt' WHERE setup_run_id=? AND status!='obsolete'",
            (run_id,),
        )
        cursor = connection.execute(
            """INSERT INTO plans(setup_run_id, revision, status, plan_hash, blockers_json,
               open_checks_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (run_id, run["revision"], status, plan_hash, canonical_json(blockers), canonical_json(open_checks), now),
        )
        plan_id = int(cursor.lastrowid)
        for position, step in enumerate(steps, 1):
            connection.execute(
                """INSERT INTO plan_steps(plan_id, position, step_type, capability_id,
                   provider_reference, state, title, rationale, prerequisites_json,
                   expected_effects_json, mutation_class) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    plan_id,
                    position,
                    step["step_type"],
                    step["capability_id"],
                    step.get("provider_reference"),
                    step["state"],
                    step["title"],
                    step["rationale"],
                    canonical_json(step["prerequisites"]),
                    canonical_json(step["expected_effects"]),
                    step["mutation_class"],
                ),
            )
        run_status = "blocked" if status == "blocked" else "plan_ready"
        connection.execute("UPDATE setup_runs SET status=?, updated_at=? WHERE id=?", (run_status, now, run_id))
        _audit(connection, "plan.generated", "plan", str(plan_id), None, plan_hash)
        return plan_id


def current_plan(database: Path, run_id: int) -> dict[str, object] | None:
    with read_connection(database) as connection:
        row = connection.execute(
            "SELECT * FROM plans WHERE setup_run_id=? AND status!='obsolete' ORDER BY id DESC LIMIT 1",
            (run_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["blockers"] = json.loads(result.pop("blockers_json"))
        result["open_checks"] = json.loads(result.pop("open_checks_json"))
        steps = connection.execute("SELECT * FROM plan_steps WHERE plan_id=? ORDER BY position", (row["id"],)).fetchall()
        result["steps"] = []
        for step in steps:
            value = dict(step)
            value["prerequisites"] = json.loads(value.pop("prerequisites_json"))
            value["expected_effects"] = json.loads(value.pop("expected_effects_json"))
            result["steps"].append(value)
        return result


def confirm_plan(database: Path, run_id: int, plan_hash: str) -> None:
    with transaction(database) as connection:
        plan = connection.execute(
            "SELECT * FROM plans WHERE setup_run_id=? AND status='ready' ORDER BY id DESC LIMIT 1",
            (run_id,),
        ).fetchone()
        if plan is None or plan["plan_hash"] != plan_hash:
            raise ValidationError("Nur der unveränderte bereite Zielplan kann bestätigt werden.")
        now = utc_now()
        connection.execute(
            "INSERT INTO plan_confirmations(plan_id, plan_hash, confirmed_at, confirmation_text_version) VALUES (?, ?, ?, 1)",
            (plan["id"], plan_hash, now),
        )
        connection.execute("UPDATE plans SET status='confirmed', confirmed_at=? WHERE id=?", (now, plan["id"]))
        connection.execute("UPDATE setup_runs SET status='plan_confirmed', updated_at=? WHERE id=?", (now, run_id))
        _audit(connection, "plan.confirmed", "plan", str(plan["id"]), None, plan_hash)


def audit_events(database: Path) -> list[dict[str, object]]:
    with read_connection(database) as connection:
        return [dict(row) for row in connection.execute("SELECT * FROM audit_events ORDER BY id")]


def _invalidate(connection: sqlite3.Connection, run_id: int, sections: set[str], reason: str) -> None:
    now = utc_now()
    placeholders = ",".join("?" for _ in sections)
    connection.execute(
        f"DELETE FROM section_confirmations WHERE setup_run_id=? AND section_id IN ({placeholders})",
        (run_id, *sorted(sections)),
    )
    plans = connection.execute(
        "SELECT id, plan_hash FROM plans WHERE setup_run_id=? AND status!='obsolete'", (run_id,)
    ).fetchall()
    for plan in plans:
        connection.execute("DELETE FROM plan_confirmations WHERE plan_id=?", (plan["id"],))
        _audit(connection, "plan.invalidated", "plan", str(plan["id"]), plan["plan_hash"], None)
    connection.execute(
        "UPDATE plans SET status='obsolete', obsolete_reason=? WHERE setup_run_id=? AND status!='obsolete'",
        (reason, run_id),
    )
    connection.execute(
        "UPDATE setup_runs SET revision=revision+1, status='draft', updated_at=? WHERE id=?",
        (now, run_id),
    )


def _audit(
    connection: sqlite3.Connection,
    event_type: str,
    object_type: str,
    object_id: str,
    before_hash: str | None,
    after_hash: str | None,
) -> None:
    connection.execute(
        "INSERT INTO audit_events(event_type, object_type, object_id, before_hash, after_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        (event_type, object_type, object_id, before_hash, after_hash, utc_now()),
    )


def _hash(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()
