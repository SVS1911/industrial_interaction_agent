from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/events", tags=["Events"])

@router.get("")
def list_events(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "event", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "event"),
    }

@router.get("/{id}")
def get_events_by_id(id: UUID):
    row = get_row("engagement", "event", "event_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="event not found")
    return row
