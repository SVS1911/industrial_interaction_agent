from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows, get_row, count_rows

router = APIRouter(prefix="/api/agent-runs", tags=["Agent Runs"])

@router.get("")
def list_agent_runs(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": list_rows("agentops", "agent_run", limit, offset),
        "limit": limit,
        "offset": offset,
        "total": count_rows("agentops", "agent_run"),
    }

@router.get("/{id}")
def get_agent_runs_by_id(id: UUID):
    row = get_row("agentops", "agent_run", "agent_run_id", id)
    if row is None:
        raise HTTPException(status_code=404, detail="agent run not found")
    return row
