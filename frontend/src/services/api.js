/**
 * Frontend -> FastAPI boundary.
 *
 * The backend is the source of truth. These functions call the real Agent 28
 * API/view endpoints and normalize database field names into the shapes the
 * existing React UI expects.
 */

const API_BASE = (import.meta.env.VITE_API_BASE_URL ||"").replace(/\/$/, "");

function asNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function itemsFrom(payload) {
  if (Array.isArray(payload)) return payload;
  return Array.isArray(payload?.items) ? payload.items : [];
}

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      Accept: "application/json",
      ...(options.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
      ...(options.headers || {}),
    },
  });

  let body = null;
  try {
    body = await response.json();
  } catch {
    // Keep the original HTTP error if the server did not return JSON.
  }

  if (!response.ok) {
    const detail = body?.detail || body?.message || `API request failed (${response.status})`;
    const message = Array.isArray(detail)
      ? detail.map((item) => item?.msg || JSON.stringify(item)).join("; ")
      : typeof detail === "object"
        ? JSON.stringify(detail)
        : String(detail);
    throw new Error(message);
  }

  return body;
}

function mapPartner(row, healthByPartner = new Map()) {
  const health = healthByPartner.get(row.industry_partner_id);
  return {
    id: row.industry_partner_id,
    name: row.name,
    sector: row.sector_label || row.sector || "—",
    status: row.status,
    score: row.health_score == null ? null : asNumber(row.health_score),
    lastActivity: row.last_activity_on || null,
    mous: asNumber(row.active_mous),
    activities: health ? asNumber(health.activities_12m) : 0,
    owner: row.relationship_owner_name || "—",
    website: row.website || null,
  };
}

function mapHealth(row, partnerById = new Map()) {
  const partner = partnerById.get(row.industry_partner_id);
  return {
    partnerId: row.industry_partner_id,
    partner: partner?.name || row.industry_partner_id,
    score: asNumber(row.health_score),
    band: row.health_band,
    dormant: Boolean(row.is_dormant),
    lastActivity: row.last_activity_on || null,
    days: row.days_since_last_activity == null ? null : asNumber(row.days_since_last_activity),
    activities12m: asNumber(row.activities_12m),
    internships12m: asNumber(row.internships_12m),
    offers12m: asNumber(row.offers_12m),
    activeMou: asNumber(row.active_mou_count),
    due: asNumber(row.deliverables_due),
    achieved: asNumber(row.deliverables_achieved),
    feedback: row.avg_feedback_rating == null ? null : asNumber(row.avg_feedback_rating),
    expiryRisk: asNumber(row.mous_expiring_without_renewal),
    asOfDate: row.as_of_date || null,
  };
}

function mapMou(row) {
  const total = asNumber(row.deliverables_total);
  const achieved = asNumber(row.deliverables_achieved);
  return {
    id: row.mou_id,
    partnerId: row.industry_partner_id,
    partner: row.partner_name,
    title: row.title,
    type: row.partner_type || "—",
    signedOn: row.signed_on,
    validFrom: row.valid_from,
    validUntil: row.valid_until,
    status: row.effective_status || row.status,
    rawStatus: row.status,
    renewal: row.open_renewal_status
      ? row.open_renewal_status.replaceAll("_", " ")
      : row.expiring_without_renewal
        ? "No discussion"
        : "Not due",
    deliverables: total,
    achieved,
    overdue: asNumber(row.deliverables_overdue),
    achievementPct: row.weighted_achievement_pct == null ? null : asNumber(row.weighted_achievement_pct),
    renewalRisk: Boolean(row.expiring_without_renewal),
    activitiesConducted: asNumber(row.activities_conducted),
    lastActivity: row.last_activity_on || null,
    scope: row.scope || "—",
    documentRef: row.document_ref || null,
  };
}

function mapDeliverable(row) {
  return {
    id: row.mou_deliverable_id,
    mouId: row.mou_id,
    description: row.description,
    type: row.deliverable_type || "—",
    target: asNumber(row.target_count),
    achieved: asNumber(row.achieved_count),
    due: row.due_date || null,
    status: row.status,
    suggestedLinks: asNumber(row.links_awaiting_confirmation),
    achievementPct: row.achievement_pct == null ? null : asNumber(row.achievement_pct),
    overdue: Boolean(row.is_overdue),
    sourcePage: row.source_page_no,
    sourceText: row.source_text,
  };
}

function mapActivity(row) {
  return {
    id: row.industry_activity_id,
    partner: row.partner_name || "—",
    partnerId: row.industry_partner_id,
    mouId: row.mou_id,
    type: row.activity_type,
    title: row.title,
    date: row.activity_date,
    endDate: row.end_date || row.activity_date,
    department: row.department_code || "—",
    participants: asNumber(row.participant_count),
    mode: row.mode || "—",
    status: row.status,
    outcome: row.outcome_summary || null,
    evidence: Boolean(row.evidence_ref),
    feedbackResponses: asNumber(row.feedback_responses),
    courseCode: row.course_code || null,
    courseTitle: row.course_title || null,
    calendarClashes: Array.isArray(row.calendar_clashes) ? row.calendar_clashes : [],
  };
}

function mapRecommendation(row) {
  const payload = row.payload && typeof row.payload === "object" ? row.payload : {};
  const company = payload.partner_name || payload.company || payload.partner || row.subject_type || "Unknown target";
  const suggested = payload.suggested_first_step || payload.action || "Review the recommendation and decide the next step.";
  const status = row.approval_status || "NOT_REQUIRED";
  return {
    id: row.agent_output_id,
    priority: payload.priority || (status === "PENDING" ? "HIGH" : status === "MODIFIED" ? "MEDIUM" : "LOW"),
    title: payload.title || `Target partnership: ${company}`,
    reason: row.reasoning_summary || "Agent-generated recommendation stored in Agent 28.",
    action: suggested,
    partner: company,
    status,
    confidence: row.confidence == null ? null : asNumber(row.confidence),
    requiresApproval: Boolean(row.requires_approval),
    createdAt: row.created_at,
    payload,
  };
}

function mapEvidence(row) {
  return {
    id: row.evidence_item_id,
    criterion: row.criterion_code || "—",
    criterionTitle: row.criterion_title || "—",
    title: row.title,
    evidenceType: row.evidence_type || "—",
    period: row.period_start && row.period_end ? `${row.period_start} → ${row.period_end}` : "—",
    source: row.source_table ? `${row.source_schema || ""}.${row.source_table}`.replace(/^\./, "") : "—",
    approved: Boolean(row.approved_at),
    approvedAt: row.approved_at || null,
    generatedBy: row.generated_by_agent || null,
    documentRef: row.document_ref || null,
  };
}

function mapAgentRun(row) {
  return {
    id: row.agent_run_id,
    agent: row.agent_name || row.agent_id || "—",
    started: row.started_at,
    finished: row.finished_at,
    records: asNumber(row.record_count ?? row.records),
    version: row.agent_version || "—",
    status: row.status,
    trigger: row.trigger_type,
    latencyMs: row.latency_ms,
  };
}

export const api = {
  baseUrl: API_BASE,

  health: () => request("/api/health"),
  databaseHealth: () => request("/api/health/db"),

  async getPartners() {
    const [partnerPayload, healthPayload] = await Promise.all([
      request("/api/views/partner-register?limit=500"),
      request("/api/views/partner-health-latest?limit=500"),
    ]);
    const healthRows = itemsFrom(healthPayload);
    const healthByPartner = new Map(healthRows.map((row) => [row.industry_partner_id, row]));
    return itemsFrom(partnerPayload).map((row) => mapPartner(row, healthByPartner));
  },

  async getPartner(id) {
    const [partner, healthPayload] = await Promise.all([
      request(`/api/partners/${encodeURIComponent(id)}`),
      request("/api/views/partner-health-latest?limit=500"),
    ]);
    const health = itemsFrom(healthPayload).find((row) => row.industry_partner_id === id);
    return mapPartner(partner, new Map(health ? [[id, health]] : []));
  },

  async getMous() {
    return itemsFrom(await request("/api/views/mou-tracker?limit=500")).map(mapMou);
  },

  async getMou(id) {
    const [mou, deliverablePayload, trackerPayload] = await Promise.all([
      request(`/api/mous/${encodeURIComponent(id)}`),
      request("/api/views/deliverable-status?limit=500"),
      request("/api/views/mou-tracker?limit=500"),
    ]);
    const tracker = itemsFrom(trackerPayload).find((row) => row.mou_id === id);
    const normalized = mapMou(tracker || {
      ...mou,
      mou_id: mou.mou_id,
      industry_partner_id: mou.industry_partner_id,
      partner_name: mou.partner_name,
    });
    const deliverables = itemsFrom(deliverablePayload)
      .filter((row) => row.mou_id === id)
      .map(mapDeliverable);
    return { ...normalized, deliverables };
  },

  async createActivity(payload) {
    return request("/api/activities", { method: "POST", body: JSON.stringify(payload) });
  },

  async runActivitiesOutcomes(asOfDate) {
    const query = asOfDate ? `?as_of_date=${encodeURIComponent(asOfDate)}` : "";
    return request(`/api/agents/activities-outcomes/run${query}`, { method: "POST" });
  },

  async getAlumni() {
    return itemsFrom(await request("/api/alumni?limit=500"));
  },

  async getGuestLectures() {
    return itemsFrom(await request("/api/guest-lectures?limit=500"))
      .map(row => ({
        id: row.guest_lecture_id,
        speakerName: row.speaker_name,
        speakerType: row.speaker_type,
        alumniId: row.alumni_id,
        domain: row.domain,
        title: row.title,
        date: row.lecture_date,
        endDate: row.end_date || row.lecture_date,
        mode: row.mode || "—",
        participants: asNumber(row.participant_count),
        partnerId: row.industry_partner_id,
        partner: row.partner_name || null,
        mouId: row.mou_id,
        mouTitle: row.mou_title || null,
        status: row.status,
        outcome: row.outcome_summary || null,
        evidence: Boolean(row.evidence_ref),
      }))
      .sort((a, b) => String(b.date).localeCompare(String(a.date)));
  },

  async createGuestLecture(payload) {
    return request("/api/guest-lectures", { method: "POST", body: JSON.stringify(payload) });
  },

  async getActivitiesOutcomesReports() {
    return itemsFrom(await request("/api/agent-outputs?limit=200"))
      .filter(row => row.output_type === "REPORT" && row.subject_type === "INDUSTRY_ACTIVITY")
      .map(row => ({ id: row.agent_output_id, runId: row.agent_run_id, payload: row.payload || {}, reasoning: row.reasoning_summary, createdAt: row.created_at }));
  },

  async getActivities() {
    return itemsFrom(await request("/api/views/activity-calendar?limit=500"))
      .map(mapActivity)
      .sort((a, b) => String(b.date).localeCompare(String(a.date)));
  },

  async getHealth() {
    const [healthPayload, partnerPayload] = await Promise.all([
      request("/api/views/partner-health-latest?limit=500"),
      request("/api/views/partner-register?limit=500"),
    ]);
    const partnerById = new Map(itemsFrom(partnerPayload).map((row) => [row.industry_partner_id, row]));
    return itemsFrom(healthPayload)
      .map((row) => mapHealth(row, partnerById))
      .sort((a, b) => b.score - a.score);
  },

  async runIntelligenceRecommendations(asOfDate) {
    const query = asOfDate ? `?as_of_date=${encodeURIComponent(asOfDate)}` : "";
    return request(`/api/agents/intelligence-recommendations/run${query}`, { method: "POST" });
  },

  async getRecommendations() {
    const payload = await request("/api/agent-outputs?limit=200");
    return itemsFrom(payload)
      .filter((row) => row.output_type === "RECOMMENDATION")
      .map(mapRecommendation)
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  },

  async runAccreditationEvidence(asOfDate) {
    const query = asOfDate ? `?as_of_date=${encodeURIComponent(asOfDate)}` : "";
    return request(`/api/agents/accreditation-evidence/run${query}`, { method: "POST" });
  },

  async downloadAccreditationEvidenceReport() {
    const response = await fetch(`${API_BASE}/api/agents/accreditation-evidence/report.csv`, {
      headers: { Accept: "text/csv" },
    });
    if (!response.ok) {
      let detail = `Report export failed (${response.status})`;
      try {
        const body = await response.json();
        detail = body?.detail || detail;
      } catch {}
      throw new Error(String(detail));
    }
    const blob = await response.blob();
    const disposition = response.headers.get("Content-Disposition") || "";
    const match = disposition.match(/filename="?([^";]+)"?/i);
    const filename = match?.[1] || "agent5-accreditation-evidence.csv";
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  },

  async getAccreditationEvidenceReports() {
    return itemsFrom(await request("/api/agent-outputs?limit=200"))
      .filter(row => row.output_type === "REPORT" && row.subject_type === "ACCREDITATION")
      .map(row => ({ id: row.agent_output_id, runId: row.agent_run_id, payload: row.payload || {}, reasoning: row.reasoning_summary, createdAt: row.created_at }));
  },

  async getEvidence() {
    return itemsFrom(await request("/api/views/accreditation-evidence?limit=500"))
      .map(mapEvidence)
      .sort((a, b) => String(b.approvedAt || "").localeCompare(String(a.approvedAt || "")));
  },

  async getAgentRuns() {
    return itemsFrom(await request("/api/agent-runs?limit=200")).map(mapAgentRun);
  },

  async getActionItems() {
    return itemsFrom(await request("/api/action-items?limit=200"));
  },

  async getDashboard() {
    const [partners, mous, activities, health, recommendations] = await Promise.all([
      this.getPartners(),
      this.getMous(),
      this.getActivities(),
      this.getHealth(),
      this.getRecommendations(),
    ]);
    return { partners, mous, activities, health, recommendations };
  },

  async runMouIntelligence(mouId) {
    const query = mouId ? `?mou_id=${encodeURIComponent(mouId)}` : "";
    return request(`/api/agents/mou-intelligence/run${query}`, { method: "POST" });
  },

  async getMouIntelligenceReports() {
    return itemsFrom(await request("/api/agent-outputs?limit=200"))
      .filter((row) => row.output_type === "REPORT" && row.subject_type === "MOU")
      .map((row) => {
        const payload = row.payload && typeof row.payload === "object" ? row.payload : {};
        return {
          id: row.agent_output_id,
          runId: row.agent_run_id,
          mouId: payload.mou_id || row.subject_id,
          partner: payload.partner_name || "—",
          title: payload.title || "MoU Intelligence Report",
          modelVersion: payload.model_version || "mou-1.0",
          extraction: payload.extraction || {},
          validation: payload.validation || {},
          citations: Array.isArray(payload.citations) ? payload.citations : [],
          confidence: row.confidence == null ? null : asNumber(row.confidence),
          requiresReview: Boolean(payload.requires_human_review || row.requires_approval),
          approvalStatus: row.approval_status || "NOT_REQUIRED",
          createdAt: row.created_at,
        };
      })
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  },

  async uploadMou(formData) {
    return request("/api/agents/mou-intelligence/upload", {
      method: "POST",
      body: formData,
    });
  },
};
