from __future__ import annotations

from pathlib import Path

import pytest

from ralf_bootstrap.config import ConfigError, DEFAULT_CONFIG_PATH, load_config


def test_missing_config_uses_default_without_creating_file(tmp_path):
    path = tmp_path / "missing.toml"
    config = load_config(path)
    assert config.database_path == Path("/var/lib/ralf/bootstrap/state.db")
    assert not path.exists()


def test_valid_config_uses_alternative_database_path(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text('[storage]\ndatabase_path = "/tmp/test-state.db"\n', encoding="utf-8")
    assert load_config(path).database_path == Path("/tmp/test-state.db")


def test_invalid_toml_and_unknown_values_fail(tmp_path):
    malformed = tmp_path / "bad.toml"
    malformed.write_text("[storage\n", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(malformed)
    unknown = tmp_path / "unknown.toml"
    unknown.write_text("[network]\nbind = \"127.0.0.1\"\n", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(unknown)


def test_default_config_path_is_documented():
    assert str(DEFAULT_CONFIG_PATH) == "/etc/ralf/bootstrap/config.toml"
