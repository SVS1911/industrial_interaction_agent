from app.services import activities_outcomes_agent as agent


def test_activity_type_map_covers_all_activity_types():
    expected = {
        "GUEST_LECTURE", "EXPERT_TALK", "INDUSTRY_VISIT", "FACULTY_EXCHANGE",
        "LAB_SUPPORT", "SPONSORED_PROJECT", "CONSULTANCY", "INTERNSHIP_DRIVE"
    }
    assert expected.issubset(agent.TYPE_MAP)


def test_activity_type_map_uses_matching_deliverable_types():
    assert agent.TYPE_MAP["GUEST_LECTURE"] == {"GUEST_LECTURE"}
    assert "INTERNSHIP" in agent.TYPE_MAP["INTERNSHIP_DRIVE"]
    assert "PLACEMENT" not in agent.TYPE_MAP["GUEST_LECTURE"]
