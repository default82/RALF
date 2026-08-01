"""Flask application factory for the read-only Bootstrap status service."""

from __future__ import annotations

from pathlib import Path
import logging
from typing import Callable

from flask import Flask, jsonify, render_template

from . import __version__
from .status import StatusCollector

StatusProvider = Callable[[], dict[str, object]]
LOGGER = logging.getLogger(__name__)


def create_app(
    status_provider: StatusProvider | None = None,
    *,
    database_path: Path | None = None,
) -> Flask:
    """Create an application without performing writes or external calls."""

    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.update(DEBUG=False, TESTING=False)
    if status_provider is None:
        collector = StatusCollector(
            **({"database_path": database_path} if database_path is not None else {})
        )
        status_provider = collector.collect

    def safe_status() -> dict[str, object]:
        try:
            return status_provider()  # type: ignore[misc]
        except Exception:
            LOGGER.exception("Statusermittlung fehlgeschlagen")
            return {
                "schema_version": 1,
                "collected_at": None,
                "bootstrap": {
                    "version": __version__,
                    "service": "ralf-bootstrap",
                    "mode": "read-only",
                    "schema_version": 1,
                    "sqlite": {"status": "unknown", "user_version": None},
                },
                "setup": {"status": "unknown"},
                "system": {},
                "network": {"status": "unknown"},
                "resources": {},
                "services": {"systemd": "unknown", "bootstrap": "running"},
                "components": [],
                "warnings": ["Status konnte nicht vollständig ermittelt werden."],
            }

    @app.after_request
    def security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        response.headers[
            "Content-Security-Policy"
        ] = "default-src 'self'; style-src 'self'; img-src 'self'; script-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
        return response

    @app.get("/")
    def index():
        return render_template("index.html", status=safe_status())

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "service": "ralf-bootstrap", "version": __version__})

    @app.get("/api/v1/status")
    def api_status():
        return jsonify(safe_status())

    return app


app = create_app()
