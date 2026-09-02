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
        return "Seed data ensured (admin, sellers, membership). Catalogs without display image removed."

    if mode == "truncate_except_users":
        truncate_data(db, keep_users=True)
        ensure_admin_user(db)
        purge_catalogs_without_display_image(db)
        ensure_catalog_seed(db)
        db.commit()
        return "Cleared mall data; kept users; re-seeded admin/sellers. Image-less catalogs removed."

    if mode == "truncate_all":
        truncate_data(db, keep_users=False)
        ensure_admin_user(db)
        purge_catalogs_without_display_image(db)
        ensure_catalog_seed(db)
        db.commit()
        return "Cleared all data; re-seeded admin/sellers. Image-less catalogs removed."

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

