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

## Mock data

Mock data is deliberately small and only exists to make the frontend demonstrable before the backend is connected.

Replace `src/data/mockData.js` usage with the API functions in:

`src/services/api.js`

The API boundary already expects routes such as:

- `GET /api/industry/partners`
- `GET /api/industry/mous`
- `GET /api/industry/mous/:id`
- `GET /api/industry/activities`
- `GET /api/industry/health`
- `GET /api/industry/recommendations`
- `GET /api/industry/evidence`
- `POST /api/industry/mous/upload`

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
