from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

PaymentStatus = Literal["ready", "confirming", "paid", "failed", "cancelled", "expired"]


class TossPrepareResponse(BaseModel):
    order_id: str = Field(alias="orderId")
    amount: int
    order_name: str = Field(alias="orderName")
    client_key: str = Field(alias="clientKey")
    customer_key: str = Field(alias="customerKey")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class TossConfirmRequest(BaseModel):
    payment_key: str = Field(alias="paymentKey", min_length=1, max_length=200)
    order_id: str = Field(alias="orderId", min_length=6, max_length=64)
    amount: int = Field(gt=0)

    model_config = {"populate_by_name": True}


class TossPaymentStatusResponse(BaseModel):
    order_id: str = Field(alias="orderId")
    status: PaymentStatus
    local_order_id: str | None = Field(default=None, alias="localOrderId")
    failure_message: str | None = Field(default=None, alias="failureMessage")
    updated_at: datetime = Field(alias="updatedAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class TossWebhookRequest(BaseModel):
    event_type: str = Field(alias="eventType")
    data: dict[str, Any]

    model_config = {"populate_by_name": True}
