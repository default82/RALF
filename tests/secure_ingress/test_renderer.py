from __future__ import annotations

import os
from pathlib import Path
import stat

import pytest


HASH = (
    "$argon2id$v=19$m=47104,t=1,p=1$"
    "QUFBQUFBQUFBQUFBQUFBQQ$QkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI"
)


def provider(ingress_module):
    return ingress_module.ProviderConfig(
        schema_version=1,
        provider="caddy",
        fqdn="ralf.home.arpa",
        allowed_cidrs=("10.10.0.0/16", "fd00:1234::/64"),
        username="ralf-admin",
    )


def test_production_render_is_deterministic_and_fixed(ingress_module):
    config = provider(ingress_module)
    first = ingress_module.render_caddyfile(config, HASH)
    second = ingress_module.render_caddyfile(config, HASH)
    assert first == second
    assert first.startswith("{\n\tadmin off\n\tpersist_config off\n\tskip_install_trust\n}")
    assert first.count("ralf.home.arpa {") == 1
    assert "@outside not remote_ip 10.10.0.0/16 fd00:1234::/64" in first
    assert 'basic_auth argon2id "RALF Bootstrap"' in first
    assert f"ralf-admin {HASH}" in first
    assert first.count("reverse_proxy 127.0.0.1:8080") == 1
    assert "auto_https" not in first
    assert "\tbind " not in first
    for header in (
        "-Authorization",
        "-Proxy-Authorization",
        "-Forwarded",
        "-X-Real-IP",
        "X-RALF-Authenticated-User {http.auth.user.id}",
    ):
        assert f"header_up {header}" in first
    assert "request_header -X-RALF-*" in first


@pytest.mark.parametrize(
    "forbidden",
    [
        "0.0.0.0",
        "private_ranges",
        "client_ip",
        "trusted_proxies",
        "tls_insecure_skip_verify",
        "on_demand_tls",
        "acme_dns",
        "forward_auth",
        "\n\tadmin 127.0.0.1:2019",
        "localhost:8080",
        "{$SECRET}",
        "\nimport other",
        "$2a$",
    ],
)
def test_forbidden_content_is_rejected(ingress_module, forbidden):
    config = provider(ingress_module)
    rendered = ingress_module.render_caddyfile(config, HASH)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.validate_rendered_contract(
            rendered + "\n" + forbidden, config, HASH
        )


def test_test_overrides_are_loopback_only_and_not_exposed_by_cli(ingress_module):
    config = provider(ingress_module)
    overrides = ingress_module.RenderOverrides(https_port=18443, upstream_port=18080)
    rendered = ingress_module.render_caddyfile(config, HASH, overrides)
    assert "https://ralf.home.arpa:18443 {" in rendered
    assert "\tbind 127.0.0.1" in rendered
    assert "reverse_proxy 127.0.0.1:18080" in rendered
    assert "auto_https disable_redirects" in rendered
    parser = ingress_module.build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args(
            [
                "render",
                "--config",
                "provider.toml",
                "--caddy",
                "caddy",
                "--output",
                "Caddyfile",
                "--https-port",
                "18443",
            ]
        )


def test_plan_is_read_only_and_contains_no_hash(ingress_module, capsys):
    ingress_module.print_plan(provider(ingress_module))
    output = capsys.readouterr().out
    assert "ralf.home.arpa" in output
    assert "10.10.0.0/16" in output
    assert "ralf-admin" in output
    assert "127.0.0.1:8080" in output
    assert "Kennworthash: noch nicht erzeugt" in output
    assert "$argon2" not in output


def test_secure_atomic_output_and_mode(ingress_module, tmp_path, monkeypatch):
    config = provider(ingress_module)
    output = tmp_path / "Caddyfile"
    observed = {}
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))
    monkeypatch.setattr(ingress_module, "hash_password", lambda binary, password: HASH)

    def validate(binary, path, current_config, password_hash, overrides=None):
        observed["temporary_name"] = Path(path).name
        observed["temporary_mode"] = stat.S_IMODE(Path(path).stat().st_mode)
        assert current_config == config
        assert password_hash == HASH
        return {}

    monkeypatch.setattr(ingress_module, "validate_with_caddy", validate)
    result = ingress_module.write_validated_caddyfile(
        config, tmp_path / "caddy", output, "a-secure-password-value"
    )
    assert result == output
    assert output.is_file() and not output.is_symlink()
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    assert observed["temporary_name"].startswith(".ralf-caddy.")
    assert observed["temporary_mode"] == 0o600
    assert "a-secure-password-value" not in output.read_text(encoding="utf-8")
    assert not list(tmp_path.glob(".ralf-caddy.*"))


def test_validation_failure_leaves_no_output_or_temporary_file(
    ingress_module, tmp_path, monkeypatch
):
    config = provider(ingress_module)
    output = tmp_path / "Caddyfile"
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))
    monkeypatch.setattr(ingress_module, "hash_password", lambda binary, password: HASH)

    def fail(*args, **kwargs):
        raise ingress_module.IngressError("validation failed")

    monkeypatch.setattr(ingress_module, "validate_with_caddy", fail)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.write_validated_caddyfile(
            config, tmp_path / "caddy", output, "a-secure-password-value"
        )
    assert not output.exists()
    assert not list(tmp_path.glob(".ralf-caddy.*"))


@pytest.mark.parametrize("kind", ["missing-parent", "existing", "symlink", "stdout"])
def test_unsafe_output_paths_are_rejected(ingress_module, tmp_path, monkeypatch, kind):
    config = provider(ingress_module)
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))
    monkeypatch.setattr(ingress_module, "hash_password", lambda binary, password: HASH)
    monkeypatch.setattr(ingress_module, "validate_with_caddy", lambda *args, **kwargs: {})
    if kind == "missing-parent":
        output = tmp_path / "missing" / "Caddyfile"
    elif kind == "existing":
        output = tmp_path / "Caddyfile"
        output.write_text("existing", encoding="utf-8")
    elif kind == "symlink":
        target = tmp_path / "target"
        target.write_text("target", encoding="utf-8")
        output = tmp_path / "Caddyfile"
        output.symlink_to(target)
    else:
        output = Path("-")
    with pytest.raises(ingress_module.IngressError):
        ingress_module.write_validated_caddyfile(
            config, tmp_path / "caddy", output, "a-secure-password-value"
        )


def test_output_race_does_not_overwrite(ingress_module, tmp_path, monkeypatch):
    config = provider(ingress_module)
    output = tmp_path / "Caddyfile"
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))
    monkeypatch.setattr(ingress_module, "hash_password", lambda binary, password: HASH)

    def create_racing_output(*args, **kwargs):
        output.write_text("racing writer", encoding="utf-8")
        return {}

    monkeypatch.setattr(ingress_module, "validate_with_caddy", create_racing_output)
    with pytest.raises(ingress_module.IngressError):
        ingress_module.write_validated_caddyfile(
            config, tmp_path / "caddy", output, "a-secure-password-value"
        )
    assert output.read_text(encoding="utf-8") == "racing writer"
    assert not list(tmp_path.glob(".ralf-caddy.*"))
