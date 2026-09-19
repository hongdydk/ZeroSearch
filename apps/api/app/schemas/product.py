from datetime import datetime

from typing import Literal

from uuid import UUID



from decimal import Decimal

from pydantic import BaseModel, Field, field_validator



from app.schemas.seller import ProductStatus, SellerSummary



OrderStatus = Literal["pending", "paid", "cancelled"]

FulfillmentStatus = Literal["paid", "preparing", "shipped", "delivered"]





class ProductResponse(BaseModel):

    id: str

    title: str

    description: str | None = None

    price_credits: int = Field(alias="priceCredits")

    stock: int

    category: str

    image_url: str | None = Field(default=None, alias="imageUrl")

    status: ProductStatus = "published"

    catalog_product_id: str = Field(alias="catalogProductId")

    option_label: str | None = Field(default=None, alias="optionLabel")

    volume_ml: int | None = Field(default=None, alias="volumeMl")

    unit_amount: float | None = Field(default=None, alias="unitAmount")

    unit: str | None = None

    pack_count: int = Field(default=1, alias="packCount")

    flavor: str | None = None

    seller: SellerSummary

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}



    @field_validator("id", mode="before")

    @classmethod

    def coerce_id(cls, value: UUID | str) -> str:

        return str(value)



    @field_validator("unit_amount", mode="before")

    @classmethod

    def coerce_unit_amount(cls, value: Decimal | float | int | None) -> float | None:

        if value is None:

            return None

        return float(value)





class ProductListResponse(BaseModel):

    items: list[ProductResponse]

    total: int



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class SellerProductCounts(BaseModel):
    all: int
    published: int
    pending: int
    sold_out: int = Field(alias="soldOut")
    hidden: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class SellerProductListResponse(BaseModel):
    items: list[ProductResponse]
    total: int
    counts: SellerProductCounts

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


