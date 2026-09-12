from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/faculty", tags=["Faculty"])

@router.get("")
def list_faculty(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("people", "faculty", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("people", "faculty"),
    }

@router.get("/{id}")
def get_faculty_by_id(id: UUID):
    row = get_row("people", "faculty", "faculty_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="faculty not found")
    return row
