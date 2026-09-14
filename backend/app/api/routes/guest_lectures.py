from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows
from app.core.database import get_connection
from app.schemas.guest_lecture import GuestLectureCreate

router = APIRouter(prefix="/api/guest-lectures", tags=["Guest Lectures"])


@router.get("")
def list_guest_lectures(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "v_guest_lecture_register", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "guest_lecture"),
    }


@router.post("", status_code=201)
def create_guest_lecture(payload: GuestLectureCreate):
    allowed_speaker_types = {"ALUMNI", "INDUSTRY_EXPERT", "ACADEMIC", "OTHER"}
    allowed_statuses = {"PLANNED", "CONFIRMED", "CONDUCTED", "POSTPONED", "CANCELLED"}
    allowed_modes = {"OFFLINE", "ONLINE", "HYBRID"}
    if payload.speaker_type not in allowed_speaker_types:
        raise HTTPException(status_code=400, detail="Invalid speaker type.")
    if payload.status not in allowed_statuses:
        raise HTTPException(status_code=400, detail="Invalid guest lecture status.")
    if payload.mode is not None and payload.mode not in allowed_modes:
        raise HTTPException(status_code=400, detail="Invalid guest lecture mode.")
    if payload.end_date and payload.end_date < payload.lecture_date:
        raise HTTPException(status_code=400, detail="End date cannot be earlier than lecture date.")
    if payload.alumni_id and payload.speaker_type != "ALUMNI":
        raise HTTPException(status_code=400, detail="An alumni link requires speaker type ALUMNI.")

    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT institution_id FROM core.institution WHERE is_active = true ORDER BY code LIMIT 1")
            inst = cur.fetchone()
            if not inst:
                raise HTTPException(status_code=400, detail="No active institution exists.")
            institution_id = inst["institution_id"]

            if payload.alumni_id:
                cur.execute("""SELECT a.alumni_id, p.full_name
                    FROM placement.alumni a JOIN people.person p ON p.person_id=a.person_id
                    WHERE a.alumni_id=%s""", (payload.alumni_id,))
                alumni = cur.fetchone()
                if not alumni:
                    raise HTTPException(status_code=400, detail="Alumni record not found.")
                speaker_name = alumni["full_name"]
            else:
                speaker_name = payload.speaker_name.strip()

            if payload.speaker_person_id:
                cur.execute("SELECT person_id FROM people.person WHERE person_id=%s AND institution_id=%s", (payload.speaker_person_id, institution_id))
                if not cur.fetchone():
                    raise HTTPException(status_code=400, detail="Speaker person record not found in the institution.")

            if payload.industry_partner_id:
                cur.execute("SELECT industry_partner_id FROM engagement.industry_partner WHERE industry_partner_id=%s AND institution_id=%s", (payload.industry_partner_id, institution_id))
                if not cur.fetchone():
                    raise HTTPException(status_code=400, detail="Industry partner not found in the institution.")

            partner_id = payload.industry_partner_id
            if payload.mou_id:
                cur.execute("SELECT mou_id, industry_partner_id FROM engagement.mou WHERE mou_id=%s", (payload.mou_id,))
                mou = cur.fetchone()
                if not mou:
                    raise HTTPException(status_code=400, detail="MoU not found.")
                if partner_id and mou["industry_partner_id"] != partner_id:
                    raise HTTPException(status_code=400, detail="Selected MoU does not belong to the selected partner.")
                partner_id = partner_id or mou["industry_partner_id"]

            cur.execute("""INSERT INTO engagement.guest_lecture
                (institution_id,speaker_name,speaker_type,alumni_id,speaker_person_id,domain,title,lecture_date,end_date,mode,
                 participant_count,industry_partner_id,mou_id,department_id,outcome_summary,evidence_ref,status)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING *""",
                (institution_id, speaker_name, payload.speaker_type, payload.alumni_id,
                 payload.speaker_person_id, payload.domain.strip(), payload.title.strip(), payload.lecture_date,
                 payload.end_date, payload.mode, payload.participant_count, partner_id,
                 payload.mou_id, payload.department_id, payload.outcome_summary, payload.evidence_ref, payload.status))
            row = dict(cur.fetchone())
            conn.commit()
            return row


@router.get("/{id}")
def get_guest_lecture(id: UUID):
    row = get_row("engagement", "v_guest_lecture_register", "guest_lecture_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="Guest lecture not found")
    return row
