from __future__ import annotations

import re

import pytest

from ralf_bootstrap.app import create_app
from ralf_bootstrap.controller.storage import create_setup_run, init_database


@pytest.fixture
def controller_db(tmp_path):
    path = tmp_path / "state.db"
    init_database(path)
    return path


@pytest.fixture
def run_id(controller_db):
    return create_setup_run(controller_db)


@pytest.fixture
def app(controller_db):
    application = create_app(database_path=controller_db)
    application.config.update(TESTING=True)
    return application


@pytest.fixture
def client(app):
    return app.test_client()


def csrf_from(response, action: str | None = None) -> str:
    body = response.get_data(as_text=True)
    if action is not None:
        form = re.search(rf'<form[^>]+action="{re.escape(action)}"[^>]*>(.*?)</form>', body, re.DOTALL)
        assert form
        body = form.group(1)
    match = re.search(r'name="csrf_token" value="([^"]+)"', body)
    assert match
    return match.group(1)
