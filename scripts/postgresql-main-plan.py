#!/usr/bin/env python3
"""Read-only deployment planner for the postgresql-main reference instance."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import ipaddress
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tomllib
from collections.abc import Callable, Mapping, Sequence


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
REAL_CONFIG_PATH = pathlib.Path(
    "/secrets/database-service/providers/postgresql-main/deployment.toml"
)
EXAMPLE_CONFIG_PATH = REPO_ROOT / "deploy/postgresql/postgresql-main.example.toml"
VERSION_MATRIX_PATH = REPO_ROOT / "deploy/postgresql/version-matrix.toml"

PROVIDER_INSTANCE_ID = "postgresql-main"
PROVIDER_HOSTNAME = "postgresql-main"
POSTGRESQL_MAJOR = 18
EXPECTED_ALLOCATIONS = ("gitea", "openbao", "semaphore", "nodered")
REFERENCE_CORES = 4
REFERENCE_MEMORY_MIB = 8192
REFERENCE_DISK_GIB = 100
OUTPUT_LIMIT = 65_536
COMMAND_TIMEOUT_SECONDS = 8

SECRET_ROOT = pathlib.Path("/secrets")
PROVIDER_SECRET_ROOT = SECRET_ROOT / "database-service/providers/postgresql-main"
ALLOCATION_SECRET_ROOT = SECRET_ROOT / "database-service/allocations"

MUTATION_PLAN = (
    "Unprivilegierten Ubuntu-26.04-LXC postgresql-main anlegen",
    "Ubuntu-Pakete kontrolliert aktualisieren",
    "PostgreSQL 18 aus den offiziellen Ubuntu-26.04-Quellen installieren",
    "Dedizierte Provider-TLS-Artefakte nach eigener Freigabe bereitstellen",
    "PostgreSQL auf SCRAM, TLS und die konkrete Provideradresse begrenzen",
    "Vier isolierte logische Datenbanken anlegen",
    "Vier isolierte Anwendungsidentitäten mit minimalen Rechten anlegen",
    "Secretwerte ausschließlich unter /secrets erzeugen",
    "Provider- und Allocation-Health sowie Readiness prüfen",
    "Initiale leere logische Backups im Custom-Format erzeugen und prüfen",
)

EXCLUDED_SCOPE = (
    "Gitea-Installation",
    "OpenBao-Installation",
    "Semaphore-Installation",
    "Node-RED-Installation",
    "RALF Core",
    "pgvector",
    "Hochverfügbarkeit",
    "Replikation",
    "Docker oder Podman",
    "automatischer PostgreSQL-Major-Wechsel",
    "keine reale Mutation im Planmodus",
)


class PlannerError(Exception):
    """Base class for safe planner failures."""


class ConfigurationError(PlannerError):
    """The local deployment configuration is invalid."""


class MatrixError(PlannerError):
    """The packaged version matrix is invalid."""


class ProbeError(PlannerError):
    """A read-only probe failed or violated the command allowlist."""


@dataclasses.dataclass(frozen=True)
class ProviderConfig:
    provider_instance_id: str
    hostname: str
    fqdn: str
    postgresql_major: int


@dataclasses.dataclass(frozen=True)
class LxcConfig:
    vmid: int
    storage: str
    bridge: str
    ipv4_interface: ipaddress.IPv4Interface
    gateway: ipaddress.IPv4Address
    dns_servers: tuple[ipaddress.IPv4Address | ipaddress.IPv6Address, ...]
    cores: int
    memory_mib: int
    swap_mib: int
    disk_gib: int


@dataclasses.dataclass(frozen=True)
class BackupConfig:
    host_root: pathlib.Path
    minimum_free_gib: int
    protection_confirmed: bool


@dataclasses.dataclass(frozen=True)
class AllocationConfig:
    allocation_id: str
    database_name: str
    application_identity: str
    allowed_client_cidrs: tuple[ipaddress.IPv4Network | ipaddress.IPv6Network, ...]


@dataclasses.dataclass(frozen=True)
class DeploymentConfig:
    provider: ProviderConfig
    lxc: LxcConfig
    backup: BackupConfig
    allocations: tuple[AllocationConfig, ...]


@dataclasses.dataclass(frozen=True)
class VersionMatrix:
    checked_at: str
    postgresql: Mapping[str, object]
    applications: Mapping[str, Mapping[str, str]]


@dataclasses.dataclass(frozen=True)
class CommandResult:
    stdout: str
    stderr: str
    returncode: int


@dataclasses.dataclass(frozen=True)
class StorageInfo:
    name: str
    status: str
    available_bytes: int


@dataclasses.dataclass
class ProxmoxState:
    pve_version: str = "unbekannt"
    vmid: int | None = None
    vmid_source: str = "unbekannt"
    storage: str | None = None
    storage_source: str = "unbekannt"
    storage_available_bytes: int | None = None
    bridge: str | None = None
    bridge_source: str = "unbekannt"
    template: str | None = None
    host_addresses_checked: bool = False
    host_routes_checked: bool = False
    warnings: list[str] = dataclasses.field(default_factory=list)
    blockers: list[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass(frozen=True)
class PathCheck:
    path: pathlib.Path
    state: str
    metadata: str
    conflict: str | None = None


@dataclasses.dataclass(frozen=True)
class BackupCheck:
    path: pathlib.Path
    state: str
    free_bytes: int | None
    blockers: tuple[str, ...]
    warnings: tuple[str, ...]


@dataclasses.dataclass
class PlanReport:
    sections: list[tuple[str, list[str]]] = dataclasses.field(default_factory=list)
    warnings: list[str] = dataclasses.field(default_factory=list)
    blockers: list[str] = dataclasses.field(default_factory=list)

    def add_section(self, title: str, lines: Sequence[str]) -> None:
        self.sections.append((title, list(lines)))

    def render(self) -> str:
        output: list[str] = []
        for title, lines in self.sections:
            output.append(f"== {title} ==")
            output.extend(lines)
            output.append("")
        output.append("== WARNUNGEN ==")
        output.extend(f"WARNUNG: {item}" for item in self.warnings)
        if not self.warnings:
            output.append("keine")
        output.append("")
        output.append("== BLOCKER ==")
        output.extend(f"BLOCKER: {item}" for item in self.blockers)
        if not self.blockers:
            output.append("keine")
        output.append("")
        output.append("PLAN_BLOCKED" if self.blockers else "PLAN_READY")
        return "\n".join(output) + "\n"


def _expect_table(value: object, context: str) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise ConfigurationError(f"{context} muss eine TOML-Tabelle sein")
    return value


def _check_keys(
    table: Mapping[str, object],
    *,
    allowed: set[str],
    required: set[str],
    context: str,
    error_type: type[PlannerError] = ConfigurationError,
) -> None:
    unknown = sorted(set(table) - allowed)
    missing = sorted(required - set(table))
    if unknown:
        raise error_type(f"{context}: unbekannte Schlüssel: {', '.join(unknown)}")
    if missing:
        raise error_type(f"{context}: fehlende Schlüssel: {', '.join(missing)}")


def _require_string(value: object, context: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ConfigurationError(f"{context} muss eine Zeichenkette sein")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ConfigurationError(f"{context} enthält Steuerzeichen")
    if not allow_empty and not value:
        raise ConfigurationError(f"{context} darf nicht leer sein")
    return value


def _require_int(value: object, context: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ConfigurationError(f"{context} muss eine Ganzzahl sein")
    if value < minimum:
        raise ConfigurationError(f"{context} muss mindestens {minimum} sein")
    return value


def _require_bool(value: object, context: str) -> bool:
    if not isinstance(value, bool):
        raise ConfigurationError(f"{context} muss true oder false sein")
    return value


def validate_fqdn(value: object) -> str:
    fqdn = _require_string(value, "provider.fqdn")
    if fqdn != fqdn.lower():
        raise ConfigurationError("provider.fqdn muss kleingeschrieben sein")
    try:
        fqdn.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ConfigurationError("provider.fqdn muss ASCII sein") from exc
    if any(token in fqdn for token in ("://", "/", ":", "@", "*")):
        raise ConfigurationError("provider.fqdn darf weder Schema, Port, Pfad, Zugangsdaten noch Wildcard enthalten")
    if fqdn.endswith(".") or len(fqdn) > 253:
        raise ConfigurationError("provider.fqdn ist nicht kanonisch")
    labels = fqdn.split(".")
    if len(labels) < 2:
        raise ConfigurationError("provider.fqdn benötigt mindestens zwei Labels")
    label_re = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
    if any(not label_re.fullmatch(label) for label in labels):
        raise ConfigurationError("provider.fqdn enthält ein ungültiges Label")
    try:
        ipaddress.ip_address(fqdn)
    except ValueError:
        return fqdn
    raise ConfigurationError("provider.fqdn darf keine IP-Adresse sein")


def validate_name(value: object, context: str) -> str:
    name = _require_string(value, context)
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,62}", name):
        raise ConfigurationError(
            f"{context} muss kleingeschrieben, höchstens 63 Zeichen lang und ein PostgreSQL-sicherer Bezeichner sein"
        )
    return name


def validate_ipv4_interface(value: object) -> ipaddress.IPv4Interface:
    raw = _require_string(value, "lxc.ipv4_cidr")
    try:
        interface = ipaddress.ip_interface(raw)
    except ValueError as exc:
        raise ConfigurationError("lxc.ipv4_cidr ist keine gültige Hostadresse mit Präfix") from exc
    if not isinstance(interface, ipaddress.IPv4Interface):
        raise ConfigurationError("lxc.ipv4_cidr muss IPv4 verwenden")
    network = interface.network
    if interface.ip in (network.network_address, network.broadcast_address):
        raise ConfigurationError("lxc.ipv4_cidr darf weder Netzwerk- noch Broadcastadresse verwenden")
    if interface.ip.is_multicast or interface.ip.is_loopback or interface.ip.is_unspecified:
        raise ConfigurationError("lxc.ipv4_cidr verwendet eine unzulässige Adresse")
    return interface


def validate_gateway(value: object, interface: ipaddress.IPv4Interface) -> ipaddress.IPv4Address:
    raw = _require_string(value, "lxc.gateway")
    try:
        gateway = ipaddress.ip_address(raw)
    except ValueError as exc:
        raise ConfigurationError("lxc.gateway ist keine gültige IPv4-Adresse") from exc
    if not isinstance(gateway, ipaddress.IPv4Address):
        raise ConfigurationError("lxc.gateway muss IPv4 verwenden")
    if gateway not in interface.network or gateway in (
        interface.network.network_address,
        interface.network.broadcast_address,
    ):
        raise ConfigurationError("lxc.gateway muss eine Hostadresse im Netz von lxc.ipv4_cidr sein")
    if gateway.is_multicast or gateway.is_loopback or gateway.is_unspecified:
        raise ConfigurationError("lxc.gateway verwendet eine unzulässige Adresse")
    return gateway


def validate_cidrs(value: object, context: str) -> tuple[ipaddress.IPv4Network | ipaddress.IPv6Network, ...]:
    if not isinstance(value, list):
        raise ConfigurationError(f"{context} muss eine Liste sein")
    result: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        raw = _require_string(item, f"{context}[{index}]")
        try:
            network = ipaddress.ip_network(raw, strict=True)
        except ValueError as exc:
            raise ConfigurationError(f"{context}[{index}] ist keine kanonische CIDR") from exc
        if raw != str(network):
            raise ConfigurationError(f"{context}[{index}] ist nicht kanonisch")
        if network.prefixlen == 0:
            raise ConfigurationError(f"{context} darf keine globale Freigabe enthalten")
        if raw in seen:
            raise ConfigurationError(f"{context} enthält ein Duplikat")
        seen.add(raw)
        result.append(network)
    return tuple(result)


def validate_dns_servers(
    value: object,
) -> tuple[ipaddress.IPv4Address | ipaddress.IPv6Address, ...]:
    if not isinstance(value, list):
        raise ConfigurationError("lxc.dns_servers muss eine Liste sein")
    result: list[ipaddress.IPv4Address | ipaddress.IPv6Address] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        raw = _require_string(item, f"lxc.dns_servers[{index}]")
        try:
            address = ipaddress.ip_address(raw)
        except ValueError as exc:
            raise ConfigurationError(
                f"lxc.dns_servers[{index}] ist keine gültige IP-Adresse"
            ) from exc
        if raw != str(address):
            raise ConfigurationError(f"lxc.dns_servers[{index}] ist nicht kanonisch")
        if address.is_unspecified or address.is_loopback or address.is_multicast:
            raise ConfigurationError(
                f"lxc.dns_servers[{index}] verwendet eine unzulässige Adresse"
            )
        if raw in seen:
            raise ConfigurationError("lxc.dns_servers enthält ein Duplikat")
        seen.add(raw)
        result.append(address)
    return tuple(result)


def _read_toml(path: pathlib.Path, error_type: type[PlannerError]) -> Mapping[str, object]:
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise error_type(f"Datei fehlt: {path}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise error_type(f"Datei muss regulär und darf kein Symlink sein: {path}")
    try:
        with path.open("rb") as handle:
            value = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise error_type(f"TOML kann nicht gelesen werden: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise error_type(f"TOML-Wurzel ist ungültig: {path}")
    return value


def ensure_no_symlink_components(path: pathlib.Path, root: pathlib.Path) -> None:
    """Reject existing symlinks from the allowed root through the target path."""
    absolute_path = pathlib.Path(os.path.abspath(path))
    absolute_root = pathlib.Path(os.path.abspath(root))
    try:
        relative = absolute_path.relative_to(absolute_root)
    except ValueError as exc:
        raise ConfigurationError(f"Pfad liegt nicht unter {absolute_root}: {absolute_path}") from exc
    candidates = [absolute_root]
    current = absolute_root
    for part in relative.parts:
        current /= part
        candidates.append(current)
    for candidate in candidates:
        try:
            info = candidate.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            raise ConfigurationError(f"Symlink-Komponente ist unzulässig: {candidate}")


def load_config(path: pathlib.Path) -> DeploymentConfig:
    root = _read_toml(path, ConfigurationError)
    _check_keys(
        root,
        allowed={"schema_version", "provider", "lxc", "backup", "allocations"},
        required={"schema_version", "provider", "lxc", "backup", "allocations"},
        context="Wurzel",
    )
    if _require_int(root["schema_version"], "schema_version") != 1:
        raise ConfigurationError("schema_version muss 1 sein")

    provider_table = _expect_table(root["provider"], "provider")
    _check_keys(
        provider_table,
        allowed={"provider_instance_id", "hostname", "fqdn", "postgresql_major"},
        required={"provider_instance_id", "hostname", "fqdn", "postgresql_major"},
        context="provider",
    )
    provider = ProviderConfig(
        provider_instance_id=_require_string(
            provider_table["provider_instance_id"], "provider.provider_instance_id"
        ),
        hostname=_require_string(provider_table["hostname"], "provider.hostname"),
        fqdn=validate_fqdn(provider_table["fqdn"]),
        postgresql_major=_require_int(
            provider_table["postgresql_major"], "provider.postgresql_major"
        ),
    )
    if provider.provider_instance_id != PROVIDER_INSTANCE_ID:
        raise ConfigurationError(f"provider.provider_instance_id muss {PROVIDER_INSTANCE_ID} sein")
    if provider.hostname != PROVIDER_HOSTNAME:
        raise ConfigurationError(f"provider.hostname muss {PROVIDER_HOSTNAME} sein")
    if provider.postgresql_major != POSTGRESQL_MAJOR:
        raise ConfigurationError("provider.postgresql_major muss 18 sein")

    lxc_table = _expect_table(root["lxc"], "lxc")
    lxc_keys = {
        "vmid",
        "storage",
        "bridge",
        "ipv4_cidr",
        "gateway",
        "dns_servers",
        "cores",
        "memory_mib",
        "swap_mib",
        "disk_gib",
    }
    _check_keys(lxc_table, allowed=lxc_keys, required=lxc_keys, context="lxc")
    vmid = _require_int(lxc_table["vmid"], "lxc.vmid")
    if vmid != 0 and not 100 <= vmid <= 999_999_999:
        raise ConfigurationError("lxc.vmid muss 0 oder eine gültige explizite VMID sein")
    interface = validate_ipv4_interface(lxc_table["ipv4_cidr"])
    gateway = validate_gateway(lxc_table["gateway"], interface)
    lxc = LxcConfig(
        vmid=vmid,
        storage=_require_string(lxc_table["storage"], "lxc.storage", allow_empty=True),
        bridge=_require_string(lxc_table["bridge"], "lxc.bridge", allow_empty=True),
        ipv4_interface=interface,
        gateway=gateway,
        dns_servers=validate_dns_servers(lxc_table["dns_servers"]),
        cores=_require_int(lxc_table["cores"], "lxc.cores", minimum=1),
        memory_mib=_require_int(lxc_table["memory_mib"], "lxc.memory_mib", minimum=1),
        swap_mib=_require_int(lxc_table["swap_mib"], "lxc.swap_mib", minimum=0),
        disk_gib=_require_int(lxc_table["disk_gib"], "lxc.disk_gib", minimum=1),
    )

    backup_table = _expect_table(root["backup"], "backup")
    backup_keys = {"host_root", "minimum_free_gib", "protection_confirmed"}
    _check_keys(backup_table, allowed=backup_keys, required=backup_keys, context="backup")
    backup_path = pathlib.Path(_require_string(backup_table["host_root"], "backup.host_root"))
    if not backup_path.is_absolute():
        raise ConfigurationError("backup.host_root muss ein absoluter Pfad sein")
    backup = BackupConfig(
        host_root=backup_path,
        minimum_free_gib=_require_int(
            backup_table["minimum_free_gib"], "backup.minimum_free_gib", minimum=1
        ),
        protection_confirmed=_require_bool(
            backup_table["protection_confirmed"], "backup.protection_confirmed"
        ),
    )

    allocation_values = root["allocations"]
    if not isinstance(allocation_values, list):
        raise ConfigurationError("allocations muss eine Liste von Tabellen sein")
    allocations: list[AllocationConfig] = []
    allocation_keys = {
        "allocation_id",
        "database_name",
        "application_identity",
        "allowed_client_cidrs",
    }
    for index, raw_allocation in enumerate(allocation_values):
        table = _expect_table(raw_allocation, f"allocations[{index}]")
        _check_keys(
            table,
            allowed=allocation_keys,
            required=allocation_keys,
            context=f"allocations[{index}]",
        )
        allocations.append(
            AllocationConfig(
                allocation_id=_require_string(
                    table["allocation_id"], f"allocations[{index}].allocation_id"
                ),
                database_name=validate_name(
                    table["database_name"], f"allocations[{index}].database_name"
                ),
                application_identity=validate_name(
                    table["application_identity"],
                    f"allocations[{index}].application_identity",
                ),
                allowed_client_cidrs=validate_cidrs(
                    table["allowed_client_cidrs"],
                    f"allocations[{index}].allowed_client_cidrs",
                ),
            )
        )
    ids = [allocation.allocation_id for allocation in allocations]
    if len(ids) != len(set(ids)):
        raise ConfigurationError("allocations enthält eine doppelte allocation_id")
    if set(ids) != set(EXPECTED_ALLOCATIONS) or len(ids) != len(EXPECTED_ALLOCATIONS):
        raise ConfigurationError(
            "allocations muss exakt gitea, openbao, semaphore und nodered enthalten"
        )
    database_names = [allocation.database_name for allocation in allocations]
    identities = [allocation.application_identity for allocation in allocations]
    if len(database_names) != len(set(database_names)):
        raise ConfigurationError("database_name muss pro Allocation eindeutig sein")
    if len(identities) != len(set(identities)):
        raise ConfigurationError("application_identity muss pro Allocation eindeutig sein")
    allocations.sort(key=lambda item: EXPECTED_ALLOCATIONS.index(item.allocation_id))
    return DeploymentConfig(provider=provider, lxc=lxc, backup=backup, allocations=tuple(allocations))


def load_version_matrix(path: pathlib.Path = VERSION_MATRIX_PATH) -> VersionMatrix:
    root = _read_toml(path, MatrixError)
    expected_sections = {
        "schema_version",
        "checked_at",
        "postgresql",
        "gitea",
        "openbao",
        "semaphore",
        "nodered",
    }
    _check_keys(
        root,
        allowed=expected_sections,
        required=expected_sections,
        context="Versionsmatrix",
        error_type=MatrixError,
    )
    if root["schema_version"] != 1:
        raise MatrixError("Versionsmatrix: schema_version muss 1 sein")
    checked = root["checked_at"]
    if isinstance(checked, dt.date):
        checked_at = checked.isoformat()
    elif isinstance(checked, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", checked):
        checked_at = checked
    else:
        raise MatrixError("Versionsmatrix: checked_at ist ungültig")

    specs: dict[str, tuple[set[str], Mapping[str, object]]] = {}
    for name in ("postgresql", "gitea", "openbao", "semaphore", "nodered"):
        value = root[name]
        if not isinstance(value, dict):
            raise MatrixError(f"Versionsmatrix: {name} muss eine Tabelle sein")
        specs[name] = (set(value), value)
    expected_keys = {
        "postgresql": {"major", "documented_minor", "package", "update_policy"},
        "gitea": {"version", "postgresql_requirement"},
        "openbao": {"version", "postgresql_requirement", "storage_backend"},
        "semaphore": {"version", "database_backend"},
        "nodered": {"version", "nodejs_reference", "database_usage"},
    }
    for name, (keys, _value) in specs.items():
        if keys != expected_keys[name]:
            raise MatrixError(f"Versionsmatrix: unerwartete Schlüssel in {name}")
    postgresql = specs["postgresql"][1]
    if postgresql != {
        "major": 18,
        "documented_minor": "18.4",
        "package": "postgresql-18",
        "update_policy": "latest-stable-18.x",
    }:
        raise MatrixError("Versionsmatrix: PostgreSQL-Referenzstand ist unerwartet")
    application_expected = {
        "gitea": {"version": "1.27.1", "postgresql_requirement": ">=12"},
        "openbao": {
            "version": "2.6.1",
            "postgresql_requirement": ">=9.5",
            "storage_backend": "postgresql",
        },
        "semaphore": {"version": "2.18.29", "database_backend": "postgres"},
        "nodered": {
            "version": "5.0.4",
            "nodejs_reference": "24",
            "database_usage": "flow_application_data_only",
        },
    }
    applications: dict[str, Mapping[str, str]] = {}
    for name, expected in application_expected.items():
        actual = specs[name][1]
        if actual != expected:
            raise MatrixError(f"Versionsmatrix: Referenzstand für {name} ist unerwartet")
        applications[name] = {key: str(value) for key, value in actual.items()}
    return VersionMatrix(
        checked_at=checked_at,
        postgresql=postgresql,
        applications=applications,
    )


def _allowed_command(arguments: Sequence[str]) -> bool:
    args = tuple(arguments)
    if args == ("pveversion",):
        return True
    if args == ("pct", "list"):
        return True
    if len(args) == 3 and args[:2] in {
        ("pct", "status"),
        ("pct", "config"),
        ("pct", "pending"),
    } and args[2].isdigit():
        return True
    if args == ("pvesm", "status", "--content", "rootdir"):
        return True
    if args in {
        ("ip", "link", "show", "type", "bridge"),
        ("ip", "address", "show"),
        ("ip", "route", "show"),
        ("pveam", "available", "--section", "system"),
    }:
        return True
    return False


class CommandRunner:
    """Execute only explicitly allowlisted, read-only host probes."""

    def __init__(
        self,
        executor: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        self._executor = executor

    def run(self, arguments: Sequence[str]) -> CommandResult:
        args = list(arguments)
        if not _allowed_command(args):
            raise ProbeError(f"nicht erlaubter externer Aufruf: {' '.join(args)}")
        try:
            completed = self._executor(
                args,
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=COMMAND_TIMEOUT_SECONDS,
                env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"},
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ProbeError(f"read-only Aufruf fehlgeschlagen: {' '.join(args)}: {exc}") from exc
        stdout = completed.stdout or ""
        stderr = completed.stderr or ""
        if len(stdout.encode()) > OUTPUT_LIMIT or len(stderr.encode()) > OUTPUT_LIMIT:
            raise ProbeError(f"read-only Aufruf lieferte zu viel Ausgabe: {' '.join(args)}")
        if completed.returncode != 0:
            diagnostic = " ".join(stderr.strip().split())[:500]
            raise ProbeError(
                f"read-only Aufruf meldete Fehler: {' '.join(args)}"
                + (f": {diagnostic}" if diagnostic else "")
            )
        return CommandResult(stdout=stdout, stderr=stderr, returncode=completed.returncode)


def _parse_pct_ids(output: str) -> set[int]:
    result: set[int] = set()
    for line in output.splitlines():
        fields = line.split()
        if fields and fields[0].isdigit():
            result.add(int(fields[0]))
    return result


def _parse_size(value: str) -> int:
    if value.isdigit():
        return int(value)
    match = re.fullmatch(r"(\d+(?:\.\d+)?)([KMGT])", value, re.IGNORECASE)
    if not match:
        raise ValueError(value)
    units = {"K": 1, "M": 2, "G": 3, "T": 4}
    return int(float(match.group(1)) * (1024 ** units[match.group(2).upper()]))


def _parse_storages(output: str) -> list[StorageInfo]:
    result: list[StorageInfo] = []
    for line in output.splitlines():
        fields = line.split()
        if not fields or fields[0].lower() == "name" or len(fields) < 6:
            continue
        try:
            available = _parse_size(fields[5])
        except ValueError:
            continue
        result.append(StorageInfo(name=fields[0], status=fields[2], available_bytes=available))
    return result


def _parse_bridges(output: str) -> list[str]:
    result: list[str] = []
    for line in output.splitlines():
        match = re.match(r"^\d+:\s+([^:@]+)(?:@[^:]+)?:", line.strip())
        if match:
            result.append(match.group(1))
    return sorted(set(result))


def _parse_templates(output: str) -> list[str]:
    candidates: list[str] = []
    for line in output.splitlines():
        for field in line.split():
            lowered = field.lower()
            if "ubuntu-26.04" in lowered and "amd64" in lowered:
                candidates.append(field)
    return sorted(set(candidates))


def _next_free_vmid(used: set[int]) -> int:
    vmid = 100
    while vmid in used:
        vmid += 1
    return vmid


def collect_proxmox_state(config: DeploymentConfig, runner: CommandRunner) -> ProxmoxState:
    state = ProxmoxState()

    def probe(arguments: Sequence[str], label: str) -> str | None:
        try:
            return runner.run(arguments).stdout
        except ProbeError as exc:
            state.blockers.append(f"{label}: {exc}")
            return None

    pve_version = probe(["pveversion"], "Proxmox-Version nicht lesbar")
    if pve_version is not None:
        state.pve_version = " ".join(pve_version.strip().split()) or "unbekannt"

    pct_output = probe(["pct", "list"], "Containerliste nicht lesbar")
    used_ids = _parse_pct_ids(pct_output or "")
    if config.lxc.vmid == 0:
        if pct_output is None:
            state.blockers.append("VMID 0 kann ohne lesbare Containerliste nicht aufgelöst werden")
        else:
            state.vmid = _next_free_vmid(used_ids)
            state.vmid_source = "read-only aus pct list ermittelt"
    else:
        state.vmid = config.lxc.vmid
        state.vmid_source = "explizite Konfiguration"
        if config.lxc.vmid in used_ids:
            state.blockers.append(f"VMID {config.lxc.vmid} ist bereits durch einen LXC belegt")
            for action in ("status", "config", "pending"):
                probe(
                    ["pct", action, str(config.lxc.vmid)],
                    f"Belegungsdiagnose pct {action} fehlgeschlagen",
                )

    storage_output = probe(
        ["pvesm", "status", "--content", "rootdir"],
        "Storagezustand nicht lesbar",
    )
    storages = [item for item in _parse_storages(storage_output or "") if item.status == "active"]
    selected_storage: StorageInfo | None = None
    if config.lxc.storage:
        state.storage_source = "explizite Konfiguration"
        selected_storage = next((item for item in storages if item.name == config.lxc.storage), None)
        if selected_storage is None:
            state.blockers.append(f"konfiguriertes Storage {config.lxc.storage} ist nicht als aktives rootdir-Storage verfügbar")
    elif len(storages) == 1:
        selected_storage = storages[0]
        state.storage_source = "eindeutig read-only ermittelt"
    elif not storages:
        state.blockers.append("kein geeignetes aktives rootdir-Storage gefunden")
    else:
        state.blockers.append(
            "Storage ist mehrdeutig; explizite Auswahl erforderlich: "
            + ", ".join(item.name for item in storages)
        )
    if selected_storage is not None:
        state.storage = selected_storage.name
        state.storage_available_bytes = selected_storage.available_bytes
        required = config.lxc.disk_gib * 1024**3
        if selected_storage.available_bytes < required:
            state.blockers.append(
                f"Storage {selected_storage.name} besitzt weniger freien Speicher als die geplanten {config.lxc.disk_gib} GiB"
            )

    bridge_output = probe(["ip", "link", "show", "type", "bridge"], "Bridges nicht lesbar")
    bridges = _parse_bridges(bridge_output or "")
    if config.lxc.bridge:
        state.bridge_source = "explizite Konfiguration"
        if config.lxc.bridge in bridges:
            state.bridge = config.lxc.bridge
        else:
            state.blockers.append(f"konfigurierte Bridge {config.lxc.bridge} ist nicht vorhanden")
    elif len(bridges) == 1:
        state.bridge = bridges[0]
        state.bridge_source = "eindeutig read-only ermittelt"
    elif not bridges:
        state.blockers.append("keine geeignete Bridge gefunden")
    else:
        state.blockers.append("Bridge ist mehrdeutig; explizite Auswahl erforderlich: " + ", ".join(bridges))

    address_output = probe(["ip", "address", "show"], "Hostadressen nicht lesbar")
    if address_output is not None:
        state.host_addresses_checked = True
        address_pattern = re.compile(rf"\binet\s+{re.escape(str(config.lxc.ipv4_interface.ip))}/")
        if address_pattern.search(address_output):
            state.blockers.append(
                f"Provideradresse {config.lxc.ipv4_interface.ip} ist bereits auf dem Proxmox-Host konfiguriert"
            )
    route_output = probe(["ip", "route", "show"], "Hostrouten nicht lesbar")
    if route_output is not None:
        state.host_routes_checked = True

    template_output = probe(
        ["pveam", "available", "--section", "system"],
        "Templatekatalog nicht lesbar",
    )
    templates = _parse_templates(template_output or "")
    if len(templates) == 1:
        state.template = templates[0]
    elif not templates:
        state.blockers.append("kein eindeutiges Ubuntu-26.04-amd64-Template gefunden")
    else:
        state.blockers.append("Ubuntu-26.04-amd64-Template ist mehrdeutig: " + ", ".join(templates))

    if config.lxc.cores < REFERENCE_CORES:
        state.warnings.append(
            f"{config.lxc.cores} vCPU liegen unter dem Referenzprofil von {REFERENCE_CORES} vCPU"
        )
    if config.lxc.memory_mib < REFERENCE_MEMORY_MIB:
        state.warnings.append(
            f"{config.lxc.memory_mib} MiB RAM liegen unter dem Referenzprofil von {REFERENCE_MEMORY_MIB} MiB"
        )
    if config.lxc.disk_gib < REFERENCE_DISK_GIB:
        state.warnings.append(
            f"{config.lxc.disk_gib} GiB Root-Disk liegen unter dem Referenzprofil von {REFERENCE_DISK_GIB} GiB"
        )
    return state


def _path_under(path: pathlib.Path, root: pathlib.Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def inspect_path(
    path: pathlib.Path,
    *,
    kind: str,
    expected_mode: int,
    require_nonempty: bool,
    lstat_function: Callable[[pathlib.Path], os.stat_result] = os.lstat,
) -> PathCheck:
    try:
        info = lstat_function(path)
    except FileNotFoundError:
        return PathCheck(path=path, state="FEHLT_GEPLANT", metadata="nicht vorhanden")
    mode = stat.S_IMODE(info.st_mode)
    metadata = f"uid={info.st_uid} gid={info.st_gid} mode={mode:04o}"
    if stat.S_ISLNK(info.st_mode):
        return PathCheck(path, "KONFLIKT", metadata, "Symlink ist unzulässig")
    if kind == "directory" and not stat.S_ISDIR(info.st_mode):
        return PathCheck(path, "KONFLIKT", metadata, "erwartetes Verzeichnis ist nicht vorhanden")
    if kind == "file" and not stat.S_ISREG(info.st_mode):
        return PathCheck(path, "KONFLIKT", metadata, "erwartete reguläre Datei ist nicht vorhanden")
    if info.st_uid != 0 or info.st_gid != 0:
        return PathCheck(path, "KONFLIKT", metadata, "Eigentümer muss root:root sein")
    if mode != expected_mode:
        return PathCheck(
            path,
            "KONFLIKT",
            metadata,
            f"Modus muss {expected_mode:04o} sein",
        )
    if require_nonempty and info.st_size == 0:
        return PathCheck(path, "KONFLIKT", metadata, "Datei darf nicht leer sein")
    return PathCheck(path=path, state="OK", metadata=metadata)


def inspect_secret_contract() -> tuple[PathCheck, ...]:
    checks: list[PathCheck] = []
    directories = [
        SECRET_ROOT,
        SECRET_ROOT / "database-service",
        SECRET_ROOT / "database-service/providers",
        PROVIDER_SECRET_ROOT,
        PROVIDER_SECRET_ROOT / "pki",
        ALLOCATION_SECRET_ROOT,
        *(ALLOCATION_SECRET_ROOT / allocation for allocation in EXPECTED_ALLOCATIONS),
    ]
    for path in directories:
        checks.append(
            inspect_path(
                path,
                kind="directory",
                expected_mode=0o700,
                require_nonempty=False,
            )
        )
    checks.append(
        inspect_path(
            REAL_CONFIG_PATH,
            kind="file",
            expected_mode=0o600,
            require_nonempty=True,
        )
    )
    secret_files = [
        PROVIDER_SECRET_ROOT / "administrative-password",
        *(ALLOCATION_SECRET_ROOT / allocation / "application-password" for allocation in EXPECTED_ALLOCATIONS),
        PROVIDER_SECRET_ROOT / "pki/ca.key",
        PROVIDER_SECRET_ROOT / "pki/server.key",
    ]
    public_files = [
        PROVIDER_SECRET_ROOT / "pki/ca.crt",
        PROVIDER_SECRET_ROOT / "pki/server.crt",
    ]
    for path in secret_files:
        checks.append(
            inspect_path(path, kind="file", expected_mode=0o600, require_nonempty=True)
        )
    for path in public_files:
        checks.append(
            inspect_path(path, kind="file", expected_mode=0o644, require_nonempty=True)
        )
    return tuple(checks)


def inspect_backup_target(config: BackupConfig, repo_root: pathlib.Path = REPO_ROOT) -> BackupCheck:
    path = config.host_root
    blockers: list[str] = []
    warnings: list[str] = []
    if _path_under(path, SECRET_ROOT):
        blockers.append("Backupziel darf nicht unter /secrets liegen")
    if _path_under(path, repo_root):
        blockers.append("Backupziel darf nicht im Git-Repository liegen")
    for forbidden_root in (pathlib.Path("/var/lib/lxc"), pathlib.Path("/var/lib/vz/private")):
        if _path_under(path, forbidden_root):
            blockers.append("Backupziel darf nicht innerhalb eines LXC-Dateisystems liegen")
    try:
        info = path.lstat()
    except FileNotFoundError:
        blockers.append(f"Backupziel fehlt: {path}")
        return BackupCheck(path, "KONFLIKT", None, tuple(blockers), tuple(warnings))
    if stat.S_ISLNK(info.st_mode):
        blockers.append("Backupziel darf kein Symlink sein")
    elif not stat.S_ISDIR(info.st_mode):
        blockers.append("Backupziel muss ein Verzeichnis sein")
    if not os.access(path, os.W_OK):
        blockers.append("Backupziel ist für den späteren Root-Prozess nicht schreibbar")
    free_bytes: int | None = None
    if not blockers or stat.S_ISDIR(info.st_mode):
        try:
            free_bytes = shutil.disk_usage(path).free
        except OSError as exc:
            blockers.append(f"freier Speicher des Backupziels ist nicht lesbar: {exc}")
    if free_bytes is not None and free_bytes < config.minimum_free_gib * 1024**3:
        blockers.append(
            f"Backupziel besitzt weniger als die konfigurierten {config.minimum_free_gib} GiB freien Speicher"
        )
    if not config.protection_confirmed:
        blockers.append("Schutz oder Verschlüsselung des Backupziels ist nicht bestätigt")
    return BackupCheck(
        path=path,
        state="OK" if not blockers else "KONFLIKT",
        free_bytes=free_bytes,
        blockers=tuple(blockers),
        warnings=tuple(warnings),
    )


def read_git_commit(repo_root: pathlib.Path = REPO_ROOT) -> str:
    git_entry = repo_root / ".git"
    if git_entry.is_file():
        content = git_entry.read_text(encoding="utf-8").strip()
        if not content.startswith("gitdir: "):
            return "unbekannt"
        git_dir = (repo_root / content.removeprefix("gitdir: ")).resolve()
    else:
        git_dir = git_entry
    try:
        head = (git_dir / "HEAD").read_text(encoding="ascii").strip()
    except OSError:
        return "unbekannt"
    if re.fullmatch(r"[0-9a-f]{40}", head):
        return head
    if not head.startswith("ref: "):
        return "unbekannt"
    reference = head.removeprefix("ref: ")
    ref_path = git_dir / reference
    try:
        value = ref_path.read_text(encoding="ascii").strip()
        if re.fullmatch(r"[0-9a-f]{40}", value):
            return value
    except OSError:
        pass
    try:
        packed = (git_dir / "packed-refs").read_text(encoding="ascii")
    except OSError:
        return "unbekannt"
    for line in packed.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1] == reference and re.fullmatch(r"[0-9a-f]{40}", fields[0]):
            return fields[0]
    return "unbekannt"


def _format_bytes(value: int | None) -> str:
    if value is None:
        return "unbekannt"
    return f"{value / 1024**3:.1f} GiB"


def build_plan(
    config: DeploymentConfig,
    matrix: VersionMatrix,
    proxmox: ProxmoxState,
    secret_checks: Sequence[PathCheck],
    backup: BackupCheck,
    git_commit: str,
) -> PlanReport:
    report = PlanReport()
    report.warnings.extend(proxmox.warnings)
    report.blockers.extend(proxmox.blockers)
    report.warnings.extend(backup.warnings)
    report.blockers.extend(backup.blockers)
    for check in secret_checks:
        if check.conflict:
            report.blockers.append(f"{check.path}: {check.conflict}")
    for allocation in config.allocations:
        if not allocation.allowed_client_cidrs:
            report.blockers.append(
                f"Allocation {allocation.allocation_id}: leere Client-Allowlist blockiert Remote-Readiness"
            )
    if not config.lxc.dns_servers:
        report.blockers.append(
            "lxc.dns_servers ist leer; der Planer errät keinen deployment-spezifischen DNS-Server"
        )

    report.add_section(
        "REPOSITORY UND MATRIX",
        [
            f"Git-Commit: {git_commit}",
            f"Matrix-Stichtag: {matrix.checked_at}",
            "PostgreSQL: Major 18, initial dokumentiert 18.4, Policy latest-stable-18.x",
            "Gitea: 1.27.1, PostgreSQL-Anforderung >=12",
            "OpenBao: 2.6.1, PostgreSQL-Anforderung >=9.5, Storage postgresql",
            "Semaphore UI: 2.18.29, Datenbankbackend postgres, keine hier festgelegte Maximalversion",
            "Node-RED: 5.0.4, Node.js-Referenz 24, Nutzung flow_application_data_only",
            "Matrix ist offline und führt keine Onlineprüfung oder Installation aus.",
        ],
    )
    report.add_section(
        "PROXMOX",
        [
            f"Plattformstatus: {proxmox.pve_version}",
            f"VMID: {proxmox.vmid if proxmox.vmid is not None else 'unaufgelöst'} ({proxmox.vmid_source})",
            "Hostname: postgresql-main",
            f"Template: {proxmox.template or 'unaufgelöst'}",
            f"Storage: {proxmox.storage or 'unaufgelöst'} ({proxmox.storage_source})",
            f"Storage frei: {_format_bytes(proxmox.storage_available_bytes)}",
            f"Bridge: {proxmox.bridge or 'unaufgelöst'} ({proxmox.bridge_source})",
            f"Ressourcen: {config.lxc.cores} vCPU, {config.lxc.memory_mib} MiB RAM, {config.lxc.swap_mib} MiB Swap, {config.lxc.disk_gib} GiB Root-Disk",
            "Betriebsform: eigener unprivilegierter Ubuntu-26.04-LTS-LXC, amd64/x86_64, nesting aktiviert",
            "Docker/Podman: nicht verwendet",
        ],
    )
    report.add_section(
        "NETZWERK",
        [
            f"Provider-IP: {config.lxc.ipv4_interface}",
            f"FQDN: {config.provider.fqdn}",
            f"Gateway: {config.lxc.gateway}",
            "DNS-Server: "
            + (", ".join(map(str, config.lxc.dns_servers)) or "LEER / BLOCKER"),
            f"Listenerziel: {config.lxc.ipv4_interface.ip} (kein 0.0.0.0)",
            "Keine ungefragte Netzwerkerkennung oder Erreichbarkeitsprobe.",
            *(
                f"{allocation.allocation_id} Client-Allowlist: "
                + (", ".join(map(str, allocation.allowed_client_cidrs)) or "LEER")
                for allocation in config.allocations
            ),
        ],
    )
    report.add_section(
        "POSTGRESQL-ZIELVERTRAG",
        [
            "Paketquelle: offizielle Ubuntu-26.04-Quellen; keine PGDG-Quelle",
            "Paket: postgresql-18",
            "Version: aktuelle stabile 18.x-Version; kein automatischer Wechsel auf PostgreSQL 19",
            "Paketverfügbarkeit: vor Installation gegen die offiziellen Ubuntu-Quellen erneut prüfen",
            "Administration: lokal über Unix-Socket und Peer-Authentifizierung",
            "Superuser: kein gespeichertes Standardkennwort und keine Remote-Anmeldung",
            "password_encryption: scram-sha-256",
            "Remotezugriff: ausschließlich TLS, konkrete Provideradresse und allocation-eigene hostssl-Regeln",
            "Authentifizierung: ausschließlich scram-sha-256",
            "Anwendungsrechte: LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION",
            "application_managed: Objekterzeugung ausschließlich in der eigenen logischen Datenbank",
            "PUBLIC: keine Consumer-übergreifenden Anwendungsobjekte; Detailkonfiguration folgt separat",
            f"TLS-Anforderung: Serverzertifikat muss {config.provider.fqdn} enthalten",
            "TLS-CA: dediziert, nicht öffentliches ACME, Erzeugung nur nach eigener Freigabe",
            "Kein automatischer Zugriff auf OPNsense.",
        ],
    )

    allocation_lines: list[str] = []
    for allocation in config.allocations:
        application = matrix.applications[allocation.allocation_id]
        version = application["version"]
        secret_path = ALLOCATION_SECRET_ROOT / allocation.allocation_id / "application-password"
        backup_path = backup.path / PROVIDER_INSTANCE_ID / allocation.allocation_id
        allocation_lines.extend(
            [
                f"[{allocation.allocation_id}]",
                f"  Datenbankname: {allocation.database_name}",
                f"  Anwendungsversion: {version}",
                f"  Anwendungsidentität: {allocation.application_identity}",
                "  Schema-Lebenszyklus: application_managed",
                "  Client-Allowlist: "
                + (", ".join(map(str, allocation.allowed_client_cidrs)) or "LEER / BLOCKER"),
                f"  Secret-Referenz: {secret_path}",
                f"  Backupziel geplant: {backup_path}",
            ]
        )
        if allocation.allocation_id == "openbao":
            allocation_lines.append(
                "  Hinweis: PostgreSQL ist deployment-spezifisch gewählt; Sensitivität hoch; dedizierte Instanz bleibt möglich."
            )
        if allocation.allocation_id == "nodered":
            allocation_lines.append(
                "  Hinweis: nur relationale Flow-Anwendungsdaten; kein interner Node-RED-Storage, keine Flowdateien, Credentials oder Context."
            )
            allocation_lines.append(
                "  Folgeentscheidung: konkreten PostgreSQL-Node oder eigenen Flow-Vertrag auswählen."
            )
    report.add_section("ALLOCATIONS", allocation_lines)

    secret_lines = [
        "Der Planer liest keine Secretwerte und gibt keine Inhalts-Hashes aus.",
        "Zielmetadaten: Verzeichnisse root:root 0700, Passwortdateien und private Schlüssel root:root 0600.",
        "Temporärer späterer Transfer: /run/ralf-database-provision auf tmpfs, root:root 0700; Dateien 0600; sofortige Entfernung.",
    ]
    secret_lines.extend(
        f"{check.path}: {check.state}; {check.metadata}" for check in secret_checks
    )
    report.add_section("SECRETS UND TLS-METADATEN", secret_lines)

    report.add_section(
        "BACKUP",
        [
            f"Host-Root: {backup.path}",
            f"Status: {backup.state}",
            f"Freier Speicher: {_format_bytes(backup.free_bytes)}",
            f"Konfiguriertes Minimum: {config.backup.minimum_free_gib} GiB",
            f"Schutz bestätigt: {'ja' if config.backup.protection_confirmed else 'nein'}",
            "Format: logisches PostgreSQL-Custom-Format pro Allocation (pg_dump --format=custom)",
            "Transport: später vom LXC zum Proxmox-Host streamen; kein dauerhafter Backup-Mount im LXC",
            "Zieldateien: root:root 0600",
            "Keine automatische Retention oder Löschung in diesem Schritt.",
        ],
    )
    report.add_section("GEPLANTE SPÄTERE MUTATIONEN", list(MUTATION_PLAN))
    report.add_section("AUSDRÜCKLICH NICHT ENTHALTEN", list(EXCLUDED_SCOPE))
    return report


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read-only Deploymentplaner für postgresql-main"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan", help="read-only Plan erzeugen")
    plan.add_argument("--config", required=True, type=pathlib.Path)
    return parser


def run_plan(
    config_path: pathlib.Path,
    *,
    runner: CommandRunner | None = None,
    require_real_path: bool = True,
    matrix_path: pathlib.Path = VERSION_MATRIX_PATH,
) -> tuple[int, str]:
    if require_real_path and config_path.absolute() != REAL_CONFIG_PATH:
        raise ConfigurationError(
            f"reale Deploymentkonfiguration muss exakt {REAL_CONFIG_PATH} sein; das Repository-Beispiel wird nicht verwendet"
        )
    if require_real_path:
        ensure_no_symlink_components(config_path, SECRET_ROOT)
    config = load_config(config_path)
    matrix = load_version_matrix(matrix_path)
    proxmox = collect_proxmox_state(config, runner or CommandRunner())
    secrets = inspect_secret_contract()
    backup = inspect_backup_target(config.backup)
    report = build_plan(config, matrix, proxmox, secrets, backup, read_git_commit())
    rendered = report.render()
    return (3 if report.blockers else 0), rendered


def main(argv: Sequence[str] | None = None) -> int:
    parser = create_parser()
    args = parser.parse_args(argv)
    if args.command != "plan":
        parser.error("nur der read-only Modus plan ist verfügbar")
    try:
        code, output = run_plan(args.config)
    except PlannerError as exc:
        print(f"PLAN_ERROR: {exc}", file=sys.stderr)
        return 2
    print(output, end="")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
