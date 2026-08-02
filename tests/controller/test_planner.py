from __future__ import annotations

import pytest

from ralf_bootstrap.controller.catalog import load_catalog
from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.planner import build_plan
from ralf_bootstrap.controller.storage import (
    confirm_plan, confirm_section, current_plan, save_inventory, save_preference, save_requirement,
)


def item(capability="monitoring", provider="existing-monitor", state="verified", location="local"):
    return {
        "capability_id": capability, "provider_id": provider, "display_name": provider,
        "product_name": provider, "location": location, "management_url": None, "source": "user",
        "state": state, "verification_method": "manual" if state == "verified" else None,
        "verification_scope": "read-only", "verification_consent": True,
        "verification_evidence": "Manuell bestätigt" if state == "verified" else "",
        "last_verified_at": "2026-08-02T10:00:00Z" if state == "verified" else None,
    }


def complete_requirements(database, run_id, selected="monitoring"):
    for capability in load_catalog().capabilities:
        save_requirement(database, run_id, capability.capability_id, "required" if capability.capability_id == selected else "not_needed")


def confirm_all(database, run_id):
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(database, run_id, section)


def test_verified_preferred_provider_is_reused_without_install(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, item())
    complete_requirements(controller_db, run_id)
    save_preference(controller_db, run_id, "monitoring", f"inventory:{item_id}", "existing-monitor", "preferred")
    confirm_all(controller_db, run_id)
    plan = build_plan(controller_db, run_id)
    assert plan["status"] == "ready"
    assert [step["step_type"] for step in plan["steps"]] == ["reuse_provider"]
    assert all(step["step_type"] != "install_provider" for step in plan["steps"])


def test_plan_generation_requires_all_section_confirmations(controller_db, run_id):
    complete_requirements(controller_db, run_id)
    with pytest.raises(ValidationError, match="bestätigte Pflichtabschnitte"):
        build_plan(controller_db, run_id)


def test_conflict_and_no_provider_block(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, item(state="conflict"))
    complete_requirements(controller_db, run_id)
    save_preference(controller_db, run_id, "monitoring", f"inventory:{item_id}", "existing-monitor", "preferred")
    confirm_all(controller_db, run_id)
    blocked = build_plan(controller_db, run_id)
    assert blocked["status"] == "blocked"
    with pytest.raises(ValidationError):
        confirm_plan(controller_db, run_id, blocked["plan_hash"])


def test_verified_fallback_precedes_reported_fallback(controller_db, run_id):
    reported = save_inventory(controller_db, run_id, item(provider="reported", state="reported"))
    verified = save_inventory(controller_db, run_id, item(provider="verified", state="verified"))
    complete_requirements(controller_db, run_id)
    save_preference(controller_db, run_id, "monitoring", f"inventory:{reported}", "reported", "allowed_fallback", 1)
    save_preference(controller_db, run_id, "monitoring", f"inventory:{verified}", "verified", "allowed_fallback", 2)
    confirm_all(controller_db, run_id)
    plan = build_plan(controller_db, run_id)
    assert plan["steps"][0]["provider_reference"] == f"inventory:{verified}"


def test_plan_hash_is_stable_confirmation_exact_and_change_obsoletes(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, item())
    complete_requirements(controller_db, run_id)
    save_preference(controller_db, run_id, "monitoring", f"inventory:{item_id}", "existing-monitor", "preferred")
    confirm_all(controller_db, run_id)
    first = build_plan(controller_db, run_id)
    second = build_plan(controller_db, run_id)
    assert first["plan_hash"] == second["plan_hash"]
    with pytest.raises(ValidationError):
        confirm_plan(controller_db, run_id, "0" * 64)
    confirm_plan(controller_db, run_id, second["plan_hash"])
    save_requirement(controller_db, run_id, "monitoring", "optional")
    assert current_plan(controller_db, run_id) is None
