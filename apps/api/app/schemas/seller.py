from datetime import datetime

from typing import Literal



from pydantic import BaseModel, Field, field_validator

from uuid import UUID





SellerStatus = Literal["pending", "active", "suspended"]

SellerType = Literal["platform", "merchant"]

ProductStatus = Literal["draft", "published", "archived"]

FulfillmentStatus = Literal["paid", "preparing", "shipped", "delivered"]





class SellerSummary(BaseModel):

    id: str

    shop_name: str = Field(alias="shopName")

    seller_type: SellerType = Field(alias="sellerType")



    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}



    @field_validator("id", mode="before")

    @classmethod

    def coerce_id(cls, value: UUID | str) -> str:

        return str(value)





class SellerResponse(BaseModel):

    id: str

    shop_name: str = Field(alias="shopName")

    slug: str

    status: SellerStatus

    seller_type: SellerType = Field(alias="sellerType")

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}



    @field_validator("id", mode="before")

    @classmethod

    def coerce_id(cls, value: UUID | str) -> str:

        return str(value)





class SellerApplyRequest(BaseModel):

    shop_name: str = Field(alias="shopName", min_length=2, max_length=100)



    model_config = {"populate_by_name": True}





class SellerProductCreateRequest(BaseModel):

    title: str = Field(min_length=1, max_length=200)

    description: str | None = None

    price_credits: int = Field(alias="priceCredits", gt=0)

    stock: int = Field(ge=0)

    category: str = Field(min_length=1, max_length=50)

    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)

    status: ProductStatus = "draft"



    model_config = {"populate_by_name": True}





class SellerProductUpdateRequest(BaseModel):

    title: str | None = Field(default=None, min_length=1, max_length=200)

    description: str | None = None

    price_credits: int | None = Field(default=None, alias="priceCredits", gt=0)

    stock: int | None = Field(default=None, ge=0)

    category: str | None = Field(default=None, min_length=1, max_length=50)

    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)

    status: ProductStatus | None = None



    model_config = {"populate_by_name": True}





class SellerOrderItemResponse(BaseModel):

    id: str

    order_id: str = Field(alias="orderId")

    product_id: str = Field(alias="productId")

    product_title: str = Field(alias="productTitle")

    qty: int

    unit_price_credits: int = Field(alias="unitPriceCredits")

    line_total_credits: int = Field(alias="lineTotalCredits")

    fulfillment_status: FulfillmentStatus = Field(alias="fulfillmentStatus")

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class SellerOrderItemListResponse(BaseModel):

    items: list[SellerOrderItemResponse]

    total: int



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class AdminOrderItemResponse(SellerOrderItemResponse):
    shop_name: str = Field(alias="shopName")
    seller_type: SellerType = Field(alias="sellerType")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminOrderItemListResponse(BaseModel):
    items: list[AdminOrderItemResponse]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class SellerOrderItemStatusUpdate(BaseModel):

    fulfillment_status: FulfillmentStatus = Field(alias="fulfillmentStatus")



    model_config = {"populate_by_name": True}





class AdminSellerItem(BaseModel):

    id: str

    user_id: str = Field(alias="userId")

    user_email: str = Field(alias="userEmail")

    shop_name: str = Field(alias="shopName")

    slug: str

    status: SellerStatus

    seller_type: SellerType = Field(alias="sellerType")

    created_at: datetime = Field(alias="createdAt")



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class AdminSellerListResponse(BaseModel):

    items: list[AdminSellerItem]

    total: int



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


