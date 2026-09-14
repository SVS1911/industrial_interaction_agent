from datetime import date
import csv
from io import StringIO
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from app.services.activities_outcomes_agent import run_activities_outcomes
from app.services.accreditation_evidence_agent import run_accreditation_evidence

router = APIRouter(prefix="/api/agents", tags=["Agent 2 - Activities & Outcomes", "Agent 5 - Accreditation Evidence"])

@router.post("/activities-outcomes/run")
def run_agent2(as_of_date: date | None = Query(None)):
    try:
        return run_activities_outcomes(as_of_date)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Agent 2 failed: {exc}") from exc

@router.post("/accreditation-evidence/run")
def run_agent5(as_of_date: date | None = Query(None)):
    try:
        return run_accreditation_evidence(as_of_date)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Agent 5 failed: {exc}") from exc


@router.get("/accreditation-evidence/report.csv")
def export_accreditation_evidence_report():
    """Export the latest Agent 5 assessment as an auditable CSV report."""
    from app.core.database import get_connection

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""SELECT payload, agent_run_id, created_at
                FROM agentops.agent_output
                WHERE output_type='REPORT' AND subject_type='ACCREDITATION'
                ORDER BY created_at DESC LIMIT 1""")
            row = cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="No Agent 5 accreditation report exists yet.")

    payload = row["payload"] or {}
    output = StringIO(newline="")
    writer = csv.writer(output)
    writer.writerow([
        "Agent", "Model version", "As of date", "Run ID", "Criterion", "Title",
        "Requirement", "Evidence records", "Source support", "Status"
    ])
    for criterion in payload.get("criteria", []):
        writer.writerow([
            "A28_INDUSTRY_INTERACTION",
            payload.get("model_version", ""),
            payload.get("as_of_date", ""),
            str(row["agent_run_id"]),
            criterion.get("criterion", ""),
            criterion.get("title", ""),
            criterion.get("requirement", ""),
            criterion.get("evidence_records", 0),
            criterion.get("source_support", ""),
            criterion.get("status", ""),
        ])

    filename = f"agent5-accreditation-evidence-{payload.get('as_of_date', 'latest')}.csv"
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
