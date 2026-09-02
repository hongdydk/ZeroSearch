import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from app.models import Product, Seller
from tests.factories import make_user, override_current_user, override_db


def _sample_seller() -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="테스트 스토어",
        slug="test-shop",
        status="active",
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    return seller


def _sample_product(seller: Seller | None = None) -> Product:
    seller = seller or _sample_seller()
    product = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        title="무선 이어폰",
        description="테스트 상품",
        price_credits=45,
        stock=10,
        category="electronics",
        image_url="/images/earbuds.png",
        status="published",
    )
    product.created_at = datetime.now(UTC)
    product.seller = seller
    return product


def test_list_products(client):
    product = _sample_product()
    override_db(MagicMock())

    with patch("app.routers.products.list_public_products", return_value=([product], 1)):
        response = client.get("/products")

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "무선 이어폰"
    assert body["items"][0]["seller"]["shopName"] == "테스트 스토어"


def test_get_product_by_id(client):
    product = _sample_product()
    override_db(MagicMock())

    with patch("app.routers.products.get_public_product", return_value=product):
        response = client.get(f"/products/{product.id}")

    assert response.status_code == 200
    assert response.json()["id"] == str(product.id)
    assert response.json()["seller"]["sellerType"] == "merchant"


def test_get_product_not_found(client):
    from fastapi import HTTPException

    override_db(MagicMock())

    with patch(
        "app.routers.products.get_public_product",
        side_effect=HTTPException(status_code=404, detail="상품을 찾을 수 없습니다."),
    ):
        response = client.get(f"/products/{uuid.uuid4()}")

    assert response.status_code == 404


def test_seller_apply_requires_auth(client):
    response = client.post("/seller/apply", json={"shopName": "내 스토어"})
    assert response.status_code == 401


def test_seller_apply(client):
    user = make_user()
    override_current_user(user)
    seller = _sample_seller()
    seller.status = "pending"
    override_db(MagicMock())

    with patch("app.routers.seller.apply_for_seller", return_value=seller):
        response = client.post(
            "/seller/apply",
            json={"shopName": "내 스토어"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 201
    assert response.json()["status"] == "pending"
