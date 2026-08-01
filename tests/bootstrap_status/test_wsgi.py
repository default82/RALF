from __future__ import annotations

import importlib


def test_gunicorn_wsgi_entrypoint_uses_config(monkeypatch, tmp_path):
    config_path = tmp_path / "config.toml"
    db_path = tmp_path / "state.db"
    config_path.write_text(f'[storage]\ndatabase_path = "{db_path}"\n', encoding="utf-8")
    monkeypatch.setenv("RALF_BOOTSTRAP_CONFIG", str(config_path))
    module = importlib.import_module("ralf_bootstrap.wsgi")
    module = importlib.reload(module)
    response = module.app.test_client().get("/api/v1/status")
    assert response.status_code == 200
    assert response.get_json()["bootstrap"]["sqlite"]["status"] == "not_initialized"
