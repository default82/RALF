from __future__ import annotations

from pathlib import Path
import shlex


PROJECT_ROOT = Path(__file__).parents[2]
UNIT_PATH = PROJECT_ROOT / "deploy/bootstrap-status/ralf-bootstrap.service"


def unit_text() -> str:
    return UNIT_PATH.read_text(encoding="utf-8")


def directive(text: str, name: str) -> str:
    prefix = f"{name}="
    values = [line.removeprefix(prefix) for line in text.splitlines() if line.startswith(prefix)]
    assert len(values) == 1, (name, values)
    return values[0]


def exec_start_arguments(text: str) -> list[str]:
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if line.startswith("ExecStart="))
    command: list[str] = []
    for line in lines[start:]:
        value = line.removeprefix("ExecStart=").strip()
        continued = value.endswith("\\")
        command.append(value.removesuffix("\\").strip())
        if not continued:
            break
    return shlex.split(" ".join(command))


def test_gunicorn_exec_start_is_loopback_only_without_control_socket():
    text = unit_text()
    arguments = exec_start_arguments(text)

    assert arguments.count("--no-control-socket") == 1
    assert "--control-socket" not in arguments
    assert not any(argument.startswith("--control-socket=") for argument in arguments)
    assert arguments.count("--bind") == 1
    assert arguments[arguments.index("--bind") + 1] == "127.0.0.1:8080"
    assert arguments.count("--workers") == 1
    assert arguments[arguments.index("--workers") + 1] == "1"


def test_unit_allows_only_required_address_families_and_no_capabilities():
    text = unit_text()

    assert directive(text, "RestrictAddressFamilies").split() == [
        "AF_UNIX",
        "AF_INET",
        "AF_INET6",
        "AF_NETLINK",
    ]
    assert "AF_PACKET" not in text
    assert directive(text, "CapabilityBoundingSet") == ""
    assert directive(text, "AmbientCapabilities") == ""


def test_unit_keeps_unprivileged_identity_and_hardening():
    text = unit_text()
    expected = {
        "User": "ralf-bootstrap",
        "Group": "ralf-bootstrap",
        "NoNewPrivileges": "true",
        "PrivateTmp": "true",
        "PrivateDevices": "true",
        "ProtectHome": "true",
        "ProtectSystem": "strict",
        "ProtectKernelTunables": "true",
        "ProtectKernelModules": "true",
        "ProtectControlGroups": "true",
        "RestrictSUIDSGID": "true",
        "LockPersonality": "true",
    }

    for name, value in expected.items():
        assert directive(text, name) == value
    assert "Environment=HOME=" not in text
    assert "RuntimeDirectory=" not in text
    assert "ReadWritePaths=" not in text
