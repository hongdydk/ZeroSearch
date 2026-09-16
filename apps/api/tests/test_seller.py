import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import Seller
from app.schemas.seller import SellerResponse
from app.services.sellers import PLATFORM_SLUG, ensure_platform_seller
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


def test_ensure_platform_seller_returns_existing_platform():
    admin = make_user(is_admin=True)
    platform = _sample_seller(
        user_id=admin.id,
        shop_name="Shopping Mall 공식",
        slug=PLATFORM_SLUG,
        status="active",
        seller_type="platform",
    )
    db = MagicMock()
    db.scalar.return_value = platform

    result = ensure_platform_seller(db, admin)

    assert result is platform
    db.add.assert_not_called()
    db.flush.assert_called_once()


def test_ensure_platform_seller_promotes_admin_merchant_instead_of_insert():
    admin = make_user(is_admin=True)
    merchant = _sample_seller(user_id=admin.id, slug="admin-shop", status="active")
    db = MagicMock()
    db.scalar.side_effect = [None, merchant]

    result = ensure_platform_seller(db, admin)

    assert result is merchant
    assert merchant.seller_type == "platform"
    assert merchant.status == "active"
    db.add.assert_not_called()
    db.flush.assert_called_once()


def test_ensure_platform_seller_does_not_reassign_when_admin_already_has_seller():
    admin = make_user(is_admin=True)
    other_user_id = uuid.uuid4()
    platform = _sample_seller(
        user_id=other_user_id,
        shop_name="Shopping Mall 공식",
        slug=PLATFORM_SLUG,
        status="active",
        seller_type="platform",
    )
    owned = _sample_seller(user_id=admin.id, slug="admin-shop", status="active")
    db = MagicMock()
    db.scalar.side_effect = [platform, owned]

    result = ensure_platform_seller(db, admin)

    assert result is platform
    assert platform.user_id == other_user_id
    db.add.assert_not_called()


def test_ensure_platform_seller_inserts_when_missing():
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.scalar.return_value = None

    result = ensure_platform_seller(db, admin)

    db.add.assert_called_once()
    added = db.add.call_args[0][0]
    assert added is result
    assert added.user_id == admin.id
    assert added.slug == PLATFORM_SLUG
    assert added.seller_type == "platform"
    db.flush.assert_called_once()


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
