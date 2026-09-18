import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import CatalogProduct, Product, Seller
from app.schemas.admin import AdminCatalogCreateRequest, AdminCatalogProductItem
from app.services.admin_catalog import (
    create_admin_catalog_product,
    list_admin_catalog_products,
    offer_stats_for_admin,
    retire_catalog_product,
)
from app.services.catalog_products import get_catalog_product
from tests.factories import make_user, override_current_user, override_db


def _catalog(**kwargs) -> CatalogProduct:
    catalog = CatalogProduct(
        id=kwargs.get("id") or uuid.uuid4(),
        title=kwargs.get("title", "백산수"),
        manufacturer=kwargs.get("manufacturer", "농심"),
        category=kwargs.get("category", "생수"),
        status=kwargs.get("status", "active"),
    )
    catalog.created_at = datetime.now(UTC)
    catalog.l1_tags = []
    return catalog


def test_retire_archives_offers_and_keeps_catalog_row():
    catalog = _catalog()
    offer_id = uuid.uuid4()
    db = MagicMock()
    db.scalars.return_value.all.return_value = [offer_id]
    db.get.return_value = catalog

    with patch("app.services.admin_catalog.resolve_catalog_product", return_value=catalog):
        item = retire_catalog_product(db, catalog.id)

    assert item.status == "retired"
    assert catalog.status == "retired"
    db.delete.assert_not_called()
    assert db.execute.call_count == 2
    executed_sql = " ".join(str(call.args[0]) for call in db.execute.call_args_list)
    assert "cart_items" in executed_sql
    assert "products" in executed_sql
    assert "UPDATE" in executed_sql.upper() or "update" in executed_sql


def test_retire_empty_catalog_is_soft_delete():
    catalog = _catalog()
    db = MagicMock()
    db.scalars.return_value.all.return_value = []
    with patch("app.services.admin_catalog.resolve_catalog_product", return_value=catalog):
        item = retire_catalog_product(db, catalog.id)
    assert item.status == "retired"
    db.delete.assert_not_called()
    db.execute.assert_not_called()


def test_retire_already_retired_conflicts():
    catalog = _catalog(status="retired")
    db = MagicMock()
    with patch("app.services.admin_catalog.resolve_catalog_product", return_value=catalog):
        with pytest.raises(HTTPException) as exc:
            retire_catalog_product(db, catalog.id)
    assert exc.value.status_code == 409
    db.delete.assert_not_called()


def test_retire_missing_catalog_404():
    db = MagicMock()
    db.get.return_value = None
    with patch("app.services.admin_catalog.resolve_catalog_product", return_value=None):
        with pytest.raises(HTTPException) as exc:
            retire_catalog_product(db, uuid.uuid4())
    assert exc.value.status_code == 404


def test_create_catalog_inserts_active_card():
    db = MagicMock()
    db.scalar.return_value = None
    payload = AdminCatalogCreateRequest(manufacturer="농심", title="백산수", category="생수")
    with patch("app.services.admin_catalog.apply_auto_l1_tags"):
        item = create_admin_catalog_product(db, payload)
    assert item.manufacturer == "농심"
    assert item.title == "백산수"
    assert item.status == "active"
    db.add.assert_called_once()
    added = db.add.call_args.args[0]
    assert isinstance(added, CatalogProduct)
    assert added.status == "active"


def test_create_catalog_rejects_active_duplicate():
    existing = _catalog(status="active")
    db = MagicMock()
    db.scalar.return_value = existing
    payload = AdminCatalogCreateRequest(manufacturer="농심", title="백산수", category="생수")
    with pytest.raises(HTTPException) as exc:
        create_admin_catalog_product(db, payload)
    assert exc.value.status_code == 409


def test_create_catalog_restores_retired_duplicate():
    existing = _catalog(status="retired")
    db = MagicMock()
    db.scalar.side_effect = [existing, 2, 0]
    payload = AdminCatalogCreateRequest(manufacturer="농심", title="백산수", category="생수")
    with patch("app.services.admin_catalog.apply_auto_l1_tags"):
        item = create_admin_catalog_product(db, payload)
    assert existing.status == "active"
    assert item.status == "active"
    db.add.assert_not_called()


def test_public_detail_hides_retired_catalog():
    catalog = _catalog(status="retired")
    db = MagicMock()
    with patch("app.services.catalog_products.resolve_catalog_product", return_value=catalog):
        with pytest.raises(HTTPException) as exc:
            get_catalog_product(db, catalog.id)
    assert exc.value.status_code == 404


def test_admin_create_catalog_endpoint(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    catalog = _catalog()
    from app.schemas.admin import AdminCatalogProductItem

    payload_item = AdminCatalogProductItem(
        id=str(catalog.id),
        title="백산수",
        manufacturer="농심",
        category="생수",
        status="active",
        offer_count=0,
        published_offer_count=0,
    )
    override_db(MagicMock())
    with patch("app.routers.admin.create_admin_catalog_product", return_value=payload_item):
        response = client.post(
            "/admin/catalog/products",
            json={"manufacturer": "농심", "title": "백산수", "category": "생수"},
            headers={"Authorization": "Bearer fake"},
        )
    assert response.status_code == 201
    assert response.json()["title"] == "백산수"
    assert response.json()["status"] == "active"


def test_admin_delete_catalog_endpoint(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    from app.schemas.admin import AdminCatalogProductItem

    item = AdminCatalogProductItem(
        id=str(uuid.uuid4()),
        title="백산수",
        manufacturer="농심",
        category="생수",
        status="retired",
        offer_count=1,
        published_offer_count=0,
    )
    override_db(MagicMock())
    with patch("app.routers.admin.retire_catalog_product", return_value=item):
        response = client.delete(
            f"/admin/catalog/products/{item.id}",
            headers={"Authorization": "Bearer fake"},
        )
    assert response.status_code == 200
    assert response.json()["status"] == "retired"


def _seller(*, slug: str = "official", status: str = "active") -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name=slug,
        slug=slug,
        status=status,
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    return seller


def _offer(catalog: CatalogProduct, seller: Seller, *, status: str = "published", price: int = 1000, volume_ml: int | None = 500) -> Product:
    offer = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=catalog.id,
        title=catalog.title,
        price_credits=price,
        stock=10,
        category=catalog.category,
        status=status,
        volume_ml=volume_ml,
    )
    offer.created_at = datetime.now(UTC)
    offer.seller = seller
    return offer


def test_offer_stats_count_shops_and_median_price():
    catalog = _catalog()
    shop_a = _seller(slug="a")
    shop_b = _seller(slug="b")
    suspended = _seller(slug="paused", status="suspended")
    offers = [
        _offer(catalog, shop_a, price=1000, volume_ml=500),
        _offer(catalog, shop_b, price=1500, volume_ml=500),
        _offer(catalog, shop_a, status="archived", price=800, volume_ml=500),
        _offer(catalog, suspended, price=900, volume_ml=500),
    ]
    total, published, shops, median_unit, median_credits, price_unit, label = offer_stats_for_admin(offers)
    assert total == 4
    assert published == 2
    assert shops == 2
    assert price_unit == "ml"
    assert label == "L당"
    assert median_unit == pytest.approx((1000 / 500 + 1500 / 500) / 2)
    assert median_credits is None


def test_list_admin_catalog_paginates_and_attaches_offer_stats():
    page = [_catalog(title="백산수"), _catalog(title="삼다수", manufacturer="광동")]
    shop = _seller()
    offers = [
        _offer(page[0], shop, price=1200, volume_ml=2000),
        _offer(page[0], shop, status="archived", price=900, volume_ml=500),
    ]
    db = MagicMock()
    db.scalar.return_value = 80
    catalogs_result = MagicMock()
    catalogs_result.all.return_value = page
    offers_result = MagicMock()
    offers_result.unique.return_value.all.return_value = offers
    db.scalars.side_effect = [catalogs_result, offers_result]

    items, total = list_admin_catalog_products(db, q="수", offset=24, limit=24)

    assert total == 80
    assert len(items) == 2
    first = items[0]
    assert first.title == "백산수"
    assert first.offer_count == 2
    assert first.published_offer_count == 1
    assert first.shop_count == 1
    assert first.median_unit_price == pytest.approx(1200 / 2000)
    assert first.display_price_label == "L당"
    assert items[1].offer_count == 0
    assert items[1].published_offer_count == 0
    assert items[1].shop_count == 0
    list_stmt = db.scalars.call_args_list[0].args[0]
    compiled = str(list_stmt.compile())
    assert "OFFSET" in compiled.upper()
    assert "LIMIT" in compiled.upper()


def test_admin_list_catalog_endpoint_forwards_pagination(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    catalog = _catalog()
    item = AdminCatalogProductItem(
        id=str(catalog.id),
        title="백산수",
        manufacturer="농심",
        category="생수",
        status="active",
        offer_count=3,
        published_offer_count=2,
        shop_count=2,
        median_unit_price=0.6,
        price_unit="ml",
        display_price_label="L당",
    )
    override_db(MagicMock())
    with patch(
        "app.routers.admin.list_admin_catalog_products",
        return_value=([item], 120),
    ) as mock_list:
        response = client.get(
            "/admin/catalog/products",
            params={
                "q": "백산",
                "offset": 48,
                "limit": 24,
                "includeRetired": True,
                "l1Tag": "생수/음료",
            },
            headers={"Authorization": "Bearer fake"},
        )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 120
    assert body["offset"] == 48
    assert body["limit"] == 24
    assert body["items"][0]["offerCount"] == 3
    assert body["items"][0]["publishedOfferCount"] == 2
    assert body["items"][0]["shopCount"] == 2
    assert body["items"][0]["medianUnitPrice"] == 0.6
    _, kwargs = mock_list.call_args
    assert kwargs["q"] == "백산"
    assert kwargs["offset"] == 48
    assert kwargs["limit"] == 24
    assert kwargs["include_retired"] is True
    assert kwargs["l1_tag"] == "생수/음료"
