from ralf_bootstrap.controller.storage import (
    confirm_section,
    confirmation_status,
    save_inventory,
)


def inventory_values(name="Existing Proxy"):
    return {
        "capability_id": "secure-ingress", "provider_id": "proxy", "display_name": name,
        "product_name": "Proxy", "location": "external", "management_url": None,
        "source": "user", "state": "reported", "verification_method": None,
        "verification_scope": "read-only", "verification_consent": True,
        "verification_evidence": "", "last_verified_at": None,
    }


def test_content_confirmation_is_invalidated_by_change(controller_db, run_id):
    item_id = save_inventory(controller_db, run_id, inventory_values())
    digest = confirm_section(controller_db, run_id, "inventory")
    assert confirmation_status(controller_db, run_id)["inventory"]
    save_inventory(controller_db, run_id, inventory_values("Changed"), item_id=item_id)
    assert not confirmation_status(controller_db, run_id)["inventory"]
    assert digest != confirm_section(controller_db, run_id, "inventory")
