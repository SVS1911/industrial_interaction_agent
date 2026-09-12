from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/offers", tags=["Offers"])

@router.get("")
def list_offers(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("placement", "offer", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("placement", "offer"),
    }

@router.get("/{id}")
def get_offers_by_id(id: UUID):
    row = get_row("placement", "offer", "offer_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="offer not found")
    return row
