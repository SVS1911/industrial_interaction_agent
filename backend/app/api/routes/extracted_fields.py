from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/extracted-fields", tags=["Extracted Fields"])

@router.get("")
def list_extracted_fields(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("knowledge", "extracted_field", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("knowledge", "extracted_field"),
    }

@router.get("/{id}")
def get_extracted_fields_by_id(id: UUID):
    row = get_row("knowledge", "extracted_field", "extracted_field_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="extracted field not found")
    return row
