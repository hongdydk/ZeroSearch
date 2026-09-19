from collections import defaultdict
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.models import CartItem, CatalogProduct, Product
from app.schemas.admin import AdminCatalogCreateRequest, AdminCatalogProductItem
from app.services.catalog_l1 import apply_auto_l1_tags, set_l1_tags
from app.services.catalog_products import _aggregate_offers, _catalog_search_filter
from app.services.catalog_variants import add_catalog_variant
from app.services.catalog_remerge import resolve_catalog_product


def _catalog_item(
    catalog: CatalogProduct,
    offer_count: int,
    published_offer_count: int,
    *,
    shop_count: int = 0,
    median_unit_price: float | None = None,
    median_price_credits: int | None = None,
    price_unit: str = "credits",
    display_price_label: str = "원",
) -> AdminCatalogProductItem:
    return AdminCatalogProductItem(
        id=str(catalog.id),
        title=catalog.title,
        manufacturer=catalog.manufacturer or "",
        category=catalog.category,
        status=catalog.status,
        offer_count=offer_count,
        published_offer_count=published_offer_count,
        shop_count=shop_count,
        median_unit_price=median_unit_price,
        median_price_credits=median_price_credits,
        price_unit=price_unit,  # type: ignore[arg-type]
        display_price_label=display_price_label,
        image_url=catalog.image_url,
        l1_tags=list(catalog.l1_tags or []),
        created_at=catalog.created_at,
    )


def _public_offers(offers: list[Product]) -> list[Product]:
    public: list[Product] = []
    for offer in offers:
        if offer.status != "published":
            continue
        seller = offer.seller
        if seller is None or seller.status != "active":
            continue
        public.append(offer)
    return public


def offer_stats_for_admin(offers: list[Product]) -> tuple[int, int, int, float | None, int | None, str, str]:
    """전체 오퍼 수, 공개(구매자) 오퍼 수, 가게 수, 중위 단가."""
    public = _public_offers(offers)
    published_count, median_unit, median_credits, price_unit, label = _aggregate_offers(public)
    shop_count = len({offer.seller_id for offer in public})
    return len(offers), published_count, shop_count, median_unit, median_credits, price_unit, label


def list_admin_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    include_retired: bool = False,
    l1_tag: str | None = None,
    offset: int = 0,
    limit: int = 50,
) -> tuple[list[AdminCatalogProductItem], int]:
    filters = _catalog_search_filter(
        q,
        None,
        l1_tag=l1_tag,
        include_retired=include_retired,
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
    offers = list(
        db.scalars(
            select(Product)
            .where(Product.catalog_product_id.in_(ids))
            .options(joinedload(Product.seller))
        )
        .unique()
        .all()
    )
    by_catalog: dict[UUID, list[Product]] = defaultdict(list)
    for offer in offers:
        by_catalog[offer.catalog_product_id].append(offer)
    items = [_item_with_stats(catalog, by_catalog[catalog.id]) for catalog in catalogs]
    return items, int(total)


def _item_with_stats(catalog: CatalogProduct, offers: list[Product]) -> AdminCatalogProductItem:
    offer_count, published, shop_count, median_unit, median_credits, price_unit, label = offer_stats_for_admin(
        offers
    )
    return _catalog_item(
        catalog,
        offer_count,
        published,
        shop_count=shop_count,
        median_unit_price=median_unit,
        median_price_credits=median_credits,
        price_unit=price_unit,
        display_price_label=label,
    )


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
        for variant in payload.variants:
            add_catalog_variant(db, existing, variant)
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
    for variant in payload.variants:
        add_catalog_variant(db, catalog, variant)
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
