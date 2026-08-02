from __future__ import annotations

import pytest

from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.storage import audit_events, get_inventory_item, save_inventory


def values(**updates):
    result = {
        "capability_id": "secure-ingress", "provider_id": "opnsense-caddy",
        "display_name": "OPNsense Caddy", "product_name": "Caddy", "location": "OPNsense",
        "management_url": "https://firewall.home.arpa/", "source": "user", "state": "reported",
        "verification_method": None, "verification_scope": "Konfiguration read-only",
        "verification_consent": True, "verification_evidence": "", "last_verified_at": None,
    }
    result.update(updates)
    return result


def test_user_report_stays_reported(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, values())
    assert get_inventory_item(controller_db, run_id, item_id)["state"] == "reported"
    event = audit_events(controller_db)[-1]
    assert event["event_type"] == "inventory.created"
    assert "OPNsense" not in "|".join(str(value) for value in event.values())


def test_verified_requires_method_time_and_evidence(controller_db, run_id):
    with pytest.raises(ValidationError, match="verified benötigt"):
        save_inventory(controller_db, run_id, values(state="verified"))
    item_id = save_inventory(
        controller_db, run_id,
        values(state="verified", verification_method="manual", last_verified_at="2026-08-02T12:00:00Z", verification_evidence="Manuell bestätigt"),
    )
    assert get_inventory_item(controller_db, run_id, item_id)["verification_method"] == "manual"
    with pytest.raises(ValidationError, match="ISO-8601"):
        save_inventory(
            controller_db, run_id,
            values(state="verified", verification_method="manual", last_verified_at="today", verification_evidence="Evidenz"),
        )


@pytest.mark.parametrize("state", ["declined", "conflict", "unknown", "unavailable"])
def test_other_stable_inventory_states(controller_db, run_id, state):
    item_id = save_inventory(controller_db, run_id, values(state=state, verification_consent=False))
    assert get_inventory_item(controller_db, run_id, item_id)["state"] == state


def test_management_url_rejects_credentials_fragment_and_script(controller_db, run_id):
    for url in ("https://user:pass@example.test", "https://example.test/#x", "javascript:alert(1)"):
        with pytest.raises(ValidationError):
            save_inventory(controller_db, run_id, values(management_url=url))
