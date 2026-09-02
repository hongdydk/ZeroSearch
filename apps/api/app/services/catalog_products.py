from statistics import median
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import or_, select
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


def _catalog_search_filter(q: str | None, category: str | None):
    filters = []
    if q:
        pattern = f"%{q.strip()}%"
        filters.append(
            or_(
                CatalogProduct.title.ilike(pattern),
                CatalogProduct.category.ilike(pattern),
                CatalogProduct.description.ilike(pattern),
                CatalogProduct.search_keywords.astext.ilike(pattern),
            )
        )
    if category:
        filters.append(CatalogProduct.category == category)
    return filters


def list_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
    offset: int = 0,
    limit: int = 50,
) -> tuple[list[CatalogProductListItem], int]:
    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    catalog_filters = _catalog_search_filter(q, category)

    base = select(CatalogProduct)
    if catalog_filters:
        base = base.where(*catalog_filters)

    all_catalogs = db.scalars(base.order_by(CatalogProduct.title)).all()
    items: list[CatalogProductListItem] = []

    for catalog in all_catalogs:
        offers = db.scalars(
            select(Product)
            .join(Seller, Product.seller_id == Seller.id)
            .where(Product.catalog_product_id == catalog.id, *offer_filters)
            .options(joinedload(Product.seller))
        ).unique().all()

        offer_count, median_unit, median_credits, price_unit, display_label = _aggregate_offers(
            list(offers)
        )
        if offer_count == 0:
            continue

        items.append(
            CatalogProductListItem(
                id=str(catalog.id),
                title=catalog.title,
                category=catalog.category,
                description=catalog.description,
                image_url=catalog.image_url,
                offer_count=offer_count,
                median_unit_price=median_unit,
                median_price_credits=median_credits,
                price_unit=price_unit,  # type: ignore[arg-type]
                display_price_label=display_label,
            )
        )

    total = len(items)
    page = items[offset : offset + limit]
    return page, total


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
        category=catalog.category,
        description=catalog.description,
        image_url=catalog.image_url,
        offer_count=len(offer_items),
        offers=offer_items,
        created_at=catalog.created_at,
    )
