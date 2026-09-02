import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import Seller
from app.schemas.seller import SellerResponse
from tests.factories import make_user, override_current_user, override_db


def _sample_seller(**kwargs) -> Seller:
    seller = Seller(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        shop_name="입점 스토어",
        slug="merchant-shop",
        status="pending",
        seller_type="merchant",
    )
    seller.created_at = datetime.now(UTC)
    for key, value in kwargs.items():
        setattr(seller, key, value)
    return seller


def test_seller_apply_conflict(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    with patch(
        "app.routers.seller.apply_for_seller",
        side_effect=HTTPException(status_code=409, detail="이미 입점 신청이 접수되었습니다."),
    ):
        response = client.post(
            "/seller/apply",
            json={"shopName": "내 스토어"},
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 409


def test_seller_me_none(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())

    with patch("app.routers.seller.get_seller_for_user", return_value=None):
        response = client.get("/seller/me", headers={"Authorization": "Bearer fake"})

    assert response.status_code == 200
    assert response.json() is None


def test_admin_approve_seller(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    mock_db = MagicMock()
    override_db(mock_db)

    seller = _sample_seller(status="active")
    user = make_user(email="merchant@test.local")
    mock_db.get.return_value = user

    with patch("app.routers.admin.approve_seller", return_value=seller):
        response = client.post(
            f"/admin/sellers/{seller.id}/approve",
            headers={"Authorization": "Bearer fake"},
        )

    assert response.status_code == 200
    assert response.json()["status"] == "active"
