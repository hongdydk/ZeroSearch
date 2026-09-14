from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.address import (
    ShippingAddressCreateRequest,
    ShippingAddressListResponse,
    ShippingAddressResponse,
    ShippingAddressUpdateRequest,
)
from app.services.addresses import create_address, delete_address, list_addresses, update_address

router = APIRouter(prefix="/me/addresses", tags=["addresses"])


@router.get("", response_model=ShippingAddressListResponse)
def read_addresses(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ShippingAddressListResponse:
    return list_addresses(db, current_user)


@router.post("", response_model=ShippingAddressResponse, status_code=status.HTTP_201_CREATED)
def create_shipping_address(
    payload: ShippingAddressCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ShippingAddressResponse:
    result = create_address(db, current_user, payload)
    db.commit()
    return result


@router.patch("/{address_id}", response_model=ShippingAddressResponse)
def patch_shipping_address(
    address_id: UUID,
    payload: ShippingAddressUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ShippingAddressResponse:
    result = update_address(db, current_user, address_id, payload)
    db.commit()
    return result


@router.delete("/{address_id}", response_model=ShippingAddressListResponse)
def remove_shipping_address(
    address_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> ShippingAddressListResponse:
    result = delete_address(db, current_user, address_id)
    db.commit()
    return result
