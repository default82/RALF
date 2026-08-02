"""Versioned capability and provider catalog loader."""

from __future__ import annotations

from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
import tomllib

from .models import (
    PROVIDER_LIFECYCLES,
    PROVIDER_READINESS,
    ValidationError,
    validate_identifier,
)


@dataclass(frozen=True)
class Capability:
    capability_id: str
    display_name: str
    description: str


@dataclass(frozen=True)
class ProviderCandidate:
    provider_id: str
    capability_id: str
    display_name: str
    product: str
    location: str
    lifecycle: str
    readiness: str


@dataclass(frozen=True)
class Catalog:
    schema_version: int
    catalog_version: int
    capabilities: tuple[Capability, ...]
    providers: tuple[ProviderCandidate, ...]

    def capability_ids(self) -> frozenset[str]:
        return frozenset(item.capability_id for item in self.capabilities)


def default_catalog_path() -> Path:
    return Path(str(files("ralf_bootstrap.controller.catalog_data").joinpath("capabilities.toml")))


def load_catalog(path: Path | None = None) -> Catalog:
    source = path or default_catalog_path()
    with Path(source).open("rb") as stream:
        data = tomllib.load(stream)
    if set(data) != {"schema_version", "catalog_version", "capabilities", "providers"}:
        raise ValidationError("Fähigkeitskatalog besitzt unbekannte oder fehlende Schlüssel.")
    if data["schema_version"] != 1 or not isinstance(data["catalog_version"], int):
        raise ValidationError("Fähigkeitskatalog besitzt eine unbekannte Version.")
    capabilities: list[Capability] = []
    seen: set[str] = set()
    for raw in data["capabilities"]:
        if set(raw) != {"id", "display_name", "description"}:
            raise ValidationError("Fähigkeit besitzt unbekannte Schlüssel.")
        capability_id = validate_identifier(raw["id"], "capability_id")
        if capability_id in seen:
            raise ValidationError("Fähigkeitskatalog enthält doppelte IDs.")
        seen.add(capability_id)
        capabilities.append(Capability(capability_id, raw["display_name"], raw["description"]))
    providers: list[ProviderCandidate] = []
    provider_ids: set[str] = set()
    for raw in data["providers"]:
        expected = {"id", "capability_id", "display_name", "product", "location", "lifecycle", "readiness"}
        if set(raw) != expected:
            raise ValidationError("Providerkandidat besitzt unbekannte Schlüssel.")
        provider_id = validate_identifier(raw["id"], "provider_id")
        capability_id = validate_identifier(raw["capability_id"], "capability_id")
        if provider_id in provider_ids or capability_id not in seen:
            raise ValidationError("Providerkandidat ist doppelt oder verweist auf eine unbekannte Fähigkeit.")
        if raw["lifecycle"] not in PROVIDER_LIFECYCLES or raw["readiness"] not in PROVIDER_READINESS:
            raise ValidationError("Providerkandidat besitzt unbekannte Statuswerte.")
        provider_ids.add(provider_id)
        providers.append(
            ProviderCandidate(
                provider_id,
                capability_id,
                raw["display_name"],
                raw["product"],
                raw["location"],
                raw["lifecycle"],
                raw["readiness"],
            )
        )
    return Catalog(data["schema_version"], data["catalog_version"], tuple(capabilities), tuple(providers))
