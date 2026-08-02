"""Server-rendered verification-contract workflow without an executor."""

from __future__ import annotations

from pathlib import Path
from urllib.parse import urlsplit

from flask import Blueprint, abort, jsonify, redirect, render_template, request, url_for

from .contracts import load_contracts
from .csrf import consume_token, issue_token
from .models import CLAIM_RESULTS, EVIDENCE_CONFIDENTIALITY, EVIDENCE_KINDS, ValidationError
from .storage import latest_run, list_rows, schema_status
from .verification import (
    add_evidence,
    assess_claim,
    assessment_preview,
    complete_verification,
    confirm_verification_review,
    confirm_verification_scope,
    create_verification_request,
    decline_verification,
    inventory_snapshot,
    list_assessments,
    list_verification_requests,
    review_content_hash,
    revoke_verification_scope,
    scope_payload,
    verification_detail,
)

LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


def create_verification_blueprint(database_path: Path) -> Blueprint:
    blueprint = Blueprint(
        "provider_verification",
        __name__,
        url_prefix="/controller",
        template_folder="templates",
    )
    database = Path(database_path)

    @blueprint.before_request
    def local_post_boundary():
        if request.method != "POST":
            return None
        if urlsplit(request.host_url).hostname not in LOCAL_HOSTS:
            abort(400, "Controller-POST ist nur ueber einen dokumentierten Loopback-Host zulaessig.")
        origin = request.headers.get("Origin")
        if origin and urlsplit(origin).hostname not in LOCAL_HOSTS:
            abort(400, "Origin ist fuer lokale Controller-Formulare nicht zulaessig.")
        return None

    def require_run():
        if schema_status(database)["status"] != "ready":
            abort(409, "Controllerdatenbank benoetigt explizit Schema 2.")
        run = latest_run(database)
        if run is None:
            abort(409, "Setup-Lauf ist nicht initialisiert.")
        return run

    def token(form_id: str) -> str:
        return issue_token(database, form_id)

    def protect(form_id: str) -> None:
        try:
            consume_token(database, form_id, request.form.get("csrf_token"))
        except ValidationError as exc:
            abort(400, str(exc))

    def detail_or_404(verification_id: int) -> dict[str, object]:
        try:
            return verification_detail(database, verification_id)
        except ValidationError as exc:
            abort(404, str(exc))

    @blueprint.get("/verifications")
    def verifications():
        run = require_run()
        return render_template(
            "controller/verifications.html",
            requests=list_verification_requests(database, int(run["id"])),
        )

    @blueprint.get("/verifications/new")
    def verification_new():
        run = require_run()
        return render_template(
            "controller/verification_new.html",
            inventory=list_rows(database, "inventory_items", int(run["id"])),
            contracts=load_contracts().contracts,
            csrf_token=token("verification.request.create"),
        )

    @blueprint.post("/verifications/new")
    def verification_new_post():
        run = require_run()
        protect("verification.request.create")
        try:
            verification_id = create_verification_request(
                database,
                int(run["id"]),
                int(request.form.get("inventory_item_id", "0")),
                request.form.get("contract_id", ""),
            )
        except (ValueError, ValidationError) as exc:
            abort(400, str(exc))
        return redirect(url_for("provider_verification.verification_scope", verification_id=verification_id), code=303)

    @blueprint.get("/verifications/<int:verification_id>")
    def verification_show(verification_id: int):
        require_run()
        return render_template(
            "controller/verification_detail.html",
            verification=detail_or_404(verification_id),
            decline_token=token(f"verification.decline.{verification_id}"),
        )

    @blueprint.get("/verifications/<int:verification_id>/scope")
    def verification_scope(verification_id: int):
        require_run()
        detail = detail_or_404(verification_id)
        contract = load_contracts().get(str(detail["contract_id"]), int(detail["contract_version"]))
        item = next(
            (
                item
                for item in list_rows(database, "inventory_items", int(detail["setup_run_id"]))
                if int(item["id"]) == int(detail["inventory_item_id"])
            ),
            None,
        )
        if item is None:
            abort(409, "Zielinventar des Verifikationsauftrags fehlt; Auftrag ist nicht mehr verwendbar.")
        scope = scope_payload(contract, inventory_snapshot(item))
        return render_template(
            "controller/verification_scope.html",
            verification=detail,
            scope=scope,
            scope_hash=detail["scope_hash"],
            confirm_token=token(f"verification.scope.confirm.{verification_id}"),
            revoke_token=token(f"verification.scope.revoke.{verification_id}"),
            decline_token=token(f"verification.decline.{verification_id}"),
        )

    @blueprint.post("/verifications/<int:verification_id>/scope/confirm")
    def verification_scope_confirm(verification_id: int):
        require_run()
        protect(f"verification.scope.confirm.{verification_id}")
        try:
            confirm_verification_scope(
                database, verification_id, scope_hash=request.form.get("scope_hash", "")
            )
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.post("/verifications/<int:verification_id>/scope/revoke")
    def verification_scope_revoke(verification_id: int):
        require_run()
        protect(f"verification.scope.revoke.{verification_id}")
        try:
            revoke_verification_scope(database, verification_id)
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.get("/verifications/<int:verification_id>/evidence/new")
    def verification_evidence_new(verification_id: int):
        require_run()
        detail = detail_or_404(verification_id)
        contract = load_contracts().get(str(detail["contract_id"]), int(detail["contract_version"]))
        supersedes_raw = request.args.get("supersedes", "")
        supersedes_id = int(supersedes_raw) if supersedes_raw.isdigit() else None
        if supersedes_id is not None and not any(
            int(item["id"]) == supersedes_id for item in detail["evidence"]  # type: ignore[index]
        ):
            abort(404)
        form_id = (
            f"verification.evidence.supersede.{verification_id}.{supersedes_id}"
            if supersedes_id is not None
            else f"verification.evidence.add.{verification_id}"
        )
        form_action = (
            url_for(
                "provider_verification.verification_evidence_supersede",
                verification_id=verification_id,
                evidence_id=supersedes_id,
            )
            if supersedes_id is not None
            else url_for(
                "provider_verification.verification_evidence_new_post",
                verification_id=verification_id,
            )
        )
        return render_template(
            "controller/verification_evidence.html",
            verification=detail,
            contract=contract,
            kinds=sorted(EVIDENCE_KINDS),
            confidentiality_values=sorted(EVIDENCE_CONFIDENTIALITY),
            csrf_token=token(form_id),
            supersedes_id=supersedes_id,
            form_action=form_action,
        )

    @blueprint.post("/verifications/<int:verification_id>/evidence/new")
    def verification_evidence_new_post(verification_id: int):
        require_run()
        protect(f"verification.evidence.add.{verification_id}")
        try:
            add_evidence(database, verification_id, **_evidence_form())
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.post("/verifications/<int:verification_id>/evidence/<int:evidence_id>/supersede")
    def verification_evidence_supersede(verification_id: int, evidence_id: int):
        require_run()
        protect(f"verification.evidence.supersede.{verification_id}.{evidence_id}")
        try:
            add_evidence(database, verification_id, supersedes_id=evidence_id, **_evidence_form())
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.get("/verifications/<int:verification_id>/claims")
    def verification_claims(verification_id: int):
        require_run()
        detail = detail_or_404(verification_id)
        contract = load_contracts().get(str(detail["contract_id"]), int(detail["contract_version"]))
        return render_template(
            "controller/verification_claims.html",
            verification=detail,
            contract=contract,
            results=sorted(CLAIM_RESULTS),
            csrf_token=token(f"verification.claim.update.{verification_id}"),
        )

    @blueprint.post("/verifications/<int:verification_id>/claims")
    def verification_claims_post(verification_id: int):
        require_run()
        protect(f"verification.claim.update.{verification_id}")
        try:
            assess_claim(
                database,
                verification_id,
                request.form.get("claim_id", ""),
                request.form.get("result", ""),
                request.form.get("rationale", ""),
            )
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("provider_verification.verification_claims", verification_id=verification_id), code=303)

    @blueprint.get("/verifications/<int:verification_id>/review")
    def verification_review(verification_id: int):
        require_run()
        detail = detail_or_404(verification_id)
        try:
            preview = assessment_preview(database, verification_id)
            content_hash = review_content_hash(database, verification_id)
        except ValidationError as exc:
            abort(409, str(exc))
        return render_template(
            "controller/verification_review.html",
            verification=detail,
            assessment=preview,
            content_hash=content_hash,
            confirm_token=token(f"verification.review.confirm.{verification_id}"),
            complete_token=token(f"verification.complete.{verification_id}"),
        )

    @blueprint.post("/verifications/<int:verification_id>/review/confirm")
    def verification_review_confirm(verification_id: int):
        require_run()
        protect(f"verification.review.confirm.{verification_id}")
        try:
            confirm_verification_review(database, verification_id, request.form.get("content_hash", ""))
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("provider_verification.verification_review", verification_id=verification_id), code=303)

    @blueprint.post("/verifications/<int:verification_id>/complete")
    def verification_complete(verification_id: int):
        require_run()
        protect(f"verification.complete.{verification_id}")
        try:
            complete_verification(database, verification_id)
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.post("/verifications/<int:verification_id>/decline")
    def verification_decline(verification_id: int):
        require_run()
        protect(f"verification.decline.{verification_id}")
        try:
            decline_verification(database, verification_id)
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("provider_verification.verification_show", verification_id=verification_id), code=303)

    @blueprint.get("/contracts")
    def contracts():
        return render_template("controller/contracts.html", contracts=load_contracts().contracts)

    @blueprint.get("/contracts/<contract_id>")
    def contract_show(contract_id: str):
        try:
            contract = load_contracts().get(contract_id)
        except ValidationError:
            abort(404)
        return render_template("controller/contract.html", contract=contract)

    return blueprint


def register_verification_api(app, database_path: Path) -> None:
    database = Path(database_path)

    @app.get("/api/v1/controller/verifications")
    def api_verifications():
        if schema_status(database)["status"] != "ready":
            return jsonify({"items": []})
        return jsonify({"items": list_verification_requests(database)})

    @app.get("/api/v1/controller/verifications/<int:verification_id>")
    def api_verification(verification_id: int):
        if schema_status(database)["status"] != "ready":
            abort(404)
        try:
            detail = verification_detail(database, verification_id)
        except ValidationError:
            abort(404)
        for evidence in detail["evidence"]:  # type: ignore[index]
            if evidence["confidentiality"] == "redacted_sensitive":
                evidence["summary"] = "[redigiert]"
        return jsonify(detail)

    @app.get("/api/v1/controller/contracts")
    def api_contracts():
        catalog = load_contracts()
        return jsonify(
            {"catalog_version": catalog.catalog_version, "items": [item.as_dict() for item in catalog.contracts]}
        )

    @app.get("/api/v1/controller/contracts/<contract_id>")
    def api_contract(contract_id: str):
        try:
            contract = load_contracts().get(contract_id)
        except ValidationError:
            abort(404)
        return jsonify(contract.as_dict())

    @app.get("/api/v1/controller/assessments")
    def api_assessments():
        if schema_status(database)["status"] != "ready":
            return jsonify({"items": []})
        return jsonify({"items": list_assessments(database)})

    @app.get("/api/v1/controller/assessments/<int:assessment_id>")
    def api_assessment(assessment_id: int):
        if schema_status(database)["status"] != "ready":
            abort(404)
        matches = [item for item in list_assessments(database) if int(item["id"]) == assessment_id]
        if not matches:
            abort(404)
        return jsonify(matches[0])


def _evidence_form() -> dict[str, object]:
    digest = request.form.get("digest", "").strip() or None
    return {
        "claim_id": request.form.get("claim_id", ""),
        "kind": request.form.get("kind", ""),
        "source": request.form.get("source", ""),
        "summary": request.form.get("summary", ""),
        "verification_method": request.form.get("verification_method", ""),
        "observed_at": request.form.get("observed_at", ""),
        "valid_until": request.form.get("valid_until", ""),
        "confidentiality": request.form.get("confidentiality", "internal"),
        "digest": digest,
    }
