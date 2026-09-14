# Industry Interaction Agent — Frontend

A lightweight React + Vite + JavaScript frontend for Agent 28: **Industry Interaction Agent**.

## Visual direction

The UI palette is derived from the supplied Vignan's Agentic AI Day reference image:

- White / near-white surfaces
- Very light blue page backgrounds
- Vignan-style blue primary accent
- Dark navy text
- Soft blue borders
- Rounded cards and subtle shadows

The original reference image is included in `reference/agentic-ai-day-reference.png`.

## Run

```bash
npm install
npm run dev
```

Then open the Vite URL shown in the terminal.

## Stack

- React
- Vite
- JavaScript (JSX) — **not TypeScript**
- React Router
- Plain CSS
- No UI framework dependency

## Database alignment

The frontend is intentionally shaped around the Agent 28 PostgreSQL schema rather than inventing a separate frontend data model.

Important SQL objects represented in the UI:

- `engagement.industry_partner`
- `engagement.mou`
- `engagement.mou_deliverable`
- `engagement.mou_deliverable_fulfilment`
- `engagement.mou_renewal`
- `engagement.industry_activity`
- `engagement.partner_health_snapshot`
- `engagement.v_mou_tracker`
- `engagement.v_deliverable_status`
- `engagement.v_partner_activity_ledger`
- `quality.kpi_value` / `quality.v_kpi_latest`
- `quality.evidence_item`
- `agentops.agent_run` / AgentOps run history

The frontend does **not** create or modify the PostgreSQL schema.

## Backend connection

The main UI pages are now connected to the FastAPI backend. `src/services/api.js` calls the real Agent 28 endpoints and normalizes PostgreSQL/view field names for the existing components.

Backend base URL:

```text
VITE_API_BASE_URL=http://127.0.0.1:8000
```

If the variable is not present, the frontend uses `http://127.0.0.1:8000` by default. See `.env.example`.

Connected data sources include:

- `GET /api/views/partner-register`
- `GET /api/views/partner-health-latest`
- `GET /api/views/mou-tracker`
- `GET /api/views/deliverable-status`
- `GET /api/views/activity-calendar`
- `GET /api/agent-outputs`
- `GET /api/agent-runs`
- `GET /api/partners/{id}`

`src/data/mockData.js` is retained only as a development fixture. Connected pages no longer import it.

The current backend does not yet provide real MoU upload/AI extraction, create-partner, create-activity, action-item creation, evidence export, or complete five-agent orchestration. Those UI actions are therefore not presented as working features.

## Five-agent UI mapping

1. **MoU Intelligence** — `/mous`
2. **Industry Activity & Outcome** — `/activities`
3. **Engagement Health** — `/health`
4. **Industry Intelligence & Recommendation** — `/recommendations`
5. **Accreditation Evidence** — `/evidence`

The overall product story is:

**Promise → Do → Check → Recommend → Prove**

## Suggested next integration order

1. Keep this frontend running with mock data.
2. Build the Python API layer.
3. Connect PostgreSQL using the supplied Agent 28 SQL schema.
4. Replace mock data with API responses.
5. Connect the five AI-agent workflows.
6. Add authentication / role-based access.
7. Add real document upload and MoU extraction.

## Guest lectures and Agent 5 export

The `/guest-lectures` page is a dedicated registry for guest lectures that do not
require an MoU. It supports alumni, industry experts, academics and other invited
speakers, with optional partner/MoU traceability.

The Accreditation Evidence page now has an `Export report` action. It downloads
the latest Agent 5 accreditation assessment as CSV from the backend.
