from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.cart import CartAddRequest, CartRemoveRequest, CartResponse, CartUpdateRequest
from app.services.cart import add_to_cart, get_cart, remove_from_cart, update_cart_item

router = APIRouter(prefix="/me/cart", tags=["cart"])


@router.get("", response_model=CartResponse)
def read_cart(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CartResponse:
    return get_cart(db, current_user)


@router.post("", response_model=CartResponse, status_code=status.HTTP_201_CREATED)
def create_cart_item(
    payload: CartAddRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CartResponse:
    cart = add_to_cart(db, current_user, payload.product_id, payload.qty)
    db.commit()
    return cart


@router.put("", response_model=CartResponse)
def update_cart(
    payload: CartUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CartResponse:
    cart = update_cart_item(db, current_user, payload.product_id, payload.qty)
    db.commit()
    return cart


@router.delete("", response_model=CartResponse)
def delete_cart_item(
    payload: CartRemoveRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CartResponse:
    cart = remove_from_cart(db, current_user, payload.product_id)
    db.commit()
    return cart
