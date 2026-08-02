"""Server-rendered, local-only inventory controller routes."""

from __future__ import annotations

from pathlib import Path
from urllib.parse import urlsplit

from flask import Blueprint, abort, jsonify, redirect, render_template, request, url_for

from .catalog import load_catalog
from .csrf import consume_token, issue_token
from .models import INVENTORY_STATES, PREFERENCES, REQUIREMENTS, SECTIONS, ValidationError
from .planner import build_plan
from .questions import load_questions, validate_answer, visible_questions
from .storage import (
    confirm_plan,
    confirm_section,
    confirmation_status,
    create_setup_run,
    current_plan,
    delete_inventory,
    get_inventory_item,
    latest_run,
    list_rows,
    save_inventory,
    save_answer,
    save_preference,
    save_requirement,
    schema_status,
)

LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


def create_controller_blueprint(database_path: Path) -> Blueprint:
    blueprint = Blueprint(
        "controller",
        __name__,
        url_prefix="/controller",
        template_folder="templates",
        static_folder="static",
        static_url_path="/static",
    )
    database = Path(database_path)

    @blueprint.before_request
    def local_post_boundary():
        if request.method != "POST":
            return None
        host = urlsplit(request.host_url).hostname
        if host not in LOCAL_HOSTS:
            abort(400, "Controller-POST ist nur über einen dokumentierten Loopback-Host zulässig.")
        origin = request.headers.get("Origin")
        if origin and urlsplit(origin).hostname not in LOCAL_HOSTS:
            abort(400, "Origin ist für lokale Controller-Formulare nicht zulässig.")
        return None

    def state_or_none():
        return latest_run(database) if schema_status(database)["status"] == "ready" else None

    def form_token(form_id: str) -> str | None:
        return issue_token(database, form_id) if schema_status(database)["status"] == "ready" else None

    def require_run():
        run = state_or_none()
        if run is None:
            abort(409, "Controllerdatenbank oder Setup-Lauf ist nicht initialisiert.")
        return run

    def protect(form_id: str) -> None:
        try:
            consume_token(database, form_id, request.form.get("csrf_token"))
        except ValidationError as exc:
            abort(400, str(exc))

    @blueprint.get("/")
    def dashboard():
        status = controller_summary(database)
        return render_template("controller/dashboard.html", controller=status)

    @blueprint.get("/setup/start")
    def setup_start():
        return render_template(
            "controller/start.html",
            initialized=schema_status(database),
            run=state_or_none(),
            csrf_token=form_token("setup.start"),
        )

    @blueprint.post("/setup/start")
    def setup_start_post():
        if schema_status(database)["status"] != "ready":
            abort(409, "Controllerdatenbank muss zuerst explizit initialisiert werden.")
        protect("setup.start")
        if state_or_none() is None:
            create_setup_run(database)
        return redirect(url_for("controller.inventory"), code=303)

    @blueprint.get("/inventory")
    def inventory():
        run = require_run()
        return render_template(
            "controller/inventory.html",
            run=run,
            items=list_rows(database, "inventory_items", run["id"]),
            csrf_token=form_token("inventory.review"),
        )

    @blueprint.get("/questions")
    def questions():
        run = require_run()
        saved_rows = list_rows(database, "answers", run["id"])
        import json

        saved = {row["question_id"]: json.loads(row["answer_json"]) for row in saved_rows}
        return render_template(
            "controller/questions.html",
            questions=visible_questions(saved),
            saved=saved,
            csrf_token=form_token("questions.update"),
        )

    @blueprint.post("/questions")
    def questions_post():
        run = require_run()
        protect("questions.update")
        question_id = request.form.get("question_id", "")
        raw_value: object = request.form.get("answer", "")
        question = next((item for item in load_questions() if item.question_id == question_id), None)
        if question and question.answer_type == "boolean":
            raw_value = raw_value == "true"
        elif question and question.answer_type == "multi_choice":
            raw_value = request.form.getlist("answer")
        try:
            save_answer(database, run["id"], question_id, validate_answer(question_id, raw_value))
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.questions"), code=303)

    @blueprint.post("/inventory")
    def inventory_post():
        run = require_run()
        protect("inventory.review")
        confirm_section(database, run["id"], "inventory")
        return redirect(url_for("controller.requirements"), code=303)

    @blueprint.get("/inventory/new")
    def inventory_new():
        require_run()
        return render_template(
            "controller/inventory_form.html",
            item=None,
            catalog=load_catalog(),
            states=sorted(INVENTORY_STATES),
            csrf_token=form_token("inventory.create"),
        )

    @blueprint.post("/inventory/new")
    def inventory_new_post():
        run = require_run()
        protect("inventory.create")
        try:
            save_inventory(database, run["id"], _inventory_form_values())
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.inventory"), code=303)

    @blueprint.get("/inventory/<int:item_id>/edit")
    def inventory_edit(item_id: int):
        run = require_run()
        item = get_inventory_item(database, run["id"], item_id)
        if item is None:
            abort(404)
        return render_template(
            "controller/inventory_form.html",
            item=item,
            catalog=load_catalog(),
            states=sorted(INVENTORY_STATES),
            csrf_token=form_token(f"inventory.edit.{item_id}"),
            delete_csrf_token=form_token(f"inventory.delete.{item_id}"),
        )

    @blueprint.post("/inventory/<int:item_id>/edit")
    def inventory_edit_post(item_id: int):
        run = require_run()
        protect(f"inventory.edit.{item_id}")
        try:
            save_inventory(database, run["id"], _inventory_form_values(), item_id=item_id)
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.inventory"), code=303)

    @blueprint.post("/inventory/<int:item_id>/delete")
    def inventory_delete(item_id: int):
        run = require_run()
        protect(f"inventory.delete.{item_id}")
        try:
            delete_inventory(database, run["id"], item_id)
        except ValidationError as exc:
            abort(404, str(exc))
        return redirect(url_for("controller.inventory"), code=303)

    @blueprint.get("/requirements")
    def requirements():
        run = require_run()
        saved = {row["capability_id"]: row for row in list_rows(database, "capability_requirements", run["id"])}
        return render_template(
            "controller/requirements.html", catalog=load_catalog(), saved=saved,
            requirements=sorted(REQUIREMENTS), csrf_token=form_token("requirements.update")
        )

    @blueprint.post("/requirements")
    def requirements_post():
        run = require_run()
        protect("requirements.update")
        catalog = load_catalog()
        try:
            for capability in catalog.capabilities:
                value = request.form.get(f"requirement.{capability.capability_id}")
                if value is None:
                    raise ValidationError(f"Pflichtentscheidung fehlt: {capability.capability_id}")
                save_requirement(database, run["id"], capability.capability_id, value)
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.preferences"), code=303)

    @blueprint.get("/preferences")
    def preferences():
        run = require_run()
        items = list_rows(database, "inventory_items", run["id"])
        saved = list_rows(database, "provider_preferences", run["id"])
        return render_template(
            "controller/preferences.html", catalog=load_catalog(), inventory=items, saved=saved,
            preferences=sorted(PREFERENCES), csrf_token=form_token("preferences.update")
        )

    @blueprint.post("/preferences")
    def preferences_post():
        run = require_run()
        protect("preferences.update")
        try:
            capability_id = request.form.get("capability_id", "")
            provider_reference = request.form.get("provider_reference", "")
            provider_id = request.form.get("provider_id", "")
            preference = request.form.get("preference", "")
            rank_value = request.form.get("rank", "").strip()
            rank = int(rank_value) if rank_value else None
            save_preference(database, run["id"], capability_id, provider_reference, provider_id, preference, rank)
        except (ValidationError, ValueError) as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.preferences"), code=303)

    @blueprint.get("/verification")
    def verification():
        run = require_run()
        items = [row for row in list_rows(database, "inventory_items", run["id"]) if row["state"] == "reported"]
        return render_template(
            "controller/verification.html", items=items, csrf_token=form_token("verification.update")
        )

    @blueprint.post("/verification")
    def verification_post():
        run = require_run()
        protect("verification.update")
        item_id = int(request.form.get("item_id", "0"))
        item = get_inventory_item(database, run["id"], item_id)
        if item is None or item["state"] != "reported":
            abort(400, "Nur gemeldete Provider erhalten eine spätere Prüfungsfreigabe.")
        item.update(
            verification_consent=request.form.get("verification_consent") == "yes",
            verification_scope=request.form.get("verification_scope", ""),
        )
        try:
            save_inventory(database, run["id"], item, item_id=item_id)
        except ValidationError as exc:
            abort(400, str(exc))
        return redirect(url_for("controller.verification"), code=303)

    @blueprint.get("/review")
    def review():
        run = require_run()
        return render_template(
            "controller/review.html", run=run, confirmations=confirmation_status(database, run["id"]),
            inventory=list_rows(database, "inventory_items", run["id"]),
            requirements=list_rows(database, "capability_requirements", run["id"]),
            preferences=list_rows(database, "provider_preferences", run["id"]),
            tokens={section: form_token(f"review.confirm.{section}") for section in sorted(SECTIONS)},
        )

    @blueprint.post("/review/confirm/<section>")
    def review_confirm(section: str):
        run = require_run()
        if section not in SECTIONS:
            abort(404)
        protect(f"review.confirm.{section}")
        confirm_section(database, run["id"], section)
        return redirect(url_for("controller.review"), code=303)

    @blueprint.get("/plan")
    def plan():
        run = require_run()
        return render_template(
            "controller/plan.html", plan=current_plan(database, run["id"]),
            generate_token=form_token("plan.generate"), confirm_token=form_token("plan.confirm")
        )

    @blueprint.post("/plan/generate")
    def plan_generate():
        run = require_run()
        protect("plan.generate")
        try:
            build_plan(database, run["id"])
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("controller.plan"), code=303)

    @blueprint.post("/plan/confirm")
    def plan_confirm():
        run = require_run()
        protect("plan.confirm")
        try:
            confirm_plan(database, run["id"], request.form.get("plan_hash", ""))
        except ValidationError as exc:
            abort(409, str(exc))
        return redirect(url_for("controller.plan"), code=303)

    return blueprint


def _inventory_form_values() -> dict[str, object]:
    return {
        "capability_id": request.form.get("capability_id", ""),
        "provider_id": request.form.get("provider_id", ""),
        "display_name": request.form.get("display_name", ""),
        "product_name": request.form.get("product_name", ""),
        "location": request.form.get("location", ""),
        "management_url": request.form.get("management_url", ""),
        "source": "user",
        "state": request.form.get("state", "reported"),
        "verification_method": request.form.get("verification_method", ""),
        "verification_scope": request.form.get("verification_scope", ""),
        "verification_consent": request.form.get("verification_consent") == "yes",
        "verification_evidence": request.form.get("verification_evidence", ""),
        "last_verified_at": request.form.get("last_verified_at", ""),
    }


def controller_summary(database: Path) -> dict[str, object]:
    schema = schema_status(database)
    result: dict[str, object] = {
        "available": schema["status"] == "ready",
        "database": schema,
        "message": "Dieser Controller führt derzeit keine Infrastrukturänderungen aus.",
        "setup_status": "not_initialized",
        "inventory_count": 0,
        "reported_count": 0,
        "verified_count": 0,
        "conflict_count": 0,
        "open_verifications": 0,
        "confirmed_sections": [],
        "plan_status": "not_generated",
        "verification_requests": 0,
        "verification_awaiting_consent": 0,
        "verification_ready": 0,
        "verification_evidence_pending": 0,
        "verification_review_pending": 0,
        "verification_completed": 0,
        "stale_assessments": 0,
        "conflict_assessments": 0,
    }
    if schema["status"] != "ready":
        return result
    run = latest_run(database)
    if run is None:
        result["setup_status"] = "not_started"
        return result
    inventory = list_rows(database, "inventory_items", run["id"])
    plan = current_plan(database, run["id"])
    confirmations = confirmation_status(database, run["id"])
    from .verification import list_assessments, list_verification_requests

    verifications = list_verification_requests(database, int(run["id"]))
    assessments = list_assessments(database)
    result.update(
        setup_status=run["status"],
        revision=run["revision"],
        inventory_count=len(inventory),
        reported_count=sum(item["state"] == "reported" for item in inventory),
        verified_count=sum(item["state"] == "verified" for item in inventory),
        conflict_count=sum(item["state"] == "conflict" for item in inventory),
        open_verifications=sum(item["state"] == "reported" for item in inventory),
        confirmed_sections=[section for section, confirmed in confirmations.items() if confirmed],
        plan_status=plan["status"] if plan else "not_generated",
        verification_requests=len(verifications),
        verification_awaiting_consent=sum(item["state"] == "awaiting_consent" for item in verifications),
        verification_ready=sum(item["state"] == "ready" for item in verifications),
        verification_evidence_pending=sum(item["state"] == "evidence_pending" for item in verifications),
        verification_review_pending=sum(item["state"] == "review_pending" for item in verifications),
        verification_completed=sum(item["state"] == "completed" for item in verifications),
        stale_assessments=sum(item["effective_freshness"] == "stale" for item in assessments),
        conflict_assessments=sum(
            item["provider_presence"] == "conflict"
            or item["contract_compatibility"] == "conflict"
            or item["integration_readiness"] == "conflict"
            for item in assessments
        ),
    )
    return result


def register_controller_api(app, database_path: Path) -> None:
    database = Path(database_path)

    @app.get("/api/v1/controller/status")
    def controller_api_status():
        return jsonify(controller_summary(database))

    @app.get("/api/v1/controller/inventory")
    def controller_api_inventory():
        run = latest_run(database) if schema_status(database)["status"] == "ready" else None
        return jsonify({"items": list_rows(database, "inventory_items", run["id"]) if run else []})

    @app.get("/api/v1/controller/capabilities")
    def controller_api_capabilities():
        catalog = load_catalog()
        return jsonify(
            {
                "catalog_version": catalog.catalog_version,
                "capabilities": [item.__dict__ for item in catalog.capabilities],
                "providers": [item.__dict__ for item in catalog.providers],
            }
        )

    @app.get("/api/v1/controller/preferences")
    def controller_api_preferences():
        run = latest_run(database) if schema_status(database)["status"] == "ready" else None
        return jsonify({"items": list_rows(database, "provider_preferences", run["id"]) if run else []})

    @app.get("/api/v1/controller/plan")
    def controller_api_plan():
        run = latest_run(database) if schema_status(database)["status"] == "ready" else None
        return jsonify({"plan": current_plan(database, run["id"]) if run else None})
