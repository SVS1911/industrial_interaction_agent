from datetime import date
from uuid import UUID
from pydantic import BaseModel, Field


class GuestLectureCreate(BaseModel):
    speaker_name: str = Field(min_length=2, max_length=255)
    speaker_type: str = "INDUSTRY_EXPERT"
    alumni_id: UUID | None = None
    speaker_person_id: UUID | None = None
    domain: str = Field(min_length=2, max_length=255)
    title: str = Field(min_length=2, max_length=500)
    lecture_date: date
    end_date: date | None = None
    mode: str | None = None
    participant_count: int | None = Field(default=None, ge=0)
    industry_partner_id: UUID | None = None
    mou_id: UUID | None = None
    department_id: UUID | None = None
    outcome_summary: str | None = None
    evidence_ref: UUID | None = None
    status: str = "CONDUCTED"
