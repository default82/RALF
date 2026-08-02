from ralf_bootstrap.controller.catalog import load_catalog
from ralf_bootstrap.controller.planner import build_plan
from ralf_bootstrap.controller.storage import confirm_section, save_inventory, save_preference, save_requirement


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
