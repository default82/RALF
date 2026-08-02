from ralf_bootstrap.controller.catalog import load_catalog
from ralf_bootstrap.controller.storage import (
    confirm_section, current_plan, save_inventory, save_preference, save_requirement,
)
from tests.controller.conftest import csrf_from


def test_complete_local_flow_ends_in_plan_confirmation_without_apply(client, controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, {
        "capability_id": "monitoring", "provider_id": "existing-monitor", "display_name": "Existing monitor",
        "product_name": "Monitor", "location": "local", "management_url": None, "source": "user",
        "state": "verified", "verification_method": "manual", "verification_scope": "status only",
        "verification_consent": True, "verification_evidence": "Manuell dokumentiert",
        "last_verified_at": "2026-08-02T12:00:00Z",
    })
    for capability in load_catalog().capabilities:
        save_requirement(controller_db, run_id, capability.capability_id, "required" if capability.capability_id == "monitoring" else "not_needed")
    save_preference(controller_db, run_id, "monitoring", f"inventory:{item_id}", "existing-monitor", "preferred")
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(controller_db, run_id, section)

    response = client.get("/controller/plan")
    generate = csrf_from(response)
    response = client.post(
        "/controller/plan/generate", data={"csrf_token": generate},
        headers={"Origin": "http://localhost"},
    )
    assert response.status_code == 303
    response = client.get("/controller/plan")
    plan = current_plan(controller_db, run_id)
    assert plan["status"] == "ready"
    confirm = csrf_from(response, "/controller/plan/confirm")
    response = client.post(
        "/controller/plan/confirm",
        data={"csrf_token": confirm, "plan_hash": plan["plan_hash"]},
        headers={"Origin": "http://localhost"},
    )
    assert response.status_code == 303
    assert current_plan(controller_db, run_id)["status"] == "confirmed"
    assert "apply" not in " ".join(rule.rule for rule in client.application.url_map.iter_rules()).lower()
