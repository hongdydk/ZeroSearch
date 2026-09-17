from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


IntakeKind = Literal["offer", "card"]
IntakeDraftStatus = Literal["pending", "attached", "promoted"]


class SellerCardDraftCreateRequest(BaseModel):
    manufacturer: str = Field(min_length=1, max_length=200)
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=120)
    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)
    flavor: str | None = Field(default=None, max_length=50)
    option_label: str | None = Field(default=None, alias="optionLabel", max_length=100)
    volume_ml: int | None = Field(default=None, alias="volumeMl", gt=0)
    description: str | None = None
    price_credits: int = Field(alias="priceCredits", gt=0)
    stock: int = Field(ge=0)

    model_config = {"populate_by_name": True}


class CatalogIntakeItem(BaseModel):
    id: str
    kind: IntakeKind
    status: IntakeDraftStatus
    seller_id: str = Field(alias="sellerId")
    shop_name: str = Field(alias="shopName")
    catalog_product_id: str | None = Field(default=None, alias="catalogProductId")
    manufacturer: str = ""
    title: str
    category: str
    image_url: str | None = Field(default=None, alias="imageUrl")
    flavor: str | None = None
    option_label: str | None = Field(default=None, alias="optionLabel")
    volume_ml: int | None = Field(default=None, alias="volumeMl")
    description: str | None = None
    price_credits: int = Field(alias="priceCredits")
    stock: int
    created_at: datetime | None = Field(default=None, alias="createdAt")
    suggested_l1_tags: list[dict] = Field(default_factory=list, alias="suggestedL1Tags")
    l1_tags: list[str] = Field(default_factory=list, alias="l1Tags")

    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}

    @field_validator("id", "seller_id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)

    @field_validator("catalog_product_id", mode="before")
    @classmethod
    def coerce_optional_id(cls, value: UUID | str | None) -> str | None:
        if value is None:
            return None
        return str(value)


class CatalogIntakeListResponse(BaseModel):
    items: list[CatalogIntakeItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminAttachDraftRequest(BaseModel):
    kind: IntakeKind
    catalog_product_id: str | None = Field(default=None, alias="catalogProductId")

    model_config = {"populate_by_name": True}


class AdminPromoteDraftRequest(BaseModel):
    category: str = Field(min_length=1, max_length=120)
    manufacturer: str | None = Field(default=None, max_length=200)
    title: str | None = Field(default=None, max_length=200)
    l1_tags: list[str] | None = Field(default=None, alias="l1Tags")
    storage: str | None = None

    model_config = {"populate_by_name": True}
