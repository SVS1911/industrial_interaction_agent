from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import close_pool

from app.api.routes.health import router as health_router
from app.api.routes.partners import router as partners_router
from app.api.routes.partner_contacts import router as partner_contacts_router
from app.api.routes.partner_expertise import router as partner_expertise_router
from app.api.routes.mous import router as mous_router
from app.api.routes.mou_deliverables import router as mou_deliverables_router
from app.api.routes.mou_fulfilments import router as mou_fulfilments_router
from app.api.routes.mou_renewals import router as mou_renewals_router
from app.api.routes.activities import router as activities_router
from app.api.routes.activity_alignments import router as activity_alignments_router
from app.api.routes.partner_health import router as partner_health_router
from app.api.routes.events import router as events_router
from app.api.routes.companies import router as companies_router
from app.api.routes.offers import router as offers_router
from app.api.routes.internships import router as internships_router
from app.api.routes.alumni import router as alumni_router
from app.api.routes.students import router as students_router
from app.api.routes.faculty import router as faculty_router
from app.api.routes.documents import router as documents_router
from app.api.routes.extraction_jobs import router as extraction_jobs_router
from app.api.routes.extracted_fields import router as extracted_fields_router
from app.api.routes.agent_runs import router as agent_runs_router
from app.api.routes.agent_outputs import router as agent_outputs_router
from app.api.routes.human_reviews import router as human_reviews_router
from app.api.routes.alerts import router as alerts_router
from app.api.routes.action_items import router as action_items_router
from app.api.routes.views import router as views_router
from app.api.routes.agents import router as agents_router
from app.api.routes.mou_intelligence_upload import router as mou_intelligence_upload_router
from app.api.routes.agents_do_prove import router as agents_do_prove_router
from app.api.routes.guest_lectures import router as guest_lectures_router


# ============================================
# React frontend location
# ============================================

BASE_DIR = Path(__file__).resolve().parents[1]
FRONTEND_DIST = BASE_DIR / "frontend_dist"


# ============================================
# FastAPI application
# ============================================

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="Database/API foundation for Agent 28 — Industry Interaction Agent.",
)


# ============================================
# CORS
# ============================================

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================
# API Routers
# ============================================

app.include_router(health_router)
app.include_router(partners_router)
app.include_router(partner_contacts_router)
app.include_router(partner_expertise_router)
app.include_router(mous_router)
app.include_router(mou_deliverables_router)
app.include_router(mou_fulfilments_router)
app.include_router(mou_renewals_router)
app.include_router(activities_router)
app.include_router(activity_alignments_router)
app.include_router(partner_health_router)
app.include_router(events_router)
app.include_router(companies_router)
app.include_router(offers_router)
app.include_router(internships_router)
app.include_router(alumni_router)
app.include_router(students_router)
app.include_router(faculty_router)
app.include_router(documents_router)
app.include_router(extraction_jobs_router)
app.include_router(extracted_fields_router)
app.include_router(agent_runs_router)
app.include_router(agent_outputs_router)
app.include_router(human_reviews_router)
app.include_router(alerts_router)
app.include_router(action_items_router)
app.include_router(views_router)
app.include_router(agents_router)
app.include_router(mou_intelligence_upload_router)
app.include_router(agents_do_prove_router)
app.include_router(guest_lectures_router)


# ============================================
# Root endpoint
# ============================================

@app.get("/")
def root():
    if FRONTEND_DIST.exists():
        return FileResponse(FRONTEND_DIST / "index.html")

    return {
        "service": settings.app_name,
        "status": "running",
        "docs": "/docs",
        "database_source_of_truth": "database/agent28_synthetic_database.sql",
    }


# ============================================
# Shutdown
# ============================================

@app.on_event("shutdown")
def shutdown():
    close_pool()


# ============================================
# Serve React frontend
# ============================================

if FRONTEND_DIST.exists():
    app.mount(
        "/assets",
        StaticFiles(
            directory=FRONTEND_DIST / "assets"
        ),
        name="assets",
    )

    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str):
        requested_file = FRONTEND_DIST / full_path

        if requested_file.is_file():
            return FileResponse(requested_file)

        return FileResponse(
            FRONTEND_DIST / "index.html"
        )