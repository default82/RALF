from __future__ import annotations

import http.client
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


def test_gunicorn_loopback_smoke():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = os.environ.copy()
    env["PYTHONPATH"] = str(Path(__file__).parents[2] / "src")
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "gunicorn",
            "--workers",
            "1",
            "--bind",
            f"127.0.0.1:{port}",
            "ralf_bootstrap.app:app",
        ],
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
                connection.request("GET", "/healthz")
                response = connection.getresponse()
                response.read()
                connection.close()
                break
            except (ConnectionRefusedError, OSError):
                time.sleep(0.1)
        assert response is not None
        assert response.status == 200
        assert process.poll() is None
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    assert process.poll() is not None
