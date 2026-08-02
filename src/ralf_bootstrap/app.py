"""Flask application factory for Bootstrap status and local controller."""

from __future__ import annotations

from pathlib import Path
import logging
from typing import Callable

from flask import Flask, jsonify, render_template

from . import __version__
from .controller.blueprint import (
    controller_summary,
    create_controller_blueprint,
    register_controller_api,
)
from .controller.verification_blueprint import (
    create_verification_blueprint,
    register_verification_api,
)
from .storage import DEFAULT_DATABASE_PATH
from .status import StatusCollector

StatusProvider = Callable[[], dict[str, object]]
LOGGER = logging.getLogger(__name__)


def create_app(
    status_provider: StatusProvider | None = None,
    *,
    database_path: Path | None = None,
) -> Flask:
    """Create the application without initializing storage or making external calls."""

    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.config.update(DEBUG=False, TESTING=False)
    controller_database = Path(database_path or DEFAULT_DATABASE_PATH)
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
                    "mode": "controller-local-state",
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
        return render_template(
            "index.html",
            status=safe_status(),
            controller=controller_summary(controller_database),
        )

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "service": "ralf-bootstrap", "version": __version__})

    @app.get("/api/v1/status")
    def api_status():
        return jsonify(safe_status())

    app.register_blueprint(create_controller_blueprint(controller_database))
    app.register_blueprint(create_verification_blueprint(controller_database))
    register_controller_api(app, controller_database)
    register_verification_api(app, controller_database)

    return app


app = create_app()
