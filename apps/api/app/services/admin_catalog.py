from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import CartItem, CatalogProduct, Product
from app.schemas.admin import AdminCatalogCreateRequest, AdminCatalogProductItem
from app.services.catalog_l1 import apply_auto_l1_tags, set_l1_tags
from app.services.catalog_remerge import resolve_catalog_product


def _catalog_item(catalog: CatalogProduct, offer_count: int, published_offer_count: int) -> AdminCatalogProductItem:
    return AdminCatalogProductItem(
        id=str(catalog.id),
        title=catalog.title,
        manufacturer=catalog.manufacturer or "",
        category=catalog.category,
        status=catalog.status,
        offer_count=offer_count,
        published_offer_count=published_offer_count,
        image_url=catalog.image_url,
        l1_tags=list(catalog.l1_tags or []),
        created_at=catalog.created_at,
    )


def list_admin_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    include_retired: bool = False,
    offset: int = 0,
    limit: int = 50,
) -> tuple[list[AdminCatalogProductItem], int]:
    filters = []
    if not include_retired:
        filters.append(CatalogProduct.status == "active")
    text = (q or "").strip()
    if text:
        pattern = f"%{text}%"
        filters.append(
            or_(
                CatalogProduct.title.ilike(pattern),
                CatalogProduct.manufacturer.ilike(pattern),
                CatalogProduct.category.ilike(pattern),
            )
        )
    count_stmt = select(func.count()).select_from(CatalogProduct)
    list_stmt = select(CatalogProduct)
    if filters:
        count_stmt = count_stmt.where(*filters)
        list_stmt = list_stmt.where(*filters)
    total = db.scalar(count_stmt) or 0
    catalogs = list(
        db.scalars(
            list_stmt.order_by(CatalogProduct.manufacturer, CatalogProduct.title)
            .offset(offset)
            .limit(limit)
        ).all()
    )
    if not catalogs:
        return [], int(total)

    ids = [catalog.id for catalog in catalogs]
    offer_counts = {cid: 0 for cid in ids}
    published_counts = {cid: 0 for cid in ids}
    for catalog_id, count in db.execute(
        select(Product.catalog_product_id, func.count())
        .where(Product.catalog_product_id.in_(ids))
        .group_by(Product.catalog_product_id)
    ):
        offer_counts[catalog_id] = int(count)
    for catalog_id, count in db.execute(
        select(Product.catalog_product_id, func.count())
        .where(Product.catalog_product_id.in_(ids), Product.status == "published")
        .group_by(Product.catalog_product_id)
    ):
        published_counts[catalog_id] = int(count)
    items = [
        _catalog_item(catalog, offer_counts[catalog.id], published_counts[catalog.id])
        for catalog in catalogs
    ]
    return items, int(total)


def create_admin_catalog_product(db: Session, payload: AdminCatalogCreateRequest) -> AdminCatalogProductItem:
    manufacturer = payload.manufacturer.strip()
    title = payload.title.strip()
    category = payload.category.strip()
    existing = db.scalar(
        select(CatalogProduct).where(
            CatalogProduct.manufacturer == manufacturer,
            CatalogProduct.category == category,
            CatalogProduct.title == title,
        )
    )
    if existing is not None:
        if existing.status == "active":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="같은 회사·종류·품목 카드가 있습니다.",
            )
        existing.status = "active"
        existing.description = payload.description
        existing.image_url = (payload.image_url or "").strip() or existing.image_url
        existing.price_unit = payload.price_unit
        if payload.volume_options:
            existing.volume_options = payload.volume_options
        if payload.l1_tags is not None:
            set_l1_tags(existing, payload.l1_tags, storage=payload.storage)
        else:
            apply_auto_l1_tags(existing, only_if_empty=True)
        db.flush()
        offer_total = db.scalar(
            select(func.count()).select_from(Product).where(Product.catalog_product_id == existing.id)
        ) or 0
        published = db.scalar(
            select(func.count())
            .select_from(Product)
            .where(Product.catalog_product_id == existing.id, Product.status == "published")
        ) or 0
        return _catalog_item(existing, int(offer_total), int(published))

    catalog = CatalogProduct(
        manufacturer=manufacturer,
        title=title,
        category=category,
        description=payload.description,
        image_url=(payload.image_url or "").strip() or None,
        price_unit=payload.price_unit,
        volume_options=list(payload.volume_options or []),
        reference_variants=[],
        status="active",
    )
    db.add(catalog)
    if payload.l1_tags is not None:
        set_l1_tags(catalog, payload.l1_tags, storage=payload.storage)
    else:
        apply_auto_l1_tags(catalog, only_if_empty=False)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="같은 회사·종류·품목 카드가 있습니다.",
        ) from exc
    return _catalog_item(catalog, 0, 0)


def retire_catalog_product(db: Session, catalog_id: UUID) -> AdminCatalogProductItem:
    catalog = resolve_catalog_product(db, catalog_id) or db.get(CatalogProduct, catalog_id)
    if catalog is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="대표 상품을 찾을 수 없습니다.")
    if catalog.status == "retired":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 삭제한 카드입니다.")

    offer_ids = list(db.scalars(select(Product.id).where(Product.catalog_product_id == catalog.id)).all())
    if offer_ids:
        db.execute(delete(CartItem).where(CartItem.product_id.in_(offer_ids)))
        db.execute(
            update(Product)
            .where(Product.catalog_product_id == catalog.id)
            .values(status="archived")
        )
        # 주문 줄 FK를 깨지 않도록 products·catalog 행은 남긴다.

    catalog.status = "retired"
    db.flush()
    return _catalog_item(catalog, len(offer_ids), 0)
