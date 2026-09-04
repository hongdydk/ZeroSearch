from unittest.mock import MagicMock, patch

from app.services.catalog_import import _iter_rows, _volume_options
from tests.factories import make_user, override_current_user, override_db


def test_volume_options_split():
    assert _volume_options("100g|1000g") == ["100g", "1000g"]
    assert _volume_options("") == []


def test_iter_rows_skips_empty_maker():
    text = "대분류,중분류,소분류,품목명,제조사,용량\n김,김치류,김치,나박김치,(주)거풍,100g\n김,김치류,김치,배추김치,,100g\n"
    rows = list(_iter_rows(text))
    assert len(rows) == 1
    assert rows[0]["manufacturer"] == "(주)거풍"
    assert rows[0]["title"] == "나박김치"
    assert rows[0]["volume_options"] == ["100g"]


def test_admin_catalog_import(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    override_db(mock_db)

    with patch(
        "app.routers.admin.import_catalog_csv",
        return_value={"source_rows": 2, "upserted": 2},
    ) as mock_import:
        response = client.post(
            "/admin/catalog/import",
            files={"file": ("mfds.csv", "대분류,중분류,소분류,품목명,제조사,용량\n".encode(), "text/csv")},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    assert response.json()["upserted"] == 2
    mock_import.assert_called_once()
    mock_db.commit.assert_called_once()


def test_admin_catalog_import_rejects_large_file(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    override_db(MagicMock())
    huge = b"x" * (4 * 1024 * 1024 + 1)

    response = client.post(
        "/admin/catalog/import",
        files={"file": ("big.csv", huge, "text/csv")},
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 400
    assert "너무 큽니다" in response.json()["detail"]


def test_admin_catalog_import_text(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    override_db(mock_db)
    csv = "대분류,중분류,소분류,품목명,제조사,용량\n김,김치류,김치,나박김치,(주)거풍,100g\n"

    with patch(
        "app.routers.admin.import_catalog_csv",
        return_value={"source_rows": 1, "upserted": 1},
    ) as mock_import:
        response = client.post(
            "/admin/catalog/import-text",
            json={"csv": csv},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    assert response.json()["upserted"] == 1
    mock_import.assert_called_once()
    mock_db.commit.assert_called_once()


def test_seller_catalog_search_requires_query(client):
    import uuid
    from datetime import UTC, datetime

    from app.models import Seller

    user = make_user()
    override_current_user(user)
    seller = Seller(
        id=uuid.uuid4(),
        user_id=user.id,
        shop_name="테스트",
        slug="test",
        status="active",
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    mock_db = MagicMock()
    mock_db.scalar.return_value = seller
    override_db(mock_db)

    response = client.get("/seller/catalog-products", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json()["items"] == []
    assert response.json()["total"] == 0
