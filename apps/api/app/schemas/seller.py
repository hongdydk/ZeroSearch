from datetime import datetime

from typing import Literal



from pydantic import BaseModel, Field, field_validator

from uuid import UUID





SellerStatus = Literal["pending", "active", "suspended", "removed"]

SellerType = Literal["platform", "merchant"]

ProductStatus = Literal["draft", "published", "archived"]

SellerOfferFilter = Literal["all", "published", "pending", "sold_out", "hidden"]

SellerOfferSort = Literal["newest", "price", "stock"]

OfferUnit = Literal["ml", "L", "g", "kg", "팩"]

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
    store_description: str | None = Field(default=None, alias="storeDescription")
    store_logo_url: str | None = Field(default=None, alias="storeLogoUrl")
    store_banner_url: str | None = Field(default=None, alias="storeBannerUrl")

    created_at: datetime | None = Field(default=None, alias="createdAt")



    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}



    @field_validator("id", mode="before")

    @classmethod

    def coerce_id(cls, value: UUID | str) -> str:

        return str(value)





class SellerApplyRequest(BaseModel):

    shop_name: str = Field(alias="shopName", min_length=2, max_length=100)



    model_config = {"populate_by_name": True}


class SellerStorefrontUpdateRequest(BaseModel):
    store_description: str | None = Field(default=None, alias="storeDescription", max_length=500)
    store_logo_url: str | None = Field(default=None, alias="storeLogoUrl", max_length=500)
    store_banner_url: str | None = Field(default=None, alias="storeBannerUrl", max_length=500)

    model_config = {"populate_by_name": True}





class SellerProductCreateRequest(BaseModel):

    title: str = Field(min_length=1, max_length=200)

    description: str | None = None

    price_credits: int | None = Field(default=None, alias="priceCredits", ge=0)

    stock: int | None = Field(default=None, ge=0)

    category: str = Field(min_length=1, max_length=50)

    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)

    detail_image_urls: list[str] = Field(default_factory=list, alias="detailImageUrls", max_length=12)

    status: ProductStatus = "draft"

    catalog_product_id: str | None = Field(default=None, alias="catalogProductId")
    variant_id: UUID | None = Field(default=None, alias="variantId")

    option_label: str | None = Field(default=None, alias="optionLabel", max_length=100)

    volume_ml: int | None = Field(default=None, alias="volumeMl", gt=0)

    unit_amount: float | None = Field(default=None, alias="unitAmount", gt=0)

    unit: OfferUnit | None = None

    pack_count: int | None = Field(default=None, alias="packCount", ge=1)

    flavor: str | None = Field(default=None, max_length=50)



    model_config = {"populate_by_name": True}





class SellerProductUpdateRequest(BaseModel):

    title: str | None = Field(default=None, min_length=1, max_length=200)

    description: str | None = None

    price_credits: int | None = Field(default=None, alias="priceCredits", gt=0)

    stock: int | None = Field(default=None, ge=0)

    category: str | None = Field(default=None, min_length=1, max_length=50)

    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)

    detail_image_urls: list[str] | None = Field(default=None, alias="detailImageUrls", max_length=12)

    status: ProductStatus | None = None

    option_label: str | None = Field(default=None, alias="optionLabel", max_length=100)

    volume_ml: int | None = Field(default=None, alias="volumeMl", gt=0)

    unit_amount: float | None = Field(default=None, alias="unitAmount", gt=0)

    unit: OfferUnit | None = None

    pack_count: int | None = Field(default=None, alias="packCount", ge=1)

    flavor: str | None = Field(default=None, max_length=50)



    model_config = {"populate_by_name": True}


class SellerProductBulkRequest(BaseModel):
    ids: list[UUID] = Field(min_length=1, max_length=100)
    price_credits: int | None = Field(default=None, alias="priceCredits", gt=0)
    stock: int | None = Field(default=None, ge=0)
    status: ProductStatus | None = None

    model_config = {"populate_by_name": True}


class SellerImageUploadResponse(BaseModel):

    image_url: str = Field(alias="imageUrl")



    model_config = {"populate_by_name": True, "ser_json_by_alias": True}





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


class DailySalesItem(BaseModel):
    date: str
    line_count: int = Field(alias="lineCount")
    amount: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class SalesStatsResponse(BaseModel):
    paid_order_count: int = Field(alias="paidOrderCount")
    sales_line_count: int = Field(alias="salesLineCount")
    sold_item_count: int = Field(alias="soldItemCount")
    sold_qty_sum: int = Field(alias="soldQtySum")
    sold_amount_sum: int = Field(alias="soldAmountSum")
    daily_sales: list[DailySalesItem] = Field(alias="dailySales")
    fulfillment_counts: dict[str, int] = Field(alias="fulfillmentCounts")
    offer_counts: dict[str, int] = Field(alias="offerCounts")

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


