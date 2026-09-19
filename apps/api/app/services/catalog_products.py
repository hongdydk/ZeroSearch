from dataclasses import dataclass
from datetime import datetime
from statistics import median
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import Text, cast, exists, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models import CatalogProduct, Product, Seller
from app.schemas.catalog_product import (
    CatalogOfferBrowseItem,
    CatalogOfferItem,
    CatalogProductDetailResponse,
    CatalogProductListItem,
    CatalogReferenceVariant,
)
from app.schemas.seller import SellerSummary
from app.services.catalog_identity import card_identity_key, matches_brand_axis, matches_menu_axis
from app.services.catalog_l1 import l1_tag_filter, l2_tag_filter
from app.services.catalog_remerge import resolve_catalog_product

VOLUME_CHIP_MIN_ML = 2000


@dataclass(frozen=True)
class CatalogIdentityRow:
    id: UUID
    manufacturer: str
    title: str
    offer_count: int
    created_at: datetime | None
    has_image: bool = False


@dataclass
class CatalogListResult:
    items: list[CatalogProductListItem]
    total: int
    available_flavors: list[str]
    has_volume_min_2000: bool


@dataclass
class CatalogOfferListResult:
    items: list[CatalogOfferBrowseItem]
    total: int


@dataclass(frozen=True)
class CatalogIdentityGroup:
    survivor_id: UUID
    member_ids: tuple[UUID, ...]


def pick_identity_groups(rows: list[CatalogIdentityRow]) -> list[CatalogIdentityGroup]:
    """같은 회사+품목의 카드들을 한 그룹으로 묶고 대표 ID를 고른다."""
    best: dict[tuple[str, str], CatalogIdentityRow] = {}
    members: dict[tuple[str, str], list[UUID]] = {}
    order: list[tuple[str, str]] = []
    for row in rows:
        key = card_identity_key(row.manufacturer, row.title)
        bucket = members.get(key)
        if bucket is None:
            members[key] = [row.id]
            best[key] = row
            order.append(key)
            continue
        bucket.append(row.id)
        if _identity_row_beats(row, best[key]):
            best[key] = row
    return [
        CatalogIdentityGroup(survivor_id=best[key].id, member_ids=tuple(members[key]))
        for key in order
    ]


def pick_identity_survivor_ids(rows: list[CatalogIdentityRow]) -> list[UUID]:
    """같은 회사+품목은 오퍼가 있는 카드 1장만 남긴다."""
    return [group.survivor_id for group in pick_identity_groups(rows)]


def member_ids_for_survivors(
    groups: list[CatalogIdentityGroup],
    survivor_ids: list[UUID],
) -> list[UUID]:
    wanted = set(survivor_ids)
    ids: list[UUID] = []
    seen: set[UUID] = set()
    for group in groups:
        if group.survivor_id not in wanted:
            continue
        for member_id in group.member_ids:
            if member_id not in seen:
                seen.add(member_id)
                ids.append(member_id)
    return ids


def _identity_row_beats(row: CatalogIdentityRow, prev: CatalogIdentityRow) -> bool:
    return (
        row.offer_count,
        1 if row.has_image else 0,
        str(row.created_at or ""),
        str(row.id),
    ) > (
        prev.offer_count,
        1 if prev.has_image else 0,
        str(prev.created_at or ""),
        str(prev.id),
    )


def offer_filter_facets(flavors: list[str | None], volume_mls: list[int | None]) -> tuple[list[str], bool]:
    seen: set[str] = set()
    available: list[str] = []
    for flavor in flavors:
        name = (flavor or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        available.append(name)
    has_volume = any(volume is not None and volume >= VOLUME_CHIP_MIN_ML for volume in volume_mls)
    return available, has_volume


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
        return 0, None, None, "credits", "원"

    unit_prices = [
        offer.price_credits / offer.volume_ml
        for offer in offers
        if offer.volume_ml is not None and offer.volume_ml > 0
    ]
    if unit_prices:
        return count, _median(unit_prices), None, "ml", "L당"

    credit_prices = [float(offer.price_credits) for offer in offers]
    return count, None, int(_median(credit_prices)), "credits", "원"


def _catalog_search_filter(
    q: str | None,
    category: str | None,
    *,
    category_major: str | None = None,
    category_mid: str | None = None,
    l1_tag: str | None = None,
    l2_tag: str | None = None,
    storage: str | None = None,
    brand: str | None = None,
    menu: str | None = None,
    include_retired: bool = False,
):
    filters = []
    if not include_retired:
        filters.append(CatalogProduct.status == "active")
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
    if l1_tag:
        # 알 수 없는 l1Tag는 fail-closed (브랜드만 매칭해 전 카탈로그가 나오지 않게).
        filters.append(l1_tag_filter(l1_tag))
    if l2_tag:
        # 해당 L1에 없는 l2Tag·L1 없이 L2만 오면 fail-closed.
        filters.append(l2_tag_filter(l1_tag, l2_tag))
    if storage in {"상온", "냉장", "냉동"}:
        filters.append(CatalogProduct.storage == storage)
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
        l1_tags=list(catalog.l1_tags or []),
        l2_tags=list(catalog.l2_tags or []),
        storage=catalog.storage,
    )


def _offer_browse_item(offer: Product) -> CatalogOfferBrowseItem:
    catalog = offer.catalog_product
    seller = offer.seller
    return CatalogOfferBrowseItem(
        id=str(offer.id),
        catalog_product_id=str(offer.catalog_product_id),
        title=(catalog.title if catalog is not None else offer.title) or offer.title,
        manufacturer=(catalog.manufacturer if catalog is not None else "") or "",
        option_label=offer.option_label,
        flavor=offer.flavor,
        volume_ml=offer.volume_ml,
        price_credits=offer.price_credits,
        stock=offer.stock,
        image_url=offer.image_url or (catalog.image_url if catalog is not None else None),
        seller=SellerSummary(
            id=str(seller.id),
            shop_name=seller.shop_name,
            seller_type=seller.seller_type,  # type: ignore[arg-type]
        ),
    )


def list_catalog_offers(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    category_major: str | None = None,
    category_mid: str | None = None,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
    l1_tag: str | None = None,
    l2_tag: str | None = None,
    storage: str | None = None,
    brand: str | None = None,
    menu: str | None = None,
    offset: int = 0,
    limit: int = 50,
) -> CatalogOfferListResult:
    """공개 오퍼를 한 장씩. 회사+품목 collapse 없음. L1·L2는 fail-closed."""
    catalog_filters = _catalog_search_filter(
        q,
        category,
        category_major=category_major,
        category_mid=category_mid,
        l1_tag=l1_tag,
        l2_tag=l2_tag,
        storage=storage,
        brand=brand,
        menu=menu,
    )
    if brand or menu:
        scoped_ids = [
            row.id
            for row in db.execute(
                select(
                    CatalogProduct.id,
                    CatalogProduct.manufacturer,
                    CatalogProduct.title,
                ).where(*catalog_filters)
            ).all()
            if matches_brand_axis(row.manufacturer or "", brand or "")
            and matches_menu_axis(row.manufacturer or "", row.title, menu or "")
        ]
        if not scoped_ids:
            return CatalogOfferListResult(items=[], total=0)
        catalog_filters = [CatalogProduct.id.in_(scoped_ids)]
    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    base = (
        select(Product.id)
        .join(Seller, Product.seller_id == Seller.id)
        .join(CatalogProduct, Product.catalog_product_id == CatalogProduct.id)
        .where(*offer_filters, *catalog_filters)
    )
    total = db.scalar(select(func.count()).select_from(base.subquery())) or 0
    if total == 0:
        return CatalogOfferListResult(items=[], total=0)

    page_ids = list(
        db.scalars(
            select(Product.id)
            .join(Seller, Product.seller_id == Seller.id)
            .join(CatalogProduct, Product.catalog_product_id == CatalogProduct.id)
            .where(*offer_filters, *catalog_filters)
            .order_by(
                CatalogProduct.manufacturer,
                CatalogProduct.title,
                Seller.shop_name,
                Product.price_credits,
                Product.id,
            )
            .offset(offset)
            .limit(limit)
        ).all()
    )
    if not page_ids:
        return CatalogOfferListResult(items=[], total=int(total))

    offers = db.scalars(
        select(Product)
        .where(Product.id.in_(page_ids))
        .options(joinedload(Product.seller), joinedload(Product.catalog_product))
    ).unique().all()
    by_id = {offer.id: offer for offer in offers}
    items = [_offer_browse_item(by_id[oid]) for oid in page_ids if oid in by_id]
    return CatalogOfferListResult(items=items, total=int(total))


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
    l1_tag: str | None = None,
    l2_tag: str | None = None,
    storage: str | None = None,
    brand: str | None = None,
    menu: str | None = None,
    offset: int = 0,
    limit: int = 50,
    require_offers: bool = False,
) -> CatalogListResult:
    catalog_filters = _catalog_search_filter(
        q,
        category,
        category_major=category_major,
        category_mid=category_mid,
        l1_tag=l1_tag,
        l2_tag=l2_tag,
        storage=storage,
        brand=brand,
        menu=menu,
    )
    id_stmt = select(
        CatalogProduct.id,
        CatalogProduct.manufacturer,
        CatalogProduct.title,
        CatalogProduct.created_at,
        CatalogProduct.image_url,
    )
    if catalog_filters:
        id_stmt = id_stmt.where(*catalog_filters)
    if require_offers:
        has_offers = _has_public_offers(
            flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
        )
        id_stmt = id_stmt.where(has_offers)

    id_stmt = id_stmt.order_by(CatalogProduct.manufacturer, CatalogProduct.title)
    identity_rows = [
        row
        for row in db.execute(id_stmt).all()
        if matches_brand_axis(row.manufacturer or "", brand or "")
        and matches_menu_axis(row.manufacturer or "", row.title, menu or "")
    ]
    if not identity_rows:
        return CatalogListResult(items=[], total=0, available_flavors=[], has_volume_min_2000=False)

    candidate_ids = [row.id for row in identity_rows]
    offer_counts: dict[UUID, int] = {row.id: 0 for row in identity_rows}
    public_filters = _public_offer_filters()
    for catalog_id, count in db.execute(
        select(Product.catalog_product_id, func.count())
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id.in_(candidate_ids), *public_filters)
        .group_by(Product.catalog_product_id)
    ):
        offer_counts[catalog_id] = int(count)

    groups = pick_identity_groups(
        [
            CatalogIdentityRow(
                id=row.id,
                manufacturer=row.manufacturer or "",
                title=row.title,
                offer_count=offer_counts.get(row.id, 0),
                created_at=row.created_at,
                has_image=(row.image_url or "").startswith("http"),
            )
            for row in identity_rows
        ]
    )
    survivors = [group.survivor_id for group in groups]
    all_member_ids = member_ids_for_survivors(groups, survivors)
    total = len(survivors)
    page_ids = survivors[offset : offset + limit]
    if not page_ids:
        flavors, has_volume = _result_set_offer_facets(db, all_member_ids)
        return CatalogListResult(
            items=[],
            total=total,
            available_flavors=flavors,
            has_volume_min_2000=has_volume,
        )

    catalogs = db.scalars(
        select(CatalogProduct).where(CatalogProduct.id.in_(page_ids))
    ).all()
    by_id = {catalog.id: catalog for catalog in catalogs}
    ordered = [by_id[cid] for cid in page_ids if cid in by_id]

    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    page_member_ids = member_ids_for_survivors(groups, page_ids)
    offers = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id.in_(page_member_ids), *offer_filters)
        .options(joinedload(Product.seller))
    ).unique().all()
    survivor_for_member = {
        member_id: group.survivor_id
        for group in groups
        for member_id in group.member_ids
        if group.survivor_id in page_ids
    }
    by_catalog: dict[UUID, list[Product]] = {cid: [] for cid in page_ids}
    for offer in offers:
        survivor_id = survivor_for_member.get(offer.catalog_product_id)
        if survivor_id is not None:
            by_catalog[survivor_id].append(offer)

    items = [_list_item(catalog, by_catalog[catalog.id]) for catalog in ordered]
    flavors, has_volume = _result_set_offer_facets(db, all_member_ids)
    return CatalogListResult(
        items=items,
        total=total,
        available_flavors=flavors,
        has_volume_min_2000=has_volume,
    )


def _result_set_offer_facets(db: Session, catalog_ids: list[UUID]) -> tuple[list[str], bool]:
    if not catalog_ids:
        return [], False
    rows = db.execute(
        select(Product.flavor, Product.volume_ml)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id.in_(catalog_ids), *_public_offer_filters())
    ).all()
    return offer_filter_facets(
        [row.flavor for row in rows],
        [row.volume_ml for row in rows],
    )


def search_seller_catalog_products(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    offset: int = 0,
    limit: int = 30,
) -> tuple[list[CatalogProductListItem], int]:
    result = list_catalog_products(
        db,
        q=q,
        category=category,
        offset=offset,
        limit=limit,
        require_offers=False,
    )
    return result.items, result.total


def _active_identity_member_ids(db: Session, catalog: CatalogProduct) -> list[UUID]:
    key = card_identity_key(catalog.manufacturer or "", catalog.title)
    rows = db.execute(
        select(CatalogProduct.id, CatalogProduct.manufacturer, CatalogProduct.title).where(
            CatalogProduct.status == "active"
        )
    ).all()
    ids = [
        row.id
        for row in rows
        if card_identity_key(row.manufacturer or "", row.title) == key
    ]
    return ids or [catalog.id]


def get_catalog_product(
    db: Session,
    catalog_id: UUID,
    *,
    flavor: str | None = None,
    volume_ml_min: int | None = None,
    volume_ml_max: int | None = None,
) -> CatalogProductDetailResponse:
    catalog = resolve_catalog_product(db, catalog_id)
    if catalog is None or catalog.status != "active":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="대표 상품을 찾을 수 없습니다.")

    offer_filters = _public_offer_filters(
        flavor=flavor, volume_ml_min=volume_ml_min, volume_ml_max=volume_ml_max
    )
    sibling_ids = _active_identity_member_ids(db, catalog)
    offers = db.scalars(
        select(Product)
        .join(Seller, Product.seller_id == Seller.id)
        .where(Product.catalog_product_id.in_(sibling_ids), *offer_filters)
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

    reference_variants = [
        CatalogReferenceVariant.model_validate(raw)
        for raw in (catalog.reference_variants or [])
        if isinstance(raw, dict)
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
        reference_variants=reference_variants,
        created_at=catalog.created_at,
        l1_tags=list(catalog.l1_tags or []),
        l2_tags=list(catalog.l2_tags or []),
        storage=catalog.storage,
    )
