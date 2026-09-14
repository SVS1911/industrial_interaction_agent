"""Deterministic Intelligence & Recommendations Agent (Agent 28).

Agent 4 turns current PostgreSQL engagement evidence into reviewable
recommendations. It does not call an LLM and it never performs the suggested
business action itself.
"""

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from app.core.database import get_connection

AGENT_CODE = "A28_INDUSTRY_INTERACTION"
AGENT_VERSION = "1.2"
MODEL_VERSION = "recommendation-1.0"

# These thresholds are deliberately explicit so recommendation behaviour is
# deterministic and testable. MoU-specific renewal windows still come from
# engagement.mou.renewal_alert_days.
CRITICAL_EXPIRY_DAYS = 30
HIGH_EXPIRY_DAYS = 60
HIGH_OVERDUE_DAYS = 30
MEDIUM_OVERDUE_DAYS = 0
LOW_ACTIVITY_90DAYS = 1
STRONG_MIN_SCORE = 75.0


def _json_value(value: Any) -> Any:
    if isinstance(value, (UUID, date, datetime, Decimal)):
        return str(value)
    if isinstance(value, dict):
        return {k: _json_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_value(v) for v in value]
    return value


def _priority_rank(priority: str) -> int:
    return {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1}[priority]


def _expiry_priority(days_to_expiry: int | None) -> str:
    if days_to_expiry is not None and days_to_expiry <= CRITICAL_EXPIRY_DAYS:
        return "CRITICAL"
    if days_to_expiry is not None and days_to_expiry <= HIGH_EXPIRY_DAYS:
        return "HIGH"
    return "MEDIUM"


def _overdue_priority(days_overdue: int) -> str:
    return "HIGH" if days_overdue >= HIGH_OVERDUE_DAYS else "MEDIUM"


def _recommendations_for_partner(row: dict[str, Any], mous: list[dict[str, Any]], deliverables: list[dict[str, Any]]) -> list[dict[str, Any]]:
    recommendations: list[dict[str, Any]] = []
    partner_id = row["partner_id"]
    partner_name = row["partner_name"]
    health_band = row.get("health_band")
    health_score = float(row["health_score"]) if row.get("health_score") is not None else None
    days_since_activity = row.get("days_since_activity")

    expiring = [m for m in mous if m.get("expiring_without_renewal")]
    overdue = [d for d in deliverables if d.get("is_overdue")]

    # A critical renewal recommendation supersedes a plain dormant re-engage
    # recommendation for the same partner, preventing duplicate instructions
    # for the same underlying urgent condition.
    if expiring:
        mou = min(expiring, key=lambda x: (x.get("days_to_expiry") if x.get("days_to_expiry") is not None else 10**9))
        days = mou.get("days_to_expiry")
        priority = _expiry_priority(days)
        recommendations.append({
            "partner_id": str(partner_id),
            "partner_name": partner_name,
            "recommendation_type": "RENEW_MOU",
            "priority": priority,
            "title": "Initiate MoU renewal",
            "reason": (
                f"The active MoU '{mou['title']}' is in its renewal window and has no open renewal discussion. "
                f"It has {days} day(s) until expiry."
            ),
            "suggested_first_step": "Begin renewal discussion with the partner and record the discussion in the MoU renewal workflow.",
            "supporting_metrics": {
                "mou_id": str(mou["mou_id"]),
                "mou_expiry_date": _json_value(mou.get("valid_until")),
                "days_to_expiry": days,
                "health_band": health_band,
                "health_score": health_score,
            },
        })

    if overdue:
        worst = max(overdue, key=lambda x: x.get("days_overdue") or 0)
        days_overdue = int(worst.get("days_overdue") or 0)
        recommendations.append({
            "partner_id": str(partner_id),
            "partner_name": partner_name,
            "recommendation_type": "FOLLOW_UP_DELIVERABLE",
            "priority": _overdue_priority(days_overdue),
            "title": "Follow up on overdue MoU deliverable",
            "reason": (
                f"The deliverable '{worst['description']}' is incomplete and {days_overdue} day(s) overdue."
            ),
            "suggested_first_step": "Contact the responsible owner, confirm the current fulfilment status, and record the next committed date.",
            "supporting_metrics": {
                "mou_deliverable_id": str(worst["mou_deliverable_id"]),
                "mou_id": str(worst["mou_id"]),
                "due_date": _json_value(worst.get("due_date")),
                "days_overdue": days_overdue,
                "achievement_pct": _json_value(worst.get("achievement_pct")),
                "health_band": health_band,
            },
        })

    if health_band == "DORMANT":
        # If renewal is already the urgent issue, the renewal recommendation
        # is sufficient; otherwise recommend re-engagement.
        if not expiring:
            recommendations.append({
                "partner_id": str(partner_id),
                "partner_name": partner_name,
                "recommendation_type": "RE_ENGAGE_PARTNER",
                "priority": "HIGH",
                "title": "Re-engage dormant partner",
                "reason": (
                    f"Partner engagement is classified as DORMANT by Agent 3. "
                    f"The last realised activity was {days_since_activity} day(s) ago."
                    if days_since_activity is not None
                    else "Partner engagement is classified as DORMANT by Agent 3 and no recent realised activity is recorded."
                ),
                "suggested_first_step": "Schedule a relationship-owner review and identify one concrete near-term engagement opportunity.",
                "supporting_metrics": {
                    "health_band": health_band,
                    "health_score": health_score,
                    "days_since_last_activity": days_since_activity,
                },
            })
    elif health_band == "AT_RISK":
        recommendations.append({
            "partner_id": str(partner_id),
            "partner_name": partner_name,
            "recommendation_type": "INCREASE_ACTIVITY",
            "priority": "HIGH" if health_score is not None and health_score < 35 else "MEDIUM",
            "title": "Increase engagement activity",
            "reason": (
                f"Agent 3 classified the partnership as AT_RISK with a health score of {health_score:.2f}. "
                "A targeted engagement intervention is warranted."
                if health_score is not None
                else "Agent 3 classified the partnership as AT_RISK, indicating that engagement needs attention."
            ),
            "suggested_first_step": "Review the relationship with the owner and schedule a concrete partner interaction in the near term.",
            "supporting_metrics": {
                "health_band": health_band,
                "health_score": health_score,
                "activities_12m": row.get("activities_12m"),
                "internships_12m": row.get("internships_12m"),
                "offers_12m": row.get("offers_12m"),
            },
        })
    elif health_band == "STABLE" and (days_since_activity is None or days_since_activity > 90):
        recommendations.append({
            "partner_id": str(partner_id),
            "partner_name": partner_name,
            "recommendation_type": "INCREASE_ACTIVITY",
            "priority": "MEDIUM",
            "title": "Increase partner activity",
            "reason": "The partnership is STABLE, but recent realised engagement is low.",
            "suggested_first_step": "Plan a near-term industry activity aligned with the partner's existing relationship scope.",
            "supporting_metrics": {
                "health_band": health_band,
                "health_score": health_score,
                "days_since_last_activity": days_since_activity,
                "activities_12m": row.get("activities_12m"),
            },
        })
    elif health_band == "STRONG" and health_score is not None and health_score >= STRONG_MIN_SCORE:
        # Expansion is only recommended when there is evidence of meaningful
        # student/industry engagement, rather than from the score alone.
        outcome_count = int(row.get("internships_12m") or 0) + int(row.get("offers_12m") or 0)
        activity_count = int(row.get("activities_12m") or 0)
        if outcome_count > 0 and activity_count > 0:
            recommendations.append({
                "partner_id": str(partner_id),
                "partner_name": partner_name,
                "recommendation_type": "EXPAND_COLLABORATION",
                "priority": "LOW",
                "title": "Explore deeper collaboration",
                "reason": (
                    f"The partnership is STRONG ({health_score:.2f}) and has both recent industry activity "
                    f"and student outcomes, supporting a measured expansion opportunity."
                ),
                "suggested_first_step": "Review the partner's existing engagement and identify one additional collaboration area such as internships, projects, research, or joint events.",
                "supporting_metrics": {
                    "health_band": health_band,
                    "health_score": health_score,
                    "activities_12m": activity_count,
                    "internships_12m": int(row.get("internships_12m") or 0),
                    "offers_12m": int(row.get("offers_12m") or 0),
                },
            })

    # Deterministic order makes API output and tests stable.
    return sorted(recommendations, key=lambda r: (-_priority_rank(r["priority"]), r["recommendation_type"]))


PARTNER_QUERY = """
WITH partners AS (
    SELECT
        ip.industry_partner_id AS partner_id,
        ip.name AS partner_name,
        ip.status AS partner_status,
        h.health_score,
        h.health_band,
        h.is_dormant,
        h.as_of_date AS health_as_of_date,
        h.last_activity_on,
        h.days_since_last_activity,
        h.activities_12m,
        h.internships_12m,
        h.offers_12m
    FROM engagement.industry_partner ip
    LEFT JOIN LATERAL (
        SELECT s.*
        FROM engagement.partner_health_snapshot s
        WHERE s.industry_partner_id = ip.industry_partner_id
          AND s.as_of_date <= %(as_of_date)s
        ORDER BY s.as_of_date DESC, s.computed_at DESC
        LIMIT 1
    ) h ON true
    WHERE ip.status IN ('ACTIVE', 'DORMANT')
      AND ip.created_at::date <= %(as_of_date)s
),
activity AS (
    SELECT
        l.industry_partner_id AS partner_id,
        max(l.event_date) FILTER (WHERE l.is_realised AND l.event_date <= %(as_of_date)s) AS last_activity_on
    FROM engagement.v_partner_activity_ledger l
    GROUP BY l.industry_partner_id
)
SELECT
    p.*,
    a.last_activity_on AS ledger_last_activity_on,
    CASE
        WHEN COALESCE(p.last_activity_on, a.last_activity_on) IS NULL THEN NULL
        ELSE (%(as_of_date)s - COALESCE(p.last_activity_on, a.last_activity_on))::integer
    END AS computed_days_since_activity
FROM partners p
LEFT JOIN activity a ON a.partner_id = p.partner_id
ORDER BY p.partner_name;
"""

MOU_QUERY = """
SELECT
    m.mou_id,
    m.industry_partner_id AS partner_id,
    m.title,
    m.valid_until,
    m.renewal_alert_days,
    (m.valid_until - %(as_of_date)s)::integer AS days_to_expiry,
    (
        m.status = 'ACTIVE'
        AND m.valid_until IS NOT NULL
        AND m.valid_until >= %(as_of_date)s
        AND (m.valid_until - %(as_of_date)s) <= COALESCE(m.renewal_alert_days, 90)
        AND NOT EXISTS (
            SELECT 1
            FROM engagement.mou_renewal r
            WHERE r.mou_id = m.mou_id
              AND r.status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY')
              AND r.initiated_on <= %(as_of_date)s
        )
    ) AS expiring_without_renewal
FROM engagement.mou m
WHERE m.status = 'ACTIVE'
  AND m.industry_partner_id IS NOT NULL
  AND m.valid_from IS NOT NULL
  AND m.valid_from <= %(as_of_date)s
  AND (m.valid_until IS NULL OR m.valid_until >= %(as_of_date)s)
ORDER BY m.valid_until NULLS LAST;
"""

DELIVERABLE_QUERY = """
SELECT
    d.mou_deliverable_id,
    d.mou_id,
    m.industry_partner_id AS partner_id,
    d.description,
    d.due_date,
    d.status,
    d.target_count,
    d.achieved_count,
    CASE WHEN d.target_count > 0
         THEN round(100.0 * LEAST(d.achieved_count, d.target_count) / d.target_count, 2)
    END AS achievement_pct,
    CASE
        WHEN d.status IN ('PENDING','IN_PROGRESS')
         AND d.due_date IS NOT NULL
         AND d.due_date < %(as_of_date)s
        THEN true ELSE false
    END AS is_overdue,
    CASE
        WHEN d.status IN ('PENDING','IN_PROGRESS')
         AND d.due_date IS NOT NULL
         AND d.due_date < %(as_of_date)s
        THEN (%(as_of_date)s - d.due_date)::integer
        ELSE 0
    END AS days_overdue
FROM engagement.mou_deliverable d
JOIN engagement.mou m ON m.mou_id = d.mou_id
WHERE m.industry_partner_id IS NOT NULL
  AND m.status = 'ACTIVE'
  AND m.valid_from IS NOT NULL
  AND m.valid_from <= %(as_of_date)s
  AND (m.valid_until IS NULL OR m.valid_until >= %(as_of_date)s)
ORDER BY d.due_date NULLS LAST;
"""


def _get_agent_and_model(cur) -> tuple[dict[str, Any], dict[str, Any]]:
    cur.execute(
        """
        SELECT agent_id, version, requires_human_approval
        FROM agentops.agent
        WHERE code = %s AND status = 'ACTIVE'
        LIMIT 1
        """,
        (AGENT_CODE,),
    )
    agent = cur.fetchone()
    if not agent:
        raise RuntimeError(f"Active agent {AGENT_CODE} was not found in agentops.agent")

    cur.execute(
        """
        SELECT model_version_id, version, model_type
        FROM agentops.model_version
        WHERE agent_id = %s AND version = %s AND status = 'ACTIVE'
        LIMIT 1
        """,
        (agent["agent_id"], MODEL_VERSION),
    )
    model = cur.fetchone()
    if not model:
        raise RuntimeError(
            f"Active model {MODEL_VERSION} was not found for {AGENT_CODE}. "
            "Apply backend/database/migrations/002_agent4_recommendation_model.sql first."
        )
    if model["model_type"] != "RULE_BASED":
        raise RuntimeError(f"Agent 4 model {MODEL_VERSION} must be RULE_BASED")
    return agent, model


def _create_run(as_of_date: date, started: datetime) -> tuple[str, str, str]:
    with get_connection() as conn:
        try:
            with conn.cursor(row_factory=dict_row) as cur:
                agent, model = _get_agent_and_model(cur)
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
                        AGENT_VERSION,
                        Jsonb({"job": "INTELLIGENCE_RECOMMENDATIONS_RUN", "as_of_date": str(as_of_date)}),
                        "Generate deterministic, human-reviewable industry interaction recommendations.",
                        started,
                    ),
                )
                run_id = cur.fetchone()["agent_run_id"]
                conn.commit()
                return str(run_id), str(model["model_version_id"]), str(agent["agent_id"])
        except Exception:
            conn.rollback()
            raise


def _mark_failed(run_id: str, exc: Exception, started: datetime) -> None:
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                finished = datetime.now(timezone.utc)
                cur.execute(
                    """
                    UPDATE agentops.agent_run
                    SET finished_at = %s,
                        latency_ms = %s,
                        status = 'FAILED',
                        failure_reason = %s
                    WHERE agent_run_id = %s
                    """,
                    (finished, int((finished - started).total_seconds() * 1000), str(exc)[:4000], run_id),
                )
                conn.commit()
    except Exception:
        # Do not hide the original agent failure if the failure bookkeeping
        # itself cannot reach PostgreSQL.
        pass


def run_intelligence_recommendations(as_of_date: date | None = None) -> dict[str, Any]:
    started = datetime.now(timezone.utc)
    target_date = as_of_date or date.today()
    run_id, model_id, agent_id = _create_run(target_date, started)

    try:
        with get_connection() as conn:
            try:
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(PARTNER_QUERY, {"as_of_date": target_date})
                    partners = cur.fetchall()
                    cur.execute(MOU_QUERY, {"as_of_date": target_date})
                    mous = cur.fetchall()
                    cur.execute(DELIVERABLE_QUERY, {"as_of_date": target_date})
                    deliverables = cur.fetchall()

                    # Agent 3's snapshot is a first-class dependency. If a
                    # partner has no snapshot at/before the requested date, we
                    # do not invent a health band for it.
                    missing_health = [p["partner_name"] for p in partners if p.get("health_band") is None]
                    if missing_health:
                        raise RuntimeError(
                            "Agent 3 health data is missing for: " + ", ".join(missing_health[:20])
                        )

                    cur.execute(
                        """
                        INSERT INTO agentops.agent_run_input
                            (agent_run_id, source_schema, source_table, record_count, filter_expression)
                        VALUES
                            (%s, 'engagement', 'industry_partner', %s, %s),
                            (%s, 'engagement', 'mou', %s, %s),
                            (%s, 'engagement', 'mou_deliverable', %s, %s),
                            (%s, 'engagement', 'partner_health_snapshot', %s, %s),
                            (%s, 'engagement', 'v_partner_activity_ledger', %s, %s),
                            (%s, 'placement', 'company/offer/internship/job_opening', NULL, %s),
                            (%s, 'engagement', 'event', NULL, %s),
                            (%s, 'quality', 'feedback_response', NULL, %s)
                        """,
                        (
                            run_id, len(partners), f"ACTIVE/DORMANT, created_on <= {target_date}",
                            run_id, len(mous), f"ACTIVE MoUs effective on {target_date}",
                            run_id, len(deliverables), f"ACTIVE MoU deliverables effective on {target_date}",
                            run_id, len(partners), f"latest health snapshot <= {target_date}",
                            run_id, len(partners), f"realised partner ledger events <= {target_date}",
                            run_id, "placement relationships are represented in the partner activity ledger",
                            run_id, "events are represented when linked as fulfilment evidence",
                            run_id, "feedback is represented in Agent 3 health calculations",
                        ),
                    )

                    mous_by_partner: dict[Any, list[dict[str, Any]]] = {}
                    for item in mous:
                        mous_by_partner.setdefault(item["partner_id"], []).append(item)
                    deliverables_by_partner: dict[Any, list[dict[str, Any]]] = {}
                    for item in deliverables:
                        deliverables_by_partner.setdefault(item["partner_id"], []).append(item)

                    outputs: list[dict[str, Any]] = []
                    for partner in partners:
                        recs = _recommendations_for_partner(
                            partner,
                            mous_by_partner.get(partner["partner_id"], []),
                            deliverables_by_partner.get(partner["partner_id"], []),
                        )
                        for rec in recs:
                            payload = _json_value(rec)
                            payload["as_of_date"] = str(target_date)
                            interpretation = {
                                "model_version": MODEL_VERSION,
                                "agent_version": AGENT_VERSION,
                                "as_of_date": str(target_date),
                                "rule_based": True,
                                "human_approval_required": True,
                            }
                            # Idempotency: a repeat run for the same date must not create
                            # another copy of the same partner/recommendation condition.
                            cur.execute(
                                """
                                SELECT agent_output_id
                                FROM agentops.agent_output
                                WHERE output_type = 'RECOMMENDATION'
                                  AND subject_type = 'INDUSTRY_PARTNER'
                                  AND subject_id = %s
                                  AND payload->>'recommendation_type' = %s
                                  AND payload->>'as_of_date' = %s
                                LIMIT 1
                                """,
                                (partner["partner_id"], rec["recommendation_type"], str(target_date)),
                            )
                            if cur.fetchone():
                                continue

                            # Only JSONB columns receive psycopg.types.json.Jsonb wrappers.
                            cur.execute(
                                """
                                INSERT INTO agentops.agent_output (
                                    agent_run_id, output_type, subject_type, subject_id,
                                    payload, reasoning_summary, interpretation,
                                    confidence, requires_approval, approval_status
                                )
                                VALUES (
                                    %s, 'RECOMMENDATION', 'INDUSTRY_PARTNER', %s,
                                    %s, %s, %s,
                                    %s, true, 'PENDING'
                                )
                                RETURNING agent_output_id
                                """,
                                (
                                    run_id,
                                    partner["partner_id"],
                                    Jsonb(payload),
                                    rec["reason"],
                                    Jsonb(interpretation),
                                    Decimal("0.950"),
                                ),
                            )
                            output_id = cur.fetchone()["agent_output_id"]
                            outputs.append({
                                "agent_output_id": str(output_id),
                                **payload,
                                "approval_status": "PENDING",
                                "requires_approval": True,
                            })

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
                        "agent_run_id": run_id,
                        "agent": AGENT_CODE,
                        "agent_id": agent_id,
                        "agent_version": AGENT_VERSION,
                        "model_version": MODEL_VERSION,
                        "model_version_id": model_id,
                        "as_of_date": str(target_date),
                        "status": "SUCCEEDED",
                        "processed_partners": len(partners),
                        "recommendations_created": len(outputs),
                        "outputs": outputs,
                    }
            except Exception:
                conn.rollback()
                raise
    except Exception as exc:
        _mark_failed(run_id, exc, started)
        raise
