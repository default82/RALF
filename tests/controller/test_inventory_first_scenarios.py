from ralf_bootstrap.controller.catalog import load_catalog
from ralf_bootstrap.controller.planner import build_plan
from ralf_bootstrap.controller.storage import confirm_section, save_inventory, save_preference, save_requirement
from ralf_bootstrap.controller.verification import (
    confirm_verification_scope,
    create_verification_request,
    verification_detail,
    decline_verification,
)

from .test_verification import complete_opnsense_assessment


def test_reported_opnsense_caddy_is_verified_and_reused_not_installed(controller_db, run_id):
    provider_id = save_inventory(controller_db, run_id, {
        "capability_id": "secure-ingress", "provider_id": "opnsense-caddy",
        "display_name": "Caddy auf OPNsense", "product_name": "os-caddy", "location": "OPNsense external",
        "management_url": "https://opnsense.home.arpa", "source": "user", "state": "reported",
        "verification_method": None, "verification_scope": "Plugin, Domains, TLS, Auth und Regeln read-only",
        "verification_consent": True, "verification_evidence": "", "last_verified_at": None,
    })
    for capability in load_catalog().capabilities:
        save_requirement(controller_db, run_id, capability.capability_id, "required" if capability.capability_id == "secure-ingress" else "not_needed")
    save_preference(controller_db, run_id, "secure-ingress", f"inventory:{provider_id}", "opnsense-caddy", "preferred")
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(controller_db, run_id, section)
    plan = build_plan(controller_db, run_id)
    types = [step["step_type"] for step in plan["steps"]]
    assert types == ["verify_provider", "decide_integration", "reuse_provider"]
    assert plan["status"] == "blocked"
    assert not any(step["step_type"] == "install_provider" for step in plan["steps"])
    assert "lokalen Caddy" not in " ".join(step["title"] for step in plan["steps"])


def test_no_existing_ingress_never_auto_selects_local_caddy(controller_db, run_id):
    for capability in load_catalog().capabilities:
        save_requirement(controller_db, run_id, capability.capability_id, "required" if capability.capability_id == "secure-ingress" else "not_needed")
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(controller_db, run_id, section)
    plan = build_plan(controller_db, run_id)
    assert plan["status"] == "blocked"
    assert not any(step["step_type"] == "install_provider" for step in plan["steps"])
    assert any("Provider" in step["title"] for step in plan["steps"])


def test_verified_compatible_opnsense_remains_integration_blocked(controller_db, run_id):
    provider_id = save_inventory(controller_db, run_id, {
        "capability_id": "secure-ingress", "provider_id": "opnsense-caddy",
        "display_name": "Caddy auf OPNsense", "product_name": "os-caddy", "location": "OPNsense external",
        "management_url": "https://opnsense.home.arpa", "source": "user", "state": "reported",
        "verification_method": None, "verification_scope": "Providervertrag read-only",
        "verification_consent": True, "verification_evidence": "", "last_verified_at": None,
    })
    for capability in load_catalog().capabilities:
        save_requirement(controller_db, run_id, capability.capability_id, "required" if capability.capability_id == "secure-ingress" else "not_needed")
    save_preference(controller_db, run_id, "secure-ingress", f"inventory:{provider_id}", "opnsense-caddy", "preferred")
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(controller_db, run_id, section)
    request_id = create_verification_request(
        controller_db, run_id, provider_id, "secure-ingress.opnsense-caddy"
    )
    detail = verification_detail(controller_db, request_id)
    confirm_verification_scope(controller_db, request_id, scope_hash=detail["scope_hash"])
    complete_opnsense_assessment(controller_db, request_id)
    plan = build_plan(controller_db, run_id)
    assert [step["step_type"] for step in plan["steps"]] == ["decide_integration", "reuse_provider"]
    assert plan["status"] == "blocked"
    assert not any(step["step_type"] in {"verify_provider", "install_provider"} for step in plan["steps"])
    assert any("O-012" in blocker for blocker in plan["blockers"])


def _prepared_opnsense(database, run_id):
    provider_id = save_inventory(database, run_id, {
        "capability_id": "secure-ingress", "provider_id": "opnsense-caddy",
        "display_name": "Caddy auf OPNsense", "product_name": "os-caddy", "location": "OPNsense external",
        "management_url": None, "source": "user", "state": "reported",
        "verification_method": None, "verification_scope": "Read-only Vertrag",
        "verification_consent": True, "verification_evidence": "", "last_verified_at": None,
    })
    for capability in load_catalog().capabilities:
        save_requirement(database, run_id, capability.capability_id, "required" if capability.capability_id == "secure-ingress" else "not_needed")
    save_preference(database, run_id, "secure-ingress", f"inventory:{provider_id}", "opnsense-caddy", "preferred")
    for section in ("inventory", "requirements", "preferences", "verification_scope"):
        confirm_section(database, run_id, section)
    request_id = create_verification_request(database, run_id, provider_id, "secure-ingress.opnsense-caddy")
    detail = verification_detail(database, request_id)
    confirm_verification_scope(database, request_id, scope_hash=detail["scope_hash"])
    return provider_id, request_id


def test_stale_assessment_restores_verification_step(controller_db, run_id):
    import sqlite3

    _provider_id, request_id = _prepared_opnsense(controller_db, run_id)
    complete_opnsense_assessment(controller_db, request_id)
    with sqlite3.connect(controller_db) as connection:
        connection.execute(
            "UPDATE verification_claim_results SET valid_until='2000-01-01T00:00:00Z' WHERE verification_request_id=? AND valid_until IS NOT NULL",
            (request_id,),
        )
    plan = build_plan(controller_db, run_id)
    assert [step["step_type"] for step in plan["steps"]] == ["verify_provider", "decide_integration", "reuse_provider"]
    assert any("veraltet" in item for item in plan["open_checks"])


def test_declined_verification_shows_fallback_without_install(controller_db, run_id):
    _provider_id, request_id = _prepared_opnsense(controller_db, run_id)
    decline_verification(controller_db, request_id)
    plan = build_plan(controller_db, run_id)
    assert plan["status"] == "blocked"
    assert [step["step_type"] for step in plan["steps"]] == ["manual_action"]
    assert "Keine automatische Installation" in plan["steps"][0]["expected_effects"]
    assert not any(step["step_type"] == "install_provider" for step in plan["steps"])


def test_changed_contract_hash_obsoletes_request_during_explicit_plan(controller_db, run_id):
    import sqlite3

    _provider_id, request_id = _prepared_opnsense(controller_db, run_id)
    with sqlite3.connect(controller_db) as connection:
        connection.execute(
            "UPDATE verification_requests SET contract_hash=? WHERE id=?", ("0" * 64, request_id)
        )
    plan = build_plan(controller_db, run_id)
    assert verification_detail(controller_db, request_id)["state"] == "obsolete"
    assert plan["steps"][0]["step_type"] == "verify_provider"
