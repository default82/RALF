from __future__ import annotations

from pathlib import Path

import pytest


def write_config(
    path: Path,
    *,
    fqdn: str = "ralf.home.arpa",
    cidrs: str = '"10.10.0.0/16"',
    username: str = "ralf-admin",
    root_extra: str = "",
    site_extra: str = "",
    auth_extra: str = "",
) -> Path:
    path.write_text(
        "schema_version = 1\n"
        'provider = "caddy"\n'
        f"{root_extra}"
        "\n[site]\n"
        f'fqdn = "{fqdn}"\n'
        f"allowed_cidrs = [{cidrs}]\n"
        f"{site_extra}"
        "\n[authentication]\n"
        f'username = "{username}"\n'
        f"{auth_extra}",
        encoding="utf-8",
    )
    return path


def test_valid_model_with_ipv4_and_ipv6(ingress_module, tmp_path):
    path = write_config(
        tmp_path / "provider.toml",
        fqdn="node.xn--example-ova.home.arpa",
        cidrs='"10.10.0.0/16", "192.168.50.0/24", "fd00:1234::/64"',
        username="Admin_01.test",
    )
    config = ingress_module.load_provider_config(path)
    assert config.schema_version == 1
    assert config.provider == "caddy"
    assert config.fqdn == "node.xn--example-ova.home.arpa"
    assert config.allowed_cidrs == (
        "10.10.0.0/16",
        "192.168.50.0/24",
        "fd00:1234::/64",
    )
    assert config.username == "Admin_01.test"


@pytest.mark.parametrize(
    "fqdn",
    [
        "",
        "single",
        "RALF.home.arpa",
        "https://ralf.home.arpa",
        "ralf.home.arpa:443",
        "ralf.home.arpa/path",
        "127.0.0.1",
        "*.home.arpa",
        "ralf.home.arpa.",
        "-ralf.home.arpa",
        "ralf-.home.arpa",
        f"{'a' * 64}.home.arpa",
        f"{'a' * 63}.{'b' * 63}.{'c' * 63}.{'d' * 62}.arpa",
        "rälf.home.arpa",
        "localhost",
    ],
)
def test_invalid_fqdn_is_rejected(ingress_module, tmp_path, fqdn):
    path = write_config(tmp_path / "provider.toml", fqdn=fqdn)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.load_provider_config(path)


@pytest.mark.parametrize(
    "cidrs",
    [
        "",
        '"10.10.1.1/16"',
        '"10.10.0.0/16", "10.10.0.0/16"',
        '"0.0.0.0/0"',
        '"::/0"',
        '"224.0.0.0/4"',
        '"ff00::/8"',
        '"0.0.0.0/32"',
        '"::/128"',
        '"private_ranges"',
        '"10.10.0.1"',
        "123",
    ],
)
def test_invalid_cidr_allowlist_is_rejected(ingress_module, tmp_path, cidrs):
    path = write_config(tmp_path / "provider.toml", cidrs=cidrs)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.load_provider_config(path)


@pytest.mark.parametrize(
    "username",
    [
        "",
        "ralf admin",
        "ralf:admin",
        "ralf\\nadmin",
        "ralf\\tadmin",
        "_admin",
        "a" * 65,
        "ädmin",
    ],
)
def test_invalid_username_is_rejected(ingress_module, tmp_path, username):
    path = write_config(tmp_path / "provider.toml", username=username)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.load_provider_config(path)


@pytest.mark.parametrize(
    ("kwargs", "needle"),
    [
        ({"root_extra": 'unexpected = "x"\n'}, "unbekannt"),
        ({"site_extra": 'upstream = "127.0.0.1:9999"\n'}, "unbekannt"),
        ({"site_extra": 'tls_mode = "internal"\n'}, "unbekannt"),
        ({"auth_extra": 'password = "forbidden"\n'}, "unbekannt"),
        ({"auth_extra": 'hash = "forbidden"\n'}, "unbekannt"),
        ({"auth_extra": 'token = "forbidden"\n'}, "unbekannt"),
    ],
)
def test_unknown_or_secret_configuration_is_rejected(
    ingress_module, tmp_path, kwargs, needle
):
    path = write_config(tmp_path / "provider.toml", **kwargs)
    with pytest.raises(ingress_module.IngressError, match=needle):
        ingress_module.load_provider_config(path)


def test_schema_provider_and_table_types_are_exact(ingress_module, tmp_path):
    variants = (
        'schema_version = 2\nprovider = "caddy"\n[site]\nfqdn="a.example"\nallowed_cidrs=["127.0.0.1/32"]\n[authentication]\nusername="admin"\n',
        'schema_version = 1\nprovider = "other"\n[site]\nfqdn="a.example"\nallowed_cidrs=["127.0.0.1/32"]\n[authentication]\nusername="admin"\n',
        'schema_version = true\nprovider = "caddy"\n[site]\nfqdn="a.example"\nallowed_cidrs=["127.0.0.1/32"]\n[authentication]\nusername="admin"\n',
    )
    for index, content in enumerate(variants):
        path = tmp_path / f"bad-{index}.toml"
        path.write_text(content, encoding="utf-8")
        with pytest.raises(ingress_module.IngressError):
            ingress_module.load_provider_config(path)


def test_example_contains_only_non_secret_supported_keys(ingress_module):
    path = Path(__file__).parents[2] / "deploy/secure-ingress/caddy/provider.example.toml"
    config = ingress_module.load_provider_config(path)
    assert config.fqdn == "ralf.home.arpa"
    lowered = path.read_text(encoding="utf-8").lower()
    for forbidden in ("password", "passwort", "hash", "token", "private", "upstream"):
        assert forbidden not in lowered
