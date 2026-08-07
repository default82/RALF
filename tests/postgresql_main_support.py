"""Shared fakes for the postgresql-main provisioning tests."""

from __future__ import annotations

import hashlib
import pathlib
import types

from postgresql_main.filesystem import SecureFilesystem
from postgresql_main.host import CONFIG_PATH, PASSWORD_PATHS, sha256_path
from postgresql_main.marker import MarkerStore
from postgresql_main.models import ALLOCATION_IDS, ProvisioningError
from postgresql_main import plan as shared_plan


NOW = "2026-08-06T12:00:00Z"
COMMIT = "a" * 40


class FakePki:
    def __init__(self, filesystem: SecureFilesystem, *, fault=lambda _point: None) -> None:
        self.fs = filesystem
        self.root = pathlib.Path("/secrets/database-service/providers/postgresql-main/pki")
        self.fault = fault

    def generate(self, fqdn: str, provider_ip: str) -> dict[str, str]:
        del fqdn, provider_ip
        for name, mode, point in (
            ("ca.key", 0o600, "after_ca_key"),
            ("ca.crt", 0o644, "after_ca_certificate"),
            ("server.key", 0o600, "after_server_key"),
            ("server.crt", 0o644, "after_server_certificate"),
        ):
            logical = self.root / name
            if not self.fs.path(logical).exists():
                self.fs.exclusive_bytes(logical, f"fake-{name}".encode(), mode=mode)
                self.fault(point)
        return self.verify("", "")

    def verify(self, fqdn: str, provider_ip: str) -> dict[str, str]:
        del fqdn, provider_ip
        for name, mode in (("ca.key", 0o600), ("ca.crt", 0o644), ("server.key", 0o600), ("server.crt", 0o644)):
            self.fs.validate(self.root / name, kind="file", mode=mode, require_nonempty=True)
        return {
            "ca": hashlib.sha256(b"fake-ca.crt").hexdigest(),
            "server": hashlib.sha256(b"fake-server.crt").hexdigest(),
        }


class FakeBackend:
    def __init__(self) -> None:
        self.commit = COMMIT
        self.clean = True
        self.actions: list[str] = []
        self.status = "absent"
        self.guest_completed: set[tuple[str, str | None]] = set()
        self.bundle_items: set[str] = set()
        self.cleanup_calls = 0

    def repository_commit(self) -> str:
        return self.commit

    def repository_clean(self) -> bool:
        return self.clean

    def create_lxc(self, plan) -> None:
        del plan
        self.actions.append("pct create")
        if self.status != "absent":
            raise ProvisioningError("LXC_CONFLICT", "exists")
        self.status = "stopped"

    def start_lxc(self, vmid: int) -> None:
        self.actions.append(f"pct start {vmid}")
        if self.status != "stopped":
            raise ProvisioningError("LXC_CONFLICT", "not stopped")
        self.status = "running"

    def verify_lxc(self, plan, *, expected_status: str) -> None:
        del plan
        if self.status != expected_status:
            raise ProvisioningError("LXC_STATE_CONFLICT", self.status)

    def verify_started_guest(self, plan) -> None:
        del plan
        if self.status != "running":
            raise ProvisioningError("GUEST_STATE_CONFLICT", self.status)

    def initialize_guest_bundle(self, vmid: int) -> None:
        self.actions.append(f"bundle init {vmid}")

    def push_bundle_item(self, vmid: int, source: pathlib.Path, relative: str, mode: int) -> None:
        del vmid, mode
        if not source.is_file():
            raise ProvisioningError("BUNDLE_SOURCE_MISSING", relative)
        self.actions.append(f"bundle push {relative}")
        self.bundle_items.add(relative)

    def verify_guest_bundle(self, vmid: int) -> None:
        del vmid
        if len(self.bundle_items) != 10:
            raise ProvisioningError("BUNDLE_INVALID", "incomplete")

    def verify_guest_bundle_item(self, vmid: int, source: pathlib.Path, relative: str, mode: int) -> None:
        del vmid, source, mode
        if relative not in self.bundle_items:
            raise ProvisioningError("BUNDLE_ITEM_CONFLICT", relative)

    def ensure_guest_secrets(self, vmid: int, sources) -> None:
        del vmid
        for allocation, source in sources.items():
            if not source.is_file():
                raise ProvisioningError("SECRET_MISSING", allocation)
            self.bundle_items.add(f"{allocation}/application-password")
        self.actions.append("guest secrets rehydrated")

    def apply_guest_phase(self, vmid: int, phase: str, *, item: str | None = None) -> str:
        del vmid
        self.actions.append(f"guest {phase}:{item}")
        self.guest_completed.add((phase, item))
        return f"PHASE_COMPLETED {phase} {item}"

    def verify_guest_phase(self, vmid: int, phase: str, *, item: str | None = None) -> None:
        del vmid
        if item is not None and (phase, item) not in self.guest_completed:
            raise ProvisioningError("GUEST_STATE_CONFLICT", f"{phase}:{item}")

    def verify_phase(self, phase: str, marker, plan) -> None:
        del marker, plan
        if phase == "lxc_created" and self.status not in {"stopped", "running"}:
            raise ProvisioningError("LXC_STATE_CONFLICT", self.status)
        if phase not in {"planned", "secret_directories_ready", "secrets_ready", "pki_ready", "lxc_created"} and self.status != "running":
            raise ProvisioningError("LXC_STATE_CONFLICT", self.status)

    def stream_backup(self, vmid: int, database_name: str, destination: pathlib.Path) -> None:
        del vmid
        self.actions.append(f"backup {database_name}")
        with destination.open("xb") as handle:
            handle.write(f"backup:{database_name}".encode())
        destination.chmod(0o600)

    def verify_backup(self, vmid: int, backup_path: pathlib.Path) -> None:
        del vmid
        if not backup_path.read_bytes().startswith(b"backup:"):
            raise ProvisioningError("BACKUP_FAILED", "invalid")

    def cleanup_guest_secrets(self, vmid: int) -> None:
        del vmid
        self.cleanup_calls += 1
        self.bundle_items -= {f"{item}/application-password" for item in ALLOCATION_IDS}


def make_environment(root: pathlib.Path):
    filesystem = SecureFilesystem(root)
    provider = root / "secrets/database-service/providers/postgresql-main"
    provider.mkdir(parents=True, mode=0o700)
    for directory in (
        root / "secrets",
        root / "secrets/database-service",
        root / "secrets/database-service/providers",
        provider,
    ):
        directory.chmod(0o700)
    config = provider / "deployment.toml"
    config.write_text("schema_version = 1\n", encoding="utf-8")
    config.chmod(0o600)
    backup = root / "backup"
    backup.mkdir(mode=0o700)
    artifacts_dir = root / "artifacts"
    artifacts_dir.mkdir()
    artifacts = {}
    for name in ("planner", "deployer", "guest", "pki_policy", "version_matrix"):
        path = artifacts_dir / name
        path.write_text(name, encoding="utf-8")
        artifacts[name] = path
    allocations = []
    for allocation in ALLOCATION_IDS:
        allocations.append({
            "allocation_id": allocation,
            "database_name": allocation,
            "application_identity": allocation,
            "owner_identity": f"{allocation}_owner",
            "allowed_client_cidrs": [f"10.20.{len(allocations) + 1}.0/24"],
        })
    plan = {
        "schema_version": 1,
        "plan_type": "postgresql-main-deployment",
        "repository_commit": COMMIT,
        "configuration_path": str(CONFIG_PATH),
        "configuration_sha256": sha256_path(config),
        "version_matrix_sha256": sha256_path(artifacts["version_matrix"]),
        "plan_inputs": {
            "provider": {"provider_instance_id": "postgresql-main", "fqdn": "postgresql-main.example.internal"},
            "lxc": {
                "ipv4_cidr": "10.20.0.10/24", "gateway": "10.20.0.1",
                "cores": 4, "memory_mib": 8192, "swap_mib": 2048,
                "disk_gib": 100, "dns_servers": ["10.20.0.1"],
            },
            "backup": {"host_root": str(backup)},
            "allocations": allocations,
        },
        "proxmox_observations": {
            "vmid": 250, "storage": "local-lvm", "bridge": "vmbr0",
            "template": "local:vztmpl/ubuntu-26.04-standard_amd64.tar.zst",
        },
        "secret_metadata_observations": [],
        "backup_observations": {},
        "warnings": [],
        "blockers": [],
        "planned_mutations": ["bounded provisioning"],
        "excluded_scope": ["rollback"],
        "plan_status": "PLAN_READY",
    }
    planner = shared_plan.planner_module()
    plan["plan_sha256"] = planner.calculate_plan_sha256(plan)
    report = types.SimpleNamespace(machine_plan=plan, blockers=[])
    store = MarkerStore(filesystem, clock=lambda: NOW)
    backend = FakeBackend()
    pki = FakePki(filesystem)
    return filesystem, backend, store, pki, artifacts, report


def secret_values(filesystem: SecureFilesystem) -> list[bytes]:
    return [filesystem.read_bytes(PASSWORD_PATHS[item]) for item in ALLOCATION_IDS]
