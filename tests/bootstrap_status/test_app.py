from __future__ import annotations

from ralf_bootstrap.app import create_app


def sample_status():
    return {
        "schema_version": 1,
        "collected_at": "2026-08-01T12:00:00Z",
        "bootstrap": {
            "version": "0.3.0",
            "service": "ralf-bootstrap",
            "mode": "controller-local-state",
            "schema_version": 1,
            "sqlite": {"status": "not_initialized", "user_version": None},
        },
        "setup": {
            "status": "bootstrap_only",
            "bootstrap_status": "present",
            "model_runtime": "not_configured",
            "model": "not_configured",
            "model_webui": "not_configured",
            "privileged_installer": "not_configured",
        },
        "system": {
            "hostname": '<host>&',
            "os_name": "Ubuntu",
            "os_version": "26.04",
            "architecture": "x86_64",
        },
        "network": {"status": "configured", "ipv4_addresses": ["192.0.2.10"], "default_route": True},
        "resources": {
            "root_filesystem": {"used_percent": 20},
            "memory": {"available_bytes": 1},
            "swap": {"free_bytes": 2},
        },
        "services": {"systemd": "running", "bootstrap": "running"},
        "components": [{"id": "bootstrap-status", "status": "running"}],
        "warnings": ["example warning"],
    }


def client():
    return create_app(sample_status).test_client()


def test_index_is_html_and_local_only():
    response = client().get("/")
    body = response.get_data(as_text=True)
    assert response.status_code == 200
    assert "text/html" in response.content_type
    assert "&lt;host&gt;&amp;" in body
    assert "https://" not in body and "cdn" not in body.lower()
    assert "<form" not in body.lower()
    assert "<button" not in body.lower()
    assert "<script" not in body.lower()


def test_healthcheck():
    response = client().get("/healthz")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok", "service": "ralf-bootstrap", "version": "0.3.0"}


def test_status_api_has_schema():
    response = client().get("/api/v1/status")
    assert response.status_code == 200
    assert response.content_type.startswith("application/json")
    assert set(response.get_json()) == {
        "schema_version", "collected_at", "bootstrap", "setup", "system",
        "network", "resources", "services", "components", "warnings",
    }


def test_security_headers_and_http_errors():
    response = client().get("/")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "no-referrer"
    assert response.headers["Cache-Control"] == "no-store"
    assert "default-src 'self'" in response.headers["Content-Security-Policy"]
    assert client().get("/missing").status_code == 404
    assert client().post("/healthz").status_code == 405


def test_css_is_packaged_and_local():
    response = client().get("/static/style.css")
    assert response.status_code == 200
    assert "system-ui" in response.get_data(as_text=True)


def test_provider_failure_is_safe():
    def broken():
        raise RuntimeError("secret traceback must not escape")

    app = create_app(broken)
    body = app.test_client().get("/api/v1/status").get_json()
    assert body["warnings"] == ["Status konnte nicht vollständig ermittelt werden."]
    assert "secret" not in str(body)
