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
from app.services.catalog_l1 import apply_auto_l1_tags, backfill_l1_tags

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

# Guest L1 browse demo — enough coverage that 라면·생수·찌개·만두/냉동·과자·장류 feel populated.
GUEST_L1_DEMO_CATALOGS = [
    {
        "title": "신라면",
        "manufacturer": "농심",
        "category": "국물봉지라면",
        "category_major": "면류",
        "category_mid": "봉지면",
        "description": "농심 신라면",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "진라면 매운맛",
        "manufacturer": "오뚜기",
        "category": "국물봉지라면",
        "category_major": "면류",
        "category_mid": "봉지면",
        "description": "오뚜기 진라면",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "짜파게티",
        "manufacturer": "농심",
        "category": "비빔봉지라면",
        "category_major": "면류",
        "category_mid": "봉지면",
        "description": "농심 짜파게티",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "제주삼다수",
        "manufacturer": "제주특별자치도개발공사",
        "category": "일반생수",
        "category_major": "음료",
        "category_mid": "생수",
        "description": "제주 삼다수",
        "price_unit": "ml",
        "image_url": "https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "백산수",
        "manufacturer": "농심",
        "category": "일반생수",
        "category_major": "음료",
        "category_mid": "생수",
        "description": "농심 백산수",
        "price_unit": "ml",
        "image_url": "https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "된장찌개 레토르트",
        "manufacturer": "오뚜기",
        "category": "즉석국/찌개",
        "category_major": "상온HMR",
        "category_mid": "레토르트",
        "description": "오뚜기 된장찌개",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "김치찌개",
        "manufacturer": "비비고",
        "category": "즉석국/찌개",
        "category_major": "상온HMR",
        "category_mid": "레토르트",
        "description": "비비고 김치찌개",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "왕교자",
        "manufacturer": "비비고",
        "category": "만두",
        "category_major": "상온HMR",
        "category_mid": "레토르트",
        "storage": "냉동",
        "description": "비비고 왕교자",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "김치왕교자",
        "manufacturer": "비비고",
        "category": "만두",
        "storage": "냉동",
        "description": "비비고 김치왕교자",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "초콜릿칩 쿠키",
        "manufacturer": "허쉬",
        "category": "쿠키",
        "category_major": "과자",
        "category_mid": "스낵",
        "description": "허쉬 초콜릿칩 쿠키",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1599490659213-e2b9527bd087?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "스윙칩 볶음고추장맛",
        "manufacturer": "오리온",
        "category": "감자스낵",
        "category_major": "과자",
        "category_mid": "스낵",
        "description": "오리온 스윙칩",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1599490659213-e2b9527bd087?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "초고추장",
        "manufacturer": "청정원",
        "category": "고추장",
        "category_major": "소스",
        "category_mid": "장류",
        "description": "청정원 초고추장",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1472476443507-6e15bbba9d8d?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "순창 고추장",
        "manufacturer": "대상",
        "category": "고추장",
        "category_major": "소스",
        "category_mid": "장류",
        "description": "순창 고추장",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1472476443507-6e15bbba9d8d?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "스팸 클래식",
        "manufacturer": "CJ제일제당",
        "category": "햄캔",
        "category_major": "통조림/안주",
        "category_mid": "통조림",
        "description": "스팸 클래식",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1588166524941-3bf61a9c41db?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "햇반",
        "manufacturer": "CJ제일제당",
        "category": "즉석밥",
        "category_major": "상온HMR",
        "category_mid": "레토르트",
        "description": "햇반 즉석밥",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "3분 짜장",
        "manufacturer": "오뚜기",
        "category": "즉석카레짜장",
        "category_major": "상온HMR",
        "category_mid": "레토르트",
        "description": "오뚜기 3분 짜장",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1516684669134-de6f7c473a2a?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "서울우유",
        "manufacturer": "서울우유",
        "category": "일반우유",
        "category_major": "유제품",
        "category_mid": "우유",
        "description": "서울우유 1L",
        "price_unit": "ml",
        "image_url": "https://images.unsplash.com/photo-1563636619-e9143da7973b?auto=format&fit=crop&w=400&q=80",
    },
    {
        "title": "커피믹스",
        "manufacturer": "맥심",
        "category": "커피",
        "category_major": "커피차",
        "category_mid": "분말차",
        "description": "맥심 커피믹스",
        "price_unit": "each",
        "image_url": "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=400&q=80",
    },
]


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
    manufacturer = data.get("manufacturer") or ""
    catalog = db.scalar(
        select(CatalogProduct).where(
            CatalogProduct.manufacturer == manufacturer,
            CatalogProduct.category == data["category"],
            CatalogProduct.title == data["title"],
        )
    )
    if catalog is None:
        title_stmt = select(CatalogProduct).where(CatalogProduct.title == data["title"])
        if manufacturer:
            title_stmt = title_stmt.where(CatalogProduct.manufacturer == manufacturer)
        catalog = db.scalar(title_stmt)
    if catalog is None:
        catalog = CatalogProduct(
            title=data["title"],
            manufacturer=manufacturer,
            category=data["category"],
            category_major=data.get("category_major"),
            category_mid=data.get("category_mid"),
            description=data.get("description"),
            image_url=data.get("image_url"),
            search_keywords=data.get("search_keywords"),
            price_unit=data.get("price_unit", "each"),
            storage=data.get("storage"),
            l1_tags=[],
        )
        db.add(catalog)
        db.flush()
    else:
        if manufacturer and not catalog.manufacturer:
            catalog.manufacturer = manufacturer
        if data.get("category_major") and not catalog.category_major:
            catalog.category_major = data.get("category_major")
        if data.get("category_mid") and not catalog.category_mid:
            catalog.category_mid = data.get("category_mid")
        if data.get("storage") and not catalog.storage:
            catalog.storage = data.get("storage")
        if data.get("image_url") and not catalog.image_url:
            catalog.image_url = data.get("image_url")
    apply_auto_l1_tags(catalog, only_if_empty=True)
    return catalog


def _ensure_demo_offer(
    db: Session,
    catalog: CatalogProduct,
    seller: Seller,
    *,
    option_label: str,
    price_credits: int,
    volume_ml: int | None = None,
) -> None:
    existing = db.scalar(
        select(Product).where(
            Product.catalog_product_id == catalog.id,
            Product.seller_id == seller.id,
            Product.option_label == option_label,
        )
    )
    if existing is not None:
        return
    db.add(
        Product(
            seller_id=seller.id,
            catalog_product_id=catalog.id,
            title=catalog.title,
            description=catalog.description,
            price_credits=price_credits,
            stock=40,
            category=catalog.category,
            image_url=catalog.image_url,
            status="published",
            option_label=option_label,
            volume_ml=volume_ml,
        )
    )


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


def _ensure_guest_l1_demo(db: Session, platform_seller: Seller, merchant_seller: Seller) -> None:
    for data in GUEST_L1_DEMO_CATALOGS:
        catalog = _ensure_catalog(db, data)
        if catalog.price_unit == "ml":
            _ensure_demo_offer(
                db,
                catalog,
                platform_seller,
                option_label="2L × 6",
                price_credits=9800,
                volume_ml=12000,
            )
            _ensure_demo_offer(
                db,
                catalog,
                merchant_seller,
                option_label="500ml × 20",
                price_credits=11500,
                volume_ml=10000,
            )
        else:
            _ensure_demo_offer(
                db,
                catalog,
                platform_seller,
                option_label="1팩",
                price_credits=4200,
            )
            _ensure_demo_offer(
                db,
                catalog,
                merchant_seller,
                option_label="묶음",
                price_credits=3980,
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

    _ensure_guest_l1_demo(db, platform_seller, merchant_seller)
    backfill_l1_tags(db, only_if_empty=True)
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
