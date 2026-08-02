from __future__ import annotations

from ralf_bootstrap.controller.storage import create_setup_run
from tests.controller.conftest import csrf_from


def test_uninitialized_controller_is_readable_and_not_created(tmp_path):
    from ralf_bootstrap.app import create_app

    database = tmp_path / "missing.db"
    client = create_app(database_path=database).test_client()
    assert client.get("/controller/").status_code == 200
    assert client.get("/api/v1/controller/status").get_json()["available"] is False
    assert not database.exists()


def test_start_requires_post_and_uses_prg(client, controller_db):
    response = client.get("/controller/setup/start")
    assert response.status_code == 200
    assert create_setup_run  # setup has not been mutated by GET
    token = csrf_from(response)
    result = client.post(
        "/controller/setup/start", data={"csrf_token": token}, headers={"Origin": "http://localhost"}
    )
    assert result.status_code == 303
    assert result.headers["Location"].endswith("/controller/inventory")


def test_inventory_form_escapes_html_and_get_does_not_mutate_domain_state(client, controller_db, run_id):
    response = client.get("/controller/inventory/new")
    token = csrf_from(response)
    result = client.post(
        "/controller/inventory/new",
        data={
            "csrf_token": token, "capability_id": "monitoring", "provider_id": "reported-monitor",
            "display_name": "<script>alert(1)</script>", "product_name": "Monitor", "location": "local",
            "management_url": "", "state": "reported",
        },
        headers={"Origin": "http://127.0.0.1"},
    )
    assert result.status_code == 303
    body = client.get("/controller/inventory").get_data(as_text=True)
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in body
    assert "<script>alert(1)</script>" not in body


def test_posts_require_csrf_and_loopback_host(client, run_id):
    assert client.post("/controller/inventory/new", data={}).status_code == 400
    response = client.get("/controller/inventory/new")
    token = csrf_from(response)
    result = client.post(
        "/controller/inventory/new",
        base_url="http://evil.example",
        data={"csrf_token": token},
        headers={"Origin": "http://evil.example"},
    )
    assert result.status_code == 400


def test_unknown_posts_and_get_mutations_are_rejected(client, run_id):
    assert client.post("/controller/unknown").status_code == 404
    assert client.get("/controller/inventory/1/delete").status_code == 405
    assert client.get("/controller/plan/generate").status_code == 405


def test_security_headers_and_no_external_resources(client, run_id):
    response = client.get("/controller/")
    assert response.headers["X-Frame-Options"] == "DENY"
    body = response.get_data(as_text=True)
    assert "cdn" not in body.lower()
    assert "<script" not in body.lower()
    assert "https://" not in body
