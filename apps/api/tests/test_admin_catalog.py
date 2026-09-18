import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import CatalogProduct, Seller
from app.schemas.admin import AdminCatalogCreateRequest
from app.services.admin_catalog import create_admin_catalog_product, retire_catalog_product
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
