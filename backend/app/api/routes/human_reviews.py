from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/human-reviews", tags=["Human Reviews"])

@router.get("")
def list_human_reviews(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("agentops", "human_review", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("agentops", "human_review"),
    }

@router.get("/{id}")
def get_human_reviews_by_id(id: UUID):
    row = get_row("agentops", "human_review", "human_review_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="human review not found")
    return row
