"""Local verification orders, redacted evidence and deterministic assessments.

This module deliberately has no executor, network client or process launcher.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import sqlite3

from .contracts import COMPLETING_METHODS, ProviderContract, load_contracts
from .models import (
    CLAIM_RESULTS,
    EVIDENCE_CONFIDENTIALITY,
    EVIDENCE_KINDS,
    ValidationError,
    canonical_json,
    normalize_text,
    require_choice,
)
from .storage import _audit, _hash, get_run, read_connection, transaction, utc_now

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_FORBIDDEN_EVIDENCE = re.compile(
    r"(?i)(password\s*[:=]|passwd\s*[:=]|api[_ -]?token\s*[:=]|authorization\s*:|-----BEGIN [A-Z ]*PRIVATE KEY-----|session[_ -]?cookie\s*[:=])"
)


def create_verification_request(
    database: Path, run_id: int, inventory_item_id: int, contract_id: str
) -> int:
    catalog = load_contracts()
    contract = catalog.get(contract_id)
    now = utc_now()
    with transaction(database) as connection:
        get_run(connection, run_id)
        item = connection.execute(
            "SELECT * FROM inventory_items WHERE id=? AND setup_run_id=?",
            (inventory_item_id, run_id),
        ).fetchone()
        if item is None:
            raise ValidationError("Verifikationsauftrag benoetigt einen vorhandenen Inventareintrag.")
        if item["provider_id"] != contract.provider_id or item["capability_id"] != contract.capability_id:
            raise ValidationError("Providervertrag passt nicht zum Inventareintrag.")
        active = connection.execute(
            """SELECT id FROM verification_requests
               WHERE inventory_item_id=? AND contract_id=?
                 AND state NOT IN ('completed','failed','declined','obsolete')""",
            (inventory_item_id, contract.contract_id),
        ).fetchone()
        if active is not None:
            raise ValidationError("Fuer diesen Provider besteht bereits ein aktiver Verifikationsauftrag.")
        snapshot = inventory_snapshot(dict(item))
        scope = scope_payload(contract, snapshot)
        scope_hash = _hash(scope)
        target_hash = _hash(snapshot)
        cursor = connection.execute(
            """INSERT INTO verification_requests(
                 setup_run_id, inventory_item_id, contract_id, contract_version,
                 contract_hash, state, scope_hash, target_snapshot_hash,
                 created_at, updated_at, completed_at, obsolete_reason
               ) VALUES (?, ?, ?, ?, ?, 'awaiting_consent', ?, ?, ?, ?, NULL, NULL)""",
            (
                run_id,
                inventory_item_id,
                contract.contract_id,
                contract.contract_version,
                contract.contract_hash,
                scope_hash,
                target_hash,
                now,
                now,
            ),
        )
        request_id = int(cursor.lastrowid)
        for position, claim in enumerate(contract.claims, 1):
            method = next(method for method in claim.accepted_methods if method in COMPLETING_METHODS)
            connection.execute(
                """INSERT INTO verification_tasks(
                     verification_request_id, position, task_id, method, title,
                     description, data_categories_json, state
                   ) VALUES (?, ?, ?, ?, ?, ?, ?, 'planned')""",
                (
                    request_id,
                    position,
                    claim.claim_id,
                    method,
                    claim.title,
                    claim.description,
                    canonical_json(list(claim.data_categories)),
                ),
            )
        _audit(
            connection,
            "verification.request_created",
            "verification_request",
            str(request_id),
            None,
            _hash({"contract_hash": contract.contract_hash, "scope_hash": scope_hash}),
        )
        return request_id


def inventory_snapshot(item: dict[str, object]) -> dict[str, object]:
    return {
        key: item.get(key)
        for key in (
            "id",
            "setup_run_id",
            "capability_id",
            "provider_id",
            "display_name",
            "product_name",
            "location",
            "management_url",
            "source",
            "state",
        )
    }


def scope_payload(contract: ProviderContract, target: dict[str, object]) -> dict[str, object]:
    return {
        "target": target,
        "contract": {
            "contract_id": contract.contract_id,
            "contract_version": contract.contract_version,
            "contract_hash": contract.contract_hash,
        },
        "claims": [
            {
                "claim_id": claim.claim_id,
                "required": claim.required,
                "accepted_methods": list(claim.accepted_methods),
                "data_categories": list(claim.data_categories),
            }
            for claim in contract.claims
        ],
        "excluded_data": [
            "passwords",
            "api_tokens",
            "private_keys",
            "session_cookies",
            "full_configuration_export",
            "unredacted_logs",
            "user_database",
        ],
        "executor": None,
    }


def confirm_verification_scope(
    database: Path,
    request_id: int,
    *,
    scope_hash: str,
    lifetime_seconds: int = 86400,
) -> None:
    if lifetime_seconds < 60 or lifetime_seconds > 2592000:
        raise ValidationError("Zustimmung besitzt eine ungueltige Gueltigkeitsdauer.")
    request_row, contract, item = _current_request(database, request_id)
    scope = scope_payload(contract, inventory_snapshot(item))
    expected_hash = _hash(scope)
    if scope_hash != expected_hash or request_row["scope_hash"] != expected_hash:
        raise ValidationError("Zustimmung stimmt nicht mit dem aktuellen Verifikationsumfang ueberein.")
    now_dt = datetime.now(timezone.utc)
    now = _format_time(now_dt)
    expires = _format_time(now_dt + timedelta(seconds=lifetime_seconds))
    with transaction(database) as connection:
        connection.execute(
            "UPDATE verification_consents SET revoked_at=? WHERE verification_request_id=? AND revoked_at IS NULL",
            (now, request_id),
        )
        connection.execute(
            """INSERT INTO verification_consents(
                 verification_request_id, scope_json, scope_hash, confirmed_at, expires_at, revoked_at
               ) VALUES (?, ?, ?, ?, ?, NULL)""",
            (request_id, canonical_json(scope), expected_hash, now, expires),
        )
        connection.execute(
            "UPDATE verification_requests SET state='ready', updated_at=? WHERE id=?",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='consented' WHERE verification_request_id=?",
            (request_id,),
        )
        _audit(connection, "verification.scope_confirmed", "verification_request", str(request_id), None, expected_hash)


def revoke_verification_scope(database: Path, request_id: int) -> None:
    now = utc_now()
    with transaction(database) as connection:
        row = _request_row(connection, request_id)
        if row["state"] in {"completed", "declined", "obsolete"}:
            raise ValidationError("Dieser Verifikationsauftrag kann nicht widerrufen werden.")
        changed = connection.execute(
            "UPDATE verification_consents SET revoked_at=? WHERE verification_request_id=? AND revoked_at IS NULL",
            (now, request_id),
        ).rowcount
        if changed != 1:
            raise ValidationError("Es besteht keine wirksame Zustimmung.")
        connection.execute(
            "UPDATE verification_requests SET state='awaiting_consent', updated_at=? WHERE id=?",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='planned' WHERE verification_request_id=? AND state!='obsolete'",
            (request_id,),
        )
        _audit(connection, "verification.scope_revoked", "verification_request", str(request_id), None, None)


def decline_verification(database: Path, request_id: int) -> None:
    now = utc_now()
    with transaction(database) as connection:
        row = _request_row(connection, request_id)
        if row["state"] in {"completed", "obsolete"}:
            raise ValidationError("Dieser Auftrag kann nicht abgelehnt werden.")
        connection.execute(
            "UPDATE verification_consents SET revoked_at=? WHERE verification_request_id=? AND revoked_at IS NULL",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_requests SET state='declined', updated_at=? WHERE id=?",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='declined' WHERE verification_request_id=?",
            (request_id,),
        )
        _audit(connection, "verification.request_declined", "verification_request", str(request_id), None, None)


def add_evidence(
    database: Path,
    request_id: int,
    *,
    claim_id: str,
    kind: str,
    source: str,
    summary: str,
    verification_method: str,
    observed_at: str,
    valid_until: str,
    confidentiality: str = "internal",
    digest: str | None = None,
    supersedes_id: int | None = None,
) -> int:
    request_row, contract, _item = _current_request(database, request_id)
    _require_effective_consent(database, request_id)
    if request_row["state"] in {"completed", "failed", "declined", "obsolete"}:
        raise ValidationError("Dieser Auftrag nimmt keine Evidenz mehr an.")
    claim = _contract_claim(contract, claim_id)
    require_choice(kind, EVIDENCE_KINDS, "Evidenzart")
    require_choice(confidentiality, EVIDENCE_CONFIDENTIALITY, "Vertraulichkeit")
    if verification_method not in COMPLETING_METHODS or verification_method not in claim.accepted_methods:
        raise ValidationError("Verifikationsmethode ist fuer diesen Claim nicht zulaessig.")
    source = normalize_text(source, "Evidenzquelle", maximum=200, required=True)
    summary = normalize_text(summary, "Evidenzzusammenfassung", maximum=2000, required=True, multiline=True)
    if _FORBIDDEN_EVIDENCE.search(summary) or _FORBIDDEN_EVIDENCE.search(source):
        raise ValidationError("Evidenz darf keine Zugangsdaten oder Geheimnisse enthalten.")
    observed = _parse_time(observed_at, "Beobachtungszeitpunkt")
    valid = _parse_time(valid_until, "Gueltigkeitszeitpunkt")
    if valid <= observed:
        raise ValidationError("Evidenz muss nach ihrem Beobachtungszeitpunkt gueltig sein.")
    if valid > observed + timedelta(seconds=claim.freshness_seconds):
        raise ValidationError("Evidenz ist laenger gueltig als der Claim-Vertrag erlaubt.")
    digest_value = digest.lower() if digest else None
    if digest_value is not None and not _SHA256_RE.fullmatch(digest_value):
        raise ValidationError("Evidenzdigest muss ein SHA-256-Hexwert sein.")
    now = utc_now()
    with transaction(database) as connection:
        if supersedes_id is not None:
            prior = connection.execute(
                "SELECT * FROM verification_evidence WHERE id=? AND verification_request_id=? AND claim_id=?",
                (supersedes_id, request_id, claim_id),
            ).fetchone()
            if prior is None:
                raise ValidationError("Zu ersetzende Evidenz wurde nicht gefunden.")
            already = connection.execute(
                "SELECT id FROM verification_evidence WHERE supersedes_id=?", (supersedes_id,)
            ).fetchone()
            if already is not None:
                raise ValidationError("Evidenz wurde bereits durch einen neueren Eintrag ersetzt.")
        cursor = connection.execute(
            """INSERT INTO verification_evidence(
                 verification_request_id, claim_id, kind, source, summary,
                 verification_method, observed_at, valid_until, digest_algorithm,
                 digest, confidentiality, created_at, supersedes_id
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                request_id,
                claim_id,
                kind,
                source,
                summary,
                verification_method,
                _format_time(observed),
                _format_time(valid),
                "sha256" if digest_value else None,
                digest_value,
                confidentiality,
                now,
                supersedes_id,
            ),
        )
        evidence_id = int(cursor.lastrowid)
        connection.execute(
            "UPDATE verification_requests SET state='evidence_pending', updated_at=? WHERE id=?",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='evidence_pending' WHERE verification_request_id=? AND task_id=?",
            (request_id, claim_id),
        )
        event = "verification.evidence_superseded" if supersedes_id else "verification.evidence_added"
        _audit(connection, event, "verification_evidence", str(evidence_id), None, _hash({"claim_id": claim_id, "digest": digest_value}))
        return evidence_id


def assess_claim(
    database: Path,
    request_id: int,
    claim_id: str,
    result: str,
    rationale: str,
) -> None:
    _request, contract, _item = _current_request(database, request_id)
    _require_effective_consent(database, request_id)
    claim = _contract_claim(contract, claim_id)
    require_choice(result, CLAIM_RESULTS, "Claim-Ergebnis")
    rationale = normalize_text(rationale, "Bewertungsgrund", maximum=1000, required=True, multiline=True)
    active = _active_evidence(database, request_id, claim_id)
    if result in {"satisfied", "not_satisfied", "conflict", "stale"} and not active:
        raise ValidationError("Diese Claim-Bewertung benoetigt zugeordnete Evidenz.")
    if result == "not_applicable" and claim.required:
        raise ValidationError("Erforderlicher Claim darf nicht nicht-anwendbar sein.")
    valid_until = min((row["valid_until"] for row in active), default=None)
    now = utc_now()
    with transaction(database) as connection:
        connection.execute(
            """INSERT INTO verification_claim_results(
                 verification_request_id, claim_id, result, rationale, assessed_at, valid_until
               ) VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(verification_request_id, claim_id) DO UPDATE SET
                 result=excluded.result, rationale=excluded.rationale,
                 assessed_at=excluded.assessed_at, valid_until=excluded.valid_until""",
            (request_id, claim_id, result, rationale, now, valid_until),
        )
        connection.execute(
            "UPDATE verification_requests SET state='review_pending', updated_at=? WHERE id=?",
            (now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='completed' WHERE verification_request_id=? AND task_id=?",
            (request_id, claim_id),
        )
        connection.execute("DELETE FROM verification_reviews WHERE verification_request_id=?", (request_id,))
        _audit(connection, "verification.claim_updated", "verification_request", str(request_id), None, _hash({"claim_id": claim_id, "result": result}))
        _audit(connection, "verification.claim_assessed", "verification_request", str(request_id), None, _hash({"claim_id": claim_id, "result": result}))


def assessment_preview(
    database: Path, request_id: int, *, now: str | None = None
) -> dict[str, object]:
    request_row, contract, item = _current_request(database, request_id, allow_terminal=True)
    current = _parse_time(now or utc_now(), "Bewertungszeitpunkt")
    with read_connection(database) as connection:
        rows = connection.execute(
            "SELECT * FROM verification_claim_results WHERE verification_request_id=? ORDER BY claim_id",
            (request_id,),
        ).fetchall()
    saved = {row["claim_id"]: dict(row) for row in rows}
    effective: dict[str, str] = {}
    for claim in contract.claims:
        row = saved.get(claim.claim_id)
        result = str(row["result"]) if row else "unknown"
        if row and row["valid_until"] and _parse_time(row["valid_until"], "Gueltigkeit") <= current:
            result = "stale"
        effective[claim.claim_id] = result

    presence_claims = [c for c in contract.claims if c.required and c.category in {"identity", "presence", "health"}]
    compatibility_claims = [c for c in contract.claims if c.required and c.category in {"capability", "security"}]
    integration_claims = [c for c in contract.claims if c.required and c.category == "integration"]
    presence_values = [effective[c.claim_id] for c in presence_claims]
    compatibility_values = [effective[c.claim_id] for c in compatibility_claims]
    integration_values = [effective[c.claim_id] for c in integration_claims]

    if "conflict" in presence_values:
        presence = "conflict"
    elif "not_satisfied" in presence_values:
        presence = "unavailable"
    elif presence_values and all(value == "satisfied" for value in presence_values):
        presence = "verified"
    else:
        presence = "reported" if item["state"] == "reported" else "unknown"

    if "conflict" in compatibility_values:
        compatibility = "conflict"
    elif "not_satisfied" in compatibility_values:
        compatibility = "incompatible"
    elif compatibility_values and all(value == "satisfied" for value in compatibility_values):
        compatibility = "compatible"
    elif any(value == "satisfied" for value in compatibility_values):
        compatibility = "partially_compatible"
    else:
        compatibility = "unknown"

    if "conflict" in integration_values:
        readiness = "conflict"
    elif integration_values and all(value == "satisfied" for value in integration_values):
        readiness = "ready"
    else:
        readiness = "blocked"

    verification_values = [
        effective[c.claim_id]
        for c in contract.claims
        if c.required and c.category != "integration"
    ]
    if any(value == "stale" for value in verification_values):
        freshness = "stale"
    elif verification_values and all(
        value not in {"unknown", "not_observed"} for value in verification_values
    ):
        freshness = "fresh"
    else:
        freshness = "never_verified"

    blockers = [
        f"Offener erforderlicher Claim: {claim.claim_id}"
        for claim in contract.claims
        if claim.required and effective[claim.claim_id] in {"unknown", "not_observed", "not_satisfied", "stale", "conflict"}
    ]
    if contract.contract_id == "secure-ingress.opnsense-caddy" and readiness != "ready":
        blockers.append("O-012: Sicherer Backendpfad vom OPNsense-Caddy zu RALF ist nicht entschieden.")
    warnings = []
    if freshness == "stale":
        warnings.append("Mindestens ein erforderlicher Nachweis ist veraltet.")
    canonical = {
        "verification_request_id": request_id,
        "contract_hash": request_row["contract_hash"],
        "effective_claims": effective,
        "provider_presence": presence,
        "contract_compatibility": compatibility,
        "integration_readiness": readiness,
        "freshness": freshness,
        "blockers": sorted(set(blockers)),
        "warnings": sorted(set(warnings)),
    }
    canonical["assessment_hash"] = _hash(canonical)
    return canonical


def review_content_hash(database: Path, request_id: int) -> str:
    preview = assessment_preview(database, request_id)
    with read_connection(database) as connection:
        evidence = connection.execute(
            """SELECT id, claim_id, kind, source, verification_method, observed_at,
                      valid_until, digest_algorithm, digest, confidentiality, supersedes_id
               FROM verification_evidence WHERE verification_request_id=? ORDER BY id""",
            (request_id,),
        ).fetchall()
    return _hash({"assessment": preview, "evidence": [dict(row) for row in evidence]})


def confirm_verification_review(database: Path, request_id: int, content_hash: str) -> None:
    expected = review_content_hash(database, request_id)
    if content_hash != expected:
        raise ValidationError("Review stimmt nicht mit Evidenz und Claim-Bewertungen ueberein.")
    now = utc_now()
    with transaction(database) as connection:
        row = _request_row(connection, request_id)
        if row["state"] in {"declined", "obsolete", "completed"}:
            raise ValidationError("Dieser Auftrag kann nicht bestaetigt werden.")
        connection.execute(
            "INSERT INTO verification_reviews(verification_request_id, content_hash, confirmed_at) VALUES (?, ?, ?)",
            (request_id, expected, now),
        )
        connection.execute(
            "UPDATE verification_requests SET state='review_pending', updated_at=? WHERE id=?",
            (now, request_id),
        )
        _audit(connection, "verification.review_confirmed", "verification_request", str(request_id), None, expected)


def complete_verification(database: Path, request_id: int) -> dict[str, object]:
    _require_effective_consent(database, request_id)
    content = review_content_hash(database, request_id)
    assessment = assessment_preview(database, request_id)
    now = utc_now()
    with transaction(database) as connection:
        request_row = _request_row(connection, request_id)
        if request_row["state"] in {"declined", "obsolete", "completed"}:
            raise ValidationError("Dieser Auftrag kann nicht abgeschlossen werden.")
        review = connection.execute(
            "SELECT id FROM verification_reviews WHERE verification_request_id=? AND content_hash=? ORDER BY id DESC LIMIT 1",
            (request_id, content),
        ).fetchone()
        if review is None:
            raise ValidationError("Die aktuelle Evidenz- und Claim-Zusammenfassung ist nicht bestaetigt.")
        cursor = connection.execute(
            """INSERT INTO provider_assessments(
                 verification_request_id, provider_presence, contract_compatibility,
                 integration_readiness, freshness, blockers_json, warnings_json,
                 assessment_hash, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                request_id,
                assessment["provider_presence"],
                assessment["contract_compatibility"],
                assessment["integration_readiness"],
                assessment["freshness"],
                canonical_json(assessment["blockers"]),
                canonical_json(assessment["warnings"]),
                assessment["assessment_hash"],
                now,
            ),
        )
        assessment_id = int(cursor.lastrowid)
        connection.execute(
            "UPDATE verification_requests SET state='completed', completed_at=?, updated_at=? WHERE id=?",
            (now, now, request_id),
        )
        connection.execute(
            "UPDATE verification_tasks SET state='completed' WHERE verification_request_id=?",
            (request_id,),
        )
        _invalidate_plans(connection, int(request_row["setup_run_id"]), "Providerbewertung geaendert")
        _audit(connection, "assessment.created", "provider_assessment", str(assessment_id), None, str(assessment["assessment_hash"]))
        _audit(connection, "verification.completed", "verification_request", str(request_id), None, str(assessment["assessment_hash"]))
    return {**assessment, "id": assessment_id}


def list_verification_requests(database: Path, run_id: int | None = None) -> list[dict[str, object]]:
    query = "SELECT * FROM verification_requests"
    parameters: tuple[object, ...] = ()
    if run_id is not None:
        query += " WHERE setup_run_id=?"
        parameters = (run_id,)
    query += " ORDER BY id"
    with read_connection(database) as connection:
        return [dict(row) for row in connection.execute(query, parameters)]


def verification_detail(database: Path, request_id: int) -> dict[str, object]:
    with read_connection(database) as connection:
        request_row = _request_row(connection, request_id)
        result: dict[str, object] = dict(request_row)
        for name, query in (
            ("tasks", "SELECT * FROM verification_tasks WHERE verification_request_id=? ORDER BY position"),
            ("evidence", "SELECT * FROM verification_evidence WHERE verification_request_id=? ORDER BY id"),
            ("claim_results", "SELECT * FROM verification_claim_results WHERE verification_request_id=? ORDER BY claim_id"),
            ("consents", "SELECT * FROM verification_consents WHERE verification_request_id=? ORDER BY id"),
            ("reviews", "SELECT * FROM verification_reviews WHERE verification_request_id=? ORDER BY id"),
            ("assessments", "SELECT * FROM provider_assessments WHERE verification_request_id=? ORDER BY id"),
        ):
            rows = [dict(row) for row in connection.execute(query, (request_id,))]
            for row in rows:
                for key in ("data_categories_json", "scope_json", "blockers_json", "warnings_json"):
                    if key in row:
                        row[key.removesuffix("_json")] = json.loads(row.pop(key))
            result[name] = rows
        current = datetime.now(timezone.utc)
        for assessment in result["assessments"]:  # type: ignore[index]
            assessment["effective_freshness"] = effective_assessment_freshness(
                database, request_id, current
            )
        return result


def list_assessments(database: Path, *, effective_at: str | None = None) -> list[dict[str, object]]:
    current = _parse_time(effective_at or utc_now(), "Bewertungszeitpunkt")
    with read_connection(database) as connection:
        rows = connection.execute(
            """SELECT a.*, r.inventory_item_id, r.contract_id, r.contract_hash
               FROM provider_assessments a JOIN verification_requests r ON r.id=a.verification_request_id
               ORDER BY a.id"""
        ).fetchall()
    results = []
    for row in rows:
        value = dict(row)
        value["blockers"] = json.loads(value.pop("blockers_json"))
        value["warnings"] = json.loads(value.pop("warnings_json"))
        value["effective_freshness"] = effective_assessment_freshness(database, int(value["verification_request_id"]), current)
        results.append(value)
    return results


def latest_assessment_for_inventory(
    database: Path, inventory_item_id: int, *, now: str | None = None
) -> dict[str, object] | None:
    current_contracts = {(c.contract_id, c.contract_version): c for c in load_contracts().contracts}
    with read_connection(database) as connection:
        row = connection.execute(
            """SELECT a.*, r.contract_id, r.contract_version, r.contract_hash, r.inventory_item_id
               FROM provider_assessments a JOIN verification_requests r ON r.id=a.verification_request_id
               WHERE r.inventory_item_id=? AND r.state='completed'
               ORDER BY a.id DESC LIMIT 1""",
            (inventory_item_id,),
        ).fetchone()
    if row is None:
        return None
    value = dict(row)
    contract = current_contracts.get((value["contract_id"], value["contract_version"]))
    if contract is None or contract.contract_hash != value["contract_hash"]:
        return None
    value["blockers"] = json.loads(value.pop("blockers_json"))
    value["warnings"] = json.loads(value.pop("warnings_json"))
    value["effective_freshness"] = effective_assessment_freshness(
        database, int(value["verification_request_id"]), _parse_time(now or utc_now(), "Zeitpunkt")
    )
    return value


def latest_verification_state_for_inventory(database: Path, inventory_item_id: int) -> str | None:
    with read_connection(database) as connection:
        row = connection.execute(
            "SELECT state FROM verification_requests WHERE inventory_item_id=? ORDER BY id DESC LIMIT 1",
            (inventory_item_id,),
        ).fetchone()
    return str(row["state"]) if row else None


def reconcile_run_verifications(database: Path, run_id: int) -> list[int]:
    """Obsolete changed targets/contracts during an explicit planning action."""

    contracts = {(item.contract_id, item.contract_version): item for item in load_contracts().contracts}
    obsolete: list[int] = []
    now = utc_now()
    with transaction(database) as connection:
        rows = connection.execute(
            """SELECT r.*, i.id AS current_item_id, i.setup_run_id AS item_run_id,
                      i.capability_id, i.provider_id, i.display_name, i.product_name,
                      i.location, i.management_url, i.source, i.state AS item_state
               FROM verification_requests r
               LEFT JOIN inventory_items i ON i.id=r.inventory_item_id
               WHERE r.setup_run_id=? AND r.state!='obsolete'""",
            (run_id,),
        ).fetchall()
        for row in rows:
            contract = contracts.get((row["contract_id"], row["contract_version"]))
            item = None
            if row["current_item_id"] is not None:
                item = {
                    "id": row["current_item_id"],
                    "setup_run_id": row["item_run_id"],
                    "capability_id": row["capability_id"],
                    "provider_id": row["provider_id"],
                    "display_name": row["display_name"],
                    "product_name": row["product_name"],
                    "location": row["location"],
                    "management_url": row["management_url"],
                    "source": row["source"],
                    "state": row["item_state"],
                }
            changed = (
                contract is None
                or contract.contract_hash != row["contract_hash"]
                or item is None
                or _hash(inventory_snapshot(item)) != row["target_snapshot_hash"]
            )
            if not changed:
                continue
            request_id = int(row["id"])
            obsolete.append(request_id)
            connection.execute(
                """UPDATE verification_requests SET state='obsolete',
                   obsolete_reason='Inventar oder Providervertrag geaendert', updated_at=? WHERE id=?""",
                (now, request_id),
            )
            connection.execute(
                "UPDATE verification_tasks SET state='obsolete' WHERE verification_request_id=?",
                (request_id,),
            )
            connection.execute(
                "UPDATE verification_consents SET revoked_at=? WHERE verification_request_id=? AND revoked_at IS NULL",
                (now, request_id),
            )
            _audit(connection, "verification.obsoleted", "verification_request", str(request_id), None, _hash({"reason": "contract_or_target_changed"}))
    return obsolete


def audit_stale_assessments(database: Path, assessment_snapshots: list[dict[str, object]]) -> None:
    stale = [item for item in assessment_snapshots if item.get("effective_freshness") == "stale"]
    if not stale:
        return
    with transaction(database) as connection:
        for item in stale:
            _audit(
                connection,
                "assessment.stale_detected",
                "provider_assessment",
                str(item.get("assessment_hash", "unknown")),
                None,
                _hash({"inventory_item_id": item.get("inventory_item_id")}),
            )


def effective_assessment_freshness(database: Path, request_id: int, now: datetime) -> str:
    catalog = load_contracts()
    with read_connection(database) as connection:
        request_row = _request_row(connection, request_id)
        rows = connection.execute(
            "SELECT claim_id, result, valid_until FROM verification_claim_results WHERE verification_request_id=?",
            (request_id,),
        ).fetchall()
    try:
        contract = catalog.get(
            str(request_row["contract_id"]), int(request_row["contract_version"])
        )
    except ValidationError:
        return "stale"
    if contract.contract_hash != request_row["contract_hash"]:
        return "stale"
    results = {str(row["claim_id"]): row for row in rows}
    required_claims = [
        claim for claim in contract.claims if claim.required and claim.category != "integration"
    ]
    if not required_claims:
        return "never_verified"
    for claim in required_claims:
        row = results.get(claim.claim_id)
        if row is None or row["result"] in {"unknown", "not_observed"}:
            return "never_verified"
        if row["valid_until"] is None:
            return "never_verified"
        if _parse_time(row["valid_until"], "Gueltigkeit") <= now:
            return "stale"
    return "fresh"


def _current_request(
    database: Path, request_id: int, *, allow_terminal: bool = False
) -> tuple[sqlite3.Row, ProviderContract, dict[str, object]]:
    catalog = load_contracts()
    with read_connection(database) as connection:
        request_row = _request_row(connection, request_id)
        if not allow_terminal and request_row["state"] in {"declined", "obsolete"}:
            raise ValidationError("Verifikationsauftrag ist nicht mehr aktiv.")
        item_row = connection.execute(
            "SELECT * FROM inventory_items WHERE id=?", (request_row["inventory_item_id"],)
        ).fetchone()
        if item_row is None:
            raise ValidationError("Zielinventar des Verifikationsauftrags fehlt.")
    contract = catalog.get(request_row["contract_id"], int(request_row["contract_version"]))
    item = dict(item_row)
    if request_row["contract_hash"] != contract.contract_hash:
        raise ValidationError("Providervertrag wurde geaendert; Auftrag muss ersetzt werden.")
    if request_row["target_snapshot_hash"] != _hash(inventory_snapshot(item)):
        raise ValidationError("Inventareintrag wurde geaendert; Auftrag muss ersetzt werden.")
    return request_row, contract, item


def _request_row(connection: sqlite3.Connection, request_id: int) -> sqlite3.Row:
    row = connection.execute("SELECT * FROM verification_requests WHERE id=?", (request_id,)).fetchone()
    if row is None:
        raise ValidationError("Verifikationsauftrag wurde nicht gefunden.")
    return row


def _contract_claim(contract: ProviderContract, claim_id: str):
    matches = [claim for claim in contract.claims if claim.claim_id == claim_id]
    if len(matches) != 1:
        raise ValidationError("Unbekannte Claim-ID fuer diesen Providervertrag.")
    return matches[0]


def _require_effective_consent(database: Path, request_id: int) -> None:
    with read_connection(database) as connection:
        row = connection.execute(
            """SELECT * FROM verification_consents
               WHERE verification_request_id=? AND revoked_at IS NULL ORDER BY id DESC LIMIT 1""",
            (request_id,),
        ).fetchone()
    if row is None or _parse_time(row["expires_at"], "Zustimmungsablauf") <= datetime.now(timezone.utc):
        raise ValidationError("Eine wirksame, nicht abgelaufene Scope-Zustimmung fehlt.")


def _active_evidence(database: Path, request_id: int, claim_id: str) -> list[dict[str, object]]:
    with read_connection(database) as connection:
        rows = connection.execute(
            """SELECT e.* FROM verification_evidence e
               WHERE e.verification_request_id=? AND e.claim_id=?
                 AND NOT EXISTS (SELECT 1 FROM verification_evidence newer WHERE newer.supersedes_id=e.id)
               ORDER BY e.id""",
            (request_id, claim_id),
        ).fetchall()
    return [dict(row) for row in rows]


def _invalidate_plans(connection: sqlite3.Connection, run_id: int, reason: str) -> None:
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
        (utc_now(), run_id),
    )


def _parse_time(value: str, field: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as exc:
        raise ValidationError(f"{field} muss ISO-8601 entsprechen.") from exc
    if parsed.tzinfo is None:
        raise ValidationError(f"{field} benoetigt eine Zeitzone.")
    return parsed.astimezone(timezone.utc)


def _format_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
