from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/partner-contacts", tags=["Partner Contacts"])

@router.get("")
def list_partner_contacts(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("engagement", "partner_contact", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("engagement", "partner_contact"),
    }

@router.get("/{id}")
def get_partner_contacts_by_id(id: UUID):
    row = get_row("engagement", "partner_contact", "partner_contact_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="partner contact not found")
    return row
