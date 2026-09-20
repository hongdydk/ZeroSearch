import re
import uuid
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.models import Seller, SellerModerationEvent, User
from app.schemas.admin import AdminSellerItem, SellerModerationEventItem

PLATFORM_SHOP_NAME = "Shopping Mall 공식"
PLATFORM_SLUG = "official"

ModerationAction = str


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


def _find_official_seller(db: Session, admin_user: User) -> Seller | None:
    """같은 user_id 행을 최우선으로 재사용한다. 없으면 slug=official, 그다음 platform 타입."""
    mine = db.scalar(select(Seller).where(Seller.user_id == admin_user.id))
    if mine is not None:
        return mine
    by_slug = db.scalar(select(Seller).where(Seller.slug == PLATFORM_SLUG))
    if by_slug is not None:
        return by_slug
    return db.scalar(select(Seller).where(Seller.seller_type == "platform").order_by(Seller.id))


def _adopt_platform_seller(db: Session, seller: Seller, admin_user: User) -> Seller:
    seller.seller_type = "platform"
    seller.status = "active"
    seller.shop_name = PLATFORM_SHOP_NAME
    if seller.slug != PLATFORM_SLUG:
        slug_taken = db.scalar(
            select(Seller.id).where(Seller.slug == PLATFORM_SLUG, Seller.id != seller.id)
        )
        if slug_taken is None:
            seller.slug = PLATFORM_SLUG
    if seller.user_id != admin_user.id:
        user_taken = db.scalar(
            select(Seller.id).where(Seller.user_id == admin_user.id, Seller.id != seller.id)
        )
        if user_taken is None:
            seller.user_id = admin_user.id
    db.flush()
    return seller


def ensure_platform_seller(db: Session, admin_user: User) -> Seller:
    existing = _find_official_seller(db, admin_user)
    if existing is not None:
        return _adopt_platform_seller(db, existing, admin_user)

    try:
        with db.begin_nested():
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
    except IntegrityError:
        recovered = _find_official_seller(db, admin_user)
        if recovered is None:
            raise
        return _adopt_platform_seller(db, recovered, admin_user)


def apply_for_seller(db: Session, user: User, shop_name: str) -> Seller:
    existing = get_seller_for_user(db, user)
    if existing is not None:
        if existing.status == "suspended":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="정지된 판매자 계정입니다.")
        if existing.status == "removed":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="해제된 판매자 계정입니다.")
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
    if seller.status in {"suspended", "removed"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="정지·해제된 판매자는 입점 승인으로 되돌릴 수 없습니다.",
        )
    seller.status = "active"
    db.flush()
    return seller


def _require_reason(reason: str) -> str:
    text = (reason or "").strip()
    if not text:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="사유를 입력하세요.")
    if len(text) > 1000:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="사유가 너무 깁니다.")
    return text


def _get_merchant(db: Session, seller_id: UUID) -> Seller:
    seller = db.get(Seller, seller_id)
    if seller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="판매자를 찾을 수 없습니다.")
    if seller.seller_type == "platform":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="공식 스토어는 제재할 수 없습니다.")
    return seller


def _record_moderation(
    db: Session,
    seller: Seller,
    admin: User,
    action: ModerationAction,
    reason: str,
) -> SellerModerationEvent:
    event = SellerModerationEvent(
        seller_id=seller.id,
        admin_user_id=admin.id,
        action=action,
        reason=reason,
    )
    db.add(event)
    db.flush()
    return event


def warn_seller(db: Session, seller_id: UUID, admin: User, reason: str) -> Seller:
    seller = _get_merchant(db, seller_id)
    if seller.status == "removed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 해제한 판매자입니다.")
    _record_moderation(db, seller, admin, "warn", _require_reason(reason))
    return seller


def suspend_seller(db: Session, seller_id: UUID, admin: User | None = None, reason: str | None = None) -> Seller:
    """Stop selling until unsuspended. Reason is required when an admin is provided."""
    seller = _get_merchant(db, seller_id)
    if seller.status == "removed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 해제한 판매자입니다.")
    if seller.status == "suspended":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 정지된 판매자입니다.")
    if admin is not None:
        _record_moderation(db, seller, admin, "suspend", _require_reason(reason or ""))
    elif reason:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="사유를 입력하세요.")
    seller.status = "suspended"
    db.flush()
    return seller


def unsuspend_seller(db: Session, seller_id: UUID, admin: User, reason: str) -> Seller:
    seller = _get_merchant(db, seller_id)
    if seller.status != "suspended":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="정지 상태가 아닙니다.")
    _record_moderation(db, seller, admin, "unsuspend", _require_reason(reason))
    seller.status = "active"
    db.flush()
    return seller


def remove_seller(db: Session, seller_id: UUID, admin: User, reason: str) -> Seller:
    seller = _get_merchant(db, seller_id)
    if seller.status == "removed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 해제한 판매자입니다.")
    _record_moderation(db, seller, admin, "remove", _require_reason(reason))
    seller.status = "removed"
    db.flush()
    return seller


def restore_seller(db: Session, seller_id: UUID, admin: User, reason: str) -> Seller:
    seller = _get_merchant(db, seller_id)
    if seller.status != "removed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="해제 상태가 아닙니다.")
    _record_moderation(db, seller, admin, "restore", _require_reason(reason))
    seller.status = "active"
    db.flush()
    return seller


def list_moderation_events(db: Session, seller_id: UUID) -> list[SellerModerationEvent]:
    seller = db.get(Seller, seller_id)
    if seller is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="판매자를 찾을 수 없습니다.")
    return list(
        db.scalars(
            select(SellerModerationEvent)
            .where(SellerModerationEvent.seller_id == seller_id)
            .order_by(SellerModerationEvent.created_at.desc())
        ).all()
    )


def list_all_moderation_events(db: Session, limit: int = 100) -> list[SellerModerationEvent]:
    return list(
        db.scalars(
            select(SellerModerationEvent)
            .order_by(SellerModerationEvent.created_at.desc())
            .limit(limit)
        ).all()
    )


def moderation_event_item(
    event: SellerModerationEvent,
    admin_email: str | None = None,
    shop_name: str | None = None,
) -> SellerModerationEventItem:
    return SellerModerationEventItem(
        id=str(event.id),
        action=event.action,
        reason=event.reason,
        created_at=event.created_at,
        admin_email=admin_email,
        shop_name=shop_name,
    )


def _moderation_summaries(db: Session, seller_ids: list[UUID]) -> dict[UUID, tuple[int, str | None, str | None]]:
    if not seller_ids:
        return {}
    warning_rows = db.execute(
        select(SellerModerationEvent.seller_id, func.count())
        .where(SellerModerationEvent.seller_id.in_(seller_ids), SellerModerationEvent.action == "warn")
        .group_by(SellerModerationEvent.seller_id)
    ).all()
    warnings = {seller_id: int(count) for seller_id, count in warning_rows}
    events = db.scalars(
        select(SellerModerationEvent)
        .where(SellerModerationEvent.seller_id.in_(seller_ids))
        .order_by(SellerModerationEvent.created_at.desc())
    ).all()
    latest: dict[UUID, SellerModerationEvent] = {}
    for event in events:
        if event.seller_id not in latest:
            latest[event.seller_id] = event
    return {
        seller_id: (
            warnings.get(seller_id, 0),
            latest[seller_id].action if seller_id in latest else None,
            latest[seller_id].reason if seller_id in latest else None,
        )
        for seller_id in seller_ids
    }


def admin_seller_item(seller: Seller, user: User | None, summary: tuple[int, str | None, str | None] | None = None) -> AdminSellerItem:
    warning_count, last_action, last_reason = summary or (0, None, None)
    return AdminSellerItem(
        id=str(seller.id),
        user_id=str(seller.user_id),
        user_email=user.email if user else "",
        shop_name=seller.shop_name,
        slug=seller.slug,
        status=seller.status,  # type: ignore[arg-type]
        seller_type=seller.seller_type,  # type: ignore[arg-type]
        created_at=seller.created_at,
        warning_count=warning_count,
        last_moderation_action=last_action,
        last_moderation_reason=last_reason,
    )


def list_admin_sellers(db: Session, status_filter: str | None = None) -> list[tuple[Seller, User | None]]:
    query = select(Seller).options(joinedload(Seller.user))
    if status_filter:
        query = query.where(Seller.status == status_filter)
    sellers = db.scalars(query.order_by(Seller.created_at.desc())).unique().all()
    return [(seller, seller.user) for seller in sellers]
