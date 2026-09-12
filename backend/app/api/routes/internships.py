from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/internships", tags=["Internships"])

@router.get("")
def list_internships(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("placement", "internship", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("placement", "internship"),
    }

@router.get("/{id}")
def get_internships_by_id(id: UUID):
    row = get_row("placement", "internship", "internship_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="internship not found")
    return row
