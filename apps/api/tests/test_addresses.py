import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

from fastapi import HTTPException

from app.schemas.address import ShippingAddressCreateRequest, ShippingAddressUpdateRequest
from app.services import addresses as address_service
from tests.factories import make_user, override_current_user, override_db


def _payload(**overrides) -> ShippingAddressCreateRequest:
    data = {
        "recipientName": "홍길동",
        "phone": "010-1234-5678",
        "zonecode": "12345",
        "address": "서울 강남구 테헤란로 1",
        "detailAddress": "101호",
    }
    data.update(overrides)
    return ShippingAddressCreateRequest.model_validate(data)


def test_list_addresses_requires_auth(client):
    response = client.get("/me/addresses")
    assert response.status_code == 401


def test_create_address_normalizes_phone(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())
    created = MagicMock()
    created.id = uuid.uuid4()
    created.recipient_name = "홍길동"
    created.phone = "01012345678"
    created.zonecode = "12345"
    created.address = "서울 강남구 테헤란로 1"
    created.detail_address = "101호"
    created.is_default = True
    created.created_at = datetime.now(UTC)
    with patch("app.routers.addresses.create_address", return_value=address_service._response(created)):
        response = client.post(
            "/me/addresses",
            headers={"Authorization": "Bearer fake"},
            json=_payload().model_dump(by_alias=True),
        )
    assert response.status_code == 201
    assert response.json()["phone"] == "01012345678"
    assert response.json()["isDefault"] is True


def test_create_caps_at_ten():
    user = make_user()
    db = MagicMock()
    db.scalar.return_value = 10
    try:
        address_service.create_address(db, user, _payload())
        raise AssertionError("expected limit error")
    except HTTPException as exc:
        assert exc.status_code == 400
        assert "10" in exc.detail


def test_create_first_address_is_default():
    user = make_user()
    db = MagicMock()
    db.scalar.return_value = 0
    result = address_service.create_address(db, user, _payload())
    added = db.add.call_args[0][0]
    assert added.is_default is True
    assert result.is_default is True
    assert added.phone == "01012345678"


def test_update_sets_single_default():
    user = make_user()
    address = MagicMock()
    address.id = uuid.uuid4()
    address.user_id = user.id
    address.recipient_name = "홍길동"
    address.phone = "01012345678"
    address.zonecode = "12345"
    address.address = "서울"
    address.detail_address = "101호"
    address.is_default = False
    address.created_at = datetime.now(UTC)
    db = MagicMock()
    db.scalar.return_value = address
    address_service.update_address(
        db,
        user,
        address.id,
        ShippingAddressUpdateRequest.model_validate({"isDefault": True}),
    )
    db.execute.assert_called()
    assert address.is_default is True


def test_foreign_address_is_rejected():
    user = make_user()
    db = MagicMock()
    db.scalar.return_value = None
    try:
        address_service.get_owned_address(db, user, uuid.uuid4())
        raise AssertionError("expected 400")
    except HTTPException as exc:
        assert exc.status_code == 400
