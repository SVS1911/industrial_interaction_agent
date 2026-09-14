"""Agent 2 - Activities / DO agent.

Connects realised industry interactions to the MoU promises they can fulfil.
The agent is deterministic: explicit database links are preferred, then a
small, explainable type match is used to suggest missing fulfilment links.
It never confirms a suggested link automatically.
"""
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID
from psycopg.types.json import Jsonb
from app.core.database import get_connection

AGENT_CODE = "A28_INDUSTRY_INTERACTION"
AGENT_VERSION = "1.2"
MODEL_VERSION = "activities-2.0"

TYPE_MAP = {
    "GUEST_LECTURE": {"GUEST_LECTURE"},
    "EXPERT_TALK": {"EXPERT_TALK", "TRAINING_PROGRAMME"},
    "INDUSTRY_VISIT": {"INDUSTRY_VISIT"},
    "FACULTY_EXCHANGE": {"FACULTY_EXCHANGE", "TRAINING_PROGRAMME"},
    "LAB_SUPPORT": {"LAB_SUPPORT"},
    "SPONSORED_PROJECT": {"SPONSORED_PROJECT"},
    "CONSULTANCY": {"CONSULTANCY"},
    "INTERNSHIP_DRIVE": {"INTERNSHIP"},
}


def _json(v: Any):
    if isinstance(v, (UUID, date, datetime, Decimal)):
        return str(v)
    if isinstance(v, dict):
        return {k: _json(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_json(x) for x in v]
    return v


def _get_agent_and_model(cur):
    cur.execute("SELECT agent_id FROM agentops.agent WHERE code=%s AND status='ACTIVE' LIMIT 1", (AGENT_CODE,))
    agent = cur.fetchone()
    if not agent:
        raise RuntimeError("Active A28_INDUSTRY_INTERACTION agent is not registered.")
    cur.execute("""
        INSERT INTO agentops.model_version (agent_id, version, model_type, feature_list, status)
        VALUES (%s, %s, 'RULE_BASED', %s, 'ACTIVE')
        ON CONFLICT (agent_id, version) DO UPDATE SET status='ACTIVE'
        RETURNING model_version_id
    """, (agent["agent_id"], MODEL_VERSION, Jsonb({"features": ["activity", "guest_lecture", "partner", "mou", "deliverable", "outcome", "evidence"]})))
    return agent["agent_id"], cur.fetchone()["model_version_id"]


def _choose_mou(cur, activity):
    if activity["mou_id"]:
        cur.execute("SELECT mou_id, title, valid_from, valid_until FROM engagement.mou WHERE mou_id=%s", (activity["mou_id"],))
        return cur.fetchone()
    cur.execute("""
        SELECT mou_id, title, valid_from, valid_until
        FROM engagement.mou
        WHERE industry_partner_id=%s AND status IN ('ACTIVE','RENEWED')
          AND (valid_from IS NULL OR valid_from <= %s)
          AND (valid_until IS NULL OR valid_until >= %s)
        ORDER BY valid_until NULLS LAST, signed_on DESC
        LIMIT 1
    """, (activity["industry_partner_id"], activity["activity_date"], activity["activity_date"]))
    return cur.fetchone()


def _match_deliverable(cur, mou_id, activity_type):
    allowed = tuple(TYPE_MAP.get(activity_type, set()))
    if not allowed:
        return None
    cur.execute("""
        SELECT mou_deliverable_id, description, deliverable_type, target_count, achieved_count, status
        FROM engagement.mou_deliverable
        WHERE mou_id=%s AND deliverable_type = ANY(%s)
        ORDER BY CASE WHEN status IN ('PENDING','IN_PROGRESS') THEN 0 ELSE 1 END,
                 due_date NULLS LAST
        LIMIT 1
    """, (mou_id, list(allowed)))
    return cur.fetchone()


def run_activities_outcomes(as_of_date: date | None = None):
    as_of_date = as_of_date or date.today()
    started = datetime.now(timezone.utc)
    matches = []
    skipped = []
    with get_connection() as conn:
        with conn.cursor() as cur:
            agent_id, model_id = _get_agent_and_model(cur)
            cur.execute("""
                INSERT INTO agentops.agent_run (agent_id, agent_version, trigger_type, scope, request_text, started_at)
                VALUES (%s,%s,'USER',%s,%s,%s) RETURNING agent_run_id
            """, (agent_id, AGENT_VERSION, Jsonb({"as_of_date": str(as_of_date)}),
                  "Connect realised industry activities to MoU deliverables", started))
            run_id = cur.fetchone()["agent_run_id"]

            cur.execute("SELECT count(*) AS n FROM engagement.industry_activity WHERE status='CONDUCTED' AND activity_date <= %s", (as_of_date,))
            activity_count = cur.fetchone()["n"]
            cur.execute("SELECT count(*) AS n FROM engagement.guest_lecture WHERE status='CONDUCTED' AND lecture_date <= %s", (as_of_date,))
            guest_lecture_count = cur.fetchone()["n"]
            cur.execute("""INSERT INTO agentops.agent_run_input
                (agent_run_id, source_schema, source_table, record_count, filter_expression)
                VALUES (%s,'engagement','industry_activity',%s,%s)""",
                (run_id, activity_count, f"status=CONDUCTED AND activity_date <= {as_of_date}"))
            cur.execute("""INSERT INTO agentops.agent_run_input
                (agent_run_id, source_schema, source_table, record_count, filter_expression)
                VALUES (%s,'engagement','guest_lecture',%s,%s)""",
                (run_id, guest_lecture_count, f"status=CONDUCTED AND lecture_date <= {as_of_date}"))

            cur.execute("""
                SELECT industry_activity_id, industry_partner_id, mou_id, activity_type, title,
                       activity_date, participant_count, evidence_ref, outcome_summary
                FROM engagement.industry_activity
                WHERE status='CONDUCTED' AND activity_date <= %s
                ORDER BY activity_date DESC
            """, (as_of_date,))
            activities = cur.fetchall()

            for activity in activities:
                if not activity["industry_partner_id"]:
                    skipped.append({"activity_id": str(activity["industry_activity_id"]), "reason": "No industry partner linked."})
                    continue
                mou = _choose_mou(cur, activity)
                if not mou:
                    skipped.append({"activity_id": str(activity["industry_activity_id"]), "title": activity["title"], "reason": "No MoU could be matched for the activity date."})
                    continue
                deliverable = _match_deliverable(cur, mou["mou_id"], activity["activity_type"])
                if not deliverable:
                    skipped.append({"activity_id": str(activity["industry_activity_id"]), "title": activity["title"], "reason": "No compatible MoU deliverable found."})
                    continue
                cur.execute("""
                    SELECT mou_deliverable_fulfilment_id, status
                    FROM engagement.mou_deliverable_fulfilment
                    WHERE mou_deliverable_id=%s AND industry_activity_id=%s
                    LIMIT 1
                """, (deliverable["mou_deliverable_id"], activity["industry_activity_id"]))
                existing = cur.fetchone()
                if existing:
                    status = existing["status"]
                    action = "EXISTING_LINK"
                else:
                    cur.execute("""
                        INSERT INTO engagement.mou_deliverable_fulfilment
                        (mou_deliverable_id, industry_activity_id, contributed_count, link_source, status,
                         match_rationale, agent_run_id)
                        VALUES (%s,%s,1,'AGENT_SUGGESTED','SUGGESTED',%s,%s)
                        RETURNING mou_deliverable_fulfilment_id
                    """, (deliverable["mou_deliverable_id"], activity["industry_activity_id"],
                          f"Activity type {activity['activity_type']} matches deliverable type {deliverable['deliverable_type']}; MoU/date link matched.", run_id))
                    existing = cur.fetchone()
                    status = "SUGGESTED"
                    action = "CREATED_SUGGESTION"
                matches.append({
                    "activity_id": str(activity["industry_activity_id"]),
                    "activity_title": activity["title"],
                    "activity_type": activity["activity_type"],
                    "activity_date": str(activity["activity_date"]),
                    "partner_id": str(activity["industry_partner_id"]),
                    "mou_id": str(mou["mou_id"]),
                    "mou_title": mou["title"],
                    "deliverable_id": str(deliverable["mou_deliverable_id"]),
                    "deliverable": deliverable["description"],
                    "fulfilment_id": str(existing["mou_deliverable_fulfilment_id"]),
                    "fulfilment_status": status,
                    "action": action,
                    "outcome": activity["outcome_summary"],
                    "evidence_ref": str(activity["evidence_ref"]) if activity["evidence_ref"] else None,
                })

            # Placement outcomes are also part of the DO stage. The placement
            # tables remain authoritative; Agent 2 only creates suggested links.
            source_specs = [
                ("internship", """SELECT i.internship_id AS source_id, c.industry_partner_id, i.company_id, i.from_date AS event_date,
                                  COALESCE(i.domain, 'Internship') AS title, 'INTERNSHIP' AS source_type
                           FROM placement.internship i JOIN placement.company c ON c.company_id=i.company_id
                           WHERE c.industry_partner_id IS NOT NULL AND i.status IN ('APPROVED','ONGOING','COMPLETED') AND i.from_date <= %s"""),
                ("offer", """SELECT o.offer_id AS source_id, c.industry_partner_id, o.company_id, o.offer_date AS event_date,
                                  COALESCE(o.role_title, 'Placement offer') AS title, 'OFFER' AS source_type
                           FROM placement.offer o JOIN placement.company c ON c.company_id=o.company_id
                           WHERE c.industry_partner_id IS NOT NULL AND o.status IN ('ACCEPTED','JOINED') AND o.offer_date <= %s"""),
                ("job_opening", """SELECT j.job_opening_id AS source_id, c.industry_partner_id, j.company_id,
                                  COALESCE(j.drive_date, j.application_deadline, current_date) AS event_date, j.role_title AS title, 'JOB_OPENING' AS source_type
                           FROM placement.job_opening j JOIN placement.company c ON c.company_id=j.company_id
                           WHERE c.industry_partner_id IS NOT NULL AND j.status IN ('OPEN','CLOSED','DRIVE_COMPLETED')
                             AND COALESCE(j.drive_date, j.application_deadline, current_date) <= %s""")
            ]
            source_to_column = {"internship":"internship_id", "offer":"offer_id", "job_opening":"job_opening_id"}
            source_to_deliverable = {"internship":"INTERNSHIP", "offer":"PLACEMENT", "job_opening":"PLACEMENT"}
            for source_kind, source_sql in source_specs:
                cur.execute(source_sql, (as_of_date,))
                for source in cur.fetchall():
                    cur.execute("""SELECT mou_id, title FROM engagement.mou
                        WHERE industry_partner_id=%s AND status IN ('ACTIVE','RENEWED')
                          AND (valid_from IS NULL OR valid_from <= %s) AND (valid_until IS NULL OR valid_until >= %s)
                        ORDER BY valid_until NULLS LAST, signed_on DESC LIMIT 1""", (source["industry_partner_id"], source["event_date"], source["event_date"]))
                    mou = cur.fetchone()
                    if not mou:
                        skipped.append({"source_id":str(source["source_id"]),"source_type":source["source_type"],"title":source["title"],"reason":"No MoU matched for the outcome date."})
                        continue
                    dtype=source_to_deliverable[source_kind]
                    cur.execute("""SELECT mou_deliverable_id, description, deliverable_type FROM engagement.mou_deliverable
                        WHERE mou_id=%s AND deliverable_type=%s ORDER BY CASE WHEN status IN ('PENDING','IN_PROGRESS') THEN 0 ELSE 1 END, due_date NULLS LAST LIMIT 1""", (mou["mou_id"],dtype))
                    d=cur.fetchone()
                    if not d:
                        skipped.append({"source_id":str(source["source_id"]),"source_type":source["source_type"],"title":source["title"],"reason":f"No {dtype} MoU deliverable found."})
                        continue
                    column=source_to_column[source_kind]
                    cur.execute(f"SELECT mou_deliverable_fulfilment_id, status FROM engagement.mou_deliverable_fulfilment WHERE mou_deliverable_id=%s AND {column}=%s LIMIT 1", (d["mou_deliverable_id"],source["source_id"]))
                    existing=cur.fetchone()
                    if existing:
                        fid=existing["mou_deliverable_fulfilment_id"]; fstatus=existing["status"]; action="EXISTING_LINK"
                    else:
                        cur.execute(f"""INSERT INTO engagement.mou_deliverable_fulfilment
                            (mou_deliverable_id,{column},contributed_count,link_source,status,match_rationale,agent_run_id)
                            VALUES (%s,%s,1,'AGENT_SUGGESTED','SUGGESTED',%s,%s) RETURNING mou_deliverable_fulfilment_id""",
                            (d["mou_deliverable_id"],source["source_id"],f"{source['source_type']} is linked to partner {source['industry_partner_id']} and matched to {dtype} deliverable.",run_id))
                        fid=cur.fetchone()["mou_deliverable_fulfilment_id"]; fstatus="SUGGESTED"; action="CREATED_SUGGESTION"
                    matches.append({"source_id":str(source["source_id"]),"source_type":source["source_type"],"activity_title":source["title"],"activity_date":str(source["event_date"]),"partner_id":str(source["industry_partner_id"]),"mou_id":str(mou["mou_id"]),"mou_title":mou["title"],"deliverable_id":str(d["mou_deliverable_id"]),"deliverable":d["description"],"fulfilment_id":str(fid),"fulfilment_status":fstatus,"action":action,"outcome":"Student/placement outcome source record"})

            payload = {
                "model_version": MODEL_VERSION,
                "as_of_date": str(as_of_date),
                "activities_processed": len(activities),
                "guest_lectures_processed": guest_lecture_count,
                "outcome_sources_processed": sum(1 for _ in matches),
                "matches": matches,
                "skipped": skipped,
                "summary": {
                    "matched": len(matches),
                    "new_suggestions": sum(1 for x in matches if x["action"] == "CREATED_SUGGESTION"),
                    "existing_links": sum(1 for x in matches if x["action"] == "EXISTING_LINK"),
                    "unmatched": len(skipped),
                },
            }
            reasoning = "Matched realised industry activities to compatible MoU deliverables using explicit MoU/partner/date links and deterministic activity-type rules. Standalone guest lectures are tracked as direct activity outcomes even when no MoU exists. New MoU links remain SUGGESTED for human confirmation."
            cur.execute("""
                INSERT INTO agentops.agent_output
                (agent_run_id, output_type, subject_type, payload, reasoning_summary, citations, interpretation, confidence)
                VALUES (%s,'REPORT','INDUSTRY_ACTIVITY',%s,%s,%s,%s,%s)
            """, (run_id, Jsonb(_json(payload)), reasoning, Jsonb([]), Jsonb({"model_version": MODEL_VERSION, "as_of_date": str(as_of_date)}), 1.0))
            latency = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
            cur.execute("UPDATE agentops.agent_run SET finished_at=%s, latency_ms=%s, status='SUCCEEDED' WHERE agent_run_id=%s", (datetime.now(timezone.utc), latency, run_id))
            conn.commit()
    return {"agent": AGENT_CODE, "agent_version": AGENT_VERSION, "model_version": MODEL_VERSION, "run_id": str(run_id), "status": "SUCCEEDED", **payload}
