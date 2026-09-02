import re
import uuid
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Seller, User

PLATFORM_SHOP_NAME = "Shopping Mall 공식"
PLATFORM_SLUG = "official"


def slugify(name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "shop"
    return base[:80]


def unique_slug(db: Session, base: str) -> str:
    slug = slugify(base)
    candidate = slug
    n = 1
    while db.scalar(select(Seller.id).where(Seller.slug == candidate)):
        candidate = f"{slug}-{n}"
        n += 1
    return candidate


def get_seller_for_user(db: Session, user: User) -> Seller | None:
    return db.scalar(select(Seller).where(Seller.user_id == user.id))


def ensure_platform_seller(db: Session, admin_user: User) -> Seller:
    existing = db.scalar(select(Seller).where(Seller.seller_type == "platform"))
    if existing is not None:
        if existing.user_id != admin_user.id:
            existing.user_id = admin_user.id
        if existing.status != "active":
            existing.status = "active"
        db.flush()
        return existing

    seller = Seller(
        id=uuid.uuid4(),
        user_id=admin_user.id,
        shop_name=PLATFORM_SHOP_NAME,
        slug=PLATFORM_SLUG,
        status="active",
        seller_type="platform",
    )
    db.add(seller)
    db.flush()
    return seller


def apply_for_seller(db: Session, user: User, shop_name: str) -> Seller:
    existing = get_seller_for_user(db, user)
    if existing is not None:
        if existing.status == "suspended":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="정지된 판매자 계정입니다.")
        if existing.status == "pending":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 입점 신청이 접수되었습니다.")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 판매자로 등록되어 있습니다.")

    seller = Seller(
        user_id=user.id,
        shop_name=shop_name.strip(),
        slug=unique_slug(db, shop_name),
        status="pending",
        seller_type="merchant",
    )
    db.add(seller)
    db.flush()
    return seller


def approve_seller(db: Session, seller_id: UUID) -> Seller:
    seller = db.get(Seller, seller_id)
    if seller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="판매자를 찾을 수 없습니다.")
    if seller.status == "active":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 승인된 판매자입니다.")
    seller.status = "active"
    db.flush()
    return seller


def suspend_seller(db: Session, seller_id: UUID) -> Seller:
    seller = db.get(Seller, seller_id)
    if seller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="판매자를 찾을 수 없습니다.")
    if seller.seller_type == "platform":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="공식 스토어는 정지할 수 없습니다.")
    seller.status = "suspended"
    db.flush()
    return seller
