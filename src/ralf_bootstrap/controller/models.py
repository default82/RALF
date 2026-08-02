"""Stable controller values and input validation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
import re
import unicodedata
from urllib.parse import urlsplit

INVENTORY_STATES = frozenset(
    {"unknown", "reported", "verified", "unavailable", "conflict", "declined"}
)
VERIFICATION_METHODS = frozenset(
    {"manual", "connector", "local_probe", "imported_evidence"}
)
VERIFICATION_REQUEST_STATES = frozenset(
    {
        "draft",
        "awaiting_consent",
        "ready",
        "evidence_pending",
        "review_pending",
        "completed",
        "failed",
        "declined",
        "obsolete",
    }
)
VERIFICATION_TASK_STATES = frozenset(
    {"planned", "consented", "evidence_pending", "completed", "failed", "declined", "obsolete"}
)
CLAIM_RESULTS = frozenset(
    {"unknown", "satisfied", "not_satisfied", "not_observed", "conflict", "stale", "not_applicable"}
)
EVIDENCE_KINDS = frozenset(
    {
        "manual_attestation",
        "configuration_summary",
        "service_status_summary",
        "capability_summary",
        "certificate_metadata",
        "imported_evidence",
        "document_reference",
    }
)
EVIDENCE_CONFIDENTIALITY = frozenset({"public", "internal", "redacted_sensitive"})
PROVIDER_PRESENCE = frozenset({"unknown", "reported", "verified", "unavailable", "conflict"})
CONTRACT_COMPATIBILITY = frozenset(
    {"unknown", "compatible", "partially_compatible", "incompatible", "conflict"}
)
INTEGRATION_READINESS = frozenset({"not_assessed", "ready", "blocked", "deferred", "conflict"})
VERIFICATION_FRESHNESS = frozenset({"never_verified", "fresh", "stale"})
REQUIREMENTS = frozenset({"required", "optional", "not_needed", "deferred"})
PREFERENCES = frozenset(
    {"preferred", "allowed_fallback", "excluded", "deferred", "recommend_then_confirm"}
)
RUN_STATUSES = frozenset(
    {
        "draft",
        "inventory_review",
        "requirements_review",
        "preferences_review",
        "plan_ready",
        "plan_confirmed",
        "blocked",
        "obsolete",
    }
)
PLAN_STATUSES = frozenset({"draft", "blocked", "ready", "confirmed", "obsolete"})
STEP_TYPES = frozenset(
    {
        "verify_provider",
        "reuse_provider",
        "resolve_conflict",
        "decide_integration",
        "install_provider",
        "configure_provider",
        "defer_capability",
        "manual_action",
    }
)
SECTIONS = frozenset({"inventory", "requirements", "preferences", "verification_scope"})
PROVIDER_LIFECYCLES = frozenset({"existing", "external", "local", "built_in"})
PROVIDER_READINESS = frozenset(
    {"available", "reported", "planned", "experimental", "unsupported"}
)

_IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
_CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


class ValidationError(ValueError):
    """Raised for invalid, non-secret controller input."""


def require_choice(value: str, allowed: frozenset[str], field: str) -> str:
    if value not in allowed:
        raise ValidationError(f"{field} besitzt einen unbekannten Wert.")
    return value


def normalize_text(
    value: object,
    field: str,
    *,
    maximum: int,
    required: bool = False,
    multiline: bool = False,
) -> str:
    if not isinstance(value, str):
        raise ValidationError(f"{field} muss Text sein.")
    normalized = unicodedata.normalize("NFC", value).strip()
    if required and not normalized:
        raise ValidationError(f"{field} darf nicht leer sein.")
    if len(normalized) > maximum:
        raise ValidationError(f"{field} ist zu lang (maximal {maximum} Zeichen).")
    if _CONTROL_RE.search(normalized):
        raise ValidationError(f"{field} enthält Steuerzeichen.")
    if not multiline and ("\n" in normalized or "\r" in normalized):
        raise ValidationError(f"{field} darf keinen Zeilenumbruch enthalten.")
    return normalized


def validate_identifier(value: object, field: str) -> str:
    text = normalize_text(value, field, maximum=128, required=True)
    if not _IDENTIFIER_RE.fullmatch(text):
        raise ValidationError(f"{field} besitzt kein gültiges Kennungsformat.")
    return text


def validate_management_url(value: object) -> str | None:
    text = normalize_text(value or "", "Management-URL", maximum=2048)
    if not text:
        return None
    parsed = urlsplit(text)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValidationError("Management-URL muss eine absolute HTTP(S)-URL sein.")
    if parsed.username is not None or parsed.password is not None:
        raise ValidationError("Management-URL darf keine Zugangsdaten enthalten.")
    if parsed.fragment:
        raise ValidationError("Management-URL darf keinen Fragmentanteil enthalten.")
    return text


def validate_inventory(values: dict[str, object]) -> dict[str, object]:
    state = require_choice(str(values.get("state", "reported")), INVENTORY_STATES, "state")
    method_value = values.get("verification_method") or None
    method = None
    if method_value:
        method = require_choice(str(method_value), VERIFICATION_METHODS, "verification_method")
    last_verified_at = normalize_text(
        values.get("last_verified_at") or "", "Verifikationszeitpunkt", maximum=64
    ) or None
    evidence = normalize_text(
        values.get("verification_evidence") or "",
        "Verifikationsevidenz",
        maximum=500,
        multiline=True,
    )
    if state == "verified" and (not method or not last_verified_at or not evidence):
        raise ValidationError(
            "verified benötigt Verifikationsart, Zeitpunkt und nicht geheime Evidenz."
        )
    if last_verified_at:
        try:
            parsed = datetime.fromisoformat(last_verified_at.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValidationError("Verifikationszeitpunkt muss ISO-8601 entsprechen.") from exc
        if parsed.tzinfo is None:
            raise ValidationError("Verifikationszeitpunkt benötigt eine Zeitzone.")
    return {
        "capability_id": validate_identifier(values.get("capability_id"), "Fähigkeit"),
        "provider_id": validate_identifier(values.get("provider_id"), "Provider"),
        "display_name": normalize_text(
            values.get("display_name"), "Anzeigename", maximum=160, required=True
        ),
        "product_name": normalize_text(
            values.get("product_name") or "", "Produktname", maximum=160
        ),
        "location": normalize_text(values.get("location") or "", "Standort", maximum=160),
        "management_url": validate_management_url(values.get("management_url")),
        "source": validate_identifier(values.get("source", "user"), "Quelle"),
        "state": state,
        "verification_method": method,
        "verification_scope": normalize_text(
            values.get("verification_scope") or "",
            "Prüfumfang",
            maximum=500,
            multiline=True,
        ),
        "verification_consent": bool(values.get("verification_consent", False)),
        "verification_evidence": evidence,
        "last_verified_at": last_verified_at,
    }


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


@dataclass(frozen=True)
class PlanStep:
    step_type: str
    capability_id: str
    provider_reference: str | None
    state: str
    title: str
    rationale: str
    prerequisites: tuple[str, ...]
    expected_effects: tuple[str, ...]
    mutation_class: str

    def as_dict(self) -> dict[str, object]:
        return {
            "step_type": self.step_type,
            "capability_id": self.capability_id,
            "provider_reference": self.provider_reference,
            "state": self.state,
            "title": self.title,
            "rationale": self.rationale,
            "prerequisites": list(self.prerequisites),
            "expected_effects": list(self.expected_effects),
            "mutation_class": self.mutation_class,
        }
