from uuid import UUID
from fastapi import APIRouter, HTTPException, Query
from app.core.database import get_connection
from app.services.db_service import get_row, count_rows

router = APIRouter(prefix="/api/agent-runs", tags=["Agent Runs"])


def _list_agent_runs(limit: int, offset: int):
    query = """
        SELECT
            r.agent_run_id,
            r.agent_id,
            a.name AS agent_name,
            r.agent_version,
            r.trigger_type,
            r.started_at,
            r.finished_at,
            r.latency_ms,
            r.status,
            COALESCE((
                SELECT SUM(COALESCE(i.record_count, 0))
                FROM agentops.agent_run_input i
                WHERE i.agent_run_id = r.agent_run_id
            ), 0)::integer AS record_count
        FROM agentops.agent_run r
        JOIN agentops.agent a ON a.agent_id = r.agent_id
        ORDER BY r.started_at DESC
        LIMIT %s OFFSET %s
    """
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, (limit, offset))
            return [dict(row) for row in cur.fetchall()]


def _json_value(value):
    from datetime import date, datetime
    from decimal import Decimal
    if isinstance(value, (UUID, date, datetime, Decimal)):
        return str(value)
    return value


def _serialize(rows):
    return [{key: _json_value(value) for key, value in row.items()} for row in rows]


@router.get("")
def list_agent_runs(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    return {
        "items": _serialize(_list_agent_runs(limit, offset)),
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
