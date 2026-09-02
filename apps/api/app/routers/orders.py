from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.order import CheckoutResponse, OrderListResponse, OrderResponse
from app.services.orders import checkout, get_order, list_orders, _order_response

router = APIRouter(prefix="/me/orders", tags=["orders"])


@router.post("", response_model=CheckoutResponse, status_code=status.HTTP_201_CREATED)
def create_order(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CheckoutResponse:
    order = checkout(db, current_user)
    db.commit()
    return CheckoutResponse(order=order)


@router.get("", response_model=OrderListResponse)
def read_orders(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> OrderListResponse:
    orders, total = list_orders(db, current_user, offset=offset, limit=limit)
    return OrderListResponse(
        items=[_order_response(o) for o in orders],
        total=total,
    )


@router.get("/{order_id}", response_model=OrderResponse)
def read_order(
    order_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> OrderResponse:
    order = get_order(db, current_user, order_id)
    return _order_response(order)
