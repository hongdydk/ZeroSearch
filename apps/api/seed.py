"""Seed admin user, platform seller, products, and membership plans for local dev.

Run: `cd apps/api && alembic upgrade head && python seed.py`
"""

import argparse

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import SessionLocal
from app.deps import hash_password
from app.models import MembershipPlan, Product, Seller, User
from app.services.sellers import ensure_platform_seller

PRODUCTS = [
    {
        "title": "무선 이어폰",
        "description": "노이즈 캔슬링 블루투스 이어폰",
        "price_credits": 45,
        "stock": 50,
        "category": "electronics",
        "image_url": "/images/earbuds.png",
    },
    {
        "title": "스마트 워치",
        "description": "건강 모니터링 스마트워치",
        "price_credits": 80,
        "stock": 30,
        "category": "electronics",
        "image_url": "/images/watch.png",
    },
    {
        "title": "면 티셔츠",
        "description": "편안한 기본 면 티셔츠",
        "price_credits": 15,
        "stock": 100,
        "category": "fashion",
        "image_url": "/images/tshirt.png",
    },
    {
        "title": "데님 자켓",
        "description": "클래식 데님 자켓",
        "price_credits": 35,
        "stock": 40,
        "category": "fashion",
        "image_url": "/images/jacket.png",
    },
    {
        "title": "에코백",
        "description": "친환경 캔버스 에코백",
        "price_credits": 10,
        "stock": 200,
        "category": "accessories",
        "image_url": "/images/ecobag.png",
    },
    {
        "title": "텀블러",
        "description": "보온·보냉 스테인리스 텀블러",
        "price_credits": 12,
        "stock": 80,
        "category": "accessories",
        "image_url": "/images/tumbler.png",
    },
    {
        "title": "노트북 파우치",
        "description": "15인치 노트북 슬림 파우치",
        "price_credits": 20,
        "stock": 60,
        "category": "accessories",
        "image_url": "/images/pouch.png",
    },
    {
        "title": "USB-C 허브",
        "description": "7-in-1 USB-C 멀티 허브",
        "price_credits": 25,
        "stock": 45,
        "category": "electronics",
        "image_url": "/images/hub.png",
    },
]

MEMBERSHIP_PLANS = [
    {"slug": "free", "name": "Free", "price_credits": 0, "interval": "month"},
    {"slug": "basic", "name": "Basic", "price_credits": 30, "interval": "month"},
    {"slug": "pro", "name": "Pro", "price_credits": 80, "interval": "month"},
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


def ensure_catalog_seed(db: Session) -> None:
    admin_user = db.scalar(select(User).where(User.is_admin.is_(True)))
    if admin_user is None:
        admin_user = ensure_admin_user(db)
    if admin_user is None:
        return

    platform_seller = ensure_platform_seller(db, admin_user)

    products_without_seller = db.scalars(select(Product).where(Product.seller_id.is_(None))).all()
    for product in products_without_seller:
        product.seller_id = platform_seller.id
        if not product.status:
            product.status = "published"

    product_count = db.scalar(select(func.count()).select_from(Product)) or 0
    if product_count == 0:
        for data in PRODUCTS:
            db.add(Product(**data, seller_id=platform_seller.id, status="published"))

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
        plan_count = db.scalar(select(func.count()).select_from(MembershipPlan)) or 0
        seller_count = db.scalar(select(func.count()).select_from(Seller)) or 0
        print(f"Products: {product_count}, Sellers: {seller_count}, Membership plans: {plan_count}")
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed mall admin user and catalog.")
    parser.parse_args()
    seed()
