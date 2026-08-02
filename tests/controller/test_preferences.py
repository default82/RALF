import pytest

from ralf_bootstrap.controller.models import ValidationError
from ralf_bootstrap.controller.storage import list_rows, save_preference


def test_exactly_one_preferred_and_unique_fallback_rank(controller_db, run_id):
    save_preference(controller_db, run_id, "monitoring", "inventory:1", "monitor-one", "preferred")
    with pytest.raises(ValidationError):
        save_preference(controller_db, run_id, "monitoring", "inventory:2", "monitor-two", "preferred")
    save_preference(controller_db, run_id, "backup", "inventory:3", "backup-one", "allowed_fallback", 1)
    with pytest.raises(ValidationError):
        save_preference(controller_db, run_id, "backup", "inventory:4", "backup-two", "allowed_fallback", 1)


def test_recommendation_is_not_preferred_implicitly(controller_db, run_id):
    save_preference(controller_db, run_id, "monitoring", "catalog:later", "later", "recommend_then_confirm")
    row = list_rows(controller_db, "provider_preferences", run_id)[0]
    assert row["preference"] == "recommend_then_confirm"
