"""Admin CSV contract for demo storefront content and seller offers."""

import csv
import io
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import CatalogProduct, CatalogVariant, Product, Seller
from app.services.offer_units import resolve_offer_units


STOREFRONT_PRODUCT_CSV_HEADERS = [
    "스토어소개", "스토어로고URL", "스토어배너URL",
    "제조사", "카드명", "종류", "옵션명", "수량", "단위", "팩수",
    "가격(원)", "재고", "대표이미지URL", "상세설명", "상세이미지URL목록",
    "추천상품", "진열순서", "공개상태",
]


def _csv_rows(content: bytes) -> list[dict[str, str]]:
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV는 UTF-8 형식이어야 합니다.") from exc
    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSV 헤더가 없습니다.")
    missing = [name for name in STOREFRONT_PRODUCT_CSV_HEADERS if name not in reader.fieldnames]
    if missing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"CSV 열이 없습니다: {', '.join(missing)}")
    rows = []
    for number, raw in enumerate(reader, start=2):
        row = {name: (raw.get(name) or "").strip() for name in STOREFRONT_PRODUCT_CSV_HEADERS}
        if not any(row.values()):
            continue
        row["_line"] = str(number)
        rows.append(row)
    if not rows:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="데이터 행이 없습니다.")
    return rows


def _truth(value: str) -> bool:
    return value.lower() in {"1", "y", "yes", "true", "예"}


def _int(value: str, *, line: str, field: str, default: int = 0) -> int:
    if not value:
        return default
    try:
        parsed = int(value)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: {field}은 숫자여야 합니다.") from exc
    if parsed < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: {field}은 0 이상이어야 합니다.")
    return parsed


def _detail_images(value: str) -> list[str]:
    return [url.strip() for url in value.split("|") if url.strip()]


def import_storefront_product_csv(db: Session, seller: Seller, content: bytes) -> dict[str, int]:
    rows = _csv_rows(content)
    imported = 0
    for row in rows:
        line = row["_line"]
        if row["스토어소개"]:
            seller.store_description = row["스토어소개"]
        if row["스토어로고URL"]:
            seller.store_logo_url = row["스토어로고URL"]
        if row["스토어배너URL"]:
            seller.store_banner_url = row["스토어배너URL"]

        # A row with only storefront fields configures a site without an offer.
        if not row["카드명"] and not row["제조사"] and not row["종류"]:
            continue
        if not all((row["제조사"], row["카드명"], row["종류"], row["옵션명"], row["수량"], row["단위"], row["팩수"])):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: 상품은 제조사·카드명·종류·옵션명·수량·단위·팩수를 모두 입력하세요.")
        catalog = db.scalar(select(CatalogProduct).where(
            CatalogProduct.manufacturer == row["제조사"],
            CatalogProduct.title == row["카드명"],
            CatalogProduct.category == row["종류"],
            CatalogProduct.status == "active",
        ))
        if catalog is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: 연결할 활성 카탈로그 카드를 찾을 수 없습니다.")
        try:
            amount = float(row["수량"])
            packs = int(row["팩수"])
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: 수량과 팩수를 확인하세요.") from exc
        variant = db.scalar(select(CatalogVariant).where(
            CatalogVariant.catalog_product_id == catalog.id,
            CatalogVariant.name == row["옵션명"],
            CatalogVariant.unit_amount == amount,
            CatalogVariant.unit == row["단위"],
            CatalogVariant.pack_count == packs,
        ))
        if variant is None:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: 카탈로그의 옵션을 찾을 수 없습니다.")
        product = db.scalar(select(Product).where(
            Product.seller_id == seller.id,
            Product.catalog_product_id == catalog.id,
            Product.variant_id == variant.id,
        ))
        units = resolve_offer_units(option_label=None, unit_amount=float(variant.unit_amount), unit=variant.unit, pack_count=variant.pack_count, volume_ml=None)
        values = {
            "title": catalog.title,
            "description": row["상세설명"] or None,
            "price_credits": _int(row["가격(원)"], line=line, field="가격(원)"),
            "stock": _int(row["재고"], line=line, field="재고"),
            "category": catalog.category,
            "image_url": row["대표이미지URL"] or variant.image_url or catalog.image_url,
            "detail_image_urls": _detail_images(row["상세이미지URL목록"]),
            "status": row["공개상태"] or "published",
            "option_label": units.option_label,
            "volume_ml": units.volume_ml,
            "unit_amount": units.unit_amount,
            "unit": units.unit,
            "pack_count": units.pack_count,
            "storefront_featured": _truth(row["추천상품"]),
            "storefront_rank": _int(row["진열순서"], line=line, field="진열순서", default=1000),
        }
        if values["status"] not in {"draft", "published", "archived"}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"{line}행: 공개상태는 draft, published, archived 중 하나여야 합니다.")
        if product is None:
            product = Product(seller_id=seller.id, catalog_product_id=catalog.id, variant_id=variant.id, **values)
            db.add(product)
        else:
            for key, value in values.items():
                setattr(product, key, value)
        imported += 1
    db.flush()
    return {"source_rows": len(rows), "upserted": imported, "canonical_groups": imported, "category_remerged": 0}


def export_storefront_product_csv(db: Session, seller: Seller) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=STOREFRONT_PRODUCT_CSV_HEADERS)
    writer.writeheader()
    seller = db.scalar(select(Seller).where(Seller.id == seller.id).options(selectinload(Seller.products).selectinload(Product.catalog_product), selectinload(Seller.products).selectinload(Product.variant))) or seller
    base = {"스토어소개": seller.store_description or "", "스토어로고URL": seller.store_logo_url or "", "스토어배너URL": seller.store_banner_url or ""}
    if not seller.products:
        writer.writerow(base)
    else:
        for product in sorted(seller.products, key=lambda item: (item.storefront_rank or 0, item.title)):
            catalog, variant = product.catalog_product, product.variant
            writer.writerow({
                **base, "제조사": catalog.manufacturer if catalog else "", "카드명": catalog.title if catalog else product.title,
                "종류": catalog.category if catalog else product.category, "옵션명": variant.name if variant else "",
                "수량": format(Decimal(variant.unit_amount).normalize(), "f") if variant else "", "단위": variant.unit if variant else "", "팩수": variant.pack_count if variant else "",
                "가격(원)": product.price_credits, "재고": product.stock, "대표이미지URL": product.image_url or "",
                "상세설명": product.description or "", "상세이미지URL목록": "|".join(product.detail_image_urls or []),
                "추천상품": "Y" if product.storefront_featured else "", "진열순서": product.storefront_rank or 0, "공개상태": product.status,
            })
    return output.getvalue().encode("utf-8-sig")


def storefront_product_template_csv() -> bytes:
    output = io.StringIO(newline="")
    csv.DictWriter(output, fieldnames=STOREFRONT_PRODUCT_CSV_HEADERS).writeheader()
    return output.getvalue().encode("utf-8-sig")
