from datetime import date

from fastapi import APIRouter, HTTPException, Query

from app.services.engagement_health_agent import run_engagement_health
from app.services.intelligence_recommendations_agent import run_intelligence_recommendations
from app.services.mou_intelligence_agent import run_mou_intelligence

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


@router.post("/intelligence-recommendations/run")
def run_intelligence_recommendations_agent(
    as_of_date: date | None = Query(
        default=None,
        description="Date used for recommendation evaluation. Defaults to the application date.",
    )
):
    try:
        return run_intelligence_recommendations(as_of_date)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Intelligence and recommendations agent failed: {exc}",
        ) from exc


@router.post("/mou-intelligence/run")
def run_mou_intelligence_agent(
    mou_id: str | None = Query(
        default=None,
        description="Optional MoU UUID. If omitted, all MoUs with linked source documents are processed.",
    )
):
    try:
        return run_mou_intelligence(mou_id)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"MoU intelligence agent failed: {exc}",
        ) from exc
