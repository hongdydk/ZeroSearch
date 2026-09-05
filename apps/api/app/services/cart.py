from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.models import CartItem, Product, User
from app.schemas.cart import CartItemResponse, CartResponse, CartIssueCode


def _item_availability(product: Product, qty: int) -> tuple[bool, CartIssueCode | None, str | None, int]:
    """행은 유지하고 판매/재고 이슈만 계산한다. 반환: available, code, message, max_qty."""
    seller = product.seller
    if product.status != "published":
        return False, "offer_unavailable", "판매가 종료된 상품입니다.", 0
    if seller is None or seller.status != "active":
        return False, "seller_inactive", "판매자가 판매 중이 아닙니다.", 0
    if product.stock <= 0:
        return False, "out_of_stock", "품절된 상품입니다.", 0
    max_qty = min(99, product.stock)
    if qty > product.stock:
        return (
            False,
            "insufficient_stock",
            f"재고가 {product.stock}개만 남았습니다.",
            max_qty,
        )
    return True, None, None, max_qty


def _cart_item_response(item: CartItem) -> CartItemResponse:
    product = item.product
    seller = product.seller
    available, code, message, max_qty = _item_availability(product, item.qty)
    return CartItemResponse(
        id=str(item.id),
        product_id=str(item.product_id),
        qty=item.qty,
        product_title=product.title,
        seller_id=str(product.seller_id),
        shop_name=seller.shop_name if seller else "",
        seller_type=seller.seller_type if seller else "merchant",  # type: ignore[arg-type]
        price_credits=product.price_credits,
        line_total_credits=product.price_credits * item.qty,
        created_at=item.created_at,
        is_available=available,
        issue_code=code,
        issue_message=message,
        max_qty=max_qty,
    )


def _ensure_purchasable(product: Product) -> None:
    if product.status != "published":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="구매할 수 없는 상품입니다.")
    if product.seller.status != "active":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="판매 중인 상품이 아닙니다.")


def get_cart(db: Session, user: User) -> CartResponse:
    items = db.scalars(
        select(CartItem)
        .where(CartItem.user_id == user.id)
        .options(joinedload(CartItem.product).joinedload(Product.seller))
        .order_by(CartItem.created_at.desc())
    ).all()
    responses = [_cart_item_response(item) for item in items]
    total = sum(r.line_total_credits for r in responses)
    blocked = any(not r.is_available for r in responses)
    return CartResponse(items=responses, total_credits=total, checkout_blocked=blocked)


def add_to_cart(db: Session, user: User, product_id: UUID, qty: int) -> CartResponse:
    product = db.scalar(
        select(Product)
        .where(Product.id == product_id)
        .options(joinedload(Product.seller))
    )
    if product is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="상품을 찾을 수 없습니다.")
    _ensure_purchasable(product)
    if product.stock < qty:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="재고가 부족합니다.")

    item = db.scalar(
        select(CartItem).where(CartItem.user_id == user.id, CartItem.product_id == product_id)
    )
    if item is None:
        item = CartItem(user_id=user.id, product_id=product_id, qty=qty)
        db.add(item)
    else:
        new_qty = item.qty + qty
        if product.stock < new_qty:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="재고가 부족합니다.")
        item.qty = new_qty

    db.flush()
    return get_cart(db, user)


def update_cart_item(db: Session, user: User, product_id: UUID, qty: int) -> CartResponse:
    item = db.scalar(
        select(CartItem)
        .where(CartItem.user_id == user.id, CartItem.product_id == product_id)
        .options(joinedload(CartItem.product).joinedload(Product.seller))
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="장바구니에 해당 상품이 없습니다.")

    if qty == 0:
        db.delete(item)
        db.flush()
        return get_cart(db, user)

    product = item.product
    # 문제 행도 수량 감소는 허용. 증가·정상 수량은 판매/재고 검증.
    if qty > item.qty:
        _ensure_purchasable(product)
        if product.stock < qty:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="재고가 부족합니다.")
    elif product.status == "published" and product.seller.status == "active" and product.stock < qty:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="재고가 부족합니다.")

    item.qty = qty
    db.flush()
    return get_cart(db, user)


def remove_from_cart(db: Session, user: User, product_id: UUID) -> CartResponse:
    item = db.scalar(
        select(CartItem).where(CartItem.user_id == user.id, CartItem.product_id == product_id)
    )
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="장바구니에 해당 상품이 없습니다.")

    db.delete(item)
    db.flush()
    return get_cart(db, user)
