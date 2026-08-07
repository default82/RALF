from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.filesystem import SecureFilesystem
from postgresql_main.host import PASSWORD_PATHS, Provisioner
from postgresql_main.models import ALLOCATION_IDS, ProvisioningError
from postgresql_main_support import NOW, make_environment, secret_values


class SecureFilesystemTests(unittest.TestCase):
    def test_exclusive_secret_creation_and_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            (root / "secrets").mkdir(mode=0o700)
            fs = SecureFilesystem(root)
            logical = pathlib.Path("/secrets/value")
            fs.exclusive_bytes(logical, b"first")
            with self.assertRaises(FileExistsError):
                fs.exclusive_bytes(logical, b"second")
            fs.atomic_bytes(logical, b"second")
            self.assertEqual(fs.read_bytes(logical), b"second")
            self.assertEqual(fs.path(logical).stat().st_mode & 0o777, 0o600)

    def test_symlink_component_is_rejected(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            (root / "outside").mkdir()
            (root / "secrets").symlink_to(root / "outside", target_is_directory=True)
            with self.assertRaisesRegex(ProvisioningError, "Symlink"):
                SecureFilesystem(root).exclusive_bytes("/secrets/value", b"secret")


class ProvisionedSecretTests(unittest.TestCase):
    def test_exactly_four_independent_secrets_with_safe_metadata(self):
        with tempfile.TemporaryDirectory() as raw:
            fs, backend, store, pki, artifacts, report = make_environment(pathlib.Path(raw))
            counter = iter([("A" * 63) + str(index) for index in range(4)])
            provisioner = Provisioner(
                filesystem=fs, backend=backend, marker_store=store, pki=pki,
                plan_factory=lambda _path: report, token_source=lambda: next(counter),
                operation_id_source=lambda: "operation-1", clock=lambda: NOW,
                artifact_paths=artifacts,
            )
            marker = provisioner.apply(pathlib.Path("/secrets/database-service/providers/postgresql-main/deployment.toml"), report.machine_plan["plan_sha256"])
            values = secret_values(fs)
            self.assertEqual(len(values), 4)
            self.assertEqual(len(set(values)), 4)
            self.assertEqual(marker["phase"], "completed")
            for allocation in ALLOCATION_IDS:
                info = fs.path(PASSWORD_PATHS[allocation]).stat()
                self.assertEqual(info.st_mode & 0o777, 0o600)
                self.assertEqual((info.st_uid, info.st_gid), (0, 0))
            combined = repr(marker) + repr(backend.actions)
            for value in values:
                self.assertNotIn(value.decode(), combined)

    def test_foreign_secrets_tree_is_untouched(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            fs, backend, store, pki, artifacts, report = make_environment(root)
            foreign = root / "secrets/another-service/keep"
            foreign.parent.mkdir(parents=True)
            foreign.write_bytes(b"do-not-touch")
            foreign.chmod(0o600)
            provisioner = Provisioner(
                filesystem=fs, backend=backend, marker_store=store, pki=pki,
                plan_factory=lambda _path: report, token_source=lambda: "S" * 64,
                operation_id_source=lambda: "operation-1", clock=lambda: NOW,
                artifact_paths=artifacts,
            )
            provisioner.apply(pathlib.Path("/secrets/database-service/providers/postgresql-main/deployment.toml"), report.machine_plan["plan_sha256"])
            self.assertEqual(foreign.read_bytes(), b"do-not-touch")
            self.assertEqual(foreign.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
