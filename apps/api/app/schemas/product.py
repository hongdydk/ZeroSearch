from datetime import datetime

from typing import Literal

from uuid import UUID



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

    seller: SellerSummary

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}



    @field_validator("id", mode="before")

    @classmethod

    def coerce_id(cls, value: UUID | str) -> str:

        return str(value)





class ProductListResponse(BaseModel):

    items: list[ProductResponse]

    total: int



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


