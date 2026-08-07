from __future__ import annotations

import ast
import builtins
import importlib.util
import io
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stderr
from unittest import mock


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts/postgresql-main-plan.py"
SPEC = importlib.util.spec_from_file_location("postgresql_main_plan", SCRIPT)
assert SPEC and SPEC.loader
planner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = planner
SPEC.loader.exec_module(planner)


def allocation_block(allocation_id: str, allowed: str = '"10.20.0.0/16"') -> str:
    return f'''[[allocations]]
allocation_id = "{allocation_id}"
database_name = "{allocation_id}"
application_identity = "{allocation_id}"
allowed_client_cidrs = [{allowed}]
'''


def config_text(
    backup_root: pathlib.Path,
    *,
    vmid: int = 200,
    storage: str = "local-lvm",
    bridge: str = "vmbr0",
    fqdn: str = "postgresql-main.example.internal",
    ipv4_cidr: str = "10.10.0.10/24",
    gateway: str = "10.10.0.1",
    major: int = 18,
    provider_id: str = "postgresql-main",
    allocations: tuple[str, ...] = planner.EXPECTED_ALLOCATIONS,
    allowed: str = '"10.20.0.0/16"',
    extra: str = "",
    protection_confirmed: bool = True,
) -> str:
    allocation_text = "\n".join(allocation_block(item, allowed) for item in allocations)
    protected = "true" if protection_confirmed else "false"
    return f'''schema_version = 1
{extra}
[provider]
provider_instance_id = "{provider_id}"
hostname = "postgresql-main"
fqdn = "{fqdn}"
postgresql_major = {major}

[lxc]
vmid = {vmid}
storage = "{storage}"
bridge = "{bridge}"
ipv4_cidr = "{ipv4_cidr}"
gateway = "{gateway}"
dns_servers = ["10.10.0.53"]
cores = 4
memory_mib = 8192
swap_mib = 2048
disk_gib = 100

[backup]
host_root = "{backup_root}"
minimum_free_gib = 1
protection_confirmed = {protected}

{allocation_text}
'''


class FakeRunner:
    def __init__(self, overrides: dict[tuple[str, ...], str] | None = None) -> None:
        self.calls: list[tuple[str, ...]] = []
        self.outputs = {
            ("pveversion",): "pve-manager/9.0/test\n",
            ("pct", "list"): "VMID Status Lock Name\n",
            (
                "pvesm",
                "status",
                "--content",
                "rootdir",
            ): "Name Type Status Total Used Available %\nlocal-lvm lvmthin active 300000000000 100000000000 200000000000 33%\n",
            ("ip", "link", "show", "type", "bridge"): "2: vmbr0: <BROADCAST,UP> mtu 1500 state UP\n",
            ("ip", "address", "show"): "1: lo: <LOOPBACK>\n    inet 127.0.0.1/8 scope host lo\n",
            ("ip", "route", "show"): "default via 10.10.0.1 dev vmbr0\n",
            (
                "pveam",
                "available",
                "--section",
                "system",
            ): "system ubuntu-26.04-standard_26.04-1_amd64.tar.zst\n",
            ("pct", "status", "200"): "status: running\n",
            ("pct", "config", "200"): "hostname: existing\n",
            ("pct", "pending", "200"): "\n",
        }
        if overrides:
            self.outputs.update(overrides)

    def run(self, arguments):
        key = tuple(arguments)
        self.calls.append(key)
        if key not in self.outputs:
            raise planner.ProbeError(f"missing fake output for {key}")
        return planner.CommandResult(self.outputs[key], "", 0)


class PlannerTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.backup = self.root / "backup"
        self.backup.mkdir()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_config(self, text: str | None = None) -> pathlib.Path:
        path = self.root / "deployment.toml"
        path.write_text(text or config_text(self.backup), encoding="utf-8")
        return path

    def load(self, **kwargs):
        return planner.load_config(self.write_config(config_text(self.backup, **kwargs)))

    def build_report(
        self,
        *,
        config=None,
        proxmox=None,
        secret_checks=(),
        backup=None,
        commit="a" * 40,
        configuration_sha256="b" * 64,
        version_matrix_sha256="c" * 64,
        generated_at="2026-08-02T20:00:00Z",
    ):
        return planner.build_plan(
            config or self.load(),
            planner.load_version_matrix(),
            proxmox or ready_proxmox(),
            secret_checks,
            backup or ready_backup(self.backup),
            commit,
            configuration_path=self.root / "deployment.toml",
            configuration_sha256=configuration_sha256,
            version_matrix_sha256=version_matrix_sha256,
            generated_at=generated_at,
        )


class ConfigurationTests(PlannerTestCase):
    def test_valid_complete_configuration(self) -> None:
        config = self.load()
        self.assertEqual(config.provider.provider_instance_id, "postgresql-main")
        self.assertEqual([item.allocation_id for item in config.allocations], list(planner.EXPECTED_ALLOCATIONS))

    def test_missing_configuration(self) -> None:
        with self.assertRaises(planner.ConfigurationError):
            planner.load_config(self.root / "missing.toml")

    def test_repository_example_is_never_automatic(self) -> None:
        with self.assertRaises(planner.ConfigurationError) as context:
            planner.run_plan(self.write_config(), runner=FakeRunner(), require_real_path=True)
        self.assertIn(str(planner.REAL_CONFIG_PATH), str(context.exception))
        self.assertNotEqual(planner.EXAMPLE_CONFIG_PATH, planner.REAL_CONFIG_PATH)

    def test_unknown_key(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "unbekannte Schlüssel"):
            planner.load_config(self.write_config(config_text(self.backup, extra="surprise = true")))

    def test_wrong_schema_version(self) -> None:
        text = config_text(self.backup).replace("schema_version = 1", "schema_version = 2")
        with self.assertRaisesRegex(planner.ConfigurationError, "schema_version muss 1"):
            planner.load_config(self.write_config(text))

    def test_wrong_postgresql_major(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "postgresql_major muss 18"):
            self.load(major=19)

    def test_wrong_provider_id(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "provider_instance_id"):
            self.load(provider_id="other")

    def test_missing_allocation(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "muss exakt"):
            self.load(allocations=("gitea", "openbao", "semaphore"))

    def test_additional_allocation(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "muss exakt"):
            self.load(allocations=(*planner.EXPECTED_ALLOCATIONS, "extra"))

    def test_duplicate_allocation(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "doppelte"):
            self.load(allocations=("gitea", "openbao", "semaphore", "nodered", "gitea"))

    def test_invalid_database_name(self) -> None:
        text = config_text(self.backup).replace('database_name = "gitea"', 'database_name = "Bad-Name"')
        with self.assertRaisesRegex(planner.ConfigurationError, "database_name"):
            planner.load_config(self.write_config(text))

    def test_invalid_identity_name(self) -> None:
        text = config_text(self.backup).replace('application_identity = "gitea"', 'application_identity = "1gitea"')
        with self.assertRaisesRegex(planner.ConfigurationError, "application_identity"):
            planner.load_config(self.write_config(text))

    def test_derived_owner_must_fit_postgresql_identifier_limit(self) -> None:
        identity = "a" * 63
        text = config_text(self.backup).replace(
            'application_identity = "gitea"', f'application_identity = "{identity}"'
        )
        with self.assertRaisesRegex(planner.ConfigurationError, "derived_owner_identity"):
            planner.load_config(self.write_config(text))

    def test_derived_owner_must_not_collide_with_database_name(self) -> None:
        text = config_text(self.backup).replace(
            'database_name = "gitea"', 'database_name = "gitea_owner"'
        )
        with self.assertRaisesRegex(planner.ConfigurationError, "kollidieren"):
            planner.load_config(self.write_config(text))

    def test_invalid_ip(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "ipv4_cidr"):
            self.load(ipv4_cidr="10.10.0.0/24")

    def test_gateway_must_match_network(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "gateway"):
            self.load(gateway="10.11.0.1")

    def test_invalid_dns_server(self) -> None:
        text = config_text(self.backup).replace(
            'dns_servers = ["10.10.0.53"]', 'dns_servers = ["127.0.0.1"]'
        )
        with self.assertRaisesRegex(planner.ConfigurationError, "dns_servers"):
            planner.load_config(self.write_config(text))

    def test_empty_dns_list_is_plan_blocker(self) -> None:
        text = config_text(self.backup).replace(
            'dns_servers = ["10.10.0.53"]', "dns_servers = []"
        )
        config = planner.load_config(self.write_config(text))
        report = planner.build_plan(
            config,
            planner.load_version_matrix(),
            ready_proxmox(),
            (),
            ready_backup(self.backup),
            "a" * 40,
        )
        self.assertTrue(
            any("lxc.dns_servers ist leer" in blocker for blocker in report.blockers)
        )

    def test_invalid_fqdn(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "fqdn"):
            self.load(fqdn="HTTPS://Bad/Path")

    def test_global_client_allowlist(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "globale Freigabe"):
            self.load(allowed='"0.0.0.0/0"')

    def test_noncanonical_client_cidr(self) -> None:
        with self.assertRaisesRegex(planner.ConfigurationError, "kanonische CIDR"):
            self.load(allowed='"10.20.0.1/16"')

    def test_missing_backup_target_value(self) -> None:
        text = config_text(self.backup).replace(f'host_root = "{self.backup}"', 'host_root = ""')
        with self.assertRaisesRegex(planner.ConfigurationError, "backup.host_root"):
            planner.load_config(self.write_config(text))

    def test_empty_client_allowlists_are_valid_input_but_plan_blocker(self) -> None:
        config = self.load(allowed="")
        report = planner.build_plan(
            config,
            planner.load_version_matrix(),
            ready_proxmox(),
            (),
            ready_backup(self.backup),
            "a" * 40,
        )
        self.assertEqual(len([item for item in report.blockers if "Client-Allowlist" in item]), 4)
        self.assertTrue(report.render().endswith("PLAN_BLOCKED\n"))


class MatrixTests(PlannerTestCase):
    def test_version_matrix_is_complete(self) -> None:
        matrix = planner.load_version_matrix()
        self.assertEqual(matrix.checked_at, "2026-08-02")
        self.assertEqual(matrix.postgresql["documented_minor"], "18.4")
        self.assertEqual(set(matrix.applications), set(planner.EXPECTED_ALLOCATIONS))

    def test_modified_matrix_is_rejected(self) -> None:
        source = planner.VERSION_MATRIX_PATH.read_text(encoding="utf-8").replace('version = "1.27.1"', 'version = "9.9.9"')
        path = self.root / "matrix.toml"
        path.write_text(source, encoding="utf-8")
        with self.assertRaises(planner.MatrixError):
            planner.load_version_matrix(path)


class SecretTests(PlannerTestCase):
    def test_parent_symlink_is_rejected_before_config_read(self) -> None:
        secret_root = self.root / "secrets"
        target = self.root / "target"
        target.mkdir()
        secret_root.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(planner.ConfigurationError, "Symlink-Komponente"):
            planner.ensure_no_symlink_components(
                secret_root / "database-service/deployment.toml", secret_root
            )

    def test_missing_path_is_only_reported_and_not_created(self) -> None:
        missing = self.root / "does-not-exist"
        check = planner.inspect_path(
            missing, kind="directory", expected_mode=0o700, require_nonempty=False
        )
        self.assertEqual(check.state, "FEHLT_GEPLANT")
        self.assertFalse(missing.exists())

    def test_symlink_is_conflict(self) -> None:
        target = self.root / "target"
        target.write_text("not-a-secret", encoding="utf-8")
        link = self.root / "link"
        link.symlink_to(target)
        check = planner.inspect_path(link, kind="file", expected_mode=0o600, require_nonempty=True)
        self.assertEqual(check.state, "KONFLIKT")
        self.assertIn("Symlink", check.conflict or "")

    def test_unsafe_mode_is_conflict(self) -> None:
        path = self.root / "metadata-only"
        path.write_text("not-a-secret", encoding="utf-8")
        path.chmod(0o644)
        check = planner.inspect_path(path, kind="file", expected_mode=0o600, require_nonempty=True)
        self.assertEqual(check.state, "KONFLIKT")
        self.assertIn("0600", check.conflict or "")

    def test_secret_content_is_never_opened(self) -> None:
        fake_stat = types.SimpleNamespace(
            st_mode=stat.S_IFREG | 0o600,
            st_uid=0,
            st_gid=0,
            st_size=32,
        )
        with mock.patch.object(builtins, "open", side_effect=AssertionError("content read")):
            check = planner.inspect_path(
                pathlib.Path("/secrets/example"),
                kind="file",
                expected_mode=0o600,
                require_nonempty=True,
                lstat_function=lambda _path: fake_stat,
            )
        self.assertEqual(check.state, "OK")


class ProxmoxTests(PlannerTestCase):
    def test_free_vmid_is_detected(self) -> None:
        config = self.load(vmid=0)
        state = planner.collect_proxmox_state(config, FakeRunner())
        self.assertEqual(state.vmid, 100)
        self.assertFalse(state.blockers)

    def test_occupied_vmid_is_blocker_and_diagnosed(self) -> None:
        runner = FakeRunner({("pct", "list"): "VMID Status Lock Name\n200 running - existing\n"})
        state = planner.collect_proxmox_state(self.load(vmid=200), runner)
        self.assertTrue(any("bereits" in item for item in state.blockers))
        self.assertIn(("pct", "status", "200"), runner.calls)
        self.assertIn(("pct", "config", "200"), runner.calls)
        self.assertIn(("pct", "pending", "200"), runner.calls)

    def test_unique_storage_is_selected(self) -> None:
        state = planner.collect_proxmox_state(self.load(storage=""), FakeRunner())
        self.assertEqual(state.storage, "local-lvm")

    def test_ambiguous_storage_is_blocker(self) -> None:
        output = "Name Type Status Total Used Available %\na dir active 300G 1G 299G 1%\nb dir active 300G 1G 299G 1%\n"
        state = planner.collect_proxmox_state(
            self.load(storage=""),
            FakeRunner({("pvesm", "status", "--content", "rootdir"): output}),
        )
        self.assertTrue(any("mehrdeutig" in item for item in state.blockers))

    def test_unique_bridge_is_selected(self) -> None:
        state = planner.collect_proxmox_state(self.load(bridge=""), FakeRunner())
        self.assertEqual(state.bridge, "vmbr0")

    def test_missing_bridge_is_blocker(self) -> None:
        state = planner.collect_proxmox_state(
            self.load(), FakeRunner({("ip", "link", "show", "type", "bridge"): ""})
        )
        self.assertTrue(any("Bridge" in item for item in state.blockers))

    def test_template_is_required(self) -> None:
        state = planner.collect_proxmox_state(
            self.load(), FakeRunner({("pveam", "available", "--section", "system"): ""})
        )
        self.assertTrue(any("Template" in item for item in state.blockers))

    def test_insufficient_storage_is_blocker(self) -> None:
        output = "Name Type Status Total Used Available %\nlocal-lvm lvmthin active 100G 99G 1G 99%\n"
        state = planner.collect_proxmox_state(
            self.load(), FakeRunner({("pvesm", "status", "--content", "rootdir"): output})
        )
        self.assertTrue(any("weniger freien Speicher" in item for item in state.blockers))

    def test_reference_resource_deviation_warns_but_does_not_block(self) -> None:
        text = config_text(self.backup).replace("cores = 4", "cores = 2").replace("memory_mib = 8192", "memory_mib = 4096").replace("disk_gib = 100", "disk_gib = 50")
        config = planner.load_config(self.write_config(text))
        state = planner.collect_proxmox_state(config, FakeRunner())
        self.assertEqual(len(state.warnings), 3)


class BackupTests(PlannerTestCase):
    def test_valid_backup_target(self) -> None:
        check = planner.inspect_backup_target(self.load().backup, self.root / "repository")
        self.assertEqual(check.state, "OK")

    def test_missing_backup_target_is_blocker(self) -> None:
        missing = self.root / "missing"
        config = self.load()
        backup = dataclasses_replace(config.backup, host_root=missing)
        check = planner.inspect_backup_target(backup, self.root / "repository")
        self.assertTrue(check.blockers)

    def test_unprotected_backup_target_is_blocker(self) -> None:
        check = planner.inspect_backup_target(self.load(protection_confirmed=False).backup, self.root / "repository")
        self.assertTrue(any("Schutz" in item for item in check.blockers))

    def test_backup_inside_repository_is_blocker(self) -> None:
        repository = self.root
        check = planner.inspect_backup_target(self.load().backup, repository)
        self.assertTrue(any("Git-Repository" in item for item in check.blockers))


class MutationBoundaryTests(PlannerTestCase):
    def test_command_runner_rejects_mutations(self) -> None:
        runner = planner.CommandRunner()
        for args in (["pct", "create", "200"], ["apt-get", "install", "postgresql-18"], ["systemctl", "start", "postgresql"]):
            with self.assertRaises(planner.ProbeError):
                runner.run(args)

    def test_allowed_command_uses_fixed_list_and_bounded_runtime(self) -> None:
        calls = []

        def executor(args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args, 0, "version\n", "")

        result = planner.CommandRunner(executor).run(["pveversion"])
        self.assertEqual(result.stdout, "version\n")
        self.assertEqual(calls[0][0], ["pveversion"])
        self.assertEqual(calls[0][1]["timeout"], planner.COMMAND_TIMEOUT_SECONDS)
        self.assertNotIn("shell", calls[0][1])

    def test_parser_has_only_plan_mode(self) -> None:
        parser = planner.create_parser()
        choices = next(action.choices for action in parser._actions if isinstance(action, planner.argparse._SubParsersAction))
        self.assertEqual(set(choices), {"plan"})
        plan_parser = choices["plan"]
        format_action = next(
            action for action in plan_parser._actions if action.dest == "format"
        )
        self.assertEqual(format_action.default, "text")
        self.assertEqual(tuple(format_action.choices), ("text", "json"))
        self.assertNotIn("output", {action.dest for action in plan_parser._actions})
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["apply"])
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["resume"])
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parser.parse_args(["plan", "--config", "/tmp/input", "--format", "yaml"])

    def test_source_has_no_mutating_or_network_executor(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        tree = ast.parse(source)
        self.assertNotIn("shell" + "=True", source)
        self.assertNotRegex(source, r"subprocess\.(?:Popen|call|check_call|check_output)")
        self.assertNotRegex(source, r"\bdef\s+(?:apply|create|install|provision|delete|restore)\b")
        forbidden_imports = {"requests", "socket", "urllib", "http", "ftplib"}
        write_methods = {
            "write_text",
            "write_bytes",
            "mkdir",
            "touch",
            "unlink",
            "rename",
            "chmod",
            "chown",
            "remove",
            "rmdir",
        }
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = {alias.name.split(".")[0] for alias in node.names}
                self.assertFalse(names & forbidden_imports)
            elif isinstance(node, ast.ImportFrom):
                self.assertNotIn((node.module or "").split(".")[0], forbidden_imports)
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                self.assertNotIn(node.func.attr, write_methods)
        self.assertNotIn("os" + ".replace", source)

    def test_planning_creates_no_files(self) -> None:
        config_path = self.write_config()
        before = sorted(path.relative_to(self.root) for path in self.root.rglob("*"))
        config = planner.load_config(config_path)
        planner.build_plan(
            config,
            planner.load_version_matrix(),
            ready_proxmox(),
            (),
            ready_backup(self.backup),
            "a" * 40,
        )
        after = sorted(path.relative_to(self.root) for path in self.root.rglob("*"))
        self.assertEqual(before, after)


class OutputTests(PlannerTestCase):
    def test_complete_plan_output(self) -> None:
        config = self.load()
        report = planner.build_plan(
            config,
            planner.load_version_matrix(),
            ready_proxmox(),
            (),
            ready_backup(self.backup),
            "a" * 40,
        )
        output = report.render()
        self.assertTrue(output.endswith("PLAN_READY\n"))
        for allocation in planner.EXPECTED_ALLOCATIONS:
            self.assertIn(f"[{allocation}]", output)
        allocation_section = output.split("== ALLOCATIONS ==", 1)[1].split("== SECRETS", 1)[0]
        self.assertNotIn("[ralf", allocation_section.lower())
        self.assertIn("nur relationale Flow-Anwendungsdaten", output)
        self.assertIn("PostgreSQL ist deployment-spezifisch gewählt", output)
        self.assertIn("DNS-Server: 10.10.0.53", output)
        self.assertIn("/secrets/database-service/allocations/gitea/application-password", output)
        self.assertIn("keine reale Mutation im Planmodus", output)
        self.assertRegex(output, r"Plan-SHA-256: [0-9a-f]{64}")

    def test_secret_text_cannot_leak_through_metadata_plan(self) -> None:
        marker = "TOP-SECRET-CONTENT"
        secret_file = self.root / "secret"
        secret_file.write_text(marker, encoding="utf-8")
        secret_file.chmod(0o600)
        check = planner.inspect_path(secret_file, kind="file", expected_mode=0o600, require_nonempty=True)
        output = planner.build_plan(
            self.load(),
            planner.load_version_matrix(),
            ready_proxmox(),
            (check,),
            ready_backup(self.backup),
            "a" * 40,
        ).render()
        self.assertNotIn(marker, output)


class PlanHashTests(PlannerTestCase):
    def plan_hash(self, **kwargs) -> str:
        report = self.build_report(**kwargs)
        assert report.machine_plan is not None
        return str(report.machine_plan["plan_sha256"])

    def test_same_state_has_same_hash(self) -> None:
        self.assertEqual(self.plan_hash(), self.plan_hash())

    def test_generated_at_is_not_hashed(self) -> None:
        first = self.plan_hash(generated_at="2026-08-02T20:00:00Z")
        second = self.plan_hash(generated_at="2026-08-03T20:00:00Z")
        self.assertEqual(first, second)

    def test_repository_commit_changes_hash(self) -> None:
        self.assertNotEqual(self.plan_hash(commit="a" * 40), self.plan_hash(commit="d" * 40))

    def test_configuration_hash_changes_plan_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(configuration_sha256="a" * 64),
            self.plan_hash(configuration_sha256="b" * 64),
        )

    def test_version_matrix_hash_changes_plan_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(version_matrix_sha256="a" * 64),
            self.plan_hash(version_matrix_sha256="b" * 64),
        )

    def test_vmid_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), vmid=200)),
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), vmid=201)),
        )

    def test_storage_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), storage="local-lvm")),
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), storage="fast-ssd")),
        )

    def test_bridge_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), bridge="vmbr0")),
            self.plan_hash(proxmox=dataclasses_replace(ready_proxmox(), bridge="vmbr1")),
        )

    def test_provider_ip_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(config=self.load(ipv4_cidr="10.10.0.10/24")),
            self.plan_hash(config=self.load(ipv4_cidr="10.10.0.11/24")),
        )

    def test_client_allowlist_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(config=self.load(allowed='"10.20.0.0/16"')),
            self.plan_hash(config=self.load(allowed='"10.30.0.0/16"')),
        )

    def test_secret_metadata_changes_hash(self) -> None:
        missing = planner.PathCheck(
            pathlib.Path("/secrets/example"), "FEHLT_GEPLANT", "nicht vorhanden"
        )
        safe = planner.PathCheck(
            pathlib.Path("/secrets/example"),
            "OK",
            "uid=0 gid=0 mode=0600",
            exists=True,
            file_type="file",
            owner=0,
            group=0,
            mode="0600",
            safe=True,
        )
        self.assertNotEqual(
            self.plan_hash(secret_checks=(missing,)),
            self.plan_hash(secret_checks=(safe,)),
        )

    def test_blocker_changes_hash(self) -> None:
        blocked = dataclasses_replace(ready_proxmox(), blockers=["test blocker"])
        self.assertNotEqual(self.plan_hash(), self.plan_hash(proxmox=blocked))

    def test_warning_changes_hash(self) -> None:
        warned = dataclasses_replace(ready_proxmox(), warnings=["security warning"])
        self.assertNotEqual(self.plan_hash(), self.plan_hash(proxmox=warned))

    def test_resource_changes_hash(self) -> None:
        config = self.load()
        reduced = dataclasses_replace(
            config, lxc=dataclasses_replace(config.lxc, cores=3)
        )
        self.assertNotEqual(
            self.plan_hash(config=config),
            self.plan_hash(config=reduced),
        )

    def test_template_changes_hash(self) -> None:
        self.assertNotEqual(
            self.plan_hash(
                proxmox=dataclasses_replace(ready_proxmox(), template="ubuntu-a")
            ),
            self.plan_hash(
                proxmox=dataclasses_replace(ready_proxmox(), template="ubuntu-b")
            ),
        )

    def test_diagnostic_order_does_not_change_hash(self) -> None:
        first = dataclasses_replace(ready_proxmox(), blockers=["a", "b"])
        second = dataclasses_replace(ready_proxmox(), blockers=["b", "a"])
        self.assertEqual(
            self.plan_hash(proxmox=first), self.plan_hash(proxmox=second)
        )


class JsonOutputTests(PlannerTestCase):
    def test_json_schema_and_complete_content(self) -> None:
        observation = planner.PathCheck(
            pathlib.Path("/secrets/database-service/example"),
            "OK",
            "uid=0 gid=0 mode=0600",
            exists=True,
            file_type="file",
            owner=0,
            group=0,
            mode="0600",
            safe=True,
        )
        report = self.build_report(secret_checks=(observation,))
        document = json.loads(report.render_json())
        self.assertEqual(
            set(document),
            {
                "schema_version",
                "plan_type",
                "provider_instance_id",
                "repository_commit",
                "configuration_path",
                "configuration_sha256",
                "version_matrix_sha256",
                "generated_at",
                "plan_inputs",
                "proxmox_observations",
                "secret_metadata_observations",
                "backup_observations",
                "warnings",
                "blockers",
                "planned_mutations",
                "excluded_scope",
                "plan_status",
                "plan_sha256",
            },
        )
        self.assertEqual(document["schema_version"], 1)
        self.assertEqual(document["plan_type"], "postgresql-main-deployment")
        self.assertEqual(document["provider_instance_id"], "postgresql-main")
        self.assertEqual(document["plan_status"], "PLAN_READY")
        self.assertRegex(document["plan_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(
            document["plan_sha256"], planner.calculate_plan_sha256(document)
        )
        self.assertEqual(
            [item["allocation_id"] for item in document["plan_inputs"]["allocations"]],
            list(planner.EXPECTED_ALLOCATIONS),
        )
        self.assertEqual(len(document["planned_mutations"]), 14)
        self.assertEqual(
            [item["position"] for item in document["planned_mutations"]],
            list(range(1, 15)),
        )
        self.assertEqual(
            set(document["secret_metadata_observations"][0]),
            {"path", "exists", "file_type", "owner", "group", "mode", "safe"},
        )

    def test_json_contains_all_blockers(self) -> None:
        proxmox = dataclasses_replace(ready_proxmox(), blockers=["second", "first"])
        document = json.loads(self.build_report(proxmox=proxmox).render_json())
        self.assertEqual(document["blockers"], ["first", "second"])
        self.assertEqual(document["plan_status"], "PLAN_BLOCKED")

    def test_json_does_not_expose_secret_material(self) -> None:
        marker = "DO-NOT-EXPOSE-SECRET"
        document = json.loads(self.build_report().render_json())
        rendered = json.dumps(document)
        self.assertNotIn(marker, rendered)
        for observation in document["secret_metadata_observations"]:
            self.assertNotIn("content", observation)
            self.assertNotIn("value", observation)
            self.assertNotIn("sha256", observation)
        self.assertNotIn("environment", document)

    def test_run_plan_supports_text_and_json_without_writes(self) -> None:
        config_path = self.write_config()
        before = sorted(path.relative_to(self.root) for path in self.root.rglob("*"))
        patches = (
            mock.patch.object(planner, "inspect_secret_contract", return_value=()),
            mock.patch.object(
                planner,
                "inspect_backup_target",
                return_value=ready_backup(self.backup),
            ),
            mock.patch.object(planner, "read_git_commit", return_value="a" * 40),
        )
        with patches[0], patches[1], patches[2]:
            text_code, text_output = planner.run_plan(
                config_path,
                runner=FakeRunner(),
                require_real_path=False,
                output_format="text",
                generated_at="2026-08-02T20:00:00Z",
            )
            json_code, json_output = planner.run_plan(
                config_path,
                runner=FakeRunner(),
                require_real_path=False,
                output_format="json",
                generated_at="2026-08-03T20:00:00Z",
            )
        self.assertEqual(text_code, 0)
        self.assertEqual(json_code, 0)
        self.assertTrue(text_output.endswith("PLAN_READY\n"))
        self.assertEqual(json.loads(json_output)["plan_status"], "PLAN_READY")
        self.assertEqual(
            re.search(r"Plan-SHA-256: ([0-9a-f]{64})", text_output).group(1),
            json.loads(json_output)["plan_sha256"],
        )
        after = sorted(path.relative_to(self.root) for path in self.root.rglob("*"))
        self.assertEqual(before, after)


class DocumentationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repository = SCRIPT.parents[1]
        self.apply_contract = (
            self.repository / "docs/operations/postgresql-main-apply-contract.md"
        ).read_text(encoding="utf-8")
        self.recovery_contract = (
            self.repository
            / "docs/recovery/postgresql-main-provisioning-recovery.md"
        ).read_text(encoding="utf-8")
        self.adr = (
            self.repository
            / "docs/decisions/ADR-0007-postgresql-apply-and-recovery-boundaries.md"
        ).read_text(encoding="utf-8")

    def test_every_planned_phase_has_apply_and_recovery_contract(self) -> None:
        for _position, phase, _mutation_id, _title in planner.PLANNED_MUTATIONS:
            self.assertIn(f"`{phase}`", self.apply_contract)
            self.assertIn(f"`{phase}`", self.recovery_contract)

    def test_contract_separates_normal_apply_and_resume(self) -> None:
        self.assertIn("Normaler Apply", self.apply_contract)
        self.assertIn("resume-plan", self.recovery_contract)
        self.assertIn("resume-apply", self.recovery_contract)
        self.assertIn("--confirm-resume-sha256", self.recovery_contract)
        self.assertIn("RESUME_CONFLICT", self.recovery_contract)

    def test_contract_forbids_automatic_rollback(self) -> None:
        for document in (self.apply_contract, self.recovery_contract, self.adr):
            self.assertRegex(document.lower(), r"kein(?:en)? automatischen rollback")

    def test_secrets_and_error_cleanup_are_bounded(self) -> None:
        self.assertIn("/secrets", self.apply_contract)
        self.assertIn("/run/ralf-database-provision/", self.apply_contract)
        self.assertIn("bei Erfolg und Fehler entfernt", self.apply_contract)
        self.assertIn("Sicherheitsbereinigung ist kein Rollback", self.apply_contract)

    def test_apply_implementation_is_separate_from_read_only_planner(self) -> None:
        deploy = self.repository / "scripts/postgresql-main-deploy.py"
        self.assertTrue(deploy.is_file())
        planner_parser = planner.create_parser()
        choices = next(
            action.choices
            for action in planner_parser._actions
            if isinstance(action, planner.argparse._SubParsersAction)
        )
        self.assertEqual(set(choices), {"plan"})


def dataclasses_replace(instance, **changes):
    return planner.dataclasses.replace(instance, **changes)


def ready_proxmox():
    return planner.ProxmoxState(
        pve_version="pve-manager/9.0/test",
        vmid=200,
        vmid_source="test",
        storage="local-lvm",
        storage_source="test",
        storage_available_bytes=200 * 1024**3,
        bridge="vmbr0",
        bridge_source="test",
        template="ubuntu-26.04-standard_26.04-1_amd64.tar.zst",
        host_addresses_checked=True,
        host_routes_checked=True,
    )


def ready_backup(path: pathlib.Path):
    return planner.BackupCheck(path, "OK", 200 * 1024**3, (), ())


if __name__ == "__main__":
    unittest.main()
