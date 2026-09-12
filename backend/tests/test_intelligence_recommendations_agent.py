from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest

from app.services import intelligence_recommendations_agent as agent


@pytest.fixture
def base_partner():
    return {
        "partner_id": uuid4(),
        "partner_name": "Test Partner",
        "health_score": Decimal("80.0"),
        "health_band": "STRONG",
        "is_dormant": False,
        "health_as_of_date": date(2026, 9, 1),
        "last_activity_on": date(2026, 8, 20),
        "days_since_activity": 12,
        "activities_12m": 4,
        "internships_12m": 2,
        "offers_12m": 3,
    }


def test_expiry_priority_boundaries():
    assert agent._expiry_priority(30) == "CRITICAL"
    assert agent._expiry_priority(31) == "HIGH"
    assert agent._expiry_priority(60) == "HIGH"
    assert agent._expiry_priority(61) == "MEDIUM"


def test_dormant_partner_gets_reengagement():
    row = {
        "partner_id": uuid4(),
        "partner_name": "Dormant Partner",
        "health_score": Decimal("91"),
        "health_band": "DORMANT",
        "days_since_activity": 201,
        "activities_12m": 0,
        "internships_12m": 0,
        "offers_12m": 0,
    }

    recs = agent._recommendations_for_partner(row, [], [])

    assert len(recs) == 1
    assert recs[0]["recommendation_type"] == "RE_ENGAGE_PARTNER"
    assert recs[0]["priority"] == "HIGH"


def test_dormant_with_expiring_mou_prioritises_renewal():
    partner_id = uuid4()

    row = {
        "partner_id": partner_id,
        "partner_name": "Dormant Partner",
        "health_score": Decimal("42"),
        "health_band": "DORMANT",
        "days_since_activity": 200,
        "activities_12m": 0,
        "internships_12m": 0,
        "offers_12m": 0,
    }

    mou = {
        "mou_id": uuid4(),
        "partner_id": partner_id,
        "title": "Industry MoU",
        "valid_until": date(2026, 9, 20),
        "days_to_expiry": 8,
        "expiring_without_renewal": True,
    }

    recs = agent._recommendations_for_partner(row, [mou], [])

    assert recs[0]["recommendation_type"] == "RENEW_MOU"
    assert recs[0]["priority"] == "CRITICAL"
    assert all(
        r["recommendation_type"] != "RE_ENGAGE_PARTNER"
        for r in recs
    )


def test_overdue_deliverable_creates_follow_up():
    partner_id = uuid4()

    row = {
        "partner_id": partner_id,
        "partner_name": "Partner",
        "health_score": Decimal("60"),
        "health_band": "STABLE",
        "days_since_activity": 10,
        "activities_12m": 3,
        "internships_12m": 1,
        "offers_12m": 1,
    }

    deliverable = {
        "mou_deliverable_id": uuid4(),
        "mou_id": uuid4(),
        "partner_id": partner_id,
        "description": "Guest lectures",
        "due_date": date(2026, 8, 1),
        "is_overdue": True,
        "days_overdue": 31,
        "achievement_pct": Decimal("25.00"),
    }

    recs = agent._recommendations_for_partner(
        row,
        [],
        [deliverable],
    )

    assert recs[0]["recommendation_type"] == "FOLLOW_UP_DELIVERABLE"
    assert recs[0]["priority"] == "HIGH"


def test_at_risk_partner_gets_medium_or_high_activity_recommendation():
    row = {
        "partner_id": uuid4(),
        "partner_name": "At Risk",
        "health_score": Decimal("40"),
        "health_band": "AT_RISK",
        "days_since_activity": 30,
        "activities_12m": 1,
        "internships_12m": 0,
        "offers_12m": 0,
    }

    recs = agent._recommendations_for_partner(
        row,
        [],
        [],
    )

    assert recs[0]["recommendation_type"] == "INCREASE_ACTIVITY"
    assert recs[0]["priority"] == "MEDIUM"


def test_strong_partner_requires_activity_and_student_outcomes_for_expansion(
    base_partner,
):
    # A STRONG health score alone must not trigger expansion.
    without_evidence = {
        **base_partner,
        "activities_12m": 0,
        "internships_12m": 0,
        "offers_12m": 0,
    }

    recs = agent._recommendations_for_partner(
        without_evidence,
        [],
        [],
    )

    assert recs == []

    # Activity alone is not enough.
    with_activity_only = {
        **base_partner,
        "activities_12m": 2,
        "internships_12m": 0,
        "offers_12m": 0,
    }

    recs = agent._recommendations_for_partner(
        with_activity_only,
        [],
        [],
    )

    assert recs == []

    # Both activity and student outcomes should trigger expansion.
    with_outcomes = {
        **base_partner,
        "activities_12m": 2,
        "internships_12m": 1,
    }

    recs = agent._recommendations_for_partner(
        with_outcomes,
        [],
        [],
    )

    assert recs[0]["recommendation_type"] == "EXPAND_COLLABORATION"
    assert recs[0]["priority"] == "LOW"


def test_jsonb_is_used_for_run_and_output_payloads():
    assert agent.Jsonb({"priority": "HIGH"}) is not None
    assert isinstance(
        agent.Jsonb({"priority": "HIGH"}),
        agent.Jsonb,
    )