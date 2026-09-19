"""Catalog cleanup helpers — remove entries that cannot show an image on Flutter web."""

from __future__ import annotations

from sqlalchemy import and_, delete, or_, select, update
from sqlalchemy.orm import Session

from app.models import CartItem, CatalogIntakeDraft, CatalogProduct, CatalogVariant, OrderItem, Product

# PR #36 auto-seed identity only. Title-only or other manufacturers are left alone.
PR36_DEMO_CATALOG_KEYS: tuple[tuple[str, str], ...] = (
    ("제주특별자치도개발공사", "제주삼다수"),
    ("롯데칠성음료", "레쓰비"),
)


def catalog_image_is_displayable(image_url: str | None) -> bool:
    """True when the web client can load the image (absolute http(s) URL)."""
    url = (image_url or "").strip()
    if not url:
        return False
    if url.startswith("/"):
        return False
    return url.startswith("http://") or url.startswith("https://")


def delete_catalog_and_offers(db: Session, catalog: CatalogProduct) -> None:
    offer_ids = db.scalars(select(Product.id).where(Product.catalog_product_id == catalog.id)).all()
    if offer_ids:
        db.execute(delete(CartItem).where(CartItem.product_id.in_(offer_ids)))
        db.execute(delete(Product).where(Product.catalog_product_id == catalog.id))
    db.execute(delete(CatalogVariant).where(CatalogVariant.catalog_product_id == catalog.id))
    db.delete(catalog)


def list_pr36_demo_catalogs(db: Session) -> list[CatalogProduct]:
    """Catalog rows whose manufacturer+title match the PR #36 demo cards."""
    return list(
        db.scalars(
            select(CatalogProduct).where(
                or_(
                    *[
                        and_(
                            CatalogProduct.manufacturer == manufacturer,
                            CatalogProduct.title == title,
                        )
                        for manufacturer, title in PR36_DEMO_CATALOG_KEYS
                    ]
                )
            )
        ).all()
    )


def _detach_intake_drafts(db: Session, catalog: CatalogProduct, offer_ids: list) -> None:
    db.execute(
        update(CatalogIntakeDraft)
        .where(CatalogIntakeDraft.catalog_product_id == catalog.id)
        .values(catalog_product_id=None)
    )
    if offer_ids:
        db.execute(
            update(CatalogIntakeDraft)
            .where(CatalogIntakeDraft.product_id.in_(offer_ids))
            .values(product_id=None)
        )


def _catalog_offers_have_orders(db: Session, offer_ids: list) -> bool:
    if not offer_ids:
        return False
    return (
        db.scalar(select(OrderItem.id).where(OrderItem.product_id.in_(offer_ids)).limit(1))
        is not None
    )


def purge_pr36_demo_catalog_cards(db: Session) -> dict[str, int]:
    """One-shot: delete PR #36 demo cards by exact manufacturer+title.

    Does not touch other catalog rows. Skips a card when its offers appear on
    order lines so purchase history stays intact. Not called from API startup.
    """
    removed_catalogs = 0
    removed_offers = 0
    skipped_with_orders = 0
    for catalog in list_pr36_demo_catalogs(db):
        offer_ids = list(
            db.scalars(select(Product.id).where(Product.catalog_product_id == catalog.id)).all()
        )
        if _catalog_offers_have_orders(db, offer_ids):
            skipped_with_orders += 1
            continue
        _detach_intake_drafts(db, catalog, offer_ids)
        removed_offers += len(offer_ids)
        delete_catalog_and_offers(db, catalog)
        removed_catalogs += 1
    if removed_catalogs:
        db.flush()
    return {
        "removed_catalogs": removed_catalogs,
        "removed_offers": removed_offers,
        "skipped_with_orders": skipped_with_orders,
    }


def purge_catalogs_without_display_image(db: Session) -> int:
    """Remove catalogs with local `/images/...` paths that cannot load on web.

    Missing `image_url` is kept — 식약처 CSV 카드는 이미지가 없다.
    """
    catalogs = db.scalars(
        select(CatalogProduct).where(
            CatalogProduct.image_url.isnot(None),
            CatalogProduct.image_url.like("/%"),
        )
    ).all()
    removed = 0
    for catalog in catalogs:
        url = (catalog.image_url or "").strip()
        if catalog_image_is_displayable(url) or not url.startswith("/"):
            continue
        delete_catalog_and_offers(db, catalog)
        removed += 1
    if removed:
        db.flush()
    return removed
