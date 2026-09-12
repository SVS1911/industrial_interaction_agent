from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest

from app.services import engagement_health_agent as agent


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows
        self.executed = []
        self._fetchone = None
        self._fetchall = []
        self._run_id = uuid4()
        self._snapshot_id = uuid4()
        self._output_id = uuid4()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, sql, params=None):
        self.executed.append((sql, params))
        normalized = " ".join(sql.split())
        if "SELECT agent_id FROM agentops.agent" in normalized:
            self._fetchone = {"agent_id": uuid4()}
        elif "SELECT model_version_id FROM agentops.model_version" in normalized:
            self._fetchone = {"model_version_id": uuid4()}
        elif "INSERT INTO agentops.agent_run (" in normalized:
            self._fetchone = {"agent_run_id": self._run_id}
        elif "INSERT INTO engagement.partner_health_snapshot (" in normalized:
            self._fetchone = {"partner_health_snapshot_id": self._snapshot_id}
        elif "INSERT INTO agentops.agent_output (" in normalized:
            self._fetchone = {"agent_output_id": self._output_id}
        elif normalized.startswith("WITH base AS"):
            self._fetchall = self.rows
        elif "INSERT INTO agentops.agent_run_input" in normalized:
            self._fetchone = None
        elif "UPDATE agentops.agent_run" in normalized:
            self._fetchone = None
        elif "UPDATE engagement.industry_partner" in normalized:
            self._fetchone = None

    def fetchone(self):
        value = self._fetchone
        self._fetchone = None
        return value

    def fetchall(self):
        return self._fetchall


class FakeConnection:
    def __init__(self, rows):
        self.cursor_obj = FakeCursor(rows)
        self.committed = False
        self.rolled_back = False

    def cursor(self, row_factory=None):
        return self.cursor_obj

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


@pytest.fixture
def sample_row():
    partner_id = uuid4()
    return {
        "partner_id": partner_id,
        "partner_name": "Test Partner",
        "created_on": date(2026, 1, 1),
        "last_activity_on": date(2026, 8, 1),
        "activities_12m": 4,
        "internships_12m": 2,
        "offers_12m": 3,
        "active_mou_count": 1,
        "achievement_ratio": Decimal("0.80"),
        "mou_elapsed_ratio": Decimal("0.50"),
        "deliverables_due": 5,
        "deliverables_achieved": 4,
        "avg_feedback_rating": Decimal("4.0"),
        "mous_expiring_without_renewal": 0,
        "recency_normalised": Decimal("0.95"),
        "activity_volume_normalised": Decimal("0.667"),
        "deliverable_progress_normalised": Decimal("1.0"),
        "student_outcomes_normalised": Decimal("0.25"),
        "feedback_normalised": Decimal("0.75"),
        "is_dormant": False,
        "health_score": Decimal("74.59"),
    }


def test_band_boundaries():
    assert agent._band(75, False) == "STRONG"
    assert agent._band(50, False) == "STABLE"
    assert agent._band(49.99, False) == "AT_RISK"
    assert agent._band(99, True) == "DORMANT"


def test_json_value_normalizes_postgres_scalar_types():
    value = {
        "id": uuid4(),
        "day": date(2026, 9, 1),
        "timestamp": agent.datetime(2026, 9, 1, 12, 30),
        "score": Decimal("12.50"),
        "nested": [Decimal("1.2")],
    }

    normalized = agent._json_value(value)

    assert all(isinstance(v, str) for v in normalized.values() if not isinstance(v, list))
    assert normalized["nested"] == ["1.2"]


def test_run_uses_jsonb_for_all_json_columns(monkeypatch, sample_row):
    fake_conn = FakeConnection([sample_row])
    monkeypatch.setattr(agent, "get_connection", lambda: fake_conn)

    result = agent.run_engagement_health(date(2026, 9, 1))

    assert result["status"] == "SUCCEEDED"
    assert result["processed_partners"] == 1
    assert fake_conn.committed is True
    assert fake_conn.rolled_back is False

    statements = fake_conn.cursor_obj.executed
    run_insert = next(p for sql, p in statements if "INSERT INTO agentops.agent_run (" in sql)
    snapshot_insert = next(p for sql, p in statements if "INSERT INTO engagement.partner_health_snapshot (" in sql)
    output_insert = next(p for sql, p in statements if "INSERT INTO agentops.agent_output (" in sql)

    assert isinstance(run_insert[2], agent.Jsonb)
    assert isinstance(snapshot_insert[7], agent.Jsonb)
    assert isinstance(output_insert[2], agent.Jsonb)
    assert isinstance(output_insert[4], agent.Jsonb)

    assert result["outputs"][0]["health_band"] == "STABLE"
