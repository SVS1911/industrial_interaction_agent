from app.services.accreditation_evidence_agent import MODEL_VERSION


def test_agent5_model_version_is_stable():
    assert MODEL_VERSION == "evidence-5.0"
