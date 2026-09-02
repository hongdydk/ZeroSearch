from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from app.models import Order, OrderItem, Seller
from app.schemas.seller import SellerOrderItemResponse, SellerOrderItemStatusUpdate

_FULFILLMENT_TRANSITIONS: dict[str, set[str]] = {
    "paid": {"preparing"},
    "preparing": {"shipped"},
    "shipped": {"delivered"},
    "delivered": set(),
}


def _apply_fulfillment_transition(item: OrderItem, next_status: str) -> None:
    if next_status not in _FULFILLMENT_TRANSITIONS.get(item.fulfillment_status, set()):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{item.fulfillment_status}에서 {next_status}(으)로 변경할 수 없습니다.",
        )
    item.fulfillment_status = next_status


def _seller_order_item_response(item: OrderItem) -> SellerOrderItemResponse:
    return SellerOrderItemResponse(
        id=str(item.id),
        order_id=str(item.order_id),
        product_id=str(item.product_id),
        product_title=item.product_title,
        qty=item.qty,
        unit_price_credits=item.unit_price_credits,
        line_total_credits=item.unit_price_credits * item.qty,
        fulfillment_status=item.fulfillment_status,  # type: ignore[arg-type]
        created_at=item.order.created_at if item.order else None,
    )


def list_seller_order_items(
    db: Session, seller: Seller, *, offset: int = 0, limit: int = 50
) -> tuple[list[OrderItem], int]:
    base = select(OrderItem).where(OrderItem.seller_id == seller.id)
    total = db.scalar(select(func.count()).select_from(base.subquery())) or 0
    items = db.scalars(
        select(OrderItem)
        .where(OrderItem.seller_id == seller.id)
        .options(joinedload(OrderItem.order))
        .join(Order, OrderItem.order_id == Order.id)
        .order_by(Order.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).all()
    return list(items), total


def list_admin_order_items(
    db: Session, *, offset: int = 0, limit: int = 50
) -> tuple[list[OrderItem], int]:
    total = db.scalar(select(func.count()).select_from(OrderItem)) or 0
    items = db.scalars(
        select(OrderItem)
        .options(joinedload(OrderItem.order), joinedload(OrderItem.seller))
        .join(Order, OrderItem.order_id == Order.id)
        .order_by(Order.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).all()
    return list(items), total


def update_seller_order_item_status(
    db: Session, seller: Seller, item_id: UUID, payload: SellerOrderItemStatusUpdate
) -> OrderItem:
    item = db.scalar(
        select(OrderItem)
        .where(OrderItem.id == item_id, OrderItem.seller_id == seller.id)
        .options(joinedload(OrderItem.order))
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="주문 항목을 찾을 수 없습니다.")

    _apply_fulfillment_transition(item, payload.fulfillment_status)
    db.flush()
    return item


def update_admin_order_item_status(
    db: Session, item_id: UUID, payload: SellerOrderItemStatusUpdate
) -> OrderItem:
    item = db.scalar(
        select(OrderItem)
        .where(OrderItem.id == item_id)
        .options(joinedload(OrderItem.order), joinedload(OrderItem.seller))
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="주문 항목을 찾을 수 없습니다.")

    _apply_fulfillment_transition(item, payload.fulfillment_status)
    db.flush()
    return item
