from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas.order import CheckoutResponse
from app.schemas.address import TossPrepareRequest
from app.schemas.payment import (
    TossConfirmRequest,
    TossPaymentStatusResponse,
    TossPrepareResponse,
    TossWebhookRequest,
)
from app.services.toss_payments import (
    confirm_payment,
    payment_status,
    prepare_payment,
    reconcile_webhook,
    toss_client,
)

router = APIRouter(prefix="/payments/toss", tags=["payments"])


@router.post("/prepare", response_model=TossPrepareResponse)
def prepare_toss_payment(
    payload: TossPrepareRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> TossPrepareResponse:
    result = prepare_payment(
        db,
        current_user,
        get_settings(),
        idempotency_key=idempotency_key,
        address_id=payload.address_id,
    )
    db.commit()
    return result


@router.post("/confirm", response_model=CheckoutResponse)
def confirm_toss_payment(
    payload: TossConfirmRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> CheckoutResponse:
    order = confirm_payment(
        db,
        current_user,
        toss_client(get_settings()),
        payment_key=payload.payment_key,
        provider_order_id=payload.order_id,
        amount=payload.amount,
    )
    db.commit()
    return CheckoutResponse(order=order)


@router.post("/webhook", status_code=200)
def toss_payment_webhook(
    payload: TossWebhookRequest,
    db: Annotated[Session, Depends(get_db)],
) -> dict[str, bool]:
    if payload.event_type != "PAYMENT_STATUS_CHANGED":
        return {"ok": True}
    payment_key = payload.data.get("paymentKey")
    order_id = payload.data.get("orderId")
    if not isinstance(payment_key, str) or not isinstance(order_id, str):
        raise HTTPException(status_code=400, detail="결제 식별자가 없습니다.")
    reconcile_webhook(
        db,
        toss_client(get_settings()),
        provider_order_id=order_id,
        payment_key=payment_key,
    )
    db.commit()
    return {"ok": True}


@router.get("/{order_id}", response_model=TossPaymentStatusResponse)
def read_toss_payment(
    order_id: str,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
) -> TossPaymentStatusResponse:
    return payment_status(db, current_user, order_id)
