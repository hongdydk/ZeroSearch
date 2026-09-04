from statistics import median
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import Text, cast, exists, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models import CatalogProduct, Product, Seller
from app.schemas.catalog_product import (
    CatalogOfferItem,
    CatalogProductDetailResponse,
    CatalogProductListItem,
)
from app.schemas.seller import SellerSummary


def _median(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(median(values))


def _public_offer_filters(
    *,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
):
    filters = [Product.status == "published", Seller.status == "active"]
    if flavor:
        filters.append(Product.flavor == flavor)
    if volume_ml_min is not None:
        filters.append(Product.volume_ml >= volume_ml_min)
    if volume_ml_max is not None:
        filters.append(Product.volume_ml <= volume_ml_max)
    return filters


def _aggregate_offers(offers: list[Product]) -> tuple[int, float | None, int | None, str, str]:
    """Return offer_count, median_unit_price, median_price_credits, price_unit, display_label."""
    count = len(offers)
    if count == 0:
        return 0, None, None, "credits", "크레딧(보통)"

    unit_prices = [
        offer.price_credits / offer.volume_ml
        for offer in offers
        if offer.volume_ml is not None and offer.volume_ml > 0
    ]
    if unit_prices:
        return count, _median(unit_prices), None, "ml", "L당"

    credit_prices = [float(offer.price_credits) for offer in offers]
    return count, None, int(_median(credit_prices)), "credits", "크레딧(보통)"


def _catalog_search_filter(
    q: str | None,
    category: str | None,
    *,
    category_major: str | None = None,
    category_mid: str | None = None,
):
    filters = []
    if q:
        pattern = f"%{q.strip()}%"
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
    if category:
        filters.append(CatalogProduct.category == category)
    if category_major:
        filters.append(CatalogProduct.category_major == category_major)
    if category_mid:
        filters.append(CatalogProduct.category_mid == category_mid)
    return filters


def _has_public_offers(
    *,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
):
    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    return exists(
        select(Product.id)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id == CatalogProduct.id, *offer_filters)
    )


def _list_item(catalog: CatalogProduct, offers: list[Product]) -> CatalogProductListItem:
    offer_count, median_unit, median_credits, price_unit, display_label = _aggregate_offers(offers)
    return CatalogProductListItem(
        id=str(catalog.id),
        title=catalog.title,
        manufacturer=catalog.manufacturer or "",
        category=catalog.category,
        category_major=catalog.category_major,
        category_mid=catalog.category_mid,
        description=catalog.description,
        image_url=catalog.image_url,
        volume_options=list(catalog.volume_options or []),
        offer_count=offer_count,
        median_unit_price=median_unit,
        median_price_credits=median_credits,
        price_unit=price_unit,  # type: ignore[arg-type]
        display_price_label=display_label,
    )


def list_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    category_major: str | None = None,
    category_mid: str | None = None,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
    offset: int = 0,
    limit: int = 50,
    require_offers: bool = True,
) -> tuple[list[CatalogProductListItem], int]:
    catalog_filters = _catalog_search_filter(
        q,
        category,
        category_major=category_major,
        category_mid=category_mid,
    )
    stmt = select(CatalogProduct)
    count_stmt = select(func.count()).select_from(CatalogProduct)
    if catalog_filters:
        stmt = stmt.where(*catalog_filters)
        count_stmt = count_stmt.where(*catalog_filters)
    if require_offers:
        has_offers = _has_public_offers(
            flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
        )
        stmt = stmt.where(has_offers)
        count_stmt = count_stmt.where(has_offers)

    total = db.scalar(count_stmt) or 0
    catalogs = db.scalars(
        stmt.order_by(CatalogProduct.manufacturer, CatalogProduct.title).offset(offset).limit(limit)
    ).all()
    if not catalogs:
        return [], total

    ids = [c.id for c in catalogs]
    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    offers = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id.in_(ids), *offer_filters)
        .options(joinedload(Product.seller))
    ).unique().all()
    by_catalog: dict[UUID, list[Product]] = {cid: [] for cid in ids}
    for offer in offers:
        by_catalog[offer.catalog_product_id].append(offer)

    items = [_list_item(catalog, by_catalog[catalog.id]) for catalog in catalogs]
    return items, total


def search_seller_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    offset: int = 0,
    limit: int = 30,
) -> tuple[list[CatalogProductListItem], int]:
    return list_catalog_products(
        db,
        q=q,
        category=category,
        offset=offset,
        limit=limit,
        require_offers=False,
    )


def get_catalog_product(
    db: Session,
    catalog_id: UUID,
    *,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
) -> CatalogProductDetailResponse:
    catalog = db.scalar(select(CatalogProduct).where(CatalogProduct.id == catalog_id))
    if catalog is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="대표 상품을 찾을 수 없습니다.")

    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    offers = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id == catalog.id, *offer_filters)
        .options(joinedload(Product.seller))
        .order_by(Product.price_credits)
    ).unique().all()

    offer_items = [
        CatalogOfferItem(
            id=str(o.id),
            option_label=o.option_label,
            flavor=o.flavor,
            volume_ml=o.volume_ml,
            price_credits=o.price_credits,
            stock=o.stock,
            seller=SellerSummary(
                id=str(o.seller.id),
                shop_name=o.seller.shop_name,
                seller_type=o.seller.seller_type,  # type: ignore[arg-type]
            ),
        )
        for o in offers
    ]

    return CatalogProductDetailResponse(
        id=str(catalog.id),
        title=catalog.title,
        manufacturer=catalog.manufacturer or "",
        category=catalog.category,
        category_major=catalog.category_major,
        category_mid=catalog.category_mid,
        description=catalog.description,
        image_url=catalog.image_url,
        volume_options=list(catalog.volume_options or []),
        offer_count=len(offer_items),
        offers=offer_items,
        created_at=catalog.created_at,
    )
