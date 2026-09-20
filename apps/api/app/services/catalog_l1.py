"""Persist guest L1/L2 tags on catalog products and list L1 facets."""

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
from app.services.catalog_identity import collapse_axis_facets
from app.services.guest_l2 import infer_l2_tags, is_guest_l2, l2s_for, normalize_l2_tags


def apply_auto_l1_tags(catalog: CatalogProduct, *, only_if_empty: bool = True) -> bool:
    current_l1 = list(catalog.l1_tags or [])
    current_l2 = list(getattr(catalog, "l2_tags", None) or [])
    skip_l1 = only_if_empty and bool(current_l1)
    skip_l2 = only_if_empty and bool(current_l2)
    if skip_l1 and skip_l2:
        return False

    result = infer_l1_tags(
        title=catalog.title or "",
        manufacturer=catalog.manufacturer or "",
        category=catalog.category or "",
        category_major=catalog.category_major or "",
        category_mid=catalog.category_mid or "",
        storage=catalog.storage,
    )
    new_l1 = current_l1 if skip_l1 else result.tags
    l2_result = infer_l2_tags(
        title=catalog.title or "",
        manufacturer=catalog.manufacturer or "",
        category=catalog.category or "",
        category_major=catalog.category_major or "",
        category_mid=catalog.category_mid or "",
        storage=result.storage or catalog.storage,
        l1_tags=new_l1,
    )
    new_l2 = current_l2 if skip_l2 else l2_result.tags
    storage_changed = (not skip_l1) and bool(result.storage) and catalog.storage != result.storage
    changed = False
    if not skip_l1 and (list(catalog.l1_tags or []) != new_l1 or storage_changed):
        catalog.l1_tags = new_l1
        if result.storage:
            catalog.storage = result.storage
        flag_modified(catalog, "l1_tags")
        changed = True
    if not skip_l2 and list(getattr(catalog, "l2_tags", None) or []) != new_l2:
        catalog.l2_tags = new_l2
        flag_modified(catalog, "l2_tags")
        changed = True
    return changed


def set_l1_tags(catalog: CatalogProduct, tags: list[str], *, storage: str | None = None) -> None:
    catalog.l1_tags = normalize_l1_tags(tags)
    if storage in {"상온", "냉장", "냉동"}:
        catalog.storage = storage
    flag_modified(catalog, "l1_tags")
    l2_result = infer_l2_tags(
        title=catalog.title or "",
        manufacturer=catalog.manufacturer or "",
        category=catalog.category or "",
        category_major=catalog.category_major or "",
        category_mid=catalog.category_mid or "",
        storage=catalog.storage,
        l1_tags=catalog.l1_tags,
    )
    catalog.l2_tags = l2_result.tags
    flag_modified(catalog, "l2_tags")


def set_l2_tags(catalog: CatalogProduct, tags: list[str]) -> None:
    catalog.l2_tags = normalize_l2_tags(tags, l1_tags=list(catalog.l1_tags or []))
    flag_modified(catalog, "l2_tags")


def backfill_l1_tags(db: Session, *, only_if_empty: bool = True) -> int:
    stmt = select(CatalogProduct)
    if only_if_empty:
        stmt = stmt.where(
            or_(
                CatalogProduct.l1_tags.is_(None),
                func.coalesce(func.jsonb_array_length(CatalogProduct.l1_tags), 0) == 0,
                CatalogProduct.l2_tags.is_(None),
                func.coalesce(func.jsonb_array_length(CatalogProduct.l2_tags), 0) == 0,
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


def l2_tag_filter(l1_tag: str | None, l2_tag: str | None):
    """L2 목록 필터. 빈 값은 필터 없음. 1차에 없는 L2·L1 없음은 빈 결과(fail-closed)."""
    if not l2_tag:
        return None
    if not is_guest_l2(l1_tag, l2_tag):
        return false()
    return CatalogProduct.l2_tags.contains([l2_tag])


def _empty_facets(l1_tag: str = "", l2_tag: str = "") -> dict:
    return {
        "l1_tag": l1_tag,
        "l2_tag": l2_tag,
        "l2s": list(l2s_for(l1_tag)) if l1_tag in GUEST_L1_SET else [],
        "default_axis": "brand",
        "brands": [],
        "menus": [],
    }


def list_l1_facets(
    db: Session,
    *,
    l1_tag: str | None = None,
    l2_tag: str | None = None,
    q: str | None = None,
    storage: str | None = None,
) -> dict:
    tag = (l1_tag or "").strip()
    l2 = (l2_tag or "").strip()
    query = (q or "").strip()
    if tag and tag not in GUEST_L1_SET:
        return _empty_facets(tag, l2)
    if l2 and not is_guest_l2(tag, l2):
        return _empty_facets(tag, l2)

    filters = []
    if tag:
        filters.append(l1_tag_filter(tag))
    if l2:
        filters.append(l2_tag_filter(tag, l2))
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
        return _empty_facets(tag, l2)
    filters.append(CatalogProduct.status == "active")

    rows = db.execute(
        select(CatalogProduct.manufacturer, CatalogProduct.title).where(*filters)
    ).all()
    brands, menus = collapse_axis_facets(
        (manufacturer or "", title or "") for manufacturer, title in rows
    )

    axis: Axis = default_axis_for(tag) if tag else "brand"
    return {
        "l1_tag": tag,
        "l2_tag": l2,
        "l2s": list(l2s_for(tag)) if tag in GUEST_L1_SET else [],
        "default_axis": axis,
        "brands": brands,
        "menus": menus,
    }
