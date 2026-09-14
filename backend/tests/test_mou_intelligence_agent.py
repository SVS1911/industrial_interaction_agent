from datetime import date
from types import SimpleNamespace
from uuid import uuid4

from app.schemas.mou_intelligence import MouIntelligenceExtraction
from app.services import mou_intelligence_agent as agent
from app.services.gemini_mou_extractor import GeminiMouExtractor


def test_structured_schema_rejects_invalid_confidence():
    try:
        MouIntelligenceExtraction(
            summary="x",
            overall_confidence=1.5,
        )
    except Exception:
        return
    raise AssertionError("Expected Pydantic validation to reject confidence > 1")


def test_deterministic_validation_keeps_database_scope_authoritative():
    extraction = MouIntelligenceExtraction(
        summary="The MoU covers training.",
        scope="Different wording",
        overall_confidence=0.9,
    )
    mou = {
        "scope": "Authoritative database scope",
        "valid_from": date(2026, 1, 1),
        "valid_until": date(2027, 1, 1),
    }
    result = agent._deterministic_validate(mou, [], extraction)
    assert result.db_scope == "Authoritative database scope"
    assert result.review_required is True
    assert result.discrepancies


def test_deterministic_validation_flags_missing_llm_deliverable():
    extraction = MouIntelligenceExtraction(
        summary="The MoU includes a deliverable.",
        scope="x",
        overall_confidence=0.95,
    )
    deliverables = [
        {
            "mou_deliverable_id": uuid4(),
            "description": "Guest lectures",
            "deliverable_type": "ACTIVITY",
            "target_count": 2,
            "achieved_count": 0,
            "due_date": date(2026, 12, 1),
            "status": "PENDING",
        }
    ]
    result = agent._deterministic_validate({"scope": "x"}, deliverables, extraction)
    assert result.review_required is True
    assert "deliverables" in result.discrepancies[0].lower()


def test_gemini_extractor_validates_structured_output():
    class FakeInteractions:
        def create(self, **kwargs):
            assert kwargs["response_format"]["mime_type"] == "application/json"
            return SimpleNamespace(
                output_text='{"summary":"Two parties collaborate.","scope":"Training","parties":["A","B"],"commitments":[],"mandatory_commitments_count":0,"conditional_commitments_count":0,"renewal_terms":{"present":false,"summary":null,"notice_period":null,"automatic_renewal":null,"evidence":[]},"exclusions":[],"ambiguities":[],"review_required":false,"overall_confidence":0.91}'
            )

    fake = SimpleNamespace(interactions=FakeInteractions())
    extractor = GeminiMouExtractor(client=fake, model="gemini-test")
    result = extractor.extract(
        partner_name="Partner",
        title="MoU",
        chunks=[{"seq_no": 1, "page_no": 1, "heading_path": "1", "chunk_text": "Training collaboration."}],
        db_context={"scope": "Training"},
    )
    assert result.summary == "Two parties collaborate."
    assert result.overall_confidence == 0.91
