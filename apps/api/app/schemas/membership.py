from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

SubscriptionStatus = Literal["active", "cancelled", "expired"]


class MembershipPlanResponse(BaseModel):
    id: str
    slug: str
    name: str
    price_credits: int = Field(alias="priceCredits")
    interval: str

    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class MembershipPlanListResponse(BaseModel):
    items: list[MembershipPlanResponse]

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class SubscribeRequest(BaseModel):
    plan_slug: str = Field(alias="planSlug")

    model_config = {"populate_by_name": True}


class SubscriptionResponse(BaseModel):
    id: str
    plan_slug: str = Field(alias="planSlug")
    plan_name: str = Field(alias="planName")
    status: SubscriptionStatus
    current_period_end: datetime = Field(alias="currentPeriodEnd")
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class MembershipResponse(BaseModel):
    subscription: SubscriptionResponse | None = None

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}
