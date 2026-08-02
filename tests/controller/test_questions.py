import pytest

from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.questions import load_questions, validate_answer, visible_questions


def test_questions_are_deterministic_and_followups_are_relevant():
    assert load_questions() == load_questions()
    without = {item.question_id for item in visible_questions({"existing.secure-ingress": "nein"})}
    with_provider = {item.question_id for item in visible_questions({"existing.secure-ingress": "ja"})}
    assert "existing.secure-ingress.product" not in without
    assert "existing.secure-ingress.product" in with_provider


def test_answers_are_strictly_validated():
    assert validate_answer("environment.platform", "Proxmox") == '"Proxmox"'
    with pytest.raises(ValidationError):
        validate_answer("environment.platform", "invented")
    with pytest.raises(ValidationError):
        validate_answer("missing.question", "x")
