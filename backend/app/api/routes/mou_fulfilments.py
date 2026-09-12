from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/mou-fulfilments", tags=["Mou Fulfilments"])

@router.get("")
def list_mou_fulfilments(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "mou_deliverable_fulfilment", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "mou_deliverable_fulfilment"),
    }

@router.get("/{id}")
def get_mou_fulfilments_by_id(id: UUID):
    row = get_row("engagement", "mou_deliverable_fulfilment", "mou_deliverable_fulfilment_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="MoU fulfilment not found")
    return row
