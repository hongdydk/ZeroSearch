from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.models import CatalogIntakeDraft, CatalogProduct, Product, Seller, User
from app.schemas.catalog_intake import (
    AdminAttachDraftRequest,
    AdminPromoteDraftRequest,
    CatalogIntakeItem,
    SellerCardDraftCreateRequest,
)
from app.services.catalog_remerge import resolve_catalog_product


def _now() -> datetime:
    return datetime.now(UTC)


def card_draft_to_item(draft: CatalogIntakeDraft) -> CatalogIntakeItem:
    seller = draft.seller
    return CatalogIntakeItem(
        id=str(draft.id),
        kind="card",
        status=draft.status,  # type: ignore[arg-type]
        seller_id=str(draft.seller_id),
        shop_name=seller.shop_name if seller else "",
        catalog_product_id=str(draft.catalog_product_id) if draft.catalog_product_id else None,
        manufacturer=draft.manufacturer,
        title=draft.title,
        category=draft.category,
        image_url=draft.image_url,
        flavor=draft.flavor,
        option_label=draft.option_label,
        volume_ml=draft.volume_ml,
        description=draft.description,
        price_credits=draft.price_credits,
        stock=draft.stock,
        created_at=draft.created_at,
    )


def _card_item(draft: CatalogIntakeDraft) -> CatalogIntakeItem:
    return card_draft_to_item(draft)


def _offer_item(product: Product) -> CatalogIntakeItem:
    catalog = product.catalog_product
    seller = product.seller
    return CatalogIntakeItem(
        id=str(product.id),
        kind="offer",
        status="pending",
        seller_id=str(product.seller_id),
        shop_name=seller.shop_name if seller else "",
        catalog_product_id=str(product.catalog_product_id),
        manufacturer=(catalog.manufacturer if catalog else "") or "",
        title=product.title,
        category=product.category,
        image_url=product.image_url,
        flavor=product.flavor,
        option_label=product.option_label,
        volume_ml=product.volume_ml,
        description=product.description,
        price_credits=product.price_credits,
        stock=product.stock,
        created_at=product.created_at,
    )


def create_card_draft(
    db: Session, seller: Seller, payload: SellerCardDraftCreateRequest
) -> CatalogIntakeDraft:
    option_label = (payload.option_label or "").strip() or None
    if not option_label:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="용량·팩을 적어 주세요.")
    draft = CatalogIntakeDraft(
        seller_id=seller.id,
        status="pending",
        manufacturer=payload.manufacturer.strip(),
        title=payload.title.strip(),
        category=payload.category.strip(),
        image_url=(payload.image_url or "").strip() or None,
        flavor=(payload.flavor or "").strip() or None,
        option_label=option_label,
        volume_ml=payload.volume_ml,
        description=payload.description,
        price_credits=payload.price_credits,
        stock=payload.stock,
    )
    db.add(draft)
    db.flush()
    draft = db.scalar(
        select(CatalogIntakeDraft)
        .where(CatalogIntakeDraft.id == draft.id)
        .options(joinedload(CatalogIntakeDraft.seller))
    )
    assert draft is not None
    return draft


def list_seller_card_drafts(db: Session, seller: Seller) -> list[CatalogIntakeDraft]:
    return list(
        db.scalars(
            select(CatalogIntakeDraft)
            .where(CatalogIntakeDraft.seller_id == seller.id)
            .options(joinedload(CatalogIntakeDraft.seller))
            .order_by(CatalogIntakeDraft.created_at.desc())
        ).all()
    )


def list_admin_intake_queue(
    db: Session, *, offset: int = 0, limit: int = 50
) -> tuple[list[CatalogIntakeItem], int]:
    offer_drafts = list(
        db.scalars(
            select(Product)
            .where(Product.status == "draft")
            .options(joinedload(Product.seller), joinedload(Product.catalog_product))
        ).all()
    )
    card_drafts = list(
        db.scalars(
            select(CatalogIntakeDraft)
            .where(CatalogIntakeDraft.status == "pending")
            .options(joinedload(CatalogIntakeDraft.seller))
        ).all()
    )
    items = [_offer_item(p) for p in offer_drafts] + [_card_item(d) for d in card_drafts]
    items.sort(key=lambda item: item.created_at or datetime.min.replace(tzinfo=UTC), reverse=True)
    total = len(items)
    return items[offset : offset + limit], total


def _get_pending_card_draft(db: Session, draft_id: UUID) -> CatalogIntakeDraft:
    draft = db.scalar(
        select(CatalogIntakeDraft)
        .where(CatalogIntakeDraft.id == draft_id)
        .options(joinedload(CatalogIntakeDraft.seller))
    )
    if draft is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="카드 초안을 찾을 수 없습니다.")
    if draft.status != "pending":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 처리된 초안입니다.")
    return draft


def _get_offer_draft(db: Session, product_id: UUID) -> Product:
    product = db.scalar(
        select(Product)
        .where(Product.id == product_id)
        .options(joinedload(Product.seller), joinedload(Product.catalog_product))
    )
    if product is None or product.status == "archived":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="오퍼 초안을 찾을 수 없습니다.")
    if product.status != "draft":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="검수 대기 오퍼가 아닙니다.")
    return product


def _require_catalog(db: Session, catalog_id: UUID) -> CatalogProduct:
    catalog = resolve_catalog_product(db, catalog_id)
    if catalog is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="대표 상품을 찾을 수 없습니다.")
    return catalog


def _append_volume_option(catalog: CatalogProduct, option_label: str | None) -> None:
    label = (option_label or "").strip()
    if not label:
        return
    options = list(catalog.volume_options or [])
    if label not in options:
        options.append(label)
        catalog.volume_options = options


def _publish_offer(
    db: Session,
    *,
    seller_id: UUID,
    catalog: CatalogProduct,
    description: str | None,
    price_credits: int,
    stock: int,
    image_url: str | None,
    option_label: str | None,
    volume_ml: int | None,
    flavor: str | None,
) -> Product:
    _append_volume_option(catalog, option_label)
    product = Product(
        seller_id=seller_id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        description=description,
        price_credits=price_credits,
        stock=stock,
        category=catalog.category,
        image_url=image_url or catalog.image_url,
        status="published",
        option_label=option_label,
        volume_ml=volume_ml,
        flavor=flavor,
    )
    db.add(product)
    db.flush()
    return product


def attach_intake_draft(
    db: Session,
    draft_id: UUID,
    payload: AdminAttachDraftRequest,
    reviewer: User,
) -> CatalogIntakeItem:
    if payload.kind == "offer":
        product = _get_offer_draft(db, draft_id)
        catalog_id = UUID(payload.catalog_product_id) if payload.catalog_product_id else product.catalog_product_id
        catalog = _require_catalog(db, catalog_id)
        _append_volume_option(catalog, product.option_label)
        product.catalog_product_id = catalog.id
        product.title = catalog.title
        product.category = catalog.category
        if not product.image_url:
            product.image_url = catalog.image_url
        product.status = "published"
        db.flush()
        product = db.scalar(
            select(Product)
            .where(Product.id == product.id)
            .options(joinedload(Product.seller), joinedload(Product.catalog_product))
        )
        assert product is not None
        item = _offer_item(product)
        item.status = "attached"
        return item

    draft = _get_pending_card_draft(db, draft_id)
    if not payload.catalog_product_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="붙일 기존 카드를 고르세요.",
        )
    catalog = _require_catalog(db, UUID(payload.catalog_product_id))
    product = _publish_offer(
        db,
        seller_id=draft.seller_id,
        catalog=catalog,
        description=draft.description,
        price_credits=draft.price_credits,
        stock=draft.stock,
        image_url=draft.image_url,
        option_label=draft.option_label,
        volume_ml=draft.volume_ml,
        flavor=draft.flavor,
    )
    draft.status = "attached"
    draft.catalog_product_id = catalog.id
    draft.product_id = product.id
    draft.reviewed_by = reviewer.id
    draft.reviewed_at = _now()
    db.flush()
    return _card_item(draft)


def promote_card_draft(
    db: Session,
    draft_id: UUID,
    payload: AdminPromoteDraftRequest,
    reviewer: User,
) -> CatalogIntakeItem:
    draft = _get_pending_card_draft(db, draft_id)
    manufacturer = (payload.manufacturer or draft.manufacturer).strip()
    title = (payload.title or draft.title).strip()
    category = payload.category.strip()
    if not manufacturer or not title or not category:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="회사·품목명·종류를 확인하세요.",
        )
    existing = db.scalar(
        select(func.count())
        .select_from(CatalogProduct)
        .where(
            CatalogProduct.manufacturer == manufacturer,
            CatalogProduct.category == category,
            CatalogProduct.title == title,
        )
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="같은 회사·종류·품목 카드가 있습니다. 기존 카드에 붙이세요.",
        )
    volumes = [draft.option_label] if draft.option_label else []
    catalog = CatalogProduct(
        title=title,
        manufacturer=manufacturer,
        category=category,
        image_url=draft.image_url,
        description=draft.description,
        volume_options=volumes,
        reference_variants=[],
        price_unit="ml",
    )
    db.add(catalog)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="같은 회사·종류·품목 카드가 있습니다. 기존 카드에 붙이세요.",
        ) from exc
    product = _publish_offer(
        db,
        seller_id=draft.seller_id,
        catalog=catalog,
        description=draft.description,
        price_credits=draft.price_credits,
        stock=draft.stock,
        image_url=draft.image_url,
        option_label=draft.option_label,
        volume_ml=draft.volume_ml,
        flavor=draft.flavor,
    )
    draft.status = "promoted"
    draft.catalog_product_id = catalog.id
    draft.product_id = product.id
    draft.reviewed_by = reviewer.id
    draft.reviewed_at = _now()
    db.flush()
    return _card_item(draft)
