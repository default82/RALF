from __future__ import annotations

import hashlib

import pytest

from ralf_bootstrap.controller.csrf import consume_token, issue_token
from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.storage import connect


def test_token_is_hashed_bound_and_single_use(controller_db):
    token = issue_token(controller_db, "inventory.create")
    assert len(token) >= 43
    with connect(controller_db, read_only=True) as connection:
        row = connection.execute("SELECT * FROM csrf_tokens").fetchone()
        assert row["token_hash"] == hashlib.sha256(token.encode("ascii")).hexdigest()
        assert token not in "|".join(str(value) for value in row)
    with pytest.raises(ValidationError):
        consume_token(controller_db, "wrong.form", token)
    consume_token(controller_db, "inventory.create", token)
    with pytest.raises(ValidationError, match="bereits"):
        consume_token(controller_db, "inventory.create", token)


def test_missing_wrong_and_expired_tokens_fail(controller_db):
    with pytest.raises(ValidationError):
        consume_token(controller_db, "inventory.create", "")
    with pytest.raises(ValidationError):
        consume_token(controller_db, "inventory.create", "not-a-token")
    token = issue_token(controller_db, "inventory.create", lifetime_seconds=1)
    with pytest.raises(ValidationError, match="abgelaufen"):
        consume_token(controller_db, "inventory.create", token, now="9999-01-01T00:00:00Z")
