from __future__ import annotations

import csv
import io
import uuid
from collections.abc import Iterable

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import CatalogProduct, CatalogProductAlias, Product
from app.services.catalog_identity import canonicalize_csv_rows
from app.services.catalog_variants import rehome_catalog_variants

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
            "manufacturer": maker,
            "title": title,
            "category": category,
            "category_major": _clip(row.get("대분류") or "", 120) or None,
            "category_mid": _clip(row.get("중분류") or "", 120) or None,
            "volume_options": _volume_options(row.get("용량") or ""),
            "category_override_reason": _clip(row.get("분류교정사유") or "", 500) or None,
            "price_unit": "each",
        }


def _apply_explicit_category_overrides(db: Session, corrected_rows: list[dict]) -> int:
    if not corrected_rows:
        return 0
    corrected_groups, _ = canonicalize_csv_rows(corrected_rows)
    targets: dict[tuple[str, str], str] = {}
    for group in corrected_groups:
        key = (group.manufacturer, group.canonical_title)
        previous = targets.get(key)
        if previous is not None and previous != group.category:
            raise RuntimeError(
                f"분류 override 충돌: {group.manufacturer} / {group.canonical_title}"
            )
        targets[key] = group.category

    remerged = 0
    for (manufacturer, title), category in targets.items():
        target = db.scalar(
            select(CatalogProduct).where(
                CatalogProduct.manufacturer == manufacturer,
                CatalogProduct.category == category,
                CatalogProduct.title == title,
            )
        )
        if target is None:
            raise RuntimeError(
                f"분류 override target 없음: {manufacturer} / {category} / {title}"
            )
        stale_rows = list(
            db.scalars(
                select(CatalogProduct).where(
                    CatalogProduct.manufacturer == manufacturer,
                    CatalogProduct.title == title,
                    CatalogProduct.category != category,
                )
            ).all()
        )
        for stale in stale_rows:
            db.execute(
                update(Product)
                .where(Product.catalog_product_id == stale.id)
                .values(catalog_product_id=target.id)
            )
            db.execute(
                update(CatalogProductAlias)
                .where(CatalogProductAlias.canonical_id == stale.id)
                .values(canonical_id=target.id)
            )
            own_alias = db.get(CatalogProductAlias, stale.id)
            if own_alias is None:
                db.add(
                    CatalogProductAlias(
                        alias_id=stale.id,
                        canonical_id=target.id,
                        original_title=stale.title,
                    )
                )
            else:
                own_alias.canonical_id = target.id
            if not target.image_url and stale.image_url:
                target.image_url = stale.image_url
            rehome_catalog_variants(db, stale.id, target.id)
            db.delete(stale)
            db.flush()
            remerged += 1
    return remerged


def import_catalog_csv(db: Session, content: bytes) -> dict[str, int]:
    text = content.decode("utf-8-sig")
    upserted = 0
    batch: list[dict] = []
    raw_rows = list(_iter_rows(text))
    source_rows = len(raw_rows)
    groups, _medium = canonicalize_csv_rows(raw_rows)

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
                "reference_variants": stmt.excluded.reference_variants,
            },
        )
        db.execute(stmt)
        upserted += len(batch)
        batch = []

    for group in groups:
        batch.append(
            {
                "id": uuid.uuid4(),
                "manufacturer": group.manufacturer[:200],
                "title": group.canonical_title[:200],
                "category": group.category[:120],
                "category_major": (group.category_major or None),
                "category_mid": (group.category_mid or None),
                "volume_options": group.volume_options,
                "reference_variants": [v.to_dict() for v in group.reference_variants],
                "price_unit": "each",
            }
        )
        if len(batch) >= BATCH:
            flush()

    flush()
    db.flush()
    category_remerged = _apply_explicit_category_overrides(
        db,
        [row for row in raw_rows if row.get("category_override_reason")],
    )
    from app.services.catalog_l1 import backfill_l1_tags
    from app.services.catalog_remerge import apply_db_remarge

    backfill_l1_tags(db, only_if_empty=True)
    apply_db_remarge(db)
    return {
        "source_rows": source_rows,
        "upserted": upserted,
        "canonical_groups": len(groups),
        "category_remerged": category_remerged,
    }
