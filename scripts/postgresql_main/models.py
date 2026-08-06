"""Shared immutable models and canonical serialization helpers."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import re
from collections.abc import Mapping, Sequence


ALLOCATION_IDS = ("gitea", "openbao", "semaphore", "nodered")
PHASES = (
    "planned",
    "secret_directories_ready",
    "secrets_ready",
    "pki_ready",
    "lxc_created",
    "lxc_started",
    "guest_bundle_ready",
    "guest_os_ready",
    "postgresql_installed",
    "postgresql_configured",
    "allocations_created",
    "readiness_verified",
    "backups_verified",
    "completed",
)
MULTI_ITEM_PHASES = {
    "secret_directories_ready": (
        "provider-pki",
        "allocations-root",
        *ALLOCATION_IDS,
    ),
    "secrets_ready": ALLOCATION_IDS,
    "guest_bundle_ready": (
        "postgresql-main-guest.py",
        "guest-plan.json",
        "public-manifest.json",
        "ca.crt",
        "server.crt",
        "server.key",
        "gitea/application-password",
        "openbao/application-password",
        "semaphore/application-password",
        "nodered/application-password",
    ),
    "guest_os_ready": ("apt_update", "full_upgrade", "validate"),
    "postgresql_installed": ("packages", "validate"),
    "postgresql_configured": ("tls", "settings", "hba", "start", "validate"),
    "allocations_created": ALLOCATION_IDS,
    "readiness_verified": ("provider", *ALLOCATION_IDS),
    "backups_verified": ALLOCATION_IDS,
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class ProvisioningError(RuntimeError):
    """A bounded provisioning step cannot continue safely."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_sha256(value: Mapping[str, object], excluded: Sequence[str] = ()) -> str:
    reduced = {key: item for key, item in value.items() if key not in set(excluded)}
    return hashlib.sha256(canonical_json(reduced)).hexdigest()


@dataclasses.dataclass(frozen=True)
class ResumePlan:
    document: Mapping[str, object]

    @property
    def status(self) -> str:
        return str(self.document["resume_status"])

    @property
    def sha256(self) -> str:
        return str(self.document["resume_sha256"])

    def render_json(self) -> str:
        return canonical_json(self.document).decode("utf-8") + "\n"

    def render_text(self) -> str:
        lines = [
            "== POSTGRESQL-MAIN RESUME-PLAN ==",
            f"Operation: {self.document['operation_id']}",
            f"Originalplan: {self.document['plan_sha256']}",
            f"Letzte bestätigte Phase: {self.document['phase']}",
            f"Offene Phase: {self.document.get('next_phase') or 'keine'}",
            f"Nächste Einzelmutation: {self.document.get('next_item') or 'keine'}",
        ]
        conflicts = list(self.document.get("conflicts", []))
        lines.append("Konflikte: " + ("; ".join(conflicts) if conflicts else "keine"))
        lines.append(f"Resume-SHA-256: {self.sha256}")
        lines.append(self.status)
        return "\n".join(lines) + "\n"
