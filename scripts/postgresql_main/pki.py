"""Versioned PostgreSQL provider PKI creation and verification."""

from __future__ import annotations

import dataclasses
import hashlib
import ipaddress
import os
import pathlib
import re
import subprocess
import tempfile
import tomllib
from collections.abc import Callable, Sequence

from .filesystem import SecureFilesystem
from .models import ProvisioningError


@dataclasses.dataclass(frozen=True)
class PkiPolicy:
    ca_key_bits: int
    ca_validity_days: int
    server_key_bits: int
    server_validity_days: int


def load_policy(path: pathlib.Path) -> PkiPolicy:
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ProvisioningError("PKI_POLICY_INVALID", str(path)) from exc
    if set(data) != {"schema_version", "ca", "server"} or data["schema_version"] != 1:
        raise ProvisioningError("PKI_POLICY_INVALID", "Unerwartetes Schema")
    ca, server = data["ca"], data["server"]
    if ca != {
        "key_algorithm": "rsa",
        "key_bits": 4096,
        "validity_days": 3650,
        "digest": "sha256",
    }:
        raise ProvisioningError("PKI_POLICY_INVALID", "CA-Policy weicht ab")
    if server != {
        "key_algorithm": "rsa",
        "key_bits": 3072,
        "validity_days": 397,
        "digest": "sha256",
        "extended_key_usage": ["serverAuth"],
    }:
        raise ProvisioningError("PKI_POLICY_INVALID", "Server-Policy weicht ab")
    return PkiPolicy(4096, 3650, 3072, 397)


class OpenSslRunner:
    def __init__(
        self,
        executor: Callable[..., subprocess.CompletedProcess[bytes]] = subprocess.run,
    ) -> None:
        self.executor = executor

    def run(self, arguments: Sequence[str], *, input_data: bytes | None = None) -> bytes:
        if not arguments or arguments[0] != "openssl":
            raise ProvisioningError("PKI_COMMAND_BLOCKED", "Nur openssl ist erlaubt")
        try:
            result = self.executor(
                list(arguments),
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ProvisioningError("PKI_COMMAND_FAILED", "OpenSSL konnte nicht ausgeführt werden") from exc
        if result.returncode != 0:
            raise ProvisioningError("PKI_COMMAND_FAILED", "OpenSSL-Prüfung oder Erzeugung fehlgeschlagen")
        return result.stdout


class PkiManager:
    def __init__(
        self,
        filesystem: SecureFilesystem,
        runner: OpenSslRunner,
        policy: PkiPolicy,
        *,
        pki_root: pathlib.Path = pathlib.Path(
            "/secrets/database-service/providers/postgresql-main/pki"
        ),
        serial_source: Callable[[], int],
        fault: Callable[[str], None] = lambda _point: None,
    ) -> None:
        self.fs = filesystem
        self.runner = runner
        self.policy = policy
        self.root = pki_root
        self.serial_source = serial_source
        self.fault = fault

    def _logical(self, name: str) -> pathlib.Path:
        return self.root / name

    def generate(self, fqdn: str, provider_ip: str) -> dict[str, str]:
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", fqdn):
            raise ProvisioningError("PKI_INPUT_INVALID", "FQDN ungültig")
        try:
            address = ipaddress.IPv4Address(provider_ip)
        except ipaddress.AddressValueError as exc:
            raise ProvisioningError("PKI_INPUT_INVALID", "Provider-IP ungültig") from exc
        existing = {
            name: self.fs.path(self._logical(name)).exists()
            for name in ("ca.key", "ca.crt", "server.key", "server.crt")
        }
        if existing["ca.crt"] and not existing["ca.key"]:
            raise ProvisioningError("PKI_PARTIAL_CONFLICT", "CA-Zertifikat ohne CA-Key")
        if existing["server.crt"] and not existing["server.key"]:
            raise ProvisioningError("PKI_PARTIAL_CONFLICT", "Serverzertifikat ohne Server-Key")
        for name, present in existing.items():
            if present:
                self.fs.validate(
                    self._logical(name),
                    kind="file",
                    mode=0o600 if name.endswith(".key") else 0o644,
                    require_nonempty=True,
                )
        root = self.fs.path(self.root)
        with tempfile.TemporaryDirectory(prefix=".pki.", dir=root) as raw_temp:
            temporary = pathlib.Path(raw_temp)
            os.chmod(temporary, 0o700)
            ca_key = temporary / "ca.key"
            ca_crt = temporary / "ca.crt"
            server_key = temporary / "server.key"
            server_csr = temporary / "server.csr"
            server_crt = temporary / "server.crt"
            ext_file = temporary / "server.ext"
            if not existing["ca.key"]:
                self.runner.run([
                    "openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt",
                    f"rsa_keygen_bits:{self.policy.ca_key_bits}", "-out", str(ca_key),
                ])
                self.fs.exclusive_bytes(self._logical("ca.key"), ca_key.read_bytes(), mode=0o600)
                self.fault("after_ca_key")
            published_ca_key = self.fs.path(self._logical("ca.key"))
            if not existing["ca.crt"]:
                self.runner.run([
                    "openssl", "req", "-new", "-x509", "-key", str(published_ca_key),
                    "-sha256", "-days", str(self.policy.ca_validity_days), "-subj",
                    "/CN=RALF postgresql-main CA", "-addext",
                    "basicConstraints=critical,CA:true,pathlen:0", "-addext",
                    "keyUsage=critical,keyCertSign,cRLSign", "-out", str(ca_crt),
                ])
                self.fs.exclusive_bytes(self._logical("ca.crt"), ca_crt.read_bytes(), mode=0o644)
                self.fault("after_ca_certificate")
            published_ca_crt = self.fs.path(self._logical("ca.crt"))
            if not existing["server.key"]:
                self.runner.run([
                    "openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt",
                    f"rsa_keygen_bits:{self.policy.server_key_bits}", "-out", str(server_key),
                ])
                self.fs.exclusive_bytes(self._logical("server.key"), server_key.read_bytes(), mode=0o600)
                self.fault("after_server_key")
            published_server_key = self.fs.path(self._logical("server.key"))
            if existing["server.crt"]:
                return self.verify(fqdn, provider_ip)
            self.runner.run([
                "openssl", "req", "-new", "-sha256", "-key", str(published_server_key),
                "-subj", f"/CN={fqdn}", "-out", str(server_csr),
            ])
            ext_file.write_text(
                "\n".join((
                    "basicConstraints=critical,CA:false",
                    "keyUsage=critical,digitalSignature,keyEncipherment",
                    "extendedKeyUsage=serverAuth",
                    f"subjectAltName=DNS:{fqdn},IP:{address}",
                    "",
                )),
                encoding="ascii",
            )
            os.chmod(ext_file, 0o600)
            serial = self.serial_source()
            if not 0 < serial < 2**159:
                raise ProvisioningError("PKI_SERIAL_INVALID", "Seriennummer ungültig")
            self.runner.run([
                "openssl", "x509", "-req", "-sha256", "-in", str(server_csr),
                "-CA", str(published_ca_crt), "-CAkey", str(published_ca_key), "-set_serial",
                f"0x{serial:x}", "-days", str(self.policy.server_validity_days),
                "-extfile", str(ext_file), "-out", str(server_crt),
            ])
            self.fs.exclusive_bytes(self._logical("server.crt"), server_crt.read_bytes(), mode=0o644)
            self.fault("after_server_certificate")
        return self.verify(fqdn, provider_ip)

    def verify(self, fqdn: str, provider_ip: str) -> dict[str, str]:
        ca_key = self.fs.path(self._logical("ca.key"))
        ca_crt = self.fs.path(self._logical("ca.crt"))
        server_key = self.fs.path(self._logical("server.key"))
        server_crt = self.fs.path(self._logical("server.crt"))
        self.fs.validate(self._logical("ca.key"), kind="file", mode=0o600, require_nonempty=True)
        self.fs.validate(self._logical("server.key"), kind="file", mode=0o600, require_nonempty=True)
        self.fs.validate(self._logical("ca.crt"), kind="file", mode=0o644, require_nonempty=True)
        self.fs.validate(self._logical("server.crt"), kind="file", mode=0o644, require_nonempty=True)
        self.runner.run(["openssl", "verify", "-CAfile", str(ca_crt), str(server_crt)])
        san_text = self.runner.run([
            "openssl", "x509", "-in", str(server_crt), "-noout", "-ext", "subjectAltName",
        ]).decode("utf-8", "replace")
        dns_names = re.findall(r"DNS:([^,\s]+)", san_text)
        ip_addresses = re.findall(r"IP Address:([^,\s]+)", san_text)
        if dns_names != [fqdn] or ip_addresses != [provider_ip]:
            raise ProvisioningError("PKI_SAN_MISMATCH", "Server-SAN stimmt nicht")
        text = self.runner.run([
            "openssl", "x509", "-in", str(server_crt), "-noout", "-text",
        ]).decode("utf-8", "replace")
        if "TLS Web Server Authentication" not in text or "CA:FALSE" not in text:
            raise ProvisioningError("PKI_CERTIFICATE_INVALID", "Serverzertifikat verletzt Policy")
        ca_text = self.runner.run([
            "openssl", "x509", "-in", str(ca_crt), "-noout", "-text",
        ]).decode("utf-8", "replace")
        if "CA:TRUE, pathlen:0" not in ca_text:
            raise ProvisioningError("PKI_CA_INVALID", "CA-Beschränkung fehlt")
        ca_key_public = self.runner.run(["openssl", "pkey", "-in", str(ca_key), "-pubout"])
        ca_cert_public = self.runner.run(["openssl", "x509", "-in", str(ca_crt), "-pubkey", "-noout"])
        if hashlib.sha256(ca_key_public).digest() != hashlib.sha256(ca_cert_public).digest():
            raise ProvisioningError("PKI_KEY_MISMATCH", "CA-Key und Zertifikat stimmen nicht")
        key_public = self.runner.run(["openssl", "pkey", "-in", str(server_key), "-pubout"])
        cert_public = self.runner.run(["openssl", "x509", "-in", str(server_crt), "-pubkey", "-noout"])
        if hashlib.sha256(key_public).digest() != hashlib.sha256(cert_public).digest():
            raise ProvisioningError("PKI_KEY_MISMATCH", "Server-Key und Zertifikat stimmen nicht")
        fingerprints: dict[str, str] = {}
        for name, path in (("ca", ca_crt), ("server", server_crt)):
            der = self.runner.run(["openssl", "x509", "-in", str(path), "-outform", "DER"])
            fingerprints[name] = hashlib.sha256(der).hexdigest()
        return fingerprints
