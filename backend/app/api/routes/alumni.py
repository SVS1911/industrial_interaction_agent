from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows
from app.core.database import get_connection

router = APIRouter(prefix="/api/alumni", tags=["Alumni"])

@router.get("")
def list_alumni(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""SELECT a.*, p.full_name
                FROM placement.alumni a JOIN people.person p ON p.person_id=a.person_id
                ORDER BY p.full_name LIMIT %s OFFSET %s""", (limit, offset))
            items = [dict(row) for row in cur.fetchall()]
    return {"items": items, "limit": limit, "offset": offset, "total": count_rows("placement", "alumni")}

@router.get("/{id}")
def get_alumni_by_id(id: UUID):
    row = get_row("placement", "alumni", "alumni_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="alumni not found")
    return row
