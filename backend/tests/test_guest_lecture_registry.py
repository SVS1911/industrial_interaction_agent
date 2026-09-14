from app.schemas.guest_lecture import GuestLectureCreate


def test_guest_lecture_accepts_standalone_expert_without_mou():
    row = GuestLectureCreate(
        speaker_name="Asha Expert",
        speaker_type="INDUSTRY_EXPERT",
        domain="Cloud Computing",
        title="Practical Cloud Security",
        lecture_date="2026-09-14",
        status="CONDUCTED",
    )
    assert row.mou_id is None
    assert row.industry_partner_id is None
    assert row.speaker_type == "INDUSTRY_EXPERT"


def test_guest_lecture_accepts_alumni_link():
    row = GuestLectureCreate(
        speaker_name="Alumni Speaker",
        speaker_type="ALUMNI",
        alumni_id="00000000-0000-0000-0000-000000000001",
        domain="Artificial Intelligence",
        title="AI in Industry",
        lecture_date="2026-09-14",
    )
    assert row.speaker_type == "ALUMNI"
    assert row.alumni_id is not None
