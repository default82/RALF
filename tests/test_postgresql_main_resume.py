from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.host import CONFIG_PATH, Provisioner, build_resume_plan
from postgresql_main.models import ALLOCATION_IDS, MULTI_ITEM_PHASES, ProvisioningError
from postgresql_main_support import FakePki, NOW, make_environment


class FaultOnce:
    def __init__(self, target: str) -> None:
        self.target = target
        self.hit = False

    def __call__(self, point: str) -> None:
        if point == self.target and not self.hit:
            self.hit = True
            raise ProvisioningError("FAULT_INJECTED", point)


def provisioner_for(fs, backend, store, pki, artifacts, report, *, fault=lambda _point: None):
    return Provisioner(
        filesystem=fs, backend=backend, marker_store=store, pki=pki,
        plan_factory=lambda _path: report, token_source=lambda: "R" * 64,
        operation_id_source=lambda: "operation-1", clock=lambda: NOW,
        fault=fault, artifact_paths=artifacts,
    )


class ResumeTests(unittest.TestCase):
    def exercise_fault(self, point: str):
        temporary = tempfile.TemporaryDirectory()
        root = pathlib.Path(temporary.name)
        fs, backend, store, pki, artifacts, report = make_environment(root)
        fault = FaultOnce(point)
        initial = provisioner_for(fs, backend, store, pki, artifacts, report, fault=fault)
        with self.assertRaises(ProvisioningError):
            initial.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
        resume = build_resume_plan(
            filesystem=fs, backend=backend, marker_store=store, pki=pki,
            artifact_paths=artifacts, generated_at=NOW,
        )
        self.assertEqual(resume.status, "RESUME_READY", resume.document["conflicts"])
        continued = provisioner_for(fs, backend, store, pki, artifacts, report)
        marker = continued.resume(resume, resume.sha256)
        self.assertEqual(marker["phase"], "completed")
        return temporary, backend, marker

    def test_resume_after_marker_creation(self):
        temporary, backend, _marker = self.exercise_fault("after_marker")
        self.addCleanup(temporary.cleanup)
        self.assertEqual(backend.actions.count("pct create"), 1)

    def test_resume_after_first_secret_does_not_replace_it(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            fs, backend, store, pki, artifacts, report = make_environment(root)
            initial = provisioner_for(fs, backend, store, pki, artifacts, report, fault=FaultOnce("after_secret:gitea"))
            with self.assertRaises(ProvisioningError):
                initial.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            path = fs.path("/secrets/database-service/allocations/gitea/application-password")
            before = path.read_bytes()
            resume = build_resume_plan(filesystem=fs, backend=backend, marker_store=store, pki=pki, artifact_paths=artifacts, generated_at=NOW)
            marker = provisioner_for(fs, backend, store, pki, artifacts, report).resume(resume, resume.sha256)
            self.assertEqual(path.read_bytes(), before)
            self.assertEqual(marker["phase_progress"]["secrets_ready"], ["gitea", "openbao", "semaphore", "nodered"])

    def test_resume_does_not_repeat_pct_create_or_start(self):
        for point in ("after_pct_create", "after_pct_start"):
            with self.subTest(point=point):
                temporary, backend, _marker = self.exercise_fault(point)
                self.addCleanup(temporary.cleanup)
                self.assertEqual(backend.actions.count("pct create"), 1)
                self.assertEqual(backend.actions.count("pct start 250"), 1)

    def test_failed_start_is_conflict_and_never_retried(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            fs, backend, store, pki, artifacts, report = make_environment(root)

            def failed_start(vmid: int) -> None:
                backend.actions.append(f"pct start {vmid}")
                raise ProvisioningError("START_FAILED", "start")

            backend.start_lxc = failed_start
            with self.assertRaises(ProvisioningError):
                provisioner_for(fs, backend, store, pki, artifacts, report).apply(
                    CONFIG_PATH, report.machine_plan["plan_sha256"]
                )
            resume = build_resume_plan(
                filesystem=fs, backend=backend, marker_store=store, pki=pki,
                artifact_paths=artifacts, generated_at=NOW,
            )
            self.assertEqual(resume.status, "RESUME_CONFLICT")
            self.assertEqual(backend.actions.count("pct start 250"), 1)

    def test_resume_recognizes_completed_guest_item(self):
        temporary, backend, marker = self.exercise_fault("after_allocations_created:gitea")
        self.addCleanup(temporary.cleanup)
        self.assertEqual(backend.actions.count("guest allocations_created:gitea"), 1)
        self.assertEqual(marker["phase_progress"]["allocations_created"], ["gitea", "openbao", "semaphore", "nodered"])
        self.assertIn("guest secrets rehydrated", backend.actions)

    def test_resume_recognizes_published_backup(self):
        temporary, backend, marker = self.exercise_fault("after_backup:gitea")
        self.addCleanup(temporary.cleanup)
        self.assertEqual(backend.actions.count("backup gitea"), 1)
        self.assertIn("gitea", marker["backup_artifacts"])

    def test_unpublished_backup_temp_is_cleaned_and_recreated(self):
        temporary, backend, marker = self.exercise_fault("after_backup_stream:gitea")
        self.addCleanup(temporary.cleanup)
        self.assertEqual(backend.actions.count("backup gitea"), 2)
        self.assertIn("gitea", marker["backup_artifacts"])

    def test_inconsistent_completed_secret_is_resume_conflict(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            fs, backend, store, pki, artifacts, report = make_environment(root)
            initial = provisioner_for(fs, backend, store, pki, artifacts, report, fault=FaultOnce("after_pct_create"))
            with self.assertRaises(ProvisioningError):
                initial.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
            fs.path("/secrets/database-service/allocations/gitea/application-password").chmod(0o644)
            resume = build_resume_plan(filesystem=fs, backend=backend, marker_store=store, pki=pki, artifact_paths=artifacts, generated_at=NOW)
            self.assertEqual(resume.status, "RESUME_CONFLICT")

    def test_resume_hash_binds_state_not_generation_time(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            fs, backend, store, pki, artifacts, report = make_environment(root)
            with self.assertRaises(ProvisioningError):
                provisioner_for(fs, backend, store, pki, artifacts, report, fault=FaultOnce("after_marker")).apply(
                    CONFIG_PATH, report.machine_plan["plan_sha256"]
                )
            first = build_resume_plan(filesystem=fs, backend=backend, marker_store=store, pki=pki, artifact_paths=artifacts, generated_at="2026-08-06T12:00:00Z")
            second = build_resume_plan(filesystem=fs, backend=backend, marker_store=store, pki=pki, artifact_paths=artifacts, generated_at="2026-08-07T12:00:00Z")
            self.assertEqual(first.sha256, second.sha256)
            backend.clean = False
            changed = build_resume_plan(filesystem=fs, backend=backend, marker_store=store, pki=pki, artifact_paths=artifacts, generated_at=NOW)
            self.assertNotEqual(first.sha256, changed.sha256)

    def test_fault_injection_after_every_persistent_boundary_is_resumable(self):
        points = [
            "after_marker",
            *(f"after_directory:{item}" for item in MULTI_ITEM_PHASES["secret_directories_ready"]),
            *(f"after_secret:{item}" for item in ALLOCATION_IDS),
            "after_ca_key", "after_ca_certificate", "after_server_key", "after_server_certificate",
            "after_pct_create", "after_pct_start",
            *(f"after_bundle:{item}" for item in MULTI_ITEM_PHASES["guest_bundle_ready"]),
            *(
                f"after_{phase}:{item}"
                for phase in ("guest_os_ready", "postgresql_installed", "postgresql_configured", "allocations_created", "readiness_verified")
                for item in MULTI_ITEM_PHASES[phase]
            ),
            *(f"after_backup_stream:{item}" for item in ALLOCATION_IDS),
            *(f"after_backup:{item}" for item in ALLOCATION_IDS),
            "before_completion",
        ]
        for point in points:
            with self.subTest(point=point), tempfile.TemporaryDirectory() as raw:
                root = pathlib.Path(raw)
                fs, backend, store, _pki, artifacts, report = make_environment(root)
                fault = FaultOnce(point)
                pki = FakePki(fs, fault=fault)
                initial = provisioner_for(fs, backend, store, pki, artifacts, report, fault=fault)
                with self.assertRaises(ProvisioningError):
                    initial.apply(CONFIG_PATH, report.machine_plan["plan_sha256"])
                resumed_pki = FakePki(fs)
                resume = build_resume_plan(
                    filesystem=fs, backend=backend, marker_store=store, pki=resumed_pki,
                    artifact_paths=artifacts, generated_at=NOW,
                )
                self.assertEqual(resume.status, "RESUME_READY", (point, resume.document["conflicts"]))
                marker = provisioner_for(fs, backend, store, resumed_pki, artifacts, report).resume(resume, resume.sha256)
                self.assertEqual(marker["phase"], "completed")


if __name__ == "__main__":
    unittest.main()
