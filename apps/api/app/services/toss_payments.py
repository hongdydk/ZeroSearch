import base64
import uuid
from datetime import UTC, datetime
from typing import Any

import httpx
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.config import Settings
from app.models import CartItem, Order, OrderItem, PaymentIntent, Product, User
from app.schemas.order import OrderResponse
from app.schemas.payment import TossPaymentStatusResponse, TossPrepareResponse
from app.services.orders import (
    _order_response,
    create_paid_order_from_snapshot,
    reserve_snapshot_stock,
)


class TossProviderError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class TossClient:
    base_url = "https://api.tosspayments.com/v1"

    def __init__(self, secret_key: str, timeout: float = 10.0):
        encoded = base64.b64encode(f"{secret_key}:".encode()).decode()
        self._headers = {
            "Authorization": f"Basic {encoded}",
            "Content-Type": "application/json",
        }
        self._timeout = timeout

    def confirm(
        self, *, payment_key: str, order_id: str, amount: int, idempotency_key: str
    ) -> dict[str, Any]:
        try:
            response = httpx.post(
                f"{self.base_url}/payments/confirm",
                headers={**self._headers, "Idempotency-Key": idempotency_key},
                json={"paymentKey": payment_key, "orderId": order_id, "amount": amount},
                timeout=self._timeout,
            )
        except httpx.TimeoutException:
            payment = self.get(payment_key)
            if payment.get("status") == "DONE":
                return payment
            raise TossProviderError("TOSS_TIMEOUT", "결제 승인 결과를 확인하지 못했습니다.")
        return self._response(response)

    def get(self, payment_key: str) -> dict[str, Any]:
        response = httpx.get(
            f"{self.base_url}/payments/{payment_key}",
            headers=self._headers,
            timeout=self._timeout,
        )
        return self._response(response)

    def cancel(self, payment_key: str, reason: str) -> dict[str, Any]:
        response = httpx.post(
            f"{self.base_url}/payments/{payment_key}/cancel",
            headers={**self._headers, "Idempotency-Key": str(uuid.uuid4())},
            json={"cancelReason": reason},
            timeout=self._timeout,
        )
        return self._response(response)

    @staticmethod
    def _response(response: httpx.Response) -> dict[str, Any]:
        data = response.json()
        if response.is_error:
            raise TossProviderError(
                str(data.get("code", "TOSS_ERROR")),
                str(data.get("message", "토스 결제 요청에 실패했습니다.")),
            )
        return data


def toss_client(settings: Settings) -> TossClient:
    if not settings.toss_secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="토스 결제가 설정되지 않았습니다.",
        )
    return TossClient(settings.toss_secret_key, settings.toss_api_timeout)


def prepare_payment(
    db: Session,
    user: User,
    settings: Settings,
    *,
    idempotency_key: str | None,
) -> TossPrepareResponse:
    if not settings.toss_client_key or not settings.toss_secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="토스 결제가 설정되지 않았습니다.",
        )
    key = idempotency_key.strip() if idempotency_key else None
    if key and len(key) > 64:
        raise HTTPException(status_code=400, detail="Idempotency-Key는 64자 이하여야 합니다.")
    if key:
        existing = db.scalar(
            select(PaymentIntent).where(
                PaymentIntent.user_id == user.id,
                PaymentIntent.idempotency_key == key,
            )
        )
        if existing:
            return _prepare_response(existing, user, settings.toss_client_key)

    cart_items = list(
        db.scalars(
            select(CartItem)
            .where(CartItem.user_id == user.id)
            .options(joinedload(CartItem.product).joinedload(Product.seller))
        ).all()
    )
    if not cart_items:
        raise HTTPException(status_code=400, detail="장바구니가 비어 있습니다.")

    snapshot: list[dict[str, Any]] = []
    for item in cart_items:
        product = item.product
        if (
            product.status != "published"
            or product.seller.status != "active"
            or product.stock < item.qty
        ):
            raise HTTPException(
                status_code=400, detail=f"'{product.title}'은(는) 구매할 수 없습니다."
            )
        snapshot.append(
            {
                "productId": str(product.id),
                "sellerId": str(product.seller_id),
                "title": product.title,
                "qty": item.qty,
                "unitPrice": product.price_credits,
            }
        )

    amount = sum(item["unitPrice"] * item["qty"] for item in snapshot)
    first_title = str(snapshot[0]["title"])
    order_name = first_title if len(snapshot) == 1 else f"{first_title} 외 {len(snapshot) - 1}건"
    intent = PaymentIntent(
        user_id=user.id,
        provider_order_id=f"zs_{uuid.uuid4().hex}",
        idempotency_key=key,
        amount=amount,
        order_name=order_name[:100],
        cart_snapshot=snapshot,
        status="ready",
    )
    db.add(intent)
    db.flush()
    return _prepare_response(intent, user, settings.toss_client_key)


def confirm_payment(
    db: Session,
    user: User,
    client: TossClient,
    *,
    payment_key: str,
    provider_order_id: str,
    amount: int,
) -> OrderResponse:
    intent = _locked_intent(db, provider_order_id)
    if intent is None or intent.user_id != user.id:
        raise HTTPException(status_code=404, detail="결제 요청을 찾을 수 없습니다.")
    if intent.status == "paid" and intent.order_id:
        order = _load_order(db, intent.order_id)
        return _order_response(order)
    if intent.status in {"cancelled", "expired"}:
        raise HTTPException(status_code=409, detail="이미 종료된 결제입니다.")
    if intent.amount != amount:
        raise HTTPException(status_code=400, detail="결제 금액이 일치하지 않습니다.")
    if intent.payment_key and intent.payment_key != payment_key:
        raise HTTPException(status_code=409, detail="결제 키가 일치하지 않습니다.")

    intent.payment_key = payment_key
    intent.status = "confirming"
    charged = False
    try:
        reserve_snapshot_stock(db, intent.cart_snapshot)
        provider = client.confirm(
            payment_key=payment_key,
            order_id=provider_order_id,
            amount=amount,
            idempotency_key=str(intent.id),
        )
        if provider.get("status") == "DONE":
            charged = True
        if (
            provider.get("status") != "DONE"
            or provider.get("orderId") != provider_order_id
            or int(provider.get("totalAmount", 0)) != amount
        ):
            raise TossProviderError("INVALID_PAYMENT", "토스 승인 결과가 일치하지 않습니다.")
        order = create_paid_order_from_snapshot(
            db,
            user,
            intent.cart_snapshot,
            idempotency_key=provider_order_id,
        )
        intent.order_id = order.id
        intent.status = "paid"
        intent.approved_at = datetime.now(UTC)
        return _order_response(order)
    except (TossProviderError, HTTPException) as exc:
        _abandon_confirm(
            db,
            client,
            provider_order_id,
            payment_key,
            charged=charged,
            exc=exc,
        )
        if isinstance(exc, HTTPException):
            raise
        raise HTTPException(status_code=502, detail=exc.message) from exc


def reconcile_webhook(
    db: Session,
    client: TossClient,
    *,
    provider_order_id: str,
    payment_key: str,
) -> None:
    provider = client.get(payment_key)
    if provider.get("orderId") != provider_order_id:
        return
    intent = _locked_intent(db, provider_order_id)
    if intent is None or intent.status == "paid":
        return
    intent.payment_key = payment_key
    provider_status = str(provider.get("status", ""))
    if provider_status == "DONE":
        if int(provider.get("totalAmount", 0)) != intent.amount:
            client.cancel(payment_key, "결제 금액 불일치")
            intent.status = "cancelled"
            intent.failure_code = "AMOUNT_MISMATCH"
            intent.failure_message = "결제 금액 불일치로 자동 취소"
            return
        try:
            reserve_snapshot_stock(db, intent.cart_snapshot)
            user = db.get(User, intent.user_id)
            if user is None:
                raise HTTPException(status_code=404, detail="사용자를 찾을 수 없습니다.")
            order = create_paid_order_from_snapshot(
                db, user, intent.cart_snapshot, idempotency_key=provider_order_id
            )
            intent.order_id = order.id
            intent.status = "paid"
            intent.approved_at = datetime.now(UTC)
        except Exception:
            db.rollback()
            try:
                client.cancel(payment_key, "주문 확정 실패로 자동 취소")
            except TossProviderError:
                pass
            cancelled = _locked_intent(db, provider_order_id)
            if cancelled and cancelled.status != "paid":
                cancelled.payment_key = payment_key
                cancelled.status = "cancelled"
                cancelled.failure_code = "LOCAL_FINALIZE_FAILED"
                cancelled.failure_message = "주문 확정 실패로 자동 취소"
    elif provider_status in {"CANCELED", "PARTIAL_CANCELED"}:
        intent.status = "cancelled"
    elif provider_status in {"EXPIRED", "ABORTED"}:
        intent.status = "expired"


def payment_status(db: Session, user: User, provider_order_id: str) -> TossPaymentStatusResponse:
    intent = db.scalar(
        select(PaymentIntent).where(
            PaymentIntent.provider_order_id == provider_order_id,
            PaymentIntent.user_id == user.id,
        )
    )
    if intent is None:
        raise HTTPException(status_code=404, detail="결제 요청을 찾을 수 없습니다.")
    return TossPaymentStatusResponse(
        order_id=intent.provider_order_id,
        status=intent.status,
        local_order_id=str(intent.order_id) if intent.order_id else None,
        failure_message=intent.failure_message,
        updated_at=intent.updated_at,
    )


def _prepare_response(
    intent: PaymentIntent, user: User, client_key: str
) -> TossPrepareResponse:
    return TossPrepareResponse(
        order_id=intent.provider_order_id,
        amount=intent.amount,
        order_name=intent.order_name,
        client_key=client_key,
        customer_key=f"user_{str(user.id).replace('-', '')}",
    )


def _abandon_confirm(
    db: Session,
    client: TossClient,
    provider_order_id: str,
    payment_key: str,
    *,
    charged: bool,
    exc: Exception,
) -> None:
    if charged:
        try:
            client.cancel(payment_key, "주문 확정 실패로 자동 취소")
        except TossProviderError:
            pass
    db.rollback()
    failed = _locked_intent(db, provider_order_id)
    if failed is None or failed.status == "paid":
        return
    failed.payment_key = payment_key
    failed.status = "cancelled" if charged else "failed"
    if isinstance(exc, TossProviderError):
        failed.failure_code = exc.code
        failed.failure_message = exc.message
    elif isinstance(exc, HTTPException):
        failed.failure_code = "LOCAL_FINALIZE_FAILED"
        failed.failure_message = str(exc.detail)
    else:
        failed.failure_code = "LOCAL_FINALIZE_FAILED"
        failed.failure_message = str(exc)
    db.commit()


def _locked_intent(db: Session, provider_order_id: str) -> PaymentIntent | None:
    return db.scalar(
        select(PaymentIntent)
        .where(PaymentIntent.provider_order_id == provider_order_id)
        .with_for_update()
    )


def _load_order(db: Session, order_id: uuid.UUID) -> Order:
    order = db.scalar(
        select(Order)
        .where(Order.id == order_id)
        .options(joinedload(Order.items).joinedload(OrderItem.seller))
    )
    if order is None:
        raise HTTPException(status_code=500, detail="주문을 찾을 수 없습니다.")
    return order
