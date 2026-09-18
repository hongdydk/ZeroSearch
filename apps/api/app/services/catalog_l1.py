"""Persist guest L1 tags on catalog products and list L1 facets."""

from __future__ import annotations

from sqlalchemy import Text, cast, false, func, or_, select
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from app.models import CatalogProduct
from app.services.guest_l1 import (
    GUEST_L1_SET,
    Axis,
    default_axis_for,
    infer_l1_tags,
    normalize_l1_tags,
)


def apply_auto_l1_tags(catalog: CatalogProduct, *, only_if_empty: bool = True) -> bool:
    current = list(catalog.l1_tags or [])
    if only_if_empty and current:
        return False
    result = infer_l1_tags(
        title=catalog.title or "",
        manufacturer=catalog.manufacturer or "",
        category=catalog.category or "",
        category_major=catalog.category_major or "",
        category_mid=catalog.category_mid or "",
        storage=catalog.storage,
    )
    new_tags = result.tags
    storage_changed = bool(result.storage) and catalog.storage != result.storage
    if list(catalog.l1_tags or []) == new_tags and not storage_changed:
        return False
    catalog.l1_tags = new_tags
    if result.storage:
        catalog.storage = result.storage
    flag_modified(catalog, "l1_tags")
    return True


def set_l1_tags(catalog: CatalogProduct, tags: list[str], *, storage: str | None = None) -> None:
    catalog.l1_tags = normalize_l1_tags(tags)
    if storage in {"상온", "냉장", "냉동"}:
        catalog.storage = storage
    flag_modified(catalog, "l1_tags")


def backfill_l1_tags(db: Session, *, only_if_empty: bool = True) -> int:
    stmt = select(CatalogProduct)
    if only_if_empty:
        stmt = stmt.where(
            or_(
                CatalogProduct.l1_tags.is_(None),
                func.coalesce(func.jsonb_array_length(CatalogProduct.l1_tags), 0) == 0,
            )
        )
    updated = 0
    for catalog in db.scalars(stmt).yield_per(200):
        if apply_auto_l1_tags(catalog, only_if_empty=only_if_empty):
            updated += 1
    if updated:
        db.flush()
    return updated


def l1_tag_filter(tag: str | None):
    """L1 목록 필터. 빈 값은 필터 없음, 알 수 없는 태그는 빈 결과(fail-closed)."""
    if not tag:
        return None
    if tag not in GUEST_L1_SET:
        return false()
    return CatalogProduct.l1_tags.contains([tag])


def _empty_facets(l1_tag: str = "") -> dict:
    return {
        "l1_tag": l1_tag,
        "default_axis": "brand",
        "brands": [],
        "menus": [],
    }


def list_l1_facets(
    db: Session,
    *,
    l1_tag: str | None = None,
    q: str | None = None,
    storage: str | None = None,
) -> dict:
    tag = (l1_tag or "").strip()
    query = (q or "").strip()
    if tag and tag not in GUEST_L1_SET:
        return _empty_facets(tag)

    filters = []
    if tag:
        filters.append(l1_tag_filter(tag))
    if query:
        pattern = f"%{query}%"
        filters.append(
            or_(
                CatalogProduct.title.ilike(pattern),
                CatalogProduct.manufacturer.ilike(pattern),
                CatalogProduct.category.ilike(pattern),
                CatalogProduct.category_major.ilike(pattern),
                CatalogProduct.category_mid.ilike(pattern),
                CatalogProduct.description.ilike(pattern),
                cast(CatalogProduct.search_keywords, Text).ilike(pattern),
            )
        )
    if storage in {"상온", "냉장", "냉동"}:
        filters.append(CatalogProduct.storage == storage)
    if not filters:
        return _empty_facets(tag)

    brand_rows = db.execute(
        select(CatalogProduct.manufacturer, func.count())
        .where(*filters, CatalogProduct.manufacturer != "")
        .group_by(CatalogProduct.manufacturer)
        .order_by(func.count().desc(), CatalogProduct.manufacturer)
    ).all()
    menu_rows = db.execute(
        select(CatalogProduct.title, func.count())
        .where(*filters)
        .group_by(CatalogProduct.title)
        .order_by(func.count().desc(), CatalogProduct.title)
    ).all()

    axis: Axis = default_axis_for(tag) if tag else "brand"
    return {
        "l1_tag": tag,
        "default_axis": axis,
        "brands": [{"name": name, "count": count} for name, count in brand_rows if name],
        "menus": [{"name": name, "count": count} for name, count in menu_rows if name],
    }
