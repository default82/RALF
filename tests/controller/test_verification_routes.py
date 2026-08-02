from __future__ import annotations

from datetime import datetime, timedelta, timezone

from ralf_bootstrap.controller.storage import save_inventory
from ralf_bootstrap.controller.verification import (
    add_evidence,
    confirm_verification_scope,
    create_verification_request,
    review_content_hash,
    verification_detail,
)

from .conftest import csrf_from
from .test_verification import inventory_values


def test_contract_and_verification_read_routes(client, controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    assert client.get("/controller/contracts").status_code == 200
    assert client.get("/controller/contracts/secure-ingress.opnsense-caddy").status_code == 200
    response = client.get("/controller/verifications/new")
    assert response.status_code == 200
    token = csrf_from(response, "/controller/verifications/new")
    created = client.post(
        "/controller/verifications/new",
        data={
            "csrf_token": token,
            "inventory_item_id": str(item_id),
            "contract_id": "secure-ingress.opnsense-caddy",
        },
    )
    assert created.status_code == 303
    assert "/scope" in created.headers["Location"]
    assert client.get("/controller/verifications").status_code == 200


def test_uninitialized_verification_api_is_read_only_not_found(tmp_path):
    from ralf_bootstrap.app import create_app

    database = tmp_path / "missing-state.db"
    response = create_app(database_path=database).test_client().get(
        "/api/v1/controller/verifications/1"
    )
    assert response.status_code == 404
    assert not database.exists()


def test_all_verification_mutations_require_csrf(client, controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    request_id = create_verification_request(
        controller_db, run_id, item_id, "secure-ingress.opnsense-caddy"
    )
    paths = [
        f"/controller/verifications/{request_id}/scope/confirm",
        f"/controller/verifications/{request_id}/scope/revoke",
        f"/controller/verifications/{request_id}/evidence/new",
        f"/controller/verifications/{request_id}/claims",
        f"/controller/verifications/{request_id}/review/confirm",
        f"/controller/verifications/{request_id}/complete",
        f"/controller/verifications/{request_id}/decline",
    ]
    assert all(client.post(path).status_code == 400 for path in paths)
    mutation_only = [path for path in paths if not path.endswith("/evidence/new") and not path.endswith("/claims")]
    assert all(client.get(path).status_code in {404, 405} for path in mutation_only)
    assert client.get(f"/controller/verifications/{request_id}/evidence/new").status_code == 200
    assert client.get(f"/controller/verifications/{request_id}/claims").status_code == 200


def test_verification_api_redacts_sensitive_summary(client, controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    request_id = create_verification_request(
        controller_db, run_id, item_id, "secure-ingress.opnsense-caddy"
    )
    detail = verification_detail(controller_db, request_id)
    confirm_verification_scope(controller_db, request_id, scope_hash=detail["scope_hash"])
    observed = datetime.now(timezone.utc) - timedelta(minutes=1)
    add_evidence(
        controller_db,
        request_id,
        claim_id="provider.caddy_is_present",
        kind="manual_attestation",
        source="Redigierte Quelle",
        summary="Interne redigierte Detailzusammenfassung",
        verification_method="manual",
        observed_at=observed.isoformat(),
        valid_until=(observed + timedelta(days=1)).isoformat(),
        confidentiality="redacted_sensitive",
    )
    payload = client.get(f"/api/v1/controller/verifications/{request_id}").get_json()
    assert payload["evidence"][0]["summary"] == "[redigiert]"
    assert "Interne redigierte Detailzusammenfassung" not in str(payload)
    assert client.get("/api/v1/controller/contracts").status_code == 200
    assert client.get("/api/v1/controller/assessments").status_code == 200


def test_management_url_is_only_rendered_not_requested(client, controller_db, run_id, monkeypatch):
    save_inventory(
        controller_db,
        run_id,
        inventory_values(management_url="https://must-not-be-contacted.invalid/path"),
    )
    response = client.get("/controller/inventory")
    assert response.status_code == 200


def test_complete_local_webflow_stops_at_assessment(client, controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    request_id = create_verification_request(
        controller_db, run_id, item_id, "secure-ingress.opnsense-caddy"
    )
    scope_page = client.get(f"/controller/verifications/{request_id}/scope")
    scope_token = csrf_from(
        scope_page, f"/controller/verifications/{request_id}/scope/confirm"
    )
    detail = verification_detail(controller_db, request_id)
    assert client.post(
        f"/controller/verifications/{request_id}/scope/confirm",
        data={"csrf_token": scope_token, "scope_hash": detail["scope_hash"]},
    ).status_code == 303

    evidence_page = client.get(f"/controller/verifications/{request_id}/evidence/new")
    evidence_token = csrf_from(
        evidence_page, f"/controller/verifications/{request_id}/evidence/new"
    )
    observed = datetime.now(timezone.utc) - timedelta(minutes=1)
    assert client.post(
        f"/controller/verifications/{request_id}/evidence/new",
        data={
            "csrf_token": evidence_token,
            "claim_id": "provider.platform_is_opnsense",
            "kind": "manual_attestation",
            "source": "Manuelle Pruefung",
            "summary": "Redigierte Beobachtung",
            "verification_method": "manual",
            "observed_at": observed.isoformat(),
            "valid_until": (observed + timedelta(days=1)).isoformat(),
            "confidentiality": "internal",
        },
    ).status_code == 303

    claims_page = client.get(f"/controller/verifications/{request_id}/claims")
    claims_token = csrf_from(
        claims_page, f"/controller/verifications/{request_id}/claims"
    )
    assert client.post(
        f"/controller/verifications/{request_id}/claims",
        data={
            "csrf_token": claims_token,
            "claim_id": "provider.platform_is_opnsense",
            "result": "satisfied",
            "rationale": "Manuell bestaetigt",
        },
    ).status_code == 303

    review_page = client.get(f"/controller/verifications/{request_id}/review")
    review_token = csrf_from(
        review_page, f"/controller/verifications/{request_id}/review/confirm"
    )
    content_hash = review_content_hash(controller_db, request_id)
    assert client.post(
        f"/controller/verifications/{request_id}/review/confirm",
        data={"csrf_token": review_token, "content_hash": content_hash},
    ).status_code == 303
    review_page = client.get(f"/controller/verifications/{request_id}/review")
    complete_token = csrf_from(
        review_page, f"/controller/verifications/{request_id}/complete"
    )
    assert client.post(
        f"/controller/verifications/{request_id}/complete",
        data={"csrf_token": complete_token},
    ).status_code == 303
    assert verification_detail(controller_db, request_id)["state"] == "completed"
    assert client.get("/api/v1/controller/assessments").get_json()["items"]
