import uuid
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.schemas.order import OrderResponse
from app.schemas.payment import TossPaymentStatusResponse, TossPrepareResponse
from app.services import toss_payments
from tests.factories import make_user, override_current_user, override_db


def test_prepare_returns_server_payment_quote(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())
    prepared = TossPrepareResponse(
        order_id="zs_123456",
        amount=12900,
        order_name="농심 백산수",
        client_key="test_ck_public",
        customer_key="user_123",
    )
    with patch("app.routers.payments.prepare_payment", return_value=prepared):
        response = client.post(
            "/payments/toss/prepare",
            headers={"Authorization": "Bearer fake", "Idempotency-Key": "prepare-1"},
        )

    assert response.status_code == 200
    assert response.json()["amount"] == 12900
    assert response.json()["clientKey"] == "test_ck_public"


def test_confirm_returns_paid_order(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())
    order = OrderResponse(
        id=str(uuid.uuid4()),
        status="paid",
        total_credits=12900,
        items=[],
        created_at=datetime.now(UTC),
    )
    with (
        patch("app.routers.payments.toss_client"),
        patch("app.routers.payments.confirm_payment", return_value=order),
    ):
        response = client.post(
            "/payments/toss/confirm",
            headers={"Authorization": "Bearer fake"},
            json={
                "paymentKey": "payment-key",
                "orderId": "zs_123456",
                "amount": 12900,
            },
        )

    assert response.status_code == 200
    assert response.json()["order"]["status"] == "paid"


def test_webhook_reconciliation_uses_server_service(client):
    override_db(MagicMock())
    with (
        patch("app.routers.payments.toss_client"),
        patch("app.routers.payments.reconcile_webhook") as reconcile,
    ):
        response = client.post(
            "/payments/toss/webhook",
            json={
                "eventType": "PAYMENT_STATUS_CHANGED",
                "data": {"paymentKey": "payment-key", "orderId": "zs_123456"},
            },
        )

    assert response.status_code == 200
    reconcile.assert_called_once()


def test_unrelated_webhook_is_acknowledged(client):
    override_db(MagicMock())
    response = client.post(
        "/payments/toss/webhook",
        json={"eventType": "METHOD_UPDATED", "data": {}},
    )
    assert response.status_code == 200


def test_payment_status_is_scoped_to_current_user(client):
    user = make_user()
    override_current_user(user)
    override_db(MagicMock())
    result = TossPaymentStatusResponse(
        order_id="zs_123456",
        status="ready",
        updated_at=datetime.now(UTC),
    )
    with patch("app.routers.payments.payment_status", return_value=result):
        response = client.get(
            "/payments/toss/zs_123456",
            headers={"Authorization": "Bearer fake"},
        )
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


def test_confirm_rejects_client_amount_before_calling_toss():
    user = make_user()
    intent = MagicMock()
    intent.user_id = user.id
    intent.status = "ready"
    intent.amount = 12900
    intent.payment_key = None
    provider = MagicMock()

    with patch.object(toss_payments, "_locked_intent", return_value=intent):
        with pytest.raises(HTTPException) as exc:
            toss_payments.confirm_payment(
                MagicMock(),
                user,
                provider,
                payment_key="payment-key",
                provider_order_id="zs_123456",
                amount=100,
            )

    assert exc.value.status_code == 400
    provider.confirm.assert_not_called()


def test_webhook_cancels_verified_payment_when_amount_differs():
    intent = MagicMock()
    intent.status = "ready"
    intent.amount = 12900
    provider = MagicMock()
    provider.get.return_value = {
        "orderId": "zs_123456",
        "status": "DONE",
        "totalAmount": 100,
    }

    with patch.object(toss_payments, "_locked_intent", return_value=intent):
        toss_payments.reconcile_webhook(
            MagicMock(),
            provider,
            provider_order_id="zs_123456",
            payment_key="payment-key",
        )

    provider.cancel.assert_called_once_with("payment-key", "결제 금액 불일치")
    assert intent.status == "cancelled"
    assert intent.failure_code == "AMOUNT_MISMATCH"


def test_prepare_unavailable_without_keys():
    user = make_user()
    settings = MagicMock(toss_client_key=None, toss_secret_key=None)
    with pytest.raises(HTTPException) as exc:
        toss_payments.prepare_payment(MagicMock(), user, settings, idempotency_key=None)
    assert exc.value.status_code == 503
    assert "설정되지 않았습니다" in exc.value.detail


def test_prepare_quotes_server_cart_total():
    user = make_user()
    settings = MagicMock(toss_client_key="ck", toss_secret_key="sk")
    product = MagicMock()
    product.id = uuid.uuid4()
    product.seller_id = uuid.uuid4()
    product.title = "농심 백산수"
    product.status = "published"
    product.stock = 10
    product.price_credits = 12900
    product.seller.status = "active"
    item = MagicMock(product=product, qty=2)
    db = MagicMock()
    db.scalar.return_value = None
    db.scalars.return_value.all.return_value = [item]

    result = toss_payments.prepare_payment(db, user, settings, idempotency_key="prep-1")

    assert result.amount == 25800
    added = db.add.call_args[0][0]
    assert added.amount == 25800
    assert added.cart_snapshot[0]["unitPrice"] == 12900


def test_prepare_reuses_idempotent_intent():
    user = make_user()
    settings = MagicMock(toss_client_key="ck", toss_secret_key="sk")
    existing = MagicMock()
    existing.provider_order_id = "zs_existing"
    existing.amount = 12900
    existing.order_name = "농심 백산수"
    db = MagicMock()
    db.scalar.return_value = existing

    result = toss_payments.prepare_payment(db, user, settings, idempotency_key="prep-1")

    assert result.order_id == "zs_existing"
    db.add.assert_not_called()


def test_confirm_paid_intent_is_idempotent():
    user = make_user()
    order_id = uuid.uuid4()
    intent = MagicMock()
    intent.user_id = user.id
    intent.status = "paid"
    intent.order_id = order_id
    intent.amount = 12900
    order = OrderResponse(
        id=str(order_id),
        status="paid",
        total_credits=12900,
        items=[],
        created_at=datetime.now(UTC),
    )
    provider = MagicMock()
    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(toss_payments, "_load_order"),
        patch.object(toss_payments, "_order_response", return_value=order),
    ):
        result = toss_payments.confirm_payment(
            MagicMock(),
            user,
            provider,
            payment_key="payment-key",
            provider_order_id="zs_123456",
            amount=12900,
        )

    assert result.status == "paid"
    provider.confirm.assert_not_called()


def test_confirm_rejects_stock_before_toss():
    user = make_user()
    intent = MagicMock()
    intent.id = uuid.uuid4()
    intent.user_id = user.id
    intent.status = "ready"
    intent.amount = 12900
    intent.payment_key = None
    intent.cart_snapshot = []
    provider = MagicMock()

    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(
            toss_payments,
            "reserve_snapshot_stock",
            side_effect=HTTPException(status_code=400, detail="재고가 부족합니다."),
        ),
        patch.object(toss_payments, "_abandon_confirm") as abandon,
    ):
        with pytest.raises(HTTPException) as exc:
            toss_payments.confirm_payment(
                MagicMock(),
                user,
                provider,
                payment_key="payment-key",
                provider_order_id="zs_123456",
                amount=12900,
            )

    assert exc.value.status_code == 400
    provider.confirm.assert_not_called()
    abandon.assert_called_once()
    assert abandon.call_args.kwargs["charged"] is False


def test_confirm_timeout_uses_payment_lookup():
    client = toss_payments.TossClient("test_sk", timeout=0.1)
    with patch("app.services.toss_payments.httpx.post", side_effect=toss_payments.httpx.TimeoutException("t")):
        with patch.object(
            client,
            "get",
            return_value={"status": "DONE", "orderId": "zs_123456", "totalAmount": 12900},
        ) as lookup:
            result = client.confirm(
                payment_key="payment-key",
                order_id="zs_123456",
                amount=12900,
                idempotency_key="idem-1",
            )

    assert result["status"] == "DONE"
    lookup.assert_called_once_with("payment-key")


def test_confirm_timeout_without_done_raises():
    client = toss_payments.TossClient("test_sk", timeout=0.1)
    with patch("app.services.toss_payments.httpx.post", side_effect=toss_payments.httpx.TimeoutException("t")):
        with patch.object(client, "get", return_value={"status": "IN_PROGRESS"}):
            with pytest.raises(toss_payments.TossProviderError) as exc:
                client.confirm(
                    payment_key="payment-key",
                    order_id="zs_123456",
                    amount=12900,
                    idempotency_key="idem-1",
                )
    assert exc.value.code == "TOSS_TIMEOUT"


def test_confirm_cancels_when_local_finalize_fails():
    user = make_user()
    intent = MagicMock()
    intent.id = uuid.uuid4()
    intent.user_id = user.id
    intent.status = "ready"
    intent.amount = 12900
    intent.payment_key = None
    intent.cart_snapshot = []
    provider = MagicMock()
    provider.confirm.return_value = {
        "status": "DONE",
        "orderId": "zs_123456",
        "totalAmount": 12900,
    }

    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(toss_payments, "reserve_snapshot_stock"),
        patch.object(
            toss_payments,
            "create_paid_order_from_snapshot",
            side_effect=HTTPException(status_code=500, detail="주문 생성 실패"),
        ),
    ):
        with pytest.raises(HTTPException):
            toss_payments.confirm_payment(
                MagicMock(),
                user,
                provider,
                payment_key="payment-key",
                provider_order_id="zs_123456",
                amount=12900,
            )

    provider.cancel.assert_called_once_with("payment-key", "주문 확정 실패로 자동 취소")


def test_confirm_success_marks_paid_and_creates_order():
    user = make_user()
    intent = MagicMock()
    intent.id = uuid.uuid4()
    intent.user_id = user.id
    intent.status = "ready"
    intent.amount = 12900
    intent.payment_key = None
    intent.cart_snapshot = [{"productId": str(uuid.uuid4()), "qty": 1}]
    order = MagicMock()
    order.id = uuid.uuid4()
    response = OrderResponse(
        id=str(order.id),
        status="paid",
        total_credits=12900,
        items=[],
        created_at=datetime.now(UTC),
    )
    provider = MagicMock()
    provider.confirm.return_value = {
        "status": "DONE",
        "orderId": "zs_123456",
        "totalAmount": 12900,
    }

    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(toss_payments, "reserve_snapshot_stock") as reserve,
        patch.object(toss_payments, "create_paid_order_from_snapshot", return_value=order),
        patch.object(toss_payments, "_order_response", return_value=response),
    ):
        result = toss_payments.confirm_payment(
            MagicMock(),
            user,
            provider,
            payment_key="payment-key",
            provider_order_id="zs_123456",
            amount=12900,
        )

    reserve.assert_called_once()
    assert intent.status == "paid"
    assert intent.order_id == order.id
    assert result.status == "paid"


def test_webhook_always_reloads_from_toss():
    intent = MagicMock()
    intent.status = "ready"
    intent.amount = 12900
    intent.cart_snapshot = []
    intent.user_id = uuid.uuid4()
    provider = MagicMock()
    provider.get.return_value = {
        "orderId": "zs_123456",
        "status": "DONE",
        "totalAmount": 12900,
    }
    user = make_user()
    order = MagicMock()
    order.id = uuid.uuid4()
    db = MagicMock()
    db.get.return_value = user

    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(toss_payments, "reserve_snapshot_stock"),
        patch.object(toss_payments, "create_paid_order_from_snapshot", return_value=order),
    ):
        toss_payments.reconcile_webhook(
            db,
            provider,
            provider_order_id="zs_123456",
            payment_key="forged-or-real",
        )

    provider.get.assert_called_once_with("forged-or-real")
    assert intent.status == "paid"


def test_duplicate_webhook_does_not_create_another_order():
    intent = MagicMock()
    intent.status = "paid"
    provider = MagicMock()
    provider.get.return_value = {
        "orderId": "zs_123456",
        "status": "DONE",
        "totalAmount": 12900,
    }

    with (
        patch.object(toss_payments, "_locked_intent", return_value=intent),
        patch.object(toss_payments, "create_paid_order_from_snapshot") as create,
    ):
        toss_payments.reconcile_webhook(
            MagicMock(),
            provider,
            provider_order_id="zs_123456",
            payment_key="payment-key",
        )

    create.assert_not_called()
    provider.cancel.assert_not_called()

