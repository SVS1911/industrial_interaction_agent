"""Rule-based Engagement Health Agent for Agent 28.

This is the first real Agent 28 execution path.  It intentionally does not
use an LLM: the project SQL already defines a deterministic health model
(version health-1.0), so this agent computes that model from live PostgreSQL
data and records the run, inputs, health snapshots, and per-partner outputs.
"""

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from app.core.database import get_connection


HEALTH_MODEL_VERSION = "health-1.0"
AGENT_CODE = "A28_INDUSTRY_INTERACTION"
DORMANCY_DAYS = 180


HEALTH_QUERY = """
WITH base AS (
    SELECT
        ip.industry_partner_id AS partner_id,
        ip.name AS partner_name,
        ip.status AS partner_status,
        ip.created_at::date AS created_on,

        (
            SELECT max(l.event_date)
            FROM engagement.v_partner_activity_ledger l
            WHERE l.industry_partner_id = ip.industry_partner_id
              AND l.is_realised
              AND l.event_date <= %(as_of_date)s
        ) AS last_activity_on,

        (
            SELECT count(*)
            FROM engagement.industry_activity a
            WHERE a.industry_partner_id = ip.industry_partner_id
              AND a.status = 'CONDUCTED'
              AND a.activity_date > %(as_of_date)s - 365
              AND a.activity_date <= %(as_of_date)s
        )::integer AS activities_12m,

        (
            SELECT count(*)
            FROM placement.internship i
            JOIN placement.company c ON c.company_id = i.company_id
            WHERE c.industry_partner_id = ip.industry_partner_id
              AND i.status IN ('APPROVED','ONGOING','COMPLETED')
              AND i.from_date > %(as_of_date)s - 365
              AND i.from_date <= %(as_of_date)s
        )::integer AS internships_12m,

        (
            SELECT count(*)
            FROM placement.offer o
            JOIN placement.company c ON c.company_id = o.company_id
            WHERE c.industry_partner_id = ip.industry_partner_id
              AND o.status IN ('ACCEPTED','JOINED')
              AND o.offer_date > %(as_of_date)s - 365
              AND o.offer_date <= %(as_of_date)s
        )::integer AS offers_12m,

        COALESCE(mo.active_mous, 0)::integer AS active_mou_count,
        mo.ach_ratio::numeric AS achievement_ratio,
        mo.elapsed_ratio::numeric AS mou_elapsed_ratio,
        COALESCE(mo.deliverables_due, 0)::integer AS deliverables_due,
        COALESCE(mo.deliverables_achieved, 0)::integer AS deliverables_achieved,

        (
            SELECT count(*)
            FROM engagement.mou m
            WHERE m.industry_partner_id = ip.industry_partner_id
              AND m.status <> 'DRAFT'
              AND m.valid_from <= %(as_of_date)s
              AND m.valid_until >= %(as_of_date)s
              AND m.valid_until - %(as_of_date)s <= COALESCE(m.renewal_alert_days, 90)
              AND NOT EXISTS (
                  SELECT 1
                  FROM engagement.mou_renewal rr
                  WHERE rr.mou_id = m.mou_id
                    AND rr.initiated_on <= %(as_of_date)s
              )
        )::integer AS mous_expiring_without_renewal,

        (
            SELECT round(avg((fr.answers->>'overall_rating')::numeric), 2)
            FROM quality.feedback_response fr
            JOIN engagement.industry_activity a
              ON a.industry_activity_id = fr.target_id
            WHERE fr.target_type = 'INDUSTRY_ACTIVITY'
              AND a.industry_partner_id = ip.industry_partner_id
              AND (fr.submitted_at AT TIME ZONE 'Asia/Kolkata')::date <= %(as_of_date)s
              AND (fr.submitted_at AT TIME ZONE 'Asia/Kolkata')::date > %(as_of_date)s - 365
        ) AS avg_feedback_rating

    FROM engagement.industry_partner ip
    LEFT JOIN LATERAL (
        SELECT
            count(DISTINCT m.mou_id) AS active_mous,
            sum(LEAST(COALESCE(ev.achieved, 0), dl.target_count))
                FILTER (WHERE dl.target_count > 0)::numeric
                / NULLIF(sum(dl.target_count) FILTER (WHERE dl.target_count > 0), 0) AS ach_ratio,
            avg(
                GREATEST(
                    0,
                    LEAST(
                        1,
                        (%(as_of_date)s - m.valid_from)::numeric
                        / NULLIF(m.valid_until - m.valid_from, 0)
                    )
                )
            ) AS elapsed_ratio,
            count(dl.mou_deliverable_id) AS deliverables_due,
            count(*) FILTER (
                WHERE dl.target_count > 0
                  AND COALESCE(ev.achieved, 0) >= dl.target_count
            ) AS deliverables_achieved
        FROM engagement.mou m
        JOIN engagement.mou_deliverable dl ON dl.mou_id = m.mou_id
        LEFT JOIN LATERAL (
            SELECT sum(f.contributed_count) AS achieved
            FROM engagement.mou_deliverable_fulfilment f
            LEFT JOIN engagement.industry_activity ia
              ON ia.industry_activity_id = f.industry_activity_id
            LEFT JOIN placement.internship it
              ON it.internship_id = f.internship_id
            LEFT JOIN placement.offer o
              ON o.offer_id = f.offer_id
            LEFT JOIN placement.job_opening j
              ON j.job_opening_id = f.job_opening_id
            LEFT JOIN engagement.event e
              ON e.event_id = f.event_id
            WHERE f.mou_deliverable_id = dl.mou_deliverable_id
              AND f.status = 'CONFIRMED'
              AND COALESCE(ia.activity_date, it.from_date, o.offer_date, j.drive_date, e.from_date)
                    <= %(as_of_date)s
        ) ev ON true
        WHERE m.industry_partner_id = ip.industry_partner_id
          AND m.status <> 'DRAFT'
          AND m.valid_from <= %(as_of_date)s
          AND (m.valid_until IS NULL OR m.valid_until >= %(as_of_date)s)
    ) mo ON true
    WHERE ip.status IN ('ACTIVE','DORMANT')
      AND ip.created_at::date <= %(as_of_date)s
), components AS (
    SELECT
        b.*,
        CASE
            WHEN b.last_activity_on IS NULL THEN 0
            ELSE GREATEST(
                0,
                1 - LEAST(%(as_of_date)s - b.last_activity_on, 365) / 365.0
            )
        END AS recency_normalised,
        LEAST(b.activities_12m, 6) / 6.0 AS activity_volume_normalised,
        CASE
            WHEN b.active_mou_count = 0 OR b.achievement_ratio IS NULL THEN 0
            ELSE LEAST(
                1,
                b.achievement_ratio / GREATEST(COALESCE(b.mou_elapsed_ratio, 0), 0.25)
            )
        END AS deliverable_progress_normalised,
        LEAST(b.internships_12m + b.offers_12m, 20) / 20.0 AS student_outcomes_normalised,
        CASE
            WHEN b.avg_feedback_rating IS NULL THEN 0.5
            ELSE (b.avg_feedback_rating - 1) / 4
        END AS feedback_normalised,
        (%(as_of_date)s - COALESCE(b.last_activity_on, b.created_on)) > %(dormancy_days)s AS is_dormant
    FROM base b
)
SELECT
    c.*,
    round(
        100 * (
            0.25 * c.recency_normalised
          + 0.20 * c.activity_volume_normalised
          + 0.25 * c.deliverable_progress_normalised
          + 0.20 * c.student_outcomes_normalised
          + 0.10 * c.feedback_normalised
        ),
        2
    ) AS health_score
FROM components c
ORDER BY health_score DESC, partner_name;
"""


def _json_value(value: Any) -> Any:
    if isinstance(value, (UUID, date, datetime, Decimal)):
        return str(value)
    if isinstance(value, dict):
        return {k: _json_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_value(v) for v in value]
    return value


def _band(score: float, dormant: bool) -> str:
    if dormant:
        return "DORMANT"
    if score >= 75:
        return "STRONG"
    if score >= 50:
        return "STABLE"
    return "AT_RISK"


def run_engagement_health(as_of_date: date | None = None) -> dict[str, Any]:
    """Run Agent 28's deterministic engagement-health model."""
    started = datetime.now(timezone.utc)
    target_date = as_of_date or date.today()

    with get_connection() as conn:
        try:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    "SELECT agent_id FROM agentops.agent WHERE code = %s AND status = 'ACTIVE'",
                    (AGENT_CODE,),
                )
                agent = cur.fetchone()
                if not agent:
                    raise RuntimeError(f"Active agent {AGENT_CODE} was not found in agentops.agent")

                cur.execute(
                    """
                    SELECT model_version_id
                    FROM agentops.model_version
                    WHERE agent_id = %s AND version = %s AND status = 'ACTIVE'
                    ORDER BY validated_on DESC NULLS LAST
                    LIMIT 1
                    """,
                    (agent["agent_id"], HEALTH_MODEL_VERSION),
                )
                model = cur.fetchone()
                if not model:
                    raise RuntimeError(
                        f"Active model {HEALTH_MODEL_VERSION} was not found for {AGENT_CODE}"
                    )

                cur.execute(
                    """
                    INSERT INTO agentops.agent_run (
                        agent_id, agent_version, trigger_type, effective_role_id,
                        scope, request_text, started_at, status
                    )
                    VALUES (
                        %s, %s, 'USER',
                        (SELECT role_id FROM identity.role WHERE code = 'INDUSTRY_RELATIONS' LIMIT 1),
                        %s, %s, %s, 'RUNNING'
                    )
                    RETURNING agent_run_id
                    """,
                    (
                        agent["agent_id"],
                        "1.2",
                        Jsonb({"job": "ENGAGEMENT_HEALTH_RUN", "as_of_date": str(target_date)}),
                        "Refresh engagement health for all active and dormant industry partners.",
                        started,
                    ),
                )
                run_id = cur.fetchone()["agent_run_id"]

                cur.execute(
                    """
                    INSERT INTO agentops.agent_run_input
                        (agent_run_id, source_schema, source_table, record_count, filter_expression)
                    VALUES
                        (%s, 'engagement', 'industry_partner',
                         (SELECT count(*) FROM engagement.industry_partner
                          WHERE status IN ('ACTIVE','DORMANT') AND created_at::date <= %s),
                         %s)
                    """,
                    (
                        run_id,
                        target_date,
                        f"status IN ('ACTIVE','DORMANT'), as_of_date={target_date}",
                    ),
                )

                cur.execute(
                    HEALTH_QUERY,
                    {"as_of_date": target_date, "dormancy_days": DORMANCY_DAYS},
                )
                rows = cur.fetchall()

                outputs: list[dict[str, Any]] = []
                for row in rows:
                    score = float(row["health_score"] or 0)
                    dormant = bool(row["is_dormant"])
                    band = _band(score, dormant)
                    last_activity = row["last_activity_on"]
                    days_since = (
                        (target_date - last_activity).days if last_activity is not None else None
                    )

                    components = {
                        "recency": {
                            "normalised": round(float(row["recency_normalised"]), 3),
                            "weight": 0.25,
                            "contribution": round(25 * float(row["recency_normalised"]), 2),
                        },
                        "activity_volume": {
                            "normalised": round(float(row["activity_volume_normalised"]), 3),
                            "weight": 0.20,
                            "contribution": round(20 * float(row["activity_volume_normalised"]), 2),
                        },
                        "deliverable_progress": {
                            "normalised": round(float(row["deliverable_progress_normalised"]), 3),
                            "weight": 0.25,
                            "contribution": round(25 * float(row["deliverable_progress_normalised"]), 2),
                            "achievement_ratio": (round(float(row["achievement_ratio"]), 3) if row["achievement_ratio"] is not None else None),
                            "mou_elapsed_ratio": (round(float(row["mou_elapsed_ratio"]), 3) if row["mou_elapsed_ratio"] is not None else None),
                        },
                        "student_outcomes": {
                            "normalised": round(float(row["student_outcomes_normalised"]), 3),
                            "weight": 0.20,
                            "contribution": round(20 * float(row["student_outcomes_normalised"]), 2),
                        },
                        "feedback": {
                            "normalised": round(float(row["feedback_normalised"]), 3),
                            "weight": 0.10,
                            "contribution": round(10 * float(row["feedback_normalised"]), 2),
                        },
                    }

                    cur.execute(
                        """
                        INSERT INTO engagement.partner_health_snapshot (
                            industry_partner_id, as_of_date, model_version_id, agent_run_id,
                            health_score, health_band, is_dormant, components,
                            last_activity_on, days_since_last_activity,
                            activities_12m, internships_12m, offers_12m,
                            active_mou_count, deliverables_due, deliverables_achieved,
                            avg_feedback_rating, mous_expiring_without_renewal
                        )
                        VALUES (
                            %s, %s, %s, %s,
                            %s, %s, %s, %s,
                            %s, %s,
                            %s, %s, %s,
                            %s, %s, %s,
                            %s, %s
                        )
                        ON CONFLICT (industry_partner_id, as_of_date, model_version_id)
                        DO UPDATE SET
                            agent_run_id = EXCLUDED.agent_run_id,
                            health_score = EXCLUDED.health_score,
                            health_band = EXCLUDED.health_band,
                            is_dormant = EXCLUDED.is_dormant,
                            components = EXCLUDED.components,
                            last_activity_on = EXCLUDED.last_activity_on,
                            days_since_last_activity = EXCLUDED.days_since_last_activity,
                            activities_12m = EXCLUDED.activities_12m,
                            internships_12m = EXCLUDED.internships_12m,
                            offers_12m = EXCLUDED.offers_12m,
                            active_mou_count = EXCLUDED.active_mou_count,
                            deliverables_due = EXCLUDED.deliverables_due,
                            deliverables_achieved = EXCLUDED.deliverables_achieved,
                            avg_feedback_rating = EXCLUDED.avg_feedback_rating,
                            mous_expiring_without_renewal = EXCLUDED.mous_expiring_without_renewal,
                            computed_at = now()
                        RETURNING partner_health_snapshot_id
                        """,
                        (
                            row["partner_id"], target_date, model["model_version_id"], run_id,
                            score, band, dormant, Jsonb(components),
                            last_activity, days_since,
                            row["activities_12m"], row["internships_12m"], row["offers_12m"],
                            row["active_mou_count"], row["deliverables_due"], row["deliverables_achieved"],
                            row["avg_feedback_rating"], row["mous_expiring_without_renewal"],
                        ),
                    )
                    snapshot_id = cur.fetchone()["partner_health_snapshot_id"]

                    cur.execute(
                        """
                        INSERT INTO agentops.agent_output (
                            agent_run_id, output_type, subject_type, subject_id,
                            payload, reasoning_summary, interpretation,
                            confidence, requires_approval, approval_status
                        )
                        VALUES (
                            %s, 'CLASSIFICATION', 'INDUSTRY_PARTNER', %s,
                            %s, %s, %s,
                            0.950, false, 'NOT_REQUIRED'
                        )
                        RETURNING agent_output_id
                        """,
                        (
                            run_id,
                            row["partner_id"],
                            Jsonb({
                                "partner_id": str(row["partner_id"]),
                                "partner_name": row["partner_name"],
                                "health_score": score,
                                "health_band": band,
                                "is_dormant": dormant,
                                "last_activity_on": str(last_activity) if last_activity else None,
                                "days_since_last_activity": days_since,
                                "components": components,
                                "active_mou_count": row["active_mou_count"],
                                "deliverables_due": row["deliverables_due"],
                                "deliverables_achieved": row["deliverables_achieved"],
                                "activities_12m": row["activities_12m"],
                                "internships_12m": row["internships_12m"],
                                "offers_12m": row["offers_12m"],
                                "avg_feedback_rating": (
                                    float(row["avg_feedback_rating"])
                                    if row["avg_feedback_rating"] is not None
                                    else None
                                ),
                                "mous_expiring_without_renewal": row["mous_expiring_without_renewal"],
                                "snapshot_id": str(snapshot_id),
                            }),
                            (
                                f"Health score {score:.2f} classified {row['partner_name']} as {band}. "
                                f"The score uses the active Agent 28 health-1.0 rule set: "
                                "recency 25%, activity volume 20%, deliverable progress 25%, "
                                "student outcomes 20%, and feedback 10%."
                            ),
                            Jsonb({
                                "model_version": HEALTH_MODEL_VERSION,
                                "as_of_date": str(target_date),
                                "dormancy_days": DORMANCY_DAYS,
                                "rule_based": True,
                            }),
                        ),
                    )
                    output_id = cur.fetchone()["agent_output_id"]

                    cur.execute(
                        """
                        UPDATE engagement.industry_partner
                        SET engagement_score = %s,
                            last_activity_on = %s
                        WHERE industry_partner_id = %s
                        """,
                        (score, last_activity, row["partner_id"]),
                    )

                    outputs.append(
                        {
                            "agent_output_id": str(output_id),
                            "partner_id": str(row["partner_id"]),
                            "partner_name": row["partner_name"],
                            "health_score": score,
                            "health_band": band,
                            "is_dormant": dormant,
                        }
                    )

                finished = datetime.now(timezone.utc)
                latency_ms = int((finished - started).total_seconds() * 1000)
                cur.execute(
                    """
                    UPDATE agentops.agent_run
                    SET finished_at = %s,
                        latency_ms = %s,
                        status = 'SUCCEEDED'
                    WHERE agent_run_id = %s
                    """,
                    (finished, latency_ms, run_id),
                )

                conn.commit()
                return {
                    "agent_run_id": str(run_id),
                    "agent": AGENT_CODE,
                    "agent_version": "1.2",
                    "model_version": HEALTH_MODEL_VERSION,
                    "as_of_date": str(target_date),
                    "status": "SUCCEEDED",
                    "processed_partners": len(rows),
                    "outputs": outputs,
                }
        except Exception:
            conn.rollback()
            raise
