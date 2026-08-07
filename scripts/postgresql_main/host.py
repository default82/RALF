"""Host-side apply and resume orchestration for postgresql-main."""

from __future__ import annotations

import contextlib
import copy
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import secrets
import stat
import subprocess
import tempfile
import uuid
from collections.abc import Callable, Mapping, Sequence

from . import plan as shared_plan
from .filesystem import SecureFilesystem
from .marker import MARKER_PATH, PLAN_PATH, MarkerStore, new_marker
from .models import (
    ALLOCATION_IDS,
    MULTI_ITEM_PHASES,
    PHASES,
    ProvisioningError,
    ResumePlan,
    canonical_json,
    canonical_sha256,
)
from .pki import PkiManager


LOCK_PATH = pathlib.Path("/run/lock/ralf-postgresql-main.lock")
CONFIG_PATH = pathlib.Path(
    "/secrets/database-service/providers/postgresql-main/deployment.toml"
)
SECRET_DIRECTORIES = (
    pathlib.Path("/secrets/database-service/providers/postgresql-main/pki"),
    pathlib.Path("/secrets/database-service/allocations"),
    *(pathlib.Path("/secrets/database-service/allocations") / item for item in ALLOCATION_IDS),
)
CONFIG_PARENT_DIRECTORIES = tuple(
    pathlib.Path(value) for value in (
        "/secrets",
        "/secrets/database-service",
        "/secrets/database-service/providers",
        "/secrets/database-service/providers/postgresql-main",
    )
)
PASSWORD_PATHS = {
    item: pathlib.Path(f"/secrets/database-service/allocations/{item}/application-password")
    for item in ALLOCATION_IDS
}
GUEST_ROOT = pathlib.PurePosixPath("/run/ralf-database-provision")
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
ARTIFACT_PATHS = {
    "planner": REPO_ROOT / "scripts/postgresql-main-plan.py",
    "deployer": REPO_ROOT / "scripts/postgresql-main-deploy.py",
    # The transferred guest artifact must be executable without the repository
    # package being present in the new container.
    "guest": REPO_ROOT / "scripts/postgresql_main/guest.py",
    "pki_policy": REPO_ROOT / "deploy/postgresql/pki-policy.toml",
    "version_matrix": REPO_ROOT / "deploy/postgresql/version-matrix.toml",
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_path(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(65_536):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_hashes(paths: Mapping[str, pathlib.Path] = ARTIFACT_PATHS) -> dict[str, str]:
    result: dict[str, str] = {}
    for name, path in paths.items():
        if not path.is_file() or path.is_symlink():
            raise ProvisioningError("ARTIFACT_MISSING", f"Artefakt fehlt: {name}")
        result[name] = sha256_path(path)
    return result


def validate_hash(value: str, *, code: str) -> str:
    normalized = value.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        raise ProvisioningError(code, "SHA-256 muss 64 Hex-Zeichen besitzen")
    return normalized


def ensure_root_directory(parent: pathlib.Path, name: str) -> pathlib.Path:
    """Create one root-owned 0700 child without following a child symlink."""
    if not re.fullmatch(r"[a-z0-9-]+", name):
        raise ProvisioningError("BACKUP_PATH_CONFLICT", name)
    parent_info = parent.lstat()
    if parent.is_symlink() or not stat.S_ISDIR(parent_info.st_mode):
        raise ProvisioningError("BACKUP_PATH_CONFLICT", str(parent))
    child = parent / name
    parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        try:
            child_info = child.lstat()
        except FileNotFoundError:
            os.mkdir(name, mode=0o700, dir_fd=parent_fd)
            os.chown(name, 0, 0, dir_fd=parent_fd, follow_symlinks=False)
            os.fsync(parent_fd)
            child_info = child.lstat()
    finally:
        os.close(parent_fd)
    if (
        child.is_symlink()
        or not stat.S_ISDIR(child_info.st_mode)
        or stat.S_IMODE(child_info.st_mode) != 0o700
        or child_info.st_uid != 0
        or child_info.st_gid != 0
    ):
        raise ProvisioningError("BACKUP_PATH_CONFLICT", str(child))
    return child


def build_pct_create_arguments(plan: Mapping[str, object]) -> list[str]:
    proxmox = plan["proxmox_observations"]
    inputs = plan["plan_inputs"]
    lxc = inputs["lxc"]
    vmid = int(proxmox["vmid"])
    storage = str(proxmox["storage"])
    bridge = str(proxmox["bridge"])
    template = str(proxmox["template"])
    nameserver = " ".join(str(item) for item in lxc["dns_servers"])
    net0 = ",".join((
        "name=eth0",
        f"bridge={bridge}",
        f"ip={lxc['ipv4_cidr']}",
        f"gw={lxc['gateway']}",
        "firewall=1",
    ))
    return [
        "pct", "create", str(vmid), template,
        "--hostname", "postgresql-main",
        "--arch", "amd64",
        "--ostype", "ubuntu",
        "--unprivileged", "1",
        "--features", "nesting=1",
        "--cores", str(lxc["cores"]),
        "--memory", str(lxc["memory_mib"]),
        "--swap", str(lxc["swap_mib"]),
        "--rootfs", f"{storage}:{lxc['disk_gib']}",
        "--net0", net0,
        "--nameserver", nameserver,
        "--onboot", "1",
        "--start", "0",
    ]


class HostBackend:
    """Production backend with bounded fixed-argument subprocess operations."""

    def __init__(self, executor: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run) -> None:
        self.executor = executor

    def _run(self, arguments: Sequence[str], *, mutating: bool, input_data: bytes | None = None) -> str:
        args = list(arguments)
        if not self._allowed(args, mutating=mutating):
            raise ProvisioningError("HOST_COMMAND_BLOCKED", "Nicht erlaubte Hostoperation")
        try:
            result = self.executor(
                args,
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=input_data is None,
                timeout=300 if mutating else 15,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ProvisioningError("HOST_COMMAND_FAILED", f"Hostoperation fehlgeschlagen: {args[0]}") from exc
        if result.returncode != 0:
            raise ProvisioningError("HOST_COMMAND_FAILED", f"Hostoperation fehlgeschlagen: {args[0]}")
        output = result.stdout
        if isinstance(output, bytes):
            return output.decode("utf-8", "replace")
        return output[:131_072]

    @staticmethod
    def _allowed(args: Sequence[str], *, mutating: bool) -> bool:
        if not args:
            return False
        if not mutating:
            if args[:3] == ["git", "-C", str(REPO_ROOT)] and args[3:] in (["status", "--porcelain"], ["rev-parse", "HEAD"]):
                return True
            if args == ["pct", "list"]:
                return True
            if len(args) == 3 and args[:2] in (["pct", "status"], ["pct", "config"], ["pct", "pending"]):
                return args[2].isdigit()
            return False
        if args[:2] == ["pct", "create"] and len(args) >= 4:
            return args[2].isdigit()
        if args[:2] == ["pct", "start"] and len(args) == 3:
            return args[2].isdigit()
        if args[:2] == ["pct", "push"] and len(args) >= 5:
            return args[2].isdigit()
        if args[:2] == ["pct", "exec"] and len(args) >= 6:
            return args[2].isdigit() and args[3] == "--"
        return False

    def repository_commit(self) -> str:
        return self._run(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"], mutating=False).strip()

    def repository_clean(self) -> bool:
        output = self._run(
            ["git", "-C", str(REPO_ROOT), "status", "--porcelain"], mutating=False
        )
        return not output.strip()

    def create_lxc(self, plan: Mapping[str, object]) -> None:
        self._run(build_pct_create_arguments(plan), mutating=True)

    def start_lxc(self, vmid: int) -> None:
        self._run(["pct", "start", str(vmid)], mutating=True)

    def verify_lxc(self, plan: Mapping[str, object], *, expected_status: str) -> None:
        vmid = int(plan["proxmox_observations"]["vmid"])
        status_text = self._run(["pct", "status", str(vmid)], mutating=False)
        if f"status: {expected_status}" not in status_text:
            raise ProvisioningError("LXC_STATE_CONFLICT", "Containerstatus stimmt nicht")
        config = self._run(["pct", "config", str(vmid)], mutating=False)
        pending = self._run(["pct", "pending", str(vmid)], mutating=False)
        expected = build_pct_create_arguments(plan)
        parsed = {
            key.strip(): value.strip()
            for line in config.splitlines()
            if ":" in line
            for key, value in (line.split(":", 1),)
        }
        required = {
            "hostname": "postgresql-main",
            "arch": "amd64",
            "ostype": "ubuntu",
            "unprivileged": "1",
            "features": "nesting=1",
            "cores": expected[expected.index("--cores") + 1],
            "memory": expected[expected.index("--memory") + 1],
            "swap": expected[expected.index("--swap") + 1],
            "net0": expected[expected.index("--net0") + 1],
            "nameserver": expected[expected.index("--nameserver") + 1],
            "onboot": "1",
        }
        if any(parsed.get(key) != value for key, value in required.items()):
            raise ProvisioningError("LXC_CONFIG_CONFLICT", "Containerkonfiguration weicht vom Plan ab")
        rootfs_lines = [line for line in config.splitlines() if line.startswith("rootfs: ")]
        storage = str(plan["proxmox_observations"]["storage"])
        disk_gib = int(plan["plan_inputs"]["lxc"]["disk_gib"])
        if len(rootfs_lines) != 1 or storage not in rootfs_lines[0] or f"size={disk_gib}G" not in rootfs_lines[0]:
            raise ProvisioningError("LXC_CONFIG_CONFLICT", "Root-Disk weicht vom Plan ab")
        forbidden_keys = re.compile(r"^(?:mp|dev|usb|hostpci)\d+$")
        if any(
            forbidden_keys.fullmatch(key) or key in {"hookscript", "lxc.mount.entry"}
            for key in parsed
        ):
            raise ProvisioningError("LXC_CONFIG_CONFLICT", "Unerlaubte LXC-Erweiterung")
        if any(line.strip() for line in pending.splitlines()[1:]):
            raise ProvisioningError("LXC_PENDING_CONFLICT", "Pending-Konfiguration vorhanden")

    def verify_started_guest(self, plan: Mapping[str, object]) -> None:
        vmid = str(plan["proxmox_observations"]["vmid"])
        lxc = plan["plan_inputs"]["lxc"]
        provider_ip = str(lxc["ipv4_cidr"]).split("/", 1)[0]
        release = self._run(["pct", "exec", vmid, "--", "/usr/bin/cat", "/etc/os-release"], mutating=True)
        if "ID=ubuntu" not in release or 'VERSION_ID="26.04"' not in release:
            raise ProvisioningError("GUEST_OS_CONFLICT", "Ubuntu 26.04 fehlt")
        architecture = self._run(["pct", "exec", vmid, "--", "/usr/bin/uname", "-m"], mutating=True).strip()
        if architecture not in {"x86_64", "amd64"}:
            raise ProvisioningError("GUEST_ARCH_CONFLICT", architecture)
        hostname = self._run(
            ["pct", "exec", vmid, "--", "/usr/bin/hostname"], mutating=True
        ).strip()
        if hostname != "postgresql-main":
            raise ProvisioningError("GUEST_HOSTNAME_CONFLICT", hostname)
        self._run(["pct", "exec", vmid, "--", "/usr/bin/systemctl", "is-system-running"], mutating=True)
        failed = self._run(["pct", "exec", vmid, "--", "/usr/bin/systemctl", "--failed", "--no-legend"], mutating=True)
        if failed.strip():
            raise ProvisioningError("GUEST_UNITS_FAILED", "Gast besitzt fehlgeschlagene Units")
        addresses = self._run(["pct", "exec", vmid, "--", "/usr/sbin/ip", "-4", "address", "show"], mutating=True)
        routes = self._run(["pct", "exec", vmid, "--", "/usr/sbin/ip", "-4", "route", "show"], mutating=True)
        if provider_ip not in addresses or f"default via {lxc['gateway']}" not in routes:
            raise ProvisioningError("GUEST_NETWORK_CONFLICT", "Adresse oder Default-Route weicht ab")
        resolv = self._run(
            ["pct", "exec", vmid, "--", "/usr/bin/cat", "/etc/resolv.conf"],
            mutating=True,
        )
        if any(f"nameserver {server}" not in resolv for server in lxc["dns_servers"]):
            raise ProvisioningError("GUEST_DNS_CONFLICT", "DNS-Konfiguration weicht ab")
        disk = self._run(
            ["pct", "exec", vmid, "--", "/usr/bin/df", "-Pk", "/"], mutating=True
        )
        lines = [line for line in disk.splitlines() if line.strip()]
        fields = lines[-1].split() if lines else []
        if len(fields) < 4 or not fields[3].isdigit() or int(fields[3]) < 2_097_152:
            raise ProvisioningError("GUEST_STORAGE_LOW", "Weniger als 2 GiB frei")
        https = self._run(
            [
                "pct", "exec", vmid, "--", "/usr/bin/python3", "-c",
                "import urllib.request; print(urllib.request.urlopen('https://archive.ubuntu.com/ubuntu/', timeout=10).status)",
            ],
            mutating=True,
        ).strip()
        if https != "200":
            raise ProvisioningError("UBUNTU_HTTPS_UNAVAILABLE", "Ubuntu-Paketquelle nicht per HTTPS erreichbar")

    def verify_guest_base(self, vmid: int, plan: Mapping[str, object]) -> None:
        arguments = [
            "pct", "exec", str(vmid), "--", "python3", str(GUEST_ROOT / "postgresql-main-guest.py"),
            "classify", "--bundle", str(GUEST_ROOT),
        ]
        output = self._run(arguments, mutating=True).strip()
        if not re.fullmatch(r"RALF_POSTGRESQL_GUEST_STATE_V1=[a-z0-9_]+", output):
            raise ProvisioningError("GUEST_CLASSIFICATION_INVALID", "Gastklassifikation ungültig")

    def initialize_guest_bundle(self, vmid: int) -> None:
        self._run([
            "pct", "exec", str(vmid), "--", "/usr/bin/install", "-d", "-o", "root", "-g", "root", "-m", "0700", str(GUEST_ROOT),
        ], mutating=True)

    def push_bundle_item(self, vmid: int, source: pathlib.Path, relative: str, mode: int) -> None:
        destination = str(GUEST_ROOT / relative)
        parent = str(pathlib.PurePosixPath(destination).parent)
        self._run([
            "pct", "exec", str(vmid), "--", "/usr/bin/install", "-d", "-o", "root", "-g", "root", "-m", "0700", parent,
        ], mutating=True)
        self._run([
            "pct", "push", str(vmid), str(source), destination,
            "--perms", f"{mode:04o}", "--user", "0", "--group", "0",
        ], mutating=True)

    def verify_guest_bundle_item(
        self, vmid: int, source: pathlib.Path, relative: str, mode: int
    ) -> None:
        destination = str(GUEST_ROOT / relative)
        metadata = self._run([
            "pct", "exec", str(vmid), "--", "/usr/bin/stat",
            "--format=%F|%a|%u|%g|%s", destination,
        ], mutating=True).strip()
        expected_size = source.stat().st_size
        if metadata != f"regular file|{mode:o}|0|0|{expected_size}":
            raise ProvisioningError("BUNDLE_ITEM_CONFLICT", relative)
        if not relative.endswith("application-password"):
            remote_hash = self._run([
                "pct", "exec", str(vmid), "--", "/usr/bin/sha256sum", destination,
            ], mutating=True).split()[0]
            if remote_hash != sha256_path(source):
                raise ProvisioningError("BUNDLE_ITEM_CONFLICT", relative)

    def verify_guest_bundle(self, vmid: int) -> None:
        self.verify_guest_base(vmid, {})

    def ensure_guest_secrets(self, vmid: int, sources: Mapping[str, pathlib.Path]) -> None:
        """Rehydrate only ephemeral password copies removed by failure cleanup."""
        for allocation in ALLOCATION_IDS:
            self.push_bundle_item(
                vmid,
                sources[allocation],
                f"{allocation}/application-password",
                0o600,
            )
            self.verify_guest_bundle_item(
                vmid,
                sources[allocation],
                f"{allocation}/application-password",
                0o600,
            )

    def apply_guest_phase(
        self, vmid: int, phase: str, *, item: str | None = None
    ) -> str:
        arguments = [
            "pct", "exec", str(vmid), "--", "python3",
            str(GUEST_ROOT / "postgresql-main-guest.py"), "apply-phase",
            "--phase", phase, "--bundle", str(GUEST_ROOT),
        ]
        if item is not None:
            arguments.extend(["--item", item])
        return self._run(arguments, mutating=True).strip()

    def verify_guest_phase(self, vmid: int, phase: str, *, item: str | None = None) -> None:
        arguments = [
            "pct", "exec", str(vmid), "--", "python3",
            str(GUEST_ROOT / "postgresql-main-guest.py"), "verify-phase",
            "--phase", phase, "--bundle", str(GUEST_ROOT),
        ]
        if item is not None:
            arguments.extend(["--item", item])
        self._run(arguments, mutating=True)

    def cleanup_guest_secrets(self, vmid: int) -> None:
        self._run([
            "pct", "exec", str(vmid), "--", "python3",
            str(GUEST_ROOT / "postgresql-main-guest.py"), "cleanup",
            "--bundle", str(GUEST_ROOT),
        ], mutating=True)

    def stream_backup(self, vmid: int, database_name: str, destination: pathlib.Path) -> None:
        arguments = [
            "pct", "exec", str(vmid), "--", "runuser", "-u", "postgres", "--",
            "pg_dump", "--format=custom", f"--dbname={database_name}",
        ]
        if not self._allowed(arguments, mutating=True):
            raise ProvisioningError("HOST_COMMAND_BLOCKED", "Backupstream blockiert")
        with destination.open("xb") as output:
            os.fchmod(output.fileno(), 0o600)
            process = subprocess.Popen(arguments, stdout=output, stderr=subprocess.PIPE)
            try:
                _stderr = process.communicate(timeout=300)[1]
            except subprocess.TimeoutExpired as exc:
                process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
                raise ProvisioningError("BACKUP_TIMEOUT", "pg_dump Zeitlimit überschritten") from exc
            if process.returncode != 0:
                raise ProvisioningError("BACKUP_FAILED", "pg_dump fehlgeschlagen")
            output.flush()
            os.fsync(output.fileno())

    def verify_backup(self, vmid: int, backup_path: pathlib.Path) -> None:
        arguments = [
            "pct", "exec", str(vmid), "--", "runuser", "-u", "postgres", "--",
            "pg_restore", "--list", "-",
        ]
        with backup_path.open("rb") as source:
            self._run(arguments, mutating=True, input_data=source.read())

    def verify_phase(self, phase: str, marker: Mapping[str, object], plan: Mapping[str, object]) -> None:
        vmid = int(marker["vmid"])
        if phase == "lxc_created":
            self.verify_lxc(plan, expected_status="stopped")
        elif phase in {"lxc_started", "guest_bundle_ready", "guest_os_ready", "postgresql_installed", "postgresql_configured", "allocations_created", "readiness_verified", "backups_verified", "completed"}:
            self.verify_lxc(plan, expected_status="running")
        if phase in {"guest_os_ready", "postgresql_installed", "postgresql_configured", "allocations_created", "readiness_verified"}:
            self.verify_guest_phase(vmid, phase)


class Provisioner:
    def __init__(
        self,
        *,
        filesystem: SecureFilesystem,
        backend: HostBackend,
        marker_store: MarkerStore,
        pki: PkiManager,
        plan_factory: Callable[[pathlib.Path], object] = shared_plan.create_plan_report,
        token_source: Callable[[], str] = lambda: secrets.token_urlsafe(48),
        operation_id_source: Callable[[], str] = lambda: str(uuid.uuid4()),
        clock: Callable[[], str] = utc_now,
        fault: Callable[[str], None] = lambda _point: None,
        repository_root: pathlib.Path = REPO_ROOT,
        artifact_paths: Mapping[str, pathlib.Path] = ARTIFACT_PATHS,
    ) -> None:
        self.fs = filesystem
        self.backend = backend
        self.store = marker_store
        self.pki = pki
        self.plan_factory = plan_factory
        self.token_source = token_source
        self.operation_id_source = operation_id_source
        self.clock = clock
        self.fault = fault
        self.repository_root = repository_root
        self.artifact_paths = artifact_paths

    def _validate_repository(self, expected_commit: str) -> None:
        if self.backend.repository_commit() != expected_commit or not self.backend.repository_clean():
            raise ProvisioningError("REPOSITORY_STATE_CONFLICT", "Repository ist nicht exakt planidentisch und sauber")
        for path in self.artifact_paths.values():
            if not path.is_file() or path.is_symlink():
                raise ProvisioningError("ARTIFACT_MISSING", str(path))

    def _validate_config_metadata(self, config_path: pathlib.Path) -> None:
        if config_path != CONFIG_PATH:
            raise ProvisioningError("CONFIG_PATH_INVALID", str(config_path))
        for directory in CONFIG_PARENT_DIRECTORIES:
            self.fs.validate(directory, kind="directory", mode=0o700)
        self.fs.validate(CONFIG_PATH, kind="file", mode=0o600)

    def _preflight(self, config_path: pathlib.Path, confirmed_hash: str):
        self._validate_config_metadata(config_path)
        report = self.plan_factory(config_path)
        if report.machine_plan is None:
            raise ProvisioningError("PLAN_INVALID", "Maschinenplan fehlt")
        plan = report.machine_plan
        if plan["plan_status"] != "PLAN_READY" or report.blockers:
            raise ProvisioningError("PLAN_BLOCKED", "Plan enthält Blocker")
        actual_hash = str(plan["plan_sha256"])
        if actual_hash != validate_hash(confirmed_hash, code="PLAN_HASH_INVALID"):
            raise ProvisioningError("APPLY_BLOCKED_PLAN_CHANGED", "Plan-Hash stimmt nicht")
        self._validate_repository(str(plan["repository_commit"]))
        if self.store.exists() or self.fs.path(PLAN_PATH).exists():
            raise ProvisioningError("APPLY_REQUIRES_RESUME", "Provisionierungsmarker oder Planevidenz existiert")
        for path in (
            *(item.parent for item in PASSWORD_PATHS.values()),
            *PASSWORD_PATHS.values(),
            self.pki.root,
        ):
            if self.fs.path(path).exists():
                raise ProvisioningError("TARGET_STATE_CONFLICT", f"Zielartefakt existiert: {path}")
        return report

    def apply(self, config_path: pathlib.Path, confirmed_hash: str) -> dict[str, object]:
        if os.geteuid() != 0:
            raise ProvisioningError("ROOT_REQUIRED", "Apply benötigt UID 0")
        # Reject stale or blocked confirmations without even publishing the lock inode.
        self._preflight(config_path, confirmed_hash)
        with self.fs.exclusive_lock(LOCK_PATH):
            # Repeat under the process lock; this is the mutation-authorizing preflight.
            report = self._preflight(config_path, confirmed_hash)
            assert report.machine_plan is not None
            plan = copy.deepcopy(report.machine_plan)
            artifacts = artifact_hashes(self.artifact_paths)
            operation_id = self.operation_id_source()
            marker = new_marker(
                operation_id=operation_id,
                repository_commit=str(plan["repository_commit"]),
                plan=plan,
                artifact_hashes=artifacts,
                now=self.clock(),
            )
            self.store.create(marker, plan)
            self.fault("after_marker")
            marker = self.store.load()
            marker = self.store.complete(marker, "planned")
            return self._continue(marker, plan)

    def resume(self, resume_plan: ResumePlan, confirmed_hash: str) -> dict[str, object]:
        if os.geteuid() != 0:
            raise ProvisioningError("ROOT_REQUIRED", "Resume-Apply benötigt UID 0")
        if resume_plan.status != "RESUME_READY" or resume_plan.sha256 != validate_hash(confirmed_hash, code="RESUME_HASH_INVALID"):
            raise ProvisioningError("APPLY_BLOCKED_PLAN_CHANGED", "Resume-Hash stimmt nicht")
        with self.fs.exclusive_lock(LOCK_PATH):
            current = build_resume_plan(
                filesystem=self.fs,
                backend=self.backend,
                marker_store=self.store,
                pki=self.pki,
                artifact_paths=self.artifact_paths,
                generated_at=self.clock(),
            )
            if current.status != "RESUME_READY" or current.sha256 != resume_plan.sha256:
                raise ProvisioningError("APPLY_BLOCKED_PLAN_CHANGED", "Resume-Plan hat sich geändert")
            marker = self.store.load()
            original_plan = self.store.load_plan()
            return self._continue(marker, original_plan)

    def _continue(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        vmid = int(marker["vmid"])
        try:
            while marker["phase"] != "completed":
                phase = PHASES[len(marker["completed_phases"])]
                if phase == "planned":
                    marker = self.store.complete(marker, "planned")
                elif phase == "secret_directories_ready":
                    marker = self._directories(marker)
                elif phase == "secrets_ready":
                    marker = self._secrets(marker)
                elif phase == "pki_ready":
                    marker = self._pki(marker, plan)
                elif phase == "lxc_created":
                    marker = self._lxc_create(marker, plan)
                elif phase == "lxc_started":
                    marker = self._lxc_start(marker, plan)
                elif phase == "guest_bundle_ready":
                    marker = self._bundle(marker, plan)
                elif phase in {"guest_os_ready", "postgresql_installed", "postgresql_configured", "allocations_created", "readiness_verified"}:
                    marker = self._guest_items(marker, plan, phase)
                elif phase == "backups_verified":
                    marker = self._backups(marker, plan)
                elif phase == "completed":
                    marker = self._complete(marker, plan)
                else:
                    raise ProvisioningError("PHASE_UNKNOWN", phase)
            return marker
        except Exception as raw_exc:
            exc = raw_exc if isinstance(raw_exc, ProvisioningError) else ProvisioningError(
                "PROVISIONING_INTERNAL_ERROR", type(raw_exc).__name__
            )
            with contextlib.suppress(Exception):
                marker = self.store.record_error(self.store.load(), exc.code, exc.message)
            cleanup_error: ProvisioningError | None = None
            if marker.get("phase") in PHASES[5:] and exc.code != "SECURITY_CLEANUP_FAILED":
                try:
                    self.backend.cleanup_guest_secrets(vmid)
                except ProvisioningError as cleanup_exc:
                    cleanup_error = cleanup_exc
                    with contextlib.suppress(Exception):
                        marker = self.store.record_error(
                            self.store.load(),
                            exc.code,
                            f"{exc.message}; SECURITY_CLEANUP_FAILED",
                        )
            if cleanup_error is not None:
                raise ProvisioningError(
                    exc.code,
                    f"{exc.message}; SECURITY_CLEANUP_FAILED: {cleanup_error.message}",
                ) from raw_exc
            if isinstance(raw_exc, ProvisioningError):
                raise
            raise exc from raw_exc

    def _directories(self, marker: dict[str, object]) -> dict[str, object]:
        completed = list(marker["phase_progress"].get("secret_directories_ready", []))
        labels = MULTI_ITEM_PHASES["secret_directories_ready"]
        for label, path in list(zip(labels, SECRET_DIRECTORIES))[len(completed):]:
            marker = self.store.begin(marker, "secret_directories_ready", label)
            self.fs.ensure_directory(path)
            self.fault(f"after_directory:{label}")
            marker = self.store.progress(marker, "secret_directories_ready", label)
        return self.store.complete(marker, "secret_directories_ready")

    def _secrets(self, marker: dict[str, object]) -> dict[str, object]:
        progress = list(marker["phase_progress"].get("secrets_ready", []))
        for allocation in ALLOCATION_IDS[len(progress):]:
            if marker.get("in_progress_phase") == "secrets_ready" and marker.get("in_progress_item") == allocation:
                self._validate_secret(allocation)
                marker = self.store.progress(marker, "secrets_ready", allocation)
                continue
            marker = self.store.begin(marker, "secrets_ready", allocation)
            value = self.token_source()
            if len(value) < 64 or not value.isascii() or any(ch.isspace() or ord(ch) < 33 for ch in value):
                raise ProvisioningError("SECRET_GENERATOR_INVALID", "Kennwortgenerator verletzt Vertrag")
            self.fs.exclusive_bytes(PASSWORD_PATHS[allocation], value.encode("ascii"), mode=0o600)
            self.fault(f"after_secret:{allocation}")
            self._validate_secret(allocation)
            marker = self.store.progress(marker, "secrets_ready", allocation)
        return self.store.complete(marker, "secrets_ready")

    def _validate_secret(self, allocation: str) -> None:
        path = self.fs.path(PASSWORD_PATHS[allocation])
        self.fs.validate(PASSWORD_PATHS[allocation], kind="file", mode=0o600, require_nonempty=True)
        data = self.fs.read_bytes(PASSWORD_PATHS[allocation], maximum=4096)
        if not data.isascii() or any(byte < 33 or byte == 127 for byte in data):
            raise ProvisioningError("SECRET_CONTENT_INVALID", f"Secretmetadaten ungültig: {allocation}")

    def _pki(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        marker = self.store.begin(marker, "pki_ready")
        provider = plan["plan_inputs"]["provider"]
        lxc = plan["plan_inputs"]["lxc"]
        provider_ip = str(lxc["ipv4_cidr"]).split("/", 1)[0]
        fingerprints = self.pki.generate(str(provider["fqdn"]), provider_ip)
        marker["public_certificate_fingerprints"] = fingerprints
        marker = self.store.save(marker)
        return self.store.complete(marker, "pki_ready")

    def _lxc_create(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        if marker.get("in_progress_phase") == "lxc_created":
            self.backend.verify_lxc(plan, expected_status="stopped")
            return self.store.complete(marker, "lxc_created")
        marker = self.store.begin(marker, "lxc_created")
        self.backend.create_lxc(plan)
        self.fault("after_pct_create")
        self.backend.verify_lxc(plan, expected_status="stopped")
        return self.store.complete(marker, "lxc_created")

    def _lxc_start(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        if marker.get("in_progress_phase") == "lxc_started":
            self.backend.verify_lxc(plan, expected_status="running")
            self.backend.verify_started_guest(plan)
            return self.store.complete(marker, "lxc_started")
        marker = self.store.begin(marker, "lxc_started")
        self.backend.start_lxc(int(marker["vmid"]))
        self.fault("after_pct_start")
        self.backend.verify_lxc(plan, expected_status="running")
        self.backend.verify_started_guest(plan)
        return self.store.complete(marker, "lxc_started")

    def _guest_plan(self, plan: Mapping[str, object]) -> dict[str, object]:
        return {
            "schema_version": 1,
            "provider_instance_id": "postgresql-main",
            "postgresql_major": 18,
            "fqdn": plan["plan_inputs"]["provider"]["fqdn"],
            "hostname": "postgresql-main",
            "provider_ip": str(plan["plan_inputs"]["lxc"]["ipv4_cidr"]).split("/", 1)[0],
            "gateway": plan["plan_inputs"]["lxc"]["gateway"],
            "dns_servers": plan["plan_inputs"]["lxc"]["dns_servers"],
            "allocations": plan["plan_inputs"]["allocations"],
        }

    def _bundle(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        vmid = int(marker["vmid"])
        self.backend.initialize_guest_bundle(vmid)
        guest_plan = self._guest_plan(plan)
        with tempfile.TemporaryDirectory(prefix="ralf-pg-bundle-") as raw:
            root = pathlib.Path(raw)
            os.chmod(root, 0o700)
            guest_plan_path = root / "guest-plan.json"
            guest_plan_path.write_bytes(canonical_json(guest_plan) + b"\n")
            os.chmod(guest_plan_path, 0o600)
            manifest = {
                "schema_version": 1,
                "artifacts": {
                    "postgresql-main-guest.py": sha256_path(self.artifact_paths["guest"]),
                    "guest-plan.json": sha256_path(guest_plan_path),
                    "ca.crt": sha256_path(self.fs.path(self.pki.root / "ca.crt")),
                    "server.crt": sha256_path(self.fs.path(self.pki.root / "server.crt")),
                },
            }
            manifest_path = root / "public-manifest.json"
            manifest_path.write_bytes(canonical_json(manifest) + b"\n")
            os.chmod(manifest_path, 0o600)
            sources = {
                "postgresql-main-guest.py": (self.artifact_paths["guest"], 0o644),
                "guest-plan.json": (guest_plan_path, 0o644),
                "public-manifest.json": (manifest_path, 0o644),
                "ca.crt": (self.fs.path(self.pki.root / "ca.crt"), 0o644),
                "server.crt": (self.fs.path(self.pki.root / "server.crt"), 0o644),
                "server.key": (self.fs.path(self.pki.root / "server.key"), 0o600),
                **{
                    f"{allocation}/application-password": (self.fs.path(PASSWORD_PATHS[allocation]), 0o600)
                    for allocation in ALLOCATION_IDS
                },
            }
            if marker.get("last_error"):
                self.backend.ensure_guest_secrets(
                    vmid,
                    {allocation: self.fs.path(PASSWORD_PATHS[allocation]) for allocation in ALLOCATION_IDS},
                )
            completed = list(marker["phase_progress"].get("guest_bundle_ready", []))
            for item in MULTI_ITEM_PHASES["guest_bundle_ready"][len(completed):]:
                source, mode = sources[item]
                if marker.get("in_progress_phase") == "guest_bundle_ready" and marker.get("in_progress_item") == item:
                    try:
                        self.backend.verify_guest_bundle_item(vmid, source, item, mode)
                    except ProvisioningError:
                        if not item.endswith("application-password"):
                            raise
                        # Error cleanup intentionally removed the ephemeral copy.
                        self.backend.push_bundle_item(vmid, source, item, mode)
                        self.backend.verify_guest_bundle_item(vmid, source, item, mode)
                    marker = self.store.progress(marker, "guest_bundle_ready", item)
                    continue
                marker = self.store.begin(marker, "guest_bundle_ready", item)
                self.backend.push_bundle_item(vmid, source, item, mode)
                self.fault(f"after_bundle:{item}")
                self.backend.verify_guest_bundle_item(vmid, source, item, mode)
                marker = self.store.progress(marker, "guest_bundle_ready", item)
        self.backend.verify_guest_bundle(vmid)
        return self.store.complete(marker, "guest_bundle_ready")

    def _guest_items(self, marker: dict[str, object], plan: Mapping[str, object], phase: str) -> dict[str, object]:
        if marker.get("last_error"):
            self.backend.ensure_guest_secrets(
                int(marker["vmid"]),
                {allocation: self.fs.path(PASSWORD_PATHS[allocation]) for allocation in ALLOCATION_IDS},
            )
        allowed = MULTI_ITEM_PHASES[phase]
        completed = list(marker["phase_progress"].get(phase, []))
        for item in allowed[len(completed):]:
            if marker.get("in_progress_phase") == phase and marker.get("in_progress_item") == item:
                self.backend.verify_guest_phase(int(marker["vmid"]), phase, item=item)
                marker = self.store.progress(marker, phase, item)
                continue
            marker = self.store.begin(marker, phase, item)
            result = self.backend.apply_guest_phase(int(marker["vmid"]), phase, item=item)
            if result == "PROVISIONING_PAUSED_REBOOT_REQUIRED":
                raise ProvisioningError(result, "Gast benötigt getrennt freigegebenen Neustart")
            self.fault(f"after_{phase}:{item}")
            self.backend.verify_guest_phase(int(marker["vmid"]), phase, item=item)
            marker = self.store.progress(marker, phase, item)
        if phase == "readiness_verified":
            marker["readiness_status"] = {
                "provider_status": "ready",
                "allocation_configuration": "verified",
                "consumer_connectivity": "pending",
                "allocation_readiness": "consumer_validation_pending",
            }
            marker = self.store.save(marker)
        return self.store.complete(marker, phase)

    def _backups(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        by_id = {item["allocation_id"]: item for item in plan["plan_inputs"]["allocations"]}
        configured_backup_root = pathlib.Path(str(plan["plan_inputs"]["backup"]["host_root"]))
        backup_root = ensure_root_directory(configured_backup_root, "postgresql-main")
        timestamp = self.clock().replace("-", "").replace(":", "")
        completed = list(marker["phase_progress"].get("backups_verified", []))
        for allocation in ALLOCATION_IDS[len(completed):]:
            if marker.get("in_progress_phase") == "backups_verified" and marker.get("in_progress_item") == allocation:
                evidence = marker["backup_artifacts"].get(allocation)
                if isinstance(evidence, dict):
                    existing = pathlib.Path(str(evidence["path"]))
                    if (
                        existing.is_symlink()
                        or not existing.is_file()
                        or stat.S_IMODE(existing.stat().st_mode) != 0o600
                        or existing.stat().st_uid != 0
                        or existing.stat().st_gid != 0
                        or existing.stat().st_size != evidence["size"]
                        or sha256_path(existing) != evidence["sha256"]
                    ):
                        raise ProvisioningError("RESUME_CONFLICT", f"Backup weicht ab: {allocation}")
                    marker = self.store.progress(marker, "backups_verified", allocation)
                    continue
            marker = self.store.begin(marker, "backups_verified", allocation)
            directory = ensure_root_directory(backup_root, allocation)
            filename = f"{timestamp}-{marker['operation_id']}.dump"
            final = directory / filename
            if final.exists():
                raise ProvisioningError("BACKUP_ALREADY_EXISTS", str(final))
            temporary = directory / f".{filename}.partial"
            try:
                self.backend.stream_backup(int(marker["vmid"]), str(by_id[allocation]["database_name"]), temporary)
                self.fault(f"after_backup_stream:{allocation}")
                self.backend.verify_backup(int(marker["vmid"]), temporary)
                digest = sha256_path(temporary)
                os.replace(temporary, final)
            finally:
                with contextlib.suppress(FileNotFoundError):
                    temporary.unlink()
            parent_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
            try:
                os.fsync(parent_fd)
            finally:
                os.close(parent_fd)
            marker["backup_artifacts"][allocation] = {
                "path": str(final), "sha256": digest, "size": final.stat().st_size,
            }
            marker = self.store.save(marker)
            self.fault(f"after_backup:{allocation}")
            marker = self.store.progress(marker, "backups_verified", allocation)
        return self.store.complete(marker, "backups_verified")

    def _complete(self, marker: dict[str, object], plan: Mapping[str, object]) -> dict[str, object]:
        marker = self.store.begin(marker, "completed")
        self.backend.cleanup_guest_secrets(int(marker["vmid"]))
        self.fault("before_completion")
        return self.store.complete(marker, "completed")


def build_resume_plan(
    *,
    filesystem: SecureFilesystem,
    backend: HostBackend,
    marker_store: MarkerStore,
    pki: PkiManager | None = None,
    artifact_paths: Mapping[str, pathlib.Path] = ARTIFACT_PATHS,
    generated_at: str | None = None,
) -> ResumePlan:
    conflicts: list[str] = []
    try:
        marker = marker_store.load()
        original_plan = marker_store.load_plan()
        planner = shared_plan.planner_module()
        if planner.calculate_plan_sha256(original_plan) != original_plan.get("plan_sha256"):
            conflicts.append("gespeicherter Plan-Hash stimmt nicht")
        if marker["plan_sha256"] != original_plan.get("plan_sha256"):
            conflicts.append("Marker und gespeicherter Plan unterscheiden sich")
        if backend.repository_commit() != marker["repository_commit"] or not backend.repository_clean():
            conflicts.append("Repositoryzustand stimmt nicht")
        current_artifacts = artifact_hashes(artifact_paths)
        if current_artifacts != marker["artifact_hashes"]:
            conflicts.append("Skripthashes stimmen nicht")
        config_path = filesystem.path(CONFIG_PATH)
        if sha256_path(config_path) != marker["configuration_sha256"]:
            conflicts.append("Konfigurationshash stimmt nicht")
        if sha256_path(artifact_paths["version_matrix"]) != marker["version_matrix_sha256"]:
            conflicts.append("Versionsmatrixhash stimmt nicht")
        for phase in marker["completed_phases"]:
            try:
                if phase == "secret_directories_ready":
                    for path in SECRET_DIRECTORIES:
                        filesystem.validate(path, kind="directory", mode=0o700)
                elif phase == "secrets_ready":
                    for path in PASSWORD_PATHS.values():
                        filesystem.validate(path, kind="file", mode=0o600, require_nonempty=True)
                elif phase == "pki_ready":
                    if pki is None:
                        conflicts.append("pki_ready: PKI_VERIFICATION_UNAVAILABLE")
                    else:
                        provider = original_plan["plan_inputs"]["provider"]
                        lxc = original_plan["plan_inputs"]["lxc"]
                        provider_ip = str(lxc["ipv4_cidr"]).split("/", 1)[0]
                        fingerprints = pki.verify(str(provider["fqdn"]), provider_ip)
                        if fingerprints != marker["public_certificate_fingerprints"]:
                            conflicts.append("pki_ready: PKI_FINGERPRINT_CONFLICT")
                elif phase not in {"planned"}:
                    backend.verify_phase(phase, marker, original_plan)
            except ProvisioningError as exc:
                conflicts.append(f"{phase}: {exc.code}")
        in_progress = marker.get("in_progress_phase")
        in_progress_item = marker.get("in_progress_item")
        try:
            if in_progress == "lxc_created":
                backend.verify_lxc(original_plan, expected_status="stopped")
            elif in_progress == "lxc_started":
                backend.verify_lxc(original_plan, expected_status="running")
                backend.verify_started_guest(original_plan)
            elif in_progress in {
                "guest_os_ready", "postgresql_installed", "postgresql_configured",
                "allocations_created", "readiness_verified",
            }:
                backend.verify_guest_phase(
                    int(marker["vmid"]), str(in_progress),
                    item=str(in_progress_item) if in_progress_item is not None else None,
                )
            elif in_progress == "secrets_ready" and in_progress_item is not None:
                secret_path = PASSWORD_PATHS[str(in_progress_item)]
                if filesystem.path(secret_path).exists():
                    filesystem.validate(secret_path, kind="file", mode=0o600, require_nonempty=True)
        except ProvisioningError as exc:
            conflicts.append(f"{in_progress}: {exc.code}")
        next_phase = PHASES[len(marker["completed_phases"])] if len(marker["completed_phases"]) < len(PHASES) else None
        next_item = None
        if next_phase in MULTI_ITEM_PHASES:
            done = marker["phase_progress"].get(next_phase, [])
            allowed = MULTI_ITEM_PHASES[next_phase]
            next_item = allowed[len(done)] if len(done) < len(allowed) else None
    except (ProvisioningError, OSError, KeyError, TypeError, ValueError) as exc:
        marker = {"operation_id": "unknown", "plan_sha256": "0" * 64, "phase": None, "completed_phases": []}
        next_phase = None
        next_item = None
        conflicts.append(exc.code if isinstance(exc, ProvisioningError) else "RESUME_STATE_INVALID")
    document: dict[str, object] = {
        "schema_version": 1,
        "plan_type": "postgresql-main-resume",
        "operation_id": marker["operation_id"],
        "provider_instance_id": "postgresql-main",
        "plan_sha256": marker["plan_sha256"],
        "repository_commit": marker.get("repository_commit"),
        "phase": marker.get("phase"),
        "completed_phases": marker.get("completed_phases", []),
        "phase_progress": marker.get("phase_progress", {}),
        "next_phase": next_phase,
        "next_item": next_item,
        "conflicts": sorted(set(conflicts)),
        "generated_at": generated_at or utc_now(),
        "resume_status": "RESUME_CONFLICT" if conflicts else "RESUME_READY",
    }
    document["resume_sha256"] = canonical_sha256(document, ("generated_at", "resume_sha256"))
    return ResumePlan(document)
