"""Import the standalone planner without parsing its rendered CLI output."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import types
from functools import lru_cache


SCRIPT_ROOT = pathlib.Path(__file__).resolve().parents[1]
PLANNER_PATH = SCRIPT_ROOT / "postgresql-main-plan.py"


@lru_cache(maxsize=1)
def planner_module() -> types.ModuleType:
    spec = importlib.util.spec_from_file_location("ralf_postgresql_main_plan", PLANNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Planermodul kann nicht geladen werden: {PLANNER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def create_plan_report(*args, **kwargs):
    """Return the shared PlanReport used by both planner and deployer."""
    return planner_module().create_plan_report(*args, **kwargs)
