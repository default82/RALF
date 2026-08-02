from __future__ import annotations

import http.client
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


def free_loopback_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_gunicorn(
    app_directory: Path,
    *,
    extra_arguments: list[str],
    home: Path,
) -> tuple[str, str]:
    port = free_loopback_port()
    env = os.environ.copy()
    env.pop("XDG_RUNTIME_DIR", None)
    env["HOME"] = str(home)
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "gunicorn",
            "--workers",
            "1",
            "--bind",
            f"127.0.0.1:{port}",
            *extra_arguments,
            "minimal_wsgi:application",
        ],
        cwd=app_directory,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        response = None
        for _ in range(30):
            try:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=0.2)
                connection.request("GET", "/")
                response = connection.getresponse()
                body = response.read().decode("ascii")
                connection.close()
                break
            except (ConnectionRefusedError, OSError):
                time.sleep(0.1)
        assert response is not None
        assert response.status == 200
        assert process.poll() is None
        time.sleep(0.2)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    stdout, stderr = process.communicate()
    assert process.poll() is not None
    return body, stdout + stderr


def make_minimal_wsgi_app(tmp_path: Path) -> Path:
    app_directory = tmp_path / "app"
    app_directory.mkdir()
    app_directory.joinpath("minimal_wsgi.py").write_text(
        "def application(environ, start_response):\n"
        "    start_response('200 OK', [('Content-Type', 'text/plain')])\n"
        "    return [b'ralf-ok']\n",
        encoding="utf-8",
    )
    return app_directory


def test_gunicorn_control_socket_error_is_reproduced_and_disabled(tmp_path):
    app_directory = make_minimal_wsgi_app(tmp_path)
    unusable_home = Path("/proc/ralf-bootstrap-unusable-home")

    body, logs = run_gunicorn(app_directory, extra_arguments=[], home=unusable_home)
    assert body == "ralf-ok"
    assert "Control server error:" in logs

    body, logs = run_gunicorn(
        app_directory,
        extra_arguments=["--no-control-socket"],
        home=unusable_home,
    )
    assert body == "ralf-ok"
    assert "Control server error:" not in logs
    assert not (unusable_home / ".gunicorn").exists()

    config = subprocess.run(
        [
            sys.executable,
            "-m",
            "gunicorn",
            "--print-config",
            "--no-control-socket",
            "minimal_wsgi:application",
        ],
        cwd=app_directory,
        env={**os.environ, "HOME": str(unusable_home), "XDG_RUNTIME_DIR": ""},
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert "control_socket_disable             = True" in config.stdout


def test_gunicorn_loopback_smoke(tmp_path):
    app_directory = make_minimal_wsgi_app(tmp_path)
    body, logs = run_gunicorn(
        app_directory,
        extra_arguments=["--no-control-socket"],
        home=Path("/proc/ralf-bootstrap-unusable-home"),
    )

    assert body == "ralf-ok"
    assert "Control server error:" not in logs
