"""Safe, read-only collection of local Bootstrap status information."""

from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import re
import socket
import subprocess
from typing import Callable, Sequence

from . import __version__
from .storage import DEFAULT_DATABASE_PATH, inspect_database

SCHEMA_VERSION = 1
CommandRunner = Callable[[Sequence[str], float], subprocess.CompletedProcess[str]]
_INET_RE = re.compile(r"\binet\s+([0-9.]+)/\d+")


def _default_runner(
    args: Sequence[str], timeout: float
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
        shell=False,
    )


class StatusCollector:
    """Collect status using injectable files, commands, and system functions."""

    def __init__(
        self,
        *,
        os_release_path: Path = Path("/etc/os-release"),
        meminfo_path: Path = Path("/proc/meminfo"),
        root_path: Path = Path("/"),
        database_path: Path = DEFAULT_DATABASE_PATH,
        command_runner: CommandRunner = _default_runner,
        hostname_fn: Callable[[], str] = socket.gethostname,
        statvfs_fn: Callable[[Path], os.statvfs_result] = os.statvfs,
        uname_fn: Callable[[], os.uname_result] = os.uname,
    ) -> None:
        self.os_release_path = Path(os_release_path)
        self.meminfo_path = Path(meminfo_path)
        self.root_path = Path(root_path)
        self.database_path = Path(database_path)
        self.command_runner = command_runner
        self.hostname_fn = hostname_fn
        self.statvfs_fn = statvfs_fn
        self.uname_fn = uname_fn
        self.warnings: list[str] = []

    def collect(self) -> dict[str, object]:
        self.warnings = []
        os_data = self._read_os_release()
        network = self._network()
        resources = self._resources()
        services = self._services()
        sqlite_state = inspect_database(self.database_path)
        sqlite_warning = sqlite_state.pop("warning", None)
        if sqlite_warning:
            self.warnings.append(str(sqlite_warning))

        try:
            hostname = self.hostname_fn()
        except (OSError, UnicodeError):
            hostname = None
            self.warnings.append("Hostname konnte nicht ermittelt werden.")
        try:
            architecture = self.uname_fn().machine
        except (OSError, AttributeError):
            architecture = None
            self.warnings.append("Architektur konnte nicht ermittelt werden.")

        return {
            "schema_version": SCHEMA_VERSION,
            "collected_at": datetime.now(timezone.utc).isoformat().replace(
                "+00:00", "Z"
            ),
            "bootstrap": {
                "version": __version__,
                "service": "ralf-bootstrap",
                "mode": "controller-local-state",
                "schema_version": SCHEMA_VERSION,
                "sqlite": sqlite_state,
            },
            "setup": {
                "status": "bootstrap_only",
                "bootstrap_status": "present",
                "model_runtime": "not_configured",
                "model": "not_configured",
                "model_webui": "not_configured",
                "privileged_installer": "not_configured",
            },
            "system": {
                "hostname": hostname,
                "os_id": os_data.get("ID"),
                "os_name": os_data.get("NAME"),
                "os_version": os_data.get("VERSION_ID") or os_data.get("VERSION"),
                "architecture": architecture,
            },
            "network": network,
            "resources": resources,
            "services": services,
            "components": [
                {"id": "bootstrap-status", "status": "running"},
                {"id": "model-runtime", "status": "not_configured"},
                {"id": "model", "status": "not_configured"},
                {"id": "model-webui", "status": "not_configured"},
                {"id": "privileged-installer", "status": "not_configured"},
            ],
            "warnings": list(self.warnings),
        }

    def _read_os_release(self) -> dict[str, str]:
        values: dict[str, str] = {}
        try:
            for line in self.os_release_path.read_text(encoding="utf-8").splitlines():
                if "=" not in line or line.startswith("#"):
                    continue
                key, value = line.split("=", 1)
                values[key] = value.strip().strip('"').strip("'")
        except (OSError, UnicodeError):
            self.warnings.append("Betriebssystemdaten aus /etc/os-release fehlen.")
        return values

    def _run(self, args: Sequence[str], *, timeout: float = 1.0) -> str | None:
        try:
            result = self.command_runner(args, timeout)
        except FileNotFoundError:
            self.warnings.append(f"Befehl nicht verfügbar: {args[0]}.")
            return None
        except subprocess.TimeoutExpired:
            self.warnings.append(f"Zeitüberschreitung bei {args[0]}.")
            return None
        except (OSError, ValueError):
            self.warnings.append(f"Statusabfrage fehlgeschlagen: {args[0]}.")
            return None
        output = (result.stdout or "")[:4096]
        if result.returncode != 0:
            self.warnings.append(f"Statusabfrage meldete einen Fehler: {args[0]}.")
            return output
        return output

    def _network(self) -> dict[str, object]:
        address_output = self._run(
            ["ip", "-4", "-o", "address", "show", "scope", "global"]
        )
        route_output = self._run(["ip", "-4", "route", "show", "default"])
        addresses = _INET_RE.findall(address_output or "")
        default_route: bool | None
        if route_output is None:
            default_route = None
        else:
            default_route = any(line.strip().startswith("default ") for line in route_output.splitlines())
        if address_output is None or route_output is None:
            state = "unknown"
        elif addresses and default_route:
            state = "configured"
        else:
            state = "degraded"
            self.warnings.append("IPv4-Adresse oder Default-Route fehlt.")
        return {
            "ipv4_addresses": addresses,
            "default_route": default_route,
            "status": state,
        }

    def _resources(self) -> dict[str, object]:
        root: dict[str, object] = {
            "total_bytes": None,
            "free_bytes": None,
            "used_bytes": None,
            "used_percent": None,
        }
        try:
            stat = self.statvfs_fn(self.root_path)
            total = stat.f_blocks * stat.f_frsize
            free = stat.f_bavail * stat.f_frsize
            used = max(total - stat.f_bfree * stat.f_frsize, 0)
            root = {
                "total_bytes": total,
                "free_bytes": free,
                "used_bytes": used,
                "used_percent": round((used / total) * 100, 2) if total else 0.0,
            }
        except (OSError, AttributeError, TypeError):
            self.warnings.append("Root-Dateisystem konnte nicht gelesen werden.")

        memory = self._read_meminfo()
        return {
            "root_filesystem": root,
            "memory": {
                "total_bytes": memory.get("MemTotal"),
                "available_bytes": memory.get("MemAvailable"),
            },
            "swap": {
                "total_bytes": memory.get("SwapTotal"),
                "free_bytes": memory.get("SwapFree"),
            },
        }

    def _read_meminfo(self) -> dict[str, int]:
        values: dict[str, int] = {}
        try:
            for line in self.meminfo_path.read_text(encoding="utf-8").splitlines():
                key, separator, raw = line.partition(":")
                if not separator:
                    continue
                parts = raw.strip().split()
                if not parts:
                    continue
                try:
                    value = int(parts[0])
                except ValueError:
                    continue
                if len(parts) > 1 and parts[1].lower() == "kb":
                    value *= 1024
                values[key] = value
        except (OSError, UnicodeError):
            self.warnings.append("Speicherinformationen aus /proc/meminfo fehlen.")
        for required in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
            if required not in values:
                self.warnings.append(f"Speicherwert fehlt: {required}.")
        return values

    def _services(self) -> dict[str, object]:
        output = self._run(["systemctl", "is-system-running"])
        if output is None:
            systemd = "unknown"
        elif output.strip() == "running":
            systemd = "running"
        else:
            systemd = output.strip() or "unknown"
        return {"systemd": systemd, "bootstrap": "running"}


def collect_status(**kwargs: object) -> dict[str, object]:
    """Convenience wrapper used by the application and tests."""

    return StatusCollector(**kwargs).collect()
