import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.deps import require_admin
from tests.factories import make_user, override_current_user, override_db


def test_require_admin_rejects_non_admin():
    with pytest.raises(HTTPException) as exc_info:
        require_admin(make_user(is_admin=False))
    assert exc_info.value.status_code == 403


def test_require_admin_allows_admin():
    admin = make_user(is_admin=True)
    assert require_admin(admin) is admin


def test_admin_stats_forbidden_for_non_admin(client):
    override_current_user(make_user(is_admin=False))

    response = client.get("/admin/stats", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 403
    assert response.json()["detail"] == "관리자 권한이 필요합니다."


def test_admin_stats_ok_for_admin(client):
    override_current_user(make_user(is_admin=True))

    with patch(
        "app.routers.admin.get_admin_stats",
        return_value={
            "user_count": 1,
            "product_count": 8,
            "order_count": 3,
            "seller_count": 2,
            "pending_seller_count": 1,
            "sold_item_count": 5,
            "sold_qty_sum": 11,
            "sold_amount_sum": 2200,
        },
    ):
        response = client.get("/admin/stats", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json() == {
        "userCount": 1,
        "productCount": 8,
        "orderCount": 3,
        "sellerCount": 2,
        "pendingSellerCount": 1,
        "soldItemCount": 5,
        "soldQtySum": 11,
        "soldAmountSum": 2200,
    }


def test_db_reset_requires_confirm_token(client):
    override_current_user(make_user(is_admin=True))

    with patch("app.routers.admin.get_settings") as mock_settings:
        mock_settings.return_value.allow_db_reset = True
        response = client.post(
            "/admin/db/reset",
            json={"mode": "seed", "confirm": "WRONG"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 400
    assert "RESET" in response.json()["detail"]


def test_db_reset_blocked_when_env_disabled(client):
    override_current_user(make_user(is_admin=True))

    with patch("app.routers.admin.get_settings") as mock_settings:
        mock_settings.return_value.allow_db_reset = False
        response = client.post(
            "/admin/db/reset",
            json={"mode": "seed", "confirm": "RESET"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 403
    assert "ALLOW_DB_RESET" in response.json()["detail"]


def test_db_reset_ok_with_confirm(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)

    with (
        patch("app.routers.admin.get_settings") as mock_settings,
        patch("app.routers.admin.run_db_reset", return_value="done") as mock_reset,
    ):
        mock_settings.return_value.allow_db_reset = True
        response = client.post(
            "/admin/db/reset",
            json={"mode": "truncate_except_users", "confirm": "RESET"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    assert response.json()["message"] == "done"
    mock_reset.assert_called_once()


def test_promote_sets_is_admin(client):
    admin = make_user(is_admin=True)
    target = make_user(email="buyer@mall.local", is_admin=False)
    override_current_user(admin)

    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    response = client.post(
        f"/admin/users/{target.id}/promote",
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 200
    assert target.is_admin is True
    assert response.json()["isAdmin"] is True


def _users_db(*users: object) -> MagicMock:
    mock_db = MagicMock()
    mock_db.scalar.return_value = len(users)
    listed = MagicMock()
    listed.unique.return_value.all.return_value = list(users)
    mock_db.scalars.return_value = listed
    return mock_db


def test_list_users_includes_seller_status(client):
    admin = make_user(is_admin=True)
    buyer = make_user(email="buyer@mall.local", is_admin=False)
    seller_user = make_user(email="shop@mall.local", is_admin=False)
    seller_user.seller = MagicMock(status="active")
    override_current_user(admin)
    override_db(_users_db(buyer, seller_user))

    response = client.get("/admin/users", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    by_email = {item["email"]: item for item in response.json()["items"]}
    assert by_email["buyer@mall.local"]["isAdmin"] is False
    assert by_email["buyer@mall.local"]["sellerStatus"] is None
    assert by_email["shop@mall.local"]["sellerStatus"] == "active"


def test_list_users_search_q(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    override_db(_users_db(make_user(email="buyer@mall.local")))

    response = client.get(
        "/admin/users",
        params={"q": "buyer"},
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 200
    assert response.json()["items"][0]["email"] == "buyer@mall.local"


def test_update_user_sets_is_admin(client):
    admin = make_user(is_admin=True)
    target = make_user(email="buyer@mall.local", is_admin=False)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    with patch("app.routers.admin.count_admins", return_value=2):
        response = client.patch(
            f"/admin/users/{target.id}",
            json={"isAdmin": True},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    assert target.is_admin is True
    assert response.json()["isAdmin"] is True


def test_delete_user_ok(client):
    admin = make_user(is_admin=True)
    target = make_user(email="buyer@mall.local", is_admin=False)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    with (
        patch("app.routers.admin.count_admins", return_value=1),
        patch("app.routers.admin.delete_user_account") as mock_delete,
    ):
        response = client.delete(
            f"/admin/users/{target.id}",
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 204
    mock_delete.assert_called_once()


def test_delete_user_rejects_self(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = admin
    override_db(mock_db)

    response = client.delete(
        f"/admin/users/{admin.id}",
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 400
    assert "자기 자신" in response.json()["detail"]
