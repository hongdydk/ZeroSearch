from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.models import ShippingAddress, User
from app.schemas.address import (
    ShippingAddressCreateRequest,
    ShippingAddressListResponse,
    ShippingAddressResponse,
    ShippingAddressUpdateRequest,
    ShippingSnapshot,
)

MAX_ADDRESSES = 10


def snapshot_from_address(address: ShippingAddress) -> dict:
    return ShippingSnapshot(
        recipient_name=address.recipient_name,
        phone=address.phone,
        zonecode=address.zonecode,
        address=address.address,
        detail_address=address.detail_address,
    ).model_dump(by_alias=True)


def _response(address: ShippingAddress) -> ShippingAddressResponse:
    return ShippingAddressResponse(
        id=str(address.id),
        recipient_name=address.recipient_name,
        phone=address.phone,
        zonecode=address.zonecode,
        address=address.address,
        detail_address=address.detail_address,
        is_default=address.is_default,
        created_at=address.created_at,
    )


def list_addresses(db: Session, user: User) -> ShippingAddressListResponse:
    rows = list(
        db.scalars(
            select(ShippingAddress)
            .where(ShippingAddress.user_id == user.id)
            .order_by(ShippingAddress.is_default.desc(), ShippingAddress.created_at.desc())
        ).all()
    )
    return ShippingAddressListResponse(items=[_response(row) for row in rows])


def get_owned_address(db: Session, user: User, address_id: UUID) -> ShippingAddress:
    address = db.scalar(
        select(ShippingAddress).where(
            ShippingAddress.id == address_id,
            ShippingAddress.user_id == user.id,
        )
    )
    if address is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="배송지를 찾을 수 없습니다.")
    return address


def _count(db: Session, user_id: UUID) -> int:
    return db.scalar(
        select(func.count()).select_from(ShippingAddress).where(ShippingAddress.user_id == user_id)
    ) or 0


def _clear_defaults(db: Session, user_id: UUID) -> None:
    db.execute(
        update(ShippingAddress)
        .where(ShippingAddress.user_id == user_id, ShippingAddress.is_default.is_(True))
        .values(is_default=False)
    )


def create_address(
    db: Session, user: User, payload: ShippingAddressCreateRequest
) -> ShippingAddressResponse:
    count = _count(db, user.id)
    if count >= MAX_ADDRESSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"배송지는 최대 {MAX_ADDRESSES}개까지 저장할 수 있습니다.",
        )
    make_default = payload.is_default or count == 0
    if make_default:
        _clear_defaults(db, user.id)
    address = ShippingAddress(
        user_id=user.id,
        recipient_name=payload.recipient_name,
        phone=payload.phone,
        zonecode=payload.zonecode,
        address=payload.address,
        detail_address=payload.detail_address,
        is_default=make_default,
    )
    db.add(address)
    db.flush()
    return _response(address)


def update_address(
    db: Session,
    user: User,
    address_id: UUID,
    payload: ShippingAddressUpdateRequest,
) -> ShippingAddressResponse:
    address = get_owned_address(db, user, address_id)
    data = payload.model_dump(exclude_unset=True)
    make_default = data.pop("is_default", None)
    for field, value in data.items():
        setattr(address, field, value)
    if make_default:
        _clear_defaults(db, user.id)
        address.is_default = True
    elif make_default is False and address.is_default:
        address.is_default = False
    db.flush()
    return _response(address)


def delete_address(db: Session, user: User, address_id: UUID) -> ShippingAddressListResponse:
    address = get_owned_address(db, user, address_id)
    was_default = address.is_default
    db.delete(address)
    db.flush()
    if was_default:
        next_default = db.scalar(
            select(ShippingAddress)
            .where(ShippingAddress.user_id == user.id)
            .order_by(ShippingAddress.created_at.desc())
        )
        if next_default is not None:
            next_default.is_default = True
            db.flush()
    return list_addresses(db, user)
