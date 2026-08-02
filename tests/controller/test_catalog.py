from ralf_bootstrap.controller.catalog import load_catalog
from ralf_bootstrap.controller.models import ValidationError


def test_catalog_is_versioned_complete_and_deterministic():
    first = load_catalog()
    second = load_catalog()
    assert first == second
    assert first.schema_version == first.catalog_version == 1
    assert first.capability_ids() == {
        "platform.virtualization", "platform.container", "network.firewall", "network.dns",
        "secure-ingress", "identity-provider", "database.relational", "database.vector",
        "storage.file", "storage.object", "backup", "monitoring", "secrets-management",
        "model-runtime", "model", "model-webui",
    }
    local = next(item for item in first.providers if item.provider_id == "local-caddy-fallback")
    assert local.readiness == "experimental"


def test_catalog_rejects_unknown_keys(tmp_path):
    path = tmp_path / "bad.toml"
    path.write_text("schema_version=1\ncatalog_version=1\nunknown=true\ncapabilities=[]\nproviders=[]\n")
    try:
        load_catalog(path)
    except ValidationError:
        pass
    else:
        raise AssertionError("unknown catalog key accepted")
