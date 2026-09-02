"""Import catalog products and offers from DummyJSON.

Run after migration and base seed::

    cd apps/api
    alembic upgrade head
    python seed.py
    python -m scripts.import_dummyjson_catalog

Price rule: DummyJSON ``price`` is USD; we store ``round(price * 10)`` credits
(e.g. $9.99 → 100, $549 → 5490). Idempotent — skips catalogs whose title
already exists.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from typing import Any

import httpx
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import CatalogProduct, Product, Seller
from seed import ensure_admin_user, ensure_merchant_seller, ensure_platform_seller

DEFAULT_API_URL = "https://dummyjson.com/products"
DEFAULT_LIMIT = 30

# DummyJSON category slug → our seed-style category
CATEGORY_MAP: dict[str, str] = {
    "smartphones": "electronics",
    "laptops": "electronics",
    "tablets": "electronics",
    "mobile-accessories": "electronics",
    "mobile phones": "electronics",
    "vehicle": "electronics",
    "motorcycle": "electronics",
    "automotive": "electronics",
    "lighting": "electronics",
    "tops": "fashion",
    "womens-dresses": "fashion",
    "mens-shirts": "fashion",
    "mens-shoes": "fashion",
    "womens-shoes": "fashion",
    "mens-watches": "fashion",
    "womens-watches": "fashion",
    "fragrances": "accessories",
    "skincare": "accessories",
    "skin-care": "accessories",
    "sunglasses": "accessories",
    "womens-bags": "accessories",
    "womens-jewellery": "accessories",
    "home-decoration": "accessories",
    "furniture": "accessories",
    "kitchen-accessories": "accessories",
    "sports-accessories": "accessories",
    "groceries": "accessories",
}


def slugify_category(category: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", category.lower()).strip("-") or "general"


def map_dummyjson_category(category: str) -> str:
    normalized = category.strip().lower()
    if normalized in CATEGORY_MAP:
        return CATEGORY_MAP[normalized]
    slug = slugify_category(normalized)
    if slug in CATEGORY_MAP:
        return CATEGORY_MAP[slug]
    return slug


def price_to_credits(price: float) -> int:
    """USD list price → integer credits (USD × 10, rounded)."""
    return max(1, round(price * 10))


def title_to_search_keywords(title: str) -> list[str]:
    words = re.findall(r"[a-zA-Z0-9]+", title.lower())
    # drop very short tokens; keep up to 6 unique words
    seen: set[str] = set()
    keywords: list[str] = []
    for word in words:
        if len(word) < 3 or word in seen:
            continue
        seen.add(word)
        keywords.append(word)
        if len(keywords) >= 6:
            break
    return keywords


def merchant_price_variation(base_price: int, seed: str) -> int:
    """Apply deterministic ±5–15% for merchant duplicate offers."""
    digest = hashlib.sha256(seed.encode()).hexdigest()
    pct = 5 + (int(digest[:8], 16) % 11)  # 5..15
    direction = -1 if int(digest[8:16], 16) % 2 else 1
    adjusted = round(base_price * (1 + direction * pct / 100))
    return max(1, adjusted)


def should_add_merchant_offer(product_id: int) -> bool:
    """~30% of DummyJSON rows also get a merchant offer."""
    return product_id % 10 < 3


def map_dummyjson_product(item: dict[str, Any]) -> dict[str, Any]:
    """Map one DummyJSON product row to catalog + platform offer fields."""
    title = str(item["title"]).strip()
    category = map_dummyjson_category(str(item.get("category", "general")))
    description = item.get("description")
    image_url = item.get("thumbnail") or (item.get("images") or [None])[0]
    price_credits = price_to_credits(float(item["price"]))
    stock = max(1, int(item.get("stock", 10)))
    product_id = int(item.get("id", 0))

    return {
        "catalog": {
            "title": title,
            "category": category,
            "description": description,
            "image_url": image_url,
            "search_keywords": title_to_search_keywords(title) or None,
            "price_unit": "each",
        },
        "platform_offer": {
            "price_credits": price_credits,
            "stock": stock,
        },
        "product_id": product_id,
        "add_merchant": should_add_merchant_offer(product_id),
        "merchant_seed": f"{product_id}:{title}",
    }


def fetch_dummyjson_products(*, limit: int, api_url: str) -> list[dict[str, Any]]:
    params = {"limit": limit}
    with httpx.Client(timeout=30.0) as client:
        response = client.get(api_url, params=params)
        response.raise_for_status()
        payload = response.json()
    products = payload.get("products")
    if not isinstance(products, list):
        raise ValueError("Unexpected DummyJSON response: missing products list")
    return products


def _catalog_exists(db: Session, title: str) -> bool:
    return db.scalar(select(CatalogProduct.id).where(CatalogProduct.title == title)) is not None


def import_dummyjson_catalog(
    db: Session,
    *,
    products: list[dict[str, Any]],
    platform_seller: Seller,
    merchant_seller: Seller,
) -> dict[str, int]:
    stats = {
        "fetched": len(products),
        "catalogs_created": 0,
        "platform_offers_created": 0,
        "merchant_offers_created": 0,
        "skipped_existing": 0,
    }

    for item in products:
        mapped = map_dummyjson_product(item)
        catalog_data = mapped["catalog"]
        title = catalog_data["title"]

        if _catalog_exists(db, title):
            stats["skipped_existing"] += 1
            continue

        catalog = CatalogProduct(**catalog_data)
        db.add(catalog)
        db.flush()

        stats["catalogs_created"] += 1

        platform = mapped["platform_offer"]
        db.add(
            Product(
                seller_id=platform_seller.id,
                catalog_product_id=catalog.id,
                title=catalog.title,
                description=catalog.description,
                price_credits=platform["price_credits"],
                stock=platform["stock"],
                category=catalog.category,
                image_url=catalog.image_url,
                status="published",
            )
        )
        stats["platform_offers_created"] += 1

        if mapped["add_merchant"]:
            merchant_price = merchant_price_variation(
                platform["price_credits"], mapped["merchant_seed"]
            )
            merchant_stock = max(1, platform["stock"] // 2)
            db.add(
                Product(
                    seller_id=merchant_seller.id,
                    catalog_product_id=catalog.id,
                    title=catalog.title,
                    description=catalog.description,
                    price_credits=merchant_price,
                    stock=merchant_stock,
                    category=catalog.category,
                    image_url=catalog.image_url,
                    status="published",
                )
            )
            stats["merchant_offers_created"] += 1

    db.flush()
    return stats


def run_import(*, limit: int = DEFAULT_LIMIT, api_url: str = DEFAULT_API_URL) -> dict[str, int]:
    db = SessionLocal()
    try:
        admin_user = ensure_admin_user(db)
        if admin_user is None:
            raise RuntimeError("ADMIN_EMAIL / ADMIN_PASSWORD must be set (see apps/api/.env.example).")

        platform_seller = ensure_platform_seller(db, admin_user)
        merchant_seller = ensure_merchant_seller(db)

        products = fetch_dummyjson_products(limit=limit, api_url=api_url)
        stats = import_dummyjson_catalog(
            db,
            products=products,
            platform_seller=platform_seller,
            merchant_seller=merchant_seller,
        )
        db.commit()

        stats["total_catalogs"] = db.scalar(select(func.count()).select_from(CatalogProduct)) or 0
        stats["total_products"] = db.scalar(select(func.count()).select_from(Product)) or 0
        return stats
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Import DummyJSON products into catalog/offers.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="DummyJSON products limit")
    parser.add_argument("--api-url", default=DEFAULT_API_URL, help="DummyJSON products endpoint")
    args = parser.parse_args()

    stats = run_import(limit=args.limit, api_url=args.api_url)
    print(
        "DummyJSON import complete - "
        f"fetched={stats['fetched']}, "
        f"catalogs_created={stats['catalogs_created']}, "
        f"platform_offers={stats['platform_offers_created']}, "
        f"merchant_offers={stats['merchant_offers_created']}, "
        f"skipped_existing={stats['skipped_existing']}, "
        f"total_catalogs={stats['total_catalogs']}, "
        f"total_products={stats['total_products']}"
    )


if __name__ == "__main__":
    main()
