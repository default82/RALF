from __future__ import annotations

from datetime import datetime
import os
import subprocess

from ralf_bootstrap.status import StatusCollector, _default_runner


class FakeStat:
    f_blocks = 100
    f_frsize = 4096
    f_bavail = 25
    f_bfree = 30


def runner_for(addresses=True, route=True, systemd="running"):
    def runner(args, timeout):
        assert timeout == 1.0
        if args[:2] == ["ip", "-4"] and "address" in args:
            output = "2: eth0    inet 192.0.2.10/24 scope global eth0\n" if addresses else ""
        elif args[:2] == ["ip", "-4"] and "route" in args:
            output = "default via 192.0.2.1 dev eth0\n" if route else ""
        elif args == ["systemctl", "is-system-running"]:
            output = f"{systemd}\n"
        else:
            raise AssertionError(args)
        return subprocess.CompletedProcess(list(args), 0, output, "")

    return runner


def collector(tmp_path, **kwargs):
    os_release = tmp_path / "os-release"
    os_release.write_text('ID=ubuntu\nNAME="Ubuntu"\nVERSION_ID="26.04"\n', encoding="utf-8")
    meminfo = tmp_path / "meminfo"
    meminfo.write_text(
        "MemTotal:       1024 kB\nMemAvailable:    512 kB\n"
        "SwapTotal:      256 kB\nSwapFree:        128 kB\n",
        encoding="utf-8",
    )
    return StatusCollector(
        os_release_path=os_release,
        meminfo_path=meminfo,
        database_path=tmp_path / "state.db",
        command_runner=kwargs.pop("command_runner", runner_for()),
        hostname_fn=lambda: "test-host",
        uname_fn=lambda: os.uname(),
        statvfs_fn=lambda _: FakeStat(),
        **kwargs,
    )


def test_collects_stable_status_and_converts_bytes(tmp_path):
    status = collector(tmp_path).collect()

    assert status["schema_version"] == 1
    assert status["system"]["os_id"] == "ubuntu"
    assert status["network"] == {
        "ipv4_addresses": ["192.0.2.10"],
        "default_route": True,
        "status": "configured",
    }
    assert status["resources"]["memory"]["total_bytes"] == 1024 * 1024
    assert status["resources"]["root_filesystem"]["total_bytes"] == 409600
    assert status["resources"]["root_filesystem"]["used_percent"] == 70.0
    datetime.fromisoformat(status["collected_at"].replace("Z", "+00:00"))
    assert status["collected_at"].endswith("Z")


def test_missing_os_and_meminfo_are_warnings(tmp_path):
    status = collector(tmp_path).collect()
    status_collector = collector(tmp_path)
    status_collector.os_release_path = tmp_path / "missing-os"
    status_collector.meminfo_path = tmp_path / "missing-meminfo"
    status = status_collector.collect()

    assert status["system"]["os_id"] is None
    assert status["resources"]["memory"]["total_bytes"] is None
    assert status["warnings"]


def test_missing_network_data_is_degraded(tmp_path):
    status = collector(tmp_path, command_runner=runner_for(False, False)).collect()
    assert status["network"]["status"] == "degraded"
    assert status["network"]["default_route"] is False


def test_missing_ipv4_or_default_route_is_degraded(tmp_path):
    no_address = collector(tmp_path, command_runner=runner_for(False, True)).collect()
    no_route = collector(tmp_path, command_runner=runner_for(True, False)).collect()
    assert no_address["network"]["ipv4_addresses"] == []
    assert no_address["network"]["status"] == "degraded"
    assert no_route["network"]["default_route"] is False
    assert no_route["network"]["status"] == "degraded"


def test_incomplete_meminfo_returns_null_values_and_warning(tmp_path):
    status_collector = collector(tmp_path)
    status_collector.meminfo_path.write_text("MemTotal: 10 kB\n", encoding="utf-8")
    status = status_collector.collect()
    assert status["resources"]["memory"]["total_bytes"] == 10 * 1024
    assert status["resources"]["memory"]["available_bytes"] is None
    assert status["resources"]["swap"]["total_bytes"] is None
    assert status["warnings"]


def test_missing_command_and_timeout_are_unknown_with_warnings(tmp_path):
    def missing(args, timeout):
        if args[0] == "systemctl":
            raise FileNotFoundError
        raise subprocess.TimeoutExpired(args, timeout)

    status = collector(tmp_path, command_runner=missing).collect()
    assert status["network"]["status"] == "unknown"
    assert status["services"]["systemd"] == "unknown"
    assert len(status["warnings"]) >= 3


def test_single_probe_failure_does_not_abort_collection(tmp_path):
    def broken(args, timeout):
        if args[0] == "systemctl":
            raise OSError("test")
        return runner_for()(args, timeout)

    status = collector(tmp_path, command_runner=broken).collect()
    assert status["services"]["systemd"] == "unknown"
    assert status["components"]


def test_commands_are_fixed_and_not_shell_mutations(tmp_path, monkeypatch):
    calls = []

    def fake_run(args, **kwargs):
        calls.append((args, kwargs))
        return subprocess.CompletedProcess(args, 0, "", "")

    monkeypatch.setattr("ralf_bootstrap.status.subprocess.run", fake_run)
    collector(tmp_path, command_runner=_default_runner).collect()

    assert calls
    assert [tuple(args) for args, _ in calls] == [
        ("ip", "-4", "-o", "address", "show", "scope", "global"),
        ("ip", "-4", "route", "show", "default"),
        ("systemctl", "is-system-running"),
    ]
    for args, kwargs in calls:
        assert kwargs["shell"] is False
        assert kwargs["timeout"] == 1.0
        assert args[0] in {"ip", "systemctl"}
