from datetime import datetime

from typing import Literal



from pydantic import BaseModel, Field



from app.schemas.seller import FulfillmentStatus, SellerType



OrderStatus = Literal["pending", "paid", "cancelled"]





class OrderItemResponse(BaseModel):

    id: str

    product_id: str = Field(alias="productId")

    product_title: str = Field(alias="productTitle")

    seller_id: str = Field(alias="sellerId")

    shop_name: str = Field(alias="shopName")

    seller_type: SellerType = Field(alias="sellerType")

    qty: int

    unit_price_credits: int = Field(alias="unitPriceCredits")

    line_total_credits: int = Field(alias="lineTotalCredits")

    fulfillment_status: FulfillmentStatus = Field(alias="fulfillmentStatus")



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class OrderResponse(BaseModel):

    id: str

    status: OrderStatus

    total_credits: int = Field(alias="totalCredits")

    items: list[OrderItemResponse]

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class OrderListResponse(BaseModel):

    items: list[OrderResponse]

    total: int



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





class CheckoutResponse(BaseModel):

    order: OrderResponse



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


