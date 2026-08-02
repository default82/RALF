"""Deterministic question catalog and answer validation."""

from __future__ import annotations

from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
import tomllib

from .models import ValidationError, canonical_json, validate_identifier


@dataclass(frozen=True)
class Question:
    question_id: str
    section: str
    prompt: str
    answer_type: str
    choices: tuple[str, ...]
    follows: str | None = None
    follows_value: str | None = None


def default_questions_path() -> Path:
    return Path(str(files("ralf_bootstrap.controller.catalog_data").joinpath("questions.toml")))


def load_questions(path: Path | None = None) -> tuple[Question, ...]:
    with Path(path or default_questions_path()).open("rb") as stream:
        data = tomllib.load(stream)
    if set(data) != {"schema_version", "catalog_version", "questions"}:
        raise ValidationError("Fragenkatalog besitzt unbekannte oder fehlende Schlüssel.")
    if data["schema_version"] != 1 or not isinstance(data["catalog_version"], int):
        raise ValidationError("Fragenkatalog besitzt eine unbekannte Version.")
    questions: list[Question] = []
    seen: set[str] = set()
    for raw in data["questions"]:
        allowed = {"id", "section", "prompt", "answer_type", "choices", "follows", "follows_value"}
        if set(raw) - allowed or not {"id", "section", "prompt", "answer_type"} <= set(raw):
            raise ValidationError("Frage besitzt unbekannte oder fehlende Schlüssel.")
        question_id = validate_identifier(raw["id"], "question_id")
        if question_id in seen:
            raise ValidationError("Fragenkatalog enthält doppelte IDs.")
        seen.add(question_id)
        choices = tuple(raw.get("choices", []))
        if raw["answer_type"] not in {"choice", "multi_choice", "text", "boolean"}:
            raise ValidationError("Frage besitzt einen unbekannten Antworttyp.")
        questions.append(
            Question(
                question_id,
                raw["section"],
                raw["prompt"],
                raw["answer_type"],
                choices,
                raw.get("follows"),
                raw.get("follows_value"),
            )
        )
    return tuple(questions)


def visible_questions(answers: dict[str, object], *, path: Path | None = None) -> tuple[Question, ...]:
    return tuple(
        question
        for question in load_questions(path)
        if question.follows is None or answers.get(question.follows) == question.follows_value
    )


def validate_answer(question_id: str, value: object, *, path: Path | None = None) -> str:
    questions = {question.question_id: question for question in load_questions(path)}
    if question_id not in questions:
        raise ValidationError("Unbekannte Fragen-ID.")
    question = questions[question_id]
    if question.answer_type == "choice":
        if not isinstance(value, str) or value not in question.choices:
            raise ValidationError("Antwort ist nicht im erlaubten Wertevorrat.")
    elif question.answer_type == "multi_choice":
        if not isinstance(value, list) or not value or any(item not in question.choices for item in value):
            raise ValidationError("Mehrfachantwort ist ungültig.")
        if len(value) != len(set(value)):
            raise ValidationError("Mehrfachantwort enthält Duplikate.")
    elif question.answer_type == "boolean":
        if not isinstance(value, bool):
            raise ValidationError("Antwort muss ein boolescher Wert sein.")
    elif not isinstance(value, str) or len(value.strip()) > 500:
        raise ValidationError("Textantwort ist ungültig.")
    return canonical_json(value)
