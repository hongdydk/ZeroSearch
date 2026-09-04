"""Seed admin user, platform seller, catalog products, offers, and membership plans.

Run: `cd apps/api && python -m alembic upgrade head && python seed.py`

Optional DummyJSON demo catalog (after seed): ``python -m scripts.import_dummyjson_catalog``
"""

import argparse

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import SessionLocal
from app.deps import hash_password
from app.models import CartItem, CatalogProduct, MembershipPlan, Product, Seller, User
from app.services.sellers import ensure_platform_seller

# Optional local demo — not auto-seeded (images are /images/* paths; use import_dummyjson or add CDN URLs).
BEVERAGE_CATALOGS = [
    {
        "title": "백산수",
        "category": "생수",
        "description": "백산수 생수 — 용량·판매자별 오퍼 비교",
        "image_url": "/images/baisansu.png",
        "search_keywords": ["물", "생수", "백산"],
        "price_unit": "ml",
    },
    {
        "title": "평창수",
        "category": "생수",
        "description": "평창수 생수",
        "image_url": "/images/pyeongchang.png",
        "search_keywords": ["물", "생수", "평창"],
        "price_unit": "ml",
    },
    {
        "title": "제주삼다수",
        "category": "생수",
        "description": "제주삼다수 생수",
        "image_url": "/images/samdasu.png",
        "search_keywords": ["물", "생수", "제주", "삼다수"],
        "price_unit": "ml",
    },
]

BEVERAGE_OFFERS = [
    # 백산수
    {"catalog_title": "백산수", "seller": "platform", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": None, "price_credits": 12000, "stock": 100},
    {"catalog_title": "백산수", "seller": "platform", "option_label": "2L × 6", "volume_ml": 12000, "flavor": None, "price_credits": 9800, "stock": 80},
    {"catalog_title": "백산수", "seller": "merchant", "option_label": "500ml × 24", "volume_ml": 12000, "flavor": None, "price_credits": 11500, "stock": 50},
    {"catalog_title": "백산수", "seller": "merchant", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": "레몬", "price_credits": 12500, "stock": 40},
    {"catalog_title": "백산수", "seller": "merchant", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": "자몽", "price_credits": 12800, "stock": 35},
    {"catalog_title": "백산수", "seller": "merchant", "option_label": "2L × 6", "volume_ml": 12000, "flavor": None, "price_credits": 10200, "stock": 60},
    {"catalog_title": "백산수", "seller": "merchant", "option_label": "500ml × 40", "volume_ml": 20000, "flavor": None, "price_credits": 22000, "stock": 30},
    # 평창수
    {"catalog_title": "평창수", "seller": "platform", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": None, "price_credits": 11800, "stock": 90},
    {"catalog_title": "평창수", "seller": "merchant", "option_label": "2L × 6", "volume_ml": 12000, "flavor": None, "price_credits": 10500, "stock": 45},
    {"catalog_title": "평창수", "seller": "merchant", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": "레몬", "price_credits": 12200, "stock": 25},
    {"catalog_title": "평창수", "seller": "merchant", "option_label": "500ml × 24", "volume_ml": 12000, "flavor": None, "price_credits": 11200, "stock": 40},
    {"catalog_title": "평창수", "seller": "merchant", "option_label": "2L × 12", "volume_ml": 24000, "flavor": None, "price_credits": 19800, "stock": 20},
    # 제주삼다수
    {"catalog_title": "제주삼다수", "seller": "platform", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": None, "price_credits": 13000, "stock": 70},
    {"catalog_title": "제주삼다수", "seller": "merchant", "option_label": "2L × 6", "volume_ml": 12000, "flavor": None, "price_credits": 11000, "stock": 55},
    {"catalog_title": "제주삼다수", "seller": "merchant", "option_label": "500ml × 20", "volume_ml": 10000, "flavor": "자몽", "price_credits": 13500, "stock": 30},
    {"catalog_title": "제주삼다수", "seller": "merchant", "option_label": "500ml × 40", "volume_ml": 20000, "flavor": None, "price_credits": 24000, "stock": 15},
]

MEMBERSHIP_PLANS = [
    {"slug": "free", "name": "Free", "price_credits": 0, "interval": "month"},
    {"slug": "basic", "name": "Basic", "price_credits": 30, "interval": "month"},
    {"slug": "pro", "name": "Pro", "price_credits": 80, "interval": "month"},
]

MERCHANT_SHOP = {"shop_name": "청정마트", "slug": "clean-mart"}
MERCHANT_SEED_EMAIL = "merchant-seed@local.dev"
MERCHANT_SEED_PASSWORD = "merchant-seed-dev"


def ensure_admin_user(db: Session) -> User | None:
    settings = get_settings()
    if not settings.admin_email or not settings.admin_password:
        return None

    user = db.scalar(select(User).where(User.email == settings.admin_email))
    if user is None:
        user = User(
            email=settings.admin_email,
            password_hash=hash_password(settings.admin_password),
            display_name="Admin",
            is_admin=True,
        )
        db.add(user)
    elif not user.is_admin:
        user.is_admin = True
    db.flush()
    return user


def ensure_merchant_user(db: Session) -> User:
    user = db.scalar(select(User).where(User.email == MERCHANT_SEED_EMAIL))
    if user is None:
        user = User(
            email=MERCHANT_SEED_EMAIL,
            password_hash=hash_password(MERCHANT_SEED_PASSWORD),
            display_name="청정마트",
            is_admin=False,
        )
        db.add(user)
        db.flush()
    return user


def ensure_merchant_seller(db: Session) -> Seller:
    existing = db.scalar(select(Seller).where(Seller.slug == MERCHANT_SHOP["slug"]))
    if existing is not None:
        if existing.status != "active":
            existing.status = "active"
        db.flush()
        return existing

    merchant_user = ensure_merchant_user(db)
    seller = Seller(
        user_id=merchant_user.id,
        shop_name=MERCHANT_SHOP["shop_name"],
        slug=MERCHANT_SHOP["slug"],
        status="active",
        seller_type="merchant",
    )
    db.add(seller)
    db.flush()
    return seller


def _ensure_catalog(db: Session, data: dict) -> CatalogProduct:
    catalog = db.scalar(select(CatalogProduct).where(CatalogProduct.title == data["title"]))
    if catalog is not None:
        return catalog

    catalog = CatalogProduct(
        title=data["title"],
        category=data["category"],
        description=data.get("description"),
        image_url=data.get("image_url"),
        search_keywords=data.get("search_keywords"),
        price_unit=data.get("price_unit", "each"),
    )
    db.add(catalog)
    db.flush()
    return catalog


def seed_beverage_demo(db: Session) -> None:
    """Seed 생수 데모 (수동 실행용). image_url은 /images/* — 웹 배포 전 CDN URL로 바꿀 것."""
    admin_user = db.scalar(select(User).where(User.is_admin.is_(True)))
    if admin_user is None:
        admin_user = ensure_admin_user(db)
    if admin_user is None:
        return

    platform_seller = ensure_platform_seller(db, admin_user)
    merchant_seller = ensure_merchant_seller(db)

    for data in BEVERAGE_CATALOGS:
        _ensure_catalog(db, data)

    db.flush()

    catalogs_by_title = {c.title: c for c in db.scalars(select(CatalogProduct)).all()}
    sellers = {"platform": platform_seller, "merchant": merchant_seller}

    for offer in BEVERAGE_OFFERS:
        catalog = catalogs_by_title.get(offer["catalog_title"])
        if catalog is None:
            continue
        seller = sellers[offer["seller"]]
        db.add(
            Product(
                seller_id=seller.id,
                catalog_product_id=catalog.id,
                title=catalog.title,
                description=catalog.description,
                price_credits=offer["price_credits"],
                stock=offer["stock"],
                category=catalog.category,
                image_url=catalog.image_url,
                status="published",
                option_label=offer["option_label"],
                volume_ml=offer["volume_ml"],
                flavor=offer["flavor"],
            )
        )

    db.flush()


def ensure_catalog_seed(db: Session) -> None:
    admin_user = db.scalar(select(User).where(User.is_admin.is_(True)))
    if admin_user is None:
        admin_user = ensure_admin_user(db)
    if admin_user is None:
        return

    platform_seller = ensure_platform_seller(db, admin_user)
    merchant_seller = ensure_merchant_seller(db)

    products_without_seller = db.scalars(select(Product).where(Product.seller_id.is_(None))).all()
    for product in products_without_seller:
        product.seller_id = platform_seller.id
        if not product.status:
            product.status = "published"

    plan_count = db.scalar(select(func.count()).select_from(MembershipPlan)) or 0
    if plan_count == 0:
        for data in MEMBERSHIP_PLANS:
            db.add(MembershipPlan(**data))

    db.flush()


def seed() -> None:
    db = SessionLocal()
    try:
        admin_user = ensure_admin_user(db)
        ensure_catalog_seed(db)
        db.commit()
        if admin_user:
            print(f"Admin user ready - {admin_user.email}")
        else:
            print("Seed skipped - ADMIN_EMAIL / ADMIN_PASSWORD not set.")
        product_count = db.scalar(select(func.count()).select_from(Product)) or 0
        catalog_count = db.scalar(select(func.count()).select_from(CatalogProduct)) or 0
        plan_count = db.scalar(select(func.count()).select_from(MembershipPlan)) or 0
        seller_count = db.scalar(select(func.count()).select_from(Seller)) or 0
        print(
            f"Catalogs: {catalog_count}, Products: {product_count}, "
            f"Sellers: {seller_count}, Membership plans: {plan_count}"
        )
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed mall admin user and catalog.")
    parser.parse_args()
    seed()
