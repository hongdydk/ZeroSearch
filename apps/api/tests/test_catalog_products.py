import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.dialects import postgresql

from app.models import CatalogProduct, Product, Seller
from app.schemas.catalog_product import CatalogProductListItem
from app.services.catalog_products import (
    _aggregate_offers,
    _catalog_search_filter,
    get_catalog_product,
    list_catalog_products,
)
from tests.factories import override_db


def _sample_seller(*, seller_type: str = "platform") -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="공식 스토어" if seller_type == "platform" else "청정마트",
        slug="official" if seller_type == "platform" else "clean-mart",
        status="active",
        seller_type=seller_type,
    )
    seller.created_at = datetime.now(UTC)
    return seller


def _sample_catalog(*, title: str = "백산수", category: str = "생수") -> CatalogProduct:
    catalog = CatalogProduct(
        id=uuid.uuid4(),
        title=title,
        category=category,
        description="테스트 생수",
        price_unit="ml",
    )
    catalog.created_at = datetime.now(UTC)
    return catalog


def _sample_offer(
    catalog: CatalogProduct,
    seller: Seller,
    *,
    price_credits: int,
    volume_ml: int | None = None,
    flavor: str | None = None,
    option_label: str | None = None,
) -> Product:
    offer = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=price_credits,
        stock=10,
        category=catalog.category,
        status="published",
        volume_ml=volume_ml,
        flavor=flavor,
        option_label=option_label,
    )
    offer.created_at = datetime.now(UTC)
    offer.seller = seller
    return offer


def test_aggregate_median_unit_price():
    catalog = _sample_catalog()
    seller = _sample_seller()
    offers = [
        _sample_offer(catalog, seller, price_credits=10000, volume_ml=10000),
        _sample_offer(catalog, seller, price_credits=12000, volume_ml=10000),
        _sample_offer(catalog, seller, price_credits=9000, volume_ml=10000),
    ]
    count, median_unit, median_credits, price_unit, label = _aggregate_offers(offers)
    assert count == 3
    assert median_unit == pytest.approx(1.0)
    assert median_credits is None
    assert price_unit == "ml"
    assert label == "L당"


def test_aggregate_median_credits_fallback():
    catalog = _sample_catalog(title="무선 이어폰", category="electronics")
    seller = _sample_seller()
    offers = [
        _sample_offer(catalog, seller, price_credits=40),
        _sample_offer(catalog, seller, price_credits=50),
        _sample_offer(catalog, seller, price_credits=45),
    ]
    count, median_unit, median_credits, price_unit, label = _aggregate_offers(offers)
    assert count == 3
    assert median_unit is None
    assert median_credits == 45
    assert price_unit == "credits"
    assert label == "크레딧(보통)"


def test_aggregate_no_offers_returns_null_prices():
    count, median_unit, median_credits, price_unit, _label = _aggregate_offers([])
    assert count == 0
    assert median_unit is None
    assert median_credits is None
    assert price_unit == "credits"


def test_catalog_search_filter_compiles_for_query():
    stmt = select(CatalogProduct).where(*_catalog_search_filter("김치", None))
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "ILIKE" in sql.upper()
    assert "search_keywords" in sql


def test_list_catalog_products(client):
    catalog = _sample_catalog()
    seller = _sample_seller()
    items = [
        CatalogProductListItem(
            id=str(catalog.id),
            title="백산수",
            category="생수",
            offer_count=2,
            median_unit_price=0.52,
            median_price_credits=None,
            price_unit="ml",
            display_price_label="L당",
        )
    ]
    override_db(MagicMock())

    with patch("app.routers.catalog_products.list_catalog_products", return_value=(items, 1)):
        response = client.get("/catalog-products?q=생수")

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["title"] == "백산수"
    assert body["items"][0]["medianUnitPrice"] == 0.52
    assert "minPriceCredits" not in body["items"][0]


def test_list_catalog_products_flavor_filter(client):
    override_db(MagicMock())

    with patch("app.routers.catalog_products.list_catalog_products", return_value=([], 0)) as mock_list:
        response = client.get("/catalog-products?flavor=레몬&volumeMlMin=2000")

    assert response.status_code == 200
    mock_list.assert_called_once()
    _, kwargs = mock_list.call_args
    assert kwargs["flavor"] == "레몬"
    assert kwargs["volume_ml_min"] == 2000
    # 구매자 목록은 오퍼 없는 대표 상품도 포함 (기본 require_offers=False)
    assert kwargs.get("require_offers", False) is False


def test_list_catalog_products_includes_zero_offer_item(client):
    catalog = _sample_catalog(title="등록 전 생수")
    items = [
        CatalogProductListItem(
            id=str(catalog.id),
            title="등록 전 생수",
            category="생수",
            offer_count=0,
            median_unit_price=None,
            median_price_credits=None,
            price_unit="credits",
            display_price_label="크레딧(보통)",
        )
    ]
    override_db(MagicMock())

    with patch("app.routers.catalog_products.list_catalog_products", return_value=(items, 1)):
        response = client.get("/catalog-products?q=생수")

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["offerCount"] == 0
    assert body["items"][0]["medianUnitPrice"] is None
    assert body["items"][0]["medianPriceCredits"] is None


def test_list_catalog_products_empty_volume_filters(client):
    override_db(MagicMock())

    with patch("app.routers.catalog_products.list_catalog_products", return_value=([], 0)) as mock_list:
        response = client.get("/catalog-products?volumeMlMin=&volumeMlMax=")

    assert response.status_code == 200
    mock_list.assert_called_once()
    _, kwargs = mock_list.call_args
    assert kwargs["volume_ml_min"] is None
    assert kwargs["volume_ml_max"] is None


def test_get_catalog_product_detail(client):
    catalog_id = uuid.uuid4()
    override_db(MagicMock())
    from app.schemas.catalog_product import CatalogProductDetailResponse

    detail = CatalogProductDetailResponse(
        id=str(catalog_id),
        title="백산수",
        category="생수",
        offer_count=1,
        offers=[],
    )

    with patch("app.routers.catalog_products.get_catalog_product", return_value=detail):
        response = client.get(f"/catalog-products/{catalog_id}")

    assert response.status_code == 200
    assert response.json()["title"] == "백산수"


def test_get_catalog_product_not_found(client):
    override_db(MagicMock())

    with patch(
        "app.routers.catalog_products.get_catalog_product",
        side_effect=HTTPException(status_code=404, detail="대표 상품을 찾을 수 없습니다."),
    ):
        response = client.get(f"/catalog-products/{uuid.uuid4()}")

    assert response.status_code == 404
