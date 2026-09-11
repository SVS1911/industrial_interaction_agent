export const partners = [
  { id: "p1", name: "Infosys", sector: "IT Services", status: "ACTIVE", score: 91, lastActivity: "2026-09-04", mous: 2, activities: 8, owner: "Dr. Priya Rao" },
  { id: "p2", name: "TCS", sector: "IT Services", status: "ACTIVE", score: 84, lastActivity: "2026-08-18", mous: 2, activities: 6, owner: "Dr. Arjun Kumar" },
  { id: "p3", name: "Wipro", sector: "IT Services", status: "ACTIVE", score: 72, lastActivity: "2026-06-12", mous: 1, activities: 4, owner: "Dr. Priya Rao" },
  { id: "p4", name: "Deloitte", sector: "Consulting", status: "ACTIVE", score: 67, lastActivity: "2026-05-28", mous: 1, activities: 3, owner: "Dr. Meera Singh" },
  { id: "p5", name: "Tech Mahindra", sector: "IT Services", status: "DORMANT", score: 34, lastActivity: "2026-02-14", mous: 1, activities: 1, owner: "Dr. Arjun Kumar" },
  { id: "p6", name: "Siemens", sector: "Industrial Automation", status: "ACTIVE", score: 79, lastActivity: "2026-07-21", mous: 1, activities: 5, owner: "Dr. Ravi Teja" }
];

export const mous = [
  { id: "m1", partnerId: "p1", partner: "Infosys", title: "Academic & Industry Collaboration", type: "INDUSTRY", signedOn: "2025-01-18", validFrom: "2025-02-01", validUntil: "2027-01-31", status: "ACTIVE", renewal: "No discussion", deliverables: 7, achieved: 6, scope: "Guest lectures, internships, projects, curriculum input and faculty engagement." },
  { id: "m2", partnerId: "p2", partner: "TCS", title: "Industry-Academia Partnership", type: "INDUSTRY", signedOn: "2024-12-10", validFrom: "2025-01-01", validUntil: "2026-12-15", status: "ACTIVE", renewal: "Discussion initiated", deliverables: 6, achieved: 5, scope: "Training, expert talks, internship drives and placement interaction." },
  { id: "m3", partnerId: "p3", partner: "Wipro", title: "Skills & Employability Collaboration", type: "INDUSTRY", signedOn: "2025-06-15", validFrom: "2025-07-01", validUntil: "2027-06-30", status: "ACTIVE", renewal: "Not due", deliverables: 5, achieved: 3, scope: "Skill development, workshops, projects and industry visits." },
  { id: "m4", partnerId: "p5", partner: "Tech Mahindra", title: "Industry Interaction MoU", type: "INDUSTRY", signedOn: "2024-03-12", validFrom: "2024-04-01", validUntil: "2026-09-30", status: "ACTIVE", renewal: "No discussion", deliverables: 4, achieved: 1, scope: "Training, expert sessions and sponsored student projects." }
];

export const deliverables = [
  { id: "d1", mouId: "m1", description: "Expert talks / guest lectures", type: "EXPERT_TALK", target: 3, achieved: 3, due: "2026-11-30", status: "ACHIEVED" },
  { id: "d2", mouId: "m1", description: "Industry internship opportunities", type: "INTERNSHIP", target: 2, achieved: 1, due: "2026-12-15", status: "IN_PROGRESS" },
  { id: "d3", mouId: "m1", description: "Curriculum input session", type: "CURRICULUM_INPUT", target: 1, achieved: 1, due: "2026-10-30", status: "ACHIEVED" },
  { id: "d4", mouId: "m2", description: "Student training programme", type: "TRAINING_PROGRAMME", target: 2, achieved: 2, due: "2026-10-31", status: "ACHIEVED" },
  { id: "d5", mouId: "m2", description: "Internship drive", type: "INTERNSHIP", target: 1, achieved: 1, due: "2026-09-30", status: "ACHIEVED" },
  { id: "d6", mouId: "m2", description: "Industry project", type: "SPONSORED_PROJECT", target: 2, achieved: 1, due: "2026-12-20", status: "IN_PROGRESS" }
];

export const activities = [
  { id: "a1", partner: "Infosys", partnerId: "p1", mouId: "m1", type: "GUEST_LECTURE", title: "AI Engineering in Production", date: "2026-09-04", department: "CSE", participants: 182, mode: "HYBRID", status: "CONDUCTED", outcome: "Students gained exposure to production AI workflows.", evidence: true },
  { id: "a2", partner: "TCS", partnerId: "p2", mouId: "m2", type: "INTERNSHIP_DRIVE", title: "TCS Internship Drive 2026", date: "2026-08-18", department: "CSE", participants: 246, mode: "OFFLINE", status: "CONDUCTED", outcome: "72 students shortlisted for technical rounds.", evidence: true },
  { id: "a3", partner: "Siemens", partnerId: "p6", mouId: null, type: "INDUSTRY_VISIT", title: "Industrial Automation Visit", date: "2026-07-21", department: "CSE", participants: 64, mode: "OFFLINE", status: "CONDUCTED", outcome: "Hands-on understanding of industrial automation systems.", evidence: true },
  { id: "a4", partner: "Wipro", partnerId: "p3", mouId: "m3", type: "EXPERT_TALK", title: "Cloud & Data Engineering Careers", date: "2026-06-12", department: "CSE", participants: 154, mode: "ONLINE", status: "CONDUCTED", outcome: "Industry expectations mapped to current skill gaps.", evidence: true },
  { id: "a5", partner: "Deloitte", partnerId: "p4", mouId: null, type: "SPONSORED_PROJECT", title: "Industry Analytics Challenge", date: "2026-05-28", department: "CSE", participants: 38, mode: "HYBRID", status: "CONDUCTED", outcome: "Three student teams completed business analytics prototypes.", evidence: false },
  { id: "a6", partner: "Tech Mahindra", partnerId: "p5", mouId: "m4", type: "TRAINING_PROGRAMME", title: "Digital Skills Bootcamp", date: "2026-02-14", department: "CSE", participants: 91, mode: "ONLINE", status: "CONDUCTED", outcome: "One training programme completed; no follow-up activity yet.", evidence: true }
];

export const health = [
  { partnerId: "p1", partner: "Infosys", score: 91, band: "STRONG", dormant: false, lastActivity: "2026-09-04", days: 7, activities12m: 8, internships12m: 2, offers12m: 14, activeMou: 2, due: 1, achieved: 6, feedback: 4.7, expiryRisk: 0 },
  { partnerId: "p2", partner: "TCS", score: 84, band: "STRONG", dormant: false, lastActivity: "2026-08-18", days: 24, activities12m: 6, internships12m: 3, offers12m: 11, activeMou: 2, due: 1, achieved: 5, feedback: 4.5, expiryRisk: 1 },
  { partnerId: "p6", partner: "Siemens", score: 79, band: "STABLE", dormant: false, lastActivity: "2026-07-21", days: 52, activities12m: 5, internships12m: 1, offers12m: 5, activeMou: 1, due: 1, achieved: 4, feedback: 4.3, expiryRisk: 0 },
  { partnerId: "p3", partner: "Wipro", score: 72, band: "STABLE", dormant: false, lastActivity: "2026-06-12", days: 91, activities12m: 4, internships12m: 1, offers12m: 7, activeMou: 1, due: 2, achieved: 3, feedback: 4.1, expiryRisk: 0 },
  { partnerId: "p4", partner: "Deloitte", score: 67, band: "AT_RISK", dormant: false, lastActivity: "2026-05-28", days: 107, activities12m: 3, internships12m: 0, offers12m: 3, activeMou: 1, due: 2, achieved: 1, feedback: 3.8, expiryRisk: 0 },
  { partnerId: "p5", partner: "Tech Mahindra", score: 34, band: "DORMANT", dormant: true, lastActivity: "2026-02-14", days: 209, activities12m: 1, internships12m: 0, offers12m: 1, activeMou: 1, due: 3, achieved: 1, feedback: 3.2, expiryRisk: 1 }
];

export const recommendations = [
  { id: "r1", priority: "URGENT", title: "Initiate renewal discussion with Tech Mahindra", reason: "MoU enters expiry window on 30 Sep 2026 and no open renewal discussion is recorded.", action: "Assign relationship owner and propose a renewal meeting.", partner: "Tech Mahindra", status: "OPEN" },
  { id: "r2", priority: "HIGH", title: "Re-engage Deloitte", reason: "Engagement score is declining with 107 days since the last realised activity.", action: "Schedule one expert interaction or live industry project this term.", partner: "Deloitte", status: "OPEN" },
  { id: "r3", priority: "HIGH", title: "Close the pending Infosys internship deliverable", reason: "One of two committed internship opportunities is still unfulfilled.", action: "Coordinate with placement cell and partner SPOC.", partner: "Infosys", status: "IN_PROGRESS" },
  { id: "r4", priority: "MEDIUM", title: "Convert Wipro skill interaction into a project", reason: "Recent expert interaction exposed a data/cloud skill gap.", action: "Propose a course-aligned industry project for CSE.", partner: "Wipro", status: "OPEN" }
];

export const evidence = [
  { id: "e1", criterion: "IND-1", title: "Functional MoU register", period: "2025-26", source: "engagement.mou", status: "READY", coverage: 100 },
  { id: "e2", criterion: "IND-2", title: "Industry activity and participation evidence", period: "2025-26", source: "engagement.industry_activity", status: "READY", coverage: 94 },
  { id: "e3", criterion: "IND-3", title: "MoU deliverable fulfilment report", period: "2025-26", source: "engagement.mou_deliverable_fulfilment", status: "PARTIAL", coverage: 78 },
  { id: "e4", criterion: "IND-4", title: "Industry interaction feedback analysis", period: "2025-26", source: "quality.feedback_response", status: "READY", coverage: 91 },
  { id: "e5", criterion: "IND-5", title: "Industry engagement KPI export", period: "2026-27", source: "quality.kpi_value", status: "IN_REVIEW", coverage: 63 }
];

export const agentRuns = [
  { id: "run-901", agent: "Engagement Health", started: "2026-09-11 12:30", status: "COMPLETED", records: 6, version: "health-1.0" },
  { id: "run-900", agent: "MoU Intelligence", started: "2026-09-11 11:48", status: "COMPLETED", records: 4, version: "mou-extract-1.2" },
  { id: "run-899", agent: "Recommendation", started: "2026-09-11 11:10", status: "COMPLETED", records: 4, version: "reco-1.0" },
  { id: "run-898", agent: "Accreditation Evidence", started: "2026-09-10 17:42", status: "COMPLETED", records: 5, version: "evidence-1.1" }
];