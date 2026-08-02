"""Strict, deterministic provider-contract catalog."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
from importlib.resources import files
from pathlib import Path
import tomllib

from .models import ValidationError, canonical_json, normalize_text, validate_identifier

CLAIM_CATEGORIES = frozenset(
    {"identity", "presence", "health", "capability", "security", "integration"}
)
CONTRACT_METHODS = frozenset({"manual", "imported_evidence", "connector", "local_probe"})
COMPLETING_METHODS = frozenset({"manual", "imported_evidence"})
SCOPE_CATEGORIES = frozenset(
    {
        "system_identity",
        "product_presence",
        "product_version",
        "service_status",
        "reverse_proxy_capabilities",
        "tls_strategy_summary",
        "authentication_capability_summary",
        "network_access_policy_summary",
        "header_policy_summary",
    }
)


@dataclass(frozen=True)
class ContractClaim:
    claim_id: str
    category: str
    title: str
    description: str
    required: bool
    accepted_methods: tuple[str, ...]
    freshness_seconds: int
    data_categories: tuple[str, ...]

    def as_dict(self) -> dict[str, object]:
        return {
            "claim_id": self.claim_id,
            "category": self.category,
            "title": self.title,
            "description": self.description,
            "required": self.required,
            "accepted_methods": list(self.accepted_methods),
            "freshness_seconds": self.freshness_seconds,
            "data_categories": list(self.data_categories),
        }


@dataclass(frozen=True)
class ProviderContract:
    contract_id: str
    contract_version: int
    provider_id: str
    capability_id: str
    display_name: str
    description: str
    freshness_seconds: int
    claims: tuple[ContractClaim, ...]
    integration_requirements: tuple[str, ...]
    contract_hash: str

    def as_dict(self) -> dict[str, object]:
        return {
            "contract_id": self.contract_id,
            "contract_version": self.contract_version,
            "provider_id": self.provider_id,
            "capability_id": self.capability_id,
            "display_name": self.display_name,
            "description": self.description,
            "freshness_seconds": self.freshness_seconds,
            "claims": [claim.as_dict() for claim in self.claims],
            "integration_requirements": list(self.integration_requirements),
            "contract_hash": self.contract_hash,
        }


@dataclass(frozen=True)
class ContractCatalog:
    schema_version: int
    catalog_version: int
    contracts: tuple[ProviderContract, ...]

    def get(self, contract_id: str, contract_version: int | None = None) -> ProviderContract:
        matches = [item for item in self.contracts if item.contract_id == contract_id]
        if contract_version is not None:
            matches = [item for item in matches if item.contract_version == contract_version]
        if len(matches) != 1:
            raise ValidationError("Unbekannter oder mehrdeutiger Providervertrag.")
        return matches[0]


def default_contracts_path() -> Path:
    return Path(
        str(files("ralf_bootstrap.controller.catalog_data").joinpath("provider_contracts.toml"))
    )


def load_contracts(path: Path | None = None) -> ContractCatalog:
    with Path(path or default_contracts_path()).open("rb") as stream:
        data = tomllib.load(stream)
    if set(data) != {"schema_version", "catalog_version", "contracts"}:
        raise ValidationError("Providervertragskatalog besitzt unbekannte oder fehlende Schluessel.")
    if data["schema_version"] != 1 or not isinstance(data["catalog_version"], int):
        raise ValidationError("Providervertragskatalog besitzt eine unbekannte Version.")
    contracts: list[ProviderContract] = []
    identities: set[tuple[str, int]] = set()
    for raw in data["contracts"]:
        expected = {
            "contract_id",
            "contract_version",
            "provider_id",
            "capability_id",
            "display_name",
            "description",
            "freshness_seconds",
            "claims",
            "integration_requirements",
        }
        if set(raw) != expected:
            raise ValidationError("Providervertrag besitzt unbekannte oder fehlende Felder.")
        contract_id = validate_identifier(raw["contract_id"], "contract_id")
        provider_id = validate_identifier(raw["provider_id"], "provider_id")
        capability_id = validate_identifier(raw["capability_id"], "capability_id")
        version = _positive_integer(raw["contract_version"], "contract_version")
        identity = (contract_id, version)
        if identity in identities:
            raise ValidationError("Providervertrag und Version muessen eindeutig sein.")
        identities.add(identity)
        freshness = _positive_integer(raw["freshness_seconds"], "freshness_seconds")
        claims = _load_claims(raw["claims"])
        required_groups = {
            "presence": any(c.required and c.category in {"identity", "presence", "health"} for c in claims),
            "compatibility": any(c.required and c.category in {"capability", "security"} for c in claims),
            "integration": any(c.required and c.category == "integration" for c in claims),
        }
        if not all(required_groups.values()):
            raise ValidationError("Providervertrag besitzt nicht alle erforderlichen Claim-Gruppen.")
        integration = tuple(raw["integration_requirements"])
        claim_ids = {claim.claim_id for claim in claims}
        if not integration or len(integration) != len(set(integration)):
            raise ValidationError("Integrationsanforderungen fehlen oder sind doppelt.")
        if any(item not in claim_ids for item in integration):
            raise ValidationError("Integrationsanforderung verweist auf eine unbekannte Claim-ID.")
        canonical = {
            "contract_id": contract_id,
            "contract_version": version,
            "provider_id": provider_id,
            "capability_id": capability_id,
            "display_name": normalize_text(raw["display_name"], "Anzeigename", maximum=160, required=True),
            "description": normalize_text(raw["description"], "Beschreibung", maximum=500, required=True),
            "freshness_seconds": freshness,
            "claims": [claim.as_dict() for claim in claims],
            "integration_requirements": list(integration),
        }
        digest = hashlib.sha256(canonical_json(canonical).encode("utf-8")).hexdigest()
        contracts.append(
            ProviderContract(
                contract_id,
                version,
                provider_id,
                capability_id,
                canonical["display_name"],  # type: ignore[arg-type]
                canonical["description"],  # type: ignore[arg-type]
                freshness,
                claims,
                integration,
                digest,
            )
        )
    contracts.sort(key=lambda item: (item.contract_id, item.contract_version))
    return ContractCatalog(data["schema_version"], data["catalog_version"], tuple(contracts))


def _load_claims(raw_claims: object) -> tuple[ContractClaim, ...]:
    if not isinstance(raw_claims, list) or not raw_claims:
        raise ValidationError("Providervertrag benoetigt Claims.")
    claims: list[ContractClaim] = []
    seen: set[str] = set()
    expected = {
        "claim_id",
        "category",
        "title",
        "description",
        "required",
        "accepted_methods",
        "freshness_seconds",
        "data_categories",
    }
    for raw in raw_claims:
        if not isinstance(raw, dict) or set(raw) != expected:
            raise ValidationError("Claim besitzt unbekannte oder fehlende Felder.")
        claim_id = validate_identifier(raw["claim_id"], "claim_id")
        if claim_id in seen:
            raise ValidationError("Claim-IDs muessen innerhalb eines Vertrags eindeutig sein.")
        seen.add(claim_id)
        category = str(raw["category"])
        methods = tuple(raw["accepted_methods"])
        data_categories = tuple(raw["data_categories"])
        if category not in CLAIM_CATEGORIES:
            raise ValidationError("Claim besitzt eine unbekannte Kategorie.")
        if not methods or len(methods) != len(set(methods)) or any(m not in CONTRACT_METHODS for m in methods):
            raise ValidationError("Claim besitzt unbekannte oder doppelte Verifikationsmethoden.")
        if not any(method in COMPLETING_METHODS for method in methods):
            raise ValidationError("M-040-Claim benoetigt eine manuelle oder importierte Methode.")
        if not data_categories or any(item not in SCOPE_CATEGORIES for item in data_categories):
            raise ValidationError("Claim besitzt unbekannte Datenkategorien.")
        if not isinstance(raw["required"], bool):
            raise ValidationError("Claim required muss boolesch sein.")
        claims.append(
            ContractClaim(
                claim_id,
                category,
                normalize_text(raw["title"], "Claim-Titel", maximum=160, required=True),
                normalize_text(raw["description"], "Claim-Beschreibung", maximum=500, required=True),
                raw["required"],
                methods,
                _positive_integer(raw["freshness_seconds"], "freshness_seconds"),
                data_categories,
            )
        )
    return tuple(claims)


def _positive_integer(value: object, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1 or value > 31536000:
        raise ValidationError(f"{field} muss eine positive, begrenzte Ganzzahl sein.")
    return value
