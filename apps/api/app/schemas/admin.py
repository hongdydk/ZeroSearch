from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.schemas.catalog_product import PriceUnit
from app.schemas.seller import DailySalesItem


class AdminStatsResponse(BaseModel):
    user_count: int = Field(alias="userCount")
    product_count: int = Field(alias="productCount")
    order_count: int = Field(alias="orderCount")
    seller_count: int = Field(alias="sellerCount")
    pending_seller_count: int = Field(alias="pendingSellerCount")
    sold_item_count: int = Field(alias="soldItemCount")
    sold_qty_sum: int = Field(alias="soldQtySum")
    sold_amount_sum: int = Field(alias="soldAmountSum")
    paid_order_count: int = Field(default=0, alias="paidOrderCount")
    sales_line_count: int = Field(default=0, alias="salesLineCount")
    daily_sales: list[DailySalesItem] = Field(default_factory=list, alias="dailySales")
    fulfillment_counts: dict[str, int] = Field(default_factory=dict, alias="fulfillmentCounts")
    offer_counts: dict[str, int] = Field(default_factory=dict, alias="offerCounts")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminUserItem(BaseModel):
    id: str
    email: str
    display_name: str | None = Field(default=None, alias="displayName")
    seller_name: str | None = Field(default=None, alias="sellerName")
    is_buyer: bool = Field(alias="isBuyer")
    is_seller: bool = Field(alias="isSeller")
    is_admin: bool = Field(alias="isAdmin")
    seller_status: str | None = Field(default=None, alias="sellerStatus")
    seller_type: str | None = Field(default=None, alias="sellerType")
    created_at: datetime = Field(alias="createdAt")

    model_config = {"populate_by_name": True, "from_attributes": True, "ser_json_by_alias": True}


class AdminUserUpdate(BaseModel):
    is_admin: bool | None = Field(default=None, alias="isAdmin")
    is_buyer: bool | None = Field(default=None, alias="isBuyer")
    is_seller: bool | None = Field(default=None, alias="isSeller")
    display_name: str | None = Field(default=None, alias="displayName", max_length=100)
    seller_name: str | None = Field(default=None, alias="sellerName", max_length=100)

    model_config = {"populate_by_name": True}


class AdminUserListResponse(BaseModel):
    items: list[AdminUserItem]
    total: int
    offset: int
    limit: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


DbResetMode = Literal["seed", "truncate_all", "truncate_except_users"]


class DbResetRequest(BaseModel):
    mode: DbResetMode = "seed"
    confirm: str

    model_config = {"populate_by_name": True}


class DbResetResponse(BaseModel):
    mode: DbResetMode
    message: str

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminCreditGrantRequest(BaseModel):
    amount: int = Field(gt=0)
    note: str | None = None

    model_config = {"populate_by_name": True}


class AdminCreditGrantResponse(BaseModel):
    user_id: str = Field(alias="userId")
    balance: int
    granted: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminSellerItem(BaseModel):
    id: str
    user_id: str = Field(alias="userId")
    user_email: str = Field(alias="userEmail")
    shop_name: str = Field(alias="shopName")
    slug: str
    status: str
    seller_type: str = Field(alias="sellerType")
    created_at: datetime = Field(alias="createdAt")
    warning_count: int = Field(default=0, alias="warningCount")
    last_moderation_action: str | None = Field(default=None, alias="lastModerationAction")
    last_moderation_reason: str | None = Field(default=None, alias="lastModerationReason")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminSellerListResponse(BaseModel):
    items: list[AdminSellerItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminSellerModerationRequest(BaseModel):
    reason: str = Field(min_length=1, max_length=1000)

    model_config = {"populate_by_name": True}

    @field_validator("reason")
    @classmethod
    def strip_reason(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError("사유를 입력하세요.")
        return text


class SellerModerationEventItem(BaseModel):
    id: str
    action: str
    reason: str
    created_at: datetime = Field(alias="createdAt")
    admin_email: str | None = Field(default=None, alias="adminEmail")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class SellerModerationEventListResponse(BaseModel):
    items: list[SellerModerationEventItem]
    total: int

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}


class AdminCatalogCreateRequest(BaseModel):
    manufacturer: str = Field(min_length=1, max_length=200)
    title: str = Field(min_length=1, max_length=200)
    category: str = Field(min_length=1, max_length=120)
    description: str | None = None
    image_url: str | None = Field(default=None, alias="imageUrl", max_length=500)
    price_unit: Literal["ml", "credits"] = Field(default="ml", alias="priceUnit")
    l1_tags: list[str] | None = Field(default=None, alias="l1Tags")
    storage: str | None = None
    volume_options: list[str] = Field(default_factory=list, alias="volumeOptions")

    model_config = {"populate_by_name": True}

    @field_validator("manufacturer", "title", "category")
    @classmethod
    def strip_required(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError("필수 값을 입력하세요.")
        return text


class AdminCatalogProductItem(BaseModel):
    id: str
    title: str
    manufacturer: str = ""
    category: str
    status: str
    offer_count: int = Field(alias="offerCount")
    published_offer_count: int = Field(alias="publishedOfferCount")
    shop_count: int = Field(default=0, alias="shopCount")
    median_unit_price: float | None = Field(default=None, alias="medianUnitPrice")
    median_price_credits: int | None = Field(default=None, alias="medianPriceCredits")
    price_unit: PriceUnit = Field(default="credits", alias="priceUnit")
    display_price_label: str = Field(default="원", alias="displayPriceLabel")
    image_url: str | None = Field(default=None, alias="imageUrl")
    l1_tags: list[str] = Field(default_factory=list, alias="l1Tags")
    created_at: datetime | None = Field(default=None, alias="createdAt")

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, value: UUID | str) -> str:
        return str(value)


class AdminCatalogProductListResponse(BaseModel):
    items: list[AdminCatalogProductItem]
    total: int
    offset: int = 0
    limit: int = 50

    model_config = {"populate_by_name": True, "ser_json_by_alias": True}
