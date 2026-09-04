"""Catalog cleanup helpers — remove entries that cannot show an image on Flutter web."""

from __future__ import annotations

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.models import CartItem, CatalogProduct, Product


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
    db.delete(catalog)


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
