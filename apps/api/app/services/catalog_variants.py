from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.models import CatalogProduct, CatalogVariant, Product
from app.schemas.catalog_variant import CatalogVariantCreateRequest, CatalogVariantItem
from app.services.offer_units import resolve_offer_units


def variant_to_item(variant: CatalogVariant) -> CatalogVariantItem:
    units = resolve_offer_units(
        unit_amount=float(variant.unit_amount), unit=variant.unit,
        pack_count=variant.pack_count,
    )
    return CatalogVariantItem(
        id=str(variant.id), name=variant.name,
        option_label=units.option_label or "",
        unit_amount=float(variant.unit_amount), unit=variant.unit,
        pack_count=variant.pack_count, image_url=variant.image_url,
    )


def find_variant(
    db: Session, *, catalog_id: UUID, name: str,
    unit_amount: float, unit: str, pack_count: int,
) -> CatalogVariant | None:
    return db.scalar(
        select(CatalogVariant).where(
            CatalogVariant.catalog_product_id == catalog_id,
            CatalogVariant.name == name.strip(),
            CatalogVariant.unit_amount == Decimal(str(unit_amount)),
            CatalogVariant.unit == unit,
            CatalogVariant.pack_count == pack_count,
        )
    )


def add_catalog_variant(
    db: Session, catalog: CatalogProduct, payload: CatalogVariantCreateRequest,
    *, allow_existing: bool = False,
) -> CatalogVariant:
    existing = find_variant(
        db, catalog_id=catalog.id, name=payload.name,
        unit_amount=payload.unit_amount, unit=payload.unit,
        pack_count=payload.pack_count,
    )
    if existing is not None:
        if allow_existing:
            return existing
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="같은 상품 옵션이 이미 있습니다.")
    variant = CatalogVariant(
        catalog_product_id=catalog.id, name=payload.name,
        unit_amount=payload.unit_amount, unit=payload.unit,
        pack_count=payload.pack_count,
        image_url=(payload.image_url or "").strip() or None,
    )
    db.add(variant)
    db.flush()
    label = variant_to_item(variant).option_label
    options = list(catalog.volume_options or [])
    if label not in options:
        catalog.volume_options = [*options, label]
    if variant.unit not in ("ml", "L"):
        catalog.price_unit = "credits"
    return variant


def require_catalog_variant(db: Session, catalog_id: UUID, variant_id: UUID) -> CatalogVariant:
    variant = db.get(CatalogVariant, variant_id)
    if variant is None or variant.catalog_product_id != catalog_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="이 카드의 상품 옵션을 찾을 수 없습니다.")
    return variant


def rehome_catalog_variants(db: Session, source_id: UUID, target_id: UUID) -> None:
    """Keep option identity and offer links when catalog cards are merged."""
    variants = list(db.scalars(select(CatalogVariant).where(CatalogVariant.catalog_product_id == source_id)).all())
    for variant in variants:
        match = find_variant(
            db, catalog_id=target_id, name=variant.name,
            unit_amount=float(variant.unit_amount), unit=variant.unit,
            pack_count=variant.pack_count,
        )
        if match:
            db.execute(update(Product).where(Product.variant_id == variant.id).values(variant_id=match.id))
            db.delete(variant)
        else:
            variant.catalog_product_id = target_id
        db.flush()
