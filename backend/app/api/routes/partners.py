from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/partners", tags=["Partners"])

@router.get("")
def list_partners(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "industry_partner", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "industry_partner"),
    }

@router.get("/{id}")
def get_partners_by_id(id: UUID):
    row = get_row("engagement", "industry_partner", "industry_partner_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="partner not found")
    return row
