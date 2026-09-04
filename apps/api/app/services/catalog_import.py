from __future__ import annotations

import csv
import io
import uuid
from collections.abc import Iterable

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import CatalogProduct

BATCH = 500


def _clip(value: str, max_len: int) -> str:
    return value.strip()[:max_len]


def _volume_options(raw: str) -> list[str]:
    parts = [p.strip() for p in (raw or "").split("|")]
    return [p for p in parts if p and p != "해당없음"]


def _iter_rows(text: str) -> Iterable[dict]:
    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        return
    for row in reader:
        maker = _clip(row.get("제조사") or "", 200)
        title = _clip(row.get("품목명") or "", 200)
        category = _clip(row.get("소분류") or "", 120)
        if not maker or not title or not category:
            continue
        yield {
            "id": uuid.uuid4(),
            "manufacturer": maker,
            "title": title,
            "category": category,
            "category_major": _clip(row.get("대분류") or "", 120) or None,
            "category_mid": _clip(row.get("중분류") or "", 120) or None,
            "volume_options": _volume_options(row.get("용량") or ""),
            "price_unit": "each",
        }


def import_catalog_csv(db: Session, content: bytes) -> dict[str, int]:
    text = content.decode("utf-8-sig")
    upserted = 0
    batch: list[dict] = []
    source_rows = 0

    def flush() -> None:
        nonlocal upserted, batch
        if not batch:
            return
        stmt = insert(CatalogProduct).values(batch)
        stmt = stmt.on_conflict_do_update(
            constraint="uq_catalog_products_maker_category_title",
            set_={
                "category_major": stmt.excluded.category_major,
                "category_mid": stmt.excluded.category_mid,
                "volume_options": stmt.excluded.volume_options,
            },
        )
        db.execute(stmt)
        upserted += len(batch)
        batch = []

    for row in _iter_rows(text):
        source_rows += 1
        batch.append(row)
        if len(batch) >= BATCH:
            flush()

    flush()
    db.flush()
    return {
        "source_rows": source_rows,
        "upserted": upserted,
    }
