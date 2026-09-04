import logging

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.models import (
    CartItem,
    CatalogProduct,
    CreditTransaction,
    CreditWallet,
    MembershipPlan,
    Order,
    OrderItem,
    Product,
    Seller,
    Subscription,
    User,
)
from app.services.catalog_cleanup import purge_catalogs_without_display_image
from seed import ensure_admin_user, ensure_catalog_seed

logger = logging.getLogger(__name__)

RESET_CONFIRM = "RESET"


def truncate_data(db: Session, *, keep_users: bool) -> None:
    db.execute(delete(OrderItem))
    db.execute(delete(Order))
    db.execute(delete(CartItem))
    db.execute(delete(Subscription))
    db.execute(delete(Product))
    db.execute(delete(CatalogProduct))
    db.execute(delete(Seller))
    db.execute(delete(MembershipPlan))
    db.execute(delete(CreditTransaction))
    db.execute(delete(CreditWallet))
    if not keep_users:
        db.execute(delete(User))
    db.commit()


def run_db_reset(db: Session, mode: str) -> str:
    if mode == "seed":
        ensure_admin_user(db)
        purge_catalogs_without_display_image(db)
        ensure_catalog_seed(db)
        db.commit()
        return "관리자·가게·멤버십을 확인했습니다. 카탈로그는 그대로입니다."

    if mode == "truncate_except_users":
        truncate_data(db, keep_users=True)
        ensure_admin_user(db)
        purge_catalogs_without_display_image(db)
        ensure_catalog_seed(db)
        db.commit()
        return "주문·가게·카탈로그를 지웠습니다. 계정은 남겼습니다."

    if mode == "truncate_all":
        truncate_data(db, keep_users=False)
        ensure_admin_user(db)
        purge_catalogs_without_display_image(db)
        ensure_catalog_seed(db)
        db.commit()
        return "모든 데이터를 지운 뒤 관리자·가게를 다시 만들었습니다."

    raise ValueError(f"Unknown reset mode: {mode}")


def get_admin_stats(db: Session) -> dict[str, int]:
    user_count = db.scalar(select(func.count()).select_from(User)) or 0
    product_count = db.scalar(select(func.count()).select_from(Product)) or 0
    order_count = db.scalar(select(func.count()).select_from(Order)) or 0
    seller_count = db.scalar(select(func.count()).select_from(Seller)) or 0
    pending_seller_count = (
        db.scalar(select(func.count()).select_from(Seller).where(Seller.status == "pending")) or 0
    )
    return {
        "user_count": user_count,
        "product_count": product_count,
        "order_count": order_count,
        "seller_count": seller_count,
        "pending_seller_count": pending_seller_count,
    }

