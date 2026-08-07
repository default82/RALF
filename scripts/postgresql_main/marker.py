"""Atomic provisioning marker with phase and item-level progress."""

from __future__ import annotations

import copy
import pathlib
import re
from collections.abc import Callable, Mapping

from .filesystem import SecureFilesystem
from .models import ALLOCATION_IDS, MULTI_ITEM_PHASES, PHASES, ProvisioningError, SHA256_RE


MARKER_PATH = pathlib.Path(
    "/secrets/database-service/providers/postgresql-main/provisioning-state.json"
)
PLAN_PATH = pathlib.Path(
    "/secrets/database-service/providers/postgresql-main/provisioning-plan.json"
)
MARKER_SCHEMA_VERSION = 1


def new_marker(
    *,
    operation_id: str,
    repository_commit: str,
    plan: Mapping[str, object],
    artifact_hashes: Mapping[str, str],
    now: str,
) -> dict[str, object]:
    if not re.fullmatch(r"[0-9a-f]{40}", repository_commit):
        raise ProvisioningError("REPOSITORY_COMMIT_INVALID", repository_commit)
    return {
        "schema_version": MARKER_SCHEMA_VERSION,
        "operation_id": operation_id,
        "provider_instance_id": "postgresql-main",
        "repository_commit": repository_commit,
        "plan_sha256": plan["plan_sha256"],
        "configuration_sha256": plan["configuration_sha256"],
        "version_matrix_sha256": plan["version_matrix_sha256"],
        "phase": None,
        "in_progress_phase": "planned",
        "in_progress_item": "provisioning-state",
        "completed_phases": [],
        "phase_progress": {},
        "created_at": now,
        "updated_at": now,
        "vmid": plan["proxmox_observations"]["vmid"],
        "artifact_hashes": dict(sorted(artifact_hashes.items())),
        "public_certificate_fingerprints": {},
        "readiness_status": {
            "provider_status": "not_verified",
            "allocation_configuration": "not_verified",
            "consumer_connectivity": "pending",
            "allocation_readiness": "consumer_validation_pending",
        },
        "backup_artifacts": {},
        "last_error": None,
    }


def validate_marker(value: object) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ProvisioningError("MARKER_INVALID", "Markerwurzel ist kein Objekt")
    required = {
        "schema_version", "operation_id", "provider_instance_id", "repository_commit",
        "plan_sha256", "configuration_sha256", "version_matrix_sha256", "phase",
        "in_progress_phase", "in_progress_item", "completed_phases", "phase_progress",
        "created_at", "updated_at", "vmid", "artifact_hashes",
        "public_certificate_fingerprints", "readiness_status", "backup_artifacts", "last_error",
    }
    if set(value) != required:
        raise ProvisioningError("MARKER_INVALID", "Markerfelder sind unvollständig oder unbekannt")
    if value["schema_version"] != MARKER_SCHEMA_VERSION or value["provider_instance_id"] != "postgresql-main":
        raise ProvisioningError("MARKER_INVALID", "Markerschema oder Provider ist ungültig")
    for key in ("plan_sha256", "configuration_sha256", "version_matrix_sha256"):
        if not isinstance(value[key], str) or not SHA256_RE.fullmatch(value[key]):
            raise ProvisioningError("MARKER_INVALID", f"Ungültiger Hash: {key}")
    if not isinstance(value["repository_commit"], str) or not re.fullmatch(r"[0-9a-f]{40}", value["repository_commit"]):
        raise ProvisioningError("MARKER_INVALID", "Repository-Commit ungültig")
    completed = value["completed_phases"]
    if not isinstance(completed, list) or completed != list(PHASES[: len(completed)]):
        raise ProvisioningError("MARKER_INVALID", "Phasenreihenfolge ist ungültig")
    phase = value["phase"]
    expected_phase = completed[-1] if completed else None
    if phase != expected_phase:
        raise ProvisioningError("MARKER_INVALID", "Phase stimmt nicht mit completed_phases überein")
    in_progress = value["in_progress_phase"]
    if in_progress is not None:
        next_index = len(completed)
        if next_index >= len(PHASES) or in_progress != PHASES[next_index]:
            raise ProvisioningError("MARKER_INVALID", "in_progress_phase ist nicht die nächste Phase")
    in_progress_item = value["in_progress_item"]
    if in_progress_item is not None:
        if in_progress not in MULTI_ITEM_PHASES or in_progress_item not in MULTI_ITEM_PHASES[in_progress]:
            if not (in_progress == "planned" and in_progress_item == "provisioning-state"):
                raise ProvisioningError("MARKER_INVALID", "in_progress_item ist ungültig")
    progress = value["phase_progress"]
    if not isinstance(progress, dict):
        raise ProvisioningError("MARKER_INVALID", "phase_progress ist ungültig")
    for key, items in progress.items():
        if key not in MULTI_ITEM_PHASES or not isinstance(items, list):
            raise ProvisioningError("MARKER_INVALID", "Unbekannter Teilfortschritt")
        allowed = MULTI_ITEM_PHASES[key]
        if len(items) != len(set(items)) or any(item not in allowed for item in items):
            raise ProvisioningError("MARKER_INVALID", "Teilfortschritt enthält ungültige Elemente")
        if items != [item for item in allowed if item in items]:
            raise ProvisioningError("MARKER_INVALID", "Teilfortschritt ist nicht geordnet")
    return copy.deepcopy(value)


class MarkerStore:
    def __init__(
        self,
        filesystem: SecureFilesystem,
        *,
        marker_path: pathlib.Path = MARKER_PATH,
        plan_path: pathlib.Path = PLAN_PATH,
        clock: Callable[[], str],
    ) -> None:
        self.fs = filesystem
        self.marker_path = marker_path
        self.plan_path = plan_path
        self.clock = clock

    def exists(self) -> bool:
        return self.fs.path(self.marker_path).exists()

    def create(self, marker: Mapping[str, object], plan: Mapping[str, object]) -> None:
        self.fs.exclusive_json(self.plan_path, plan)
        self.fs.exclusive_json(self.marker_path, marker)

    def load(self) -> dict[str, object]:
        self.fs.validate(self.marker_path, kind="file", mode=0o600)
        return validate_marker(self.fs.read_json(self.marker_path))

    def load_plan(self) -> dict[str, object]:
        self.fs.validate(self.plan_path, kind="file", mode=0o600)
        value = self.fs.read_json(self.plan_path)
        if not isinstance(value, dict) or not SHA256_RE.fullmatch(str(value.get("plan_sha256", ""))):
            raise ProvisioningError("PLAN_EVIDENCE_INVALID", "Gespeicherter Plan ist ungültig")
        return value

    def save(self, marker: Mapping[str, object]) -> dict[str, object]:
        updated = copy.deepcopy(dict(marker))
        updated["updated_at"] = self.clock()
        validate_marker(updated)
        self.fs.atomic_json(self.marker_path, updated)
        return updated

    def begin(self, marker: Mapping[str, object], phase: str, item: str | None = None) -> dict[str, object]:
        updated = copy.deepcopy(dict(marker))
        if phase != PHASES[len(updated["completed_phases"])]:
            raise ProvisioningError("PHASE_ORDER_CONFLICT", phase)
        updated["in_progress_phase"] = phase
        updated["in_progress_item"] = item
        updated["last_error"] = None
        return self.save(updated)

    def progress(self, marker: Mapping[str, object], phase: str, item: str) -> dict[str, object]:
        updated = copy.deepcopy(dict(marker))
        items = list(updated["phase_progress"].get(phase, []))
        allowed = MULTI_ITEM_PHASES[phase]
        expected = allowed[len(items)] if len(items) < len(allowed) else None
        if item != expected:
            raise ProvisioningError("PHASE_PROGRESS_CONFLICT", f"{phase}:{item}")
        items.append(item)
        updated["phase_progress"][phase] = items
        updated["in_progress_item"] = None
        return self.save(updated)

    def complete(self, marker: Mapping[str, object], phase: str) -> dict[str, object]:
        updated = copy.deepcopy(dict(marker))
        if phase in MULTI_ITEM_PHASES and updated["phase_progress"].get(phase, []) != list(MULTI_ITEM_PHASES[phase]):
            raise ProvisioningError("PHASE_INCOMPLETE", phase)
        if phase != PHASES[len(updated["completed_phases"])]:
            raise ProvisioningError("PHASE_ORDER_CONFLICT", phase)
        updated["completed_phases"].append(phase)
        updated["phase"] = phase
        updated["in_progress_phase"] = None
        updated["in_progress_item"] = None
        updated["last_error"] = None
        return self.save(updated)

    def record_error(self, marker: Mapping[str, object], code: str, message: str) -> dict[str, object]:
        updated = copy.deepcopy(dict(marker))
        updated["last_error"] = {"code": code, "summary": message[:300]}
        return self.save(updated)
