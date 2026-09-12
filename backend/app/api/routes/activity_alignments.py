from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/activity-alignments", tags=["Activity Course Alignments"])

@router.get("")
def list_activity_alignments(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "activity_course_alignment", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "activity_course_alignment"),
    }

@router.get("/{id}")
def get_activity_alignments_by_id(id: UUID):
    row = get_row("engagement", "activity_course_alignment", "activity_course_alignment_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="activity course alignment not found")
    return row
