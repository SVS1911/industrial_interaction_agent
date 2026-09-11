from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/action-items", tags=["Action Items"])

@router.get("")
def list_action_items(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("studentlife", "action_item", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("studentlife", "action_item"),
    }

@router.get("/{id}")
def get_action_items_by_id(id: UUID):
    row = get_row("studentlife", "action_item", "action_item_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="action item not found")
    return row
