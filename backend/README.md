# Industry Interaction Agent — FastAPI Backend

## What this backend does

This is the FastAPI/PostgreSQL backend foundation for Agent 28 — Industry Interaction Agent.
The PostgreSQL SQL file in `backend/database/agent28_synthetic_database.sql` remains the database source of truth; Agent 4 adds only a model-registry row to that existing schema. The backend
does not recreate the database with SQLAlchemy or an ORM.

The SQL defines 13 PostgreSQL schemas and Agent 28 data covering industry partners,
contacts, expertise, MoUs, deliverables, activities, course alignment, partner health,
placement relationships, evidence/documents, agent runs/outputs, human review, alerts,
follow-ups, accreditation evidence and KPIs.

## Technology

Python, FastAPI, PostgreSQL, psycopg3, psycopg connection pooling, Pydantic,
python-dotenv, Uvicorn and pytest.

## Windows setup

Requirements:
- Python 3.10+
- PostgreSQL 14+
- PostgreSQL `psql` client

Create the database:

```powershell
createdb agent28_dev
```

Or create `agent28_dev` using pgAdmin.

Create and activate a virtual environment:

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and set your real PostgreSQL URL:

```text
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/agent28_dev
APP_NAME=Industry Interaction Agent Backend
APP_ENV=development
APP_HOST=127.0.0.1
APP_PORT=8000
PSQL_PATH=psql
```

Never commit `.env`.

Initialize the database:

```powershell
python scripts/init_database.py
```

Verify the database:

```powershell
python scripts/verify_database.py
```

Start FastAPI:

```powershell
uvicorn app.main:app --reload
```

## First verification URL

```text
http://127.0.0.1:8000/api/health
```

Database verification:

```text
http://127.0.0.1:8000/api/health/db
```

Swagger:

```text
http://127.0.0.1:8000/docs
```

## API resources

### Health

- `GET /api/health`
- `GET /api/health/db`

### Database resources

- `GET /api/partners` — list partners
- `GET /api/partners/{id}` — get one
- `GET /api/partner-contacts` — list partner contacts
- `GET /api/partner-contacts/{id}` — get one
- `GET /api/partner-expertise` — list partner expertise
- `GET /api/partner-expertise/{id}` — get one
- `GET /api/mous` — list MoUs
- `GET /api/mous/{id}` — get one
- `GET /api/mou-deliverables` — list MoU deliverables
- `GET /api/mou-deliverables/{id}` — get one
- `GET /api/mou-fulfilments` — list MoU fulfilments
- `GET /api/mou-fulfilments/{id}` — get one
- `GET /api/mou-renewals` — list MoU renewals
- `GET /api/mou-renewals/{id}` — get one
- `GET /api/activities` — list industry activities
- `GET /api/activities/{id}` — get one
- `GET /api/activity-alignments` — list activity course alignments
- `GET /api/activity-alignments/{id}` — get one
- `GET /api/partner-health` — list partner health snapshots
- `GET /api/partner-health/{id}` — get one
- `GET /api/events` — list events
- `GET /api/events/{id}` — get one
- `GET /api/companies` — list companies
- `GET /api/companies/{id}` — get one
- `GET /api/offers` — list offers
- `GET /api/offers/{id}` — get one
- `GET /api/internships` — list internships
- `GET /api/internships/{id}` — get one
- `GET /api/alumni` — list alumni
- `GET /api/alumni/{id}` — get one
- `GET /api/students` — list students
- `GET /api/students/{id}` — get one
- `GET /api/faculty` — list faculty
- `GET /api/faculty/{id}` — get one
- `GET /api/documents` — list documents
- `GET /api/documents/{id}` — get one
- `GET /api/extraction-jobs` — list extraction jobs
- `GET /api/extraction-jobs/{id}` — get one
- `GET /api/extracted-fields` — list extracted fields
- `GET /api/extracted-fields/{id}` — get one
- `GET /api/agent-runs` — list agent runs
- `GET /api/agent-runs/{id}` — get one
- `GET /api/agent-outputs` — list agent outputs
- `GET /api/agent-outputs/{id}` — get one
- `GET /api/human-reviews` — list human reviews
- `GET /api/human-reviews/{id}` — get one
- `GET /api/alerts` — list alerts
- `GET /api/alerts/{id}` — get one
- `GET /api/action-items` — list action items
- `GET /api/action-items/{id}` — get one

### Agent 28 read views

- `GET /api/views`
- `GET /api/views/partner-activity-ledger`
- `GET /api/views/deliverable-status`
- `GET /api/views/mou-tracker`
- `GET /api/views/partner-health-latest`
- `GET /api/views/partner-register`
- `GET /api/views/activity-calendar`
- `GET /api/views/activity-feedback-summary`
- `GET /api/views/sector-gap`
- `GET /api/views/target-partner-candidates`
- `GET /api/views/accreditation-evidence`
- `GET /api/views/kpi-latest`

List APIs support `?limit=50&offset=0`.

## React connection

CORS allows:
- `http://localhost:5173`
- `http://127.0.0.1:5173`

Example:

```javascript
const response = await fetch("http://127.0.0.1:8000/api/partners");
const data = await response.json();
console.log(data.items);
```

## Agent-ready architecture

The current backend intentionally does not fabricate an AI agent. The database already
contains agent registry/run/output/human-review structures. The backend keeps:

React → FastAPI → service layer → PostgreSQL

so future orchestration/agent logic can be added without replacing the database model.

## Testing

```powershell
pytest
```

The health tests do not require a production database.

## Database source notes

The SQL source states that the database is synthetic, should be run on an empty database,
and contains PostgreSQL extensions, functions, triggers, views, grants and a transaction.
It also defines demo "today" as 2026-09-11.

Do not run the initializer against production.

## Frontend integration

The repository also contains a React/Vite frontend. The connected frontend uses the
Agent 28 read views and API resources rather than importing `frontend/src/data/mockData.js`.
See the project-root `FRONTEND_BACKEND_CONNECTION.md` for the integration map and current
implementation boundaries.

## Agent 4 — Intelligence & Recommendations

The repository now contains a deterministic Agent 4 runtime at:

```text
backend/app/services/intelligence_recommendations_agent.py
```

API:

```text
POST /api/agents/intelligence-recommendations/run
```

Agent 4 reads the existing PostgreSQL engagement data and Agent 3 health snapshots. It writes
`agentops.agent_run`, `agentops.agent_run_input` and `agentops.agent_output` records. It does not
call an LLM and it does not execute the recommended business actions. Recommendations are stored
with `requires_approval = true` and `approval_status = PENDING`.

### Existing database migration

Agent 4 uses the model registry version `recommendation-1.0`. If the existing Supabase database
was initialized before this version was added, apply this migration once using PostgreSQL/psql:

```powershell
psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f database/migrations/002_agent4_recommendation_model.sql
```

Fresh database initialization also includes this model registry row. Do not replace or recreate
an existing Supabase database merely to install the model row.

### Swagger

After starting FastAPI, open:

```text
http://127.0.0.1:8000/docs
```

and execute `POST /api/agents/intelligence-recommendations/run`.

The existing Recommendations page has a `Run Agent 4` control and continues to consume
`GET /api/agent-outputs?limit=200`; no frontend framework or database replacement was introduced.

## First real Agent 28 execution: Engagement Health

The backend now contains the first real Agent 28 execution path. It is deliberately **rule-based**, not an LLM, because the SQL source of truth already defines the active `health-1.0` model and its weights.

Run it with:

```text
POST http://127.0.0.1:8000/api/agents/engagement-health/run?as_of_date=2026-09-11
```

The run:

1. Reads live partner, activity, MoU/deliverable, internship, offer, and industry-activity feedback data.
2. Calculates the five health components from the `health-1.0` rules.
3. Classifies each partner as `STRONG`, `STABLE`, `AT_RISK`, or `DORMANT`.
4. Writes `agentops.agent_run` and `agentops.agent_run_input`.
5. Writes/updates `engagement.partner_health_snapshot`.
6. Writes one `CLASSIFICATION` record per processed partner in `agentops.agent_output`.
7. Updates the partner's `engagement_score` and `last_activity_on`.

The endpoint response contains the generated agent outputs directly. This is the first actual execution path; no fake LLM output is used.

## Agent 1 — MoU Intelligence (Google Gemini)

Agent 1 uses Google Gemini for semantic extraction from MoU document chunks, then performs deterministic reconciliation against the authoritative PostgreSQL records. It writes reports to `agentops.agent_output` and does not directly mutate `engagement.mou` or `engagement.mou_deliverable`.

### Gemini configuration

Add these server-side variables to `backend/.env`:

```env
GEMINI_API_KEY=YOUR_GEMINI_API_KEY
GEMINI_MODEL=gemini-3.8-flash
```

Never put the Gemini key in the frontend or commit it to source control.

### Install

```bash
pip install -r requirements.txt
```

### Register Agent 1 model

Against the existing PostgreSQL/Supabase database:

```bash
python scripts/register_agent1_model.py
```

or apply `database/migrations/003_agent1_mou_intelligence_model.sql` using the project's normal migration process.

### Run Agent 1

For one MoU:

```text
POST /api/agents/mou-intelligence/run?mou_id=<UUID>
```

For all MoUs with linked source documents:

```text
POST /api/agents/mou-intelligence/run
```

The endpoint requires `GEMINI_API_KEY` and an active `mou-1.0` model registration.

## Agent 1 frontend + MoU upload

The React MoU Intelligence page is connected to Agent 1. It supports:

- viewing stored Agent 1 reports from `agentops.agent_output`
- running Agent 1 for one existing MoU
- uploading a new PDF MoU from the UI
- storing the uploaded PDF as a `knowledge.document`
- extracting readable PDF pages into `knowledge.document_chunk`
- creating a `knowledge.extraction_job` for provenance
- reusing or creating the matching `engagement.industry_partner`
- creating the new `engagement.mou` linked to the document/job
- automatically running Agent 1 on the new MoU
- showing Gemini extraction, reconciliation flags, confidence and citations in the MoU detail page

The upload endpoint is `POST /api/agents/mou-intelligence/upload` and accepts multipart form data. PDF files with no readable text are rejected with a clear message because OCR is not currently configured.

Basic MoU metadata (partner name, title, partner type and signed date) is collected by the frontend because `engagement.mou.signed_on` is a required authoritative database field. The Agent 1 report remains a report-only output and does not overwrite authoritative MoU/deliverable data.

## Agent 2 and Agent 5 runtime paths

Agent 2 (`activities-2.0`) is the deterministic Activities / DO agent. It connects realised industry activities and placement outcomes to matching MoUs and deliverables, creating missing fulfilment links as `AGENT_SUGGESTED` / `SUGGESTED` rather than auto-confirming them.

API: `POST /api/agents/activities-outcomes/run` (optional `as_of_date`).

Agent 5 (`evidence-5.0`) is the deterministic Accreditation Evidence / PROVE agent. It evaluates authoritative MoU, activity, outcome and feedback records against accreditation criteria and produces an auditable evidence assessment with explicit missing/incomplete proof. It never fabricates evidence.

API: `POST /api/agents/accreditation-evidence/run` (optional `as_of_date`).

The Industry Partners page now supports `POST /api/partners` and the Activities page supports `POST /api/activities` for institution-managed master/activity entry.

## Guest Lecture Registry and Agent 5 Export

Migration `database/migrations/004_guest_lecture_registry.sql` adds the dedicated
`engagement.guest_lecture` table and `engagement.v_guest_lecture_register` view.
It is additive: existing `engagement.industry_activity` guest lectures are not
copied or changed. The new registry is for independently recorded guest lectures
from alumni, industry experts, academics or other speakers; MoU and partner links
are optional.

Apply the migration to the existing PostgreSQL/Supabase database before using the
Guest Lectures page or its API endpoints. The frontend exposes `/guest-lectures`.

Agent 5 now includes evidenced standalone guest lectures in IND-2 and records the
new table as an AgentOps input source. The Accreditation Evidence page's `Export
report` button downloads the latest Agent 5 assessment as CSV from
`GET /api/agents/accreditation-evidence/report.csv`.
