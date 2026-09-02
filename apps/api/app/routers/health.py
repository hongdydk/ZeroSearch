from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database import get_db

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    return {"status": "ok", "service": "shopping-mall-api"}


@router.get("/health/ready")
def health_ready(db: Annotated[Session, Depends(get_db)]):
    checks: dict[str, str] = {}
    overall = "ok"

    try:
        db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:
        checks["database"] = f"error: {exc}"
        overall = "degraded"

    return {"status": overall, "checks": checks}
