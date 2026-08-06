from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.host import (
    CONFIG_PATH, LOCK_PATH, Provisioner, build_pct_create_arguments,
)
from postgresql_main.models import ALLOCATION_IDS, ProvisioningError
from postgresql_main_support import NOW, make_environment


def make_provisioner(root: pathlib.Path, *, fault=lambda _point: None):
    fs, backend, store, pki, artifacts, report = make_environment(root)
    provisioner = Provisioner(
        filesystem=fs, backend=backend, marker_store=store, pki=pki,
        plan_factory=lambda _path: report, token_source=lambda: "S" * 64,
        operation_id_source=lambda: "operation-1", clock=lambda: NOW,
        fault=fault, artifact_paths=artifacts,
    )
    return provisioner, fs, backend, store, pki, artifacts, report


class ApplyBoundaryTests(unittest.TestCase):
    def test_wrong_hash_blocks_before_any_mutation(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, fs, backend, _store, _pki, _artifacts, _report = make_provisioner(pathlib.Path(raw))
            with self.assertRaisesRegex(ProvisioningError, "Plan-Hash") as caught:
                provisioner.apply(CONFIG_PATH, "0" * 64)
            self.assertEqual(caught.exception.code, "APPLY_BLOCKED_PLAN_CHANGED")
            self.assertEqual(backend.actions, [])
            self.assertFalse(fs.path("/secrets/database-service/providers/postgresql-main/provisioning-state.json").exists())
            self.assertFalse(fs.path(LOCK_PATH).exists())

    def test_blocked_plan_is_not_applyable(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, _fs, backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            report.blockers.append("blocked")
            with self.assertRaisesRegex(ProvisioningError, "Blocker"):
                provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            self.assertEqual(backend.actions, [])

    def test_dirty_repository_blocks_before_marker(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, fs, backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            backend.clean = False
            with self.assertRaisesRegex(ProvisioningError, "Repository"):
                provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            self.assertFalse(fs.path("/secrets/database-service/providers/postgresql-main/provisioning-state.json").exists())

    def test_unsafe_configuration_metadata_blocks(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, fs, _backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            fs.path(CONFIG_PATH).chmod(0o644)
            with self.assertRaisesRegex(ProvisioningError, "Metadaten"):
                provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])

    def test_parallel_apply_is_rejected_without_waiting(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, fs, _backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            with fs.exclusive_lock(LOCK_PATH):
                with self.assertRaises(ProvisioningError) as caught:
                    provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            self.assertEqual(caught.exception.code, "PROVISIONING_ALREADY_RUNNING")

    def test_complete_mocked_apply_has_single_create_and_start(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, _fs, backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            marker = provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            self.assertEqual(backend.actions.count("pct create"), 1)
            self.assertEqual(backend.actions.count("pct start 250"), 1)
            self.assertEqual(marker["readiness_status"]["provider_status"], "ready")
            self.assertEqual(marker["readiness_status"]["allocation_readiness"], "consumer_validation_pending")
            self.assertEqual(set(marker["backup_artifacts"]), set(ALLOCATION_IDS))
            self.assertEqual(backend.cleanup_calls, 1)

    def test_lxc_command_is_exactly_bounded(self):
        with tempfile.TemporaryDirectory() as raw:
            _provisioner, _fs, _backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))
            args = build_pct_create_arguments(report.machine_plan)
            self.assertEqual(args[:4], ["pct", "create", "250", "local:vztmpl/ubuntu-26.04-standard_amd64.tar.zst"])
            self.assertIn("nesting=1", args)
            self.assertIn("--unprivileged", args)
            self.assertNotIn("mp0", " ".join(args))
            self.assertNotIn("gpu", " ".join(args).lower())

    def test_cleanup_failure_is_reported_without_hiding_original_error(self):
        with tempfile.TemporaryDirectory() as raw:
            provisioner, fs, backend, _store, _pki, _artifacts, report = make_provisioner(pathlib.Path(raw))

            def fail_after_guest(point: str) -> None:
                if point == "after_guest_os_ready:apt_update":
                    raise ProvisioningError("ORIGINAL_FAILURE", "original")

            def cleanup_failure(_vmid: int) -> None:
                raise ProvisioningError("SECURITY_CLEANUP_FAILED", "cleanup")

            provisioner.fault = fail_after_guest
            backend.cleanup_guest_secrets = cleanup_failure
            with self.assertRaises(ProvisioningError) as caught:
                provisioner.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            self.assertEqual(caught.exception.code, "ORIGINAL_FAILURE")
            self.assertIn("SECURITY_CLEANUP_FAILED", caught.exception.message)
            self.assertEqual(backend.status, "running")
            self.assertTrue(fs.path("/secrets/database-service/allocations/gitea/application-password").exists())


class CliSurfaceTests(unittest.TestCase):
    def test_only_contractual_commands_are_exposed(self):
        import importlib.util
        path = SCRIPTS / "postgresql-main-deploy.py"
        spec = importlib.util.spec_from_file_location("postgresql_main_deploy_cli", path)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader
        spec.loader.exec_module(module)
        parser = module.create_parser()
        commands = next(action for action in parser._actions if action.dest == "command").choices
        self.assertEqual(set(commands), {"apply", "resume-plan", "resume-apply"})
        for forbidden in ("--force", "--yes", "--skip-checks", "--rollback", "--mock", "--test-root"):
            self.assertNotIn(forbidden, parser.format_help())


if __name__ == "__main__":
    unittest.main()
