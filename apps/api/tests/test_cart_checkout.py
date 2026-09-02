import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from app.schemas.cart import CartItemResponse, CartResponse
from app.schemas.order import OrderItemResponse, OrderResponse
from tests.factories import make_user, override_current_user, override_db


def test_get_cart_requires_auth(client):
    response = client.get("/me/cart")
    assert response.status_code == 401


def test_add_to_cart(client):
    user = make_user()
    override_current_user(user)
    mock_db = MagicMock()
    override_db(mock_db)

    cart = CartResponse(
        items=[
            CartItemResponse(
                id=str(uuid.uuid4()),
                product_id=str(uuid.uuid4()),
                qty=2,
                product_title="텀블러",
                price_credits=12,
                line_total_credits=24,
                created_at=datetime.now(UTC),
            )
        ],
        total_credits=24,
    )

    with patch("app.routers.cart.add_to_cart", return_value=cart):
        response = client.post(
            "/me/cart",
            json={"productId": str(uuid.uuid4()), "qty": 2},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 201
    assert response.json()["totalCredits"] == 24
    assert len(response.json()["items"]) == 1


def test_checkout_creates_paid_order(client):
    user = make_user()
    override_current_user(user)
    mock_db = MagicMock()
    override_db(mock_db)

    order_id = str(uuid.uuid4())
    order = OrderResponse(
        id=order_id,
        status="paid",
        total_credits=24,
        items=[
            OrderItemResponse(
                id=str(uuid.uuid4()),
                product_id=str(uuid.uuid4()),
                product_title="텀블러",
                seller_id=str(uuid.uuid4()),
                shop_name="공식 스토어",
                seller_type="platform",
                qty=2,
                unit_price_credits=12,
                line_total_credits=24,
                fulfillment_status="paid",
            )
        ],
        created_at=datetime.now(UTC),
    )

    with patch("app.routers.orders.checkout", return_value=order):
        response = client.post("/me/orders", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 201
    body = response.json()["order"]
    assert body["status"] == "paid"
    assert body["totalCredits"] == 24


def test_checkout_response_shape(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    order = OrderResponse(
        id=str(uuid.uuid4()),
        status="paid",
        total_credits=45,
        items=[],
        created_at=datetime.now(UTC),
    )

    with patch("app.routers.orders.checkout", return_value=order):
        response = client.post("/me/orders", headers={"Authorization": "Bearer fake"})

    assert "order" in response.json()


def test_list_orders(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    order = OrderResponse(
        id=str(uuid.uuid4()),
        status="paid",
        total_credits=45,
        items=[],
        created_at=datetime.now(UTC),
    )

    with patch("app.routers.orders.list_orders", return_value=([order], 1)):
        response = client.get("/me/orders", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json()["total"] == 1
