from uuid import UUID
from pydantic import BaseModel, Field, HttpUrl

class PartnerCreate(BaseModel):
    name: str = Field(min_length=2, max_length=255)
    sector: str | None = None
    website: str | None = None
    contact_person: str | None = None
    contact_email: str | None = None
    contact_phone: str | None = None
    relationship_owner_faculty_id: UUID | None = None
    status: str = "ACTIVE"
