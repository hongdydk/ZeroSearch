import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.models import Seller, SellerModerationEvent
from app.services.sellers import (
    list_all_moderation_events,
    remove_seller,
    restore_seller,
    suspend_seller,
    unsuspend_seller,
    warn_seller,
)
from tests.factories import make_user, override_current_user, override_db


def _seller(**kwargs) -> Seller:
    seller = Seller(
        id=kwargs.get("id") or uuid.uuid4(),
        user_id=kwargs.get("user_id") or uuid.uuid4(),
        shop_name=kwargs.get("shop_name", "입점마트"),
        slug=kwargs.get("slug", "merchant-shop"),
        status=kwargs.get("status", "active"),
        seller_type=kwargs.get("seller_type", "merchant"),
    )
    seller.created_at = datetime.now(UTC)
    return seller


def test_warn_keeps_active_and_records_reason():
    seller = _seller(status="active")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    result = warn_seller(db, seller.id, admin, " 허위 재고 ")

    assert result.status == "active"
    db.add.assert_called_once()
    event = db.add.call_args.args[0]
    assert isinstance(event, SellerModerationEvent)
    assert event.action == "warn"
    assert event.reason == "허위 재고"
    assert event.seller_id == seller.id
    assert event.admin_user_id == admin.id


def test_warn_requires_reason():
    seller = _seller()
    db = MagicMock()
    db.get.return_value = seller
    with pytest.raises(HTTPException) as exc:
        warn_seller(db, seller.id, make_user(is_admin=True), "   ")
    assert exc.value.status_code == 400
    db.add.assert_not_called()


def test_suspend_from_active_hides_seller():
    seller = _seller(status="active")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    result = suspend_seller(db, seller.id, admin, "반복 품절")

    assert result.status == "suspended"
    event = db.add.call_args.args[0]
    assert event.action == "suspend"
    assert event.reason == "반복 품절"


def test_suspend_platform_forbidden():
    seller = _seller(seller_type="platform")
    db = MagicMock()
    db.get.return_value = seller
    with pytest.raises(HTTPException) as exc:
        suspend_seller(db, seller.id, make_user(is_admin=True), "테스트")
    assert exc.value.status_code == 400
    assert seller.status == "active"


def test_unsuspend_restores_active():
    seller = _seller(status="suspended")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    result = unsuspend_seller(db, seller.id, admin, "시정 확인")

    assert result.status == "active"
    assert db.add.call_args.args[0].action == "unsuspend"


def test_unsuspend_not_from_removed():
    seller = _seller(status="removed")
    db = MagicMock()
    db.get.return_value = seller
    with pytest.raises(HTTPException) as exc:
        unsuspend_seller(db, seller.id, make_user(is_admin=True), "복구")
    assert exc.value.status_code == 409
    assert seller.status == "removed"


def test_remove_from_suspended_is_soft_delete():
    seller = _seller(status="suspended")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    result = remove_seller(db, seller.id, admin, "약관 위반")

    assert result.status == "removed"
    db.delete.assert_not_called()
    assert db.add.call_args.args[0].action == "remove"


def test_remove_from_active_allowed():
    seller = _seller(status="active")
    db = MagicMock()
    db.get.return_value = seller
    result = remove_seller(db, seller.id, make_user(is_admin=True), "장기 미운영")
    assert result.status == "removed"


def test_restore_from_removed_sets_active():
    seller = _seller(status="removed")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    result = restore_seller(db, seller.id, admin, "관리자가 판매자 역할을 부여함")

    assert result.status == "active"
    assert db.add.call_args.args[0].action == "restore"


def test_restore_not_from_active():
    seller = _seller(status="active")
    db = MagicMock()
    db.get.return_value = seller
    with pytest.raises(HTTPException) as exc:
        restore_seller(db, seller.id, make_user(is_admin=True), "복구")
    assert exc.value.status_code == 409
    assert seller.status == "active"


def test_remove_platform_forbidden():
    seller = _seller(seller_type="platform")
    db = MagicMock()
    db.get.return_value = seller
    with pytest.raises(HTTPException) as exc:
        remove_seller(db, seller.id, make_user(is_admin=True), "안됨")
    assert exc.value.status_code == 400


def test_warn_then_suspend_then_remove_sequence():
    seller = _seller(status="active")
    admin = make_user(is_admin=True)
    db = MagicMock()
    db.get.return_value = seller

    warn_seller(db, seller.id, admin, "1차 경고")
    assert seller.status == "active"
    suspend_seller(db, seller.id, admin, "2차 정지")
    assert seller.status == "suspended"
    remove_seller(db, seller.id, admin, "3차 해제")
    assert seller.status == "removed"
    assert db.add.call_count == 3
    actions = [call.args[0].action for call in db.add.call_args_list]
    assert actions == ["warn", "suspend", "remove"]


def test_admin_suspend_endpoint_requires_reason(client):
    override_current_user(make_user(is_admin=True))
    override_db(MagicMock())
    response = client.post(
        f"/admin/sellers/{uuid.uuid4()}/suspend",
        json={},
        headers={"Authorization": "Bearer fake"},
    )
    assert response.status_code == 422


def test_admin_warn_endpoint(client):
    admin = make_user(is_admin=True)
    override_current_user(admin)
    seller = _seller(status="active")
    mock_db = MagicMock()
    mock_db.get.return_value = make_user(email="shop@mall.local")
    override_db(mock_db)
    with (
        patch("app.routers.admin.warn_seller", return_value=seller),
        patch("app.routers.admin._moderation_summaries", return_value={seller.id: (1, "warn", "허위 재고")}),
    ):
        response = client.post(
            f"/admin/sellers/{seller.id}/warn",
            json={"reason": "허위 재고"},
            headers={"Authorization": "Bearer fake"},
        )
    assert response.status_code == 200
    assert response.json()["status"] == "active"
    assert response.json()["warningCount"] == 1
    assert response.json()["lastModerationAction"] == "warn"


def test_list_all_moderation_events_limits_newest_rows():
    db = MagicMock()
    result = list_all_moderation_events(db, limit=25)
    sql = str(db.scalars.call_args.args[0]).lower()
    assert "seller_moderation_events" in sql
    assert "limit" in sql
    assert result == list(db.scalars.return_value.all.return_value)


def test_admin_audit_endpoint_returns_events_with_seller_name(client):
    admin = make_user(is_admin=True)
    seller = _seller(shop_name="한결마트")
    event = SellerModerationEvent(
        id=uuid.uuid4(), seller_id=seller.id, admin_user_id=admin.id, action="warn", reason="재고 확인"
    )
    event.created_at = datetime.now(UTC)
    mock_db = MagicMock()
    mock_db.get.side_effect = lambda model, value: admin if value == admin.id else seller
    override_current_user(admin)
    override_db(mock_db)
    with patch("app.routers.admin.list_all_moderation_events", return_value=[event]):
        response = client.get("/admin/audit", headers={"Authorization": "Bearer fake"})
    assert response.status_code == 200
    assert response.json()["items"][0]["shopName"] == "한결마트"
