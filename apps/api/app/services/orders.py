from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session, joinedload

from app.models import CartItem, Order, OrderItem, Product, User
from app.schemas.order import OrderItemResponse, OrderResponse
from app.services.credits import debit_credits


def _order_item_response(item: OrderItem) -> OrderItemResponse:
    seller = item.seller
    return OrderItemResponse(
        id=str(item.id),
        product_id=str(item.product_id),
        product_title=item.product_title,
        seller_id=str(item.seller_id),
        shop_name=seller.shop_name if seller else "",
        seller_type=seller.seller_type if seller else "merchant",  # type: ignore[arg-type]
        qty=item.qty,
        unit_price_credits=item.unit_price_credits,
        line_total_credits=item.unit_price_credits * item.qty,
        fulfillment_status=item.fulfillment_status,  # type: ignore[arg-type]
    )


def _order_response(order: Order) -> OrderResponse:
    items = [_order_item_response(item) for item in order.items]
    return OrderResponse(
        id=str(order.id),
        status=order.status,  # type: ignore[arg-type]
        total_credits=order.total_credits,
        items=items,
        created_at=order.created_at,
    )


def list_orders(db: Session, user: User, *, offset: int = 0, limit: int = 50) -> tuple[list[Order], int]:
    total = db.scalar(select(func.count()).select_from(Order).where(Order.user_id == user.id)) or 0
    orders = db.scalars(
        select(Order)
        .where(Order.user_id == user.id)
        .options(joinedload(Order.items).joinedload(OrderItem.seller))
        .order_by(Order.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).unique().all()
    return list(orders), total


def get_order(db: Session, user: User, order_id: UUID) -> Order:
    order = db.scalar(
        select(Order)
        .where(Order.id == order_id, Order.user_id == user.id)
        .options(joinedload(Order.items).joinedload(OrderItem.seller))
    )
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="주문을 찾을 수 없습니다.")
    return order


def _reserve_stock(db: Session, *, product_id: UUID, qty: int, title: str) -> None:
    """원자적으로 재고를 차감한다. 동시 주문에서도 stock >= qty인 행만 갱신된다."""
    reserved = db.execute(
        update(Product)
        .where(Product.id == product_id, Product.stock >= qty)
        .values(stock=Product.stock - qty)
        .returning(Product.id)
    ).first()
    if reserved is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"'{title}' 재고가 부족합니다.",
        )


def checkout(db: Session, user: User) -> OrderResponse:
    cart_items = list(
        db.scalars(
            select(CartItem)
            .where(CartItem.user_id == user.id)
            .options(joinedload(CartItem.product).joinedload(Product.seller))
        ).all()
    )

    if not cart_items:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="장바구니가 비어 있습니다.")

    for item in cart_items:
        product = item.product
        if product.status != "published":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"'{product.title}'은(는) 구매할 수 없습니다.",
            )
        if product.seller.status != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"'{product.title}' 판매자가 활성 상태가 아닙니다.",
            )

    # Deadlock 완화: 상품 ID 오름차순으로 재고 예약
    cart_items.sort(key=lambda item: item.product_id)

    total = sum(item.product.price_credits * item.qty for item in cart_items)

    order = Order(user_id=user.id, status="pending", total_credits=total)
    db.add(order)
    db.flush()

    for item in cart_items:
        _reserve_stock(
            db,
            product_id=item.product_id,
            qty=item.qty,
            title=item.product.title,
        )
        db.add(
            OrderItem(
                order_id=order.id,
                product_id=item.product_id,
                seller_id=item.product.seller_id,
                qty=item.qty,
                unit_price_credits=item.product.price_credits,
                product_title=item.product.title,
                fulfillment_status="paid",
            )
        )

    debit_credits(
        db,
        user,
        total,
        ref_type="order",
        ref_id=order.id,
        note="주문 결제",
    )

    order.status = "paid"
    for item in cart_items:
        db.delete(item)

    db.flush()
    # 원자 UPDATE 이후 ORM에 남은 구 재고 값 폐기
    db.expire_all()

    order = db.scalar(
        select(Order)
        .where(Order.id == order.id)
        .options(joinedload(Order.items).joinedload(OrderItem.seller))
    )
    if order is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="주문 생성 실패")
    return _order_response(order)
