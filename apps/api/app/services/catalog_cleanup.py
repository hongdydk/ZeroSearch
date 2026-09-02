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
    """Remove catalogs whose image_url is missing or not loadable on deployed web."""
    removed = 0
    for catalog in db.scalars(select(CatalogProduct)).all():
        if catalog_image_is_displayable(catalog.image_url):
            continue
        delete_catalog_and_offers(db, catalog)
        removed += 1
    if removed:
        db.flush()
    return removed
