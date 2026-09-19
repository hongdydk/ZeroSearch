import uuid
from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.deps import require_active_seller
from app.models import Product, Seller
from app.schemas.product import SellerProductCounts
from app.schemas.seller import SellerProductBulkRequest, SellerProductUpdateRequest
from app.services.products import (
    delete_seller_product,
    bulk_update_seller_products,
    list_seller_products,
    product_to_response,
    update_seller_product,
)
from tests.factories import make_user, override_current_user, override_db


def _seller(**kwargs) -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="입점마트",
        slug="merchant-shop",
        status="active",
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    for key, value in kwargs.items():
        setattr(seller, key, value)
    return seller


def _product(seller: Seller, **kwargs) -> Product:
    product = Product(
        id=uuid.uuid4(),
        seller_id=seller.id,
        catalog_product_id=uuid.uuid4(),
        title="백산수",
        option_label="500ml × 20",
        flavor="레몬",
        volume_ml=10000,
        price_credits=12000,
        stock=40,
        category="생수",
        image_url="https://img.example/water.jpg",
        status="published",
        pack_count=1,
    )
    product.created_at = datetime.now(UTC)
    product.seller = seller
    for key, value in kwargs.items():
        setattr(product, key, value)
    return product


def test_product_to_response_keeps_option_fields():
    product = _product(_seller())
    body = product_to_response(product).model_dump(by_alias=True)
    assert body["optionLabel"] == "500ml × 20"
    assert body["flavor"] == "레몬"
    assert body["volumeMl"] == 10000
    assert body["catalogProductId"] == str(product.catalog_product_id)


def _empty_counts_row(**kwargs) -> SimpleNamespace:
    row = SimpleNamespace(all_count=0, published=0, pending=0, sold_out=0, hidden=0)
    for key, value in kwargs.items():
        setattr(row, key, value)
    return row


def _mock_list_db(items: list[Product] | None = None, counts: SimpleNamespace | None = None) -> MagicMock:
    db = MagicMock()
    db.execute.return_value.one.return_value = counts or _empty_counts_row()
    unique = MagicMock()
    unique.all.return_value = items or []
    db.scalars.return_value.unique.return_value = unique
    return db


def test_list_seller_products_includes_archived():
    db = _mock_list_db()
    list_seller_products(db, _seller())
    sql = str(db.scalars.call_args.args[0])
    assert "archived" not in sql.lower()


def test_list_seller_products_search_sort_paginates_and_counts():
    seller = _seller()
    product = _product(seller, price_credits=3000, stock=2)
    counts = _empty_counts_row(all_count=4, published=1, pending=2, sold_out=0, hidden=1)
    db = _mock_list_db([product], counts)
    items, total, body = list_seller_products(
        db,
        seller,
        q="백산",
        offer_filter="published",
        sort="price",
        offset=20,
        limit=10,
    )
    assert items == [product]
    assert total == 1
    assert body.published == 1
    assert body.pending == 2
    assert body.hidden == 1
    count_sql = str(db.execute.call_args.args[0]).lower()
    assert "title" in count_sql
    assert "option_label" in count_sql
    list_sql = str(db.scalars.call_args.args[0]).lower()
    assert "price_credits" in list_sql
    assert "offset" in list_sql or "limit" in list_sql


def test_list_seller_products_sorts_stock_and_filters_pending():
    db = _mock_list_db(counts=_empty_counts_row(all_count=3, pending=3))
    _, total, counts = list_seller_products(db, _seller(), offer_filter="pending", sort="stock")
    assert total == 3
    assert counts.pending == 3
    sql = str(db.scalars.call_args.args[0]).lower()
    assert "stock" in sql
    assert "status" in sql


def test_patch_price_and_stock():
    seller = _seller()
    product = _product(seller)
    with patch("app.services.products.get_seller_product", return_value=product):
        updated = update_seller_product(
            MagicMock(),
            seller,
            product.id,
            SellerProductUpdateRequest(priceCredits=9900, stock=7),
        )
    assert updated.price_credits == 9900
    assert updated.stock == 7
    assert updated.status == "published"


def test_patch_hide_archives_published_offer():
    seller = _seller()
    product = _product(seller, status="published")
    with patch("app.services.products.get_seller_product", return_value=product):
        updated = update_seller_product(
            MagicMock(),
            seller,
            product.id,
            SellerProductUpdateRequest(status="archived"),
        )
    assert updated.status == "archived"


def test_patch_unhide_restores_published_from_archived():
    seller = _seller()
    product = _product(seller, status="archived")
    with patch("app.services.products.get_seller_product", return_value=product):
        updated = update_seller_product(
            MagicMock(),
            seller,
            product.id,
            SellerProductUpdateRequest(status="published"),
        )
    assert updated.status == "published"


def test_patch_still_blocks_self_publish_from_draft():
    seller = _seller()
    product = _product(seller, status="draft")
    with patch("app.services.products.get_seller_product", return_value=product):
        with pytest.raises(HTTPException) as exc:
            update_seller_product(
                MagicMock(),
                seller,
                product.id,
                SellerProductUpdateRequest(status="published"),
            )
    assert exc.value.status_code == 400
    assert "검수" in exc.value.detail
    assert product.status == "draft"


def test_bulk_sets_price_stock_and_hide_for_owned_ids():
    seller = _seller()
    first = _product(seller, price_credits=12000, stock=4)
    second = _product(seller, price_credits=8000, stock=9, status="published")
    db = MagicMock()
    unique = MagicMock()
    unique.all.return_value = [first, second]
    db.scalars.return_value.unique.return_value = unique
    updated, failed = bulk_update_seller_products(
        db,
        seller,
        SellerProductBulkRequest(ids=[first.id, second.id], priceCredits=5500, stock=0),
    )
    assert failed == []
    assert [row.id for row in updated] == [first.id, second.id]
    assert first.price_credits == 5500
    assert second.price_credits == 5500
    assert first.stock == 0
    assert second.stock == 0

    unique.all.return_value = [first, second]
    hidden, hide_failed = bulk_update_seller_products(
        db,
        seller,
        SellerProductBulkRequest(ids=[first.id, second.id], status="archived"),
    )
    assert hide_failed == []
    assert [row.status for row in hidden] == ["archived", "archived"]


def test_bulk_records_missing_and_blocks_draft_unhide():
    seller = _seller()
    visible = _product(seller, status="archived")
    draft = _product(seller, status="draft")
    missing = uuid.uuid4()
    db = MagicMock()
    unique = MagicMock()
    unique.all.return_value = [visible, draft]
    db.scalars.return_value.unique.return_value = unique
    updated, failed = bulk_update_seller_products(
        db,
        seller,
        SellerProductBulkRequest(ids=[visible.id, missing, draft.id], status="published"),
    )
    assert [row.id for row in updated] == [visible.id]
    assert visible.status == "published"
    assert draft.status == "draft"
    assert {row.id: row.detail for row in failed} == {
        str(missing): "상품을 찾을 수 없습니다.",
        str(draft.id): "검수 전에는 공개할 수 없습니다.",
    }


def test_bulk_requires_an_action():
    seller = _seller()
    with pytest.raises(HTTPException) as exc:
        bulk_update_seller_products(
            MagicMock(),
            seller,
            SellerProductBulkRequest(ids=[uuid.uuid4()]),
        )
    assert exc.value.status_code == 400
    assert "가격" in exc.value.detail


def test_delete_removes_offer_and_its_live_references():
    seller = _seller()
    product = _product(seller, status="published")
    db = MagicMock()
    with patch("app.services.products.get_seller_product", return_value=product):
        delete_seller_product(db, seller, product.id)
    assert product.status == "published"
    db.delete.assert_called_once_with(product)
    assert db.execute.call_count == 2
    assert "cart_items" in str(db.execute.call_args_list[0].args[0]).lower()
    assert "catalog_intake_drafts" in str(db.execute.call_args_list[1].args[0]).lower()


def test_seller_list_route_returns_hidden_option_fields(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    hidden = _product(seller, status="archived", option_label="2L × 6", flavor="자몽")
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    counts = SellerProductCounts(all=1, published=0, pending=0, sold_out=0, hidden=1)
    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch(
            "app.routers.seller.list_seller_products",
            return_value=([hidden], 1, counts),
        ):
            response = client.get(
                "/seller/products",
                params={"q": "자몽", "filter": "hidden", "sort": "newest", "offset": 0, "limit": 20},
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 200
    body = response.json()
    row = body["items"][0]
    assert body["total"] == 1
    assert body["counts"]["hidden"] == 1
    assert body["counts"]["published"] == 0
    assert row["status"] == "archived"
    assert row["optionLabel"] == "2L × 6"
    assert row["flavor"] == "자몽"


def test_seller_get_product_route(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    product = _product(seller, option_label="2L × 6")
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch("app.routers.seller.get_seller_product", return_value=product):
            response = client.get(
                f"/seller/products/{product.id}",
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(product.id)
    assert body["optionLabel"] == "2L × 6"


def test_seller_patch_route_hide_price_stock(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    product = _product(seller, price_credits=8800, stock=5, status="archived")
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch("app.routers.seller.update_seller_product", return_value=product) as mock_update:
            response = client.patch(
                f"/seller/products/{product.id}",
                json={"priceCredits": 8800, "stock": 5, "status": "archived"},
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 200
    mock_update.assert_called_once()
    payload = mock_update.call_args.args[3]
    assert payload.price_credits == 8800
    assert payload.stock == 5
    assert payload.status == "archived"
    body = response.json()
    assert body["priceCredits"] == 8800
    assert body["stock"] == 5
    assert body["status"] == "archived"
    assert body["optionLabel"] == "500ml × 20"
    assert body["packCount"] == 1


def test_seller_bulk_route_returns_partial_summary(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    product = _product(seller, price_credits=3000, stock=0)
    override_current_user(user)
    override_db(MagicMock())
    from app.schemas.product import SellerProductBulkFailure
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch(
            "app.routers.seller.bulk_update_seller_products",
            return_value=(
                [product],
                [SellerProductBulkFailure(id=str(uuid.uuid4()), detail="상품을 찾을 수 없습니다.")],
            ),
        ) as mock_bulk:
            response = client.post(
                "/seller/products/bulk",
                json={"ids": [str(product.id), str(uuid.uuid4())], "stock": 0},
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 200
    mock_bulk.assert_called_once()
    payload = mock_bulk.call_args.args[2]
    assert payload.stock == 0
    body = response.json()
    assert body["successCount"] == 1
    assert body["failCount"] == 1
    assert body["updated"][0]["stock"] == 0
    assert body["failed"][0]["detail"] == "상품을 찾을 수 없습니다."


def test_seller_bulk_route_rejects_empty_action(client):
    user = make_user()
    seller = _seller(user_id=user.id)
    product_id = uuid.uuid4()
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch(
            "app.routers.seller.bulk_update_seller_products",
            side_effect=HTTPException(status_code=400, detail="가격, 재고, 숨김 중 하나를 지정하세요."),
        ):
            response = client.post(
                "/seller/products/bulk",
                json={"ids": [str(product_id)]},
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 400
    assert "가격" in response.json()["detail"]


def test_create_without_price_derives_per_unit_volume(client):
    seller = _seller()
    catalog_id = uuid.uuid4()
    product = _product(
        seller,
        price_credits=0,
        stock=0,
        option_label="2L × 12",
        volume_ml=2000,
        status="draft",
    )
    product.unit = "L"
    product.unit_amount = 2
    product.pack_count = 12
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())
    from main import app

    app.dependency_overrides[require_active_seller] = lambda: seller
    try:
        with patch("app.routers.seller.create_seller_product", return_value=product) as mock_create:
            response = client.post(
                "/seller/products",
                json={
                    "title": "백산수",
                    "category": "생수",
                    "catalogProductId": str(catalog_id),
                    "unitAmount": 2,
                    "unit": "L",
                    "packCount": 12,
                },
                headers={"Authorization": "Bearer fake"},
            )
    finally:
        app.dependency_overrides.pop(require_active_seller, None)

    assert response.status_code == 201
    mock_create.assert_called_once()
    payload = mock_create.call_args.args[2]
    assert payload.price_credits is None
    assert payload.stock is None
    assert payload.unit_amount == 2
    assert payload.unit == "L"
    assert payload.pack_count == 12
    body = response.json()
    assert body["priceCredits"] == 0
    assert body["status"] == "draft"
    assert body["optionLabel"] == "2L × 12"
    assert body["volumeMl"] == 2000
    assert body["packCount"] == 12
    assert body["unit"] == "L"
