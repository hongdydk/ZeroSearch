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
        "paidOrderCount": 0,
        "salesLineCount": 0,
        "dailySales": [],
        "fulfillmentCounts": {},
        "offerCounts": {},
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
    seller_user.seller = MagicMock(status="active", shop_name="청정마트", seller_type="merchant")
    override_current_user(admin)
    override_db(_users_db(buyer, seller_user))

    response = client.get("/admin/users", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    by_email = {item["email"]: item for item in response.json()["items"]}
    assert by_email["buyer@mall.local"]["isAdmin"] is False
    assert by_email["buyer@mall.local"]["isBuyer"] is True
    assert by_email["buyer@mall.local"]["isSeller"] is False
    assert by_email["buyer@mall.local"]["sellerStatus"] is None
    assert by_email["buyer@mall.local"]["sellerName"] is None
    assert by_email["shop@mall.local"]["sellerStatus"] == "active"
    assert by_email["shop@mall.local"]["sellerName"] == "청정마트"
    assert by_email["shop@mall.local"]["isSeller"] is True


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


def test_update_user_names_and_roles(client):
    admin = make_user(is_admin=True)
    target = make_user(email="shop@mall.local", display_name="옛구매", is_admin=False)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    mock_db.scalar.return_value = None
    override_db(mock_db)

    response = client.patch(
        f"/admin/users/{target.id}",
        json={
            "displayName": "  구매자이름  ",
            "sellerName": "청정마트",
            "isBuyer": True,
            "isSeller": True,
            "isAdmin": False,
        },
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 200
    body = response.json()
    assert target.display_name == "구매자이름"
    assert body["displayName"] == "구매자이름"
    assert body["sellerName"] == "청정마트"
    assert body["isBuyer"] is True
    assert body["isSeller"] is True
    assert body["isAdmin"] is False
    assert body["sellerStatus"] == "active"


def test_update_user_revokes_seller_soft(client):
    admin = make_user(is_admin=True)
    target = make_user(email="shop@mall.local")
    seller = MagicMock()
    seller.id = uuid.uuid4()
    seller.status = "active"
    seller.shop_name = "청정마트"
    seller.seller_type = "merchant"
    target.seller = seller
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    with patch("app.services.admin_users.remove_seller") as mock_remove:
        def _remove(_db, _seller_id, _admin, _reason):
            seller.status = "removed"
            return seller

        mock_remove.side_effect = _remove
        response = client.patch(
            f"/admin/users/{target.id}",
            json={"isSeller": False},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    mock_remove.assert_called_once()
    assert response.json()["isSeller"] is False
    assert response.json()["sellerStatus"] == "removed"
    assert response.json()["sellerName"] == "청정마트"


def test_update_user_restores_removed_seller(client):
    admin = make_user(is_admin=True)
    target = make_user(email="shop@mall.local")
    seller = MagicMock()
    seller.id = uuid.uuid4()
    seller.status = "removed"
    seller.shop_name = "청정마트"
    seller.seller_type = "merchant"
    target.seller = seller
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    with patch("app.services.admin_users.restore_seller") as mock_restore:
        def _restore(_db, _seller_id, _admin, _reason):
            seller.status = "active"
            return seller

        mock_restore.side_effect = _restore
        response = client.patch(
            f"/admin/users/{target.id}",
            json={"isSeller": True},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    mock_restore.assert_called_once()
    assert response.json()["isSeller"] is True
    assert response.json()["sellerStatus"] == "active"


def test_update_user_rejects_self_admin_strip(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = admin
    override_db(mock_db)

    response = client.patch(
        f"/admin/users/{admin.id}",
        json={"isAdmin": False},
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 400
    assert "자기 자신" in response.json()["detail"]
    assert admin.is_admin is True


def test_update_user_rejects_last_admin_demotion(client):
    admin = make_user(is_admin=True)
    target = make_user(email="other-admin@mall.local", is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    with patch("app.services.admin_users.count_admins", return_value=1):
        response = client.patch(
            f"/admin/users/{target.id}",
            json={"isAdmin": False},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 400
    assert "마지막 관리자" in response.json()["detail"]
    assert target.is_admin is True


def test_update_user_rejects_platform_seller_revoke(client):
    admin = make_user(is_admin=True)
    target = make_user(email="official@mall.local")
    seller = MagicMock()
    seller.id = uuid.uuid4()
    seller.status = "active"
    seller.shop_name = "Shopping Mall 공식"
    seller.seller_type = "platform"
    target.seller = seller
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    response = client.patch(
        f"/admin/users/{target.id}",
        json={"isSeller": False},
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 400
    assert "공식 스토어" in response.json()["detail"]
    assert seller.status == "active"


def test_update_user_revokes_buyer(client):
    admin = make_user(is_admin=True)
    target = make_user(email="buyer@mall.local", is_buyer=True)
    override_current_user(admin)
    mock_db = MagicMock()
    mock_db.get.return_value = target
    override_db(mock_db)

    response = client.patch(
        f"/admin/users/{target.id}",
        json={"isBuyer": False},
        headers={"Authorization": "Bearer fake"},
    )

    assert response.status_code == 200
    assert target.is_buyer is False
    assert response.json()["isBuyer"] is False


def test_assert_buyer_rejects_revoked_buyer():
    from app.deps import assert_buyer

    with pytest.raises(HTTPException) as exc_info:
        assert_buyer(make_user(is_buyer=False))
    assert exc_info.value.status_code == 403
    assert "구매자 권한" in exc_info.value.detail
