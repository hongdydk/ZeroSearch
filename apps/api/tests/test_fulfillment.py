import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import Order, OrderItem, Seller
from app.schemas.seller import SellerOrderItemStatusUpdate
from app.services.seller_orders import (
    update_admin_order_item_status,
    update_seller_order_item_status,
)
from tests.factories import make_user, override_current_user, override_db


def _order_item(**kwargs) -> OrderItem:
    item = OrderItem(
        id=uuid.uuid4(),
        order_id=uuid.uuid4(),
        product_id=uuid.uuid4(),
        seller_id=uuid.uuid4(),
        qty=1,
        unit_price_credits=100,
        product_title="테스트 상품",
        fulfillment_status="paid",
    )
    order = Order(
        id=item.order_id,
        user_id=uuid.uuid4(),
        status="paid",
        total_credits=100,
    )
    order.created_at = datetime.now(UTC)
    item.order = order
    for key, value in kwargs.items():
        setattr(item, key, value)
    return item


def _seller(**kwargs) -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="테스트 숍",
        slug="test-shop",
        status="active",
        seller_type="merchant",
    )
    for key, value in kwargs.items():
        setattr(seller, key, value)
    return seller


def test_fulfillment_transition_happy_path():
    db = MagicMock()
    seller = _seller()
    item = _order_item(seller_id=seller.id)
    db.scalar.return_value = item

    for status in ("preparing", "shipped", "delivered"):
        update_seller_order_item_status(
            db,
            seller,
            item.id,
            SellerOrderItemStatusUpdate(fulfillment_status=status),
        )
        assert item.fulfillment_status == status


def test_fulfillment_skip_step_rejected():
    db = MagicMock()
    seller = _seller()
    item = _order_item(seller_id=seller.id, fulfillment_status="paid")
    db.scalar.return_value = item

    with pytest.raises(HTTPException) as exc:
        update_seller_order_item_status(
            db,
            seller,
            item.id,
            SellerOrderItemStatusUpdate(fulfillment_status="shipped"),
        )
    assert exc.value.status_code == 400


def test_fulfillment_wrong_seller_not_found():
    db = MagicMock()
    seller = _seller()
    db.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        update_seller_order_item_status(
            db,
            seller,
            uuid.uuid4(),
            SellerOrderItemStatusUpdate(fulfillment_status="preparing"),
        )
    assert exc.value.status_code == 404


def test_admin_can_update_any_item():
    db = MagicMock()
    item = _order_item(fulfillment_status="shipped")
    seller = _seller(seller_type="platform")
    item.seller = seller
    db.scalar.return_value = item

    update_admin_order_item_status(
        db,
        item.id,
        SellerOrderItemStatusUpdate(fulfillment_status="delivered"),
    )
    assert item.fulfillment_status == "delivered"


def test_admin_list_orders_requires_admin(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    response = client.get("/admin/orders", headers={"Authorization": "Bearer fake"})
    assert response.status_code == 403


def test_admin_list_orders_ok(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    override_db(MagicMock())

    item = _order_item()
    seller = _seller()
    item.seller = seller

    with patch("app.routers.admin.list_admin_order_items", return_value=([item], 1)):
        response = client.get("/admin/orders", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["shopName"] == "테스트 숍"
    assert body["items"][0]["sellerType"] == "merchant"
