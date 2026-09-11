from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/partner-expertise", tags=["Partner Expertise"])

@router.get("")
def list_partner_expertise(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "partner_expertise", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "partner_expertise"),
    }

@router.get("/{id}")
def get_partner_expertise_by_id(id: UUID):
    row = get_row("engagement", "partner_expertise", "partner_expertise_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="partner expertise not found")
    return row
