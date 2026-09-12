from datetime import date

from fastapi import APIRouter, HTTPException, Query

from app.services.engagement_health_agent import run_engagement_health

router = APIRouter(prefix="/api/agents", tags=["Agents"])


@router.post("/engagement-health/run")
def run_engagement_health_agent(
    as_of_date: date | None = Query(
        default=None,
        description="Date used for the health calculation. Defaults to the database/application date.",
    )
):
    try:
        return run_engagement_health(as_of_date)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Engagement health agent failed: {exc}") from exc
