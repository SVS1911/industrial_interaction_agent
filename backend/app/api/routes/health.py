from fastapi import APIRouter
from fastapi.responses import JSONResponse
from app.services.db_service import health_check

router = APIRouter(prefix="/api/health", tags=["Health"])

@router.get("")
def health():
    return {"status": "healthy", "service": "industry-interaction-agent-backend"}

@router.get("/db")
def database_health():
    try:
        info = health_check()
        return {"status": "healthy", "database": info["database"]}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "unhealthy", "database": None})
