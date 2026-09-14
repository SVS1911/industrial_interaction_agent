from datetime import date
from uuid import UUID
from pydantic import BaseModel, Field

class ActivityCreate(BaseModel):
    industry_partner_id: UUID | None = None
    mou_id: UUID | None = None
    department_id: UUID | None = None
    activity_type: str
    title: str = Field(min_length=2, max_length=500)
    activity_date: date
    end_date: date | None = None
    mode: str | None = None
    participant_count: int | None = Field(default=None, ge=0)
    outcome_summary: str | None = None
    evidence_ref: UUID | None = None
    status: str = "CONDUCTED"
