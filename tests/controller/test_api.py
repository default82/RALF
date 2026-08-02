from ralf_bootstrap.controller.storage import save_inventory


def test_read_only_controller_apis(client, controller_db, run_id):
    save_inventory(controller_db, run_id, {
        "capability_id": "network.firewall", "provider_id": "opnsense", "display_name": "OPNsense",
        "product_name": "OPNsense", "location": "router", "management_url": "https://router.home.arpa",
        "source": "user", "state": "reported", "verification_method": None,
        "verification_scope": "", "verification_consent": False, "verification_evidence": "",
        "last_verified_at": None,
    })
    assert client.get("/api/v1/controller/status").get_json()["reported_count"] == 1
    assert client.get("/api/v1/controller/inventory").get_json()["items"][0]["provider_id"] == "opnsense"
    assert client.get("/api/v1/controller/capabilities").get_json()["catalog_version"] == 1
    assert client.get("/api/v1/controller/preferences").get_json() == {"items": []}
    assert client.get("/api/v1/controller/plan").get_json() == {"plan": None}
    for path in (
        "/api/v1/controller/status", "/api/v1/controller/inventory", "/api/v1/controller/capabilities",
        "/api/v1/controller/preferences", "/api/v1/controller/plan",
    ):
        assert client.post(path).status_code == 405


def test_existing_status_api_contract_is_unchanged(client):
    body = client.get("/api/v1/status").get_json()
    assert set(body) == {
        "schema_version", "collected_at", "bootstrap", "setup", "system",
        "network", "resources", "services", "components", "warnings",
    }
