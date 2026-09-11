from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/extraction-jobs", tags=["Extraction Jobs"])

@router.get("")
def list_extraction_jobs(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("knowledge", "extraction_job", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("knowledge", "extraction_job"),
    }

@router.get("/{id}")
def get_extraction_jobs_by_id(id: UUID):
    row = get_row("knowledge", "extraction_job", "extraction_job_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="extraction job not found")
    return row
