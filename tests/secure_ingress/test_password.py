from __future__ import annotations

from pathlib import Path
import subprocess

import pytest


VALID_HASH = (
    "$argon2id$v=19$m=47104,t=1,p=1$"
    "QUFBQUFBQUFBQUFBQUFBQQ$QkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkI"
)


def test_password_is_only_sent_on_stdin(ingress_module, monkeypatch):
    password = "unique-memory-only-password"
    calls = []
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))

    def run(argv, **kwargs):
        calls.append((argv, kwargs))
        return subprocess.CompletedProcess(argv, 0, VALID_HASH + "\n", "")

    monkeypatch.setattr(ingress_module.subprocess, "run", run)
    assert ingress_module.hash_password("/tmp/caddy", password) == VALID_HASH
    assert len(calls) == 1
    argv, kwargs = calls[0]
    assert argv == ["/tmp/caddy", "hash-password", "--algorithm", "argon2id"]
    assert "--plaintext" not in argv
    assert all(password not in argument for argument in argv)
    assert kwargs["input"] == password + "\n"
    assert password not in "\n".join(f"{key}={value}" for key, value in kwargs["env"].items())
    assert kwargs["capture_output"] is True


@pytest.mark.parametrize(
    "output",
    [
        "",
        "\n",
        VALID_HASH,
        VALID_HASH + "\nwarning\n",
        "warning\n" + VALID_HASH + "\n",
        " " + VALID_HASH + "\n",
        "$2a$14$abcdefghijklmnopqrstuvwxyz\n",
        "plaintext-password\n",
    ],
)
def test_invalid_hash_output_is_rejected(ingress_module, output):
    with pytest.raises(ingress_module.IngressError):
        ingress_module.validate_argon2id_hash(output)


def test_short_or_multiline_password_is_rejected_before_caddy(
    ingress_module, monkeypatch
):
    called = False

    def validate_binary(value):
        nonlocal called
        called = True
        return Path(value)

    monkeypatch.setattr(ingress_module, "validate_caddy_binary", validate_binary)
    for password in ("short", "sixteen-characters\nmore", "sixteen-characters\x00"):
        with pytest.raises(ingress_module.IngressError):
            ingress_module.hash_password("/tmp/caddy", password)
    assert called is False


def test_caddy_failure_is_generic_and_has_no_secret(ingress_module, monkeypatch):
    password = "unique-memory-only-password"
    monkeypatch.setattr(ingress_module, "validate_caddy_binary", lambda value: Path(value))
    monkeypatch.setattr(
        ingress_module.subprocess,
        "run",
        lambda argv, **kwargs: subprocess.CompletedProcess(argv, 9, "", password),
    )
    with pytest.raises(ingress_module.IngressError) as error:
        ingress_module.hash_password("/tmp/caddy", password)
    assert password not in str(error.value)


def test_stdin_reader_accepts_one_terminal_newline(ingress_module, monkeypatch):
    password = "unique-memory-only-password"

    class Input:
        class Buffer:
            @staticmethod
            def read(limit):
                assert limit == 4097
                return (password + "\n").encode()

        buffer = Buffer()

    monkeypatch.setattr(ingress_module.sys, "stdin", Input())
    assert ingress_module.read_password_from_stdin() == password


@pytest.mark.parametrize("option", ["--password", "--password-env", "--hash"])
def test_cli_does_not_offer_secret_arguments(ingress_module, option):
    parser = ingress_module.build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args(
            [
                "render",
                "--config",
                "provider.toml",
                "--caddy",
                "/tmp/caddy",
                "--output",
                "/tmp/Caddyfile",
                option,
                "forbidden",
            ]
        )
