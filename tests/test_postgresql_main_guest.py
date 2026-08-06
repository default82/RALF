from __future__ import annotations

import fcntl
import hashlib
import json
import os
import pathlib
import sys
import tempfile
import types
import unittest
from unittest import mock

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.guest import (
    GuestProvisioner, load_guest_plan, render_hba, validate_hba,
)
from postgresql_main.models import ALLOCATION_IDS, ProvisioningError


class FakeRunner:
    def __init__(self, *, clusters: bytes = b"") -> None:
        self.clusters = clusters
        self.calls: list[tuple[list[str], bytes | None]] = []
        self.query_results: list[bytes] = []

    def run(self, arguments, *, input_data=None, **_kwargs):
        args = list(arguments)
        self.calls.append((args, input_data))
        if args[0] == "pg_lsclusters":
            return self.clusters
        if args[:2] == ["apt-cache", "policy"]:
            return b"Installed: (none)\nCandidate: 18.4-0ubuntu0.26.04.1\n"
        if args[:2] == ["openssl", "verify"]:
            return b"ok"
        if args[:3] == ["openssl", "x509", "-in"] and "-text" in args:
            return b"DNS:postgresql-main.example.internal, IP Address:10.20.0.10\n"
        if args[:2] == ["openssl", "pkey"] or (args[:2] == ["openssl", "x509"] and "-pubkey" in args):
            return b"same-public-key"
        if args[:4] == ["pg_conftool", "18", "main", "show"]:
            return b"listen_addresses = 10.20.0.10\nssl = on\npassword_encryption = scram-sha-256\nssl_min_protocol_version = TLSv1.2\n"
        if args[0] == "ss":
            return b"LISTEN 0 244 10.20.0.10:5432"
        if args[:3] == ["ip", "-4", "address"]:
            return b"inet 10.20.0.10/24 scope global eth0"
        if args[:3] == ["ip", "-4", "route"]:
            return b"default via 10.20.0.1 dev eth0"
        if args[0] == "df":
            return b"Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/root 10000000 1000 9000000 1% /\n"
        if args[0] == "runuser" and "--tuples-only" in args:
            return self.query_results.pop(0) if self.query_results else b"180004\non\nscram-sha-256\nTLSv1.2\n0\n"
        return b""


def make_bundle(root: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, dict[str, object]]:
    guest_root = root / "guest"
    guest_root.mkdir()
    target_root = root / "target"
    (target_root / "etc/apt/sources.list.d").mkdir(parents=True)
    (target_root / "etc").mkdir(exist_ok=True)
    (target_root / "etc/os-release").write_text('ID=ubuntu\nVERSION_ID="26.04"\n', encoding="utf-8")
    (target_root / "etc/resolv.conf").write_text("nameserver 10.20.0.1\n", encoding="utf-8")
    (target_root / "etc/apt/sources.list.d/ubuntu.sources").write_text(
        "Types: deb\nURIs: https://archive.ubuntu.com/ubuntu\nSuites: resolute\n",
        encoding="utf-8",
    )
    (target_root / "var/lib/dpkg").mkdir(parents=True)
    (target_root / "var/lib/apt/lists").mkdir(parents=True)
    allocations = [
        {
            "allocation_id": item,
            "database_name": item,
            "application_identity": item,
            "owner_identity": f"{item}_owner",
            "allowed_client_cidrs": [f"10.30.{index}.0/24"],
        }
        for index, item in enumerate(ALLOCATION_IDS, 1)
    ]
    plan = {
        "schema_version": 1,
        "provider_instance_id": "postgresql-main",
        "postgresql_major": 18,
        "fqdn": "postgresql-main.example.internal",
        "hostname": "postgresql-main",
        "provider_ip": "10.20.0.10",
        "gateway": "10.20.0.1",
        "dns_servers": ["10.20.0.1"],
        "allocations": allocations,
    }
    (guest_root / "guest-plan.json").write_text(json.dumps(plan), encoding="utf-8")
    for name in ("postgresql-main-guest.py", "ca.crt", "server.crt", "server.key"):
        (guest_root / name).write_bytes(name.encode())
    artifacts = {}
    for name in ("postgresql-main-guest.py", "guest-plan.json", "ca.crt", "server.crt"):
        artifacts[name] = hashlib.sha256((guest_root / name).read_bytes()).hexdigest()
    (guest_root / "public-manifest.json").write_text(json.dumps({"schema_version": 1, "artifacts": artifacts}), encoding="utf-8")
    for allocation in ALLOCATION_IDS:
        directory = guest_root / allocation
        directory.mkdir()
        secret = directory / "application-password"
        secret.write_bytes((allocation + "-" + "S" * 64).encode())
        secret.chmod(0o600)
    return guest_root, target_root, plan


class GuestValidationTests(unittest.TestCase):
    def test_wrong_os_and_architecture_are_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            (target / "etc/os-release").write_text("ID=debian\nVERSION_ID=13\n", encoding="utf-8")
            with self.assertRaisesRegex(ProvisioningError, "Ubuntu 26.04"):
                provisioner._validate_base()
            (target / "etc/os-release").write_text('ID=ubuntu\nVERSION_ID="26.04"\n', encoding="utf-8")
            with mock.patch("postgresql_main.guest.platform.machine", return_value="aarch64"):
                with self.assertRaisesRegex(ProvisioningError, "amd64"):
                    provisioner._validate_base()

    def test_pgdg_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            (target / "etc/apt/sources.list.d/pgdg.list").write_text("deb https://apt.postgresql.org/pub/repos/apt", encoding="utf-8")
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            with self.assertRaisesRegex(ProvisioningError, "PGDG"):
                provisioner.classify()

    def test_wrong_or_multiple_clusters_are_conflict(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            for clusters in (b"19 main 5432 down postgres\n", b"18 main 5432 down postgres\n18 other 5433 down postgres\n"):
                with self.subTest(clusters=clusters):
                    provisioner = GuestProvisioner(runner=FakeRunner(clusters=clusters), bundle=bundle, root=target)
                    self.assertEqual(provisioner.classify(), "guest_conflict")

    def test_package_lock_and_reboot_pause_are_visible(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            lock = target / "var/lib/dpkg/lock-frontend"
            lock.touch()
            fd = os.open(lock, os.O_RDONLY)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                with self.assertRaisesRegex(ProvisioningError, "belegt"):
                    provisioner.prepare_os("apt_update")
            finally:
                os.close(fd)
            lock.unlink()
            (target / "var/run").mkdir(parents=True)
            (target / "var/run/reboot-required").touch()
            self.assertEqual(provisioner.prepare_os("full_upgrade"), "PROVISIONING_PAUSED_REBOOT_REQUIRED")

    def test_existing_policy_rc_blocks_package_install(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            policy = target / "usr/sbin/policy-rc.d"
            policy.parent.mkdir(parents=True)
            policy.write_text("existing", encoding="utf-8")
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            with self.assertRaisesRegex(ProvisioningError, "policy-rc.d"):
                provisioner.install_postgresql("packages")

    def test_non_18_package_candidate_is_rejected_before_install(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            runner = FakeRunner()
            original = runner.run

            def candidate_19(arguments, **kwargs):
                if arguments[:2] == ["apt-cache", "policy"]:
                    return b"Candidate: 19.0-1\n"
                return original(arguments, **kwargs)

            runner.run = candidate_19
            provisioner = GuestProvisioner(runner=runner, bundle=bundle, root=target)
            with self.assertRaisesRegex(ProvisioningError, "PostgreSQL-18"):
                provisioner.install_postgresql("packages")
            self.assertFalse(any(call[0][:2] == ["apt-get", "-y"] for call in runner.calls))

    def test_runtime_base_checks_network_dns_https_sources_and_storage(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            self.assertEqual(provisioner.prepare_os("validate"), "PHASE_COMPLETED guest_os_ready validate")
            (target / "etc/resolv.conf").write_text("nameserver 192.0.2.1\n", encoding="utf-8")
            with self.assertRaisesRegex(ProvisioningError, "DNS"):
                provisioner.prepare_os("validate")

    def test_hba_is_allocation_specific_and_rejects_weak_rules(self):
        with tempfile.TemporaryDirectory() as raw:
            _bundle, _target, plan = make_bundle(pathlib.Path(raw))
            hba = render_hba(plan)
            validate_hba(hba)
            self.assertEqual(hba.count("hostssl "), 4)
            self.assertNotIn("hostssl all all", hba)
            self.assertNotIn("0.0.0.0/0", hba)
            for bad in ("host all all 0.0.0.0/0 trust\n", "hostssl all all 10.0.0.0/8 md5\n"):
                with self.assertRaises(ProvisioningError):
                    validate_hba(bad)

    def test_tls_files_are_installed_with_bounded_metadata(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            provisioner = GuestProvisioner(runner=FakeRunner(), bundle=bundle, root=target)
            with mock.patch("postgresql_main.guest.grp.getgrnam", return_value=types.SimpleNamespace(gr_gid=0)):
                provisioner.configure_postgresql("tls")
            tls = target / "etc/postgresql/18/main/tls"
            self.assertEqual((tls / "server.key").stat().st_mode & 0o777, 0o640)
            self.assertEqual((tls / "server.crt").stat().st_mode & 0o777, 0o644)
            self.assertEqual((tls / "ca.crt").stat().st_mode & 0o777, 0o644)

    def test_wrong_certificate_san_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            runner = FakeRunner()
            original = runner.run

            def wrong_san(arguments, **kwargs):
                if arguments[:3] == ["openssl", "x509", "-in"] and "-text" in arguments:
                    return b"DNS:other.example, IP Address:192.0.2.1\n"
                return original(arguments, **kwargs)

            runner.run = wrong_san
            provisioner = GuestProvisioner(runner=runner, bundle=bundle, root=target)
            with self.assertRaisesRegex(ProvisioningError, "bindet Plan nicht"):
                provisioner._validate_bundle_pki()

    def test_allocation_secret_is_only_sent_over_stdin(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            runner = FakeRunner(clusters=b"18 main 5432 online postgres\n")
            runner.query_results = [b"", b"", b"f\n", b""]
            provisioner = GuestProvisioner(runner=runner, bundle=bundle, root=target)
            provisioner.create_allocation("gitea")
            secret = (bundle / "gitea/application-password").read_text()
            argv = "\n".join(" ".join(arguments) for arguments, _input in runner.calls)
            self.assertNotIn(secret, argv)
            self.assertTrue(any(secret.encode() in (input_data or b"") for _args, input_data in runner.calls))

    def test_global_listener_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            bundle, target, _plan = make_bundle(pathlib.Path(raw))
            runner = FakeRunner(clusters=b"18 main 5432 online postgres\n")
            original = runner.run

            def broad(arguments, **kwargs):
                if arguments[0] == "ss":
                    return b"LISTEN 0 244 0.0.0.0:5432"
                return original(arguments, **kwargs)

            runner.run = broad
            provisioner = GuestProvisioner(runner=runner, bundle=bundle, root=target)
            with self.assertRaisesRegex(ProvisioningError, "global"):
                provisioner.verify_readiness("provider")


if __name__ == "__main__":
    unittest.main()
