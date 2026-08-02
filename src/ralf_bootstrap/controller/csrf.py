"""Single-use form-bound CSRF tokens stored only as SHA-256 hashes."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
import secrets

from .models import ValidationError, validate_identifier
from .storage import transaction, utc_now


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def issue_token(database: Path, form_id: str, *, lifetime_seconds: int = 600) -> str:
    form_id = validate_identifier(form_id, "Formular")
    if lifetime_seconds < 1 or lifetime_seconds > 3600:
        raise ValidationError("Ungültige CSRF-Gültigkeitsdauer.")
    token = secrets.token_urlsafe(32)
    expires = (datetime.now(timezone.utc) + timedelta(seconds=lifetime_seconds)).isoformat().replace("+00:00", "Z")
    with transaction(database) as connection:
        connection.execute(
            "DELETE FROM csrf_tokens WHERE consumed_at IS NOT NULL OR expires_at < ?", (utc_now(),)
        )
        connection.execute(
            "INSERT INTO csrf_tokens(token_hash, form_id, expires_at, consumed_at) VALUES (?, ?, ?, NULL)",
            (_hash(token), form_id, expires),
        )
    return token


def consume_token(database: Path, form_id: str, token: object, *, now: str | None = None) -> None:
    form_id = validate_identifier(form_id, "Formular")
    if not isinstance(token, str) or not token or len(token) > 256:
        raise ValidationError("CSRF-Token fehlt oder ist ungültig.")
    current = now or utc_now()
    with transaction(database) as connection:
        row = connection.execute(
            "SELECT form_id, expires_at, consumed_at FROM csrf_tokens WHERE token_hash=?",
            (_hash(token),),
        ).fetchone()
        if row is None or not secrets.compare_digest(row["form_id"], form_id):
            raise ValidationError("CSRF-Token ist ungültig.")
        if row["consumed_at"] is not None:
            raise ValidationError("CSRF-Token wurde bereits verwendet.")
        if row["expires_at"] <= current:
            raise ValidationError("CSRF-Token ist abgelaufen.")
        connection.execute(
            "UPDATE csrf_tokens SET consumed_at=? WHERE token_hash=?", (current, _hash(token))
        )
