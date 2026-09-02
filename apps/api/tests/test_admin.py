import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.deps import require_admin
from tests.factories import make_user, override_current_user


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
