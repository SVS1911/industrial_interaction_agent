from datetime import date

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app.services.mou_upload_service import upload_and_run_mou

router = APIRouter(prefix="/api/agents/mou-intelligence", tags=["Agent 1 - MoU Intelligence"])


@router.post("/upload")
async def upload_mou_for_intelligence(
    file: UploadFile = File(...),
    partner_name: str = Form(...),
    title: str = Form(...),
    partner_type: str = Form("INDUSTRY"),
    signed_on: date = Form(...),
    valid_from: date | None = Form(None),
    valid_until: date | None = Form(None),
    renewal_alert_days: int = Form(90),
):
    allowed_types = {"INDUSTRY", "UNIVERSITY", "RESEARCH_LAB", "NGO", "GOVERNMENT", "INTERNATIONAL"}
    if partner_type not in allowed_types:
        raise HTTPException(status_code=400, detail=f"Invalid partner type. Use one of: {', '.join(sorted(allowed_types))}")
    if not 0 <= renewal_alert_days <= 730:
        raise HTTPException(status_code=400, detail="Renewal alert days must be between 0 and 730.")
    try:
        data = await file.read()
        return upload_and_run_mou(
            file_bytes=data,
            filename=file.filename or "mou.pdf",
            partner_name=partner_name,
            title=title,
            partner_type=partner_type,
            signed_on=signed_on,
            valid_from=valid_from,
            valid_until=valid_until,
            renewal_alert_days=renewal_alert_days,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"MoU upload failed: {exc}") from exc
