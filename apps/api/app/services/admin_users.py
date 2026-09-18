from fastapi import HTTPException, status
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models import (
    CartItem,
    CatalogIntakeDraft,
    CreditTransaction,
    CreditWallet,
    Order,
    OrderItem,
    PaymentIntent,
    Product,
    Seller,
    SellerModerationEvent,
    ShippingAddress,
    Subscription,
    User,
)
from app.schemas.admin import AdminUserItem, AdminUserUpdate
from app.services.sellers import remove_seller, restore_seller, unique_slug

_ROLE_GRANT_REASON = "관리자가 판매자 역할을 부여함"
_ROLE_REVOKE_REASON = "관리자가 판매자 역할을 해제함"


def _clean_name(value: str | None) -> str | None:
    text = (value or "").strip()
    return text or None


def _as_bool(value: object, default: bool) -> bool:
    return value if isinstance(value, bool) else default


def _attached_seller(user: User) -> Seller | None:
    seller = getattr(user, "seller", None)
    if seller is None:
        return None
    if not isinstance(getattr(seller, "status", None), str):
        return None
    return seller


def _is_seller_role(seller: Seller | None) -> bool:
    if seller is None:
        return False
    return seller.status != "removed"


def admin_user_item(user: User) -> AdminUserItem:
    seller = _attached_seller(user)
    seller_status = seller.status if seller is not None else None
    seller_type = seller.seller_type if seller is not None and isinstance(seller.seller_type, str) else None
    shop_name = seller.shop_name if seller is not None and isinstance(seller.shop_name, str) else None
    return AdminUserItem(
        id=str(user.id),
        email=user.email,
        display_name=user.display_name,
        seller_name=shop_name,
        is_buyer=_as_bool(getattr(user, "is_buyer", True), True),
        is_seller=_is_seller_role(seller),
        is_admin=_as_bool(getattr(user, "is_admin", False), False),
        seller_status=seller_status,
        seller_type=seller_type,
        created_at=user.created_at,
    )


def user_search_filter(q: str | None):
    text = (q or "").strip()
    if not text:
        return None
    pattern = f"%{text}%"
    return or_(
        User.email.ilike(pattern),
        User.display_name.ilike(pattern),
        Seller.shop_name.ilike(pattern),
    )


def list_admin_users(
    db: Session,
    *,
    offset: int,
    limit: int,
    q: str | None,
) -> tuple[list[User], int]:
    search = user_search_filter(q)
    count_stmt = select(func.count()).select_from(User)
    list_stmt = select(User).options(joinedload(User.seller))
    if search is not None:
        count_stmt = count_stmt.outerjoin(Seller, Seller.user_id == User.id).where(search)
        list_stmt = list_stmt.outerjoin(Seller, Seller.user_id == User.id).where(search)
    total = db.scalar(count_stmt) or 0
    users = db.scalars(list_stmt.order_by(User.created_at.desc()).offset(offset).limit(limit)).unique().all()
    return list(users), int(total)


def count_admins(db: Session) -> int:
    return int(db.scalar(select(func.count()).select_from(User).where(User.is_admin.is_(True))) or 0)


def _fallback_shop_name(user: User, seller_name: str | None) -> str:
    return _clean_name(seller_name) or _clean_name(user.display_name) or user.email.split("@")[0]


def _grant_seller_role(db: Session, user: User, admin: User, seller_name: str | None) -> None:
    seller = _attached_seller(user)
    if seller is None:
        shop_name = _fallback_shop_name(user, seller_name)
        created = Seller(
            user_id=user.id,
            shop_name=shop_name,
            slug=unique_slug(db, shop_name),
            status="active",
            seller_type="merchant",
        )
        db.add(created)
        db.flush()
        user.seller = created
        return
    if seller.seller_type == "platform":
        return
    if seller.status == "pending":
        seller.status = "active"
        db.flush()
        return
    if seller.status == "removed":
        restore_seller(db, seller.id, admin, _ROLE_GRANT_REASON)
        return


def _revoke_seller_role(db: Session, user: User, admin: User) -> None:
    seller = _attached_seller(user)
    if seller is None or seller.status == "removed":
        return
    if seller.seller_type == "platform":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="공식 스토어의 판매자 역할은 해제할 수 없습니다.",
        )
    remove_seller(db, seller.id, admin, _ROLE_REVOKE_REASON)


def _apply_seller_name(user: User, seller_name: str | None) -> None:
    name = _clean_name(seller_name)
    if name is None:
        return
    seller = _attached_seller(user)
    if seller is None:
        return
    seller.shop_name = name


def update_admin_user(db: Session, user: User, admin: User, payload: AdminUserUpdate) -> User:
    fields = payload.model_fields_set

    if "display_name" in fields:
        user.display_name = _clean_name(payload.display_name)

    if payload.is_admin is False:
        if user.id == admin.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="자기 자신의 관리자 권한은 해제할 수 없습니다.",
            )
        if user.is_admin and count_admins(db) <= 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="마지막 관리자 권한은 해제할 수 없습니다.",
            )
    if payload.is_admin is not None:
        user.is_admin = payload.is_admin

    if payload.is_buyer is not None:
        user.is_buyer = payload.is_buyer

    if payload.is_seller is True:
        _grant_seller_role(db, user, admin, payload.seller_name)
    elif payload.is_seller is False:
        _revoke_seller_role(db, user, admin)

    if "seller_name" in fields:
        _apply_seller_name(user, payload.seller_name)

    db.flush()
    return user


def delete_user_account(db: Session, user: User) -> None:
    user_id = user.id
    seller = db.scalar(select(Seller).where(Seller.user_id == user_id))
    order_ids = list(db.scalars(select(Order.id).where(Order.user_id == user_id)).all())
    db.execute(delete(PaymentIntent).where(PaymentIntent.user_id == user_id))
    if order_ids:
        db.execute(delete(OrderItem).where(OrderItem.order_id.in_(order_ids)))
    db.execute(delete(Order).where(Order.user_id == user_id))
    db.execute(delete(CartItem).where(CartItem.user_id == user_id))
    if seller is not None:
        product_ids = list(db.scalars(select(Product.id).where(Product.seller_id == seller.id)).all())
        db.execute(delete(SellerModerationEvent).where(SellerModerationEvent.seller_id == seller.id))
        db.execute(delete(CatalogIntakeDraft).where(CatalogIntakeDraft.seller_id == seller.id))
        if product_ids:
            db.execute(delete(CartItem).where(CartItem.product_id.in_(product_ids)))
            db.execute(delete(OrderItem).where(OrderItem.product_id.in_(product_ids)))
        db.execute(delete(OrderItem).where(OrderItem.seller_id == seller.id))
        db.execute(delete(Product).where(Product.seller_id == seller.id))
        db.execute(delete(Seller).where(Seller.id == seller.id))
    db.execute(delete(Subscription).where(Subscription.user_id == user_id))
    db.execute(delete(ShippingAddress).where(ShippingAddress.user_id == user_id))
    wallet = db.scalar(select(CreditWallet).where(CreditWallet.user_id == user_id))
    if wallet is not None:
        db.execute(delete(CreditTransaction).where(CreditTransaction.wallet_id == wallet.id))
        db.execute(delete(CreditWallet).where(CreditWallet.id == wallet.id))
    db.delete(user)
