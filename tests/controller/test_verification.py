from __future__ import annotations

from datetime import datetime, timedelta, timezone
import sqlite3

import pytest

from ralf_bootstrap.controller.contracts import load_contracts
from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.storage import audit_events, save_inventory
from ralf_bootstrap.controller.verification import (
    add_evidence,
    assess_claim,
    assessment_preview,
    complete_verification,
    confirm_verification_review,
    confirm_verification_scope,
    create_verification_request,
    decline_verification,
    list_assessments,
    review_content_hash,
    revoke_verification_scope,
    verification_detail,
)


def inventory_values(**updates):
    values = {
        "capability_id": "secure-ingress",
        "provider_id": "opnsense-caddy",
        "display_name": "OPNsense Caddy",
        "product_name": "os-caddy",
        "location": "Firewall",
        "management_url": "https://firewall.home.arpa",
        "source": "user",
        "state": "reported",
        "verification_method": None,
        "verification_scope": "Providervertrag read-only bewerten",
        "verification_consent": True,
        "verification_evidence": "",
        "last_verified_at": None,
    }
    values.update(updates)
    return values


def create_ready_request(database, run_id):
    item_id = save_inventory(database, run_id, inventory_values())
    request_id = create_verification_request(
        database, run_id, item_id, "secure-ingress.opnsense-caddy"
    )
    detail = verification_detail(database, request_id)
    confirm_verification_scope(database, request_id, scope_hash=detail["scope_hash"])
    return item_id, request_id


def time_pair(days=1):
    observed = datetime.now(timezone.utc) - timedelta(minutes=1)
    valid = observed + timedelta(days=days)
    return observed.isoformat(), valid.isoformat()


def add_claim_evidence(database, request_id, claim_id, *, summary="Redigierte Beobachtung"):
    observed, valid = time_pair()
    return add_evidence(
        database,
        request_id,
        claim_id=claim_id,
        kind="manual_attestation",
        source="Manuelle kontrollierte Pruefung",
        summary=summary,
        verification_method="manual",
        observed_at=observed,
        valid_until=valid,
        confidentiality="internal",
    )


def test_request_scope_consent_does_not_execute_and_inventory_change_obsoletes(controller_db, run_id):
    item_id, request_id = create_ready_request(controller_db, run_id)
    assert verification_detail(controller_db, request_id)["state"] == "ready"
    save_inventory(controller_db, run_id, inventory_values(location="Andere Firewall"), item_id=item_id)
    detail = verification_detail(controller_db, request_id)
    assert detail["state"] == "obsolete"
    assert detail["consents"][-1]["revoked_at"] is not None
    assert all(task["state"] == "obsolete" for task in detail["tasks"])


def test_request_requires_existing_matching_inventory(controller_db, run_id):
    with pytest.raises(ValidationError, match="vorhandenen Inventareintrag"):
        create_verification_request(
            controller_db, run_id, 9999, "secure-ingress.opnsense-caddy"
        )
    item_id = save_inventory(
        controller_db,
        run_id,
        inventory_values(provider_id="other-proxy"),
    )
    with pytest.raises(ValidationError, match="passt nicht"):
        create_verification_request(
            controller_db, run_id, item_id, "secure-ingress.opnsense-caddy"
        )


def test_scope_revoke_and_decline_are_separate_states(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    revoke_verification_scope(controller_db, request_id)
    assert verification_detail(controller_db, request_id)["state"] == "awaiting_consent"
    detail = verification_detail(controller_db, request_id)
    confirm_verification_scope(controller_db, request_id, scope_hash=detail["scope_hash"])
    decline_verification(controller_db, request_id)
    assert verification_detail(controller_db, request_id)["state"] == "declined"
    with pytest.raises(ValidationError):
        complete_verification(controller_db, request_id)


def test_evidence_is_immutable_supersedable_and_strict(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    first = add_claim_evidence(controller_db, request_id, "provider.platform_is_opnsense")
    with sqlite3.connect(controller_db) as connection, pytest.raises(sqlite3.IntegrityError):
        connection.execute("UPDATE verification_evidence SET summary='changed' WHERE id=?", (first,))
    observed, valid = time_pair()
    second = add_evidence(
        controller_db, request_id,
        claim_id="provider.platform_is_opnsense", kind="manual_attestation",
        source="Korrigierte manuelle Pruefung", summary="Redigierte Korrektur",
        verification_method="manual", observed_at=observed, valid_until=valid,
        confidentiality="redacted_sensitive", digest="a" * 64, supersedes_id=first,
    )
    assert verification_detail(controller_db, request_id)["evidence"][-1]["supersedes_id"] == first
    with pytest.raises(ValidationError, match="Geheimnisse"):
        add_claim_evidence(
            controller_db, request_id, "provider.caddy_is_present", summary="password=do-not-store"
        )
    with pytest.raises(ValidationError, match="SHA-256"):
        observed, valid = time_pair()
        add_evidence(
            controller_db, request_id, claim_id="provider.caddy_is_present",
            kind="manual_attestation", source="Pruefung", summary="Redigiert",
            verification_method="manual", observed_at=observed, valid_until=valid,
            digest="xyz",
        )


def test_claim_requires_evidence_and_rejects_unknown_claim(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    with pytest.raises(ValidationError, match="Evidenz"):
        assess_claim(controller_db, request_id, "provider.caddy_is_present", "satisfied", "Geprueft")
    with pytest.raises(ValidationError, match="Claim-ID"):
        assess_claim(controller_db, request_id, "unknown.claim", "unknown", "Offen")
    observed, valid = time_pair()
    with pytest.raises(ValidationError, match="Claim-ID"):
        add_evidence(
            controller_db,
            request_id,
            claim_id="unknown.claim",
            kind="manual_attestation",
            source="Pruefung",
            summary="Redigierte Zusammenfassung",
            verification_method="manual",
            observed_at=observed,
            valid_until=valid,
        )


def test_task_state_tracks_evidence_and_assessment(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    claim_id = "provider.caddy_is_present"
    add_claim_evidence(controller_db, request_id, claim_id)
    task = next(
        item for item in verification_detail(controller_db, request_id)["tasks"]
        if item["task_id"] == claim_id
    )
    assert task["state"] == "evidence_pending"
    assess_claim(controller_db, request_id, claim_id, "satisfied", "Bestaetigt")
    task = next(
        item for item in verification_detail(controller_db, request_id)["tasks"]
        if item["task_id"] == claim_id
    )
    assert task["state"] == "completed"


def test_partial_evidence_is_not_fresh_verification(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    add_claim_evidence(controller_db, request_id, "provider.caddy_is_present")
    assess_claim(
        controller_db,
        request_id,
        "provider.caddy_is_present",
        "satisfied",
        "Bestaetigt",
    )
    preview = assessment_preview(controller_db, request_id)
    assert preview["freshness"] == "never_verified"
    assert preview["provider_presence"] == "reported"


def test_imported_evidence_timestamp_digest_and_confidentiality_validation(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    observed, valid = time_pair()
    evidence_id = add_evidence(
        controller_db, request_id,
        claim_id="provider.supports_tls", kind="imported_evidence",
        source="Extern redigierte Nachweisreferenz", summary="TLS-Faehigkeit redigiert zusammengefasst",
        verification_method="imported_evidence", observed_at=observed, valid_until=valid,
        confidentiality="public", digest="b" * 64,
    )
    assert evidence_id > 0
    with pytest.raises(ValidationError, match="Vertraulichkeit"):
        add_evidence(
            controller_db, request_id,
            claim_id="provider.supports_tls", kind="imported_evidence",
            source="Quelle", summary="Zusammenfassung", verification_method="imported_evidence",
            observed_at=observed, valid_until=valid, confidentiality="secret",
        )
    with pytest.raises(ValidationError, match="Zeitzone"):
        add_evidence(
            controller_db, request_id,
            claim_id="provider.supports_tls", kind="imported_evidence",
            source="Quelle", summary="Zusammenfassung", verification_method="imported_evidence",
            observed_at="2026-08-02T12:00:00", valid_until=valid,
        )
    with pytest.raises(ValidationError, match="nach ihrem Beobachtungszeitpunkt"):
        add_evidence(
            controller_db, request_id,
            claim_id="provider.supports_tls", kind="imported_evidence",
            source="Quelle", summary="Zusammenfassung", verification_method="imported_evidence",
            observed_at=valid, valid_until=observed,
        )


def test_wrong_scope_and_expired_consent_never_authorize_evidence(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    request_id = create_verification_request(
        controller_db, run_id, item_id, "secure-ingress.opnsense-caddy"
    )
    with pytest.raises(ValidationError, match="Verifikationsumfang"):
        confirm_verification_scope(controller_db, request_id, scope_hash="0" * 64)
    detail = verification_detail(controller_db, request_id)
    confirm_verification_scope(controller_db, request_id, scope_hash=detail["scope_hash"])
    with sqlite3.connect(controller_db) as connection:
        connection.execute(
            "UPDATE verification_consents SET expires_at='2000-01-01T00:00:00Z' WHERE verification_request_id=?",
            (request_id,),
        )
    with pytest.raises(ValidationError, match="Zustimmung"):
        add_claim_evidence(controller_db, request_id, "provider.caddy_is_present")


def test_unavailable_and_incompatible_are_independent(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    add_claim_evidence(controller_db, request_id, "provider.caddy_is_present")
    assess_claim(controller_db, request_id, "provider.caddy_is_present", "not_satisfied", "Nicht vorhanden")
    add_claim_evidence(controller_db, request_id, "provider.supports_tls")
    assess_claim(controller_db, request_id, "provider.supports_tls", "not_satisfied", "Nicht unterstuetzt")
    preview = assessment_preview(controller_db, request_id)
    assert preview["provider_presence"] == "unavailable"
    assert preview["contract_compatibility"] == "incompatible"
    assert preview["integration_readiness"] == "blocked"


def complete_opnsense_assessment(database, request_id):
    contract = load_contracts().get("secure-ingress.opnsense-caddy")
    for claim in contract.claims:
        if claim.category == "integration":
            assess_claim(database, request_id, claim.claim_id, "not_observed", "O-012 ist offen")
        else:
            add_claim_evidence(database, request_id, claim.claim_id)
            assess_claim(database, request_id, claim.claim_id, "satisfied", "Manuell nachvollziehbar bestaetigt")
    digest = review_content_hash(database, request_id)
    confirm_verification_review(database, request_id, digest)
    return complete_verification(database, request_id)


def test_three_assessment_levels_remain_separate_for_opnsense(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    assessment = complete_opnsense_assessment(controller_db, request_id)
    assert assessment["provider_presence"] == "verified"
    assert assessment["contract_compatibility"] == "compatible"
    assert assessment["integration_readiness"] == "blocked"
    assert assessment["freshness"] == "fresh"
    assert any("O-012" in blocker for blocker in assessment["blockers"])
    saved = list_assessments(controller_db)[0]
    assert saved["assessment_hash"] == assessment["assessment_hash"]
    assert saved["effective_freshness"] == "fresh"


def test_stale_conflict_unavailable_and_incompatible_assessments(controller_db, run_id, monkeypatch):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    add_claim_evidence(controller_db, request_id, "provider.platform_is_opnsense")
    assess_claim(controller_db, request_id, "provider.platform_is_opnsense", "conflict", "Widerspruch")
    preview = assessment_preview(controller_db, request_id)
    assert preview["provider_presence"] == "conflict"
    with sqlite3.connect(controller_db) as connection:
        connection.execute(
            "UPDATE verification_claim_results SET valid_until='2000-01-01T00:00:00Z' WHERE verification_request_id=?",
            (request_id,),
        )
    assert assessment_preview(controller_db, request_id)["freshness"] == "stale"


def test_audit_contains_only_events_and_hashes(controller_db, run_id):
    _item_id, request_id = create_ready_request(controller_db, run_id)
    add_claim_evidence(controller_db, request_id, "provider.caddy_is_present")
    events = audit_events(controller_db)
    assert {event["event_type"] for event in events} >= {
        "verification.request_created", "verification.scope_confirmed", "verification.evidence_added"
    }
    assert all("Redigierte Beobachtung" not in str(event) for event in events)
