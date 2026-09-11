from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/companies", tags=["Companies"])

@router.get("")
def list_companies(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("placement", "company", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("placement", "company"),
    }

@router.get("/{id}")
def get_companies_by_id(id: UUID):
    row = get_row("placement", "company", "company_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="companie not found")
    return row
