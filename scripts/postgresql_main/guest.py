"""Guest-side bounded Ubuntu and PostgreSQL provisioning phases."""

from __future__ import annotations

import argparse
import contextlib
import grp
import hashlib
import ipaddress
import json
import os
import pathlib
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Callable, Mapping, Sequence

try:
    from .models import ALLOCATION_IDS, ProvisioningError
except ImportError:
    # The host transfers this file as the single, standalone guest program.
    # Keep the fallback deliberately minimal so the exact same implementation
    # is importable in the repository and executable in the LXC bundle.
    ALLOCATION_IDS = ("gitea", "openbao", "semaphore", "nodered")

    class ProvisioningError(RuntimeError):
        """A bounded guest provisioning step cannot continue safely."""

        def __init__(self, code: str, message: str) -> None:
            super().__init__(message)
            self.code = code
            self.message = message


GUEST_PHASES = (
    "guest_os_ready",
    "postgresql_installed",
    "postgresql_configured",
    "allocations_created",
    "readiness_verified",
)
GUEST_ITEMS = (
    "apt_update", "full_upgrade", "validate", "packages", "tls", "settings",
    "hba", "start", "provider", *ALLOCATION_IDS,
)
BUNDLE_ROOT = pathlib.Path("/run/ralf-database-provision")
POSTGRESQL_ROOT = pathlib.Path("/etc/postgresql/18/main")
TLS_ROOT = POSTGRESQL_ROOT / "tls"
HBA_PATH = POSTGRESQL_ROOT / "pg_hba.conf"
POLICY_RC_PATH = pathlib.Path("/usr/sbin/policy-rc.d")


class GuestCommandRunner:
    def __init__(self, executor: Callable[..., subprocess.CompletedProcess[bytes]] = subprocess.run) -> None:
        self.executor = executor

    def run(
        self,
        arguments: Sequence[str],
        *,
        input_data: bytes | None = None,
        timeout: int = 300,
        allowed_returncodes: tuple[int, ...] = (0,),
    ) -> bytes:
        if not self._allowed(arguments):
            raise ProvisioningError("GUEST_COMMAND_BLOCKED", "Gastbefehl nicht erlaubt")
        try:
            result = self.executor(
                list(arguments), input=input_data, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=timeout, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ProvisioningError("GUEST_COMMAND_FAILED", f"Gastoperation fehlgeschlagen: {arguments[0]}") from exc
        if result.returncode not in allowed_returncodes:
            raise ProvisioningError("GUEST_COMMAND_FAILED", f"Gastoperation fehlgeschlagen: {arguments[0]}")
        return result.stdout[:262_144]

    @staticmethod
    def _allowed(arguments: Sequence[str]) -> bool:
        if not arguments:
            return False
        command = arguments[0]
        return command in {
            "apt-get", "apt-cache", "dpkg", "uname", "systemctl", "ip", "df",
            "pg_lsclusters", "pg_conftool",
            "pg_ctlcluster", "pg_isready", "ss", "runuser", "openssl", "findmnt",
        }


def _safe_identifier(value: str) -> str:
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,62}", value):
        raise ProvisioningError("IDENTIFIER_INVALID", "PostgreSQL-Bezeichner ungültig")
    return value


def _quote_identifier(value: str) -> str:
    return '"' + _safe_identifier(value).replace('"', '""') + '"'


def _quote_literal(value: str) -> str:
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ProvisioningError("SECRET_CONTENT_INVALID", "Secret enthält Steuerzeichen")
    return "'" + value.replace("'", "''") + "'"


def _atomic_file(path: pathlib.Path, data: bytes, *, mode: int, uid: int = 0, gid: int = 0) -> None:
    current = pathlib.Path(path.anchor)
    for part in path.parent.parts[1:] if path.is_absolute() else path.parent.parts:
        current /= part
        if current.is_symlink():
            raise ProvisioningError("GUEST_PATH_CONFLICT", f"Symlink unzulässig: {current}")
    if path.is_symlink():
        raise ProvisioningError("GUEST_PATH_CONFLICT", f"Symlink unzulässig: {path}")
    path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = pathlib.Path(temporary)
    try:
        os.fchmod(fd, mode)
        os.fchown(fd, uid, gid)
        view = memoryview(data)
        while view:
            size = os.write(fd, view)
            view = view[size:]
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(temp_path, path)
        parent_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    finally:
        if fd >= 0:
            os.close(fd)
        with contextlib.suppress(FileNotFoundError):
            temp_path.unlink()


def read_secret(path: pathlib.Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise ProvisioningError("SECRET_METADATA_INVALID", f"Secret fehlt: {path.name}") from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != 0 or info.st_gid != 0 or info.st_size == 0:
        raise ProvisioningError("SECRET_METADATA_INVALID", f"Secretmetadaten ungültig: {path.name}")
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        if (
            not stat.S_ISREG(opened.st_mode)
            or stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_uid != 0
            or opened.st_gid != 0
            or opened.st_size == 0
        ):
            raise ProvisioningError(
                "SECRET_METADATA_INVALID", f"Secretmetadaten ungültig: {path.name}"
            )
        data = os.read(fd, 4097)
    finally:
        os.close(fd)
    if len(data) > 4096:
        raise ProvisioningError("SECRET_CONTENT_INVALID", "Secret ist zu lang")
    try:
        value = data.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ProvisioningError("SECRET_CONTENT_INVALID", "Secret ist nicht ASCII") from exc
    if not value or any(char.isspace() or ord(char) < 33 or ord(char) == 127 for char in value):
        raise ProvisioningError("SECRET_CONTENT_INVALID", "Secretformat ungültig")
    return value


def load_guest_plan(bundle: pathlib.Path) -> dict[str, object]:
    path = bundle / "guest-plan.json"
    if path.is_symlink() or not path.is_file():
        raise ProvisioningError("GUEST_PLAN_INVALID", "guest-plan.json fehlt")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProvisioningError("GUEST_PLAN_INVALID", "guest-plan.json ungültig") from exc
    if not isinstance(value, dict) or set(value) != {
        "schema_version", "provider_instance_id", "postgresql_major", "fqdn", "hostname",
        "provider_ip", "gateway", "dns_servers", "allocations"
    }:
        raise ProvisioningError("GUEST_PLAN_INVALID", "Gastplanfelder ungültig")
    if value["schema_version"] != 1 or value["provider_instance_id"] != "postgresql-main" or value["postgresql_major"] != 18:
        raise ProvisioningError("GUEST_PLAN_INVALID", "Gastprofil ungültig")
    try:
        ipaddress.IPv4Address(str(value["provider_ip"]))
        ipaddress.IPv4Address(str(value["gateway"]))
        for server in value["dns_servers"]:
            ipaddress.ip_address(str(server))
    except ipaddress.AddressValueError as exc:
        raise ProvisioningError("GUEST_PLAN_INVALID", "Provider-IP ungültig") from exc
    allocations = value["allocations"]
    if not isinstance(allocations, list) or [item.get("allocation_id") for item in allocations if isinstance(item, dict)] != list(ALLOCATION_IDS):
        raise ProvisioningError("GUEST_PLAN_INVALID", "Allocation-Menge ungültig")
    for allocation in allocations:
        _safe_identifier(str(allocation["database_name"]))
        _safe_identifier(str(allocation["application_identity"]))
        _safe_identifier(str(allocation["owner_identity"]))
        for raw in allocation["allowed_client_cidrs"]:
            network = ipaddress.ip_network(str(raw), strict=True)
            if not isinstance(network, ipaddress.IPv4Network) or network.prefixlen == 0:
                raise ProvisioningError("GUEST_PLAN_INVALID", "Nur begrenzte IPv4-Allowlists sind zulässig")
    return value


def verify_manifest(bundle: pathlib.Path) -> None:
    manifest_path = bundle / "public-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ProvisioningError("BUNDLE_INVALID", "Manifest ungültig") from exc
    if set(manifest) != {"schema_version", "artifacts"} or manifest["schema_version"] != 1:
        raise ProvisioningError("BUNDLE_INVALID", "Manifest-Schema ungültig")
    expected = {"postgresql-main-guest.py", "guest-plan.json", "ca.crt", "server.crt"}
    if set(manifest["artifacts"]) != expected:
        raise ProvisioningError("BUNDLE_INVALID", "Manifest-Artefakte ungültig")
    for name, digest in manifest["artifacts"].items():
        path = bundle / name
        if path.is_symlink() or not path.is_file():
            raise ProvisioningError("BUNDLE_INVALID", f"Artefakt fehlt: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ProvisioningError("BUNDLE_INVALID", f"Artefakthash falsch: {name}")
    for allocation in ALLOCATION_IDS:
        read_secret(bundle / allocation / "application-password")


def render_hba(plan: Mapping[str, object]) -> str:
    lines = [
        "# Managed by RALF postgresql-main provisioning",
        "local all postgres peer",
        "local all all reject",
    ]
    for allocation in plan["allocations"]:
        database = _safe_identifier(str(allocation["database_name"]))
        identity = _safe_identifier(str(allocation["application_identity"]))
        for cidr in allocation["allowed_client_cidrs"]:
            network = ipaddress.ip_network(str(cidr), strict=True)
            if not isinstance(network, ipaddress.IPv4Network) or network.prefixlen == 0:
                raise ProvisioningError("HBA_INVALID", "Nur begrenzte IPv4-CIDRs sind zulässig")
            lines.append(f"hostssl {database} {identity} {network} scram-sha-256")
    lines.extend((
        "host all all 0.0.0.0/1 reject",
        "host all all 128.0.0.0/1 reject",
        "host all all ::/1 reject",
        "host all all 8000::/1 reject",
    ))
    return "\n".join(lines) + "\n"


def validate_hba(text: str) -> None:
    lowered = text.lower()
    forbidden = (
        "0.0.0.0/0", "::/0", "hostssl all all", " trust", " md5", " password",
    )
    if any(item in lowered for item in forbidden):
        raise ProvisioningError("HBA_UNSAFE", "HBA enthält breite oder schwache Regel")
    for line in text.splitlines():
        if line.startswith("hostssl ") and not line.endswith(" scram-sha-256"):
            raise ProvisioningError("HBA_UNSAFE", "hostssl ohne SCRAM")


class GuestProvisioner:
    def __init__(
        self,
        *,
        runner: GuestCommandRunner,
        bundle: pathlib.Path = BUNDLE_ROOT,
        root: pathlib.Path = pathlib.Path("/"),
        fault: Callable[[str], None] = lambda _point: None,
    ) -> None:
        self.runner = runner
        self.bundle = bundle
        self.root = root
        self.fault = fault
        self.plan = load_guest_plan(bundle)

    def target(self, absolute: pathlib.Path) -> pathlib.Path:
        return self.root / absolute.relative_to("/")

    def _os_release(self) -> Mapping[str, str]:
        result: dict[str, str] = {}
        for line in self.target(pathlib.Path("/etc/os-release")).read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                result[key] = value.strip('"')
        return result

    def _validate_base(self) -> None:
        if os.geteuid() != 0:
            raise ProvisioningError("ROOT_REQUIRED", "Gastphase benötigt UID 0")
        release = self._os_release()
        if release.get("ID") != "ubuntu" or release.get("VERSION_ID") != "26.04":
            raise ProvisioningError("GUEST_OS_CONFLICT", "Ubuntu 26.04 erforderlich")
        machine = platform.machine()
        if machine not in {"x86_64", "amd64"}:
            raise ProvisioningError("GUEST_ARCH_CONFLICT", "amd64/x86_64 erforderlich")

    def _reject_pgdg(self) -> None:
        apt_root = self.target(pathlib.Path("/etc/apt"))
        for path in apt_root.rglob("*"):
            if path.is_file() and not path.is_symlink() and path.suffix in {".list", ".sources"}:
                text = path.read_text(encoding="utf-8", errors="replace").lower()
                if "apt.postgresql.org" in text or "postgresql.org/pub/repos/apt" in text:
                    raise ProvisioningError("PGDG_SOURCE_CONFLICT", "PGDG-Quelle ist unzulässig")

    def classify(self) -> str:
        self._validate_base()
        verify_manifest(self.bundle)
        self._reject_pgdg()
        clusters = self.runner.run(["pg_lsclusters", "--no-header"], allowed_returncodes=(0, 1)).decode("utf-8", "replace")
        if not clusters.strip():
            return "guest_os_ready"
        rows = [line.split() for line in clusters.splitlines() if line.strip()]
        if len(rows) != 1 or rows[0][:2] != ["18", "main"]:
            return "guest_conflict"
        return "postgresql_installed" if rows[0][3] == "down" else "postgresql_running"

    def apply_phase(self, phase: str, item: str | None) -> str:
        if phase not in GUEST_PHASES:
            raise ProvisioningError("GUEST_PHASE_INVALID", phase)
        self._validate_base()
        verify_manifest(self.bundle)
        self._reject_pgdg()
        if phase == "guest_os_ready":
            return self.prepare_os(item)
        if phase == "postgresql_installed":
            self.install_postgresql(item)
        elif phase == "postgresql_configured":
            self.configure_postgresql(item)
        elif phase == "allocations_created":
            if item not in ALLOCATION_IDS:
                raise ProvisioningError("GUEST_ITEM_INVALID", str(item))
            self.create_allocation(item)
        elif phase == "readiness_verified":
            if item not in ("provider", *ALLOCATION_IDS):
                raise ProvisioningError("GUEST_ITEM_INVALID", str(item))
            self.verify_readiness(item)
        self.verify_phase(phase, item)
        return f"PHASE_COMPLETED {phase}" + (f" {item}" if item else "")

    def prepare_os(self, item: str | None) -> str:
        if item not in {"apt_update", "full_upgrade", "validate"}:
            raise ProvisioningError("GUEST_ITEM_INVALID", str(item))
        locks = (
            self.target(pathlib.Path("/var/lib/dpkg/lock-frontend")),
            self.target(pathlib.Path("/var/lib/apt/lists/lock")),
        )
        for path in locks:
            if path.exists():
                fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
                try:
                    import fcntl
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError as exc:
                        raise ProvisioningError("PACKAGE_MANAGER_LOCKED", "Paketmanager ist belegt") from exc
                finally:
                    os.close(fd)
        if item == "apt_update":
            self.runner.run(["apt-get", "update"])
            self.fault("after_apt_update")
        elif item == "full_upgrade":
            self.runner.run(["apt-get", "-y", "full-upgrade"])
            if self.target(pathlib.Path("/var/run/reboot-required")).exists():
                return "PROVISIONING_PAUSED_REBOOT_REQUIRED"
        else:
            self.runner.run(["dpkg", "--audit"])
            self._verify_runtime_base()
        return f"PHASE_COMPLETED guest_os_ready {item}"

    def _verify_runtime_base(self) -> None:
        self.runner.run(["systemctl", "is-system-running"])
        failed = self.runner.run(["systemctl", "--failed", "--no-legend"]).decode("utf-8", "replace")
        if failed.strip():
            raise ProvisioningError("GUEST_UNITS_FAILED", "Fehlgeschlagene systemd-Units vorhanden")
        addresses = self.runner.run(["ip", "-4", "address", "show"]).decode("utf-8", "replace")
        routes = self.runner.run(["ip", "-4", "route", "show"]).decode("utf-8", "replace")
        if str(self.plan["provider_ip"]) not in addresses or f"default via {self.plan['gateway']}" not in routes:
            raise ProvisioningError("GUEST_NETWORK_CONFLICT", "Gastnetz weicht vom Plan ab")
        resolv = self.target(pathlib.Path("/etc/resolv.conf")).read_text(encoding="utf-8", errors="replace")
        if not any(f"nameserver {server}" in resolv for server in self.plan["dns_servers"]):
            raise ProvisioningError("GUEST_DNS_CONFLICT", "Kein geplanter DNS-Server aktiv")
        disk = self.runner.run(["df", "-Pk", "/"]).decode("utf-8", "replace")
        numbers = re.findall(r"\d+", disk.splitlines()[-1] if disk.splitlines() else "")
        if len(numbers) < 3 or int(numbers[2]) < 2_097_152:
            raise ProvisioningError("GUEST_STORAGE_LOW", "Weniger als 2 GiB frei")
        apt_root = self.target(pathlib.Path("/etc/apt"))
        ubuntu_sources: list[str] = []
        for path in apt_root.rglob("*"):
            if path.is_file() and not path.is_symlink() and path.suffix in {".list", ".sources"}:
                ubuntu_sources.extend(
                    line.strip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
                    if "ubuntu" in line.lower() and ("uri" in line.lower() or line.lstrip().startswith("deb "))
                )
        if not ubuntu_sources or any("http://" in line.lower() for line in ubuntu_sources):
            raise ProvisioningError("UBUNTU_SOURCE_SECURITY_CONFLICT", "Ubuntu-Paketquellen müssen HTTPS verwenden")

    def install_postgresql(self, item: str | None) -> None:
        if item not in {"packages", "validate"}:
            raise ProvisioningError("GUEST_ITEM_INVALID", str(item))
        if item == "validate":
            self._verify_cluster(expected_status="down")
            return
        candidate = self.runner.run(["apt-cache", "policy", "postgresql-18"]).decode("utf-8", "replace")
        match = re.search(r"^\s*Candidate:\s*(\S+)", candidate, re.MULTILINE)
        if not match or not re.match(r"^18(?:\.|\+|~)", match.group(1)):
            raise ProvisioningError("POSTGRESQL_CANDIDATE_CONFLICT", "Ubuntu bietet keine erwartete PostgreSQL-18-Version")
        policy = self.target(POLICY_RC_PATH)
        if policy.exists() or policy.is_symlink():
            raise ProvisioningError("POLICY_RC_CONFLICT", "policy-rc.d existiert bereits")
        _atomic_file(policy, b"#!/bin/sh\nexit 101\n", mode=0o755)
        try:
            self.runner.run(["apt-get", "-y", "install", "postgresql-18", "postgresql-client-18"])
            self.fault("after_postgresql_install")
        finally:
            with contextlib.suppress(FileNotFoundError):
                policy.unlink()
        self._verify_cluster(expected_status="down")

    def _verify_cluster(self, *, expected_status: str | None = None) -> None:
        clusters = self.runner.run(["pg_lsclusters", "--no-header"]).decode("utf-8", "replace")
        rows = [line.split() for line in clusters.splitlines() if line.strip()]
        if len(rows) != 1 or rows[0][:2] != ["18", "main"]:
            raise ProvisioningError("POSTGRESQL_CLUSTER_CONFLICT", "Erwartet wird genau 18/main")
        if expected_status is not None and rows[0][3] != expected_status:
            raise ProvisioningError("POSTGRESQL_STARTED_EARLY", "Cluster startete vor Sicherheitskonfiguration")

    def configure_postgresql(self, item: str | None) -> None:
        if item not in {"tls", "settings", "hba", "start", "validate"}:
            raise ProvisioningError("GUEST_ITEM_INVALID", str(item))
        postgres_gid = grp.getgrnam("postgres").gr_gid
        if item == "tls":
            self._validate_bundle_pki()
            tls_root = self.target(TLS_ROOT)
            tls_root.mkdir(mode=0o750, parents=True, exist_ok=True)
            os.chown(tls_root, 0, postgres_gid)
            os.chmod(tls_root, 0o750)
            _atomic_file(tls_root / "server.key", (self.bundle / "server.key").read_bytes(), mode=0o640, uid=0, gid=postgres_gid)
            _atomic_file(tls_root / "server.crt", (self.bundle / "server.crt").read_bytes(), mode=0o644)
            _atomic_file(tls_root / "ca.crt", (self.bundle / "ca.crt").read_bytes(), mode=0o644)
        elif item == "settings":
            settings = (
                ("listen_addresses", str(self.plan["provider_ip"])),
                ("ssl", "on"),
                ("ssl_cert_file", str(TLS_ROOT / "server.crt")),
                ("ssl_key_file", str(TLS_ROOT / "server.key")),
                ("ssl_ca_file", str(TLS_ROOT / "ca.crt")),
                ("password_encryption", "scram-sha-256"),
                ("ssl_min_protocol_version", "TLSv1.2"),
            )
            for key, value in settings:
                self.runner.run(["pg_conftool", "18", "main", "set", key, value])
        elif item == "hba":
            hba = render_hba(self.plan)
            validate_hba(hba)
            _atomic_file(self.target(HBA_PATH), hba.encode("ascii"), mode=0o640, uid=0, gid=postgres_gid)
        elif item == "start":
            self.runner.run(["pg_conftool", "18", "main", "show"])
            self.runner.run(["pg_ctlcluster", "18", "main", "start"])
            self.fault("after_postgresql_configuration")
        else:
            self.verify_phase("postgresql_configured", "validate")

    def _validate_bundle_pki(self) -> None:
        ca = self.bundle / "ca.crt"
        certificate = self.bundle / "server.crt"
        key = self.bundle / "server.key"
        self.runner.run(["openssl", "verify", "-CAfile", str(ca), str(certificate)])
        text = self.runner.run([
            "openssl", "x509", "-in", str(certificate), "-noout", "-ext", "subjectAltName",
        ]).decode("utf-8", "replace")
        dns_names = re.findall(r"DNS:([^,\s]+)", text)
        ip_addresses = re.findall(r"IP Address:([^,\s]+)", text)
        if dns_names != [str(self.plan["fqdn"])] or ip_addresses != [str(self.plan["provider_ip"])]:
            raise ProvisioningError("PKI_SAN_MISMATCH", "Serverzertifikat bindet Plan nicht")
        key_public = self.runner.run(["openssl", "pkey", "-in", str(key), "-pubout"])
        cert_public = self.runner.run(["openssl", "x509", "-in", str(certificate), "-pubkey", "-noout"])
        if hashlib.sha256(key_public).digest() != hashlib.sha256(cert_public).digest():
            raise ProvisioningError("PKI_KEY_MISMATCH", "Server-Key passt nicht zum Zertifikat")

    def _allocation(self, allocation_id: str) -> Mapping[str, object]:
        return next(item for item in self.plan["allocations"] if item["allocation_id"] == allocation_id)

    def _psql(self, sql: str, *, database: str = "postgres") -> bytes:
        return self.runner.run([
            "runuser", "-u", "postgres", "--", "psql", "-X", "--no-psqlrc",
            "--set", "ON_ERROR_STOP=1", "--dbname", database,
        ], input_data=sql.encode("utf-8"))

    def _query(self, sql: str, *, database: str = "postgres") -> str:
        return self.runner.run([
            "runuser", "-u", "postgres", "--", "psql", "-X", "--no-psqlrc",
            "--set", "ON_ERROR_STOP=1", "--tuples-only", "--no-align",
            "--dbname", database,
        ], input_data=sql.encode("utf-8")).decode("utf-8", "replace").strip()

    def create_allocation(self, allocation_id: str) -> None:
        allocation = self._allocation(allocation_id)
        database = _safe_identifier(str(allocation["database_name"]))
        login = _safe_identifier(str(allocation["application_identity"]))
        owner = _safe_identifier(str(allocation["owner_identity"]))
        secret = read_secret(self.bundle / allocation_id / "application-password")
        owner_state = self._query(
            "SELECT rolcanlogin::text||'|'||rolsuper::text||'|'||rolcreatedb::text||'|'||rolcreaterole::text||'|'||rolreplication::text "
            f"FROM pg_roles WHERE rolname={_quote_literal(owner)};\n"
        )
        if not owner_state:
            self._psql(
                f"CREATE ROLE {_quote_identifier(owner)} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;\n"
            )
        elif owner_state != "false|false|false|false|false" and owner_state != "f|f|f|f|f":
            raise ProvisioningError("ALLOCATION_ROLE_CONFLICT", f"Eigentümerrolle weicht ab: {allocation_id}")
        login_state = self._query(
            "SELECT rolcanlogin::text||'|'||rolsuper::text||'|'||rolcreatedb::text||'|'||rolcreaterole::text||'|'||rolreplication::text "
            f"FROM pg_roles WHERE rolname={_quote_literal(login)};\n"
        )
        if not login_state:
            self._psql(
                f"CREATE ROLE {_quote_identifier(login)} LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD {_quote_literal(secret)};\n"
            )
        elif login_state not in {"true|false|false|false|false", "t|f|f|f|f"}:
            raise ProvisioningError("ALLOCATION_ROLE_CONFLICT", f"Loginrolle weicht ab: {allocation_id}")
        membership = self._query(
            f"SELECT pg_has_role({_quote_literal(login)}, {_quote_literal(owner)}, 'member');\n"
        )
        if membership not in {"t", "true"}:
            self._psql(
                f"GRANT {_quote_identifier(owner)} TO {_quote_identifier(login)} "
                "WITH INHERIT FALSE, SET FALSE;\n"
            )
        database_owner = self._query(
            "SELECT pg_get_userbyid(datdba) FROM pg_database "
            f"WHERE datname={_quote_literal(database)};\n"
        )
        if not database_owner:
            self._psql(
                f"CREATE DATABASE {_quote_identifier(database)} OWNER {_quote_identifier(owner)} ENCODING 'UTF8' TEMPLATE template0;\n"
            )
        elif database_owner != owner:
            raise ProvisioningError("ALLOCATION_DATABASE_CONFLICT", f"Datenbankeigentümer weicht ab: {allocation_id}")
        self._psql(
            "\n".join((
                "REVOKE CONNECT ON DATABASE " + _quote_identifier(database) + " FROM PUBLIC;",
                "GRANT CONNECT ON DATABASE " + _quote_identifier(database) + " TO " + _quote_identifier(login) + ";",
                "",
            ))
        )
        self._psql(
            "REVOKE CREATE ON SCHEMA public FROM PUBLIC;\n"
            "GRANT USAGE, CREATE ON SCHEMA public TO " + _quote_identifier(login) + ";\n",
            database=database,
        )
        self.fault(f"after_allocation:{allocation_id}")

    def verify_readiness(self, item: str) -> None:
        if item == "provider":
            self.runner.run(["pg_isready", "--timeout=5"])
            output = self.runner.run(["ss", "-ltnp"]).decode("utf-8", "replace")
            if "0.0.0.0:5432" in output or "[::]:5432" in output:
                raise ProvisioningError("LISTENER_TOO_BROAD", "PostgreSQL lauscht global")
            if f"{self.plan['provider_ip']}:5432" not in output:
                raise ProvisioningError("LISTENER_MISSING", "Providerlistener fehlt")
            settings = self._query(
                "SHOW server_version_num; SHOW ssl; SHOW password_encryption; SHOW ssl_min_protocol_version;\n"
                "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;\n"
            ).splitlines()
            if len(settings) != 5 or not settings[0].startswith("18") or settings[1:] != ["on", "scram-sha-256", "TLSv1.2", "0"]:
                raise ProvisioningError("POSTGRESQL_RUNTIME_CONFLICT", "Runtime- oder HBA-Zustand weicht ab")
            return
        allocation = self._allocation(item)
        login = _quote_literal(str(allocation["application_identity"]))
        owner = _quote_literal(str(allocation["owner_identity"]))
        database = _quote_literal(str(allocation["database_name"]))
        result = self._query(
            "SELECT 1 FROM pg_roles WHERE rolname=" + login + " AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND rolpassword LIKE 'SCRAM-SHA-256$%';\n"
            "SELECT 1 FROM pg_roles WHERE rolname=" + owner + " AND NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication;\n"
            "SELECT 1 FROM pg_database WHERE datname=" + database + ";\n"
        )
        if result.splitlines() != ["1", "1", "1"]:
            raise ProvisioningError("ALLOCATION_CONFIGURATION_CONFLICT", f"Allocationattribute weichen ab: {item}")
        membership = self._query(
            "SELECT pg_has_role(" + login + ", " + owner + ", 'member')::text||'|'||"
            "pg_has_role(" + login + ", " + owner + ", 'usage')::text||'|'||"
            "pg_has_role(" + login + ", " + owner + ", 'set')::text;\n"
        )
        if membership not in {"true|false|false", "t|f|f"}:
            raise ProvisioningError(
                "ALLOCATION_ROLE_CONFLICT",
                f"Eigentümermitgliedschaft ist zu weitreichend: {item}",
            )
        allocation = self._allocation(item)
        login_name = _safe_identifier(str(allocation["application_identity"]))
        database_name = _safe_identifier(str(allocation["database_name"]))
        self._psql(
            f"SET ROLE {_quote_identifier(login_name)};\n"
            "CREATE TEMP TABLE ralf_readiness_probe(value integer);\n"
            "INSERT INTO ralf_readiness_probe VALUES (1);\n"
            "SELECT value FROM ralf_readiness_probe;\n"
            "DROP TABLE ralf_readiness_probe;\nRESET ROLE;\n",
            database=database_name,
        )
        for foreign in self.plan["allocations"]:
            if foreign["allocation_id"] == item:
                continue
            has_connect = self._query(
                "SELECT has_database_privilege("
                f"{_quote_literal(login_name)}, {_quote_literal(str(foreign['database_name']))}, 'CONNECT');\n"
            )
            if has_connect not in {"f", "false"}:
                raise ProvisioningError("ISOLATION_VIOLATION", f"Fremdzugriff möglich: {item}")

    def verify_phase(self, phase: str, item: str | None = None) -> None:
        if phase == "guest_os_ready":
            self._validate_base()
            self.runner.run(["dpkg", "--audit"])
            self._verify_runtime_base()
        elif phase == "postgresql_installed":
            self._verify_cluster(expected_status="down")
        elif phase == "postgresql_configured":
            if item in {"tls", "validate"}:
                self._validate_bundle_pki()
                key_info = self.target(TLS_ROOT / "server.key").stat()
                postgres_gid = grp.getgrnam("postgres").gr_gid
                if stat.S_IMODE(key_info.st_mode) != 0o640 or key_info.st_uid != 0 or key_info.st_gid != postgres_gid:
                    raise ProvisioningError("TLS_METADATA_INVALID", "Server-Key-Modus falsch")
            if item in {"settings", "validate"}:
                shown = self.runner.run(["pg_conftool", "18", "main", "show"]).decode("utf-8", "replace")
                required = (
                    f"listen_addresses = {self.plan['provider_ip']}",
                    "ssl = on",
                    "password_encryption = scram-sha-256",
                    "ssl_min_protocol_version = TLSv1.2",
                )
                if "0.0.0.0" in shown or "listen_addresses = *" in shown or any(value not in shown for value in required):
                    raise ProvisioningError("POSTGRESQL_CONFIG_CONFLICT", "Effektive Einstellungen weichen ab")
            if item in {"hba", "validate"}:
                validate_hba(self.target(HBA_PATH).read_text(encoding="ascii"))
            if item in {"start", "validate"}:
                self.verify_readiness("provider")
        elif phase == "allocations_created":
            if item is None:
                for allocation in ALLOCATION_IDS:
                    self.verify_readiness(allocation)
            else:
                self.verify_readiness(item)
        elif phase == "readiness_verified":
            self.verify_readiness(item or "provider")

    def cleanup(self) -> None:
        failures: list[str] = []
        for allocation in ALLOCATION_IDS:
            path = self.bundle / allocation / "application-password"
            try:
                path.unlink(missing_ok=True)
            except OSError:
                failures.append(allocation)
        if failures:
            raise ProvisioningError("SECURITY_CLEANUP_FAILED", "Temporäre Gastsecrets konnten nicht vollständig entfernt werden")


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Bounded postgresql-main guest provisioner")
    sub = parser.add_subparsers(dest="command", required=True)
    classify = sub.add_parser("classify")
    classify.add_argument("--bundle", required=True, type=pathlib.Path)
    apply_phase = sub.add_parser("apply-phase")
    apply_phase.add_argument("--phase", required=True, choices=GUEST_PHASES)
    apply_phase.add_argument("--item", choices=GUEST_ITEMS)
    apply_phase.add_argument("--bundle", required=True, type=pathlib.Path)
    verify = sub.add_parser("verify-phase")
    verify.add_argument("--phase", required=True, choices=GUEST_PHASES)
    verify.add_argument("--item", choices=GUEST_ITEMS)
    verify.add_argument("--bundle", required=True, type=pathlib.Path)
    cleanup = sub.add_parser("cleanup")
    cleanup.add_argument("--bundle", required=True, type=pathlib.Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = create_parser().parse_args(argv)
    provisioner: GuestProvisioner | None = None
    try:
        provisioner = GuestProvisioner(runner=GuestCommandRunner(), bundle=args.bundle)
        if args.command == "classify":
            print(f"RALF_POSTGRESQL_GUEST_STATE_V1={provisioner.classify()}")
        elif args.command == "apply-phase":
            print(provisioner.apply_phase(args.phase, args.item))
        elif args.command == "verify-phase":
            provisioner.verify_phase(args.phase, args.item)
            print(f"PHASE_VERIFIED {args.phase}" + (f" {args.item}" if args.item else ""))
        elif args.command == "cleanup":
            provisioner.cleanup()
            print("SECURITY_CLEANUP_COMPLETED")
        return 0
    except Exception as raw_exc:
        exc = raw_exc if isinstance(raw_exc, ProvisioningError) else ProvisioningError(
            "GUEST_INTERNAL_ERROR", type(raw_exc).__name__
        )
        cleanup_failed = False
        if provisioner is not None and args.command in {"apply-phase", "verify-phase"}:
            try:
                provisioner.cleanup()
            except ProvisioningError:
                cleanup_failed = True
        print(f"{exc.code}: {exc.message}", file=sys.stderr)
        if cleanup_failed:
            print("SECURITY_CLEANUP_FAILED: temporäre Gastsecrets konnten nicht vollständig entfernt werden", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
