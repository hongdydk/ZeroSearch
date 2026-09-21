from __future__ import annotations

import csv
import io
import uuid
from collections.abc import Iterable
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session, selectinload

from app.models import CatalogProduct, CatalogProductAlias, Product
from app.schemas.catalog_variant import CatalogVariantCreateRequest
from app.services.catalog_identity import canonicalize_csv_rows
from app.services.catalog_l1 import apply_auto_l1_tags
from app.services.catalog_variants import add_catalog_variant, find_variant
from app.services.catalog_variants import rehome_catalog_variants

BATCH = 500

ADMIN_CSV_HEADERS = (
    "제조사", "카드명", "종류", "카드설명", "카드사진URL",
    "옵션명", "수량", "단위", "팩수", "옵션사진URL",
)


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


def _admin_csv_rows(content: bytes) -> list[dict[str, str]]:
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV는 UTF-8로 저장하세요.") from exc
    reader = csv.DictReader(io.StringIO(text))
    headers = tuple((header or "").strip() for header in (reader.fieldnames or []))
    if headers != ADMIN_CSV_HEADERS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="카탈로그 템플릿을 내려받아 같은 열 순서로 작성하세요.",
        )
    rows: list[dict[str, str]] = []
    for line_number, raw in enumerate(reader, start=2):
        row = {key: (raw.get(key) or "").strip() for key in ADMIN_CSV_HEADERS}
        if not any(row.values()):
            continue
        missing = [key for key in ("제조사", "카드명", "종류") if not row[key]]
        if missing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{line_number}행: {', '.join(missing)}은(는) 필수입니다.",
            )
        option_fields = ("옵션명", "수량", "단위", "팩수")
        present = [bool(row[key]) for key in option_fields]
        if any(present) and not all(present):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{line_number}행: 옵션명·수량·단위·팩수는 함께 입력하세요.",
            )
        if all(present):
            try:
                amount = float(row["수량"])
                packs = int(row["팩수"])
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"{line_number}행: 수량과 팩수는 숫자로 입력하세요.",
                ) from exc
            try:
                CatalogVariantCreateRequest(
                    name=row["옵션명"], unitAmount=amount, unit=row["단위"],
                    packCount=packs, imageUrl=row["옵션사진URL"] or None,
                )
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"{line_number}행: 옵션 정보를 확인하세요.",
                ) from exc
        rows.append(row)
    if not rows:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="데이터 행이 없습니다.")
    return rows


def import_admin_catalog_csv(db: Session, content: bytes) -> dict[str, int]:
    """Import reviewed card/options CSV from the admin portal.

    The deployment AI-Hub importer intentionally remains separate: it is a raw
    reference pipeline and must not define the operator-facing CSV contract.
    """
    rows = _admin_csv_rows(content)
    cards: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for row in rows:
        key = (row["제조사"], row["종류"], row["카드명"])
        cards.setdefault(key, []).append(row)

    imported = 0
    for (manufacturer, category, title), card_rows in cards.items():
        catalog = db.scalar(
            select(CatalogProduct).where(
                CatalogProduct.manufacturer == manufacturer,
                CatalogProduct.category == category,
                CatalogProduct.title == title,
            )
        )
        first = card_rows[0]
        if catalog is None:
            catalog = CatalogProduct(
                manufacturer=manufacturer, category=category, title=title,
                description=first["카드설명"] or None,
                image_url=first["카드사진URL"] or None,
                price_unit="ml",
                reference_variants=[], status="active",
            )
            db.add(catalog)
            db.flush()
            apply_auto_l1_tags(catalog, only_if_empty=False)
        else:
            catalog.status = "active"
            if first["카드설명"]:
                catalog.description = first["카드설명"]
            if first["카드사진URL"]:
                catalog.image_url = first["카드사진URL"]
        # CSV re-imports must refresh browse tags too. Otherwise a card updated
        # through the admin portal can be visible to sellers but be filtered out
        # of the buyer's L1/L2 catalogue.
        apply_auto_l1_tags(catalog, only_if_empty=False)

        for row in card_rows:
            if not row["옵션명"]:
                continue
            payload = CatalogVariantCreateRequest(
                name=row["옵션명"], unitAmount=float(row["수량"]), unit=row["단위"],
                packCount=int(row["팩수"]), imageUrl=row["옵션사진URL"] or None,
            )
            existing = find_variant(
                db, catalog_id=catalog.id, name=payload.name,
                unit_amount=payload.unit_amount, unit=payload.unit, pack_count=payload.pack_count,
            )
            if existing is None:
                add_catalog_variant(db, catalog, payload)
            elif payload.image_url:
                existing.image_url = payload.image_url
        imported += 1
    db.flush()
    return {"source_rows": len(rows), "upserted": imported, "canonical_groups": imported, "category_remerged": 0}


def export_admin_catalog_csv(db: Session) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=ADMIN_CSV_HEADERS)
    writer.writeheader()
    catalogs = db.scalars(
        select(CatalogProduct)
        .where(CatalogProduct.status == "active")
        .options(selectinload(CatalogProduct.variants))
        .order_by(CatalogProduct.manufacturer, CatalogProduct.category, CatalogProduct.title)
    ).all()
    for catalog in catalogs:
        base = {
            "제조사": catalog.manufacturer or "", "카드명": catalog.title,
            "종류": catalog.category, "카드설명": catalog.description or "",
            "카드사진URL": catalog.image_url or "",
        }
        variants = sorted(catalog.variants, key=lambda item: (item.name, item.unit, item.unit_amount, item.pack_count))
        if not variants:
            writer.writerow(base)
            continue
        for variant in variants:
            writer.writerow({
                **base, "옵션명": variant.name,
                "수량": format(Decimal(variant.unit_amount).normalize(), "f"),
                "단위": variant.unit, "팩수": variant.pack_count,
                "옵션사진URL": variant.image_url or "",
            })
    return output.getvalue().encode("utf-8-sig")


def admin_catalog_template_csv() -> bytes:
    output = io.StringIO(newline="")
    csv.DictWriter(output, fieldnames=ADMIN_CSV_HEADERS).writeheader()
    return output.getvalue().encode("utf-8-sig")
