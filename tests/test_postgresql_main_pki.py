from __future__ import annotations

import pathlib
import shutil
import stat
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1] / "scripts"
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

from postgresql_main.filesystem import SecureFilesystem
from postgresql_main.models import ProvisioningError
from postgresql_main.pki import OpenSslRunner, PkiManager, load_policy


@unittest.skipUnless(shutil.which("openssl"), "openssl is unavailable")
class PkiIntegrationTests(unittest.TestCase):
    def make_manager(self, root: pathlib.Path, *, fault=lambda _point: None):
        pki = root / "secrets/database-service/providers/postgresql-main/pki"
        pki.mkdir(parents=True, mode=0o700, exist_ok=True)
        return PkiManager(
            SecureFilesystem(root), OpenSslRunner(),
            load_policy(REPO / "deploy/postgresql/pki-policy.toml"),
            serial_source=lambda: 123456789, fault=fault,
        )

    def test_real_pki_chain_san_key_match_and_modes(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            manager = self.make_manager(root)
            fingerprints = manager.generate("postgresql-main.example.internal", "10.20.0.10")
            self.assertEqual(set(fingerprints), {"ca", "server"})
            self.assertTrue(all(len(value) == 64 for value in fingerprints.values()))
            for name, mode in (("ca.key", 0o600), ("server.key", 0o600), ("ca.crt", 0o644), ("server.crt", 0o644)):
                info = manager.fs.path(manager.root / name).stat()
                self.assertEqual(stat.S_IMODE(info.st_mode), mode)
            self.assertEqual(
                fingerprints,
                manager.verify("postgresql-main.example.internal", "10.20.0.10"),
            )

    def test_partial_generation_is_resumed_without_replacing_ca_key(self):
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)

            def fail(point: str) -> None:
                if point == "after_ca_key":
                    raise ProvisioningError("INJECTED", point)

            manager = self.make_manager(root, fault=fail)
            with self.assertRaises(ProvisioningError):
                manager.generate("postgresql-main.example.internal", "10.20.0.10")
            ca_key = manager.fs.path(manager.root / "ca.key")
            before = ca_key.read_bytes()
            resumed = self.make_manager(root)
            resumed.generate("postgresql-main.example.internal", "10.20.0.10")
            self.assertEqual(ca_key.read_bytes(), before)

    def test_policy_is_exact_and_unknown_value_is_rejected(self):
        policy = load_policy(REPO / "deploy/postgresql/pki-policy.toml")
        self.assertEqual((policy.ca_key_bits, policy.server_key_bits), (4096, 3072))
        with tempfile.TemporaryDirectory() as raw:
            bad = pathlib.Path(raw) / "policy.toml"
            bad.write_text((REPO / "deploy/postgresql/pki-policy.toml").read_text().replace("397", "398"), encoding="utf-8")
            with self.assertRaises(ProvisioningError):
                load_policy(bad)


if __name__ == "__main__":
    unittest.main()
