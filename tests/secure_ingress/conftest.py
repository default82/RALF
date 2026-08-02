from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

import pytest


@pytest.fixture(scope="session")
def ingress_module():
    script = Path(__file__).parents[2] / "scripts" / "ralf-secure-ingress-caddy.py"
    spec = importlib.util.spec_from_file_location("ralf_secure_ingress_caddy", script)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module
