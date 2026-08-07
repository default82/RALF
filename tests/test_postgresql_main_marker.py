from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.filesystem import SecureFilesystem
from postgresql_main.marker import MarkerStore, new_marker, validate_marker
from postgresql_main.models import PHASES, ProvisioningError
from postgresql_main_support import COMMIT, NOW, make_environment


class MarkerTests(unittest.TestCase):
    def test_marker_and_plan_are_exclusive_atomic_files(self):
        with tempfile.TemporaryDirectory() as raw:
            fs, _backend, store, _pki, artifacts, report = make_environment(pathlib.Path(raw))
            marker = new_marker(
                operation_id="operation-1", repository_commit=COMMIT,
                plan=report.machine_plan,
                artifact_hashes={name: "b" * 64 for name in artifacts}, now=NOW,
            )
            store.create(marker, report.machine_plan)
            self.assertEqual(store.load()["in_progress_phase"], "planned")
            self.assertEqual(fs.path(store.marker_path).stat().st_mode & 0o777, 0o600)
            self.assertEqual(fs.path(store.plan_path).stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                store.create(marker, report.machine_plan)

    def test_phase_order_and_partial_progress_are_strict(self):
        with tempfile.TemporaryDirectory() as raw:
            _fs, _backend, store, _pki, artifacts, report = make_environment(pathlib.Path(raw))
            marker = new_marker(
                operation_id="operation-1", repository_commit=COMMIT,
                plan=report.machine_plan,
                artifact_hashes={name: "b" * 64 for name in artifacts}, now=NOW,
            )
            marker["completed_phases"] = ["planned", "secrets_ready"]
            marker["phase"] = "secrets_ready"
            with self.assertRaises(ProvisioningError):
                validate_marker(marker)

    def test_unknown_in_progress_item_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            _fs, _backend, _store, _pki, artifacts, report = make_environment(pathlib.Path(raw))
            marker = new_marker(
                operation_id="operation-1", repository_commit=COMMIT,
                plan=report.machine_plan,
                artifact_hashes={name: "b" * 64 for name in artifacts}, now=NOW,
            )
            marker["in_progress_item"] = "unknown"
            with self.assertRaisesRegex(ProvisioningError, "in_progress_item"):
                validate_marker(marker)

    def test_marker_never_contains_secret_material(self):
        with tempfile.TemporaryDirectory() as raw:
            _fs, _backend, _store, _pki, artifacts, report = make_environment(pathlib.Path(raw))
            marker = new_marker(
                operation_id="operation-1", repository_commit=COMMIT,
                plan=report.machine_plan,
                artifact_hashes={name: "b" * 64 for name in artifacts}, now=NOW,
            )
            rendered = json.dumps(marker)
            self.assertNotIn("password", rendered.lower())
            self.assertNotIn("connection", rendered.lower())
            self.assertEqual(tuple(PHASES)[-1], "completed")


if __name__ == "__main__":
    unittest.main()
