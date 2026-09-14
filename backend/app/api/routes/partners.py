from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows
from app.core.database import get_connection
from app.schemas.partner import PartnerCreate

router = APIRouter(prefix="/api/partners", tags=["Partners"])

@router.get("")
def list_partners(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "industry_partner", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "industry_partner"),
    }


@router.post("", status_code=201)
def create_partner(payload: PartnerCreate):
    allowed = {"PROSPECT", "ACTIVE", "DORMANT", "CONCLUDED"}
    if payload.status not in allowed:
        raise HTTPException(status_code=400, detail=f"Invalid partner status. Use one of: {', '.join(sorted(allowed))}")
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Partner name is required.")
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT institution_id FROM core.institution WHERE is_active = true ORDER BY code LIMIT 1")
            inst = cur.fetchone()
            if not inst:
                raise HTTPException(status_code=400, detail="No active institution exists.")
            cur.execute("SELECT industry_partner_id FROM engagement.industry_partner WHERE institution_id=%s AND lower(name)=lower(%s) LIMIT 1", (inst["institution_id"], name))
            if cur.fetchone():
                raise HTTPException(status_code=409, detail="A partner with this name already exists.")
            cur.execute("""INSERT INTO engagement.industry_partner
                (institution_id,name,sector,website,contact_person,contact_email,contact_phone,relationship_owner_faculty_id,status)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING *""", (inst["institution_id"], name, payload.sector, payload.website, payload.contact_person, payload.contact_email, payload.contact_phone, payload.relationship_owner_faculty_id, payload.status))
            row = dict(cur.fetchone())
            conn.commit()
            return row

@router.get("/{id}")
def get_partners_by_id(id: UUID):
    row = get_row("engagement", "industry_partner", "industry_partner_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="partner not found")
    return row
