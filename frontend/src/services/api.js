/*
  Frontend API boundary.

  The UI currently uses mockData.js so it can run without a backend.
  When the Python/PostgreSQL backend is ready, replace the functions below
  with fetch calls. Keep the returned shape aligned with the SQL views:
    engagement.v_mou_tracker
    engagement.v_deliverable_status
    engagement.v_partner_activity_ledger
    engagement.partner_health_snapshot
    quality.v_kpi_latest
*/

const API_BASE = import.meta.env.VITE_API_BASE_URL || "";

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options
  });
  if (!response.ok) throw new Error(`API error ${response.status}`);
  return response.json();
}

export const api = {
  getPartners: () => request("/api/industry/partners"),
  getMous: () => request("/api/industry/mous"),
  getMou: (id) => request(`/api/industry/mous/${id}`),
  getActivities: () => request("/api/industry/activities"),
  getHealth: () => request("/api/industry/health"),
  getRecommendations: () => request("/api/industry/recommendations"),
  getEvidence: () => request("/api/industry/evidence"),
  uploadMou: (formData) =>
    fetch(`${API_BASE}/api/industry/mous/upload`, { method: "POST", body: formData }).then((r) => {
      if (!r.ok) throw new Error(`Upload error ${r.status}`);
      return r.json();
    })
};