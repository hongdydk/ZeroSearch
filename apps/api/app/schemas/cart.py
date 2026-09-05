from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.seller import SellerType


class CartItemResponse(BaseModel):
    id: str
    product_id: str = Field(alias="productId")
    qty: int
    product_title: str = Field(alias="productTitle")
    seller_id: str = Field(alias="sellerId")
    shop_name: str = Field(alias="shopName")
    seller_type: SellerType = Field(alias="sellerType")
    price_credits: int = Field(alias="priceCredits")
    line_total_credits: int = Field(alias="lineTotalCredits")
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class CartResponse(BaseModel):
    items: list[CartItemResponse]
    total_credits: int = Field(alias="totalCredits")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class CartAddRequest(BaseModel):
    product_id: UUID = Field(alias="productId")
    qty: int = Field(default=1, ge=1, le=99)

    model_config = {"populate_by_name": True}


class CartUpdateRequest(BaseModel):
    product_id: UUID = Field(alias="productId")
    qty: int = Field(ge=0, le=99)

    model_config = {"populate_by_name": True}


class CartRemoveRequest(BaseModel):
    product_id: UUID = Field(alias="productId")

    model_config = {"populate_by_name": True}
