from fastapi import APIRouter, HTTPException, Query
from app.services.db_service import list_rows

router = APIRouter(prefix="/api/views", tags=["Agent 28 Read Views"])

VIEW_MAP = {
    "partner-activity-ledger": ("engagement", "v_partner_activity_ledger"),
    "deliverable-status": ("engagement", "v_deliverable_status"),
    "mou-tracker": ("engagement", "v_mou_tracker"),
    "partner-health-latest": ("engagement", "v_partner_health_latest"),
    "partner-register": ("engagement", "v_partner_register"),
    "activity-calendar": ("engagement", "v_activity_calendar"),
    "activity-feedback-summary": ("engagement", "v_activity_feedback_summary"),
    "sector-gap": ("engagement", "v_sector_gap"),
    "target-partner-candidates": ("engagement", "v_target_partner_candidates"),
    "accreditation-evidence": ("engagement", "v_accreditation_evidence"),
    "kpi-latest": ("quality", "v_kpi_latest"),
}

@router.get("")
def list_views():
    return {"views": sorted(VIEW_MAP)}

@router.get("/{view_name}")
def get_view(view_name: str, limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    if view_name not in VIEW_MAP:
        raise HTTPException(status_code=404, detail="View not found")
    schema, view = VIEW_MAP[view_name]
    return {"items": list_rows(schema, view, limit, offset), "limit": limit, "offset": offset}
