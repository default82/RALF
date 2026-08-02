"""Deterministic descriptive planner; it never creates executable commands."""

from __future__ import annotations

import hashlib
from pathlib import Path

from .catalog import Catalog, load_catalog
from .models import PlanStep, ValidationError, canonical_json
from .storage import confirmation_status, list_rows, read_connection, store_plan
from .verification import (
    audit_stale_assessments,
    latest_assessment_for_inventory,
    latest_verification_state_for_inventory,
    reconcile_run_verifications,
)


def build_plan(database: Path, run_id: int, *, catalog: Catalog | None = None) -> dict[str, object]:
    reconcile_run_verifications(database, run_id)
    catalog = catalog or load_catalog()
    confirmations = confirmation_status(database, run_id)
    requirements = {
        row["capability_id"]: row for row in list_rows(database, "capability_requirements", run_id)
    }
    inventory = list_rows(database, "inventory_items", run_id)
    preferences = list_rows(database, "provider_preferences", run_id)
    blockers: list[str] = []
    open_checks: list[str] = []
    steps: list[PlanStep] = []
    assessment_snapshots: list[dict[str, object]] = []

    missing_confirmations = [section for section, confirmed in sorted(confirmations.items()) if not confirmed]
    if missing_confirmations:
        raise ValidationError(
            "Planerzeugung benötigt bestätigte Pflichtabschnitte: "
            + ", ".join(missing_confirmations)
        )

    for capability in catalog.capabilities:
        requirement_row = requirements.get(capability.capability_id)
        if requirement_row is None:
            blockers.append(f"Pflichtentscheidung fehlt: {capability.capability_id}")
            continue
        requirement = str(requirement_row["requirement"])
        if requirement == "not_needed":
            continue
        if requirement == "deferred":
            steps.append(
                PlanStep(
                    "defer_capability",
                    capability.capability_id,
                    None,
                    "deferred",
                    f"{capability.display_name} zurückstellen",
                    "Die Fähigkeit wurde ausdrücklich zurückgestellt.",
                    (),
                    ("Keine Infrastrukturänderung",),
                    "local_persistent",
                )
            )
            continue

        candidates = [item for item in inventory if item["capability_id"] == capability.capability_id]
        selected_preferences = [
            item
            for item in preferences
            if item["capability_id"] == capability.capability_id
            and item["preference"] not in {"excluded", "deferred"}
        ]
        preferred = [item for item in selected_preferences if item["preference"] == "preferred"]
        if len(preferred) > 1:
            blockers.append(f"Mehrere bevorzugte Provider: {capability.capability_id}")
            continue
        def provider_state(preference: dict[str, object]) -> int:
            matching = next(
                (
                    item for item in candidates
                    if preference["provider_reference"] in {f"inventory:{item['id']}", item["provider_id"]}
                ),
                None,
            )
            assessment = (
                latest_assessment_for_inventory(database, int(matching["id"])) if matching else None
            )
            if assessment and assessment["effective_freshness"] == "fresh" and assessment["provider_presence"] == "verified":
                return 0
            if matching and matching["state"] == "verified":
                return 0
            if matching and matching["state"] == "reported":
                return 1
            return 2

        ordered_preferences = preferred + sorted(
            [item for item in selected_preferences if item["preference"] == "allowed_fallback"],
            key=lambda item: (provider_state(item), item["rank"] or 2**31, item["provider_reference"]),
        )
        recommendation = [
            item for item in selected_preferences if item["preference"] == "recommend_then_confirm"
        ]
        if not ordered_preferences and recommendation:
            blockers.append(f"Empfehlung wartet auf Bestätigung: {capability.capability_id}")
            steps.append(
                PlanStep(
                    "manual_action",
                    capability.capability_id,
                    recommendation[0]["provider_reference"],
                    "awaiting_confirmation",
                    f"Provider für {capability.display_name} bestätigen",
                    "Eine deterministische Empfehlung ist keine automatische Providerwahl.",
                    ("Ausdrückliche Providerbestätigung",),
                    ("Noch keine Installation",),
                    "local_persistent",
                )
            )
            continue
        chosen = ordered_preferences[0] if ordered_preferences else None
        if chosen is None:
            fallbacks = [
                item.display_name for item in catalog.providers
                if item.capability_id == capability.capability_id and item.readiness != "unsupported"
            ]
            if requirement == "required":
                blockers.append(f"Erforderliche Fähigkeit ohne bestätigten Provider: {capability.capability_id}")
            steps.append(
                PlanStep(
                    "manual_action",
                    capability.capability_id,
                    None,
                    "provider_needed",
                    f"Provider für {capability.display_name} auswählen",
                    "Vorhandene Provider und mögliche Fallbacks müssen zuerst bewertet werden.",
                    ("Providerwahl",),
                    tuple(["Kein Provider wird automatisch installiert", *[f"Möglicher späterer Fallback: {name}" for name in fallbacks]]),
                    "local_persistent",
                )
            )
            continue

        provider_reference = str(chosen["provider_reference"])
        inventory_provider = next(
            (
                item
                for item in candidates
                if provider_reference in {f"inventory:{item['id']}", str(item["provider_id"])}
            ),
            None,
        )
        catalog_provider = next(
            (item for item in catalog.providers if item.provider_id == chosen["provider_id"]), None
        )
        if inventory_provider:
            state = str(inventory_provider["state"])
            assessment = latest_assessment_for_inventory(database, int(inventory_provider["id"]))
            verification_state = latest_verification_state_for_inventory(
                database, int(inventory_provider["id"])
            )
            if assessment:
                assessment_snapshots.append(
                    {
                        key: assessment[key]
                        for key in (
                            "inventory_item_id",
                            "assessment_hash",
                            "provider_presence",
                            "contract_compatibility",
                            "integration_readiness",
                            "effective_freshness",
                        )
                    }
                )
            if state == "conflict":
                blockers.append(f"Ausgewählter Provider im Konflikt: {provider_reference}")
                steps.append(
                    PlanStep(
                        "resolve_conflict", capability.capability_id, provider_reference, state,
                        f"Konflikt für {inventory_provider['display_name']} lösen",
                        "Ein konfliktbehafteter Provider darf nicht direkt verwendet werden.",
                        ("Providervertrag klären",), ("Keine automatische Verwendung",), "read_only",
                    )
                )
                continue
            if state == "declined":
                blockers.append(f"Ausgewählter Provider wurde abgelehnt: {provider_reference}")
                continue
            if assessment and assessment["contract_compatibility"] in {"incompatible", "conflict"}:
                blockers.append(f"Providervertrag ist nicht kompatibel: {provider_reference}")
                steps.append(
                    PlanStep(
                        "resolve_conflict", capability.capability_id, provider_reference,
                        str(assessment["contract_compatibility"]),
                        f"Vertragskonflikt für {inventory_provider['display_name']} lösen",
                        "Die abgeschlossene Providerbewertung erlaubt keine direkte Wiederverwendung.",
                        ("Providerbewertung prüfen",), ("Keine automatische Verwendung",), "read_only",
                    )
                )
                continue
            assessment_fresh = bool(
                assessment
                and assessment["effective_freshness"] == "fresh"
                and assessment["provider_presence"] == "verified"
                and assessment["contract_compatibility"] == "compatible"
            )
            needs_verification = state == "reported" and not assessment_fresh
            if assessment and assessment["effective_freshness"] == "stale":
                needs_verification = True
                open_checks.append(f"Providerbewertung ist veraltet: {provider_reference}")
            if verification_state == "declined" and needs_verification:
                blockers.append(f"Providerverifikation wurde abgelehnt: {provider_reference}")
                fallbacks = [
                    item.display_name
                    for item in catalog.providers
                    if item.capability_id == capability.capability_id
                    and item.provider_id != inventory_provider["provider_id"]
                    and item.readiness != "unsupported"
                ]
                steps.append(
                    PlanStep(
                        "manual_action",
                        capability.capability_id,
                        provider_reference,
                        "verification_declined",
                        f"Alternative fuer {inventory_provider['display_name']} bewusst waehlen",
                        "Die abgelehnte Verifikation erlaubt weder Hochstufung noch automatische Fallbackinstallation.",
                        ("Neue Providerpraeferenz bestaetigen",),
                        tuple(["Keine automatische Installation", *[f"Moeglicher Fallback: {name}" for name in fallbacks]]),
                        "local_persistent",
                    )
                )
                continue
            if needs_verification:
                if not inventory_provider["verification_consent"]:
                    if verification_state not in {"ready", "evidence_pending", "review_pending"}:
                        blockers.append(f"Notwendige Verifikation nicht freigegeben: {provider_reference}")
                open_checks.append(f"Read-only Verifikation ausstehend: {provider_reference}")
                steps.append(
                    PlanStep(
                        "verify_provider", capability.capability_id, provider_reference,
                        verification_state or state,
                        f"{inventory_provider['display_name']} read-only verifizieren",
                        "Existenz und Providervertrag benötigen eine frische, abgeschlossene Bewertung.",
                        (str(inventory_provider["verification_scope"] or "Prüfumfang festlegen"),),
                        ("Providerstatus wird durch Evidenz nachvollziehbar",), "read_only",
                    )
                )
            elif not assessment_fresh and state not in {"verified"}:
                blockers.append(f"Provider ist nicht nutzbar: {provider_reference} ({state})")
                continue

            integration_blocked = bool(
                assessment and assessment["integration_readiness"] in {"blocked", "conflict"}
            )
            if capability.capability_id == "secure-ingress" and (
                _is_external_ingress(inventory_provider) or integration_blocked
            ):
                blockers.append("Sicherer Backendpfad vom externen Ingress zum Loopback-Upstream ist offen (O-012).")
                steps.append(
                    PlanStep(
                        "decide_integration", capability.capability_id, provider_reference, "blocked",
                        "Sicheren Backendpfad zum RALF-Webprozess entscheiden",
                        "Ein externer Proxy erreicht 127.0.0.1 im RALF-LXC nicht; Gunicorn wird nicht pauschal im LAN geöffnet.",
                        ("Quellbeschränkung", "Firewallgrenzen", "Backendtransport", "Host- und Proxy-Vertrauen"),
                        ("Ein minimaler, ausdrücklich bestätigter Backendvertrag",), "future_infrastructure",
                    )
                )
            steps.append(
                PlanStep(
                    "reuse_provider", capability.capability_id, provider_reference,
                    "after_verification" if needs_verification else (
                        "after_integration" if integration_blocked else "planned"
                    ),
                    f"Vorhandenen Provider {inventory_provider['display_name']} bevorzugt wiederverwenden",
                    "Ein geeigneter vorhandener Provider hat Vorrang vor einer Doppelinstallation.",
                    ("Provider verifiziert", "Integrationsvertrag geklärt"),
                    ("Keine redundante Providerinstallation",), "future_infrastructure",
                )
            )
        elif catalog_provider:
            if catalog_provider.readiness in {"planned", "experimental", "unsupported"}:
                blockers.append(f"Neuer Provider ist nicht sofort installierbar: {catalog_provider.provider_id}")
            steps.append(
                PlanStep(
                    "install_provider", capability.capability_id, f"catalog:{catalog_provider.provider_id}",
                    catalog_provider.readiness,
                    f"{catalog_provider.display_name} erst nach gesondertem Plan bereitstellen",
                    "Der neue Provider wurde ausdrücklich gewählt; dieser Zielplan führt ihn nicht aus.",
                    ("Gesonderter technischer Plan", "Eigene Apply-Freigabe"),
                    ("Spätere Providerbereitstellung",), "future_infrastructure",
                )
            )
        else:
            blockers.append(f"Unbekannte Providerreferenz: {provider_reference}")

    canonical = {
        "run_id": run_id,
        "requirements": requirements,
        "preferences": preferences,
        "inventory": inventory,
        "steps": [step.as_dict() for step in steps],
        "blockers": sorted(set(blockers)),
        "open_checks": sorted(set(open_checks)),
        "assessments": sorted(assessment_snapshots, key=lambda item: int(item["inventory_item_id"])),
    }
    with read_connection(database) as connection:
        revision = int(connection.execute("SELECT revision FROM setup_runs WHERE id=?", (run_id,)).fetchone()[0])
    canonical["revision"] = revision
    plan_hash = hashlib.sha256(canonical_json(canonical).encode("utf-8")).hexdigest()
    status = "blocked" if blockers else "ready"
    result = {
        "status": status,
        "plan_hash": plan_hash,
        "steps": [step.as_dict() for step in steps],
        "blockers": sorted(set(blockers)),
        "open_checks": sorted(set(open_checks)),
    }
    audit_stale_assessments(database, assessment_snapshots)
    result["id"] = store_plan(
        database, run_id, status, plan_hash, result["steps"], result["blockers"], result["open_checks"]
    )
    return result


def _is_external_ingress(item: dict[str, object]) -> bool:
    text = " ".join(
        str(item.get(key, "")).lower() for key in ("display_name", "product_name", "location", "provider_id")
    )
    return "opnsense" in text or "external" in text or "extern" in text
