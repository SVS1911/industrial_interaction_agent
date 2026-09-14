from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field


class Evidence(BaseModel):
    page_no: int | None = None
    heading_path: str | None = None
    source_text: str = Field(min_length=1)


class Commitment(BaseModel):
    description: str = Field(min_length=1)
    commitment_type: Literal[
        "DELIVERABLE",
        "ACTIVITY",
        "RESOURCE",
        "OUTCOME",
        "GOVERNANCE",
        "OTHER",
    ]
    party: str | None = None
    mandatory: bool = True
    conditional: bool = False
    condition: str | None = None
    target_count: int | None = Field(default=None, ge=0)
    due_date: date | None = None
    recurrence: str | None = None
    exclusions: list[str] = Field(default_factory=list)
    evidence: list[Evidence] = Field(default_factory=list)
    confidence: float = Field(ge=0, le=1)
    review_required: bool = False


class RenewalTerms(BaseModel):
    present: bool = False
    summary: str | None = None
    notice_period: str | None = None
    automatic_renewal: bool | None = None
    evidence: list[Evidence] = Field(default_factory=list)


class MouIntelligenceExtraction(BaseModel):
    summary: str = Field(min_length=1)
    scope: str | None = None
    parties: list[str] = Field(default_factory=list)
    commitments: list[Commitment] = Field(default_factory=list)
    mandatory_commitments_count: int = Field(default=0, ge=0)
    conditional_commitments_count: int = Field(default=0, ge=0)
    renewal_terms: RenewalTerms = Field(default_factory=RenewalTerms)
    exclusions: list[str] = Field(default_factory=list)
    ambiguities: list[str] = Field(default_factory=list)
    review_required: bool = False
    overall_confidence: float = Field(ge=0, le=1)


class DeterministicValidation(BaseModel):
    db_scope: str | None = None
    db_valid_from: date | None = None
    db_valid_until: date | None = None
    db_deliverables: list[dict] = Field(default_factory=list)
    extracted_deliverables_count: int = 0
    reconciled_deliverables_count: int = 0
    discrepancies: list[str] = Field(default_factory=list)
    review_required: bool = False


class MouIntelligenceReport(BaseModel):
    mou_id: str
    partner_name: str
    title: str
    document_id: str | None = None
    extraction_job_id: str | None = None
    model_version: str
    extraction: MouIntelligenceExtraction
    validation: DeterministicValidation
    citations: list[dict] = Field(default_factory=list)
    requires_human_review: bool = False
