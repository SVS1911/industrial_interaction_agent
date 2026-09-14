"""Agent 5 - Accreditation Evidence / PROVE agent.

Builds an auditable evidence map from industry interactions, MoUs, outcomes,
documents and feedback. Existing evidence is reused; missing proof is reported,
never fabricated.
"""
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID
from psycopg.types.json import Jsonb
from app.core.database import get_connection

AGENT_CODE = "A28_INDUSTRY_INTERACTION"
AGENT_VERSION = "1.2"
MODEL_VERSION = "evidence-5.0"


def _json(v: Any):
    if isinstance(v, (UUID, date, datetime, Decimal)):
        return str(v)
    if isinstance(v, dict): return {k: _json(x) for k, x in v.items()}
    if isinstance(v, list): return [_json(x) for x in v]
    return v


def _ensure_model(cur):
    cur.execute("SELECT agent_id FROM agentops.agent WHERE code=%s AND status='ACTIVE' LIMIT 1", (AGENT_CODE,))
    row = cur.fetchone()
    if not row: raise RuntimeError("Active A28_INDUSTRY_INTERACTION agent is not registered.")
    cur.execute("""INSERT INTO agentops.model_version (agent_id,version,model_type,feature_list,status)
        VALUES (%s,%s,'RULE_BASED',%s,'ACTIVE')
        ON CONFLICT (agent_id,version) DO UPDATE SET status='ACTIVE'
        RETURNING model_version_id""", (row["agent_id"], MODEL_VERSION, Jsonb({"features":["mous","activities","guest_lectures","outcomes","documents","feedback","criteria"]})))
    return row["agent_id"]


def run_accreditation_evidence(as_of_date: date | None = None):
    as_of_date = as_of_date or date.today()
    started = datetime.now(timezone.utc)
    with get_connection() as conn:
        with conn.cursor() as cur:
            agent_id = _ensure_model(cur)
            cur.execute("""INSERT INTO agentops.agent_run
                (agent_id,agent_version,trigger_type,scope,request_text,started_at)
                VALUES (%s,%s,'USER',%s,%s,%s) RETURNING agent_run_id""",
                (agent_id, AGENT_VERSION, Jsonb({"as_of_date":str(as_of_date)}), "Map industry interaction evidence to accreditation criteria", started))
            run_id = cur.fetchone()["agent_run_id"]

            cur.execute("SELECT count(*) AS n FROM engagement.industry_activity WHERE status='CONDUCTED' AND activity_date <= %s", (as_of_date,))
            activity_count = cur.fetchone()["n"]
            cur.execute("SELECT count(*) AS n FROM engagement.guest_lecture WHERE status='CONDUCTED' AND lecture_date <= %s", (as_of_date,))
            guest_lecture_count = cur.fetchone()["n"]
            cur.execute("SELECT count(*) AS n FROM engagement.mou WHERE status <> 'DRAFT' AND signed_on <= %s", (as_of_date,))
            mou_count = cur.fetchone()["n"]
            cur.execute("""INSERT INTO agentops.agent_run_input (agent_run_id,source_schema,source_table,record_count,filter_expression)
                VALUES (%s,'engagement','industry_activity',%s,'status=CONDUCTED'),
                       (%s,'engagement','guest_lecture',%s,'status=CONDUCTED'),
                       (%s,'engagement','mou',%s,'status<>DRAFT'),
                       (%s,'quality','evidence_item',NULL,'existing evidence'),
                       (%s,'quality','feedback_response',NULL,'industry activity feedback')""",
                (run_id,activity_count,run_id,guest_lecture_count,run_id,mou_count,run_id,run_id))

            cur.execute("SELECT accreditation_criterion_id, code, title, evidence_specification FROM quality.accreditation_criterion ORDER BY code")
            criteria = cur.fetchall()
            results=[]
            for c in criteria:
                code=c["code"]
                if code == "IND-1":
                    cur.execute("""SELECT count(*) AS n FROM engagement.mou m
                        WHERE m.partner_type='INDUSTRY' AND m.status<>'DRAFT' AND m.signed_on<=%s
                          AND (EXISTS (SELECT 1 FROM engagement.industry_activity a WHERE a.mou_id=m.mou_id AND a.status='CONDUCTED' AND a.activity_date<=%s)
                               OR EXISTS (SELECT 1 FROM engagement.mou_deliverable_fulfilment f JOIN engagement.mou_deliverable d ON d.mou_deliverable_id=f.mou_deliverable_id
                                          WHERE d.mou_id=m.mou_id AND f.status='CONFIRMED'))""", (as_of_date,as_of_date))
                    supported=cur.fetchone()["n"]
                    cur.execute("SELECT count(*) AS n FROM engagement.mou WHERE partner_type='INDUSTRY' AND status<>'DRAFT' AND signed_on<=%s", (as_of_date,)); total=cur.fetchone()["n"]
                    found = supported > 0
                    detail=f"{supported} of {total} industry MoUs have activity or confirmed fulfilment evidence."
                elif code == "IND-2":
                    cur.execute("""SELECT count(*) AS n FROM engagement.industry_activity a
                        WHERE a.status='CONDUCTED' AND a.activity_date<=%s
                          AND a.activity_type IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT','FACULTY_EXCHANGE')
                          AND a.evidence_ref IS NOT NULL""", (as_of_date,)); activity_evidence=cur.fetchone()["n"]
                    cur.execute("""SELECT count(*) AS n FROM engagement.guest_lecture g
                        WHERE g.status='CONDUCTED' AND g.lecture_date<=%s AND g.evidence_ref IS NOT NULL""", (as_of_date,)); lecture_evidence=cur.fetchone()["n"]
                    n=activity_evidence + lecture_evidence
                    found=n>0; detail=f"{n} qualifying academic-industry activities or standalone guest lectures have linked documents."
                elif code == "IND-3":
                    cur.execute("""SELECT count(*) AS n FROM placement.internship i JOIN placement.company c ON c.company_id=i.company_id
                        WHERE c.industry_partner_id IS NOT NULL AND i.status IN ('APPROVED','ONGOING','COMPLETED') AND i.from_date<=%s
                        """, (as_of_date,)); internships=cur.fetchone()["n"]
                    cur.execute("""SELECT count(*) AS n FROM engagement.industry_activity a WHERE a.status='CONDUCTED' AND a.activity_type IN ('SPONSORED_PROJECT','CONSULTANCY') AND a.evidence_ref IS NOT NULL AND a.activity_date<=%s""", (as_of_date,)); projects=cur.fetchone()["n"]
                    found=(internships+projects)>0; detail=f"{internships} partner-linked internships and {projects} evidenced projects/consultancies found."
                elif code == "IND-4":
                    cur.execute("SELECT count(*) AS n FROM engagement.industry_activity WHERE status='CONDUCTED' AND activity_type='LAB_SUPPORT' AND evidence_ref IS NOT NULL AND activity_date<=%s", (as_of_date,)); n=cur.fetchone()["n"]
                    found=n>0; detail=f"{n} lab-support activities have linked evidence."
                elif code == "IND-5":
                    cur.execute("""SELECT count(*) AS n FROM quality.feedback_response fr JOIN engagement.industry_activity a ON a.industry_activity_id=fr.target_id
                        WHERE fr.target_type='INDUSTRY_ACTIVITY' AND a.activity_date<=%s""", (as_of_date,)); n=cur.fetchone()["n"]
                    found=n>0; detail=f"{n} industry-interaction feedback responses are available."
                else:
                    found=False; detail="No mapping rule is defined for this criterion."
                cur.execute("""SELECT count(*) AS n FROM quality.evidence_item WHERE accreditation_criterion_id=%s AND source_schema='engagement'""", (c["accreditation_criterion_id"],)); existing=cur.fetchone()["n"]
                results.append({"criterion":code,"title":c["title"],"requirement":c["evidence_specification"],"evidence_records":existing,"source_support":detail,"status":"EVIDENCE_AVAILABLE" if found else "MISSING_OR_INCOMPLETE"})

            payload={"model_version":MODEL_VERSION,"as_of_date":str(as_of_date),"criteria":results,"summary":{"criteria_total":len(results),"available":sum(x["status"]=="EVIDENCE_AVAILABLE" for x in results),"missing_or_incomplete":sum(x["status"]=="MISSING_OR_INCOMPLETE" for x in results)}}
            reasoning="Mapped authoritative MoU, activity, outcome and feedback records to accreditation criteria. Missing proof is reported explicitly; the agent does not fabricate evidence."
            cur.execute("""INSERT INTO agentops.agent_output
                (agent_run_id,output_type,subject_type,payload,reasoning_summary,citations,interpretation,confidence)
                VALUES (%s,'REPORT','ACCREDITATION',%s,%s,%s,%s,%s)""",(run_id,Jsonb(_json(payload)),reasoning,Jsonb([]),Jsonb({"model_version":MODEL_VERSION,"as_of_date":str(as_of_date)}),1.0))
            latency=int((datetime.now(timezone.utc)-started).total_seconds()*1000)
            cur.execute("UPDATE agentops.agent_run SET finished_at=%s,latency_ms=%s,status='SUCCEEDED' WHERE agent_run_id=%s",(datetime.now(timezone.utc),latency,run_id))
            conn.commit()
    return {"agent":AGENT_CODE,"agent_version":AGENT_VERSION,"model_version":MODEL_VERSION,"run_id":str(run_id),"status":"SUCCEEDED",**payload}
