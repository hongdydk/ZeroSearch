from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models import (
    CartItem,
    CreditTransaction,
    CreditWallet,
    Order,
    OrderItem,
    PaymentIntent,
    Product,
    Seller,
    ShippingAddress,
    Subscription,
    User,
)
from app.schemas.admin import AdminUserItem


def admin_user_item(user: User) -> AdminUserItem:
    seller = getattr(user, "seller", None)
    seller_status = getattr(seller, "status", None) if seller is not None else None
    if not isinstance(seller_status, str):
        seller_status = None
    return AdminUserItem(
        id=str(user.id),
        email=user.email,
        display_name=user.display_name,
        is_admin=user.is_admin,
        seller_status=seller_status,
        created_at=user.created_at,
    )


def user_search_filter(q: str | None):
    text = (q or "").strip()
    if not text:
        return None
    pattern = f"%{text}%"
    return or_(User.email.ilike(pattern), User.display_name.ilike(pattern))


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
        count_stmt = count_stmt.where(search)
        list_stmt = list_stmt.where(search)
    total = db.scalar(count_stmt) or 0
    users = db.scalars(list_stmt.order_by(User.created_at.desc()).offset(offset).limit(limit)).unique().all()
    return list(users), int(total)


def count_admins(db: Session) -> int:
    return int(db.scalar(select(func.count()).select_from(User).where(User.is_admin.is_(True))) or 0)


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
