from __future__ import annotations

import base64
import contextlib
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time

import pytest


CADDY_ENV = "RALF_CADDY_BIN"


def caddy_binary() -> Path:
    value = os.environ.get(CADDY_ENV)
    if not value:
        pytest.skip(f"{CADDY_ENV} ist nicht gesetzt")
    return Path(value)


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


class EchoHandler(BaseHTTPRequestHandler):
    records: list[dict[str, object]] = []

    def do_GET(self):  # noqa: N802 - stdlib handler API
        record = {
            "path": self.path,
            "headers": {key.lower(): value for key, value in self.headers.items()},
        }
        type(self).records.append(record)
        body = json.dumps(record, sort_keys=True).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):  # noqa: A002 - stdlib handler API
        return


@contextlib.contextmanager
def mock_upstream(port: int):
    EchoHandler.records = []
    server = ThreadingHTTPServer(("127.0.0.1", port), EchoHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield EchoHandler.records
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


class SNIHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, connect_host: str, port: int, server_name: str, context: ssl.SSLContext):
        super().__init__(connect_host, port, context=context, timeout=5)
        self._server_name = server_name

    def connect(self):
        raw = socket.create_connection((self.host, self.port), self.timeout)
        self.sock = self._context.wrap_socket(raw, server_hostname=self._server_name)


def https_request(
    fqdn: str,
    port: int,
    context: ssl.SSLContext,
    path: str = "/",
    headers: dict[str, str] | None = None,
    *,
    host: str | None = None,
) -> tuple[int, dict[str, str], bytes, dict[str, object]]:
    connection = SNIHTTPSConnection("127.0.0.1", port, fqdn, context)
    request_headers = {"Host": host or fqdn, **(headers or {})}
    connection.putrequest("GET", path, skip_host=True)
    for key, value in request_headers.items():
        connection.putheader(key, value)
    connection.endheaders()
    response = connection.getresponse()
    status = response.status
    response_headers = {key.lower(): value for key, value in response.getheaders()}
    body = response.read()
    certificate = connection.sock.getpeercert() if connection.sock is not None else {}
    connection.close()
    return status, response_headers, body, certificate


def basic_credentials(username: str, password: str) -> str:
    token = base64.b64encode(f"{username}:{password}".encode()).decode("ascii")
    return "Basic " + token


def listener_ports(pid: int) -> set[int]:
    inodes: set[str] = set()
    for descriptor in Path(f"/proc/{pid}/fd").iterdir():
        try:
            target = os.readlink(descriptor)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            inodes.add(match.group(1))
    ports: set[int] = set()
    for table in (Path("/proc/net/tcp"), Path("/proc/net/tcp6")):
        for line in table.read_text(encoding="ascii").splitlines()[1:]:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A" and fields[9] in inodes:
                ports.add(int(fields[1].split(":")[1], 16))
    return ports


def certificate_fingerprint(path: Path) -> str:
    pem = path.read_text(encoding="ascii")
    der = ssl.PEM_cert_to_DER_cert(pem)
    return hashlib.sha256(der).hexdigest()


def wait_for_caddy(
    process: subprocess.Popen[bytes],
    root_certificate: Path,
    fqdn: str,
    port: int,
) -> ssl.SSLContext:
    deadline = time.monotonic() + 15
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Caddy endete unerwartet mit {process.returncode}")
        if root_certificate.is_file():
            context = ssl.create_default_context(cafile=str(root_certificate))
            try:
                status, _, _, _ = https_request(fqdn, port, context)
                if status in {401, 403}:
                    return context
            except (OSError, ssl.SSLError) as exc:
                last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Caddy wurde nicht bereit: {type(last_error).__name__}")


@contextlib.contextmanager
def running_caddy(
    caddy: Path,
    caddyfile: Path,
    runtime: Path,
    fqdn: str,
    port: int,
):
    data = runtime / "data"
    config = runtime / "config"
    home = runtime / "home"
    for directory in (data, config, home):
        directory.mkdir(exist_ok=True)
    stdout_path = runtime / f"caddy-{port}.stdout.log"
    stderr_path = runtime / f"caddy-{port}.stderr.log"
    environment = {
        "HOME": str(home),
        "XDG_DATA_HOME": str(data),
        "XDG_CONFIG_HOME": str(config),
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LC_ALL": "C",
        "LANG": "C",
    }
    command = [str(caddy), "run", "--config", str(caddyfile), "--adapter", "caddyfile"]
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=environment)
        try:
            root_certificate = data / "caddy/pki/authorities/local/root.crt"
            context = wait_for_caddy(process, root_certificate, fqdn, port)
            yield process, context, root_certificate, environment, command
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            assert process.poll() is not None


def write_test_caddyfile(
    ingress_module,
    path: Path,
    config,
    password_hash: str,
    overrides,
) -> dict[str, object]:
    rendered = ingress_module.render_caddyfile(config, password_hash, overrides)
    path.write_text(rendered, encoding="utf-8")
    path.chmod(0o600)
    return ingress_module.validate_with_caddy(
        caddy_binary(), path, config, password_hash, overrides
    )


def test_caddy_version_and_production_validation(ingress_module, tmp_path):
    caddy = ingress_module.validate_caddy_binary(caddy_binary())
    result = subprocess.run([str(caddy), "version"], check=True, capture_output=True, text=True)
    assert result.stdout.startswith("v2.11.4 ")
    config = ingress_module.ProviderConfig(
        1, "caddy", "validation.home.arpa", ("10.10.0.0/16",), "validation-user"
    )
    password_hash = ingress_module.hash_password(caddy, secrets.token_urlsafe(24))
    caddyfile = tmp_path / "Caddyfile"
    caddyfile.write_text(ingress_module.render_caddyfile(config, password_hash), encoding="utf-8")
    caddyfile.chmod(0o600)
    adapted = ingress_module.validate_with_caddy(caddy, caddyfile, config, password_hash)
    assert adapted["admin"]["disabled"] is True
    assert adapted["admin"]["config"]["persist"] is False


def test_complete_tls_cidr_auth_proxy_and_header_contract(ingress_module, tmp_path):
    caddy = caddy_binary()
    fqdn = f"ralf-{secrets.token_hex(5)}.home.arpa"
    username = "test-" + secrets.token_hex(5)
    password = secrets.token_urlsafe(32)
    assert password not in os.environ.values()
    password_hash = ingress_module.hash_password(caddy, password)
    upstream_port = free_port()
    https_port = free_port()
    denied_port = free_port()
    allowed = ingress_module.ProviderConfig(
        1, "caddy", fqdn, ("127.0.0.1/32",), username
    )
    denied = ingress_module.ProviderConfig(
        1, "caddy", fqdn, ("192.0.2.0/24",), username
    )
    runtime_parent = tmp_path / "runtime-parent"
    runtime_parent.mkdir()
    with tempfile.TemporaryDirectory(dir=runtime_parent, prefix="caddy-runtime-") as name:
        runtime = Path(name)
        allowed_overrides = ingress_module.RenderOverrides(https_port, upstream_port)
        denied_overrides = ingress_module.RenderOverrides(denied_port, upstream_port)
        allowed_file = runtime / "Caddyfile.allowed"
        denied_file = runtime / "Caddyfile.denied"
        adapted = write_test_caddyfile(
            ingress_module, allowed_file, allowed, password_hash, allowed_overrides
        )
        write_test_caddyfile(
            ingress_module, denied_file, denied, password_hash, denied_overrides
        )
        assert adapted["admin"] == {"disabled": True, "config": {"persist": False}}
        assert adapted["apps"]["pki"]["certificate_authorities"]["local"] == {
            "install_trust": False
        }
        with mock_upstream(upstream_port) as records:
            before = len(records)
            with running_caddy(caddy, denied_file, runtime, fqdn, denied_port) as (
                denied_process,
                denied_context,
                _,
                _,
                _,
            ):
                status, headers, _, _ = https_request(
                    fqdn, denied_port, denied_context
                )
                assert status == 403
                assert "www-authenticate" not in headers
                assert len(records) == before
                assert 2019 not in listener_ports(denied_process.pid)

            with running_caddy(caddy, allowed_file, runtime, fqdn, https_port) as (
                process,
                context,
                root_certificate,
                environment,
                command,
            ):
                assert password not in "\n".join(command)
                assert password not in "\n".join(environment.values())
                ports = listener_ports(process.pid)
                assert https_port in ports
                assert 2019 not in ports
                private_key = runtime / "data/caddy/pki/authorities/local/root.key"
                assert root_certificate.is_file()
                assert private_key.is_file()
                assert root_certificate.is_relative_to(runtime / "data")
                assert private_key.is_relative_to(runtime / "data")
                fingerprint = certificate_fingerprint(root_certificate)
                assert re.fullmatch(r"[0-9a-f]{64}", fingerprint)
                with pytest.raises(ssl.SSLCertVerificationError):
                    https_request(fqdn, https_port, ssl.create_default_context())

                status, headers, _, certificate = https_request(fqdn, https_port, context)
                assert status == 401
                assert headers["www-authenticate"].startswith("Basic ")
                names = {value for kind, value in certificate.get("subjectAltName", ()) if kind == "DNS"}
                assert names == {fqdn}
                wrong_password = basic_credentials(username, "incorrect-password-value")
                assert https_request(
                    fqdn, https_port, context, headers={"Authorization": wrong_password}
                )[0] == 401
                wrong_user = basic_credentials("other-user", password)
                assert https_request(
                    fqdn, https_port, context, headers={"Authorization": wrong_user}
                )[0] == 401

                auth = basic_credentials(username, password)
                for path in ("/", "/healthz", "/api/v1/status"):
                    assert https_request(
                        fqdn, https_port, context, path, {"Authorization": auth}
                    )[0] == 200

                before_wrong_host = len(records)
                wrong_status, _, wrong_body, _ = https_request(
                    fqdn,
                    https_port,
                    context,
                    headers={"Authorization": auth},
                    host="wrong.home.arpa",
                )
                assert wrong_status in {200, 404, 421}
                assert wrong_body == b""
                assert len(records) == before_wrong_host

                spoofed = {
                    "Authorization": auth,
                    "Proxy-Authorization": "Basic spoofed",
                    "Forwarded": "for=198.51.100.10;proto=http",
                    "X-Real-IP": "198.51.100.11",
                    "X-Forwarded-For": "198.51.100.12",
                    "X-Forwarded-Host": "attacker.example",
                    "X-Forwarded-Proto": "http",
                    "X-RALF-Authenticated-User": "attacker",
                    "X-RALF-Admin": "true",
                }
                status, _, body, _ = https_request(
                    fqdn, https_port, context, "/headers", spoofed
                )
                assert status == 200
                observed = json.loads(body)["headers"]
                assert "authorization" not in observed
                assert "proxy-authorization" not in observed
                assert "forwarded" not in observed
                assert "x-real-ip" not in observed
                assert "x-ralf-admin" not in observed
                assert observed["x-ralf-authenticated-user"] == username
                assert observed["x-forwarded-for"] == "127.0.0.1"
                assert observed["x-forwarded-proto"] == "https"
                assert observed["x-forwarded-host"] == fqdn
                assert observed["host"] == fqdn

            autosave = runtime / "config/caddy/autosave.json"
            assert not autosave.exists()
            secret_bytes = password.encode()
            hash_occurrences: list[Path] = []
            for file in runtime.rglob("*"):
                if not file.is_file():
                    continue
                content = file.read_bytes()
                assert secret_bytes not in content
                if password_hash.encode() in content:
                    hash_occurrences.append(file)
            assert set(hash_occurrences) == {allowed_file, denied_file}
    assert not any(runtime_parent.iterdir())
