from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/documents", tags=["Documents"])

@router.get("")
def list_documents(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("knowledge", "document", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("knowledge", "document"),
    }

@router.get("/{id}")
def get_documents_by_id(id: UUID):
    row = get_row("knowledge", "document", "document_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="document not found")
    return row
