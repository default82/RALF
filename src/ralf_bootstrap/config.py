"""Small, non-secret configuration reader for the Bootstrap service."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import tomllib

from .storage import DEFAULT_DATABASE_PATH

DEFAULT_CONFIG_PATH = Path("/etc/ralf/bootstrap/config.toml")


class ConfigError(ValueError):
    """Raised when the non-secret Bootstrap configuration is invalid."""


@dataclass(frozen=True)
class BootstrapConfig:
    database_path: Path = DEFAULT_DATABASE_PATH


def load_config(path: Path | str | None = None) -> BootstrapConfig:
    """Load configuration without creating files or directories.

    A missing file keeps the application usable with its documented default.
    A present but malformed or ambiguous file fails explicitly.
    """

    config_path = Path(path or os.environ.get("RALF_BOOTSTRAP_CONFIG", DEFAULT_CONFIG_PATH))
    if not config_path.exists():
        return BootstrapConfig()
    try:
        with config_path.open("rb") as stream:
            data = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ConfigError(f"Konfiguration konnte nicht gelesen werden: {config_path}") from exc

    if set(data) - {"storage"}:
        raise ConfigError("Ungültige Konfiguration: nur der Abschnitt [storage] ist erlaubt.")
    storage = data.get("storage", {})
    if not isinstance(storage, dict) or set(storage) - {"database_path"}:
        raise ConfigError("Ungültige Konfiguration im Abschnitt [storage].")
    database_path = storage.get("database_path", str(DEFAULT_DATABASE_PATH))
    if not isinstance(database_path, str) or not database_path.startswith("/"):
        raise ConfigError("storage.database_path muss ein absoluter Pfad sein.")
    return BootstrapConfig(database_path=Path(database_path))
