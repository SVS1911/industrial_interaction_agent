from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows
from app.core.database import get_connection
from app.schemas.activity import ActivityCreate

router = APIRouter(prefix="/api/activities", tags=["Industry Activities"])

@router.get("")
def list_activities(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "industry_activity", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "industry_activity"),
    }


@router.post("", status_code=201)
def create_activity(payload: ActivityCreate):
    types = {"INDUSTRY_VISIT","GUEST_LECTURE","EXPERT_TALK","SPONSORED_PROJECT","INTERNSHIP_DRIVE","FACULTY_EXCHANGE","LAB_SUPPORT","CONSULTANCY"}
    statuses = {"PLANNED","CONFIRMED","CONDUCTED","POSTPONED","CANCELLED"}
    modes = {"OFFLINE","ONLINE","HYBRID"}
    if payload.activity_type not in types:
        raise HTTPException(status_code=400, detail="Invalid activity type.")
    if payload.status not in statuses:
        raise HTTPException(status_code=400, detail="Invalid activity status.")
    if payload.mode is not None and payload.mode not in modes:
        raise HTTPException(status_code=400, detail="Invalid activity mode.")
    if payload.end_date and payload.end_date < payload.activity_date:
        raise HTTPException(status_code=400, detail="End date cannot be earlier than activity date.")
    if not payload.industry_partner_id and not payload.mou_id:
        raise HTTPException(status_code=400, detail="Select a partner or MoU for the activity.")
    with get_connection() as conn:
        with conn.cursor() as cur:
            if payload.industry_partner_id:
                cur.execute("SELECT 1 FROM engagement.industry_partner WHERE industry_partner_id=%s", (payload.industry_partner_id,))
                if not cur.fetchone(): raise HTTPException(status_code=400, detail="Partner not found.")
            if payload.mou_id:
                cur.execute("SELECT industry_partner_id FROM engagement.mou WHERE mou_id=%s", (payload.mou_id,))
                mou=cur.fetchone()
                if not mou: raise HTTPException(status_code=400, detail="MoU not found.")
                if payload.industry_partner_id and mou["industry_partner_id"] != payload.industry_partner_id:
                    raise HTTPException(status_code=400, detail="Selected MoU does not belong to the selected partner.")
                partner_id = payload.industry_partner_id or mou["industry_partner_id"]
            else:
                partner_id = payload.industry_partner_id
            cur.execute("""INSERT INTO engagement.industry_activity
                (industry_partner_id,mou_id,department_id,activity_type,title,activity_date,end_date,mode,participant_count,outcome_summary,evidence_ref,status)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""",
                (partner_id,payload.mou_id,payload.department_id,payload.activity_type,payload.title.strip(),payload.activity_date,payload.end_date,payload.mode,payload.participant_count,payload.outcome_summary,payload.evidence_ref,payload.status))
            row=dict(cur.fetchone()); conn.commit(); return row

@router.get("/{id}")
def get_activities_by_id(id: UUID):
    row = get_row("engagement", "industry_activity", "industry_activity_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="industry activitie not found")
    return row
