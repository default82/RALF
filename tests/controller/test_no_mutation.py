from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).parents[2]
CONTROLLER = ROOT / "src/ralf_bootstrap/controller"


def test_controller_has_no_command_or_network_execution_imports():
    forbidden_modules = {"subprocess", "socket", "urllib.request", "requests", "http.client"}
    for path in CONTROLLER.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        imports = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.add(node.module)
        assert not (imports & forbidden_modules), (path, imports & forbidden_modules)


def test_planner_stores_no_shell_commands():
    text = (CONTROLLER / "planner.py").read_text(encoding="utf-8")
    forbidden = (
        "apt-get", "systemctl start", "systemctl stop", "systemctl restart", "pct ",
        "pvesh", "pvesm", "sudo ", "ssh ", "curl ", "wget ", "nmap", "masscan",
    )
    assert not any(value in text for value in forbidden)
