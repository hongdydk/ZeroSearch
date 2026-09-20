from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import and_, case, delete, func, or_, select, update
from sqlalchemy.orm import Session, joinedload

from app.models import CartItem, CatalogIntakeDraft, CatalogProduct, Product, Seller
from app.schemas.product import ProductResponse, SellerProductBulkFailure, SellerProductCounts
from app.schemas.seller import (
    SellerOfferFilter,
    SellerOfferSort,
    SellerProductBulkRequest,
    SellerProductCreateRequest,
    SellerProductUpdateRequest,
    SellerSummary,
)
from app.services.catalog_remerge import resolve_catalog_product
from app.services.offer_units import resolve_offer_units


def _product_response(product: Product) -> ProductResponse:
    return ProductResponse(
        id=str(product.id),
        title=product.title,
        description=product.description,
        price_credits=product.price_credits,
        stock=product.stock,
        category=product.category,
        image_url=product.image_url,
        detail_image_urls=product.detail_image_urls or [],
        status=product.status,  # type: ignore[arg-type]
        catalog_product_id=str(product.catalog_product_id),
        variant_id=str(product.variant_id) if product.variant_id else None,
        option_label=product.option_label,
        volume_ml=product.volume_ml,
        unit_amount=float(product.unit_amount) if product.unit_amount is not None else None,
        unit=product.unit,
        pack_count=product.pack_count or 1,
        flavor=product.flavor,
        seller=SellerSummary(
            id=str(product.seller.id),
            shop_name=product.seller.shop_name,
            seller_type=product.seller.seller_type,  # type: ignore[arg-type]
        ),
        created_at=product.created_at,
    )


def list_public_products(db: Session, *, offset: int = 0, limit: int = 50) -> tuple[list[Product], int]:
    filters = (Product.status == "published", Seller.status == "active")
    total = (
        db.scalar(
            select(func.count())
            .select_from(Product)
            .join(Seller, Product.seller_id == Seller.id)
            .where(*filters)
        )
        or 0
    )
    products = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(*filters)
        .options(joinedload(Product.seller))
        .order_by(Product.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).unique().all()
    return list(products), total


def get_public_product(db: Session, product_id: UUID) -> Product:
    product = db.scalar(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(
            Product.id == product_id,
            Product.status == "published",
            Seller.status == "active",
        )
        .options(joinedload(Product.seller))
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="상품을 찾을 수 없습니다.")
    return product


def _seller_offer_search_filters(q: str | None) -> list:
    text = (q or "").strip()
    if not text:
        return []
    pattern = f"%{text}%"
    return [or_(Product.title.ilike(pattern), Product.option_label.ilike(pattern))]


def _seller_offer_status_filters(offer_filter: SellerOfferFilter) -> list:
    return {
        "published": [Product.status == "published", Product.stock > 0],
        "pending": [Product.status == "draft"],
        "sold_out": [Product.status == "published", Product.stock <= 0],
        "hidden": [Product.status == "archived"],
        "all": [],
    }[offer_filter]


def _seller_offer_order(sort: SellerOfferSort):
    if sort == "price":
        return Product.price_credits.asc(), Product.created_at.desc()
    if sort == "stock":
        return Product.stock.asc(), Product.created_at.desc()
    return (Product.created_at.desc(),)


def _count_if(condition):
    return func.coalesce(func.sum(case((condition, 1), else_=0)), 0)


def list_seller_products(
    db: Session,
    seller: Seller,
    *,
    q: str | None = None,
    offer_filter: SellerOfferFilter = "all",
    sort: SellerOfferSort = "newest",
    offset: int = 0,
    limit: int = 20,
) -> tuple[list[Product], int, SellerProductCounts]:
    owner = Product.seller_id == seller.id
    search_filters = _seller_offer_search_filters(q)
    status_filters = _seller_offer_status_filters(offer_filter)
    counts_row = db.execute(
        select(
            func.count().label("all_count"),
            _count_if(and_(Product.status == "published", Product.stock > 0)).label("published"),
            _count_if(Product.status == "draft").label("pending"),
            _count_if(and_(Product.status == "published", Product.stock <= 0)).label("sold_out"),
            _count_if(Product.status == "archived").label("hidden"),
        )
        .select_from(Product)
        .where(owner, *search_filters)
    ).one()
    counts = SellerProductCounts(
        all=int(counts_row.all_count or 0),
        published=int(counts_row.published or 0),
        pending=int(counts_row.pending or 0),
        sold_out=int(counts_row.sold_out or 0),
        hidden=int(counts_row.hidden or 0),
    )
    total = {
        "all": counts.all,
        "published": counts.published,
        "pending": counts.pending,
        "sold_out": counts.sold_out,
        "hidden": counts.hidden,
    }[offer_filter]
    products = db.scalars(
        select(Product)
        .where(owner, *search_filters, *status_filters)
        .options(joinedload(Product.seller))
        .order_by(*_seller_offer_order(sort))
        .offset(offset)
        .limit(limit)
    ).unique().all()
    return list(products), total, counts


def get_seller_product(db: Session, seller: Seller, product_id: UUID) -> Product:
    product = db.scalar(
        select(Product)
        .where(Product.id == product_id, Product.seller_id == seller.id)
        .options(joinedload(Product.seller))
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="상품을 찾을 수 없습니다.")
    return product


def _resolve_catalog_product(
    db: Session, payload: SellerProductCreateRequest
) -> CatalogProduct:
    if not payload.catalog_product_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="대표 상품을 목록에서 고르세요.",
        )
    catalog = resolve_catalog_product(db, UUID(payload.catalog_product_id))
    if catalog is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="대표 상품을 찾을 수 없습니다.")
    return catalog


def create_seller_product(db: Session, seller: Seller, payload: SellerProductCreateRequest) -> Product:
    catalog = _resolve_catalog_product(db, payload)
    variant = None
    if payload.variant_id:
        from app.services.catalog_variants import require_catalog_variant

        variant = require_catalog_variant(db, catalog.id, payload.variant_id)
    units = resolve_offer_units(
        option_label=None if variant else payload.option_label,
        unit_amount=float(variant.unit_amount) if variant else payload.unit_amount,
        unit=variant.unit if variant else payload.unit,
        pack_count=variant.pack_count if variant else payload.pack_count,
        volume_ml=None if variant else payload.volume_ml,
    )
    product = Product(
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        variant_id=variant.id if variant else None,
        title=(f"{catalog.title} · {variant.name} · {units.option_label}"[:200] if variant else catalog.title),
        description=payload.description,
        price_credits=payload.price_credits or 0,
        stock=payload.stock or 0,
        category=catalog.category,
        image_url=payload.image_url or (variant.image_url if variant else None) or catalog.image_url,
        detail_image_urls=payload.detail_image_urls,
        status="draft",
        option_label=units.option_label,
        volume_ml=units.volume_ml,
        unit_amount=units.unit_amount,
        unit=units.unit,
        pack_count=units.pack_count,
        flavor=None if variant else payload.flavor,
    )
    db.add(product)
    db.flush()
    product = get_seller_product(db, seller, product.id)
    return product


def _apply_seller_product_update(product: Product, payload: SellerProductUpdateRequest) -> None:
    if product.variant_id and any(
        value is not None
        for value in (payload.option_label, payload.unit_amount, payload.unit, payload.pack_count, payload.volume_ml, payload.flavor)
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="상품 옵션은 변경할 수 없습니다. 새 오퍼를 등록하세요.")
    if payload.status is not None:
        if payload.status == "published" and product.status == "draft":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="검수 전에는 공개할 수 없습니다.",
            )
    if payload.title is not None:
        product.title = payload.title
    if payload.description is not None:
        product.description = payload.description
    if payload.price_credits is not None:
        product.price_credits = payload.price_credits
    if payload.stock is not None:
        product.stock = payload.stock
    if payload.category is not None:
        product.category = payload.category
    if payload.image_url is not None:
        product.image_url = payload.image_url
    if payload.detail_image_urls is not None:
        product.detail_image_urls = payload.detail_image_urls
    if payload.status is not None:
        product.status = payload.status
    if payload.flavor is not None:
        product.flavor = payload.flavor
    unit_touched = any(
        value is not None
        for value in (payload.option_label, payload.unit_amount, payload.unit, payload.pack_count, payload.volume_ml)
    )
    if unit_touched:
        units = resolve_offer_units(
            option_label=payload.option_label if payload.option_label is not None else product.option_label,
            unit_amount=payload.unit_amount if payload.unit_amount is not None else (
                float(product.unit_amount) if product.unit_amount is not None else None
            ),
            unit=payload.unit if payload.unit is not None else product.unit,
            pack_count=payload.pack_count if payload.pack_count is not None else product.pack_count,
            volume_ml=payload.volume_ml if payload.volume_ml is not None else product.volume_ml,
        )
        product.option_label = units.option_label
        product.volume_ml = units.volume_ml
        product.unit_amount = units.unit_amount
        product.unit = units.unit
        product.pack_count = units.pack_count


def update_seller_product(
    db: Session, seller: Seller, product_id: UUID, payload: SellerProductUpdateRequest
) -> Product:
    product = get_seller_product(db, seller, product_id)
    _apply_seller_product_update(product, payload)
    db.flush()
    return product


def bulk_update_seller_products(
    db: Session, seller: Seller, payload: SellerProductBulkRequest
) -> tuple[list[Product], list[SellerProductBulkFailure]]:
    if payload.price_credits is None and payload.stock is None and payload.status is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="가격, 재고, 숨김 중 하나를 지정하세요.",
        )
    ids = list(dict.fromkeys(payload.ids))
    products = db.scalars(
        select(Product)
        .where(Product.seller_id == seller.id, Product.id.in_(ids))
        .options(joinedload(Product.seller))
    ).unique().all()
    by_id = {product.id: product for product in products}
    patch = SellerProductUpdateRequest(
        price_credits=payload.price_credits,
        stock=payload.stock,
        status=payload.status,
    )
    updated: list[Product] = []
    failed: list[SellerProductBulkFailure] = []
    for product_id in ids:
        product = by_id.get(product_id)
        if product is None:
            failed.append(
                SellerProductBulkFailure(id=str(product_id), detail="상품을 찾을 수 없습니다.")
            )
            continue
        try:
            _apply_seller_product_update(product, patch)
        except HTTPException as exc:
            detail = exc.detail if isinstance(exc.detail, str) else "적용할 수 없습니다."
            failed.append(SellerProductBulkFailure(id=str(product_id), detail=detail))
            continue
        updated.append(product)
    db.flush()
    return updated, failed


def delete_seller_product(db: Session, seller: Seller, product_id: UUID) -> None:
    product = get_seller_product(db, seller, product_id)
    db.execute(delete(CartItem).where(CartItem.product_id == product.id))
    db.execute(
        update(CatalogIntakeDraft)
        .where(CatalogIntakeDraft.product_id == product.id)
        .values(product_id=None)
    )
    db.delete(product)
    db.flush()


def product_to_response(product: Product) -> ProductResponse:
    return _product_response(product)
