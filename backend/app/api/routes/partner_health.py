from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/partner-health", tags=["Partner Health Snapshots"])

@router.get("")
def list_partner_health(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "partner_health_snapshot", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "partner_health_snapshot"),
    }

@router.get("/{id}")
def get_partner_health_by_id(id: UUID):
    row = get_row("engagement", "partner_health_snapshot", "partner_health_snapshot_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="partner health snapshot not found")
    return row
