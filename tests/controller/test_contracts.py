from __future__ import annotations

from pathlib import Path

import pytest

from ralf_bootstrap.controller.contracts import load_contracts
from ralf_bootstrap.controller.models import ValidationError


def test_opnsense_contract_is_deterministic_and_separates_claim_groups():
    first = load_contracts()
    second = load_contracts()
    assert first == second
    contract = first.get("secure-ingress.opnsense-caddy")
    assert contract.provider_id == "opnsense-caddy"
    assert contract.capability_id == "secure-ingress"
    assert len(contract.contract_hash) == 64
    assert {claim.category for claim in contract.claims} == {
        "identity", "presence", "health", "capability", "security", "integration"
    }
    assert all("manual" in claim.accepted_methods or "imported_evidence" in claim.accepted_methods for claim in contract.claims)
    assert all("10." not in claim.description and "http" not in claim.description for claim in contract.claims)


def test_unknown_contract_fields_and_methods_are_rejected(tmp_path):
    with pytest.raises(ValidationError, match="Unbekannter"):
        load_contracts().get("unknown.contract")
    with pytest.raises(ValidationError, match="Unbekannter"):
        load_contracts().get("secure-ingress.opnsense-caddy", 99)

    original = Path(load_contracts.__globals__["default_contracts_path"]()).read_text()
    bad_field = tmp_path / "bad-field.toml"
    bad_field.write_text(original.replace("catalog_version = 1", "catalog_version = 1\nunknown = true", 1))
    with pytest.raises(ValidationError, match="Schluessel"):
        load_contracts(bad_field)
    bad_method = tmp_path / "bad-method.toml"
    bad_method.write_text(original.replace('"manual", "imported_evidence", "connector"', '"manual", "magic"', 1))
    with pytest.raises(ValidationError, match="Verifikationsmethoden"):
        load_contracts(bad_method)


def test_duplicate_claim_unknown_category_and_bad_freshness_are_rejected(tmp_path):
    original = Path(load_contracts.__globals__["default_contracts_path"]()).read_text()
    duplicate = tmp_path / "duplicate.toml"
    duplicate.write_text(original.replace(
        'claim_id = "provider.caddy_is_present"',
        'claim_id = "provider.platform_is_opnsense"',
        1,
    ))
    with pytest.raises(ValidationError, match="Claim-IDs"):
        load_contracts(duplicate)
    category = tmp_path / "category.toml"
    category.write_text(original.replace('category = "identity"', 'category = "magic"', 1))
    with pytest.raises(ValidationError, match="Kategorie"):
        load_contracts(category)
    freshness = tmp_path / "freshness.toml"
    freshness.write_text(original.replace("freshness_seconds = 2592000", "freshness_seconds = 0", 1))
    with pytest.raises(ValidationError, match="positive"):
        load_contracts(freshness)
    version = tmp_path / "version.toml"
    version.write_text(original.replace("contract_version = 1", "contract_version = 0", 1))
    with pytest.raises(ValidationError, match="positive"):
        load_contracts(version)


def test_contract_change_changes_hash(tmp_path):
    original_path = Path(load_contracts.__globals__["default_contracts_path"]())
    changed = tmp_path / "changed.toml"
    changed.write_text(original_path.read_text().replace(
        "Read-only Vertrag fuer einen vorhandenen OPNsense-Caddy-Provider",
        "Geaenderter read-only Vertrag fuer einen vorhandenen OPNsense-Caddy-Provider",
    ))
    assert load_contracts().contracts[0].contract_hash != load_contracts(changed).contracts[0].contract_hash
