# Agent 28 — Frontend / Backend Connection

## What was changed

The existing React/Vite frontend was previously rendering `frontend/src/data/mockData.js` directly. The existing `frontend/src/services/api.js` also referenced `/api/industry/...` paths that do not exist in the FastAPI backend.

The frontend now calls the real FastAPI backend and maps its PostgreSQL/view field names into the shapes expected by the existing UI.

### Connected pages

- Dashboard
- Industry Partners
- MoU Intelligence
- MoU Details
- Activities & Outcomes
- Engagement Health
- Recommendations
- Accreditation Evidence
- Agent Runs

### Backend endpoints used

- `GET /api/views/partner-register`
- `GET /api/views/partner-health-latest`
- `GET /api/views/mou-tracker`
- `GET /api/views/deliverable-status`
- `GET /api/views/activity-calendar`
- `GET /api/agent-outputs`
- `GET /api/agent-runs`
- `GET /api/partners/{id}`

The frontend base URL is controlled by `VITE_API_BASE_URL`. If it is not supplied, it defaults to `http://127.0.0.1:8000`.

## Important: what is NOT claimed as implemented

The following workflows are intentionally not fabricated:

- MoU file upload
- AI/OCR/LLM MoU extraction
- Human validation workflow for newly uploaded MoUs
- Creating partners/activities from the UI
- Creating action items from recommendation cards
- Evidence report export
- Full Agent 1–5 orchestration

The corresponding UI buttons are disabled where the backend has no real endpoint yet.

## Source of truth

The PostgreSQL database and its Agent 28 views remain authoritative. `mockData.js` is retained as a development fixture but is no longer imported by the connected pages.

## Local run

### Backend

```powershell
cd backend
.venv\Scripts\activate
uvicorn app.main:app --reload
```

### Frontend

```powershell
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173`.

## Expected smoke test

The dashboard should no longer display the old hard-coded six-partner demo dataset. It should load records from the backend. The current synthetic database contains approximately:

- 32 industry partners
- 40 MoUs
- 205 industry activities
- 294 partner-health snapshots
- 124 MoU deliverables
- 369 MoU fulfilment records
- 22 agent runs
- 33 agent outputs
- 138 evidence items

The exact dashboard cards are filtered/aggregated views of those records, so their displayed numbers do not need to equal every raw table count.

## Verification performed in the build environment

- All modified Python files compile successfully with `compileall`.
- All frontend JavaScript/JSX source files parse successfully with the repository's Babel parser.
- A production Vite build could not be completed in this environment because the uploaded `node_modules` contains Windows-native Rollup/esbuild binaries while the validation environment is Linux. Run `npm install` on the Windows development machine before `npm run build`.
- Live Supabase API verification was not performed from this environment because the required PostgreSQL client dependency/network access is unavailable here. The project therefore does not claim a live database test from this environment.
