from __future__ import annotations

import logging
import threading
import uuid
from typing import Any

from sqlalchemy import text

from app.database import SessionLocal
from app.services.catalog_import import import_catalog_csv

logger = logging.getLogger(__name__)
_jobs: dict[str, dict[str, Any]] = {}
_lock = threading.Lock()


def get_job(job_id: str) -> dict[str, Any] | None:
    with _lock:
        job = _jobs.get(job_id)
        return dict(job) if job is not None else None


def start_import_job(csv_text: str) -> dict[str, Any]:
    job_id = str(uuid.uuid4())
    with _lock:
        _jobs[job_id] = {
            "job_id": job_id,
            "status": "running",
            "source_rows": 0,
            "upserted": 0,
            "error": None,
        }
    thread = threading.Thread(target=_run_import_job, args=(job_id, csv_text), daemon=True)
    thread.start()
    return get_job(job_id) or {"job_id": job_id, "status": "running", "source_rows": 0, "upserted": 0, "error": None}


def _update(job_id: str, **fields: Any) -> None:
    with _lock:
        job = _jobs.get(job_id)
        if job is not None:
            job.update(fields)


def _run_import_job(job_id: str, csv_text: str) -> None:
    db = SessionLocal()
    try:
        db.execute(text("SET LOCAL lock_timeout = '15s'"))
        db.execute(text("SET LOCAL statement_timeout = '90s'"))
        result = import_catalog_csv(db, csv_text.encode("utf-8"))
        db.commit()
        _update(job_id, status="done", source_rows=result["source_rows"], upserted=result["upserted"])
    except Exception as exc:
        db.rollback()
        logger.exception("catalog import job %s failed", job_id)
        _update(job_id, status="error", error=_job_error_message(exc))
    finally:
        db.close()


def _job_error_message(exc: Exception) -> str:
    text_exc = str(exc).lower()
    if "lock timeout" in text_exc or "canceling statement" in text_exc:
        return "다른 작업이 끝나지 않았습니다. 초기화가 끝나면 다시 올리세요."
    if "cannot affect row a second time" in text_exc:
        return "같은 품목이 두 줄이라 반영하지 못했습니다."
    return "카탈로그 반영에 실패했습니다."
